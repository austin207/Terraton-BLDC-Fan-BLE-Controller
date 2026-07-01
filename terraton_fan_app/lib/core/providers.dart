// lib/core/providers.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/daily_runtime_repository.dart';
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

final dailyRuntimeRepositoryProvider = Provider<DailyRuntimeRepository>(
    (_) => DailyRuntimeRepositoryImpl(store));

// ObjectBox queries are synchronous by design and run in microseconds.
// FutureProvider keeps the query off the build-call stack.
final savedFansProvider = FutureProvider<List<FanDevice>>((ref) async =>
    ref.watch(fanRepositoryProvider).getAllFans());

// Tracks the deviceId of the fan the control screen is currently connected to.
// Set by _ControlScreenState on connect; cleared on dispose. Allows the
// analytics screen to watch live state without knowing the deviceId up front.
final connectedFanDeviceIdProvider = StateProvider<String?>((ref) => null);

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
  // Boost is mutually exclusive with Nature and Smart, but may coexist with
  // Reverse. So a 'boost' notification clears an active Nature/Smart mode (but
  // keeps Reverse), and a 'smart' notification clears isBoost. A 'reverse'
  // notification preserves isBoost (BOOST + REVERSE is allowed).
  void updateMode(String? modeName) {
    switch (modeName) {
      case 'boost':
        // Hardware confirmed boost — set isBoost. An active mode means the fan
        // is running, so mark it powered (a Boost from the remote must ungrey
        // the UI and turn the power button green).
        // Boost is mutually exclusive with Nature and Smart; clear either.
        // Reverse may coexist (BOOST + REVERSE).
        update(state.copyWith(
          isPowered: true,
          isBoost: true,
          activeMode: () => (state.activeMode == 'nature' || state.activeMode == 'smart')
              ? null
              : state.activeMode,
        ));
      case 'nature':
        // Nature is mutually exclusive with boost. Active mode ⇒ powered.
        update(state.copyWith(isPowered: true, isBoost: false, activeMode: () => 'nature'));
      case 'smart':
        // Smart is mutually exclusive with boost; clear isBoost. Active mode ⇒ powered.
        update(state.copyWith(isPowered: true, isBoost: false, activeMode: () => 'smart'));
      case null:
        // Fan reported no active mode — clear both. No power assumption here.
        update(state.copyWith(isBoost: false, activeMode: () => null));
      default:
        // 'reverse' — preserve isBoost so boost UI stays active (coexists).
        // Active mode ⇒ powered.
        update(state.copyWith(isPowered: true, activeMode: () => modeName));
    }
  }

  // activatedAt should be passed only from the UI (when the user taps a timer
  // button). BLE response handlers leave it null so the existing start time is
  // preserved — the fan only reports which duration is active, not time remaining.
  void updateTimer(int timerCode, {DateTime? activatedAt}) => update(state.copyWith(
    activeTimerCode:  () => timerCode == 0 ? null : timerCode,
    timerActivatedAt: () => timerCode == 0 ? null : (activatedAt ?? state.timerActivatedAt),
  ));

  /// Clears volatile connection-state fields so reconnects don't show stale data.
  /// The Machine State response updates them back to actual values within ~100 ms.
  /// The timer is cleared too so a stale persisted value can't flash before the
  /// Machine State timer frame (0x22) lands — firmware is authoritative on connect.
  void resetOnConnect() => update(state.copyWith(
    isPowered:        false,
    isBoost:          false,
    activeMode:       () => null,
    speed:            0,
    lastWatts:        () => null,
    lastRpm:          () => null,
    activeTimerCode:  () => null,
    timerActivatedAt: () => null,
  ));

  /// Applied when Motor State frame [1] (0x02) reports the fan is powered OFF.
  /// Clears all operating state atomically — speed, mode, and boost are
  /// undefined when the fan is off; do not preserve previous-session values.
  void applyMotorStatePowerOff() => update(state.copyWith(
    isPowered:  false,
    isBoost:    false,
    activeMode: () => null,
    speed:      0,
    lastWatts:  () => null,
    lastRpm:    () => null,
  ));

  void updateWatts(int watts)       => update(state.copyWith(lastWatts:       () => watts));
  void updateRpm(int rpm)           => update(state.copyWith(lastRpm:         () => rpm));
  void updateRuntime(int secs)      => update(state.copyWith(lastRuntimeSecs: () => secs));
  void clearWatts()                 => update(state.copyWith(lastWatts:       () => null));
  void clearRpm()                   => update(state.copyWith(lastRpm:         () => null));

  /// Toggle boost. Nature mode blocks boost activation (the UI clears Nature
  /// first). Activating boost also exits Smart — Smart and Boost are mutually
  /// exclusive — but leaves Reverse untouched (BOOST + REVERSE may coexist).
  void setBoostActive(bool on) {
    if (on && state.activeMode == 'nature') return;
    update(state.copyWith(
      isBoost: on,
      activeMode: () => (on && state.activeMode == 'smart') ? null : state.activeMode,
    ));
  }

  /// Activate or clear a non-boost mode. Nature and Smart both clear boost
  /// (mutually exclusive with it); Reverse preserves isBoost (may coexist).
  void setActiveMode(String? mode) => update(state.copyWith(
    isBoost: (mode == 'nature' || mode == 'smart') ? false : state.isBoost,
    activeMode: () => mode,
  ));

  /// Applied when Motor State (getMotorState) frame [2] is received.
  /// Frame [2] is the exclusive truth: one speed OR one special mode is active,
  /// never both simultaneously. Clears all other mode state atomically.
  void applyMotorStateTruth(String? mode) {
    switch (mode) {
      case 'boost':
        update(state.copyWith(isBoost: true, activeMode: () => null));
      case null:
        // Speed was frame [2] — fan is in plain speed mode, no special mode active.
        update(state.copyWith(isBoost: false, activeMode: () => null));
      default: // 'nature', 'smart', 'reverse'
        update(state.copyWith(isBoost: false, activeMode: () => mode));
    }
  }

  void updateLighting({
    required String colorType,
    required double brightness,
    required bool isOn,
  }) => update(state.copyWith(
    lastLightColorType:  colorType,
    lastLightBrightness: brightness,
    lastLightIsOn:       isOn,
  ));
}

// autoDispose releases the notifier when no widget is watching it,
// preventing unbounded accumulation across multi-fan sessions.
final activeFanStateProvider =
    NotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>(
        ActiveFanStateNotifier.new);
