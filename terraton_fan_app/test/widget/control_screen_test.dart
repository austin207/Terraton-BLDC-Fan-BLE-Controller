// test/widget/control_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/control/lighting_control_widget.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

class _MockBle            extends Mock implements BleService {}
class _MockRepo           extends Mock implements FanRepository {}
class _MockUsageLogRepo   extends Mock implements UsageLogRepository {}

FanDevice _testFan() => FanDevice()
  ..deviceId   = 'TT-001'
  ..macAddress = 'AA:BB:CC:DD:EE:FF'
  ..nickname   = 'Bedroom Fan'
  ..model      = 'Terraton X1'
  ..fwVersion  = '1.0'
  ..addedAt    = DateTime(2026, 1, 1);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    await ApplianceLoader.load();
    registerFallbackValue(<int>[]);
    registerFallbackValue(FanState());
    registerFallbackValue(UsageLog(
      deviceId: '', startTime: DateTime(0), durationSecs: 0, gear: 0, watts: 0,
    ));
  });

  late _MockBle          mockBle;
  late _MockRepo         mockRepo;
  late _MockUsageLogRepo mockUsageLogRepo;
  late StreamController<BleConnectionState> stateCtrl;
  late StreamController<List<int>>          notifyCtrl;

  setUp(() {
    mockBle          = _MockBle();
    mockRepo         = _MockRepo();
    mockUsageLogRepo = _MockUsageLogRepo();
    stateCtrl  = StreamController<BleConnectionState>.broadcast();
    notifyCtrl = StreamController<List<int>>.broadcast();

    when(() => mockUsageLogRepo.addLog(any())).thenReturn(null);
    when(() => mockUsageLogRepo.getLogsInRange(any(), any())).thenReturn([]);
    when(() => mockUsageLogRepo.getLogsForDevice(any(), any(), any())).thenReturn([]);
    when(() => mockUsageLogRepo.allDeviceIds()).thenReturn([]);
    when(() => mockUsageLogRepo.pruneBefore(any())).thenReturn(null);

    when(() => mockBle.connectionStateStream)
        .thenAnswer((_) => stateCtrl.stream);
    when(() => mockBle.notifyStream)
        .thenAnswer((_) => notifyCtrl.stream);
    when(() => mockBle.currentState)
        .thenReturn(BleConnectionState.disconnected);
    when(() => mockBle.scanResultsStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockBle.startScan(timeoutSeconds: any(named: 'timeoutSeconds')))
        .thenAnswer((_) async {});
    when(() => mockBle.connect(any()))
        .thenAnswer((_) async => 'AA:BB:CC:DD:EE:FF');
    when(() => mockBle.disconnect())
        .thenAnswer((_) async {});
    when(() => mockBle.writeFrame(any()))
        .thenAnswer((_) async {});
    when(() => mockBle.writeCharStatus).thenReturn('pending');
    when(() => mockBle.connectStatus).thenReturn('idle');

    when(() => mockRepo.getState(any()))
        .thenReturn(FanState()..deviceId = 'TT-001');
    when(() => mockRepo.getAllFans()).thenReturn([]);
    when(() => mockRepo.saveState(any())).thenAnswer((_) async {});
    when(() => mockRepo.saveOpenSegment(
          any(),
          start: any(named: 'start'),
          gear: any(named: 'gear'),
          mode: any(named: 'mode'),
          smartBaselineGear: any(named: 'smartBaselineGear'),
          wattsSum: any(named: 'wattsSum'),
          wattsCount: any(named: 'wattsCount'),
          rpmSum: any(named: 'rpmSum'),
          rpmCount: any(named: 'rpmCount'),
        )).thenAnswer((_) async {});
    when(() => mockRepo.updateMac(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await stateCtrl.close();
    await notifyCtrl.close();
  });

  Widget buildScreen() => ProviderScope(
        overrides: [
          bleServiceProvider.overrideWithValue(mockBle),
          fanRepositoryProvider.overrideWithValue(mockRepo),
          usageLogRepositoryProvider.overrideWithValue(mockUsageLogRepo),
        ],
        child: MaterialApp(home: ControlScreen(fan: _testFan())),
      );

  // Pump the screen and emit a connected state.
  // Two extra pumps let stream delivery and StreamProvider rebuild complete.
  Future<void> pumpConnected(WidgetTester tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();       // fire addPostFrameCallback → _connect()
    await tester.pump();       // drain async microtasks from startScan/connect
    stateCtrl.add(BleConnectionState.connected);
    when(() => mockBle.currentState)
        .thenReturn(BleConnectionState.connected);
    await tester.pump();       // StreamProvider delivers event
    await tester.pump();       // widget rebuilds with enabled=true
  }

  // Pump connected AND simulate a power-on BLE notification so that
  // controlsEnabled = true (controls require isPowered as well as connected).
  // Power-on response frame: [55 AA 07 02 01 01 0B]
  //   checksum = (0x55+0xAA+0x07+0x02+0x01+0x01) & 0xFF = 266 & 0xFF = 0x0A
  Future<void> pumpPoweredOn(WidgetTester tester) async {
    await pumpConnected(tester);
    notifyCtrl.add(const [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A]);
    await tester.pump(); // notification delivered → updatePower(true)
    await tester.pump(); // widget rebuilds with controlsEnabled = true
  }

  // ── Helpers — invoke widget callbacks directly ─────────────────────────────
  // CircularSpeedDial: six GestureDetectors share the same pixel centre, so
  //   tester.tap() hits the overlaid Column instead of an arc segment.
  // Lighting / Boost: layout height exceeds the 600 px test viewport, placing
  //   widgets off-screen. For both cases the frame content (not gesture routing)
  //   is what the PRD requires us to test, so we invoke the callbacks directly.

  // ── Speed dial ─────────────────────────────────────────────────────────────

  group('speed dial', () {
    testWidgets('speed 1 sends correct frame', (tester) async {
      await pumpConnected(tester);

      tester
          .widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(1);
      await tester.pump();

      verify(
        () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x01, 0x0B]),
      ).called(1);
    });

    testWidgets('speed 3 sends correct frame', (tester) async {
      await pumpConnected(tester);

      tester
          .widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(3);
      await tester.pump();

      verify(
        () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x03, 0x0D]),
      ).called(1);
    });
  });

  // ── Boost ──────────────────────────────────────────────────────────────────

  testWidgets('boost sends correct frame', (tester) async {
    await pumpPoweredOn(tester); // controls require isPowered; use powered-on helper

    final dial = tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
    expect(dial.enabled, true, reason: 'dial must be enabled in connected state');

    final boostGesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('boost_button')),
    );
    expect(boostGesture.onTap, isNotNull,
        reason: 'BOOST button must be enabled when connected');
    boostGesture.onTap!();
    await tester.pump();

    verify(
      () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x21, 0x01, 0x01, 0x28]),
    ).called(1);
  });

  // ── Disabled state ─────────────────────────────────────────────────────────

  testWidgets('all controls disabled when disconnected — writeFrame never called',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(); // fire postFrameCallback
    await tester.pump(); // settle; state stream never emits connected

    final dial = tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
    expect(dial.enabled, false);

    final boostGesture = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('boost_button')),
    );
    expect(boostGesture.onTap, isNull);

    // _connect() already sent the post-connect Get Motor State sync frame;
    // clear it so this verifies no *control* frame was written.
    clearInteractions(mockBle);
    verifyNever(() => mockBle.writeFrame(any()));
  });

  // ── Lighting pending ───────────────────────────────────────────────────────

  testWidgets('light ON shows SnackBar and auto powers on the fan',
      (tester) async {
    await pumpConnected(tester);
    // _connect() already sent the post-connect Get Motor State sync frame;
    // clear it so this verifies only the frames written for the lighting tap.
    clearInteractions(mockBle);

    // LightingControlWidget may be scrolled off the 600 px test viewport.
    // Invoke onLightOn directly — the contract being tested is the frame
    // (null → SnackBar, no lighting writeFrame call), not the tap geometry.
    final lightWidget = tester.widget<LightingControlWidget>(
      find.byType(LightingControlWidget),
    );
    lightWidget.onLightOn();
    await tester.pump(); // show SnackBar

    expect(
      find.text('Lighting commands pending from Terraton'),
      findsOneWidget,
    );
    // The lighting frame itself is still pending (null → SnackBar only), but
    // since the fan was off, using any control auto powers it on first.
    verify(
      () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x09]),
    ).called(1);
  });

  // ── Machine State restore on reconnect (after mains power-cycle) ─────────────
  // After connecting, _scheduleConnectPolls() sends getMotorState and sets
  // _awaitingMotorState, so the reply is routed through the atomic assembler.
  // These tests emit the 3-frame reply in the delivery patterns a freshly-rebooted
  // MCU can produce and assert the dial restores Power + Speed/Mode + Timer,
  // independent of frame ordering or notification-splitting.
  //
  // Response frames (packet id 0x07):
  //   Power ON  : 55 AA 07 02 01 01 0A      Power OFF : 55 AA 07 02 01 00 09
  //   Speed 5   : 55 AA 07 04 01 05 10      Mode Smart: 55 AA 07 21 01 04 2C
  //   Timer OFF : 55 AA 07 22 01 00 29      Timer 2H  : 55 AA 07 22 01 02 2B
  group('machine state restore on reconnect', () {
    const powerOn  = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A];
    const powerOff = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x09];
    const speed5   = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x05, 0x10];
    const modeSmart= [0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C];
    const timerOff = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29];
    const timer2h  = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x02, 0x2B];

    FanState stateOf(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(ControlScreen)))
        .read(activeFanStateProvider('TT-001'));

    testWidgets('concatenated, in order [power][speed][timer] → power ON, speed 5',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
      expect(s.activeTimerCode, 0x02);
    });

    testWidgets('split across notifications [speed][timer] then [power] → speed 5 restored',
        (tester) async {
      await pumpConnected(tester);
      // The bug case: speed+timer arrive first, power in a later notification.
      notifyCtrl.add([...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();
      // Not applied yet — power unknown, so the assembler holds the buffer.
      expect(stateOf(tester).speed, 0);

      notifyCtrl.add(powerOn);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('reordered within one notification [speed][power][timer] → speed 5',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...speed5, ...powerOn, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('powered, no timer frame → restored via debounce', (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...speed5]); // no timer → not immediately complete
      await tester.pump();
      // Debounce window (300 ms) fires the flush.
      await tester.pump(const Duration(milliseconds: 350));

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('mode reply [power][smart][timer] → power ON, activeMode smart',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...modeSmart, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.isBoost, false);
      expect(s.speed, 0); // a mode is frame [2], not a fixed speed
    });

    testWidgets('power OFF reply → fan off, dial blank (no stored speed shown)',
        (tester) async {
      await pumpConnected(tester);
      // Frame [2] carries the hardware's last stored speed even while OFF; it
      // must not light a dot.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.speed, 0);
    });
  });
}
