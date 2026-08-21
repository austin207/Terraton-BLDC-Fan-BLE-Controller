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
import 'package:terraton_fan_app/core/diagnostics/connection_log_service.dart';
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

// Sleep-timer duration code (0x22 data byte) → hours. Shared by the countdown
// display and the expiry-sync scheduler.
int _timerCodeToHours(int? code) => switch (code) {
  0x02 => 2,
  0x04 => 4,
  0x08 => 8,
  _    => 0,
};

class ControlScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const ControlScreen({super.key, required this.fan});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with WidgetsBindingObserver {
  // The single 3 s poll. Sends the status poll (watts/RPM) and a Get Motor
  // State (power / speed-or-mode / timer) on the same tick; WriteQueue paces
  // them 60 ms apart. This poll is the ONLY thing that updates the display.
  Timer? _pollTimer;
  Timer? _expiryTimer;
  Timer? _expiryOnceTimer;
  Timer? _runtimeTimer;
  StreamSubscription<List<int>>? _notifySub;
  late BleService _ble;
  // Cached to allow clearing connectedFanDeviceIdProvider in dispose()
  // (ref.read() is forbidden inside dispose() in Riverpod 2.x).
  late StateController<String?> _connectedFanCtrl;
  DateTime? _lastWattsAt;
  DateTime? _lastRpmAt;
  Duration  _serviceRemaining = Duration.zero;


  // Fires once when an armed sleep timer is expected to reach zero, clearing
  // the chip. The fan cannot report a running timer (its state reply answers
  // 22 01 00 regardless), so the app owns the countdown end as well as its
  // start. A power-off reply clears it too, whichever lands first.
  Timer?    _timerExpiryTimer;
  DateTime? _timerExpiryTarget;

  // What the ongoing (foreground-service) notification currently shows, as
  // "label|endAtMillis"; null means no notification is up. _refreshOngoing-
  // Notification() is driven off every FanState change, which fires several
  // times per 3 s telemetry cycle, so this keeps the platform channel quiet
  // by re-issuing only when the rendered content actually changes.
  String? _ongoingNotifKey;

  // Reassembles frames from raw notification bytes. The BLE60 bridges the
  // MCU's UART stream into notifications cut at arbitrary byte boundaries, so
  // a multi-frame reply (e.g. the 3-frame getMotorState burst + runtime frame)
  // is routinely split MID-frame across notifications — stateless parsing
  // would silently drop the split frame (historically the timer/mode frame,
  // losing Smart mode and the sleep timer on reconnect). Reset on every
  // (re)connect and on pause so stale partial bytes can't cross sessions.
  final _rxAssembler = FrameStreamAssembler();

  // Tracks the resolved MAC without mutating widget.fan (which is immutable).
  // Populated from widget.fan.macAddress on init; updated after first discovery.
  String? _resolvedMac;

  bool _connecting = false;
  bool _showDisconnectAlert = false;

  /// The pause-initiated disconnect, kept so `resumed` can await it instead of
  /// racing it. Errors are swallowed onto this future — it is a completion
  /// signal, not a result.
  Future<void>? _pauseDisconnect;

  /// True once `paused` has asked for the link to be released. `resumed` must
  /// reconnect on THIS, not on `_ble.currentState`, which still reads
  /// `connected` for as long as the disconnect is in flight.
  bool _linkReleasedByPause = false;

  /// Bumped on every pause and every resume so a slow resume can detect that a
  /// later lifecycle event superseded it and bail out.
  int _lifecycleEpoch = 0;

