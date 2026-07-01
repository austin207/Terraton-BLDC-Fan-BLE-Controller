// lib/features/control/control_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/ble/ble_frame_builder.dart';
import 'package:terraton_fan_app/core/ble/ble_response_parser.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/features/control/connection_banner.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';
import 'package:terraton_fan_app/features/control/lighting_control_widget.dart';
import 'package:terraton_fan_app/core/background/ble_foreground_service.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Callback type for sending a BLE frame from the controls panel.
typedef _SendFn = Future<void> Function(
  List<int>? frame, {
  String? pendingMsg,
  String label,
});

// ── Control screen ────────────────────────────────────────────────────────────

class ControlScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const ControlScreen({super.key, required this.fan});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with WidgetsBindingObserver {
  Timer? _telemetryTimer;
  Timer? _expiryTimer;
  Timer? _expiryOnceTimer;
  Timer? _motorStateTimer;
  Timer? _runtimeTimer;
  StreamSubscription<List<int>>? _notifySub;
  late BleService _ble;
  // Cached to allow clearing connectedFanDeviceIdProvider in dispose()
  // (ref.read() is forbidden inside dispose() in Riverpod 2.x).
  late StateController<String?> _connectedFanCtrl;
  DateTime? _lastWattsAt;
  DateTime? _lastRpmAt;
  Duration  _serviceRemaining = Duration.zero;
  // Suppresses incoming power=false BLE frames for 1.5 s after the app sends a
  // powerOn command. Prevents the initial motor-state response (queued at connect
  // time, before the powerOn frame reaches the fan) from overriding the
  // user-initiated optimistic isPowered=true back to false.
  bool   _recentlyPoweredOn      = false;
  Timer? _recentlyPoweredOnTimer;

  // Set while we are waiting for the response to a getMotorState poll WE sent
  // (on connect or via _requestMotorState). Lets the notify handler tell our own
  // poll's echo apart from a spontaneous power frame broadcast by the remote, so
  // the rescue poll fires for the latter but never loops on the former. Cleared
  // when a motor-state response arrives, with a timeout as a safety net.
  bool   _awaitingMotorState     = false;
  Timer? _awaitingMotorStateTimer;

  // Drives the post-wake motor-state poll retries (see _scheduleWakePolls).
  // A single rescue poll is not enough when the fan was woken right after a
  // mains power-cycle: its MCU has just rebooted and isn't ready to answer the
  // first query, so we retry until the gear/mode is known.
  Timer? _wakePollTimer;
  int    _wakePollAttempts = 0;

  // Drives the on-(re)connect motor-state poll retries (see _scheduleConnectPolls).
  // Set true the moment a real motor-state response lands, so the connect poll
  // can stop. A single connect poll is lost if the reconnect happens while the
  // fan MCU is still booting after a mains power-cycle, leaving the dial blank.
  Timer? _connectPollTimer;
  int    _connectPollAttempts = 0;
  bool   _motorStateReceived  = false;

  // Machine State response assembler. A getMotorState reply is always 3 frames —
  // power (0x02), speed (0x04) OR mode (0x21), and timer (0x22) — but the BLE60
  // bridge may split or reorder them across notifications, especially from a
  // freshly-rebooted MCU after a mains power-cycle. Applying frames live then
  // makes the speed/mode gate (which needs power first) drop the speed. Instead,
  // while _awaitingMotorState we buffer these frames and apply them atomically
  // once complete (or after a short debounce), independent of arrival order.
  bool?   _msPower;
  int?    _msSpeed;
  String? _msMode;
  int?    _msTimer;
  Timer?  _msFlushTimer;

  // Tracks the resolved MAC without mutating widget.fan (which is immutable).
  // Populated from widget.fan.macAddress on init; updated after first discovery.
  String? _resolvedMac;

  bool _connecting = false;
  bool _showDisconnectAlert = false;

  // Debug state isolated in a ValueNotifier so only _DebugCard rebuilds on
  // each BLE notification — not the entire ControlScreen.
  final _debug = ValueNotifier(const _DebugSnapshot());

