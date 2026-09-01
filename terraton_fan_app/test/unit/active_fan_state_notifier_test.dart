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
  Future<void> setModel(String deviceId, String model) async {}
  @override
  FanState getState(String deviceId) =>
      _states[deviceId] ?? (FanState()..deviceId = deviceId);
  @override
  Future<void> saveState(FanState fanState) async =>
      _states[fanState.deviceId] = fanState;

  // Field-scoped writers — mirror FanRepositoryImpl: mutate only the method's
  // own field group on the stored row, so a telemetry write can never touch
  // the operating state (the property the reconnect rewrite depends on).
  /// Counts every scoped write, so a test can assert that an unchanged value
  /// produces no write at all.
  int writeCount = 0;

  FanState _row(String deviceId) {
    writeCount++;
    return _states[deviceId] ??= (FanState()..deviceId = deviceId);
  }
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
  Future<void> saveLed(String deviceId, {required bool isOn}) async {
    _row(deviceId).lastLedIsOn = isOn;
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

    test('updateTimer non-zero sets activeTimerCode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).updateTimer(0x04);
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, 0x04);
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
      c.read(activeFanStateProvider(deviceId).notifier).updateRpm(382);
      expect(c.read(activeFanStateProvider(deviceId)).lastRpm, 382);
    });

    test('clearWatts sets lastWatts to null', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateWatts(42);
      n.clearWatts();
      expect(c.read(activeFanStateProvider(deviceId)).lastWatts, isNull);
    });

    test('clearRpm sets lastRpm to null', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateRpm(382);
      n.clearRpm();
      expect(c.read(activeFanStateProvider(deviceId)).lastRpm, isNull);
    });
  });

  // ── setModeHighlight ────────────────────────────────────────────────────────
  // Which mode chip is lit, driven only by a 0x21 frame's mode name. isBoost and
  // activeMode are one UI concept in two columns, so a 0x21 naming one mode
  // necessarily unlights the others — that is reading the byte, not inferring.
  // What it must NOT do is touch isPowered or speed.

  group('ActiveFanStateNotifier — setModeHighlight', () {
    for (final name in ['nature', 'smart', 'reverse']) {
      test('$name lights that chip and clears boost', () {
        final c = makeContainer();
        addTearDown(c.dispose);
        final n = c.read(activeFanStateProvider(deviceId).notifier);
        n.setModeHighlight('boost');
        n.setModeHighlight(name);
        final s = c.read(activeFanStateProvider(deviceId));
        expect(s.activeMode, name);
        expect(s.isBoost, false);
      });
    }

    test('boost lights isBoost and clears any active mode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setModeHighlight('smart');
      n.setModeHighlight('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull);
    });

    test('boost is NOT blocked while nature is lit — no app-side policy', () {
      // The firmware's BOOST branch calls ClearModes() unconditionally, so the
      // old "nature blocks boost" rule was app policy the fan does not share.
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setModeHighlight('nature');
      n.setModeHighlight('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull);
    });

    test('null clears both chips', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setModeHighlight('reverse');
      n.setModeHighlight(null);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, isNull);
      expect(s.isBoost, false);
    });

    test('never touches isPowered or speed — only a 0x02/0x04 frame may', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setModeHighlight('smart');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isPowered, false, reason: 'a mode does not imply power');
      expect(s.speed, 0);
    });
  });

  // ── applyPowerOff ───────────────────────────────────────────────────────────
  // Applied on a 0x02 frame reporting OFF. Clearing the chips and the timer is
  // firmware fact (the power-off branch runs ClearModes() and clears
  // FlagAutoPower); keeping the speed is too (OldTargetSpeed survives off/on).

  group('ActiveFanStateNotifier — applyPowerOff', () {
    test('clears power, mode, boost and the timer', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.setModeHighlight('smart');
      n.updateTimer(0x04);
      n.applyPowerOff();
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isPowered, false);
      expect(s.activeMode, isNull);
      expect(s.isBoost, false);
      expect(s.activeTimerCode, isNull);
      expect(s.timerActivatedAt, isNull);
    });

    test('KEEPS the speed — the firmware restores it on the next power-on', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updateSpeed(5);
      n.applyPowerOff();
      expect(c.read(activeFanStateProvider(deviceId)).speed, 5);
    });
  });

  // ── resetTelemetryOnConnect ─────────────────────────────────────────────────

  group('ActiveFanStateNotifier — resetTelemetryOnConnect', () {
    test('blanks watts/RPM but leaves power, speed and mode alone', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updateSpeed(4);
      n.setModeHighlight('smart');
      n.updateWatts(42);
      n.updateRpm(382);
      n.resetTelemetryOnConnect();
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.lastWatts, isNull);
      expect(s.lastRpm, isNull);
      // Not blanked: the app reconnects on every resume, and these are the
      // fan's own memory. The first poll tick corrects anything stale.
      expect(s.isPowered, true);
      expect(s.speed, 4);
      expect(s.activeMode, 'smart');
    });

    test('never persists the blank', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateWatts(42);
      n.resetTelemetryOnConnect();
      expect(repo.getState(deviceId).lastWatts, 42,
          reason: 'display blanking is in-memory only');
    });

    test('leaves the sleep timer completely untouched', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetTelemetryOnConnect();
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeTimerCode, 0x04);
      expect(s.timerActivatedAt, tap);
    });
  });

  // ── No-op guards ────────────────────────────────────────────────────────────
  // The 3 s poll sends two frames and gets ~6 back, so an unguarded mutator
  // would allocate a new FanState (identity-compared → full screen rebuild) and
  // fire an ObjectBox write several times a second for values that never moved.

  group('ActiveFanStateNotifier — unchanged values do not write', () {
    test('re-reporting the same state does not persist again', () {
      final repo = _FakeRepo();
      final c = ProviderContainer(overrides: [
        fanRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updatePower(true);
      n.updateSpeed(4);
      n.setModeHighlight('smart');
      n.updateWatts(42);
      final writesAfterFirstPoll = repo.writeCount;

      // A second identical poll reply.
      n.updatePower(true);
      n.updateSpeed(4);
      n.setModeHighlight('smart');
      n.updateWatts(42);

      expect(repo.writeCount, writesAfterFirstPoll);
    });

    test('the state object identity is preserved when nothing changes', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateSpeed(4);
      final first = c.read(activeFanStateProvider(deviceId));
      n.updateSpeed(4);
      expect(identical(c.read(activeFanStateProvider(deviceId)), first), isTrue,
          reason: 'a no-op must not trigger a Riverpod rebuild');
    });
  });

  // ── Remote / poll-driven scenarios ──────────────────────────────────────────
  // These document the contract control_screen._applyFrame relies on. Frame
  // parsing lives in BleResponseParser; the notifier just honours the mapping.

  group('ActiveFanStateNotifier — poll-driven scenarios', () {
    test('a 0x21 reverse frame lights the Reverse chip', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(activeFanStateProvider(deviceId).notifier).setModeHighlight('reverse');
      expect(c.read(activeFanStateProvider(deviceId)).activeMode, 'reverse');
    });

    test('a 0x22 code of 0 clears the chip when applied', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateTimer(0x04);
      n.updateTimer(0x00);
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, isNull);
    });

    test('a 0x22 code of 2 stores that duration', () {
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
  // detection). Nothing on the connect path touches the timer, so the countdown
  // keeps ticking across reconnects and the current-state rule confirms it.

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
      n.updateTimer(0x04); // BLE echo / poll reply, no timestamp
      expect(c.read(activeFanStateProvider(deviceId)).timerActivatedAt, tap);
    });

    test('a reconnect keeps the running timer; same-code reply keeps it', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetTelemetryOnConnect();
      final blanked = c.read(activeFanStateProvider(deviceId));
      expect(blanked.activeTimerCode, 0x04);
      expect(blanked.timerActivatedAt, tap);
      n.updateTimer(0x04); // poll reply confirms the same duration
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeTimerCode, 0x04);
      expect(s.timerActivatedAt, tap); // countdown continues, not restarted
    });

    test('a different code after a reconnect counts down from detection', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      final tap = DateTime.now().subtract(const Duration(minutes: 5));
      n.updateTimer(0x04, activatedAt: tap);
      n.resetTelemetryOnConnect();
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
      n.updateTimer(0);        // user tapped Timer OFF
      expect(c.read(activeFanStateProvider(deviceId)).activeTimerCode, isNull);
      n.updateTimer(0x04);     // same code again later
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.timerActivatedAt, isNot(tap)); // fresh detection time
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
      n2.resetTelemetryOnConnect();
      n2.updateTimer(0x02); // poll reply confirms the same duration
      final s = c2.read(activeFanStateProvider(deviceId));
      expect(s.timerActivatedAt, tap); // original start time, not detection
    });
  });
}