  /// Throttle for the "status poll skipped — not connected" log line in
  /// `_startTelemetry` — logged at most once per ~30 s so a prolonged
  /// disconnect doesn't drown the Connection Log capture.
  DateTime? _lastSkippedPollLogAt;

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
      // Marks where a capture's restore sequence begins. The baseline is
      // logged for the capture's readability only — nothing reads it back.
      // The 3 s poll is what corrects any stale value.
      final b = ref.read(fanRepositoryProvider).getState(widget.fan.deviceId);
      ConnectionLogService.event(
        'connected; restore baseline power:${b.isPowered ? 'on' : 'off'} '
        'speed:${b.speed} mode:${b.activeMode ?? '-'} '
        'timer:${b.activeTimerCode ?? '-'} '
        'since:${b.timerActivatedAt?.toIso8601String() ?? '-'}',
      );
      // Blank only the instantaneous readings. Power/speed/mode are NOT
      // blanked: the app disconnects on every background, so blanking them
      // would collapse the dial visibly on every resume while the poll refilled
      // it — and they are the fan's own memory, so they are very likely still
      // right. The first poll tick corrects anything that isn't.
      ref
          .read(activeFanStateProvider(widget.fan.deviceId).notifier)
          .resetTelemetryOnConnect();
      _startPoll();
      _rxAssembler.reset();
      _subscribeNotify();
      _startRuntimePoll();
      // No connect-time state fetch is needed: _startPoll's 3 s tick
      // already asks for Get Motor State, so the dial fills on the first tick
      // and keeps re-confirming every tick after that. If the reconnect lands
      // while the MCU is still booting after a mains cycle, the early polls go
      // unanswered and the next one picks it up.
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

  void _subscribeNotify() {
    // Assign new subscription before cancelling old one so no events are
    // missed between cancel and listen on the broadcast stream.
    final old = _notifySub;
    _notifySub = _ble.notifyStream.listen((bytes) {
      if (!mounted) return;
      _debug.value = _debug.value.copyWith(receivedFrame: bytes);

      // The BLE60 both concatenates multiple frames into one notification AND
      // splits single frames across notifications at arbitrary byte boundaries
      // (it chunks the MCU's UART stream, ignoring frame boundaries). The
      // assembler carries partial tail bytes across notifications so a
      // mid-frame split can't drop the frame. It is load-bearing for polling
      // itself: without it a split reply is silently lost.
      final responses = _rxAssembler.addChunk(bytes);
      if (responses.isEmpty) return;
      // Paired with the RX line for the same bytes, this is what makes a
      // tester's capture readable: RX shows what the BLE60 sent, FRM shows what
      // survived reassembly. A frame present in RX but absent here was dropped.
      ConnectionLogService.frames(_frameSummary(responses));

      final notifier =
          ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
      for (final r in responses) {
        _applyFrame(r, notifier);
      }
    });
    unawaited(old?.cancel() ?? Future<void>.value());
  }

