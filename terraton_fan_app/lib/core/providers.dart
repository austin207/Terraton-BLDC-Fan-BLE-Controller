// lib/core/providers.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

final bluetoothAdapterStateProvider = StreamProvider<BluetoothAdapterState>(
    (_) => FlutterBluePlus.adapterState);

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleServiceImpl();
  ref.onDispose(service.dispose);
  return service;
});

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) =>
    ref.watch(bleServiceProvider).connectionStateStream);

final fanRepositoryProvider = Provider<FanRepository>((ref) => FanRepositoryImpl());

// ObjectBox queries are synchronous by design and run in microseconds.
// FutureProvider keeps the query off the build-call stack.
final savedFansProvider = FutureProvider<List<FanDevice>>((ref) async =>
    ref.watch(fanRepositoryProvider).getAllFans());

// ── Active fan state (mirrors ObjectBox + live BLE updates) ─────────────────
// Uses .family so each fan's notifier is independent and not torn down
// when navigation or provider watches change.

class ActiveFanStateNotifier extends StateNotifier<FanState> {
  final FanRepository _repo;

  ActiveFanStateNotifier(FanRepository repo, String deviceId)
      : _repo = repo,
        super(repo.getState(deviceId));

  void update(FanState s) {
    state = s;
    unawaited(_repo.saveState(s));
  }

  void updatePower(bool powered) => update(state.copyWith(isPowered: powered));

  void updateSpeed(int speed) => update(state.copyWith(speed: speed));

  // Accepts the mode name string from BleResponseParser.parseModeString —
  // byte-to-name mapping lives in BleResponseParser, not here.
  void updateMode(String? modeName) => update(state.copyWith(
    isBoost: modeName == 'boost',
    activeMode: () => modeName == 'boost' ? null : modeName,
  ));

  void updateTimer(int timerCode) => update(state.copyWith(
    activeTimerCode: () => timerCode == 0 ? null : timerCode,
  ));

  void updateWatts(int watts) => update(state.copyWith(lastWatts: () => watts));
  void updateRpm(int rpm)     => update(state.copyWith(lastRpm:   () => rpm));
  void clearWatts()           => update(state.copyWith(lastWatts: () => null));
  void clearRpm()             => update(state.copyWith(lastRpm:   () => null));
}

// autoDispose releases the notifier when no widget is watching it,
// preventing unbounded accumulation across multi-fan sessions.
final activeFanStateProvider =
    StateNotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>(
        (ref, deviceId) {
  final repo = ref.watch(fanRepositoryProvider);
  return ActiveFanStateNotifier(repo, deviceId);
});
