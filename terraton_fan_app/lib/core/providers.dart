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

  // ── Frame → field ──────────────────────────────────────────────────────────
  // One reported byte writes one thing. Nothing here infers a second field from
  // a first: a mode does not imply power, a speed does not imply "no mode".
  // Whatever the fan reports is what the UI shows.
  //
  // Every mutator no-ops when the value is unchanged. The 3 s poll sends both a
  // status poll and a Get Motor State, so ~6 frames arrive per tick; without
  // these guards each one allocates a new FanState (identity-compared, so
  // Riverpod rebuilds the whole screen) and fires an ObjectBox write, forever.

  void updatePower(bool powered) {
    if (state.isPowered == powered) return;
    state = state.copyWith(isPowered: powered);
    _persistOperating();
  }

  void updateSpeed(int speed) {
    if (state.speed == speed) return;
    state = state.copyWith(speed: speed);
    _persistOperating();
  }

  /// Sets which mode chip is lit, from a `0x21` frame's mode name — or clears
  /// it with null.
  ///
  /// `isBoost` and `activeMode` are one UI concept (which chip is lit) stored
  /// in two columns, so writing both is writing one field, not cross-field
  /// inference. A `0x21` frame names exactly one mode, so lighting that one
  /// necessarily unlights the others.
  ///
  /// Deliberately does NOT touch `isPowered`: only a `0x02` frame may do that.
  void setModeHighlight(String? name) {
    final boost = name == 'boost';
    final mode  = boost ? null : name;
    if (state.isBoost == boost && state.activeMode == mode) return;
    state = state.copyWith(isBoost: boost, activeMode: () => mode);
    _persistOperating();
  }

  // The fan reports WHICH duration is active (2H/4H/8H) and, on updated
  // firmware, remaining time (BleResponseParser.parseTimerRemainingSeconds)
  // — but never a start time, so the countdown anchor (timerActivatedAt) is
  // still computed and owned app-side.
  //
  // When [remainingSeconds] is available, it is firmware ground truth for
  // *this instant* and is used to re-derive the anchor directly
  // (endsAt = now + remaining; activatedAt = endsAt - duration) — see
  // _reconcileFromRemaining. This is what closes the reconnect-ambiguity gap:
  // a timer of the same code that was cancelled and re-armed while the app
  // was away now has a different true end time, which shows up as a large
  // jump in the derived endsAt and forces a re-anchor, instead of the old
  // code-only check silently keeping the stale start time.
  //
  // When it isn't available (firmware not yet updated, or the demo path),
  // resolution falls back to the original heuristic:
  //   1. explicit [activatedAt] — the UI passes DateTime.now() on a user tap;
  //   2. the current start time, when the reported code hasn't changed;
  //   3. DateTime.now() — timer discovered mid-flight (e.g. set from the IR
  //      remote while disconnected): count down from detection (upper bound).
  void updateTimer(int timerCode, {DateTime? activatedAt, int? remainingSeconds}) {
    if (timerCode == 0) {
      if (state.activeTimerCode == null && state.timerActivatedAt == null) return;
      state = state.copyWith(
        activeTimerCode:  () => null,
        timerActivatedAt: () => null,
      );
      _persistTimer();
      return;
    }
    final durationHours = switch (timerCode) { 0x02 => 2, 0x04 => 4, _ => 8 };
    DateTime resolved;
    if (remainingSeconds != null) {
      resolved = _reconcileFromRemaining(timerCode, durationHours, remainingSeconds);
    } else {
      resolved = activatedAt
          ?? (state.activeTimerCode == timerCode ? state.timerActivatedAt : null)
          ?? DateTime.now();
      // Sanity: the firmware says this timer is ACTIVE, so a start time
      // implying it already expired is wrong (e.g. a stale persisted value
      // from a previous run of the same duration) — count from detection.
      if (DateTime.now().difference(resolved) >= Duration(hours: durationHours)) {
        resolved = DateTime.now();
      }
    }
    if (state.activeTimerCode == timerCode && state.timerActivatedAt == resolved) {
      return;
    }
    state = state.copyWith(
      activeTimerCode:  () => timerCode,
      timerActivatedAt: () => resolved,
    );
    _persistTimer();
  }

  // Firmware quantizes remaining time to its own ~10s tick (AutoPowerState.
  // CurrentTime, IRScan.c AutoPowerControl()), so re-deriving `now + remaining`
  // on every 3 s poll wobbles by up to that tick even while the SAME timer
  // keeps running — recomputing the anchor on every wobble would both jitter
  // the on-screen countdown and defeat the mutator no-op guard (a write every
  // poll, forever, while a timer is armed). So this only re-anchors when
  // there is no comparable existing anchor, or the firmware-derived end time
  // has drifted from it by more than the tick noise can explain — which is
  // exactly the signature of a genuinely different timer (cancelled +
  // re-armed while disconnected), not the same one still counting down.
  //
  // Threshold set well above the ~10s tick (was 3 minutes when firmware only
  // reported 2-minute buckets; tightened once the 3-byte/raw-10s-tick
  // firmware landed) so it still catches a real re-arm quickly without
  // reacting to normal reporting noise.
  DateTime _reconcileFromRemaining(
      int timerCode, int durationHours, int remainingSeconds) {
    final firmwareEndsAt =
        DateTime.now().add(Duration(seconds: remainingSeconds));
    final sameCode = state.activeTimerCode == timerCode;
    final currentEndsAt = sameCode && state.timerActivatedAt != null
        ? state.timerActivatedAt!.add(Duration(hours: durationHours))
        : null;
    if (currentEndsAt == null ||
        firmwareEndsAt.difference(currentEndsAt).abs() >
            const Duration(seconds: 30)) {
      return firmwareEndsAt.subtract(Duration(hours: durationHours));
    }
    return state.timerActivatedAt!;
  }

  /// Blanks the instantaneous readings on (re)connect so a reconnect never
  /// shows watts/RPM from before the gap. Display-only: assigns `state`
  /// without persisting.
  ///
  /// Operating state (power, speed, mode) is deliberately NOT blanked. The app
  /// disconnects on every background and reconnects on every resume, so
  /// blanking it here would collapse the dial visibly on every single resume
  /// while the poll refilled it. Watts and RPM are instantaneous and genuinely
  /// cannot be stale-displayed; power/speed/mode are the fan's own memory and
  /// are very likely still correct. The sleep timer is untouched — the
  /// countdown ticks from its persisted start time straight through the gap.
  void resetTelemetryOnConnect() {
    state = state.copyWith(
      lastWatts: () => null,
      lastRpm:   () => null,
    );
  }

  /// Applied when a `0x02` frame reports the fan is OFF.
  ///
  /// Clearing the mode chips and the timer is not inference — the firmware's
  /// power-off branch runs `ClearModes()` and `FlagAutoPower = 0`, so those
  /// really are gone in the fan. `speed` is deliberately KEPT: the firmware
  /// preserves `OldTargetSpeed` across off/on and restores it on power-on, an
  /// OFF state reply reports that stored speed in frame [2], and clearing it
  /// here would fight that frame two bytes later in the same burst.
  void applyPowerOff() {
    if (!state.isPowered &&
        !state.isBoost &&
        state.activeMode == null &&
        state.activeTimerCode == null) {
      return;
    }
    state = state.copyWith(
      isPowered:        false,
      isBoost:          false,
      activeMode:       () => null,
      activeTimerCode:  () => null,
      timerActivatedAt: () => null,
    );
    _persistOperating();
    _persistTimer();
  }

  void updateWatts(int watts) {
    if (state.lastWatts == watts) return;
    state = state.copyWith(lastWatts: () => watts);
    _persistTelemetry();
  }

  void updateRpm(int rpm) {
    if (state.lastRpm == rpm) return;
    state = state.copyWith(lastRpm: () => rpm);
    _persistTelemetry();
  }

  void updateRuntime(int secs) {
    if (state.lastRuntimeSecs == secs) return;
    state = state.copyWith(lastRuntimeSecs: () => secs);
    _persistTelemetry();
  }

  void clearWatts() {
    if (state.lastWatts == null) return;
    state = state.copyWith(lastWatts: () => null);
    _persistTelemetry();
  }

  void clearRpm() {
    if (state.lastRpm == null) return;
    state = state.copyWith(lastRpm: () => null);
    _persistTelemetry();
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