  /// One frame in, one field out.
  ///
  /// This is the whole receive path. There is no cross-frame assembly, no
  /// ordering rule and no trust decision: frames are applied in the order the
  /// fan sent them, and the last write of a field in a burst wins — which is
  /// exactly what the fan meant. Whatever the fan reports is what the UI shows.
  /// Button taps never write state; they only send bytes.
  ///
  /// Note the fan echoes every command it accepts, so a tap is normally
  /// reflected in ~100 ms by its own echo, not after a full poll interval.
  /// The 3 s poll is the backstop that also catches IR-remote changes.
  void _applyFrame(FanResponse r, ActiveFanStateNotifier notifier) {
    // ── Telemetry ───────────────────────────────────────────────────────────
    final watts = BleResponseParser.parsePowerWatts(r);           // 0x23
    if (watts != null) {
      notifier.updateWatts(watts);
      _lastWattsAt = DateTime.now();
      _refreshOngoingNotification();
      return;
    }
    final rpm = BleResponseParser.parseRpm(r);                    // 0x24
    if (rpm != null) {
      notifier.updateRpm(rpm);
      _lastRpmAt = DateTime.now();
      return;
    }
    final runtimeSecs = BleResponseParser.parseRuntimeSeconds(r); // 0x08
    if (runtimeSecs != null) {
      notifier.updateRuntime(runtimeSecs);
      final now = DateTime.now();
      ref.read(dailyRuntimeRepositoryProvider).upsertForDate(
        widget.fan.deviceId,
        DateTime(now.year, now.month, now.day),
        runtimeSecs,
      );
      return;
    }

    // ── State ───────────────────────────────────────────────────────────────
    final power = BleResponseParser.parsePowerState(r);           // 0x02
    if (power != null) {
      if (power) {
        notifier.updatePower(true);
      } else {
        // An OFF fan has no mode and no countdown. Not an inference: the
        // firmware's power-off branch runs ClearModes() and clears
        // FlagAutoPower. The stored speed is deliberately kept — see
        // ActiveFanStateNotifier.applyPowerOff.
        notifier.applyPowerOff();
      }
      ConnectionLogService.machineState('power=${power ? 'on' : 'off'}');
      _refreshOngoingNotification();
      return;
    }

    final speed = BleResponseParser.parseSpeed(r);                // 0x04
    if (speed != null) {
      // Speed only. A 0x04 never touches a mode chip, with no exceptions.
      //
      // Frame [2] of a Motor State reply IS exclusive — get_mc_state()
      // (IRScan.c:1264) picks exactly one of reverse / nature / smart / boost /
      // speed — so a 0x04 does mean "no mode running". We still do not act on
      // that here, because the same 0x04 bytes also arrive as the echo of a
      // speed tap (case SPEED, IRScan.c:1357), which does NOT clear smart_mode.
      // Acting on the echo would unlight Smart for one poll interval and then
      // relight it. Turning a chip off is handled on the tap path instead,
      // where we know which command we sent — see _onMode and onSpeedSelected.
      notifier.updateSpeed(speed);
      ConnectionLogService.machineState('speed=$speed');
      return;
    }

    final mode = BleResponseParser.parseModeString(r);            // 0x21
    if (mode != null) {
      notifier.setModeHighlight(mode);
      ConnectionLogService.machineState('mode=$mode');
      return;
    }

    final timer = BleResponseParser.parseTimer(r);                // 0x22
    // A reported 0 is NOT a cancellation. This firmware answers 22 01 00 on
    // every state reply whatever is running: case TIMER sets the auto-power
    // time but never sets IRControl.FlagAutoPower, and get_mc_state() gates the
    // timer field on exactly that flag. Treating the 0 as a clear would kill
    // the countdown within one poll tick of arming it — the "timer resets on
    // reconnect" field bug. Only a non-zero code is information; everything
    // else about the countdown is owned by the app (see _scheduleTimerExpiry).
    if (timer != null && timer != 0) {
      notifier.updateTimer(timer);
      ConnectionLogService.machineState('timer=$timer');
    }
  }

