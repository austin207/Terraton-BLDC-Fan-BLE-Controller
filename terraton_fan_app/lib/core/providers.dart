// lib/core/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ble/ble_service.dart';
import 'ble/ble_connection_state.dart';
import 'storage/fan_repository.dart';
import '../models/fan_device.dart';
import '../models/fan_state.dart';

final bleServiceProvider = Provider<BleService>((ref) => BleServiceImpl());

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) =>
    ref.watch(bleServiceProvider).connectionStateStream);

final fanRepositoryProvider = Provider<FanRepository>((ref) => FanRepositoryImpl());

final savedFansProvider = Provider<List<FanDevice>>((ref) =>
    ref.watch(fanRepositoryProvider).getAllFans());

// ── Active fan selection ─────────────────────────────────────────────────────

class ActiveFanNotifier extends StateNotifier<FanDevice?> {
  ActiveFanNotifier() : super(null);
  void set(FanDevice fan) => state = fan;
  void clear() => state = null;
}

final activeFanProvider = StateNotifierProvider<ActiveFanNotifier, FanDevice?>(
    (ref) => ActiveFanNotifier());

// ── Active fan state (mirrors ObjectBox + live BLE updates) ─────────────────

class ActiveFanStateNotifier extends StateNotifier<FanState> {
  final FanRepository _repo;

  ActiveFanStateNotifier(FanRepository repo, String deviceId)
      : _repo = repo,
        super(repo.getState(deviceId));

  void update(FanState s) {
    state = s;
    _repo.saveState(s);
  }

  void updatePower(bool powered) {
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = state.speed
      ..isBoost       = state.isBoost
      ..activeMode    = state.activeMode
      ..activeTimerCode = state.activeTimerCode
      ..isPowered     = powered
      ..lastWatts     = state.lastWatts
      ..lastRpm       = state.lastRpm;
    update(s);
  }

  void updateSpeed(int speed) {
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = speed
      ..isBoost       = state.isBoost
      ..activeMode    = state.activeMode
      ..activeTimerCode = state.activeTimerCode
      ..isPowered     = state.isPowered
      ..lastWatts     = state.lastWatts
      ..lastRpm       = state.lastRpm;
    update(s);
  }

  void updateMode(int modeCode) {
    final modeMap = {0x01: 'boost', 0x02: 'nature', 0x03: 'reverse', 0x04: 'smart'};
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = state.speed
      ..isBoost       = modeCode == 0x01
      ..activeMode    = modeCode == 0x01 ? null : modeMap[modeCode]
      ..activeTimerCode = state.activeTimerCode
      ..isPowered     = state.isPowered
      ..lastWatts     = state.lastWatts
      ..lastRpm       = state.lastRpm;
    update(s);
  }

  void updateTimer(int timerCode) {
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = state.speed
      ..isBoost       = state.isBoost
      ..activeMode    = state.activeMode
      ..activeTimerCode = timerCode == 0 ? null : timerCode
      ..isPowered     = state.isPowered
      ..lastWatts     = state.lastWatts
      ..lastRpm       = state.lastRpm;
    update(s);
  }

  void updateWatts(int watts) {
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = state.speed
      ..isBoost       = state.isBoost
      ..activeMode    = state.activeMode
      ..activeTimerCode = state.activeTimerCode
      ..isPowered     = state.isPowered
      ..lastWatts     = watts
      ..lastRpm       = state.lastRpm;
    update(s);
  }

  void updateRpm(int rpm) {
    final s = FanState()
      ..deviceId      = state.deviceId
      ..speed         = state.speed
      ..isBoost       = state.isBoost
      ..activeMode    = state.activeMode
      ..activeTimerCode = state.activeTimerCode
      ..isPowered     = state.isPowered
      ..lastWatts     = state.lastWatts
      ..lastRpm       = rpm;
    update(s);
  }
}

final activeFanStateProvider =
    StateNotifierProvider<ActiveFanStateNotifier, FanState>((ref) {
  final id  = ref.watch(activeFanProvider)?.deviceId ?? '';
  final repo = ref.watch(fanRepositoryProvider);
  return ActiveFanStateNotifier(repo, id);
});