  bool get _isDemo => widget.fan.deviceId == kDemoDeviceId;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    _connectedFanCtrl = ref.read(connectedFanDeviceIdProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _resolvedMac = widget.fan.macAddress.isNotEmpty ? widget.fan.macAddress : null;
    if (!_isDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
    if (widget.fan.isServiceAccess) _scheduleServiceExpiry();
  }

  void _scheduleServiceExpiry() {
    final expiry = widget.fan.serviceExpiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_handleServiceExpiry()));
      return;
    }
    setState(() => _serviceRemaining = remaining);
    // Update the banner every 30 s; fire exact expiry via a one-shot Timer.
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final rem = expiry.difference(DateTime.now());
      if (rem.isNegative) {
        _expiryTimer?.cancel();
        unawaited(_handleServiceExpiry());
      } else {
        setState(() => _serviceRemaining = rem);
      }
    });
    // One-shot to fire precisely at expiry even between 30 s ticks.
    _expiryOnceTimer = Timer(remaining, () {
      if (mounted) unawaited(_handleServiceExpiry());
    });
  }

  Future<void> _handleServiceExpiry() async {
    _expiryTimer?.cancel();
    if (!mounted) return;
    if (!_isDemo) unawaited(_ble.disconnect());
    await ref.read(fanRepositoryProvider).deleteFan(widget.fan.deviceId);
    if (!mounted) return;
    ref.invalidate(savedFansProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Service access has expired. Fan disconnected.')),
    );
    context.go(AppRoutes.home);
  }

  void _promptBlePairing() {
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth Not Linked'),
        content: const Text(
          'This fan was added via QR code and has not been paired via Bluetooth yet. '
          'Scan for the fan to connect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(context.push(AppRoutes.scanBle));
            },
            child: const Text('Scan for Fan'),
          ),
        ],
      ),
    ));
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final mac = _resolvedMac;
    if (mac == null) {
      if (mounted) _promptBlePairing();
      return;
    }

    _connecting = true;
    try {
      final returnedMac = await _ble.connect(mac);
      if (!mounted) return;

      if (widget.fan.macAddress.isEmpty && !_isDemo) {
        final repo = ref.read(fanRepositoryProvider);
        await repo.updateMac(widget.fan.deviceId, returnedMac);
        _resolvedMac = returnedMac; // local state — widget.fan is not mutated
        if (!mounted) return;
        ref.invalidate(savedFansProvider);
      }

      _lastWattsAt = null;
      _lastRpmAt   = null;
      _connectedFanCtrl.state = widget.fan.deviceId;
      // Reset volatile state so stale data from the previous session doesn't
      // persist. Motor state response corrects to actual values within ~100 ms.
      ref.read(activeFanStateProvider(widget.fan.deviceId).notifier).resetOnConnect();
      _startTelemetry();
      _subscribeNotify();
      _startRuntimePoll();
      // Pull full motor state so the dial reflects the fan's real gear/mode the
      // moment the app reopens and reconnects. Retrying (not a single poll):
      // if the reconnect lands while the fan MCU is still booting after a mains
      // power-cycle, the first query is dropped and the dial would stay blank.
      _scheduleConnectPolls();
      try {
        await _ble.writeFrame(BleFrameBuilder.queryRuntime());
      } on Object catch (_) {
        // Fan disconnected before initial sync; reconnection retries cover it.
      }
    } on Object catch (_) {
      // Expected connection Exception — connectionStateStream emits disconnected,
      // surfacing the ConnectionLostCard with a Retry button.
    } finally {
      if (mounted) _connecting = false;
    }
  }

  /// Fire-and-forget request for the fan's full motor state (power/speed/mode/
  /// timer). Used to refresh the dial when the fan is woken via the remote and
  /// the spontaneous frame lacks speed/mode. Errors are swallowed — the
  /// connection state stream surfaces any real disconnect.
  void _requestMotorState() {
    _markAwaitingMotorState();
    unawaited(_ble.writeFrame(BleFrameBuilder.getMotorState()).catchError((Object _) {}));
  }

  /// Marks that we are expecting a motor-state response to a poll we just sent,
  /// so its echo can't re-trigger another poll. The timeout is a safety net in
  /// case the response never arrives (e.g. fan dropped mid-poll).
  void _markAwaitingMotorState() {
    _awaitingMotorState = true;
    _awaitingMotorStateTimer?.cancel();
    _awaitingMotorStateTimer = Timer(const Duration(milliseconds: 1500), () {
      _awaitingMotorState = false;
    });
  }

  /// Polls motor state after the fan is woken by the remote, retrying until the
  /// gear/mode is actually known.
  ///
  /// When mains is cut and restored, the fan MCU reboots. Pressing ON on the
  /// remote makes the fan broadcast a bare power-ON frame (→ power button turns
  /// green) but the just-booted MCU is not yet ready to answer a motor-state
  /// query, so the very first rescue poll comes back without a usable speed.
  /// A single-shot poll then leaves the dial blank forever, because the only
  /// recurring poll (the 3 s status poll) carries watts/RPM, never speed.
  /// Poll immediately, then retry every 1.5 s until the gear or an active mode
  /// resolves (or the fan is switched back off), giving the MCU time to wake.
  void _scheduleWakePolls() {
    _wakePollTimer?.cancel();
    _wakePollAttempts = 0;
    _resetMachineStateBuffer();
    _requestMotorState();
    _wakePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _ble.currentState != BleConnectionState.connected) {
        t.cancel();
        _wakePollTimer = null;
        return;
      }
      final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
      // Resolved (gear or mode known) or fan turned back off — stop polling.
      if (!s.isPowered || s.speed > 0 || s.activeMode != null) {
        t.cancel();
        _wakePollTimer = null;
        return;
      }
      // Give the rebooted MCU ~6 s (4 retries) to become responsive, then stop.
      if (++_wakePollAttempts > 4) {
        t.cancel();
        _wakePollTimer = null;
        return;
      }
      _requestMotorState();
    });
  }

  /// Fetches motor state on (re)connect, retrying until a real response lands.
  ///
  /// Called once per successful connect (app reopen, resume, Retry). A single
  /// poll is fragile: if the reconnect happens right after a mains power-cycle
  /// the fan MCU may still be booting and won't answer the first query, leaving
  /// the dial blank until the user touches the remote. Unlike _scheduleWakePolls
  /// we cannot use the dial state as the stop signal here — resetOnConnect() has
  /// just blanked it to isPowered=false/speed=0, which is indistinguishable from
  /// a genuine "fan off" until a response actually arrives. So stop on the
  /// dedicated _motorStateReceived flag (set when any motor-state frame lands,
  /// powered or off — either is the truth), or after a ~6 s cap.
  void _scheduleConnectPolls() {
    _connectPollTimer?.cancel();
    _connectPollAttempts = 0;
    _motorStateReceived  = false;
    _resetMachineStateBuffer();
    _requestMotorState();
    _connectPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _ble.currentState != BleConnectionState.connected) {
        t.cancel();
        _connectPollTimer = null;
        return;
      }
      // A motor-state response (on or off) has landed — we have the truth.
      if (_motorStateReceived) {
        t.cancel();
        _connectPollTimer = null;
        return;
      }
      // Give the rebooted MCU ~6 s (4 retries) to become responsive, then stop.
      if (++_connectPollAttempts > 4) {
        t.cancel();
        _connectPollTimer = null;
        return;
      }
      _requestMotorState();
    });
  }

  void _subscribeNotify() {
    // Assign new subscription before cancelling old one so no events are
    // missed between cancel and listen on the broadcast stream.
    final old = _notifySub;
    _notifySub = _ble.notifyStream.listen((bytes) {
      if (!mounted) return;
      _debug.value = _debug.value.copyWith(receivedFrame: bytes);

      // Hardware sometimes concatenates multiple frames in one notification
      // (e.g. mode frame + RPM frame). Parse all frames present.
      final responses = BleResponseParser.parseAll(bytes);
      if (responses.isEmpty) return;

      final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);

      // While awaiting the reply to a getMotorState poll WE sent, assemble its
      // frames atomically (see _bufferMachineState) instead of applying them live.
      // A Machine State reply is always 3 frames (power, speed-or-mode, timer) but
      // the BLE60 bridge — especially a freshly-rebooted MCU after a mains cycle —
      // may split or reorder them across notifications, which would defeat the
      // live speed/mode gate below (it needs the power frame applied first).
      if (_awaitingMotorState) {
        _bufferMachineState(responses, notifier);
        return;
      }

      // A getMotorState response always contains a timer frame (0x22) alongside
      // the power and speed/mode frames. Status-poll responses only contain
      // watts (0x23) and RPM (0x24) — never a timer. Use this to distinguish.
      final isMotorStateResponse =
          responses.any((r) => BleResponseParser.parseTimer(r) != null);

      for (final response in responses) {
        final power = BleResponseParser.parsePowerState(response);
        if (power != null) {
          // Ignore power=false frames while _recentlyPoweredOn is set — a stale
          // motor-state response (sent before the fan received powerOn) must not
          // race back and cancel the user-initiated power-on.
          if (power == false && _recentlyPoweredOn) { continue; }
          if (isMotorStateResponse && power == false) {
            // Motor State frame [1] = OFF: fan is powered down.
            // Clear ALL operating state — speed, mode, and boost are undefined
            // when the fan is off; do not show any stale previous-session values.
            notifier.applyMotorStatePowerOff();
            if (!_isDemo) unawaited(BleForegroundService.stop());
          } else {
            final wasPowered =
                ref.read(activeFanStateProvider(widget.fan.deviceId)).isPowered;
            notifier.updatePower(power);
            if (!_isDemo) {
              if (power) {
                final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
                final label = s.speed > 0 ? 'Speed ${s.speed}' : 'Fan running';
                unawaited(BleForegroundService.start(label));
              } else {
                unawaited(BleForegroundService.stop());
              }
            }
            // A spontaneous power-ON frame from the remote may carry no speed/
            // mode (sometimes just power, sometimes power + timer) — the dial
            // would render blank. Pull full state so the gear/mode is restored
            // regardless of which remote button woke the fan, or whether the
            // frame happened to include a timer. Gated on !_awaitingMotorState
            // (not !isMotorStateResponse) so it fires for spontaneous remote
            // frames even when they include a timer, while the echo of our own
            // poll is suppressed; !wasPowered independently breaks any loop.
            // Use a retrying burst (not a single poll): when the fan was woken
            // right after a mains power-cycle its MCU has just rebooted and
            // won't answer the first query, so one poll leaves the dial blank.
            if (power && !wasPowered && !_awaitingMotorState) _scheduleWakePolls();
          }
          _updateMotorStatePoll();
          continue;
        }
        final speed = BleResponseParser.parseSpeed(response);
        if (speed != null) {
          if (isMotorStateResponse) {
            // Motor State frame [2] = speed. Only apply when frame [1]
            // confirmed the fan is ON. If OFF, this speed is the hardware's
            // last stored value — it must not re-light a speed dot on an
            // inactive fan (and must not call updatePower(true)).
            final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
            if (!s.isPowered) { continue; }
            // Fan is ON: speed is the exclusive active state — clear mode flags.
            notifier.applyMotorStateTruth(null);
            notifier.updateSpeed(speed);
          } else {
            // Regular speed notification (remote or app echo). Smart, Nature,
            // and Reverse are all incompatible with a fixed speed step — if any
            // is active the hardware has exited the mode; clear it so the UI
            // stays in sync.
            notifier.updateSpeed(speed);
            if (speed > 0) notifier.updatePower(true);
            final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
            if (s.activeMode != null) notifier.setActiveMode(null);
            if (s.isBoost) notifier.setBoostActive(false);
          }
          continue;
        }
        final mode = BleResponseParser.parseModeString(response);
        if (mode != null) {
          if (isMotorStateResponse) {
            // Motor State frame [2] = mode. Only apply when frame [1]
            // confirmed the fan is ON — same gate as the speed case above.
            final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
            if (!s.isPowered) { continue; }
            // Fan is ON: this mode is the exclusive active state.
            notifier.applyMotorStateTruth(mode);
          } else if (mode == 'reverse' &&
                     ref.read(activeFanStateProvider(widget.fan.deviceId)).activeMode == 'reverse') {
            // Hardware toggle model: 0x03 means "reverse active". When the remote
            // sends 0x03 while we are already in reverse, this is an exit toggle.
            notifier.setActiveMode(null);
          } else {
            notifier.updateMode(mode);
          }
          _updateMotorStatePoll();
          continue;
        }
        final timer = BleResponseParser.parseTimer(response);
        if (timer != null) {
          notifier.updateTimer(timer);
          continue;
        }
        final watts = BleResponseParser.parsePowerWatts(response);
        if (watts != null) {
          notifier.updateWatts(watts);
          _lastWattsAt = DateTime.now();
          if (!_isDemo) {
            final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
            if (s.isPowered) {
              final label = s.speed > 0 ? 'Speed ${s.speed} · ${watts}W' : '${watts}W';
              unawaited(BleForegroundService.update(label));
            }
          }
          continue;
        }
        final rpm = BleResponseParser.parseRpm(response);
        if (rpm != null) { notifier.updateRpm(rpm); _lastRpmAt = DateTime.now(); continue; }
        final runtimeSecs = BleResponseParser.parseRuntimeSeconds(response);
        if (runtimeSecs != null) {
          notifier.updateRuntime(runtimeSecs);
          final now = DateTime.now();
          ref.read(dailyRuntimeRepositoryProvider).upsertForDate(
            widget.fan.deviceId,
            DateTime(now.year, now.month, now.day),
            runtimeSecs,
          );
        }
      }

      // The response to a poll we sent has now been fully applied — stop
      // suppressing the rescue poll so a later spontaneous remote frame is
      // honoured. (Done after the loop so the echo's own power frame, processed
      // above, still saw the flag set.)
      if (isMotorStateResponse) {
        _awaitingMotorState = false;
        _awaitingMotorStateTimer?.cancel();
        // Tells _scheduleConnectPolls the fan's real state has arrived, so the
        // on-connect retry loop can stop.
        _motorStateReceived = true;
      }
    });
    unawaited(old?.cancel() ?? Future<void>.value());
  }

  /// Collects the frames of a Machine State (getMotorState) reply we are awaiting
  /// into the _ms* buffer, then flushes them atomically. Power/speed/mode/timer
  /// frames are buffered (frame [2] is speed OR mode — mutually exclusive, so the
  /// latest of the two wins); watts/RPM/runtime frames are applied live because
  /// they are status-poll telemetry that interleaves during the connect burst.
  void _bufferMachineState(List<FanResponse> responses, ActiveFanStateNotifier notifier) {
    var gotMachineFrame = false;
    for (final r in responses) {
      final power = BleResponseParser.parsePowerState(r);
      if (power != null) {
        // Respect the post-power-on suppression window: a stale power=OFF frame
        // must not cancel a user-initiated power-on.
        if (!(power == false && _recentlyPoweredOn)) _msPower = power;
        gotMachineFrame = true;
        continue;
      }
      final speed = BleResponseParser.parseSpeed(r);
      if (speed != null) { _msSpeed = speed; _msMode = null; gotMachineFrame = true; continue; }
      final mode = BleResponseParser.parseModeString(r);
      if (mode != null) { _msMode = mode; _msSpeed = null; gotMachineFrame = true; continue; }
      final timer = BleResponseParser.parseTimer(r);
      if (timer != null) { _msTimer = timer; gotMachineFrame = true; continue; }

      // Telemetry frames stay live so watts/RPM/runtime don't stall mid-burst.
      final watts = BleResponseParser.parsePowerWatts(r);
      if (watts != null) { notifier.updateWatts(watts); _lastWattsAt = DateTime.now(); continue; }
      final rpm = BleResponseParser.parseRpm(r);
      if (rpm != null) { notifier.updateRpm(rpm); _lastRpmAt = DateTime.now(); continue; }
      final runtimeSecs = BleResponseParser.parseRuntimeSeconds(r);
      if (runtimeSecs != null) {
        notifier.updateRuntime(runtimeSecs);
        final now = DateTime.now();
        ref.read(dailyRuntimeRepositoryProvider).upsertForDate(
          widget.fan.deviceId,
          DateTime(now.year, now.month, now.day),
          runtimeSecs,
        );
      }
    }
    if (!gotMachineFrame) return;

    // All three frames present → apply now. Otherwise debounce briefly to let
    // split/out-of-order frames from the same reply catch up.
    if (_machineStateComplete) {
      _flushMachineState();
    } else {
      _msFlushTimer?.cancel();
      _msFlushTimer = Timer(const Duration(milliseconds: 300), _flushMachineState);
    }
  }

  /// True once the buffered reply carries enough to apply immediately: a power
  /// frame, and — when powered — the frame [2] state (speed or mode) plus a timer.
  bool get _machineStateComplete {
    if (_msPower == null) return false;
    if (_msPower == false) return true;
    return (_msSpeed != null || _msMode != null) && _msTimer != null;
  }

  /// Applies the assembled Machine State atomically, independent of the order or
  /// notification-splitting of the frames that built it.
  void _flushMachineState() {
    _msFlushTimer?.cancel();
    _msFlushTimer = null;
    if (!mounted) { _resetMachineStateBuffer(); return; }

    final power = _msPower;
    // No power frame yet — cannot decide. Keep the buffer so a later power frame
    // in the same retry burst completes it; leave the retry polls running.
    if (power == null) return;

    final speed = _msSpeed;
    final mode  = _msMode;
    final timer = _msTimer;
    final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
    var received = false;

    if (power == false) {
      // Machine State frame [1] = OFF: clear ALL operating state.
      notifier.applyMotorStatePowerOff();
      if (!_isDemo) unawaited(BleForegroundService.stop());
      received = true; // OFF is complete, authoritative truth.
    } else {
      notifier.updatePower(true);
      if (mode != null) {
        // Frame [2] = mode: the exclusive active state.
        notifier.applyMotorStateTruth(mode);
      } else if (speed != null) {
        // Frame [2] = speed: plain speed mode, clear any special mode.
        notifier.applyMotorStateTruth(null);
        notifier.updateSpeed(speed);
      }
      if (timer != null) notifier.updateTimer(timer);
      // Complete only when the operating state (speed or mode) is known. A bare
      // power=ON (MCU still booting) leaves the retry polls running to fill it in.
      received = speed != null || mode != null;
      if (received && !_isDemo) {
        final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
        unawaited(BleForegroundService.start(
          s.speed > 0 ? 'Speed ${s.speed}' : 'Fan running',
        ));
      }
    }

    _resetMachineStateBuffer();
    _updateMotorStatePoll();

    if (received) {
      _awaitingMotorState = false;
      _awaitingMotorStateTimer?.cancel();
      // Stops _scheduleConnectPolls / _scheduleWakePolls — the truth has landed.
      _motorStateReceived = true;
    }
  }

  void _resetMachineStateBuffer() {
    _msFlushTimer?.cancel();
    _msFlushTimer = null;
    _msPower = null;
    _msSpeed = null;
    _msMode  = null;
    _msTimer = null;
  }

  // Starts or stops the 90-second Motor State poll based on whether the fan
  // is in Smart, Nature, or Reverse mode. Called whenever mode or power state
  // changes so the timer tracks the actual firmware state.
  void _updateMotorStatePoll() {
    if (_isDemo) return;
    final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));
    final needsPoll = fanState.isPowered &&
        (fanState.activeMode == 'smart' ||
         fanState.activeMode == 'nature' ||
         fanState.activeMode == 'reverse');

    if (!needsPoll || _ble.currentState != BleConnectionState.connected) {
      _motorStateTimer?.cancel();
      _motorStateTimer = null;
      return;
    }

    // Timer already running — avoid duplicates.
    if (_motorStateTimer != null) return;

    _motorStateTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      if (!mounted) { _motorStateTimer?.cancel(); return; }
      if (_ble.currentState != BleConnectionState.connected) {
        _motorStateTimer?.cancel();
        _motorStateTimer = null;
        return;
      }
      final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
      if (!s.isPowered ||
          (s.activeMode != 'smart' &&
           s.activeMode != 'nature' &&
           s.activeMode != 'reverse')) {
        _motorStateTimer?.cancel();
        _motorStateTimer = null;
        return;
      }
      // Route through _requestMotorState so the reply is assembled atomically
      // (see _bufferMachineState) rather than hitting the ordering-sensitive
      // live gate — these autonomous modes change speed, so a dropped frame 2
      // would leave the dial stale.
      _requestMotorState();
    });
  }

  void _startRuntimePoll() {
    _runtimeTimer?.cancel();
    _runtimeTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      if (!mounted) { _runtimeTimer?.cancel(); return; }
      if (_ble.currentState != BleConnectionState.connected) {
        _runtimeTimer?.cancel();
        _runtimeTimer = null;
        return;
      }
      try {
        await _ble.writeFrame(BleFrameBuilder.queryRuntime());
      } on Object catch (_) {
        // Fan disconnected mid-poll; connection state stream handles recovery.
      }
    });
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      if (_ble.currentState != BleConnectionState.connected) return;

      final now = DateTime.now();
      final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
      if (_lastWattsAt != null && now.difference(_lastWattsAt!) > const Duration(seconds: 5)) {
        notifier.clearWatts();
        _lastWattsAt = null;
      }
      if (_lastRpmAt != null && now.difference(_lastRpmAt!) > const Duration(seconds: 5)) {
        notifier.clearRpm();
        _lastRpmAt = null;
      }

      // Normally returns 2 frames (0x23 watts + 0x24 RPM).
      // Exception: the FIRST poll after the fan is freshly powered on returns 4 frames —
      // 0x02 (power), 0x04 (speed), 0x23 (watts), 0x24 (RPM) — so the fan can restore
      // state that may reset when disconnected from mains. _subscribeNotify dispatches
      // all four frame types; no special casing needed here.
      try {
        await _ble.writeFrame(BleFrameBuilder.statusPoll());
        if (!mounted) return;
      } on Object catch (_) {
        // Fan disconnected mid-poll; connection state stream handles recovery.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDemo) return;
    switch (state) {
      case AppLifecycleState.paused:
        // Screen off / app backgrounded: release the single GATT connection so
        // another phone can use the fan. Stop the foreground notification too —
        // it would otherwise stay up showing stale telemetry. (Cloudflare usage
        // upload is independent: it runs at app startup in main.dart, gated by
        // opt-in + Wi-Fi + once-per-day, so dropping the link here doesn't
        // affect it.)
        _telemetryTimer?.cancel();
        _motorStateTimer?.cancel();
        _motorStateTimer = null;
        _runtimeTimer?.cancel();
        _runtimeTimer = null;
        _wakePollTimer?.cancel();
        _wakePollTimer = null;
        _connectPollTimer?.cancel();
        _connectPollTimer = null;
        _awaitingMotorState = false;
        _awaitingMotorStateTimer?.cancel();
        _resetMachineStateBuffer();
        unawaited(BleForegroundService.stop());
        unawaited(_ble.disconnect());
      case AppLifecycleState.resumed:
        // Re-establish the link unless we're already connected. connect() fails
        // gracefully with an 'in use by another device' status (GATT 133) when
        // another phone holds the fan — the BLE60 allows only one connection —
        // so this never steals an active connection from someone else.
        if (_ble.currentState != BleConnectionState.connected) {
          unawaited(_connect());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connecting = false;
    _connectedFanCtrl.state = null;
    _telemetryTimer?.cancel();
    _motorStateTimer?.cancel();
    _runtimeTimer?.cancel();
    _expiryTimer?.cancel();
    _expiryOnceTimer?.cancel();
    _recentlyPoweredOnTimer?.cancel();
    _awaitingMotorStateTimer?.cancel();
    _wakePollTimer?.cancel();
    _connectPollTimer?.cancel();
    _msFlushTimer?.cancel();
    unawaited(_notifySub?.cancel() ?? Future<void>.value());
    unawaited(BleForegroundService.stop());
    _debug.dispose();
    super.dispose();
  }

  void _applyDemoFrame(List<int> frame) {
    if (frame.length < 7) return;
    final cmd     = frame[3];
    final dataLen = frame[4];
    if (frame.length < 5 + dataLen + 1) return;
    final data    = frame[5];
    final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
    if (cmd == CommandLoader.responseCommand('power')) {
      notifier.updatePower(data == 0x01);
    } else if (cmd == CommandLoader.responseCommand('speed')) {
      notifier.updateSpeed(data);
    } else if (cmd == CommandLoader.responseCommand('mode')) {
      final modeStr = switch (data) {
        0x01 => 'boost',
        0x02 => 'nature',
        0x03 => 'reverse',
        0x04 => 'smart',
        _    => null as String?,
      };
      if (modeStr == 'reverse' &&
          ref.read(activeFanStateProvider(widget.fan.deviceId)).activeMode == 'reverse') {
        notifier.setActiveMode(null);
      } else {
        notifier.updateMode(modeStr);
      }
    } else if (cmd == CommandLoader.responseCommand('timer')) {
      notifier.updateTimer(data);
    }
  }

  Future<void> _send(List<int>? frame, {String? pendingMsg, String label = ''}) async {
    if (frame == null) {
      if (pendingMsg != null && mounted && !_isDemo) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pendingMsg)));
      }
      return;
    }
    _debug.value = _DebugSnapshot(sentFrame: frame, sentLabel: label);
    // Suppress incoming power=false for 1.5 s after any powerOn command so the
    // initial motor-state response (queued before the fan receives powerOn) cannot
    // race back and override the user-initiated isPowered=true.
    if (label.startsWith('Power ON')) {
      _recentlyPoweredOn = true;
      _recentlyPoweredOnTimer?.cancel();
      _recentlyPoweredOnTimer = Timer(const Duration(milliseconds: 1500), () {
        _recentlyPoweredOn = false;
      });
    }
    if (_isDemo) {
      _applyDemoFrame(frame);
      return;
    }
    try {
      await _ble.writeFrame(frame);
    } on Object catch (e) {
      _debug.value = _debug.value.copyWith(writeError: e.toString());
    }
    if (!mounted) return;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<BluetoothAdapterState>>(
      bluetoothAdapterStateProvider,
      (prev, next) {
        if (prev?.hasValue != true) return;
        if (_isDemo) return;
        if (next.valueOrNull == BluetoothAdapterState.off && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bluetooth has been disabled. Please turn on Bluetooth.'),
            duration: Duration(seconds: 4),
          ));
        }
      },
    );

    final fanState  = ref.watch(activeFanStateProvider(widget.fan.deviceId));
    final connState = ref.watch(bleConnectionStateProvider).value
        ?? BleConnectionState.disconnected;

    final enabled         = _isDemo || connState == BleConnectionState.connected;
    final controlsEnabled = enabled && fanState.isPowered;
    final isDisconnected  = !_isDemo && connState == BleConnectionState.disconnected;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.fan.nickname,
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
            _ConnStatusLabel(state: connState, isDemo: _isDemo),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _BluetoothIndicator(
              isConnected: !_isDemo && connState == BleConnectionState.connected,
              isConnecting: !_isDemo && (connState == BleConnectionState.connecting ||
                  connState == BleConnectionState.scanning),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, isDisconnected ? 200 : 28),
            child: Column(
              children: [
                if (widget.fan.isServiceAccess)
                  _ServiceAccessBanner(remaining: _serviceRemaining),
                _PowerButton(
                  isPowered: fanState.isPowered,
                  isConnected: enabled,
                  onTap: () {
                    if (!enabled && !_isDemo) {
                      setState(() => _showDisconnectAlert = true);
                      return;
                    }
                    final on = !fanState.isPowered;
                    ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                        .updatePower(on);
                    unawaited(_send(
                      on ? BleFrameBuilder.powerOn() : BleFrameBuilder.powerOff(),
                      label: on ? 'Power ON' : 'Power OFF',
                    ));
                  },
                ),
                const SizedBox(height: 20),
                // Only block taps when disconnected — when the fan is connected
                // but powered off, taps still register so they can auto power-on
                // the fan via _ensurePoweredOn() before applying the action.
                IgnorePointer(
                  ignoring: !enabled,
                  child: AnimatedOpacity(
                    opacity: controlsEnabled ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 300),
                    child: _FanControlsPanel(
                      fan: widget.fan,
                      enabled: enabled,
                      send: _send,
                    ),
                  ),
                ),
                // Debug card: visible to service technicians only (isServiceAccess).
                // Regular customers do not see raw BLE frame data.
                if (widget.fan.isServiceAccess) ...[
                  const SizedBox(height: 16),
                  ValueListenableBuilder<_DebugSnapshot>(
                    valueListenable: _debug,
                    builder: (_, snap, __) => _DebugCard(
                      sentFrame: snap.sentFrame,
                      sentLabel: snap.sentLabel,
                      receivedFrame: snap.receivedFrame,
                      writeCharStatus: _isDemo ? 'demo' : _ble.writeCharStatus,
                      connectStatus:   _isDemo ? 'demo' : _ble.connectStatus,
                      writeError: snap.writeError,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isDisconnected)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: ConnectionLostCard(
                onRetry: _connect,
                connectStatus: _isDemo ? null : _ble.connectStatus,
                subtitle: !_isDemo && _ble.connectStatus.contains('in use by another device')
                    ? 'This fan appears to be connected to another device. '
                      'Ask the other user to disconnect, then try again.'
                    : null,
              ),
            ),
          if (_showDisconnectAlert)
            _DisconnectAlertOverlay(
              fanName: widget.fan.nickname,
              onClose: () => setState(() => _showDisconnectAlert = false),
              onRetry: () {
                setState(() => _showDisconnectAlert = false);
                unawaited(_connect());
              },
            ),
        ],
      ),
    );
  }
}

