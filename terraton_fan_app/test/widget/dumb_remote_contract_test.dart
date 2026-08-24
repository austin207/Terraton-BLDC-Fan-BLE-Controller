// test/widget/dumb_remote_contract_test.dart
//
// The whole contract of the control screen, in four tables.
//
//   A. Button  -> exactly these bytes, and nothing else.
//   B. Button  -> no local state change at all.
//   C. Frame   -> exactly one field changes.
//   D. The 3 s poll sends both of its frames.
//
// If a future change reintroduces optimistic updates, an auto power-on, a
// send-sequencing rule, or a cross-field inference, something here fails.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/ble/ble_frame_builder.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/daily_runtime_repository.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

class _MockBle              extends Mock implements BleService {}
class _MockRepo             extends Mock implements FanRepository {}
class _MockUsageLogRepo     extends Mock implements UsageLogRepository {}
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

  late _MockBle              mockBle;
  late _MockRepo             mockRepo;
  late _MockUsageLogRepo     mockUsageLogRepo;
  late _MockDailyRuntimeRepo mockDailyRuntimeRepo;
  late StreamController<BleConnectionState> stateCtrl;
  late StreamController<List<int>>          notifyCtrl;

  setUp(() {
    mockBle              = _MockBle();
    mockRepo             = _MockRepo();
    mockUsageLogRepo     = _MockUsageLogRepo();
    mockDailyRuntimeRepo = _MockDailyRuntimeRepo();
    stateCtrl  = StreamController<BleConnectionState>.broadcast();
    notifyCtrl = StreamController<List<int>>.broadcast();

    when(() => mockDailyRuntimeRepo.upsertForDate(any(), any(), any()))
        .thenReturn(null);
    when(() => mockDailyRuntimeRepo.getRange(any(), any(), any()))
        .thenReturn([]);
    when(() => mockUsageLogRepo.addLog(any())).thenReturn(null);
    when(() => mockUsageLogRepo.getLogsInRange(any(), any())).thenReturn([]);
    when(() => mockUsageLogRepo.getLogsForDevice(any(), any(), any()))
        .thenReturn([]);
    when(() => mockUsageLogRepo.allDeviceIds()).thenReturn([]);
    when(() => mockUsageLogRepo.pruneBefore(any())).thenReturn(null);

    when(() => mockBle.connectionStateStream).thenAnswer((_) => stateCtrl.stream);
    when(() => mockBle.notifyStream).thenAnswer((_) => notifyCtrl.stream);
    when(() => mockBle.currentState).thenReturn(BleConnectionState.disconnected);
    when(() => mockBle.scanResultsStream).thenAnswer((_) => const Stream.empty());
    when(() => mockBle.startScan(timeoutSeconds: any(named: 'timeoutSeconds')))
        .thenAnswer((_) async {});
    when(() => mockBle.connect(any())).thenAnswer((_) async => 'AA:BB:CC:DD:EE:FF');
    when(() => mockBle.disconnect()).thenAnswer((_) async {});
    when(() => mockBle.writeFrame(any())).thenAnswer((_) async {});
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
    when(() => mockRepo.saveOpenSegment(any(),
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

  Future<void> pumpConnected(WidgetTester tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();
    await tester.pump();
    stateCtrl.add(BleConnectionState.connected);
    when(() => mockBle.currentState).thenReturn(BleConnectionState.connected);
    await tester.pump();
    await tester.pump();
  }

  FanState stateOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(ControlScreen)),
      ).read(activeFanStateProvider('TT-001'));

  // Response frames (packet id 0x07).
  const rPowerOn  = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A];
  const rPowerOff = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x09];
  const rSpeed5   = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x05, 0x10];
  const rBoost    = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x01, 0x29];
  const rNature   = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x02, 0x2A];
  const rReverse  = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x03, 0x2B];
  const rSmart    = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C];
  const rTimer2h  = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x02, 0x2B];
  const rTimer0   = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29];
  const rWatts10  = [0x55, 0xAA, 0x07, 0x23, 0x01, 0x0A, 0x34];
  const rRpm300   = [0x55, 0xAA, 0x07, 0x24, 0x02, 0x01, 0x2C, 0x59];

  Future<void> emit(WidgetTester tester, List<int> frames) async {
    notifyCtrl.add(frames);
    await tester.pump();
    await tester.pump();
  }

  // Powers the fan on via a poll reply so the controls are enabled, then
  // forgets every frame written so far.
  Future<void> pumpReady(WidgetTester tester) async {
    await pumpConnected(tester);
    await emit(tester, rPowerOn);
    clearInteractions(mockBle);
  }

  // ── Table A: button → exactly these bytes, and nothing else ────────────────

  group('A. one button, one frame', () {
    /// Asserts the tap wrote exactly [frame] and no other frame at all.
    /// Captures rather than using verifyNoMoreInteractions, which would also
    /// trip on incidental `currentState` reads.
    void expectOnlyFrame(List<int> frame) {
      final written =
          verify(() => mockBle.writeFrame(captureAny())).captured;
      expect(written, [frame]);
    }

    testWidgets('Power ON', (tester) async {
      await pumpConnected(tester); // fan reports nothing → isPowered false
      clearInteractions(mockBle);
      final btn = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PowerButton');
      await tester.tap(btn);
      await tester.pump();
      expectOnlyFrame(BleFrameBuilder.powerOn()!);
    });

    testWidgets('Power OFF', (tester) async {
      await pumpReady(tester);
      final btn = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PowerButton');
      await tester.tap(btn);
      await tester.pump();
      expectOnlyFrame(BleFrameBuilder.powerOff()!);
    });

    for (var s = 1; s <= 6; s++) {
      testWidgets('Speed $s', (tester) async {
        await pumpReady(tester);
        tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
            .onSpeedSelected(s);
        await tester.pump();
        expectOnlyFrame(BleFrameBuilder.setSpeed(s)!);
      });
    }

    for (final m in const {
      'nature': 0x02,
      'smart': 0x04,
      'reverse': 0x03,
    }.entries) {
      testWidgets('Mode ${m.key}', (tester) async {
        await pumpReady(tester);
        tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
            .onMode(m.key);
        await tester.pump();
        expectOnlyFrame([0x55, 0xAA, 0x06, 0x21, 0x01, m.value, 0x27 + m.value]);
      });
    }

    testWidgets('Boost', (tester) async {
      await pumpReady(tester);
      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget)).onBoost();
      await tester.pump();
      expectOnlyFrame(BleFrameBuilder.setBoost()!);
    });

    for (final t in const {
      'off': [0x55, 0xAA, 0x06, 0x22, 0x01, 0x00, 0x28],
      '2h':  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x02, 0x2A],
      '4h':  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x04, 0x2C],
      '8h':  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x08, 0x30],
    }.entries) {
      testWidgets('Timer ${t.key}', (tester) async {
        await pumpReady(tester);
        tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
            .onTimer(t.key);
        await tester.pump();
        expectOnlyFrame(t.value);
      });
    }

    testWidgets('a control tapped while the fan is OFF sends ONE frame — no '
        'power-on is injected ahead of it', (tester) async {
      await pumpConnected(tester);
      await emit(tester, rPowerOff);
      clearInteractions(mockBle);

      tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(4);
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setSpeed(4)!)).called(1);
      verifyNoMoreInteractions(mockBle);
    });

    // Re-tapping a LIT chip means "turn this off" — but only for Reverse.
    // Confirmed against the firmware source: none of the remote's own mode
    // buttons (IRNatureWind/IRSmartMode/IRSpeed7) exit on a repeat press —
    // Nature is guarded idempotent, Smart/Boost just re-arm unconditionally.
    // Reverse alone is a genuine toggle (`direction ^= 0x01`), which is why
    // it needs a dedicated exit path instead of re-sending its own frame —
    // Table C below proves the receive path ignores a plain 0x04 for mode
    // purposes in the one ambiguous case (ignore that, it does not apply
    // here since Reverse's own echo is what is untrustworthy, not a 0x04).

    testWidgets('re-tapping Nature re-sends the Nature frame, does not exit',
        (tester) async {
      // Matches the remote's own IRNatureWind: still lit means still active,
      // so a repeat tap is just another "enter Nature" command.
      await pumpReady(tester);
      await emit(tester, rNature);
      expect(stateOf(tester).activeMode, 'nature');
      clearInteractions(mockBle);

      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('nature');
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setNature()!)).called(1);
      expect(stateOf(tester).activeMode, 'nature');
    });

    testWidgets('re-tapping Reverse exits with a speed frame, NOT another '
        'reverse frame', (tester) async {
      // Firmware Reverse is `direction ^= 0x01` (IRScan.c:1396) and always
      // echoes 21 01 03 (IRScan.c:1402) whichever way it ended up. Re-sending
      // it would flip the fan back; a speed frame clears `direction` outright
      // (IRScan.c:1361) — which is also why speed must be seeded BEFORE
      // Reverse is engaged here: a speed frame arriving after Reverse would
      // now correctly clear the chip itself, defeating the "still lit"
      // precondition this test needs.
      await pumpReady(tester);
      await emit(tester, rSpeed5);
      await emit(tester, rReverse);
      clearInteractions(mockBle);

      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('reverse');
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setSpeed(5)!)).called(1);
      verifyNever(() => mockBle.writeFrame(BleFrameBuilder.setReverse()!));
      expect(stateOf(tester).activeMode, isNull);
    });

    testWidgets('re-tapping Smart re-sends the Smart frame, does not exit',
        (tester) async {
      // Matches the remote's own IRSmartMode: it has no "already active"
      // guard at all, it just re-arms (SpeedCnt reset, SetSpeed(6)) — never
      // toggles off. Smart is exited only by selecting a speed.
      await pumpReady(tester);
      await emit(tester, rSmart);
      expect(stateOf(tester).activeMode, 'smart');
      clearInteractions(mockBle);

      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('smart');
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setSmart()!)).called(1);
      verifyNever(() => mockBle.writeFrame(BleFrameBuilder.powerOn()!));
      expect(stateOf(tester).activeMode, 'smart');
    });

    testWidgets('re-tapping Boost re-sends the Boost frame, does not exit',
        (tester) async {
      // Matches the remote's own IRSpeed7: it unconditionally re-sends
      // SetSpeed(7) with no "already active" check — never toggles off.
      // Boost is exited only by selecting a speed.
      await pumpReady(tester);
      await emit(tester, rBoost);
      expect(stateOf(tester).isBoost, true);
      clearInteractions(mockBle);

      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget)).onBoost();
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setBoost()!)).called(1);
      expect(stateOf(tester).isBoost, true);
    });

    testWidgets('an exit falls back to speed 3 when the stored speed is unusable',
        (tester) async {
      // Matches the firmware's own fallback when OldTargetSpeed is 0
      // (MoveForward, IRScan.c:763).
      await pumpReady(tester);
      await emit(tester, rReverse);
      expect(stateOf(tester).speed, 0);
      clearInteractions(mockBle);

      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('reverse');
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.setSpeed(3)!)).called(1);
    });

    // A speed dot still sends exactly one speed frame. What changes locally is
    // only what `case SPEED` (IRScan.c:1357) is KNOWN to clear — that is
    // knowledge of our own command, not an inference from any reply.

    testWidgets('a speed dot clears Nature, Boost and Reverse', (tester) async {
      for (final mode in [rNature, rBoost, rReverse]) {
        await pumpReady(tester);
        await emit(tester, mode);
        clearInteractions(mockBle);

        tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
            .onSpeedSelected(4);
        await tester.pump();

        verify(() => mockBle.writeFrame(BleFrameBuilder.setSpeed(4)!)).called(1);
        final s = stateOf(tester);
        expect(s.activeMode, isNull);
        expect(s.isBoost, false);
      }
    });

    testWidgets(
        'a speed dot exits Smart with power-ON, then applies the tapped speed',
        (tester) async {
      // The BLE speed path alone does not clear smart_mode; only power-ON
      // does (case POWER's on-branch). So a speed tap taken while Smart is
      // lit must send that exit frame first, then the tapped speed.
      await pumpReady(tester);
      await emit(tester, rSmart);
      clearInteractions(mockBle);

      tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(4);
      await tester.pump();

      verify(() => mockBle.writeFrame(BleFrameBuilder.powerOn()!)).called(1);
      verify(() => mockBle.writeFrame(BleFrameBuilder.setSpeed(4)!)).called(1);
      expect(stateOf(tester).activeMode, isNull);
    });

    testWidgets('arming a real timer clears Smart, and Timer OFF does not',
        (tester) async {
      // case TIMER runs smart_mode = 0 for codes 2/4/8 only
      // (IRScan.c:1424/1428/1432). get_mc_state() never reports Smart either
      // way, so this tap is the app's only chance to know.
      await pumpReady(tester);
      await emit(tester, rSmart);

      tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
          .onTimer('2h');
      await tester.pump();
      expect(stateOf(tester).activeMode, isNull);

      await emit(tester, rSmart);
      tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
          .onTimer('off');
      await tester.pump();
      expect(stateOf(tester).activeMode, 'smart');
    });

    testWidgets('arming a timer leaves Nature and Reverse alone', (tester) async {
      for (final mode in [rNature, rReverse]) {
        await pumpReady(tester);
        await emit(tester, mode);

        tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
            .onTimer('4h');
        await tester.pump();

        expect(stateOf(tester).activeMode, isNotNull);
      }
    });
  });

  // ── Table B: a tap changes nothing locally ─────────────────────────────────
  // The one deliberate exception is the sleep timer, whose countdown origin the
  // fan cannot report and the app therefore owns.

  group('B. a tap sends bytes and changes no local state', () {
    testWidgets('speed tap does not move the dial until the fan says so',
        (tester) async {
      await pumpReady(tester);
      final before = stateOf(tester);
      tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(6);
      await tester.pump();
      expect(stateOf(tester).speed, before.speed);
    });

    testWidgets('mode tap does not light the chip until the fan says so',
        (tester) async {
      await pumpReady(tester);
      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget))
          .onMode('smart');
      await tester.pump();
      expect(stateOf(tester).activeMode, isNull);
    });

    testWidgets('boost tap does not light Boost until the fan says so',
        (tester) async {
      await pumpReady(tester);
      tester.widget<ModeControlWidget>(find.byType(ModeControlWidget)).onBoost();
      await tester.pump();
      expect(stateOf(tester).isBoost, false);
    });

    testWidgets('power tap does not flip isPowered until the fan says so',
        (tester) async {
      await pumpConnected(tester);
      final btn = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PowerButton');
      await tester.tap(btn);
      await tester.pump();
      expect(stateOf(tester).isPowered, false);
    });

    testWidgets('EXCEPTION: the timer tap arms the countdown immediately',
        (tester) async {
      // The fan answers 22 01 00 whatever is running, so the app owns the
      // countdown origin. Without this the countdown could never start.
      await pumpReady(tester);
      tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
          .onTimer('4h');
      await tester.pump();
      final s = stateOf(tester);
      expect(s.activeTimerCode, 0x04);
      expect(s.timerActivatedAt, isNotNull);
    });
  });

  // ── Table C: one frame in, one field out ───────────────────────────────────

  group('C. one frame changes exactly one thing', () {
    testWidgets('0x02 ON sets only isPowered', (tester) async {
      await pumpConnected(tester);
      final before = stateOf(tester);
      await emit(tester, rPowerOn);
      final s = stateOf(tester);
      expect(s.isPowered, true);
      expect(s.speed, before.speed);
      expect(s.activeMode, before.activeMode);
      expect(s.isBoost, before.isBoost);
      expect(s.lastWatts, before.lastWatts);
    });

    testWidgets('0x04 sets only the speed', (tester) async {
      await pumpReady(tester);
      await emit(tester, rSpeed5);
      final s = stateOf(tester);
      expect(s.speed, 5);
      expect(s.activeMode, isNull);
      expect(s.isBoost, false);
      expect(s.isPowered, true);
    });

    testWidgets('0x04 DOES clear an active Nature highlight', (tester) async {
      // Confirmed against the actual firmware source in use: SetSpeed()
      // (called by case SPEED, the remote's speed buttons, and
      // get_mc_state()'s own fallthrough) unconditionally clears NatureFlage
      // before a bare speed value can ever be reported — there is no code
      // path where a 04 coexists with Nature still genuinely active. Smart
      // stays the one exception (case SPEED never clears smart_mode); see the
      // next test.
      await pumpReady(tester);
      await emit(tester, rNature);
      await emit(tester, rSpeed5);
      final s = stateOf(tester);
      expect(s.activeMode, isNull);
      expect(s.speed, 5);
    });

    testWidgets('0x04 DOES clear an active Smart highlight too', (tester) async {
      // A remote speed press clears smart_mode unconditionally (IRSpeed1..6),
      // and an app-originated speed tap now sends an explicit power-ON exit
      // frame before the speed frame (see onSpeedSelected) — so a bare 0x04
      // can no longer arrive while Smart is genuinely still active, from
      // either origin. Safe to treat it the same as Nature/Reverse/Boost.
      await pumpReady(tester);
      await emit(tester, rSmart);
      await emit(tester, rSpeed5);
      expect(stateOf(tester).activeMode, isNull);
    });

    testWidgets('0x04 DOES clear Boost', (tester) async {
      // boost_flag is always cleared before a bare speed value can be
      // reported on this firmware — see the Nature test above.
      await pumpReady(tester);
      await emit(tester, rBoost);
      await emit(tester, rSpeed5);
      expect(stateOf(tester).isBoost, false);
    });

    testWidgets('0x04 DOES clear Reverse too — no exceptions left',
        (tester) async {
      // Confirmed against the actual firmware source in use: a bare 0x04 is
      // proof a mode has ended, whether it arrives from get_mc_state()'s own
      // fallthrough or as the echo of a speed command — direction is always
      // cleared first. Smart used to be an exception (case SPEED never
      // clears smart_mode on its own), but onSpeedSelected now sends an
      // explicit power-ON exit frame before a speed frame whenever Smart is
      // lit, so that ambiguity no longer exists from either origin.
      await pumpReady(tester);
      await emit(tester, rReverse);
      expect(stateOf(tester).activeMode, 'reverse');

      await emit(tester, rSpeed5);
      final s = stateOf(tester);
      expect(s.activeMode, isNull);
      expect(s.speed, 5);
    });

    testWidgets('0x21 replaces whichever chip was lit', (tester) async {
      await pumpReady(tester);
      await emit(tester, rSmart);
      await emit(tester, rBoost);
      var s = stateOf(tester);
      expect(s.isBoost, true);
      expect(s.activeMode, isNull);

      await emit(tester, rNature);
      s = stateOf(tester);
      expect(s.activeMode, 'nature');
      expect(s.isBoost, false);
    });

    testWidgets('0x22 with a real code arms the countdown', (tester) async {
      await pumpReady(tester);
      await emit(tester, rTimer2h);
      final s = stateOf(tester);
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt, isNotNull);
    });

    testWidgets(
        '0x22 code 0 while powered DOES cancel now (2026-08-22 firmware fix)',
        (tester) async {
      // get_mc_state() now gates the timer field on AutoPowerState.FlagAutoPower
      // (previously IRControl.FlagAutoPower, which case TIMER never set and
      // AutoPowerControl() cleared one tick after arming regardless — that old
      // bug is what made a reported 0 meaningless). AutoPowerState.FlagAutoPower
      // persists correctly for the whole armed duration and is genuinely
      // cleared by both case TIMER and case IRTimerOFF, so a reported 0 is now
      // trustworthy.
      await pumpReady(tester);
      tester.widget<TimerControlWidget>(find.byType(TimerControlWidget))
          .onTimer('4h');
      await tester.pump();

      await emit(tester, [...rPowerOn, ...rSpeed5, ...rTimer0]);

      final s = stateOf(tester);
      expect(s.activeTimerCode, isNull);
      expect(s.timerActivatedAt, isNull);
    });

    testWidgets('0x02 OFF clears power, chips and timer but keeps the speed',
        (tester) async {
      await pumpReady(tester);
      await emit(tester, [...rSpeed5, ...rSmart, ...rTimer2h]);
      await emit(tester, rPowerOff);
      final s = stateOf(tester);
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.isBoost, false);
      expect(s.activeTimerCode, isNull);
      expect(s.speed, 5, reason: 'the firmware restores this on the next ON');
    });

    testWidgets('0x23 sets only watts, 0x24 only RPM', (tester) async {
      await pumpReady(tester);
      await emit(tester, rSmart);
      await emit(tester, [...rWatts10, ...rRpm300]);
      final s = stateOf(tester);
      expect(s.lastWatts, 10);
      expect(s.lastRpm, 300);
      expect(s.activeMode, 'smart');
      expect(s.isPowered, true);
    });

    testWidgets('a frame split mid-way across notifications still applies once',
        (tester) async {
      await pumpReady(tester);
      // Cut the speed frame in half — the assembler must carry the tail.
      notifyCtrl.add(rSpeed5.sublist(0, 4));
      await tester.pump();
      expect(stateOf(tester).speed, 0);
      notifyCtrl.add(rSpeed5.sublist(4));
      await tester.pump();
      await tester.pump();
      expect(stateOf(tester).speed, 5);
    });
  });

  // ── Table D: the poll ──────────────────────────────────────────────────────

  group('D. the 3 s poll', () {
    testWidgets('each tick asks for telemetry AND motor state', (tester) async {
      await pumpConnected(tester);
      clearInteractions(mockBle);

      await tester.pump(const Duration(seconds: 3));

      verify(() => mockBle.writeFrame(BleFrameBuilder.statusPoll())).called(1);
      verify(() => mockBle.writeFrame(BleFrameBuilder.getMotorState())).called(1);
    });

    testWidgets('every tick sends the same motor-state frame — no alternation',
        (tester) async {
      // The vendor-doc variant (…00 02) is never sent, because the firmware
      // provably rejects it. check_crc() (IRScan.c:1462) sums only
      // request_frame[2]+[3]+[5] = 0x00+0x01+0x00 = 0x01, so the …02 frame
      // fails the check, read_request() never sets recv_flag, and
      // Process_Response() is not called at all. Alternating meant every
      // second tick got no reply and the display updated every 6 s, not 3 s.
      await pumpConnected(tester);
      clearInteractions(mockBle);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));

      verify(() => mockBle.writeFrame(BleFrameBuilder.getMotorState()))
          .called(2);
      verifyNever(
          () => mockBle.writeFrame(BleFrameBuilder.getMotorStateVendor()));
    });

    testWidgets('nothing is polled while disconnected', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();
      await tester.pump();
      when(() => mockBle.currentState)
          .thenReturn(BleConnectionState.disconnected);
      clearInteractions(mockBle);

      await tester.pump(const Duration(seconds: 3));

      verifyNever(() => mockBle.writeFrame(BleFrameBuilder.statusPoll()));
      verifyNever(() => mockBle.writeFrame(BleFrameBuilder.getMotorState()));
    });
  });
}
