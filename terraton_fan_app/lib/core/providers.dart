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

  // ── Persistence ────────────────────────────────────────────────────────────
  // Every mutator persists ONLY its own field group through FanRepository's
  // scoped writers. There is deliberately no whole-row persist: the old
  // update() wrote the entire FanState on every mutation, so any write that
  // followed resetOnConnect()'s display blank — a watts or runtime frame from
  // the connect burst — carried the blank into ObjectBox and destroyed the
  // last-known-good state the reconnect logic depended on. Scoped writes make
  // that bug class unexpressible rather than guarded-against.

  /// Fire-and-forget persist; the assert surfaces failures in debug builds.
  void _persist(Future<void> op) {
    unawaited(op.onError((e, st) {
      assert(false, 'ObjectBox persist failed: $e\n$st');
    }));
  }

  void _persistOperating() => _persist(_repo.saveOperatingState(
        arg,
        isPowered:  state.isPowered,
        isBoost:    state.isBoost,
        speed:      state.speed,
        activeMode: state.activeMode,
      ));

  void _persistTimer() => _persist(_repo.saveTimerState(
        arg,
        activeTimerCode:  state.activeTimerCode,
        timerActivatedAt: state.timerActivatedAt,
      ));

  void _persistTelemetry() => _persist(_repo.saveTelemetry(
        arg,
        lastWatts:       state.lastWatts,
        lastRpm:         state.lastRpm,
        lastRuntimeSecs: state.lastRuntimeSecs,
      ));

  void _persistLighting() => _persist(_repo.saveLighting(
        arg,
        colorType:  state.lastLightColorType,
        brightness: state.lastLightBrightness,
        isOn:       state.lastLightIsOn,
      ));

  void updatePower(bool powered) {
    state = state.copyWith(isPowered: powered);
    _persistOperating();
  }

  void updateSpeed(int speed) {
    state = state.copyWith(speed: speed);
    _persistOperating();
  }

  // Accepts the mode name string from BleResponseParser.parseModeString.
  // Boost is mutually exclusive with ALL modes (Nature, Smart, Reverse) —
  // matching the firmware's Machine-State model where frame [2] reports exactly
  // one active state. A 'boost' notification clears any active mode; any mode
  // notification clears isBoost.
  void updateMode(String? modeName) {
    switch (modeName) {
      case 'boost':
        // Hardware confirmed boost — set isBoost. An active mode means the fan
        // is running, so mark it powered (a Boost from the remote must ungrey
        // the UI and turn the power button green). Boost replaces any active
        // mode highlight — including Reverse.
        state = state.copyWith(
          isPowered: true,
          isBoost: true,
          activeMode: () => null,
        );
      case 'nature':
        // Nature is mutually exclusive with boost. Active mode ⇒ powered.
        state = state.copyWith(isPowered: true, isBoost: false, activeMode: () => 'nature');
      case 'smart':
        // Smart is mutually exclusive with boost; clear isBoost. Active mode ⇒ powered.
        state = state.copyWith(isPowered: true, isBoost: false, activeMode: () => 'smart');
      case null:
        // Fan reported no active mode — clear both. No power assumption here.
        state = state.copyWith(isBoost: false, activeMode: () => null);
      default:
        // 'reverse' — clears isBoost (symmetric exclusivity). Active mode ⇒ powered.
        state = state.copyWith(isPowered: true, isBoost: false, activeMode: () => modeName);
    }
    _persistOperating();
  }

  // The fan only reports WHICH duration is active (2H/4H/8H), never the time
  // remaining, so the countdown start timestamp is app-side. Resolution order:
  //   1. explicit [activatedAt] — the UI passes DateTime.now() on a user tap;
  //   2. the current start time, when the reported code hasn't changed —
  //      resetOnConnect() never touches the timer, so this also confirms the
  //      running countdown across reconnects;
  //   3. DateTime.now() — timer discovered mid-flight (e.g. set from the IR
  //      remote while disconnected): count down from detection (upper bound).
  void updateTimer(int timerCode, {DateTime? activatedAt}) {
    if (timerCode == 0) {
      state = state.copyWith(
        activeTimerCode:  () => null,
        timerActivatedAt: () => null,
      );
      _persistTimer();
      return;
    }
    var resolved = activatedAt
        ?? (state.activeTimerCode == timerCode ? state.timerActivatedAt : null)
        ?? DateTime.now();
    // Sanity: the firmware says this timer is ACTIVE, so a start time implying
    // it already expired is wrong (e.g. a stale persisted value from a previous
    // run of the same duration) — fall back to counting from detection.
    final durationHours = switch (timerCode) { 0x02 => 2, 0x04 => 4, _ => 8 };
    if (DateTime.now().difference(resolved) >= Duration(hours: durationHours)) {
      resolved = DateTime.now();
    }
    state = state.copyWith(
      activeTimerCode:  () => timerCode,
      timerActivatedAt: () => resolved,
    );
    _persistTimer();
  }

  /// Blanks volatile connection-state fields so reconnects don't show stale
  /// data; the Machine-State sync then restores the actual values.
  /// Display-only BY CONSTRUCTION: this assigns `state` without persisting,
  /// and every mutator persists only its own field group — so no later write
  /// of any kind can carry this blank into ObjectBox. (Under the old
  /// whole-row persist, the first telemetry frame after this call re-wrote
  /// the blanked operating fields to the DB — the root of the reconnect
  /// state-loss field bug.)
  ///
  /// The sleep timer is deliberately NOT cleared: the countdown keeps ticking
  /// from the persisted start time across the reconnect, and the Machine State
  /// timer frame (0x22) then confirms it (same code keeps the start time via
  /// updateTimer's current-state rule) or corrects it (OFF or code 0 clears; a
  /// different code restarts from detection).
  void resetOnConnect() {
    state = state.copyWith(
      isPowered:  false,
      isBoost:    false,
      activeMode: () => null,
      speed:      0,
      lastWatts:  () => null,
      lastRpm:    () => null,
    );
  }

  /// Applied when Motor State frame [1] (0x02) reports the fan is powered OFF.
  /// Clears all operating state atomically — speed, mode, and boost are
  /// undefined when the fan is off; do not preserve previous-session values.
  void applyMotorStatePowerOff() {
    state = state.copyWith(
      isPowered:  false,
      isBoost:    false,
      activeMode: () => null,
      speed:      0,
      lastWatts:  () => null,
      lastRpm:    () => null,
    );
    _persistOperating();
    _persistTelemetry();
  }

  void updateWatts(int watts) {
    state = state.copyWith(lastWatts: () => watts);
    _persistTelemetry();
  }

  void updateRpm(int rpm) {
    state = state.copyWith(lastRpm: () => rpm);
    _persistTelemetry();
  }

  void updateRuntime(int secs) {
    state = state.copyWith(lastRuntimeSecs: () => secs);
    _persistTelemetry();
  }

  void clearWatts() {
    state = state.copyWith(lastWatts: () => null);
    _persistTelemetry();
  }

  void clearRpm() {
    state = state.copyWith(lastRpm: () => null);
    _persistTelemetry();
  }

  /// Toggle boost. Nature mode blocks boost activation (the UI clears Nature
  /// first). Activating boost exits ANY active mode — Boost is mutually
  /// exclusive with Nature, Smart, and Reverse.
  void setBoostActive(bool on) {
    if (on && state.activeMode == 'nature') return;
    state = state.copyWith(
      isBoost: on,
      activeMode: () => on ? null : state.activeMode,
    );
    _persistOperating();
  }

  /// Activate or clear a non-boost mode. Every mode (Nature, Smart, Reverse)
  /// clears boost — Boost is mutually exclusive with all of them.
  void setActiveMode(String? mode) {
    state = state.copyWith(
      isBoost: mode != null ? false : state.isBoost,
      activeMode: () => mode,
    );
    _persistOperating();
  }

  /// Applied when Motor State (getMotorState) frame [2] is received.
  /// Frame [2] is the exclusive truth: one speed OR one special mode is active,
  /// never both simultaneously. Clears all other mode state atomically.
  void applyMotorStateTruth(String? mode) {
    switch (mode) {
      case 'boost':
        state = state.copyWith(isBoost: true, activeMode: () => null);
      case null:
        // Speed was frame [2] — fan is in plain speed mode, no special mode active.
        state = state.copyWith(isBoost: false, activeMode: () => null);
      default: // 'nature', 'smart', 'reverse'
        state = state.copyWith(isBoost: false, activeMode: () => mode);
    }
    _persistOperating();
  }

  void updateLighting({
    required String colorType,
    required double brightness,
    required bool isOn,
  }) {
    state = state.copyWith(
      lastLightColorType:  colorType,
      lastLightBrightness: brightness,
      lastLightIsOn:       isOn,
    );
    _persistLighting();
  }
}

// autoDispose releases the notifier when no widget is watching it,
// preventing unbounded accumulation across multi-fan sessions.
final activeFanStateProvider =
    NotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>(
        ActiveFanStateNotifier.new);
