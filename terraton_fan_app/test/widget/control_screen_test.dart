// test/widget/control_screen_test.dart
import 'dart:async';
import 'dart:io' show sleep;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/ble/ble_frame_builder.dart';
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
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';
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
    when(() => mockRepo.saveOperatingState(any(),
          isPowered: any(named: 'isPowered'),
          isBoost: any(named: 'isBoost'),
          speed: any(named: 'speed'),
          activeMode: any(named: 'activeMode'),
        )).thenAnswer((_) async {});
    when(() => mockRepo.saveTimerState(any(),
          activeTimerCode: any(named: 'activeTimerCode'),
          timerActivatedAt: any(named: 'timerActivatedAt'),
        )).thenAnswer((_) async {});
    when(() => mockRepo.saveTelemetry(any(),
          lastWatts: any(named: 'lastWatts'),
          lastRpm: any(named: 'lastRpm'),
          lastRuntimeSecs: any(named: 'lastRuntimeSecs'),
        )).thenAnswer((_) async {});
    when(() => mockRepo.saveLighting(any(),
          colorType: any(named: 'colorType'),
          brightness: any(named: 'brightness'),
          isOn: any(named: 'isOn'),
        )).thenAnswer((_) async {});
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

  // Pump connected AND deliver a CONFIRMED powered-on Machine-State reply so
  // controlsEnabled = true (controls require isPowered as well as connected).
  // The sync engine applies state only when two consecutively assembled
  // replies agree across a query boundary, so the helper emits the full reply
  // {ON, speed 3, timer OFF}, lets the engine's confirm poll go out, and
  // emits it again. (A bare power-ON frame is correctly discarded now — an
  // MCU still booting answers exactly that way.)
  const msReplyOn3 = [
    0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A, // power ON
    0x55, 0xAA, 0x07, 0x04, 0x01, 0x03, 0x0E, // speed 3
    0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29, // timer OFF
  ];
  Future<void> pumpPoweredOn(WidgetTester tester) async {
    await pumpConnected(tester);
    notifyCtrl.add(msReplyOn3);
    await tester.pump(); // delivered → candidate + accelerated confirm poll
    notifyCtrl.add(msReplyOn3);
    await tester.pump(); // delivered → agreement → applied
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
  // _connect() starts a MachineStateSync session: getMotorState polls retry
  // (alternating the lab and vendor checksum variants) and a state is applied
  // only when TWO consecutively assembled replies agree across a query
  // boundary — so a stale BLE60 backlog burst can never confirm itself, and a
  // reply that is never confirmed is never applied. These tests emit replies
  // in the delivery patterns a freshly-rebooted MCU can produce and assert
  // the dial restores Power + Speed/Mode + Timer.
  //
  // Response frames (packet id 0x07):
  //   Power ON  : 55 AA 07 02 01 01 0A      Power OFF : 55 AA 07 02 01 00 09
  //   Speed 5   : 55 AA 07 04 01 05 10      Mode Smart: 55 AA 07 21 01 04 2C
  //   Timer OFF : 55 AA 07 22 01 00 29      Timer 2H  : 55 AA 07 22 01 02 2B
  group('machine state restore on reconnect', () {
    const powerOn  = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A];
    const powerOff = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x09];
    const speed5   = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x05, 0x10];
    const speed6   = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x06, 0x11];
    const modeBoost= [0x55, 0xAA, 0x07, 0x21, 0x01, 0x01, 0x29];
    const modeNature=[0x55, 0xAA, 0x07, 0x21, 0x01, 0x02, 0x2A];
    const modeSmart= [0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C];
    const timerOff = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29];
    const timer2h  = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x02, 0x2B];

    FanState stateOf(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(ControlScreen)))
        .read(activeFanStateProvider('TT-001'));

    // Emits [reply] twice with a pump in between: the first delivery becomes
    // the session candidate and triggers the engine's accelerated confirm
    // poll; the second (now past a query boundary) agrees → applied.
    Future<void> emitConfirmed(WidgetTester tester, List<int> reply) async {
      notifyCtrl.add(reply);
      await tester.pump();
      notifyCtrl.add(reply);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('confirmed reply [power][speed][timer] → power ON, speed 5; '
        'a single reply alone is only a candidate', (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      // First reply after connect is never applied alone (anti-backlog rule).
      expect(stateOf(tester).isPowered, false);

      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
      expect(s.activeTimerCode, 0x02);
    });

    testWidgets('reply split at a frame boundary [power] then [speed][timer] '
        '→ assembled, then confirmed', (tester) async {
      await pumpConnected(tester);
      // The BLE60 preserves UART order but cuts anywhere: power first, the
      // rest in a later notification.
      notifyCtrl.add(powerOn);
      await tester.pump();
      expect(stateOf(tester).speed, 0); // incomplete — nothing applied
      notifyCtrl.add([...speed5, ...timerOff]);
      await tester.pump();
      // Assembled into ONE candidate; still unapplied until confirmed.
      expect(stateOf(tester).speed, 0);

      await emitConfirmed(tester, [...powerOn, ...speed5, ...timerOff]);

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('reordered within one notification [speed][power][timer] → speed 5',
        (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...speed5, ...powerOn, ...timerOff]);
      await tester.pump();
      notifyCtrl.add([...speed5, ...powerOn, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('powered, no timer frame (vendor-doc reply shape) → restored '
        'via debounce; timer untouched', (tester) async {
      await pumpConnected(tester);
      // Newer firmware per the vendor doc reports no timer field at all.
      notifyCtrl.add([...powerOn, ...speed5]);
      await tester.pump(const Duration(milliseconds: 350)); // debounce → candidate
      notifyCtrl.add([...powerOn, ...speed5]);
      await tester.pump(const Duration(milliseconds: 350)); // debounce → agreement
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
    });

    testWidgets('mode reply [power][smart][timer] → power ON, activeMode smart',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);

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
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);

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
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);
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
      await emitConfirmed(tester, [...powerOff, ...modeSmart, ...timerOff]);

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
      // Assembled into one candidate; the confirming reply applies it.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
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
      // Complete the connect sync (confirmed) so later frames are spontaneous
      // live-path traffic.
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timerOff]);

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
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer2h]);

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
      notifyCtrl.add(burst); // confirming reply → agreement → applied
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
      notifyCtrl.add(burst); // confirming reply
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

      // Machine State reply (confirmed) reports the same duration code.
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);

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

      // Fan was turned off while disconnected — confirmed firmware truth
      // clears the chip.
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);

      expect(stateOf(tester).activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Slow Machine-State reply (booting MCU / BT adapter cycle) ────────────
    // The reply may arrive well after the session's poll retries stopped. The
    // session stays open for late replies until its 12 s timeout, and the 3 s
    // status poll keeps advancing the query sequence, so a late reply can
    // still be confirmed.

    testWidgets(
        'reply landing 8 s after connect, split [power OFF][speed] then [timer] '
        '→ assembled, confirmed via the status-poll query boundary', (tester) async {
      await pumpConnected(tester);
      // Session polls run at 0/1.5/…/7.5 s (cap 6); nothing has replied yet.
      await tester.pump(const Duration(seconds: 8));

      notifyCtrl.add([...powerOff, ...speed5]);
      await tester.pump();
      notifyCtrl.add(timerOff);
      await tester.pump();
      // One assembled candidate — never applied alone.
      expect(stateOf(tester).speed, 0);

      // The 3 s status poll advances the query sequence; the identical late
      // reply then confirms the candidate.
      await tester.pump(const Duration(seconds: 3));
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
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
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);
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
        'the assembling Smart mode', (tester) async {
      await pumpConnected(tester);
      // First part of the reply we polled for: power + mode, timer still in flight.
      notifyCtrl.add([...powerOn, ...modeSmart]);
      await tester.pump();
      // A 4-frame status poll interleaves — its 0x04 must not tear the
      // partial or null the mode.
      notifyCtrl.add([...powerOn, ...speed5, ...watts10, ...rpm300]);
      await tester.pump();
      // The reply's timer frame finally lands → candidate {ON, smart, 2H}.
      notifyCtrl.add(timer2h);
      await tester.pump();
      // The confirming reply applies it.
      notifyCtrl.add([...powerOn, ...modeSmart, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart'); // not replaced by speed 5
      expect(s.activeTimerCode, 0x02);
    });

    // ── Anti-backlog agreement (stale first reply after reconnect) ────────────
    // The BLE60 buffers the MCU's UART output while no phone is connected and
    // flushes that stale backlog into a new connection; a just-woken MCU may
    // answer the first poll with default state. The sync session therefore
    // applies a state only when two consecutively assembled replies agree
    // across a query boundary — replies are judged against EACH OTHER, never
    // against the persisted row, so no damaged baseline can silently disarm
    // the protection (the failure mode that survived six fixes). And a reply
    // that is never confirmed is never applied: no timeout promotes a lone
    // stale OFF to truth.

    // Persisted last-known-good: fan running Smart with a 2H timer 30 min in.
    FanState runningSmartBaseline(DateTime started) => FanState()
      ..deviceId         = 'TT-001'
      ..isPowered        = true
      ..activeMode       = 'smart'
      ..activeTimerCode  = 0x02
      ..timerActivatedAt = started;

    // Make mockRepo round-trip like the real ObjectBox repo, per field group:
    // the scoped writers mutate only their own fields on the stored row and
    // getState returns that row. The default setUp stubs persist as no-ops and
    // getState as a constant, so the persisted row could never be observed
    // changing — which is precisely why the pre-rewrite tests stayed green
    // while the field was broken.
    void useStatefulRepo(FanState seed) {
      var row = seed;
      when(() => mockRepo.getState(any())).thenAnswer((_) => row);
      when(() => mockRepo.saveState(any())).thenAnswer((inv) async {
        row = inv.positionalArguments[0] as FanState;
      });
      when(() => mockRepo.saveOperatingState(any(),
            isPowered: any(named: 'isPowered'),
            isBoost: any(named: 'isBoost'),
            speed: any(named: 'speed'),
            activeMode: any(named: 'activeMode'),
          )).thenAnswer((inv) async {
        row = row.copyWith(
          isPowered:  inv.namedArguments[#isPowered] as bool,
          isBoost:    inv.namedArguments[#isBoost] as bool,
          speed:      inv.namedArguments[#speed] as int,
          activeMode: () => inv.namedArguments[#activeMode] as String?,
        );
      });
      when(() => mockRepo.saveTimerState(any(),
            activeTimerCode: any(named: 'activeTimerCode'),
            timerActivatedAt: any(named: 'timerActivatedAt'),
          )).thenAnswer((inv) async {
        row = row.copyWith(
          activeTimerCode:  () => inv.namedArguments[#activeTimerCode] as int?,
          timerActivatedAt: () => inv.namedArguments[#timerActivatedAt] as DateTime?,
        );
      });
      when(() => mockRepo.saveTelemetry(any(),
            lastWatts: any(named: 'lastWatts'),
            lastRpm: any(named: 'lastRpm'),
            lastRuntimeSecs: any(named: 'lastRuntimeSecs'),
          )).thenAnswer((inv) async {
        row = row.copyWith(
          lastWatts:       () => inv.namedArguments[#lastWatts] as int?,
          lastRpm:         () => inv.namedArguments[#lastRpm] as int?,
          lastRuntimeSecs: () => inv.namedArguments[#lastRuntimeSecs] as int?,
        );
      });
    }

    // Query Runtime reply: 55 AA 07 08 02 HH LL CRC → (0x0100)*5 = 1280 s.
    // checksum = (0x55+0xAA+0x07+0x08+0x02+0x01+0x00) & 0xFF = 273 & 0xFF = 0x11
    const runtime1280 = [0x55, 0xAA, 0x07, 0x08, 0x02, 0x01, 0x00, 0x11];

    testWidgets(
        'FIELD BUG: connect-burst telemetry cannot poison the persisted row; '
        'a lone stale OFF is never applied', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      useStatefulRepo(runningSmartBaseline(started));

      await pumpConnected(tester); // resetOnConnect blanks the UI in-memory

      // The real connect burst. _connect() fires queryRuntime() immediately and
      // starts the 3 s status poll, so runtime/watts/RPM land BEFORE any
      // Machine-State reply — the ordering that poisoned the whole-row persist.
      // Scoped persistence makes the poisoning structurally impossible.
      notifyCtrl.add([...runtime1280, ...watts10, ...rpm300]);
      await tester.pump();
      await tester.pump();

      final base = mockRepo.getState('TT-001');
      expect(base.isPowered, true, reason: 'operating row must be untouchable by telemetry');
      expect(base.activeMode, 'smart');
      expect(base.activeTimerCode, 0x02);
      expect(base.timerActivatedAt, started);
      // ...while the telemetry itself still persisted.
      expect(base.lastRuntimeSecs, 1280);
      expect(base.lastWatts, 10);

      // Now the stale BLE60 backlog OFF reply lands. It becomes a session
      // candidate — never applied alone, no matter what any baseline says.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final afterStale = mockRepo.getState('TT-001');
      expect(afterStale.isPowered, true);
      expect(afterStale.activeMode, 'smart');
      expect(afterStale.activeTimerCode, 0x02);
      expect(afterStale.timerActivatedAt, started);
      expect(stateOf(tester).activeTimerCode, 0x02); // countdown still ticking

      // The genuine state contradicts the stale candidate, then confirms.
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);
      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started); // countdown continued, not restarted
    });

    testWidgets(
        'a genuine remote OFF applies instantly on the live path once the '
        'session is over', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      useStatefulRepo(runningSmartBaseline(started));

      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);
      expect(stateOf(tester).activeMode, 'smart');

      // Fan is switched off at the remote. The session is over, so the full
      // OFF reply dispatches live and applies at once — steady state has no
      // backlog, and remote OFF must feel instant.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      // ...and the truth reached the DB, so later reconnects see it.
      final base = mockRepo.getState('TT-001');
      expect(base.isPowered, false);
      expect(base.activeMode, isNull);
    });

    testWidgets(
        'FIELD BUG: stale OFF reply on reconnect is only a candidate; genuine '
        'replies restore Smart + countdown', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      // Stale backlog reply: fan "off", stored speed, no timer.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      // Candidate only, not applied: the persisted countdown is untouched.
      var s = stateOf(tester);
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
      expect(find.textContaining('REMAINING'), findsOneWidget);

      // The genuine state contradicts the candidate, then confirms itself.
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);

      s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started); // countdown continued, not restarted
    });

    testWidgets(
        'stale [ON][speed][timer-0] reply is only a candidate; genuine replies '
        'keep Smart + timer', (tester) async {
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

      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);

      s = stateOf(tester);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
    });

    testWidgets(
        'two agreeing OFF replies → genuinely off: state and timer cleared',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    testWidgets(
        'no confirmation ever → NOTHING is applied: Smart + countdown survive '
        'the whole session (the old 3 s fallback wiped them here)',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      useStatefulRepo(runningSmartBaseline(started));

      await pumpConnected(tester);

      // A lone stale OFF reply, then silence: the fan never answers again.
      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      expect(stateOf(tester).activeTimerCode, 0x02);

      // Ride out the whole session (12 s timeout) plus slack. The old design's
      // 3 s fallback applied the held OFF here — converting "no confirmation"
      // into "wipe Smart + the timer". The rewrite refuses: an unconfirmed
      // reply is never promoted to truth.
      await tester.pump(const Duration(seconds: 14));

      final s = stateOf(tester);
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, started);
      expect(find.textContaining('REMAINING'), findsOneWidget);
      final base = mockRepo.getState('TT-001');
      expect(base.isPowered, true, reason: 'the stale OFF must never persist');
      expect(base.activeMode, 'smart');
      expect(base.activeTimerCode, 0x02);
    });

    testWidgets(
        'expired-timer OFF: confirmed like everything else, then clears the '
        'countdown', (tester) async {
      // 2H timer started 2h05m ago — the fan shut itself down while we were away.
      final started = DateTime.now()
          .subtract(const Duration(hours: 2, minutes: 5));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Live path after the session: full replies apply atomically ───────────

    testWidgets(
        'late full OFF reply after the session expired applies directly on the '
        'live path — stored 0x22 shows no phantom countdown', (tester) async {
      await pumpConnected(tester);
      // Let the session (12 s timeout) fully lapse with no reply at all.
      await tester.pump(const Duration(seconds: 13));

      // OFF reply whose frame [3] carries the firmware's STORED duration (2H).
      // On the live path a power+timer chunk is applied as one atomic reply,
      // so the stored speed cannot re-light the dial its own OFF just cleared.
      notifyCtrl.add([...powerOff, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.speed, 0);
      expect(s.activeTimerCode, isNull); // stored duration ≠ running countdown
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    testWidgets(
        'bare live power=OFF frame applies full OFF semantics in steady state',
        (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);
      expect(stateOf(tester).activeMode, 'smart');

      // A lone power=OFF frame (IR remote press). Steady state has no backlog,
      // so it applies at once — with full OFF semantics: no mode, no speed, no
      // countdown on an off fan.
      notifyCtrl.add([...powerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      expect(find.textContaining('REMAINING'), findsNothing);
    });

    // ── Frame [2] = speed is NOT proof no mode is active (field bug 2026-07-04) ──
    // Proof capture: test/unit/field_capture_2026_07_04_test.dart. Smart is
    // tapped at speed 5; the firmware raises the fan to speed 6 on its own
    // (Smart adjusting speed autonomously) and every subsequent state reply
    // reports frame [2] as "04 01 06" — never "21 01 04" — even though the
    // app never sends a speed command. The old code read that as "the
    // hardware exited the mode" and cleared it on every reconnect. A reply
    // carrying BOTH a power frame and a timer frame is applied atomically by
    // _dispatchLive's first branch straight into _applyMachineState, so a
    // single such chunk exercises the fixed code path directly — no session,
    // no agreement, no poll pumping required.

    testWidgets(
        'FIELD BUG 2026-07-04: mode-driven speed-6 reply must not clear Smart',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);
      expect(stateOf(tester).activeMode, 'smart');

      // Session is over; this full reply (power + timer both present)
      // dispatches on the live path and applies atomically.
      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, 'smart',
          reason: 'field report: "Smart is not retained after reconnecting" — '
              'the firmware reports speed (04 01 06), not mode (21 01 04), '
              'once Smart drives the fan to speed 6, and the app must not '
              'read that as a mode exit');
      expect(s.speed, 6);
    });

    testWidgets(
        'FIELD BUG 2026-07-04: mode-driven speed-6 reply must not clear Nature',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeNature, ...timerOff]);
      expect(stateOf(tester).activeMode, 'nature');

      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, 'nature',
          reason: 'field report: "Nature is restored but does not work at '
              'Speed 6" — the same speed-report-not-mode-exit mechanism as '
              'Smart, just for a different mode driven to speed 6');
      expect(s.speed, 6);
    });

    testWidgets(
        'FIELD BUG 2026-07-04: mode-driven speed-6 reply must not clear Boost',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeBoost, ...timerOff]);
      expect(stateOf(tester).isBoost, true);

      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isBoost, true,
          reason: 'field report: "Boost is restored but does not work at '
              'Speed 6" — Boost must survive a firmware speed-6 report the '
              'same way Smart and Nature do');
      expect(s.speed, 6);
    });

    testWidgets(
        'exclusivity is still intact: an explicit mode frame still switches '
        'away from Smart', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);
      expect(stateOf(tester).activeMode, 'smart');

      // A genuine mode change (0x21 reporting a DIFFERENT mode) must still
      // clear the old mode — the fix only stops a bare SPEED frame from
      // doing that, not an explicit mode frame.
      notifyCtrl.add([...powerOn, ...modeNature, ...timerOff]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeMode, 'nature',
          reason: 'an explicit 0x21 mode frame must still switch the active '
              'mode — the fix must not make activeMode sticky against real '
              'mode changes');
    });

    testWidgets(
        'power OFF reply still clears mode, boost, and speed',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);
      expect(stateOf(tester).activeMode, 'smart');

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false,
          reason: 'a trusted power==false must still clear mode/boost/speed '
              'even though a bare speed frame no longer clears the mode on '
              'its own');
      expect(s.activeMode, isNull);
      expect(s.isBoost, false);
      expect(s.speed, 0);
    });

    // ── State-reply 0x22 field is a bad timer reporter (field bug 2026-07-04) ──
    // Proof capture: test/unit/field_capture_2026_07_04_test.dart. The firmware
    // echoes/re-reports a set 4 h timer as active, yet every Get Motor State
    // reply carries 22 01 00 — an explicit zero, not a missing frame — and the
    // capture contains no timer-off command. machine_state_timer_policy.dart's
    // timerFromStateReply() treats that explicit 0 as neutral (like an absent
    // 0x22 frame already was) so it can no longer wipe the countdown.
    const timer4h = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x04, 0x2D];

    testWidgets(
        'FIELD BUG 2026-07-04: powered reply reporting timer 0 must not clear '
        'an active 4 h countdown', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer4h]);
      expect(stateOf(tester).activeTimerCode, 0x04);

      // Session is over; this full reply (power + timer both present)
      // dispatches on the live path and applies atomically straight into
      // _applyMachineState.
      notifyCtrl.add([...powerOn, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, 0x04,
          reason: 'field report: "The Timer does not display the remaining '
              'countdown after the app is sent to the background and '
              'reopened. Instead, it appears to have been reset or cleared, '
              'even if the timer is still active on the device" — this '
              "firmware's state-reply 0x22 field always reports 0 and must "
              'not be read as a cancellation');
    });

    testWidgets(
        'a genuine power-OFF reply still clears an active 4 h countdown',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer4h]);
      expect(stateOf(tester).activeTimerCode, 0x04);

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, isNull,
          reason: 'the timer-neutral-zero rule must not defeat the existing '
              'invariant that an OFF fan has no running countdown');
    });

    testWidgets(
        'a powered reply reporting a nonzero timer code still applies — a '
        'timer set from the IR remote must still be discovered', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer4h]);
      expect(stateOf(tester).activeTimerCode, 0x04);

      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, 0x02,
          reason: 'only an explicit reported 0 is neutral — a genuine '
              'nonzero code from firmware (e.g. the IR remote setting a new '
              'duration) must still update the countdown');
    });

    testWidgets(
        'a powered reply with no 0x22 frame at all remains neutral on the '
        'timer (pre-existing rule, unaffected by the zero-is-neutral fix)',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer4h]);
      expect(stateOf(tester).activeTimerCode, 0x04);

      notifyCtrl.add([...powerOn, ...speed5]); // no timer frame in this chunk
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, 0x04,
          reason: 'a reply carrying no 0x22 frame at all was already neutral '
              'before this fix and must remain so');
    });
  });

  // ── Field bug: fast app-switch leaves the app deaf ──────────────────────
  // Report: "The status polling function is not being called ... the app is
  // not receiving updated device status." Root cause: `resumed` decided
  // whether to reconnect by reading `_ble.currentState`, which still read
  // `connected` for as long as the `paused`-triggered disconnect (fired
  // fire-and-forget) had not yet landed. On a fast pause→resume, `resumed`
  // would see "connected", skip `_connect()` entirely, and then the
  // in-flight disconnect would complete anyway and tear down the notify
  // subscription — leaving the app believing it's connected while no polls
  // are sent and no notifications arrive.
  group('app lifecycle — fast pause/resume (field bug fix)', () {
    FanState stateOf(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(ControlScreen)))
        .read(activeFanStateProvider('TT-001'));

    const watts10 = [0x55, 0xAA, 0x07, 0x23, 0x01, 0x0A, 0x34];
    const rpm300  = [0x55, 0xAA, 0x07, 0x24, 0x02, 0x01, 0x2C, 0x59];

    testWidgets(
        'a fast pause then resume, with the pause disconnect still in '
        'flight, still reconnects and resumes telemetry + Machine-State '
        'polling once the disconnect lands', (tester) async {
      await pumpConnected(tester);

      // The exact race from the field report: the pause-triggered
      // disconnect has not completed, so a naive `currentState` read would
      // still say "connected" for the whole test.
      final disconnectCompleter = Completer<void>();
      when(() => mockBle.disconnect())
          .thenAnswer((_) => disconnectCompleter.future);
      when(() => mockBle.currentState)
          .thenReturn(BleConnectionState.connected);

      clearInteractions(mockBle);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      // Reason: resume must not decide anything while the pause disconnect
      // it triggered is still in flight — currentState alone (which this
      // test pins to "connected" throughout) must never be trusted for the
      // reconnect decision. (mocktail's `verify(...).called(0)` throws
      // unconditionally on zero matches, so a true "never called" check
      // must use `verifyNever`.)
      verifyNever(() => mockBle.connect(any()));

      // The pause disconnect finally lands.
      disconnectCompleter.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        verify(() => mockBle.connect(any())).callCount,
        1,
        reason: 'once the in-flight pause disconnect actually completes, '
            'the deferred resume must reconnect — this is the fix for the '
            'field report that a fast app-switch leaves the app deaf',
      );

      expect(
        verify(() => mockBle.writeFrame(BleFrameBuilder.getMotorState()))
            .callCount,
        greaterThanOrEqualTo(1),
        reason: 'the fresh connect() must start a new MachineStateSync '
            'session so the dial re-syncs after the reconnect',
      );

      // Advance past the 3 s telemetry tick to prove status polling itself
      // (the exact function the field report says stopped running) is alive
      // again.
      await tester.pump(const Duration(seconds: 3));
      expect(
        verify(() => mockBle.writeFrame(BleFrameBuilder.statusPoll()))
            .callCount,
        greaterThanOrEqualTo(1),
        reason: 'the 3 s status poll must be running again post-reconnect — '
            'this is precisely the field report: "the status polling '
            'function is not being called"',
      );
    });

    testWidgets(
        'a second pause superseding an in-flight resume leaves no stale '
        'reconnect racing it (epoch guard)', (tester) async {
      await pumpConnected(tester);

      final disconnectCompleter = Completer<void>();
      when(() => mockBle.disconnect())
          .thenAnswer((_) => disconnectCompleter.future);
      when(() => mockBle.currentState)
          .thenReturn(BleConnectionState.connected);

      clearInteractions(mockBle);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // The first resume's helper is now awaiting the still-pending
      // disconnect. A second pause supersedes it before that wait resolves.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      disconnectCompleter.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The most recent lifecycle event is a pause: the app is backgrounded
      // and the link is meant to be released. Reconnecting here would be
      // wrong regardless of the superseded resume's own logic — the epoch
      // guard is what stops that stale resume from acting once its wait on
      // the first disconnect finally resolves. Reason: a resume superseded
      // by a later pause must not reconnect once its stale wait resolves —
      // the app is currently paused, so a reconnect here would race the
      // very pause that superseded it (the epoch guard exists to prevent
      // this).
      verifyNever(() => mockBle.connect(any()));
    });

    testWidgets(
        'a resume with no prior pause does not reconnect while genuinely '
        'connected', (tester) async {
      await pumpConnected(tester);
      clearInteractions(mockBle);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Reason: the fix must not turn every resume into a reconnect — with
      // no prior pause (_linkReleasedByPause == false) and a genuinely
      // connected link, resume must stay a no-op exactly as before.
      verifyNever(() => mockBle.connect(any()));
    });

    testWidgets(
        'stale watts/RPM clear on the 3 s tick even while disconnected '
        '(previously gated behind the connected check)', (tester) async {
      await pumpConnected(tester);

      notifyCtrl.add([...watts10, ...rpm300]);
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).lastWatts, 10,
          reason: 'sanity check — telemetry applies live before the drop');
      expect(stateOf(tester).lastRpm, 300,
          reason: 'sanity check — telemetry applies live before the drop');

      // Link drops — status polling stops, but the stale-value clear must
      // not be gated behind the connected check (it used to sit below it,
      // making it unreachable while disconnected).
      when(() => mockBle.currentState)
          .thenReturn(BleConnectionState.disconnected);

      // `_lastWattsAt`/`_lastRpmAt` are stamped with real `DateTime.now()`
      // (there's no injectable clock here), so the FakeAsync virtual clock
      // that `tester.pump(duration)` normally fast-forwards cannot age them
      // by itself — it advances pending Timers, not `DateTime.now()`.
      // `runAsync` steps outside the FakeAsync zone so real time actually
      // passes; a synchronous `sleep` (rather than `Future.delayed`) blocks
      // the isolate without pumping the real event loop, so it can't let
      // unrelated real-zone futures (e.g. google_fonts asset loading) run
      // and throw mid-test. The following `pump` then advances the fake
      // clock far enough to fire the 3 s telemetry tick, whose staleness
      // check reads the now-genuinely-elapsed real time.
      await tester.runAsync(() async {
        sleep(const Duration(seconds: 6));
      });
      await tester.pump(const Duration(seconds: 3));

      expect(stateOf(tester).lastWatts, isNull,
          reason: 'B1: the stale-watts clear must run regardless of '
              'connection state, or watts stay on screen indefinitely '
              'after a drop');
      expect(stateOf(tester).lastRpm, isNull,
          reason: 'B1: the stale-RPM clear must run regardless of '
              'connection state, or RPM stays on screen indefinitely '
              'after a drop');
    });
  });

  // ── Reverse → Nature / Smart: the two-frame sequence ───────────────────────
  // Field report: "after turning on reverse mode, when we try to switch to
  // nature or smart mode, in the first step it does not go to nature/smart but
  // goes to the previous speed it was set to."
  //
  // Both frames are required. Firmware's `case BOOST` NATURE/SMART branches
  // never clear `direction`, and get_mc_state() tests `direction` first, so a
  // fan left reversed would keep reporting 21 01 03 and mask the new mode —
  // the app has to bring it forward first. The exit-reverse frame landed and
  // the mode frame did not, so the fan simply returned to its previous speed.
  //
  // The loss happened at the BLE layer (both writes in one connection
  // interval), which a mocked BleService cannot reproduce — see
  // test/unit/ble_service_write_pacing_test.dart for the pacing that fixes it.
  // What these tests pin down is the app-side contract the fix depends on:
  // both frames are issued, exit-reverse first.
  group('reverse → nature/smart sends both frames, mode after exit-reverse', () {
    const powerOn     = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A];
    const speed5      = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x05, 0x10];
    const timerOff    = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29];
    const rxReverse   = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x03, 0x2B];
    const txExitRev   = [0x55, 0xAA, 0x06, 0x21, 0x01, 0x03, 0x2A];
    const txNature    = [0x55, 0xAA, 0x06, 0x21, 0x01, 0x02, 0x29];
    const txSmart     = [0x55, 0xAA, 0x06, 0x21, 0x01, 0x04, 0x2B];

    FanState stateOf(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(ControlScreen)))
        .read(activeFanStateProvider('TT-001'));

    // Connected, powered at speed 5, sync engine idle, then Reverse arrives on
    // the live path so the highlight is set exactly as it is in the field.
    Future<void> pumpReversed(WidgetTester tester) async {
      await pumpConnected(tester);
      const reply = [...powerOn, ...speed5, ...timerOff];
      notifyCtrl.add(reply);
      await tester.pump();
      notifyCtrl.add(reply);
      await tester.pump();
      await tester.pump();
      notifyCtrl.add(rxReverse);
      await tester.pump();
      expect(stateOf(tester).activeMode, 'reverse',
          reason: 'precondition: the test must actually be in Reverse');
    }

    testWidgets('Reverse → Nature writes exit-reverse then nature', (tester) async {
      await pumpReversed(tester);
      clearInteractions(mockBle);

      tester
          .widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('nature');
      await tester.pump();

      verifyInOrder([
        () => mockBle.writeFrame(txExitRev),
        () => mockBle.writeFrame(txNature),
      ]);
    });

    testWidgets('Reverse → Smart writes exit-reverse then smart', (tester) async {
      await pumpReversed(tester);
      clearInteractions(mockBle);

      tester
          .widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('smart');
      await tester.pump();

      verifyInOrder([
        () => mockBle.writeFrame(txExitRev),
        () => mockBle.writeFrame(txSmart),
      ]);
    });
  });

  // ── Sleep-timer countdown survives backgrounding ───────────────────────────
  // The client's ask: the countdown must stay visible as a notification while
  // the app is in the background — with no BLE (the link is still released on
  // pause, and the fan performs its own shutdown at T-0). Before this, `paused`
  // stopped the foreground service unconditionally, so the countdown vanished
  // the moment the user left the app.
  group('sleep-timer countdown notification', () {
    const bgChannel = MethodChannel('com.terraton/bg_service');
    late List<MethodCall> bgCalls;

    setUp(() {
      bgCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bgChannel, (call) async {
        bgCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bgChannel, null);
    });

    testWidgets('backgrounding with a 4H timer armed keeps the notification up '
        'as a countdown instead of stopping it', (tester) async {
      await pumpPoweredOn(tester);

      tester
          .widget<TimerControlWidget>(find.byType(TimerControlWidget))
          .onTimer('4h');
      await tester.pump();

      bgCalls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        bgCalls.map((c) => c.method),
        isNot(contains('stop')),
        reason: 'stopping the service on pause is what made the countdown '
            'disappear the moment the app was backgrounded',
      );
      final start = bgCalls.lastWhere((c) => c.method == 'start');
      final endAt = (start.arguments as Map)['endAt'] as int;
      expect(
        endAt,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
        reason: 'the notification must carry the expiry timestamp — Android '
            'renders and ticks the countdown from it, which is what lets it '
            'keep running with nothing awake on the Dart side',
      );
    });

    testWidgets('backgrounding with no timer armed still stops the '
        'notification', (tester) async {
      await pumpPoweredOn(tester);

      bgCalls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        bgCalls.map((c) => c.method),
        contains('stop'),
        reason: 'with no countdown to show, a backgrounded app must not leave '
            'an ongoing notification behind showing stale telemetry',
      );
    });
  });
}
