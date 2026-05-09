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

    // updateMode — non-trivial: boost maps to isBoost=true + activeMode=null
    test('updateMode boost sets isBoost=true and clears activeMode', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(activeFanStateProvider(deviceId).notifier);
      n.updateMode('nature'); // prime a non-boost mode first
      n.updateMode('boost');
      final s = c.read(activeFanStateProvider(deviceId));
      expect(s.isBoost, true);
      expect(s.activeMode, isNull);
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
}
