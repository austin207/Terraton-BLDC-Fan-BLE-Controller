// test/unit/active_fan_state_notifier_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

// Minimal in-memory FanRepository — avoids the ObjectBox native library.
class _FakeRepo implements FanRepository {
  final _states = <String, FanState>{};

  @override
  List<FanDevice> getAllFans() => const <FanDevice>[];
  @override
  FanDevice? getFanByDeviceId(String deviceId) => null;
  @override
  FanDevice? getFanByMac(String macAddress) => null;
  @override
  Future<void> saveFan(FanDevice fan) async {}
  @override
  Future<void> updateMac(String deviceId, String macAddress) async {}
  @override
  Future<void> deleteFan(String deviceId) async {}
  @override
  Future<void> renameFan(String deviceId, String newNickname) async {}
  @override
  FanState getState(String deviceId) =>
      _states[deviceId] ?? (FanState()..deviceId = deviceId);
  @override
  Future<void> saveState(FanState fanState) async =>
      _states[fanState.deviceId] = fanState;

  // Field-scoped writers — mirror FanRepositoryImpl: mutate only the method's
  // own field group on the stored row, so a telemetry write can never touch
  // the operating state (the property the reconnect rewrite depends on).
  FanState _row(String deviceId) =>
      _states[deviceId] ??= (FanState()..deviceId = deviceId);
  @override
  Future<void> saveOperatingState(
    String deviceId, {
    required bool isPowered,
    required bool isBoost,
    required int speed,
    required String? activeMode,
  }) async {
    _row(deviceId)
      ..isPowered  = isPowered
      ..isBoost    = isBoost
      ..speed      = speed
      ..activeMode = activeMode;
  }

  @override
  Future<void> saveTimerState(
    String deviceId, {
    required int? activeTimerCode,
    required DateTime? timerActivatedAt,
  }) async {
    _row(deviceId)
      ..activeTimerCode  = activeTimerCode
      ..timerActivatedAt = timerActivatedAt;
  }

  @override
  Future<void> saveTelemetry(
    String deviceId, {
    required int? lastWatts,
    required int? lastRpm,
    required int? lastRuntimeSecs,
  }) async {
    _row(deviceId)
      ..lastWatts       = lastWatts
      ..lastRpm         = lastRpm
      ..lastRuntimeSecs = lastRuntimeSecs;
  }

  @override
  Future<void> saveLighting(
    String deviceId, {
    required String colorType,
    required double brightness,
    required bool isOn,
  }) async {
    _row(deviceId)
      ..lastLightColorType  = colorType
      ..lastLightBrightness = brightness
      ..lastLightIsOn       = isOn;
  }
  @override
  Future<void> saveOpenSegment(
    String deviceId, {
    required DateTime start,
    required int gear,
    String? mode,
    int? smartBaselineGear,
    required int wattsSum,
    required int wattsCount,
    required int rpmSum,
    required int rpmCount,
  }) async {}
  @override
  String exportToJson() => '{}';
  @override
  Future<int> importFromJson(String json) async => 0;
}