// ── Service access banner ─────────────────────────────────────────────────────

class _ServiceAccessBanner extends StatelessWidget {
  final Duration remaining;
  const _ServiceAccessBanner({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    // Banner updates every 30 s — show HH:MM to avoid misleading seconds precision.
    final timeStr = '${h.toString().padLeft(2, '0')}:$m';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kYellowFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kYellowBorderHi),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_circle_outlined, color: kYellow, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SERVICE ACCESS · $timeStr remaining',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w600, color: kYellow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connection status label ───────────────────────────────────────────────────

class _ConnStatusLabel extends StatelessWidget {
  final BleConnectionState state;
  final bool isDemo;
  const _ConnStatusLabel({required this.state, required this.isDemo});

  @override
  Widget build(BuildContext context) {
    if (isDemo) {
      return Text('● DEMO MODE',
          style: GoogleFonts.manrope(fontSize: 10, color: kYellow,
              fontWeight: FontWeight.w700, letterSpacing: 1.5));
    }
    final (String text, Color color) = switch (state) {
      BleConnectionState.connected    => ('CONNECTED',    kYellow),
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => ('CONNECTING…', kYellowSoft),
      BleConnectionState.disconnected => ('DISCONNECTED', kTextDim),
    };
    return Text(text,
        style: GoogleFonts.manrope(fontSize: 10, color: color,
            fontWeight: FontWeight.w700, letterSpacing: 1.5));
  }
}

// ── Fan controls panel ────────────────────────────────────────────────────────
// Owns the lighting UI state and all mode/speed/timer/lighting callbacks.
// Extracted from ControlScreen.build() to keep that method under 100 lines.

class _FanControlsPanel extends ConsumerStatefulWidget {
  final FanDevice fan;
  // BLE-connection-based (not power-gated) — controls stay tappable while the
  // fan is powered off so _ensurePoweredOn() can auto power-on the fan.
  final bool enabled;
  final _SendFn send;

  const _FanControlsPanel({
    required this.fan,
    required this.enabled,
    required this.send,
  });

  @override
  ConsumerState<_FanControlsPanel> createState() => _FanControlsPanelState();
}

class _FanControlsPanelState extends ConsumerState<_FanControlsPanel>
    with WidgetsBindingObserver {
  String _colorType       = 'warm';
  double _brightnessValue = 0.7;
  bool   _isLightOn       = false;

  // ── Usage-log segment tracker (Last Known State Continuation) ──────────────
  // A segment's duration can span app restarts/disconnects — it remains open
  // until the app detects another speed/mode change, per the analytics spec.
  DateTime? _segmentStart;
  int   _segmentGear = 0;
  String? _segmentMode;
  // Speed active immediately before Smart Mode was enabled — Smart-mode
  // efficiency baseline. Only meaningful when _segmentMode == 'smart'.
  int? _segmentSmartBaseline;

  // Running accumulators: sum all BLE poll responses during a segment, then
  // divide at flush time. Avoids the "watts=0 if polled before first response"
  // problem that made kWh=0 for every log and broke analytics + Cloudflare.
  int _segmentWattsSum   = 0;
  int _segmentWattsCount = 0;
  int _segmentRpmSum     = 0;
  int _segmentRpmCount   = 0;
  // Last observed non-zero value — used as a fallback when no telemetry
  // arrived yet (e.g. speed changed immediately after connect).
  int _lastKnownWatts    = 0;

  // Cached in initState — ref.read() is forbidden inside dispose().
  late final UsageLogRepository _usageLogRepo;
  late final FanRepository      _fanRepo;
  // Cached because fan.model is immutable for the widget's lifetime.
  late final ApplianceType? _applianceType;

  // Speed saved when Nature mode activates — restored when Nature is toggled off
  // or when switching to Smart/Reverse.
  int _preNatureSpeed = 0;
  // Speed saved when Smart mode activates — restored when Smart is toggled off.
  int _preSmartSpeed = 0;

  @override
  void initState() {
    super.initState();
    _usageLogRepo    = ref.read(usageLogRepositoryProvider);
    _fanRepo         = ref.read(fanRepositoryProvider);
    _applianceType   = ApplianceLoader.typeForModel(widget.fan.model);
    WidgetsBinding.instance.addObserver(this);
    final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
    // Seed _preNatureSpeed so that if the fan is loaded from ObjectBox already
    // in Nature mode, a subsequent switch to Smart/Reverse has a speed to restore.
    if (s.activeMode == 'nature') {
      // Default to 3 when speed is 0 (e.g. screen re-opened before first telemetry).
      _preNatureSpeed = s.speed > 0 ? s.speed : 3;
    }
    if (s.activeMode == 'smart') {
      _preSmartSpeed = s.speed > 0 ? s.speed : 3;
    }
    // Restore lighting UI state from last persisted values.
    _colorType       = s.lastLightColorType;
    _brightnessValue = s.lastLightBrightness;
    _isLightOn       = s.lastLightIsOn;
    // Resume or reconcile the persisted open segment (Last Known State Continuation).
    _reconcileOpenSegment(s);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Persist the open segment's progress so it can be continued (or
      // reconciled against a remote-detected change) on resume/restart.
      _persistOpenSegment();
    } else if (state == AppLifecycleState.resumed) {
      final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
      _reconcileOpenSegment(s);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistOpenSegment();
    super.dispose();
  }

  /// Reconciles the in-memory segment tracker against the persisted "open
  /// segment" and the current live fan state (Last Known State Continuation).
  ///
  /// - If the persisted open segment matches the live gear/mode, resume it
  ///   as-is — its duration now spans whatever time has passed, including
  ///   any time the app was closed or disconnected.
  /// - If the live state differs (a remote/disconnected change was detected),
  ///   close the persisted segment as of now and start a new one.
  /// - If there is no persisted open segment, start one if the fan is running.
  void _reconcileOpenSegment(FanState live) {
    final persisted = _fanRepo.getState(widget.fan.deviceId);
    final continuing = persisted.openSegmentGear > 0 &&
        persisted.openSegmentGear == live.speed &&
        persisted.openSegmentMode == live.activeMode &&
        live.isPowered;

    if (continuing) {
      _segmentStart         = persisted.openSegmentStart;
      _segmentGear          = persisted.openSegmentGear;
      _segmentMode          = persisted.openSegmentMode;
      _segmentSmartBaseline = persisted.openSegmentSmartBaseline;
      _segmentWattsSum      = persisted.openSegmentWattsSum;
      _segmentWattsCount    = persisted.openSegmentWattsCount;
      _segmentRpmSum        = persisted.openSegmentRpmSum;
      _segmentRpmCount      = persisted.openSegmentRpmCount;
      return;
    }

    if (persisted.openSegmentGear > 0) {
      final secs = DateTime.now().difference(persisted.openSegmentStart).inSeconds;
      if (secs > 0) {
        _writeUsageLog(
          start:             persisted.openSegmentStart,
          durationSecs:      secs,
          gear:              persisted.openSegmentGear,
          mode:              persisted.openSegmentMode,
          smartBaselineGear: persisted.openSegmentSmartBaseline,
          wattsSum:          persisted.openSegmentWattsSum,
          wattsCount:        persisted.openSegmentWattsCount,
          rpmSum:            persisted.openSegmentRpmSum,
          rpmCount:          persisted.openSegmentRpmCount,
        );
      }
    }

    _segmentWattsSum   = 0;
    _segmentWattsCount = 0;
    _segmentRpmSum     = 0;
    _segmentRpmCount   = 0;
    if (live.isPowered && live.speed > 0) {
      _segmentStart         = DateTime.now();
      _segmentGear          = live.speed;
      _segmentMode          = live.activeMode;
      _segmentSmartBaseline = null;
    } else {
      _segmentStart         = null;
      _segmentGear          = 0;
      _segmentMode          = null;
      _segmentSmartBaseline = null;
    }
    _persistOpenSegment();
  }

  /// Writes a completed segment to the usage log, averaging telemetry
  /// accumulated over its lifetime.
  void _writeUsageLog({
    required DateTime start,
    required int durationSecs,
    required int gear,
    required String? mode,
    required int? smartBaselineGear,
    required int wattsSum,
    required int wattsCount,
    required int rpmSum,
    required int rpmCount,
  }) {
    final avgWatts = wattsCount > 0 ? (wattsSum / wattsCount).round() : _lastKnownWatts;
    final avgRpm   = rpmCount > 0 ? (rpmSum / rpmCount).round() : 0;
    try {
      _usageLogRepo.addLog(UsageLog(
        deviceId:          widget.fan.deviceId,
        startTime:         start,
        durationSecs:      durationSecs,
        gear:              gear,
        watts:             avgWatts,
        rpm:               avgRpm,
        mode:              mode,
        smartBaselineGear: smartBaselineGear,
      ));
    } on Object catch (_) {
      // Store teardown or disk-full; segment is lost but app must not crash.
    }
  }

  /// Persists the currently-open segment (start, gear, mode, running
  /// telemetry sums) so it can be resumed across app restarts/disconnects.
  void _persistOpenSegment() {
    unawaited(_fanRepo.saveOpenSegment(
      widget.fan.deviceId,
      start:             _segmentStart ?? DateTime(0),
      gear:              _segmentGear,
      mode:              _segmentMode,
      smartBaselineGear: _segmentSmartBaseline,
      wattsSum:          _segmentWattsSum,
      wattsCount:        _segmentWattsCount,
      rpmSum:            _segmentRpmSum,
      rpmCount:          _segmentRpmCount,
    ));
  }

  /// Flush the completed segment to ObjectBox then start a new one.
  /// Uses the running avg of all poll responses received during the segment,
  /// falling back to the last known non-zero watt value when no readings
  /// arrived yet (e.g. speed changed immediately after connect).
  void _flushSegment({
    required int newGear,
    required String? newMode,
    int? smartBaselineGear,
  }) {
    final start = _segmentStart;
    if (start != null && _segmentGear > 0) {
      final secs = DateTime.now().difference(start).inSeconds;
      if (secs > 0) {
        _writeUsageLog(
          start:             start,
          durationSecs:      secs,
          gear:              _segmentGear,
          mode:              _segmentMode,
          smartBaselineGear: _segmentSmartBaseline,
          wattsSum:          _segmentWattsSum,
          wattsCount:        _segmentWattsCount,
          rpmSum:            _segmentRpmSum,
          rpmCount:          _segmentRpmCount,
        );
      }
    }
    // Reset accumulators for the new segment.
    _segmentWattsSum   = 0;
    _segmentWattsCount = 0;
    _segmentRpmSum     = 0;
    _segmentRpmCount   = 0;
    _segmentStart = DateTime.now();
    _segmentGear  = newGear;
    _segmentMode  = newMode;
    _segmentSmartBaseline = newMode == 'smart' ? smartBaselineGear : null;
    _persistOpenSegment();
  }

  /// Returns true when the appliance type for this fan declares [control],
  /// OR when the device has no stored model (legacy BLE-paired fan → show all).
  bool _has(String control) =>
      _applianceType == null || _applianceType.hasControl(control);

  static String _timerLabel(int? code) => switch (code) {
    0x02 => '2H',
    0x04 => '4H',
    0x08 => '8H',
    _    => '',
  };

  static int _timerCodeToHours(int? code) => switch (code) {
    0x02 => 2,
    0x04 => 4,
    0x08 => 8,
    _    => 0,
  };

  /// If the fan is connected but powered off, power it on (optimistically and
  /// over BLE) before executing the requested control action. Mirrors the
  /// manual power-button flow so any control interaction "wakes" the fan.
  void _ensurePoweredOn() {
    final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));
    if (fanState.isPowered) return;
    ref.read(activeFanStateProvider(widget.fan.deviceId).notifier).updatePower(true);
    unawaited(widget.send(BleFrameBuilder.powerOn(), label: 'Power ON (auto)'));
  }

