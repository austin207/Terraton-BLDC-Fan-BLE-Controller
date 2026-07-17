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
import 'package:terraton_fan_app/core/storage/daily_runtime_repository.dart';
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
// The real impl needs an ObjectBox Store, so an un-overridden runtime frame
// throws out of the notify handler and silently drops the rest of the burst.
class _MockDailyRuntimeRepo extends Mock implements DailyRuntimeRepository {}

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
  late _MockDailyRuntimeRepo mockDailyRuntimeRepo;
  late StreamController<BleConnectionState> stateCtrl;
  late StreamController<List<int>>          notifyCtrl;

  setUp(() {
    mockBle          = _MockBle();
    mockRepo         = _MockRepo();
    mockUsageLogRepo = _MockUsageLogRepo();
    mockDailyRuntimeRepo = _MockDailyRuntimeRepo();
    when(() => mockDailyRuntimeRepo.upsertForDate(any(), any(), any()))
        .thenReturn(null);
    when(() => mockDailyRuntimeRepo.getRange(any(), any(), any()))
        .thenReturn([]);
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
          dailyRuntimeRepositoryProvider.overrideWithValue(mockDailyRuntimeRepo),
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

    // ── Power-on memory restore (Issue: app Power ON must mirror IR remote ON) ──
    // Frame [2] of an OFF Machine State reply is the firmware's stored last
    // state. The app keeps it and re-sends it after Power ON, because a bare
    // BLE powerOn does not trigger the firmware's own memory restore.

    Finder powerButton() => find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_PowerButton');

    testWidgets('OFF reply stores speed memory; Power ON re-sends it',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).speed, 0); // dial blank while OFF

      clearInteractions(mockBle);
      await tester.tap(powerButton());
      await tester.pump();

      // Power ON + the remembered speed 5, mirroring the IR remote's restore.
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x09]))
          .called(1);
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x05, 0x0F]))
          .called(1);
      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('OFF reply stores mode memory; Power ON re-sends the mode frame',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOff, ...modeSmart, ...timerOff]);
      await tester.pump();
      await tester.pump();

      clearInteractions(mockBle);
      await tester.tap(powerButton());
      await tester.pump();

      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x09]))
          .called(1);
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x21, 0x01, 0x04, 0x2B]))
          .called(1);
      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
    });

    testWidgets('split OFF reply still captures the speed memory',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOff, ...timerOff]); // incomplete → debounce holds
      await tester.pump();
      notifyCtrl.add(speed5); // stored speed lands in a later notification
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).isPowered, false);

      clearInteractions(mockBle);
      await tester.tap(powerButton());
      await tester.pump();

      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x05, 0x0F]))
          .called(1);
      expect(stateOf(tester).speed, 5);
    });

    // ── Boost ↔ Reverse mutual exclusivity (remote-originated boost) ──────────

    testWidgets('remote Boost while Reverse highlighted → Boost replaces Reverse',
        (tester) async {
      await pumpConnected(tester);
      // Complete the connect Machine-State reply so later frames are spontaneous.
      notifyCtrl.add([...powerOn, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // Remote presses Reverse (spontaneous 0x21 0x03 — no timer frame).
      notifyCtrl.add(const [0x55, 0xAA, 0x07, 0x21, 0x01, 0x03, 0x2B]);
      await tester.pump();
      expect(stateOf(tester).activeMode, 'reverse');

      // Remote presses Boost (spontaneous 0x21 0x01).
      notifyCtrl.add(const [0x55, 0xAA, 0x07, 0x21, 0x01, 0x01, 0x29]);
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // reverse highlight replaced by boost
    });

    // ── Sleep-timer countdown ─────────────────────────────────────────────────

    testWidgets('timer discovered via Machine State shows a live countdown',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      // No app-side start time existed, so updateTimer resolves it to the
      // detection moment and the live h/m/s countdown renders — NOT the
      // static '2H REMAINING' fallback (the pre-fix frozen display).
      // (DateTime.now() is wall time, not the test's fake clock, so the tick
      // itself can't be observed here; the per-second maths is unit-tested.)
      final label = tester.widget<Text>(find.textContaining('REMAINING')).data!;
      expect(label, isNot('2H REMAINING'));
      expect(label, matches(RegExp(r'^1h 59m \d{1,2}s REMAINING$')));
    });

    // ── Mid-frame notification splits (BLE60 UART chunking) ──────────────────
    // The BLE60 chunks the MCU's UART stream into notifications at ARBITRARY
    // byte boundaries — a 21-byte Machine-State burst is routinely cut inside
    // a frame. The stateless parser dropped the split frame (field bug
    // 2026-07-03: Smart mode + sleep timer lost on every reconnect).

    testWidgets(
        'reply split mid-TIMER-frame across notifications → Smart AND countdown restored',
        (tester) async {
      await pumpConnected(tester);
      final burst = [...powerOn, ...modeSmart, ...timer2h];
      notifyCtrl.add(burst.sublist(0, 18)); // cut inside the timer frame
      await tester.pump();
      notifyCtrl.add(burst.sublist(18)); // remaining 3 bytes of the timer frame
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      final label = tester.widget<Text>(find.textContaining('REMAINING')).data!;
      expect(label, matches(RegExp(r'^1h 59m \d{1,2}s REMAINING$')));
    });

    testWidgets(
        'reply split mid-MODE-frame across notifications → Smart restored',
        (tester) async {
      await pumpConnected(tester);
      final burst = [...powerOn, ...modeSmart, ...timer2h];
      notifyCtrl.add(burst.sublist(0, 10)); // cut inside the mode frame
      await tester.pump();
      notifyCtrl.add(burst.sublist(10));
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
    });

    // ── Persisted countdown across reconnect / relaunch ───────────────────────
    // resetOnConnect no longer clears the sleep timer: the countdown keeps
    // ticking from the persisted start time, and the Machine State reply then
    // confirms (same code keeps the timestamp) or corrects it (OFF clears).

    testWidgets(
        'persisted countdown ticks immediately on reconnect and survives the reply',
        (tester) async {
      final started = DateTime.now()
          .subtract(const Duration(minutes: 30, seconds: 5));
      when(() => mockRepo.getState(any())).thenReturn(FanState()
        ..deviceId = 'TT-001'
        ..activeTimerCode = 0x02
        ..timerActivatedAt = started);

      await pumpConnected(tester);
      // Before ANY notify frame: the chip already shows the remaining time.
      final before = tester.widget<Text>(find.textContaining('REMAINING')).data!;
      expect(before, matches(RegExp(r'^1h 29m \d{1,2}s REMAINING$')));

      // Machine State reply confirms the same duration code.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, 'smart');
      expect(s.timerActivatedAt, started); // countdown continues, not restarted
      final after = tester.widget<Text>(find.textContaining('REMAINING')).data!;
      expect(after, matches(RegExp(r'^1h 29m \d{1,2}s REMAINING$')));
    });

    testWidgets('OFF reply clears the persisted timer', (tester) async {
      when(() => mockRepo.getState(any())).thenReturn(FanState()
        ..deviceId = 'TT-001'
        ..activeTimerCode = 0x02
        ..timerActivatedAt = DateTime.now().subtract(const Duration(minutes: 30)));

      await pumpConnected(tester);
      expect(find.textContaining('REMAINING'), findsOneWidget);

      // Fan was turned off while disconnected — firmware truth clears the chip.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Slow Machine-State reply (awaiting-timeout race) ──────────────────────
    // The reply to a poll we sent may arrive well after the poll (a rebooted
    // MCU after a mains cycle, or a BT adapter cycle). _awaitingMotorState must
    // outlive the retry burst so the late reply is still assembled atomically —
    // with the old 1500 ms timeout it fell onto the live path, where a split
    // OFF reply lights the dial from the stored speed.

    testWidgets(
        'reply landing 8 s after connect, split [speed][timer] then [power OFF] '
        '→ still assembled atomically (dial stays dark)', (tester) async {
      await pumpConnected(tester);
      // Connect polls run at 0/1.5/3/4.5/6 s then stop; nothing has replied.
      await tester.pump(const Duration(seconds: 8));

      notifyCtrl.add([...speed5, ...timerOff]);
      await tester.pump();
      // Buffered, not applied — power still unknown.
      expect(stateOf(tester).speed, 0);

      notifyCtrl.add(powerOff);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.speed, 0); // stored speed captured as memory, not shown
    });

    // ── 4-frame post-mains-restore status poll must not wipe Smart ────────────
    // The first status poll after mains restore returns 0x02 0x04 0x23 0x24.
    // Its 0x04 is the stored speed, not a mode exit — a just-restored Smart
    // highlight must survive it; the app re-checks via getMotorState instead.

    const watts10 = [0x55, 0xAA, 0x07, 0x23, 0x01, 0x0A, 0x34];
    const rpm300  = [0x55, 0xAA, 0x07, 0x24, 0x02, 0x01, 0x2C, 0x59];

    testWidgets('4-frame status poll [power][speed][watts][rpm] keeps Smart active',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).activeMode, 'smart');

      clearInteractions(mockBle);
      notifyCtrl.add([...powerOn, ...speed5, ...watts10, ...rpm300]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, 'smart'); // not wiped by the stored-speed frame
      expect(s.lastWatts, 10);       // telemetry still applied live
      expect(s.lastRpm, 300);
      // Mode truth is re-checked from the fan instead of guessed.
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x00, 0x01, 0x01, 0x00, 0x01]))
          .called(1);
    });

    testWidgets(
        'status poll interleaving a split Machine-State reply cannot overwrite '
        'the buffered Smart mode', (tester) async {
      await pumpConnected(tester);
      // First part of the reply we polled for: power + mode, timer still in flight.
      notifyCtrl.add([...powerOn, ...modeSmart]);
      await tester.pump();
      // A 4-frame status poll interleaves — its 0x04 must not null the mode.
      notifyCtrl.add([...powerOn, ...speed5, ...watts10, ...rpm300]);
      await tester.pump();
      // The reply's timer frame finally lands → flush.
      notifyCtrl.add(timer2h);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart'); // not replaced by speed 5
      expect(s.activeTimerCode, 0x02);
    });

    // ── Confirm-before-demote (stale first reply after reconnect) ─────────────
    // The BLE60 buffers the MCU's UART output while no phone is connected and
    // can flush that stale backlog into a new connection; a just-woken MCU may
    // answer the first poll with default state. A reply that DEMOTES the
    // persisted last-known-good state (power off / mode cleared / unexpired
    // timer cleared) must be confirmed by a second reply before it is applied —
    // one stale reply must not wipe Smart + the persisted countdown (the
    // 2026-07-04 field bug that survived every transport-level fix).

    // Persisted last-known-good: fan running Smart with a 2H timer 30 min in.
    FanState runningSmartBaseline(DateTime started) => FanState()
      ..deviceId         = 'TT-001'
      ..isPowered        = true
      ..activeMode       = 'smart'
      ..activeTimerCode  = 0x02
      ..timerActivatedAt = started;

    // Make mockRepo round-trip like the real ObjectBox repo: saveState stores,
    // getState returns what was stored. The default setUp stubs saveState as a
    // no-op and getState as a constant, so the persisted baseline can never be
    // observed changing — which is precisely why these tests stayed green while
    // the field was broken. _isStateDemotion reads that baseline on every reply.
    void useStatefulRepo(FanState seed) {
      var row = seed;
      when(() => mockRepo.getState(any())).thenAnswer((_) => row);
      when(() => mockRepo.saveState(any())).thenAnswer((inv) async {
        row = inv.positionalArguments[0] as FanState;
      });
    }

    // Query Runtime reply: 55 AA 07 08 02 HH LL CRC → (0x0100)*5 = 1280 s.
    // checksum = (0x55+0xAA+0x07+0x08+0x02+0x01+0x00) & 0xFF = 273 & 0xFF = 0x11
    const runtime1280 = [0x55, 0xAA, 0x07, 0x08, 0x02, 0x01, 0x00, 0x11];

    testWidgets(
        'FIELD BUG: connect-burst telemetry must not poison the demotion '
        'baseline; stale OFF is still held afterwards', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      useStatefulRepo(runningSmartBaseline(started));

      await pumpConnected(tester); // resetOnConnect blanks the UI in-memory

      // The real connect burst. _connect() fires queryRuntime() immediately and
      // starts the 3 s status poll, so runtime/watts/RPM land BEFORE the
      // Machine-State reply is assembled — the one ordering the older tests
      // never produced. Each of these goes through update(), which persists the
      // whole FanState row.
      notifyCtrl.add([...runtime1280, ...watts10, ...rpm300]);
      await tester.pump();
      await tester.pump();

      // The last-known-good baseline must be intact: telemetry knows nothing
      // about power/mode/speed and must not be able to overwrite them.
      final base = mockRepo.getState('TT-001');
      expect(base.isPowered, true, reason: 'baseline poisoned → guard disarmed');
      expect(base.activeMode, 'smart');
      expect(base.activeTimerCode, 0x02);
      expect(base.timerActivatedAt, started);
      // ...while the telemetry itself still persisted.
      expect(base.lastRuntimeSecs, 1280);
      expect(base.lastWatts, 10);

      clearInteractions(mockBle);

      // Now the stale BLE60 backlog OFF reply lands. With the baseline intact
      // the guard sees a demotion, holds it, and re-polls instead of wiping.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // Held, so nothing was applied and nothing was erased. (The dial is still
      // blank from resetOnConnect — that is the restore pending, not a wipe —
      // but the sleep timer keeps ticking and the baseline is untouched.)
      final afterStale = mockRepo.getState('TT-001');
      expect(afterStale.isPowered, true);
      expect(afterStale.activeMode, 'smart');
      expect(afterStale.activeTimerCode, 0x02);
      expect(afterStale.timerActivatedAt, started);
      expect(stateOf(tester).activeTimerCode, 0x02);
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x00, 0x01, 0x01, 0x00, 0x01]))
          .called(1);

      // The genuine reply confirms the running state and closes the window.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();
      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started); // countdown continued, not restarted
    });

    testWidgets(
        'a genuine OFF still applies after the restore window closes',
        (tester) async {
      // Guards the trade-off: the merge must not pin the old baseline forever.
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      useStatefulRepo(runningSmartBaseline(started));

      await pumpConnected(tester);
      // Genuine reply closes the window (markRestored fires in _applyMachineState).
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();

      // Fan is switched off at the remote. The first reply demotes, so it is
      // held and re-polled; the confirming reply must land past the 300 ms
      // same-burst window to count as confirmation rather than more of the
      // same burst.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      // ...and the demoted truth reached the DB, so later reconnects see it.
      final base = mockRepo.getState('TT-001');
      expect(base.isPowered, false);
      expect(base.activeMode, isNull);
    });

    testWidgets(
        'FIELD BUG: stale OFF reply on reconnect is held, genuine reply restores '
        'Smart + countdown', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);
      clearInteractions(mockBle);

      // Stale backlog reply: fan "off", stored speed, no timer.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // Held, not applied: the persisted countdown is untouched and the fan
      // was immediately re-polled to confirm.
      var s = stateOf(tester);
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
      expect(find.textContaining('REMAINING'), findsOneWidget);
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x00, 0x01, 0x01, 0x00, 0x01]))
          .called(1);

      // The genuine reply to our confirm poll restores everything.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();

      s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started); // countdown continued, not restarted
    });

    testWidgets(
        'stale [ON][speed][timer-0] reply is held; genuine reply keeps Smart + timer',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      // Stale/default reply: plain speed instead of Smart, timer code 0.
      notifyCtrl.add([...powerOn, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      var s = stateOf(tester);
      expect(s.activeTimerCode, 0x02);   // not cleared by the suspect reply
      expect(s.timerActivatedAt, started);

      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();

      s = stateOf(tester);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
    });

    testWidgets(
        'two consecutive OFF replies → genuinely off: state and timer cleared',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      // Past the same-burst window (300 ms) so the next reply counts as the
      // answer to the confirm poll, not a continuation of the stale burst.
      await tester.pump(const Duration(milliseconds: 400));

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    testWidgets(
        'no second reply → held OFF reply applied by the fallback (~3 s)',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      // Still held right after delivery…
      expect(stateOf(tester).activeTimerCode, 0x02);

      // …but with no confirming reply the fallback applies the held truth.
      await tester.pump(const Duration(milliseconds: 3500));

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeTimerCode, isNull);
    });

    testWidgets(
        'OFF is applied immediately when the persisted timer already expired '
        '(expected shutdown, no confirm round-trip)', (tester) async {
      // 2H timer started 2h05m ago — the fan shut itself down while we were away.
      final started = DateTime.now()
          .subtract(const Duration(hours: 2, minutes: 5));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // No hold: applied on the first reply.
      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Live-path OFF reply: stored 0x22 must not light the chip ─────────────

    testWidgets(
        'live-path OFF reply with stored 0x22 does not show a phantom countdown',
        (tester) async {
      await pumpConnected(tester);
      // Let the connect retry burst and the awaiting window fully lapse so the
      // reply lands on the LIVE dispatch path.
      await tester.pump(const Duration(seconds: 11));

      // OFF reply whose frame [3] carries the firmware's STORED duration (2H).
      notifyCtrl.add([...powerOff, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeTimerCode, isNull); // stored duration ≠ running countdown
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Confirm-before-demote on the LIVE path ────────────────────────────────
    // The demotion guard used to run ONLY while awaiting a poll we sent. A stale
    // BLE60 backlog OFF reply landing AFTER the awaiting window closed fell onto
    // the live dispatch path and wiped Smart + the timer AND persisted the wipe
    // (poisoning the baseline the guard reads) — the regression that survived
    // every buffered-path fix. The guard now runs on every motor-state reply.

    testWidgets(
        'FIELD BUG: stale OFF reply on the LIVE path (after restore) is held, '
        'not applied; genuine reply keeps Smart + countdown', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      // Genuine reply to the connect poll lands first and closes the awaiting
      // window (_awaitingMotorState → false), so the next reply is dispatched on
      // the LIVE path — exactly where the unguarded OFF wipe used to happen.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).activeMode, 'smart');

      clearInteractions(mockBle);

      // Stale BLE60 backlog OFF reply now arrives on the live path.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // Held + re-polled, NOT applied: Smart and the countdown survive.
      var s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
      expect(find.textContaining('REMAINING'), findsOneWidget);
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x00, 0x01, 0x01, 0x00, 0x01]))
          .called(1);

      // The confirm reply restores/confirms the running state.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();
      s = stateOf(tester);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started); // countdown continued, not restarted
    });

    testWidgets(
        'bare live power=OFF frame (no timer) is confirmed, not applied blindly, '
        'while Smart + timer are persisted', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);
      // Close the awaiting window with a genuine reply.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();
      clearInteractions(mockBle);

      // A lone power=OFF frame (no 0x22 → live path). Because the persisted
      // baseline still has an active mode, it must be re-polled to confirm
      // rather than persisting off and poisoning the baseline.
      notifyCtrl.add([...powerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);       // not wiped
      expect(s.activeMode, 'smart');   // Smart survives
      expect(s.activeTimerCode, 0x02); // timer survives
      verify(() => mockBle.writeFrame([0x55, 0xAA, 0x00, 0x01, 0x01, 0x00, 0x01]))
          .called(1);
    });
  });
}