  static String _hex2(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();

  /// Assembled frames as `cmd=data` pairs, e.g. `02=01 21=04 22=02`.
  static String _frameSummary(List<FanResponse> rs) => rs
      .map((r) => '${_hex2(r.command)}='
          '${r.data.isEmpty ? '-' : r.data.map(_hex2).join()}')
      .join(' ');

  /// Arms a one-shot clear for the moment an armed sleep timer reaches zero.
  ///
  /// The app owns both ends of the countdown because the fan cannot report a
  /// running one — its state reply answers 22 01 00 regardless of what is
  /// armed. The fan does perform its own shutdown at T-0, so the next poll's
  /// power=OFF frame clears the chip as well; this timer is what clears it when
  /// that reply is late, or when the app is backgrounded with the link
  /// released and no poll is running at all.
  ///
  /// Driven from the ref.listen in build() on every FanState change; a cleared
  /// or changed timer reschedules via the _timerExpiryTarget comparison.
  void _scheduleTimerExpiry(FanState s) {
    final code      = s.activeTimerCode;
    final startedAt = s.timerActivatedAt;
    if (code == null || code == 0 || startedAt == null) {
      _timerExpiryTimer?.cancel();
      _timerExpiryTimer  = null;
      _timerExpiryTarget = null;
      return;
    }
    final target = startedAt.add(Duration(hours: _timerCodeToHours(code)));
    if (_timerExpiryTarget == target && _timerExpiryTimer != null) return;
    _timerExpiryTarget = target;
    _timerExpiryTimer?.cancel();
    var delay = target.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _timerExpiryTimer = Timer(delay, () {
      if (!mounted) return;
      ref
          .read(activeFanStateProvider(widget.fan.deviceId).notifier)
          .updateTimer(0);
      _timerExpiryTimer  = null;
      _timerExpiryTarget = null;
      _refreshOngoingNotification();
    });
  }

  /// The moment an armed sleep timer is expected to fire, or null when none is
  /// armed (or the expected moment has already passed).
  DateTime? _timerEndsAt(FanState s) {
    final code      = s.activeTimerCode;
    final startedAt = s.timerActivatedAt;
    if (code == null || code == 0 || startedAt == null) return null;
    final end = startedAt.add(Duration(hours: _timerCodeToHours(code)));
    return end.isAfter(DateTime.now()) ? end : null;
  }

  /// Single decision point for the ongoing (foreground-service) notification.
  ///
  /// Two things can justify one: live telemetry while the fan runs, and an
  /// armed sleep timer. The timer outranks the connection — the countdown is
  /// precisely what the user wants to keep seeing after backgrounding the app,
  /// and the app deliberately drops the BLE link on pause, so the notification
  /// has to survive with nothing connected behind it. Android renders the
  /// countdown itself from `endsAt`; nothing here ticks it.
  ///
  /// Pass [linkReleased] from the pause path: `_ble.currentState` can still
  /// read `connected` while the pause-initiated disconnect is in flight, and a
  /// backgrounded app must not claim to be showing live telemetry.
  void _refreshOngoingNotification({bool linkReleased = false}) {
    if (_isDemo) return;
    final s      = ref.read(activeFanStateProvider(widget.fan.deviceId));
    final endsAt = _timerEndsAt(s);
    final live   = !linkReleased &&
        _ble.currentState == BleConnectionState.connected &&
        s.isPowered;

    if (endsAt == null && !live) {
      if (_ongoingNotifKey == null) return;
      _ongoingNotifKey = null;
      unawaited(BleForegroundService.stop());
      return;
    }

    final label = live ? _telemetryNotifLabel(s) : 'Sleep timer';
    final key   = '$label|${endsAt?.millisecondsSinceEpoch ?? 0}';
    if (key == _ongoingNotifKey) return;
    _ongoingNotifKey = key;
    unawaited(BleForegroundService.start(label, endsAt: endsAt));
  }

  String _telemetryNotifLabel(FanState s) {
    final watts = s.lastWatts;
    final parts = [
      if (s.speed > 0) 'Speed ${s.speed}',
      if (watts != null && watts > 0) '${watts}W',
    ];
    return parts.isEmpty ? 'Fan running' : parts.join(' · ');
  }

  void _startRuntimePoll() {
    _runtimeTimer?.cancel();
    _runtimeTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      if (!mounted) { _runtimeTimer?.cancel(); return; }
      if (_ble.currentState != BleConnectionState.connected) return;
      try {
        await _ble.writeFrame(BleFrameBuilder.queryRuntime());
      } on Object catch (_) {
        // Fan disconnected mid-poll; connection state stream handles recovery.
      }
    });
  }

  /// The single periodic poll — the only thing that updates the display.
  ///
  /// Each tick asks the fan two questions: the status poll for watts/RPM, and
  /// Get Motor State for power / speed-or-mode / timer. Both are enqueued in
  /// one synchronous turn so WriteQueue serialises them 60 ms apart rather than
  /// issuing both into the same connection interval (the BLE60 flushes to the
  /// MCU UART only on CRLF and the MCU parses one request at a time, so an
  /// unpaced pair costs the second frame).
  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;

      // Stale-value clear must run regardless of connection state — otherwise
      // watts/RPM from before a disconnect stay on screen indefinitely (they
      // were previously gated behind the connected check below, so they never
      // cleared while disconnected).
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

      if (_ble.currentState != BleConnectionState.connected) {
        // Throttled to roughly once per 30 s so a prolonged disconnect
        // doesn't drown a field tester's Connection Log capture.
        if (_lastSkippedPollLogAt == null ||
            now.difference(_lastSkippedPollLogAt!) > const Duration(seconds: 30)) {
          ConnectionLogService.event('status poll skipped — not connected');
          _lastSkippedPollLogAt = now;
        }
        return;
      }

      // Status poll: 0x23 watts + 0x24 RPM (4 frames on the first poll after a
      // fresh power-on, which also carries 0x02 and 0x04 — harmless, they take
      // the same path as any other frame).
      //
      // Get Motor State: 0x02 power, frame [2] speed-or-mode, 0x22 timer.
      //
      // Always the `…00 01` frame. The alternation with the vendor-doc
      // `…00 02` variant is gone: the firmware source settles which one is
      // right. check_crc() (IRScan.c:1462) sums request_frame[2]+[3]+[5] only,
      // giving 0x00+0x01+0x00 = 0x01, so the `…02` frame fails the check and
      // read_request() never sets recv_flag — Process_Response() is not called
      // at all. Sending it alternately meant every second tick got no reply,
      // making the display update every 6 s instead of 3 s.
      final motorState = BleFrameBuilder.getMotorState();
      // Errors swallowed per frame: a mid-poll disconnect is surfaced by the
      // connection state stream, and the next tick retries anyway.
      unawaited(
          _ble.writeFrame(BleFrameBuilder.statusPoll()).catchError((Object _) {}));
      unawaited(_ble.writeFrame(motorState).catchError((Object _) {}));
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
        ConnectionLogService.event('app paused → disconnecting');
        _pollTimer?.cancel();
        _pollTimer = null;
        _runtimeTimer?.cancel();
        _runtimeTimer = null;
        _rxAssembler.reset();
        // The sleep-timer expiry one-shot deliberately KEEPS running while
        // backgrounded — it is what clears the chip when the fan shuts itself
        // off with no poll and no BLE link to observe it.
        // NOT an unconditional stop: an armed sleep timer keeps the ongoing
        // notification up, switched to its countdown, which is the one thing
        // the user still wants to see while the app is backgrounded. The BLE
        // link is still released below — the countdown needs no connection
        // (Android renders it) and the fan performs its own shutdown at T-0.
        // The service is already running by this point, so nothing is being
        // started from the background.
        _refreshOngoingNotification(linkReleased: true);
        // Record intent instead of trusting `_ble.currentState` afterwards —
        // on a fast app-switch, `resumed` can fire before this disconnect
        // lands, and `currentState` still reads `connected` for as long as
        // it's in flight. Errors are swallowed onto the stored future so it
        // can never surface as an unhandled async error; it is only a
        // completion signal for `resumed` to await.
        _lifecycleEpoch++;
        _linkReleasedByPause = true;
        _pauseDisconnect = _ble.disconnect().catchError((Object _) {});
      case AppLifecycleState.resumed:
        // Re-establish the link unless we're already connected. connect() fails
        // gracefully with an 'in use by another device' status (GATT 133) when
        // another phone holds the fan — the BLE60 allows only one connection —
        // so this never steals an active connection from someone else.
        ConnectionLogService.event('app resumed');
        // Delegate to an async helper — lifecycle callbacks must stay
        // synchronous. The epoch is bumped and captured here so the helper
        // can detect a later pause/resume superseding it.
        _lifecycleEpoch++;
        final epoch = _lifecycleEpoch;
        unawaited(_handleResume(epoch));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  // Waits out a pause-initiated disconnect (if any) before deciding whether
  // to reconnect. Reconnect decisions are made on `_linkReleasedByPause` /
  // the post-await `_ble.currentState` — never on `_ble.currentState` alone,
  // which can still read `connected` while the disconnect from a fast
  // app-switch is in flight (the root cause of the field bug where polling
  // silently stopped after a quick pause/resume).
  Future<void> _handleResume(int epoch) async {
    final pending = _pauseDisconnect;
    if (pending != null) {
      try {
        await pending.timeout(const Duration(seconds: 3));
      } on Object catch (_) {
        // Timeout or a (already-swallowed) error — either way this is only a
        // completion signal, not a result.
      }
    }

    if (!mounted) return;
    // A later pause or resume has superseded this one — bail out so this
    // stale resume can't race the newer lifecycle event's decision.
    if (epoch != _lifecycleEpoch) return;

    final released = _linkReleasedByPause;
    final bleState = _ble.currentState;
    ConnectionLogService.event(
      'resume reconnect: released=$released bleState=$bleState',
    );

    _linkReleasedByPause = false;
    _pauseDisconnect = null;

    if (released || bleState != BleConnectionState.connected) {
      unawaited(_connect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connecting = false;
    _connectedFanCtrl.state = null;
    _pollTimer?.cancel();
    _runtimeTimer?.cancel();
    _expiryTimer?.cancel();
    _expiryOnceTimer?.cancel();
    _timerExpiryTimer?.cancel();
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
      // Demo has no firmware to echo back, so it emulates one. Reverse is a
      // toggle in hardware, and emulating that here is what keeps the demo
      // Reverse chip from sticking on. Confined to the demo path — the real
      // control path never guesses at state.
      if (modeStr == 'reverse' &&
          ref.read(activeFanStateProvider(widget.fan.deviceId)).activeMode == 'reverse') {
        notifier.setModeHighlight(null);
      } else {
        notifier.setModeHighlight(modeStr);
        if (modeStr != null) notifier.updatePower(true);
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
    // A tap sends bytes and nothing else — no local state write, no suppression
    // window, no in-flight retrieval to cancel. The fan's echo and the 3 s poll
    // are the only things that move the display.
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
    // Track the sleep timer so a Machine State fetch fires right after its
    // expected expiry (the firmware's shutdown is otherwise never pushed).
    ref.listen(activeFanStateProvider(widget.fan.deviceId), (_, next) {
      _scheduleTimerExpiry(next);
      // Also how a Timer tap in _FanControlsPanel arms the countdown
      // notification: the tap writes FanState, this fires, and the service is
      // (re)started while the app is still foregrounded — which is what keeps
      // us clear of the Android 12+ ban on starting a foreground service from
      // the background. Cheap to call this often: it no-ops unless what the
      // notification renders actually changed.
      _refreshOngoingNotification();
    });
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
                    // One button, one frame. No memory restore: the firmware's
                    // power-on branch already sets TargetSpeed from its stored
                    // OldTargetSpeed, so re-sending a speed would be redundant,
                    // and re-sending a stored Reverse would actively flip the
                    // fan the wrong way (Reverse is direction ^= 1, a toggle).
                    final on = !fanState.isPowered;
                    unawaited(_send(
                      on ? BleFrameBuilder.powerOn() : BleFrameBuilder.powerOff(),
                      label: on ? 'Power ON' : 'Power OFF',
                    ));
                  },
                ),
                const SizedBox(height: 20),
                // Only block taps when disconnected. A tap while the fan is off
                // still sends its own frame — nothing is injected ahead of it.
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
  // fan is powered off so a tap still sends its own frame to the fan.
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

  // The gear the fan was on when Smart was last engaged. ANALYTICS ONLY — it is
  // the efficiency baseline UsageLog.smartBaselineGear compares against, since
  // a Smart segment's own gear is chosen by the firmware, not the user. No
  // frame is ever derived from this value; it restores nothing.
  int _smartBaselineGear = 0;

  @override
  void initState() {
    super.initState();
    _usageLogRepo    = ref.read(usageLogRepositoryProvider);
    _fanRepo         = ref.read(fanRepositoryProvider);
    _applianceType   = ApplianceLoader.typeForModel(widget.fan.model);
    WidgetsBinding.instance.addObserver(this);
    final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
    // Seed the analytics baseline if the screen opens with Smart already
    // active, so a segment started before this build still has one.
    if (s.activeMode == 'smart') {
      _smartBaselineGear = s.speed > 0 ? s.speed : 3;
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

  /// True when [m] is the mode currently lit on screen.
  bool _isLit(FanState s, String m) =>
      m == 'boost' ? s.isBoost : s.activeMode == m;

  /// Turns OFF the mode that is currently lit.
  ///
  /// The fan never sends a frame that means "no mode". get_mc_state()
  /// (IRScan.c:1264) answers a 0x21 while a mode runs and a plain 0x04 once it
  /// stops, and the receive path deliberately ignores that 0x04 — so the chip
  /// has to be cleared here, on the tap that caused it.
  ///
  /// Which frame actually turns each mode off is read from the firmware:
  ///
  ///   reverse  SetSpeed clears `direction`      (case SPEED, IRScan.c:1361)
  ///   nature   SetSpeed clears `NatureFlage`    (SetSpeed,   IRScan.c:187)
  ///   boost    a speed < 7 drops OldTargetSpeed (case SPEED, IRScan.c:1369)
  ///   smart    ONLY power-ON clears smart_mode  (case POWER, IRScan.c:1347)
  ///
  /// Two deliberate choices:
  ///
  /// - Reverse is exited with a SPEED frame, never by re-sending Reverse.
  ///   Firmware Reverse is `direction ^= 0x01` (IRScan.c:1396) and its echo is
  ///   an unconditional `21 01 03` (IRScan.c:1402) whichever way the fan ended
  ///   up, so the echo cannot be trusted and a duplicate flips it straight back.
  ///   This is the same hazard that keeps WriteQueue on `retries: 0`.
  /// - Smart is exited with power-ON, which does NOT stop a running fan:
  ///   case POWER's on-branch restores `TargetSpeed = OldTargetSpeed`
  ///   (IRScan.c:1344), so the speed is unchanged.
  void _exitMode(String m, FanState s) {
    // Speed 7 IS Boost in this firmware, so a Boost exit must land on 1-6.
    // Where the stored speed is unusable, 3 matches what the firmware itself
    // falls back to when OldTargetSpeed is 0 (MoveForward, IRScan.c:763).
    final speed = (s.speed >= 1 && s.speed <= 6) ? s.speed : 3;
    final (List<int>? frame, String label) = switch (m) {
      // Power-ON is the ONLY thing that clears smart_mode. It cannot be used
      // for the others: its on-branch restores TargetSpeed = OldTargetSpeed,
      // which re-enters Boost when that is 7, and it never touches `direction`,
      // so it cannot exit Reverse either.
      'smart' => (BleFrameBuilder.powerOn(), 'Exit smart (power on)'),
      _       => (BleFrameBuilder.setSpeed(speed), 'Exit $m (speed $speed)'),
    };

    _flushSegment(newGear: speed, newMode: null);
    // The second and last sanctioned optimistic write on this screen, next to
    // the sleep timer. Required, not a convenience: none of the frames above
    // produce a 0x21 reply, and the 0x04 that does come back is ignored by
    // _applyFrame. Without this the chip could never turn off.
    ref
        .read(activeFanStateProvider(widget.fan.deviceId).notifier)
        .setModeHighlight(null);
    unawaited(widget.send(frame, label: label));
  }

  /// Mode button: one tap, one frame.
  ///
  /// Turning a mode ON is still pure dumb-remote — send that mode's frame and
  /// write no local state; the fan's own 0x21 echo lights the chip. Turning one
  /// OFF is the one case the fan cannot tell us about, so it is handled by
  /// [_exitMode].
  ///
  /// Still absent, and must stay absent: exit-reverse-first, mode-before-speed
  /// ordering, a Smart speed floor, and pre-Nature speed save/restore.
  void _onMode(String m) {
    final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));

    if (_isLit(fanState, m)) {
      _exitMode(m, fanState);
      return;
    }

    // Analytics only — the efficiency baseline for a Smart segment. Captured
    // before the segment flushes; influences no frame.
    if (m == 'smart') _smartBaselineGear = fanState.speed;
    _flushSegment(
      newGear: fanState.speed,
      newMode: m,
      smartBaselineGear: m == 'smart' ? _smartBaselineGear : null,
    );

    final frame = switch (m) {
      'nature'  => BleFrameBuilder.setNature(),
      'smart'   => BleFrameBuilder.setSmart(),
      'reverse' => BleFrameBuilder.setReverse(),
      _         => null,
    };
    unawaited(widget.send(frame, label: 'Mode: $m'));
  }

  /// Boost button: send the Boost frame, or exit Boost if it is already lit.
  void _onBoost() {
    final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));
    if (_isLit(fanState, 'boost')) {
      _exitMode('boost', fanState);
      return;
    }
    _flushSegment(newGear: fanState.speed, newMode: 'boost');
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
              // One dot, one speed frame — that part is unchanged.
              //
              // The chips are then updated from what this frame is KNOWN to do
              // in firmware, not from anything the fan replies. `case SPEED`
              // (IRScan.c:1357) runs SetSpeed(), which clears NatureFlage
              // (:187), and clears `direction` (:1361) and boost_flag (:1369).
              // It pointedly does NOT clear smart_mode — the IR remote's speed
              // buttons do (:592), the BLE path does not — so Smart stays lit.
              // Without this, leaving Nature by tapping a dot would strand the
              // Nature chip on forever: the fan answers 0x04, and _applyFrame
              // ignores a 0x04 for mode purposes.
              onSpeedSelected: (s) {
                final keepSmart = fanState.activeMode == 'smart';
                _flushSegment(newGear: s, newMode: keepSmart ? 'smart' : null);
                if (!keepSmart) {
                  ref
                      .read(activeFanStateProvider(fan.deviceId).notifier)
                      .setModeHighlight(null);
                }
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
              final code = switch (a) {
                '2h' => 0x02,
                '4h' => 0x04,
                '8h' => 0x08,
                _    => 0x00,
              };
              final notifier =
                  ref.read(activeFanStateProvider(fan.deviceId).notifier);
              notifier.updateTimer(
                code,
                // Record start time when activating so the countdown can compute
                // remaining time. Pass null when cancelling (timer off).
                activatedAt: code != 0 ? DateTime.now() : null,
              );
              // Arming any real timer silently turns Smart off in firmware:
              // `case TIMER` runs smart_mode = 0 for codes 2, 4 and 8
              // (IRScan.c:1424/1428/1432) but not for code 0. get_mc_state()
              // never reports Smart either way, so this tap is the only moment
              // the app can know. Nature and Reverse are untouched by the timer,
              // so they are left alone.
              if (code != 0 && fanState.activeMode == 'smart') {
                notifier.setModeHighlight(null);
              }
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
              setState(() => _isLightOn = true);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: _colorType, brightness: _brightnessValue, isOn: true);
              unawaited(widget.send(BleFrameBuilder.lightOn(),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
            onLightOff: () {
              setState(() => _isLightOn = false);
              ref.read(activeFanStateProvider(fan.deviceId).notifier)
                  .updateLighting(colorType: _colorType, brightness: _brightnessValue, isOn: false);
              unawaited(widget.send(BleFrameBuilder.lightOff(),
                  pendingMsg: 'Lighting commands pending from Terraton'));
            },
            onColorTypeChanged: (t) {
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
      // Expired while disconnected: shows briefly (≤~2 s) on reconnect until
      // the Machine State reply reports OFF and clears the chip. Deliberately
      // no self-clearing here — a build-tick widget mutating the provider is
      // riskier than the short "0s" window; firmware truth does the clearing.
      label = '0s REMAINING';
    } else {
      final h = remaining.inHours;
      final m = remaining.inMinutes.remainder(60);
      final s = remaining.inSeconds.remainder(60);
      label = h > 0
          ? '${h}h ${m}m ${s}s REMAINING'
          : (m > 0 ? '${m}m ${s}s REMAINING' : '${s}s REMAINING');
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