  void _onMode(String m) {
    final fan      = widget.fan;
    final fanState = ref.read(activeFanStateProvider(fan.deviceId));
    final notifier = ref.read(activeFanStateProvider(fan.deviceId).notifier);

    _ensurePoweredOn();

    // Reverse toggles off on second tap (hardware toggle model).
    // Nature and Smart are activation-only — tapping their active button has no effect.
    if (fanState.activeMode == m) {
      if (m == 'reverse') {
        // Hardware toggle: second Reverse command exits reverse mode.
        // No optimistic setActiveMode(null) — the BLE echo (0x03) will arrive
        // and the toggle-detection in _subscribeNotify clears the mode.
        // Speed is preserved as-is — exiting Reverse only flips direction.
        _flushSegment(newGear: fanState.speed, newMode: null);
        unawaited(widget.send(BleFrameBuilder.setReverse(), label: 'Mode: forward (toggle)'));
      }
      return;
    }

    // Switching FROM Reverse → Nature or Smart: exit reverse first, then activate.
    // The fan's current speed carries over unchanged (Reverse no longer tracks
    // a separate "pre-reverse" speed to restore).
    if (fanState.activeMode == 'reverse' && (m == 'nature' || m == 'smart')) {
      final restore = fanState.speed;
      if (m == 'nature') {
        _preNatureSpeed = restore;
        _flushSegment(newGear: fanState.speed, newMode: 'nature');
        // No optimistic mode update — reverse echo clears it, nature echo sets it.
        unawaited(widget.send(BleFrameBuilder.setReverse(), label: 'Mode: forward (exit reverse)'));
        unawaited(widget.send(BleFrameBuilder.setNature(), label: 'Mode: nature'));
      } else {
        _preSmartSpeed = restore;
        final smartSpeed = restore < 3 ? 3 : restore;
        _flushSegment(newGear: smartSpeed, newMode: 'smart', smartBaselineGear: _preSmartSpeed);
        if (smartSpeed != fanState.speed) notifier.updateSpeed(smartSpeed);
        // No optimistic mode update — reverse echo clears it, smart echo sets it.
        unawaited(widget.send(BleFrameBuilder.setReverse(), label: 'Mode: forward (exit reverse)'));
        unawaited(widget.send(BleFrameBuilder.setSmart(), label: 'Mode: smart'));
        if (smartSpeed != fanState.speed) {
          unawaited(widget.send(BleFrameBuilder.setSpeed(smartSpeed), label: 'Speed $smartSpeed'));
        }
      }
      return;
    }

    // Switching INTO Nature: save current speed, then activate.
    if (m == 'nature') {
      _preNatureSpeed = fanState.speed;
      _flushSegment(newGear: fanState.speed, newMode: 'nature');
      notifier.setActiveMode('nature');
      unawaited(widget.send(BleFrameBuilder.setNature(), label: 'Mode: nature'));
      return;
    }

    // Switching FROM Nature → Smart or Reverse: restore pre-nature speed.
    if (fanState.activeMode == 'nature') {
      final restore = (m == 'smart' && _preNatureSpeed < 3) ? 3 : _preNatureSpeed;
      if (m == 'smart') _preSmartSpeed = _preNatureSpeed;
      // Reverse: no optimistic mode update — let the BLE echo drive it via toggle detection.
      if (m != 'reverse') notifier.setActiveMode(m);
      if (restore > 0) notifier.updateSpeed(restore);
      _flushSegment(
        newGear: restore > 0 ? restore : fanState.speed,
        newMode: m,
        smartBaselineGear: m == 'smart' ? _preSmartSpeed : null,
      );
      // Mode frame first so the hardware exits Nature before receiving the speed command.
      final frame = switch (m) {
        'smart'   => BleFrameBuilder.setSmart(),
        'reverse' => BleFrameBuilder.setReverse(),
        _         => null,
      };
      unawaited(widget.send(frame, label: 'Mode: $m'));
      if (restore > 0) {
        unawaited(widget.send(BleFrameBuilder.setSpeed(restore), label: 'Speed $restore'));
      }
      return;
    }

    // Normal activation (Smart/Reverse, not from Nature).
    if (m == 'smart') {
      _preSmartSpeed = fanState.speed;
      if (fanState.speed > 0 && fanState.speed < 3) {
        notifier.updateSpeed(3);
        unawaited(widget.send(BleFrameBuilder.setSpeed(3), label: 'Speed 3 (Smart)'));
      }
    }
    _flushSegment(
      newGear: fanState.speed,
      newMode: m,
      smartBaselineGear: m == 'smart' ? _preSmartSpeed : null,
    );
    // Reverse: no optimistic mode update — let the BLE echo drive it via toggle detection.
    if (m != 'reverse') notifier.setActiveMode(m);
    final frame = switch (m) {
      'reverse' => BleFrameBuilder.setReverse(),
      'smart'   => BleFrameBuilder.setSmart(),
      _         => null,
    };
    unawaited(widget.send(frame, label: 'Mode: $m'));
  }

