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

    // updateMode — boost clears nature (mutually exclusive) but preserves smart/reverse
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

    test('updateMode boost preserves reverse activeMode (coexistence)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('reverse'); // reverse + boost may coexist
      n.updateMode('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, 'reverse'); // reverse preserved
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

    test('updateMode reverse preserves isBoost (coexistence)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('boost'); // boost active first
      n.updateMode('reverse'); // reverse may coexist with boost
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'reverse');
      expect(s.isBoost, true);
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

    test('setBoostActive(true) preserves reverse activeMode (coexistence)', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('reverse');
      n.setBoostActive(true);
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, 'reverse'); // reverse preserved
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

    test('setActiveMode(reverse) sets activeMode and preserves isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setActiveMode('reverse');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.activeMode, 'reverse');
      expect(s.isBoost, true);
    });

    test('setActiveMode(null) clears activeMode and preserves isBoost', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.setBoostActive(true);
      n.setActiveMode('reverse'); // reverse coexists with boost
      n.setActiveMode(null);
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
}
