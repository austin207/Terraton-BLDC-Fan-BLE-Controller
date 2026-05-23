// lib/core/providers.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/core/storage/objectbox_store.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

final packageInfoProvider = FutureProvider<PackageInfo>(
    (_) => PackageInfo.fromPlatform());

// ── User name ─────────────────────────────────────────────────────────────────
// Persisted to app_settings.json via AppSettings. Loaded lazily by build().

class UserNameNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    try {
      return await AppSettings.loadUserName();
    } on Exception {
      return '';
    }
  }

  Future<void> save(String name) async {
    await AppSettings.saveUserName(name);
    state = AsyncData(name);
  }
}

final userNameProvider =
    AsyncNotifierProvider<UserNameNotifier, String>(UserNameNotifier.new);

// ── BLE ───────────────────────────────────────────────────────────────────────

final bluetoothAdapterStateProvider = StreamProvider<BluetoothAdapterState>(
    (_) => FlutterBluePlus.adapterState);

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleServiceImpl();
  ref.onDispose(service.dispose);
  return service;
});

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) =>
    ref.watch(bleServiceProvider).connectionStateStream);

// ── Fan repository ────────────────────────────────────────────────────────────
// Injects the already-initialised ObjectBox store so tests can swap it out.

final fanRepositoryProvider = Provider<FanRepository>(
    (_) => FanRepositoryImpl(store));

final usageLogRepositoryProvider = Provider<UsageLogRepository>(
    (_) => UsageLogRepositoryImpl(store));

// ObjectBox queries are synchronous by design and run in microseconds.
// FutureProvider keeps the query off the build-call stack.
final savedFansProvider = FutureProvider<List<FanDevice>>((ref) async =>
    ref.watch(fanRepositoryProvider).getAllFans());

// ── Active fan state (mirrors ObjectBox + live BLE updates) ──────────────────
// Uses .family so each fan's notifier is independent and not torn down
// when navigation or provider watches change.

class ActiveFanStateNotifier extends AutoDisposeFamilyNotifier<FanState, String> {
  late FanRepository _repo;

  @override
  FanState build(String deviceId) {
    _repo = ref.watch(fanRepositoryProvider);
    return _repo.getState(deviceId);
  }

  void update(FanState s) {
    state = s;
    // Fire-and-forget persist; assert catches failures in debug builds.
    unawaited(_repo.saveState(s).onError((e, st) {
      assert(false, 'ObjectBox saveState failed: $e\n$st');
    }));
  }

  void updatePower(bool powered) => update(state.copyWith(isPowered: powered));

  void updateSpeed(int speed) => update(state.copyWith(speed: speed));

  // Accepts the mode name string from BleResponseParser.parseModeString.
  // Boost and activeMode are independent: receiving a 'smart'/'reverse'
  // notification preserves isBoost, and receiving 'boost' preserves activeMode.
  // This allows BOOST + SMART/REVERSE to coexist in UI state even when the
  // hardware can only execute one mode at a time.
  void updateMode(String? modeName) {
    switch (modeName) {
      case 'boost':
        // Hardware confirmed boost — set isBoost.
        // Nature is mutually exclusive with boost; clear it.
        // Smart/reverse can coexist (BOOST + SMART, BOOST + REVERSE).
        update(state.copyWith(
          isBoost: true,
          activeMode: () => state.activeMode == 'nature' ? null : state.activeMode,
        ));
      case 'nature':
        // Nature is mutually exclusive with boost.
        update(state.copyWith(isBoost: false, activeMode: () => 'nature'));
      case null:
        // Fan reported no active mode — clear both.
        update(state.copyWith(isBoost: false, activeMode: () => null));
      default:
        // 'smart' or 'reverse' — preserve isBoost so boost UI stays active.
        update(state.copyWith(activeMode: () => modeName));
    }
  }

  void updateTimer(int timerCode) => update(state.copyWith(
    activeTimerCode: () => timerCode == 0 ? null : timerCode,
  ));

  void updateWatts(int watts) => update(state.copyWith(lastWatts: () => watts));
  void updateRpm(int rpm)     => update(state.copyWith(lastRpm:   () => rpm));
  void clearWatts()           => update(state.copyWith(lastWatts: () => null));
  void clearRpm()             => update(state.copyWith(lastRpm:   () => null));

  /// Toggle boost only — does NOT touch activeMode.
  /// Nature mode blocks boost activation.
  void setBoostActive(bool on) {
    if (on && state.activeMode == 'nature') return;
    update(state.copyWith(isBoost: on));
  }

  /// Activate or clear a non-boost mode without disturbing isBoost,
  /// EXCEPT nature which explicitly clears boost.
  void setActiveMode(String? mode) => update(state.copyWith(
    isBoost: mode == 'nature' ? false : state.isBoost,
    activeMode: () => mode,
  ));
}

// autoDispose releases the notifier when no widget is watching it,
// preventing unbounded accumulation across multi-fan sessions.
final activeFanStateProvider =
    NotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>(
        ActiveFanStateNotifier.new);