  void _onBoost() {
    final fan = widget.fan;

    // Ensure power on BEFORE reading state so isBoost/activeMode reflect the
    // current session (not stale ObjectBox values from a previous disconnect).
    _ensurePoweredOn();

    final fanState = ref.read(activeFanStateProvider(fan.deviceId));
    final notifier = ref.read(activeFanStateProvider(fan.deviceId).notifier);

    // Nature → Boost: clear Nature, activate Boost, skip speed restore.
    if (fanState.activeMode == 'nature') {
      _flushSegment(newGear: fanState.speed, newMode: 'boost');
      notifier.setActiveMode(null);
      notifier.setBoostActive(true);
      unawaited(widget.send(BleFrameBuilder.setBoost(), label: 'Boost'));
      return;
    }

    // Boost is activation-only — tapping active boost has no effect.
    if (fanState.isBoost) return;

    // Smart → Boost: setBoostActive(true) clears Smart (mutually exclusive), so
    // only the Boost command is sent. Reverse is preserved (may coexist).
    _flushSegment(newGear: fanState.speed, newMode: 'boost');
    notifier.setBoostActive(true);
    unawaited(widget.send(BleFrameBuilder.setBoost(), label: 'Boost'));
  }

  @override
  Widget build(BuildContext context) {
    final fan      = widget.fan;
    final enabled  = widget.enabled;
    final fanState = ref.watch(activeFanStateProvider(fan.deviceId));

    // Accumulate every BLE poll response that arrives while a segment is open.
    // ref.listen fires on state changes — no side-effect risk. NOTE: normal polls
    // deliver two frames (0x23 watts, 0x24 RPM) as separate notifier mutations,
    // so this fires ~twice per 3 s cadence. The first poll after a fresh power-on
    // delivers four frames and fires up to four times; the average is still
    // unaffected (sum and count inflate symmetrically). Only treat _segment*Count
    // as a weight, never as a poll
    // count.
    ref.listen(activeFanStateProvider(fan.deviceId), (_, next) {
      if (_segmentGear > 0) {
        if (next.lastWatts != null && next.lastWatts! > 0) {
          _segmentWattsSum   += next.lastWatts!;
          _segmentWattsCount++;
          _lastKnownWatts = next.lastWatts!;
        }
        if (next.lastRpm != null && next.lastRpm! > 0) {
          _segmentRpmSum   += next.lastRpm!;
          _segmentRpmCount++;
        }
      }
    });

    // Custom (non-built-in) controls declared in appliances.yaml for this type.
    // _applianceType is cached in initState — fan.model is immutable.
    final customControls = _applianceType == null
        ? const <String>[]
        : _applianceType.controls
            .where((String c) => !ControlRegistry.isBuiltIn(c))
            .toList(growable: false);

    return Column(
      children: [

        // ── Speed dial ──────────────────────────────────────────────────────
        if (_has('speed'))
          RepaintBoundary(
            child: CircularSpeedDial(
              currentSpeed: fanState.speed,
              watts: fanState.lastWatts,
              // Negate RPM in reverse so the dial shows e.g. "−236 RPM".
              rpm: fanState.activeMode == 'reverse' && fanState.lastRpm != null
                  ? -(fanState.lastRpm!)
                  : fanState.lastRpm,
              enabled: enabled,
              isBoost: fanState.isBoost,
              isNature: fanState.activeMode == 'nature',
              isSmart: fanState.activeMode == 'smart',
              isReverse: fanState.activeMode == 'reverse',
              disabledSpeeds: const {},
              onSpeedSelected: (s) {
                _ensurePoweredOn();
                final notifier = ref.read(activeFanStateProvider(fan.deviceId).notifier);

                // Selecting a speed while Nature is active exits Nature and
                // applies the new speed immediately.
                if (fanState.activeMode == 'nature') {
                  notifier.setActiveMode(null);
                  _flushSegment(newGear: s, newMode: null);
                  notifier.updateSpeed(s);
                  unawaited(widget.send(BleFrameBuilder.setSpeed(s), label: 'Speed $s'));
                  return;
                }

                // Selecting a speed while Smart is active exits Smart and applies
                // the new speed immediately — including speeds 1-2, which Smart
                // normally restricts.
                if (fanState.activeMode == 'smart') {
                  notifier.setActiveMode(null);
                  _flushSegment(newGear: s, newMode: null);
                  notifier.updateSpeed(s);
                  unawaited(widget.send(BleFrameBuilder.setSpeed(s), label: 'Speed $s'));
                  return;
                }

                if (fanState.isBoost) {
                  notifier.setBoostActive(false);
                  if (fanState.activeMode == 'reverse') {
                    unawaited(widget.send(BleFrameBuilder.setReverse(), label: 'Mode: reverse'));
                  }
                }
                _flushSegment(newGear: s, newMode: fanState.activeMode);
                notifier.updateSpeed(s);
                unawaited(widget.send(BleFrameBuilder.setSpeed(s), label: 'Speed $s'));
              },
            ),
          ),

        if (_has('speed')) const SizedBox(height: 12),

        // ── Operating modes (includes boost button) ──────────────────────────
        if (_has('mode')) ...[
          const _SectionHeader('OPERATING MODES'),
          const SizedBox(height: 10),
          ModeControlWidget(
            activeMode: fanState.activeMode,
            isBoost: fanState.isBoost,
            enabled: enabled,
            onMode: _onMode,
            onBoost: _onBoost,
          ),
          const SizedBox(height: 20),
        ],

        // ── Sleep timer ─────────────────────────────────────────────────────
        if (_has('timer')) ...[
          _SectionHeader(
            'SLEEP TIMER',
            trailing: (fanState.activeTimerCode != null && fanState.activeTimerCode != 0)
                ? (fanState.timerActivatedAt != null
                    ? _TimerCountdown(
                        activatedAt:   fanState.timerActivatedAt!,
                        durationHours: _timerCodeToHours(fanState.activeTimerCode),
                      )
                    // No start time (timer was set while app was disconnected) —
                    // fall back to the static label.
                    : Text(
                        '${_timerLabel(fanState.activeTimerCode)} REMAINING',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: kYellow,
                            fontWeight: FontWeight.w700, letterSpacing: 1.6),
                      ))
                : null,
          ),
          const SizedBox(height: 10),
          TimerControlWidget(
            activeTimerCode: fanState.activeTimerCode,
            enabled: enabled,
            onTimer: (a) {
              _ensurePoweredOn();
              final code = switch (a) {
                '2h' => 0x02,
                '4h' => 0x04,
                '8h' => 0x08,
                _    => 0x00,
              };
              ref.read(activeFanStateProvider(fan.deviceId).notifier).updateTimer(
                code,
                // Record start time when activating so the countdown can compute
                // remaining time. Pass null when cancelling (timer off).
                activatedAt: code != 0 ? DateTime.now() : null,
              );
              final frame = switch (a) {
                '2h' => BleFrameBuilder.timer2h(),
                '4h' => BleFrameBuilder.timer4h(),
                '8h' => BleFrameBuilder.timer8h(),
                _    => BleFrameBuilder.timerOff(),
              };
              unawaited(widget.send(frame, label: 'Timer: $a'));
            },
          ),
          const SizedBox(height: 20),
        ],

        // ── Mood lighting ───────────────────────────────────────────────────
        if (_has('lighting'))
          LightingControlWidget(
            enabled: enabled,
            isLightOn: _isLightOn,
            colorType: _colorType,
            brightnessValue: _brightnessValue,
            onLightOn: () {
              _ensurePoweredOn();
              setState(() => _isLightOn = true);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: _colorType, brightness: _brightnessValue, isOn: true);
              unawaited(widget.send(BleFrameBuilder.lightOn(),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
            onLightOff: () {
              _ensurePoweredOn();
              setState(() => _isLightOn = false);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: _colorType, brightness: _brightnessValue, isOn: false);
              unawaited(widget.send(BleFrameBuilder.lightOff(),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
            onColorTypeChanged: (t) {
              _ensurePoweredOn();
              setState(() => _colorType = t);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: t, brightness: _brightnessValue, isOn: _isLightOn);
              final byte = switch (t) {
                'neutral' => 0x80,
                'cool'    => 0xFF,
                _         => 0x00,
              };
              unawaited(widget.send(BleFrameBuilder.lightColorTemp(byte),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
            onBrightness: (v) {
              _ensurePoweredOn();
              setState(() => _brightnessValue = v);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: _colorType, brightness: v, isOn: _isLightOn);
              final byte = (v * 255).round().clamp(0, 255);
              unawaited(widget.send(BleFrameBuilder.lightColorTemp(byte),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
          ),

        // ── Custom controls from ControlRegistry ──────────────────────────
        // Any control type in appliances.yaml that is not built-in is looked
        // up in ControlRegistry and rendered here. Register builders in main.dart.
        for (final controlType in customControls)
          if (ControlRegistry.get(controlType) case final builder?)
            builder(ControlBuildParams(
              device:    fan,
              fanState:  fanState,
              enabled:   enabled,
              ref:       ref,
            )),

      ],
    );
  }
}

// ── Bluetooth indicator ───────────────────────────────────────────────────────

class _BluetoothIndicator extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;
  const _BluetoothIndicator({required this.isConnected, required this.isConnecting});

  @override
  State<_BluetoothIndicator> createState() => _BluetoothIndicatorState();
}

class _BluetoothIndicatorState extends State<_BluetoothIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    );
    if (widget.isConnected) _blinkCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BluetoothIndicator old) {
    super.didUpdateWidget(old);
    if (widget.isConnected && !old.isConnected) {
      _blinkCtrl.repeat(reverse: true);
    } else if (!widget.isConnected && old.isConnected) {
      _blinkCtrl.stop();
      _blinkCtrl.reset();
    }
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: AnimatedBuilder(
        animation: _blinkCtrl,
        builder: (_, __) => Icon(
          Icons.bluetooth_rounded,
          size: 20,
          color: widget.isConnected
              ? Color.lerp(kBluetoothBlue, kBluetoothBlueFaint, _blinkCtrl.value)!
              : widget.isConnecting
                  ? kYellowSoft
                  : kTextMut,
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _SectionHeader(this.label, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              )),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Power button ──────────────────────────────────────────────────────────────
//   green  : connected + powered on   (kPowerOn)
//   red    : connected + powered off  (kPowerOff)
//   grey   : disconnected

class _PowerButton extends StatelessWidget {
  final bool isPowered;
  final bool isConnected;
  final VoidCallback onTap;

  const _PowerButton({
    required this.isPowered,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color rim, iconColor, bgColor;
    final List<BoxShadow> shadows;

    if (!isConnected) {
      rim       = kDisabledRim;
      iconColor = kDisabledIcon;
      bgColor   = kCard;
      shadows   = const [BoxShadow(color: kHairline, blurRadius: 8)];
    } else if (isPowered) {
      rim       = kPowerOn;
      iconColor = kPowerOn;
      bgColor   = kPowerOnFill;
      shadows   = const [
        BoxShadow(color: kPowerOnGlow1, blurRadius: 14),
        BoxShadow(color: kPowerOnGlow2, blurRadius: 28),
      ];
    } else {
      rim       = kPowerOff;
      iconColor = kPowerOff;
      bgColor   = kPowerOffFill;
      shadows   = const [
        BoxShadow(color: kPowerOffGlow1, blurRadius: 10),
        BoxShadow(color: kPowerOffGlow2, blurRadius: 22),
      ];
    }

    return Semantics(
      button: true,
      label: 'Power',
      value: isPowered ? 'on' : 'off',
      child: GestureDetector(
        onTap: () {
          unawaited(HapticFeedback.lightImpact());
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: rim, width: 1.5),
            boxShadow: shadows,
          ),
          child: Icon(Icons.power_settings_new_rounded, size: 26, color: iconColor),
        ),
      ),
    );
  }
}

// ── Disconnect alert overlay ──────────────────────────────────────────────────

class _DisconnectAlertOverlay extends StatelessWidget {
  final String fanName;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  const _DisconnectAlertOverlay({
    required this.fanName,
    required this.onClose,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withAlpha(178),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kHairlineStrong),
                boxShadow: const [BoxShadow(color: kModalShadowSoft, blurRadius: 80)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: kYellowFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kYellowBorderHi),
                    ),
                    child: const Icon(Icons.bluetooth_rounded, size: 28, color: kYellow),
                  ),
                  const SizedBox(height: 18),
                  Text('Fan is disconnected',
                      style: GoogleFonts.manrope(
                        fontSize: 20, fontWeight: FontWeight.w700, color: kText,
                      ),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.5),
                      children: [
                        const TextSpan(text: 'Please re-establish the Bluetooth connection to '),
                        TextSpan(
                          text: fanName,
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: kText),
                        ),
                        const TextSpan(text: ' before powering it on.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kYellow, foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text('Reconnect',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700,
                              letterSpacing: 0.04)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity, height: 46,
                    child: TextButton(
                      onPressed: onClose,
                      child: Text('Not now',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600,
                              color: kTextMut)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Timer countdown ───────────────────────────────────────────────────────────
// Displays a live reverse countdown from the moment the timer was activated.
// Owns a 1-second ticker so only this widget rebuilds per tick, not the whole panel.

class _TimerCountdown extends StatefulWidget {
  final DateTime activatedAt;
  final int durationHours; // 2, 4, or 8; 0 = unknown (shows static label)

  const _TimerCountdown({required this.activatedAt, required this.durationHours});

  @override
  State<_TimerCountdown> createState() => _TimerCountdownState();
}

class _TimerCountdownState extends State<_TimerCountdown> {
  late Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.durationHours == 0) {
      return Text('ACTIVE',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: kYellow,
              fontWeight: FontWeight.w700, letterSpacing: 1.6));
    }

    final elapsed   = DateTime.now().difference(widget.activatedAt);
    final total     = Duration(hours: widget.durationHours);
    final remaining = total - elapsed;

    final String label;
    if (remaining.isNegative || remaining.inSeconds <= 0) {
      label = '0m REMAINING';
    } else {
      final h = remaining.inHours;
      final m = remaining.inMinutes.remainder(60);
      label = h > 0 ? '${h}h ${m}m REMAINING' : '${m}m REMAINING';
    }

    return Text(label,
        style: GoogleFonts.jetBrainsMono(
            fontSize: 10, color: kYellow,
            fontWeight: FontWeight.w700, letterSpacing: 1.6));
  }
}

// ── Debug snapshot ────────────────────────────────────────────────────────────

class _DebugSnapshot {
  final List<int>? sentFrame;
  final String sentLabel;
  final List<int>? receivedFrame;
  final String? writeError;

  const _DebugSnapshot({
    this.sentFrame,
    this.sentLabel = '',
    this.receivedFrame,
    this.writeError,
  });

  _DebugSnapshot copyWith({
    List<int>? sentFrame,
    String? sentLabel,
    List<int>? receivedFrame,
    Object? writeError = _sentinel,
  }) => _DebugSnapshot(
    sentFrame: sentFrame ?? this.sentFrame,
    sentLabel: sentLabel ?? this.sentLabel,
    receivedFrame: receivedFrame ?? this.receivedFrame,
    writeError: identical(writeError, _sentinel)
        ? this.writeError
        : writeError as String?,
  );

  static const Object _sentinel = Object();
}

// ── Debug card ────────────────────────────────────────────────────────────────

// Named palette for the debug card — avoids magic hex values in build().
const _kDbgBg     = Color(0xFF0F172A);
const _kDbgBorder = Color(0xFF1E3A5F);
const _kDbgBlue   = Color(0xFF60A5FA);
const _kDbgSlate  = Color(0xFF475569);
const _kDbgGreen  = Color(0xFF34D399);
const _kDbgRed    = Color(0xFFFCA5A5);
const _kDbgYellow = Color(0xFFFCD34D);
const _kDbgPurple = Color(0xFF818CF8);
const _kDbgSnow   = Color(0xFFE2E8F0);
const _kDbgMuted  = Color(0xFF94A3B8);
const _kDbgDim    = Color(0xFF64748B);

class _DebugCard extends StatelessWidget {
  final List<int>? sentFrame;
  final String     sentLabel;
  final List<int>? receivedFrame;
  final String     writeCharStatus;
  final String     connectStatus;
  final String?    writeError;

  const _DebugCard({
    required this.sentFrame,
    required this.sentLabel,
    required this.receivedFrame,
    required this.writeCharStatus,
    required this.connectStatus,
    this.writeError,
  });

  static String _hex(List<int> bytes) =>
      bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join('  ');

  static String _frameLabel(List<int> bytes) {
    if (bytes.length < 4) return '';
    final cmd  = bytes[3];
    final data = bytes.length > 5 ? bytes[5] : null;
    if (cmd == CommandLoader.responseCommand('power')) {
      return data == 0x01 ? 'Power ON' : 'Power OFF';
    }
    if (cmd == CommandLoader.responseCommand('speed')) return 'Speed ${data ?? '?'}';
    if (cmd == CommandLoader.responseCommand('mode')) {
      return switch (data) {
        0x01 => 'Boost',
        0x02 => 'Nature',
        0x03 => 'Reverse',
        0x04 => 'Smart',
        _    => 'Mode ?',
      };
    }
    if (cmd == CommandLoader.responseCommand('timer')) {
      return switch (data) {
        0x00 => 'Timer OFF',
        0x02 => 'Timer 2h',
        0x04 => 'Timer 4h',
        0x08 => 'Timer 8h',
        _    => 'Timer ?',
      };
    }
    if (cmd == CommandLoader.responseCommand('power_watts')) return 'Query Power';
    if (cmd == CommandLoader.responseCommand('running_rpm')) return 'Query Speed';
    return 'cmd=0x${cmd.toRadixString(16).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kDbgBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kDbgBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kDbgBorder,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('DEBUG', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: _kDbgBlue, letterSpacing: 1.2,
                )),
              ),
              const Spacer(),
              const Text('BLE FRAMES', style: TextStyle(
                fontSize: 10, color: _kDbgSlate, letterSpacing: 1.0,
              )),
            ],
          ),
          const SizedBox(height: 10),
          _StatusRow(label: 'CONN', value: connectStatus,
            color: connectStatus == 'connected' ? _kDbgGreen
              : connectStatus.contains('failed') ? _kDbgRed
              : _kDbgYellow),
          const SizedBox(height: 6),
          _StatusRow(label: 'CHAR', value: writeCharStatus,
            color: writeCharStatus.startsWith('found') ? _kDbgGreen
              : writeCharStatus == 'pending' || writeCharStatus == 'disconnected'
                ? _kDbgDim
                : _kDbgRed),
          const SizedBox(height: 10),
          _DebugRow(
            direction: 'TX',
            color: writeError != null ? _kDbgRed : _kDbgGreen,
            label: sentFrame != null ? sentLabel : '—',
            hex: sentFrame != null ? _hex(sentFrame!) : '',
          ),
          if (writeError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text('ERR: $writeError',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: _kDbgRed, height: 1.4,
                )),
            ),
          ],
          const SizedBox(height: 10),
          _DebugRow(
            direction: 'RX',
            color: _kDbgPurple,
            label: receivedFrame != null ? _frameLabel(receivedFrame!) : '—',
            hex: receivedFrame != null ? _hex(receivedFrame!) : '',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatusRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('$label ', style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: _kDbgMuted, letterSpacing: 0.8,
      )),
      Expanded(
        child: Text(value,
          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: color),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _DebugRow extends StatelessWidget {
  final String direction;
  final Color color;
  final String label;
  final String hex;

  const _DebugRow({
    required this.direction,
    required this.color,
    required this.label,
    required this.hex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28, height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withAlpha(80)),
              ),
              child: Text(direction, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color,
              )),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _kDbgSnow,
            )),
          ],
        ),
        if (hex.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(hex,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: _kDbgMuted, letterSpacing: 0.5, height: 1.6,
              )),
          ),
        ],
      ],
    );
  }
}