void main() {
  const deviceId = 'test-fan-001';

  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(_FakeRepo()),
      ]);

  group('ActiveFanStateNotifier', () {
    test('initial state has default field values', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.deviceId, deviceId);
      expect(s.isPowered, false);
      expect(s.speed, 0);
      expect(s.isBoost, false);
      expect(s.activeMode, isNull);
      expect(s.activeTimerCode, isNull);
      expect(s.lastWatts, isNull);
      expect(s.lastRpm, isNull);
    });

    test('updatePower true sets isPowered', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updatePower(true);
      expect(c.read(activeFanStateProvider(deviceId)).isPowered, true);
    });

    test('updatePower false clears isPowered', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updatePower(false);
      expect(c.read(activeFanStateProvider(deviceId)).isPowered, false);
    });

    test('updateSpeed sets speed field', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateSpeed(4);
      expect(c.read(activeFanStateProvider(deviceId)).speed, 4);
    });

    // updateMode — boost is mutually exclusive with ALL modes (nature/smart/reverse)
    test('updateMode boost sets isBoost=true and clears nature activeMode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('nature'); // prime with nature (mutually exclusive with boost)
      n.updateMode('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // nature cleared; boost won
    });

    test('updateMode boost clears smart activeMode (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('smart'); // smart and boost are mutually exclusive
      n.updateMode('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // smart cleared; boost won
    });

    test('updateMode boost clears reverse activeMode (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('reverse');
      n.updateMode('boost'); // boost replaces the reverse highlight
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // reverse cleared; boost won
    });

    test('updateMode smart clears isBoost (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('boost'); // boost active first
      n.updateMode('smart'); // smart must clear boost
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'smart');
      expect(s.isBoost, false);
    });

    test('updateMode reverse clears isBoost (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('boost'); // boost active first
      n.updateMode('reverse'); // reverse replaces the boost highlight
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'reverse');
      expect(s.isBoost, false);
    });

    test('updateMode nature sets isBoost=false and activeMode=nature', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateMode('nature');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, false);
      expect(s.activeMode, 'nature');
    });

    test('updateMode reverse sets isBoost=false and activeMode=reverse', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateMode('reverse');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, false);
      expect(s.activeMode, 'reverse');
    });

    test('updateMode null clears both isBoost and activeMode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('smart');
      n.updateMode(null);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, false);
      expect(s.activeMode, isNull);
    });

    // updateTimer — non-trivial: timerCode 0 → null
    test('updateTimer non-zero sets activeTimerCode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateTimer(0x02);
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, 0x02);
    });

    test('updateTimer 0 clears activeTimerCode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateTimer(0x04);
      n.updateTimer(0);
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, isNull);
    });

    test('updateWatts sets lastWatts', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateWatts(42);
      expect(c.read(activeFanStateProvider(deviceId)).lastWatts, 42);
    });

    test('updateRpm sets lastRpm', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateRpm(600);
      expect(c.read(activeFanStateProvider(deviceId)).lastRpm, 600);
    });

    test('clearWatts sets lastWatts to null', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateWatts(28);
      n.clearWatts();
      expect(c.read(activeFanStateProvider(deviceId)).lastWatts, isNull);
    });

    test('clearRpm sets lastRpm to null', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateRpm(300);
      n.clearRpm();
      expect(c.read(activeFanStateProvider(deviceId)).lastRpm, isNull);
    });
  });

  group('ActiveFanStateNotifier — setBoostActive', () {
    test('setBoostActive(true) sets isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).setBoostActive(true);
      expect(c.read(activeFanStateProvider(deviceId)).isBoost, true);
    });

    test('setBoostActive(false) clears isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setBoostActive(false);
      expect(c.read(activeFanStateProvider(deviceId)).isBoost, false);
    });

    test('setBoostActive(true) blocked when activeMode is nature', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('nature'); // prime with nature
      n.setBoostActive(true); // nature blocks boost
      expect(c.read(activeFanStateProvider(deviceId)).isBoost, false);
    });

    test('setBoostActive(true) clears smart activeMode (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('smart');
      n.setBoostActive(true);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // smart cleared
    });

    test('setBoostActive(true) clears reverse activeMode (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('reverse');
      n.setBoostActive(true);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull); // reverse cleared — boost excludes all modes
    });
  });

  group('ActiveFanStateNotifier — setActiveMode', () {
    test('setActiveMode(nature) sets activeMode and clears isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true); // prime boost
      n.setActiveMode('nature');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'nature');
      expect(s.isBoost, false);
    });

    test('setActiveMode(smart) sets activeMode and clears isBoost (mutually exclusive)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setActiveMode('smart');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'smart');
      expect(s.isBoost, false); // boost cleared — Smart and Boost are exclusive
    });

    test('setActiveMode(reverse) sets activeMode and clears isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setActiveMode('reverse'); // reverse replaces the boost highlight
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'reverse');
      expect(s.isBoost, false);
    });

    test('setActiveMode(null) clears activeMode and preserves isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setActiveMode(null); // clearing a mode never touches boost
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, isNull);
      expect(s.isBoost, true);
    });
  });

  // ── Remote sync scenarios ──────────────────────────────────────────────────
  // These tests document the exact notifier calls made by _subscribeNotify
  // for each remote-triggered state change. The toggle detection (Reverse)
  // and byte mapping (Timer) both live in control_screen.dart; the notifier
  // just needs to honour the contract below.

  group('ActiveFanStateNotifier — remote sync scenarios', () {
    test('remote Reverse ON — updateMode reverse → activeMode=reverse', () {
      // Remote presses Reverse while not in reverse: hardware sends 0x03,
      // _subscribeNotify calls updateMode('reverse').
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateMode('reverse');
      expect(c.read(activeFanStateProvider(deviceId)).activeMode, 'reverse');
    });

    test('remote Reverse OFF — setActiveMode(null) → activeMode=null', () {
      // Remote presses Reverse while reverse is active: hardware sends 0x03,
      // toggle-detection in _subscribeNotify calls setActiveMode(null).
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setActiveMode('reverse');
      n.setActiveMode(null);
      expect(c.read(activeFanStateProvider(deviceId)).activeMode, isNull);
    });

    test('remote timer OFF byte 0x00 — updateTimer(0x00) → activeTimerCode=null', () {
      // Remote sends Timer OFF; parseTimer returns 0x00; updateTimer(0x00)
      // must treat 0 as "clear" (OFF state is stored as null).
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateTimer(0x04); // prime with 4H
      n.updateTimer(0x00); // remote sends OFF
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, isNull);
    });

    test('remote timer 2H byte 0x02 — updateTimer(0x02) → activeTimerCode=0x02', () {
      // Remote sends Timer 2H; parseTimer returns 0x02; updateTimer stores it.
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateTimer(0x02);
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, 0x02);
    });
  });

  // ── Sleep-timer start-timestamp resolution ─────────────────────────────────
  // The fan only reports WHICH duration is active, never the time remaining, so
  // the countdown start timestamp is app-side. updateTimer resolves it as:
  // explicit → current (same code) → DateTime.now() (count down from
  // detection). resetOnConnect never touches the timer, so the countdown keeps
  // ticking across reconnects and the current-state rule confirms it.

  group('ActiveFanStateNotifier — timer start timestamp', () {
    test('explicit activatedAt wins (user tap)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      expect(c.read(activeFanStateProvider(deviceId)).timerActivatedAt, tap);
    });

    test('echo with same code preserves the existing start time', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.updateTimer(0x04); // BLE echo / Machine State frame, no timestamp
      expect(c.read(activeFanStateProvider(deviceId)).timerActivatedAt, tap);
    });

    test('resetOnConnect preserves the running timer; same-code reply keeps it', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetOnConnect(); // reconnect keeps the countdown ticking…
      final blanked = c.read(activeFanStateProvider(deviceId));
      expect(blanked.activeTimerCode, 0x04);
      expect(blanked.timerActivatedAt, tap);
      n.updateTimer(0x04); // …Machine State reply confirms the same duration
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeTimerCode, 0x04);
      expect(s.timerActivatedAt, tap); // countdown continues, not restarted
    });

    test('different code after resetOnConnect counts down from detection', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetOnConnect();
      final before = DateTime.now();
      n.updateTimer(0x02); // remote changed the timer while disconnected
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeTimerCode, 0x02);
      expect(s.timerActivatedAt!.isBefore(before), isFalse); // ≈ now, not tap
    });

    test('unknown timer (set from remote) counts down from detection', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final before = DateTime.now();
      n.updateTimer(0x08); // no prior knowledge, no explicit timestamp
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.timerActivatedAt, isNotNull);
      expect(s.timerActivatedAt!.isBefore(before), isFalse);
    });

    test('start time implying the timer already expired is discarded', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final stale = DateTime.now().subtract(const Duration(hours: 3));
      n.updateTimer(0x02, activatedAt: stale); // 2H timer "started" 3 h ago
      final s = c.read(activeFanStateProvider(deviceId));
      // Firmware says ACTIVE, so the stale timestamp is wrong → detection time.
      expect(
        DateTime.now().difference(s.timerActivatedAt!),
        lessThan(const Duration(hours: 2)),
      );
    });

    test('updateTimer(0) clears the start time for good', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetOnConnect();
      n.updateTimer(0);        // fan reports timer OFF — countdown is gone
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, isNull);
      n.updateTimer(0x04);     // same code again later
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.timerActivatedAt, isNot(tap)); // fresh detection time
    });
  });

  // ── resetOnConnect persistence semantics ────────────────────────────────────
  // The connect-time blank is in-memory only: the DB keeps the last-known-good
  // state so an app kill mid-connect (before the Machine State reply lands)
  // loses nothing — in particular the sleep-timer start timestamp.

  group('ActiveFanStateNotifier — resetOnConnect persistence', () {
    test('resetOnConnect blanks the UI state but does not persist the blank', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updatePower(true);
      n.updateSpeed(4);
      n.updateMode('smart');
      n.updateTimer(0x02, activatedAt: tap);
      n.resetOnConnect();

      final visible = c.read(activeFanStateProvider(deviceId));
      expect(visible.isPowered, false);
      expect(visible.speed, 0);
      expect(visible.activeMode, isNull);

      final persisted = repo.getState(deviceId);
      expect(persisted.isPowered, true);
      expect(persisted.speed, 4);
      expect(persisted.activeMode, 'smart');
      expect(persisted.activeTimerCode, 0x02);
      expect(persisted.timerActivatedAt, tap);
    });

    // FIELD BUG (2026-07-17): under the old whole-row persist, the first
    // telemetry frame after connect — the runtime reply rides the very same
    // notification burst as the Machine-State reply — re-persisted the blanked
    // operating state and destroyed the last-known-good row, wiping Smart +
    // the sleep timer on every reconnect. Field-scoped persistence makes this
    // structurally impossible: a telemetry write touches only telemetry.
    test('telemetry after resetOnConnect does not persist the blank', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updatePower(true);
      n.updateSpeed(4);
      n.updateMode('smart');
      n.updateTimer(0x02, activatedAt: tap);
      n.resetOnConnect();

      // The connect burst: runtime + watts + RPM land before the Machine-State
      // reply is assembled and flushed.
      n.updateRuntime(1234);
      n.updateWatts(200);
      n.updateRpm(310);

      // The UI still shows the blank — that part is intended.
      final visible = c.read(activeFanStateProvider(deviceId));
      expect(visible.isPowered, false);
      expect(visible.activeMode, isNull);
      expect(visible.speed, 0);

      // ...but the persisted baseline must still hold the truth from before the
      // disconnect, or the demotion guard has nothing left to defend.
      final persisted = repo.getState(deviceId);
      expect(persisted.isPowered, true, reason: 'baseline poisoned: guard disarmed');
      expect(persisted.speed, 4);
      expect(persisted.activeMode, 'smart');
      expect(persisted.activeTimerCode, 0x02);
      expect(persisted.timerActivatedAt, tap);
      // Telemetry itself must still reach the DB.
      expect(persisted.lastRuntimeSecs, 1234);
      expect(persisted.lastWatts, 200);
      expect(persisted.lastRpm, 310);
    });

    test('an authoritative apply persists verbatim, blank or not', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updateMode('smart');
      n.resetOnConnect();

      // Machine-State truth lands (released by the sync engine): the fan
      // really is off now. The apply must persist — scoped writes protect the
      // row from writes OUTSIDE their field group, never from a deliberate
      // operating-state apply.
      n.applyMotorStatePowerOff();
      n.updateWatts(0);

      final persisted = repo.getState(deviceId);
      expect(persisted.isPowered, false);
      expect(persisted.activeMode, isNull);
      expect(persisted.lastWatts, 0);
    });

    test('a timer write after the blank never touches the operating row', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updateMode('smart');
      n.resetOnConnect();

      // A confirmed 4H timer lands while the display is still blank. The
      // timer is its own field group, so it persists — and the operating
      // baseline underneath stays exactly as it was before the disconnect.
      final tap = DateTime.now().subtract(const Duration(minutes: 10));
      n.updateTimer(0x04, activatedAt: tap);

      final persisted = repo.getState(deviceId);
      expect(persisted.activeTimerCode, 0x04);
      expect(persisted.timerActivatedAt, tap);
      // ...and the operating baseline is still intact underneath it.
      expect(persisted.isPowered, true);
      expect(persisted.activeMode, 'smart');
    });

    test('timer countdown survives an app kill and relaunch', () {
      final repo = _FakeRepo();
      final tap = DateTime.now().subtract(const Duration(minutes: 30));

      final c1 = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      c1
          .read(activeFanStateProvider(deviceId).notifier)
          .updateTimer(0x02, activatedAt: tap);
      c1.dispose(); // app killed — the notifier and any in-memory state die

      final c2 = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c2.dispose);
      // Relaunch: build() loads the persisted timer, so the chip ticks at once.
      final loaded = c2.read(activeFanStateProvider(deviceId));
      expect(loaded.activeTimerCode, 0x02);
      expect(loaded.timerActivatedAt, tap);

      final n2 = c2.read(activeFanStateProvider(deviceId).notifier);
      n2.resetOnConnect();
      n2.updateTimer(0x02); // Machine State reply confirms the same duration
      final s = c2.read(activeFanStateProvider(deviceId));
      expect(s.timerActivatedAt, tap); // original start time, not detection
    });
  });
}
