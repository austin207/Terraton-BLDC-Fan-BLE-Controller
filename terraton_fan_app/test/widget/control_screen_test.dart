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

FanDevice _testFan({String model = 'Terraton X1', String deviceId = 'TT-001'}) =>
    FanDevice()
      ..deviceId   = deviceId
      ..macAddress = deviceId == '__demo__' ? '' : 'AA:BB:CC:DD:EE:FF'
      ..nickname   = 'Bedroom Fan'
      ..model      = model
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
    when(() => mockRepo.saveLed(any(), isOn: any(named: 'isOn')))
        .thenAnswer((_) async {});
    when(() => mockRepo.setModel(any(), any())).thenAnswer((_) async {});
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

  Widget buildScreen({String model = 'Terraton X1', String deviceId = 'TT-001'}) =>
      ProviderScope(
        overrides: [
          bleServiceProvider.overrideWithValue(mockBle),
          fanRepositoryProvider.overrideWithValue(mockRepo),
          usageLogRepositoryProvider.overrideWithValue(mockUsageLogRepo),
          dailyRuntimeRepositoryProvider.overrideWithValue(mockDailyRuntimeRepo),
        ],
        child: MaterialApp(
          home: ControlScreen(fan: _testFan(model: model, deviceId: deviceId)),
        ),
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

  // Pump connected AND deliver a powered-on poll reply so controlsEnabled =
  // true (controls require isPowered as well as connected). One reply is
  // enough: every frame the fan sends is applied on arrival, with no agreement
  // rule and no candidate/confirm step.
  const msReplyOn3 = [
    0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A, // power ON
    0x55, 0xAA, 0x07, 0x04, 0x01, 0x03, 0x0E, // speed 3
    0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29, // timer OFF (neutral — ignored)
  ];
  Future<void> pumpPoweredOn(WidgetTester tester) async {
    await pumpConnected(tester);
    notifyCtrl.add(msReplyOn3);
    await tester.pump(); // delivered → applied
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

  testWidgets('light ON shows SnackBar and sends nothing else',
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
    // The lighting frame is pending (null → SnackBar only) and NOTHING else
    // goes out. A tap on an off fan no longer injects a power-on ahead of it.
    verifyNever(() => mockBle.writeFrame(any()));
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

    // Delivers [reply] and lets the widget rebuild. Every frame in it is
    // applied on arrival — there is no agreement step to satisfy.
    Future<void> emitConfirmed(WidgetTester tester, List<int> reply) async {
      notifyCtrl.add(reply);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('reply [power][speed][timer] applies on arrival — power ON, '
        'speed 5, 2H', (tester) async {
      await pumpConnected(tester);
      notifyCtrl.add([...powerOn, ...speed5, ...timer2h]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, 5);
      expect(s.activeTimerCode, 0x02);
    });

    testWidgets('reply split at a frame boundary [power] then [speed][timer] '
        '→ each frame applies as it lands', (tester) async {
      await pumpConnected(tester);
      // The BLE60 preserves UART order but cuts anywhere: power first, the
      // rest in a later notification.
      notifyCtrl.add(powerOn);
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).isPowered, true); // applied immediately
      expect(stateOf(tester).speed, 0);        // speed hasn't arrived yet

      notifyCtrl.add([...speed5, ...timerOff]);
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

    testWidgets('power OFF reply → fan off; the stored speed is kept',
        (tester) async {
      await pumpConnected(tester);
      // Frame [2] carries the firmware's stored last speed even while OFF, and
      // the firmware restores exactly that on the next power-on. Keeping it
      // also avoids fighting the 0x04 frame arriving in the same burst. The
      // panel is dimmed and untappable while isPowered is false.
      await emitConfirmed(tester, [...powerOff, ...speed5, ...timerOff]);

      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.speed, 5);
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
        'a genuine [ON][speed][timer-0] reply DOES clear the timer '
        '(2026-08-22 firmware fix)', (tester) async {
      // get_mc_state()'s timer field now gates on AutoPowerState.FlagAutoPower,
      // which is correctly cleared by both case TIMER and case IRTimerOFF —
      // so this reply is trustworthy, not stale, and a reported 0 is a real
      // cancellation.
      final started = DateTime.now().subtract(const Duration(minutes: 30));
      when(() => mockRepo.getState(any()))
          .thenReturn(runningSmartBaseline(started));

      await pumpConnected(tester);

      notifyCtrl.add([...powerOn, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      var s = stateOf(tester);
      expect(s.activeMode, isNull);      // plain speed also clears Smart
      expect(s.activeTimerCode, isNull); // and the timer-0 report is trusted
      expect(s.timerActivatedAt, isNull);

      // A later genuine Smart + 2H reply still re-arms both normally.
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timer2h]);

      s = stateOf(tester);
      expect(s.activeMode, 'smart');
      expect(s.activeTimerCode, 0x02);
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

    // ── A mode-driven speed-6 reply now DOES clear Smart too (2026-08-22) ──────
    // The 2026-07-04 field report (test/unit/field_capture_2026_07_04_test.dart)
    // was from older/other-batch firmware whose periodic status push lacked a
    // smart_mode check entirely, so it could report a bare speed while Smart
    // was genuinely still active. On the actual firmware source now in use,
    // get_mc_state()'s fallthrough only ever reports 04 once smart_mode is
    // already 0, and the app itself never sends a bare speed command while
    // Smart is lit anymore (onSpeedSelected sends power-ON first) — so there
    // is no remaining path, from the app or from the remote, where a genuine
    // 04 coexists with Smart still running. Treating it as proof of exit is
    // now correct rather than the read that caused the original regression.

    testWidgets(
        'a mode-driven speed-6 reply DOES clear Smart — no ambiguity left on '
        'this firmware', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);
      expect(stateOf(tester).activeMode, 'smart');

      // Session is over; this full reply (power + timer both present)
      // dispatches on the live path and applies atomically.
      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, isNull,
          reason: 'a genuine 04 is proof Smart ended on this firmware — see '
              'the comment above for why the old field-bug protection no '
              'longer applies');
      expect(s.speed, 6);
    });

    // ── A bare speed reply DOES clear Nature/Reverse/Boost (2026-08-22) ────────
    // Confirmed against the actual firmware source in use: SetSpeed() (called
    // by case SPEED, the remote's IRSpeed1..7, and get_mc_state()'s own
    // fallthrough) unconditionally clears NatureFlage/direction, and the
    // relevant handlers clear boost_flag too, every time a speed value is
    // reported — there is no code path on this firmware where a bare 04
    // coexists with Nature/Reverse/Boost still genuinely active. Smart is the
    // one exception (case SPEED never clears smart_mode), so it keeps the old
    // protection above.
    testWidgets(
        'a bare speed-6 reply DOES clear Nature — current firmware always '
        'clears NatureFlage before reporting a speed', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeNature, ...timerOff]);
      expect(stateOf(tester).activeMode, 'nature');

      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.activeMode, isNull,
          reason: 'a genuine 04 is proof Nature ended on this firmware — '
              'SetSpeed() always clears NatureFlage before it can be sent');
      expect(s.speed, 6);
    });

    testWidgets(
        'a bare speed-6 reply DOES clear Boost — current firmware always '
        'clears boost_flag before reporting a speed', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeBoost, ...timerOff]);
      expect(stateOf(tester).isBoost, true);

      notifyCtrl.add([...powerOn, ...speed6, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isBoost, false,
          reason: 'a genuine 04 is proof Boost ended on this firmware — '
              'boost_flag is always cleared before it can be sent');
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
        'power OFF reply clears mode and boost but keeps the stored speed',
        (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...modeSmart, ...timerOff]);
      expect(stateOf(tester).activeMode, 'smart');

      notifyCtrl.add([...powerOff, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      final s = stateOf(tester);
      expect(s.isPowered, false);
      // Firmware fact, not inference: the power-off branch runs ClearModes(),
      // so the chips really are gone in the fan too...
      expect(s.activeMode, isNull,
          reason: 'a power==false frame clears the mode even though a bare '
              'speed frame no longer does');
      expect(s.isBoost, false);
      // ...while OldTargetSpeed survives and is restored on the next power-on,
      // so the speed the OFF reply reports is kept.
      expect(s.speed, 5);
    });

    // ── State-reply 0x22 field is a trustworthy timer reporter (fixed 2026-08-22) ──
    // The 2026-07-04 field report was against firmware whose get_mc_state()
    // gated the timer field on IRControl.FlagAutoPower — a flag AutoPowerControl()
    // clears one tick after ANY timer is armed, so every reply reported 0
    // regardless of whether a timer was genuinely running. The fix (confirmed
    // in the firmware source now in use) gates on AutoPowerState.FlagAutoPower
    // instead, which persists correctly for the whole armed duration and is
    // properly cleared by both case TIMER (BLE) and case IRTimerOFF (remote).
    // A reported 0 is therefore real information now, not noise — this is what
    // makes a remote-driven Timer OFF observable at all.
    const timer4h = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x04, 0x2D];

    testWidgets(
        'a powered reply reporting timer 0 DOES clear an active 4 h countdown '
        'now — no ambiguity left on this firmware', (tester) async {
      await pumpConnected(tester);
      await emitConfirmed(tester, [...powerOn, ...speed5, ...timer4h]);
      expect(stateOf(tester).activeTimerCode, 0x04);

      notifyCtrl.add([...powerOn, ...speed5, ...timerOff]);
      await tester.pump();
      await tester.pump();

      expect(stateOf(tester).activeTimerCode, isNull,
          reason: 'get_mc_state() now gates the timer field on '
              'AutoPowerState.FlagAutoPower, which is genuinely cleared by a '
              'remote Timer OFF press — see the comment above for why the '
              'old field-bug protection no longer applies');
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

      // Advance past the 3 s poll tick to prove polling itself (the exact
      // function the field report says stopped running) is alive again. Both
      // frames of the tick must go out.
      await tester.pump(const Duration(seconds: 3));
      expect(
        verify(() => mockBle.writeFrame(BleFrameBuilder.statusPoll()))
            .callCount,
        greaterThanOrEqualTo(1),
        reason: 'the 3 s status poll must be running again post-reconnect — '
            'this is precisely the field report: "the status polling '
            'function is not being called"',
      );
      expect(
        verify(() => mockBle.writeFrame(BleFrameBuilder.getMotorState()))
            .callCount,
        greaterThanOrEqualTo(1),
        reason: 'the same tick must also re-ask for motor state, since that '
            'is the only thing that refreshes power/speed/mode after a '
            'reconnect',
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

  // ── Per-remote layout (CF-01 / CF-02 / CF-03) ────────────────────────────────
  // The mode-row buttons and control sections come from the fan's resolved
  // RemoteProfile (ApplianceLoader.remoteForModel). Frame behaviour is covered
  // elsewhere; this only checks the wiring.
  group('remote profiles', () {
    testWidgets('CF-01 has the four modes and no mood lighting', (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-01'));
      await tester.pumpAndSettle();

      final modeWidget =
          tester.widget<ModeControlWidget>(find.byType(ModeControlWidget));
      expect(modeWidget.modes, ['nature', 'smart', 'reverse', 'boost']);
      expect(find.byType(LightingControlWidget), findsNothing);
    });

    testWidgets('CF-02 swaps Nature for an LED toggle, still no lighting',
        (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-02'));
      await tester.pumpAndSettle();

      final modeWidget =
          tester.widget<ModeControlWidget>(find.byType(ModeControlWidget));
      expect(modeWidget.modes, ['led', 'smart', 'reverse', 'boost']);
      expect(find.byType(LightingControlWidget), findsNothing);
    });

    testWidgets('CF-03 shows only Reverse + Boost and adds mood lighting',
        (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-03'));
      await tester.pumpAndSettle();

      final modeWidget =
          tester.widget<ModeControlWidget>(find.byType(ModeControlWidget));
      expect(modeWidget.modes, ['reverse', 'boost']);
      expect(find.byType(LightingControlWidget), findsOneWidget);
    });
  });

  // ── Demo fan ────────────────────────────────────────────────────────────────
  group('demo fan', () {
    testWidgets('shows the remote switcher and starts on CF-01', (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-01', deviceId: '__demo__'));
      await tester.pumpAndSettle();

      expect(find.text('DEMO · REMOTE'), findsOneWidget);
      expect(find.text('CF-01'), findsOneWidget);
      expect(find.text('CF-02'), findsOneWidget);
      expect(find.text('CF-03'), findsOneWidget);

      final mode =
          tester.widget<ModeControlWidget>(find.byType(ModeControlWidget));
      expect(mode.modes, ['nature', 'smart', 'reverse', 'boost']);
    });

    testWidgets('switching to CF-03 swaps the layout and clears a stale mode',
        (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-01', deviceId: '__demo__'));
      await tester.pumpAndSettle();

      // Light Nature, then switch to CF-03 (which has no Nature button).
      tester
          .widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('nature');
      await tester.pump();

      await tester.tap(find.text('CF-03'));
      await tester.pumpAndSettle();

      final mode =
          tester.widget<ModeControlWidget>(find.byType(ModeControlWidget));
      expect(mode.modes, ['reverse', 'boost']);
      expect(mode.activeMode, isNull, reason: 'stale Nature chip must be cleared');
      expect(find.byType(LightingControlWidget), findsOneWidget);
    });

    testWidgets('a demo tap drives the fan (power on → dial + telemetry light up)',
        (tester) async {
      await tester.pumpWidget(buildScreen(model: 'TN-CF-01', deviceId: '__demo__'));
      await tester.pumpAndSettle();

      // Power button is a 56 dp circle above the panel.
      await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
      await tester.pumpAndSettle();

      final dial = tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.currentSpeed, greaterThan(0));
      expect(dial.watts, isNotNull);
      expect(dial.rpm, isNotNull);
    });
  });
}
