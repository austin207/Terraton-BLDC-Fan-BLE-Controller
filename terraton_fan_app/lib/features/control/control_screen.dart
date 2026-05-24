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
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/features/control/connection_banner.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';
import 'package:terraton_fan_app/features/control/lighting_control_widget.dart';
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

class _ControlScreenState extends ConsumerState<ControlScreen> {
  Timer? _telemetryTimer;
  Timer? _expiryTimer;
  Timer? _expiryOnceTimer;
  StreamSubscription<List<int>>? _notifySub;
  late BleService _ble;
  DateTime? _lastWattsAt;
  DateTime? _lastRpmAt;
  Duration  _serviceRemaining = Duration.zero;

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleServiceExpiry());
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
    ref.invalidate(savedFansProvider);
    if (!mounted) return;
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
      _startTelemetry();
      _subscribeNotify();
    } on Object catch (_) {
      // Expected connection Exception — connectionStateStream emits disconnected,
      // surfacing the ConnectionLostCard with a Retry button.
    } finally {
      if (mounted) _connecting = false;
    }
  }

  void _subscribeNotify() {
    unawaited(_notifySub?.cancel() ?? Future<void>.value());
    _notifySub = _ble.notifyStream.listen((bytes) {
      if (!mounted) return;
      _debug.value = _debug.value.copyWith(receivedFrame: bytes);
      final response = BleResponseParser.parse(bytes);
      if (response == null) return;
      final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
      final power = BleResponseParser.parsePowerState(response);
      if (power != null) { notifier.updatePower(power); return; }
      final speed = BleResponseParser.parseSpeed(response);
      if (speed != null) {
        notifier.updateSpeed(speed);
        if (speed > 0) notifier.updatePower(true);
        return;
      }
      final mode = BleResponseParser.parseModeString(response);
      if (mode != null) { notifier.updateMode(mode); return; }
      final timer = BleResponseParser.parseTimer(response);
      if (timer != null) { notifier.updateTimer(timer); return; }
      final watts = BleResponseParser.parsePowerWatts(response);
      if (watts != null) { notifier.updateWatts(watts); _lastWattsAt = DateTime.now(); return; }
      final rpm = BleResponseParser.parseRpm(response);
      if (rpm != null) { notifier.updateRpm(rpm); _lastRpmAt = DateTime.now(); }
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

      final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));
      if (!fanState.isPowered) return;

      try {
        await _ble.writeFrame(BleFrameBuilder.statusPoll());
        if (!mounted) return;
      } on Object catch (_) {
        // Fan disconnected mid-poll; connection state stream handles recovery.
      }
    });
  }

  @override
  void dispose() {
    _connecting = false;
    _telemetryTimer?.cancel();
    _expiryTimer?.cancel();
    _expiryOnceTimer?.cancel();
    unawaited(_notifySub?.cancel() ?? Future<void>.value());
    if (!_isDemo) unawaited(_ble.disconnect());
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
      notifier.updateMode(switch (data) {
        0x01 => 'boost',
        0x02 => 'nature',
        0x03 => 'reverse',
        0x04 => 'smart',
        _    => null,
      });
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
                IgnorePointer(
                  ignoring: !controlsEnabled,
                  child: AnimatedOpacity(
                    opacity: controlsEnabled ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 300),
                    child: _FanControlsPanel(
                      fan: widget.fan,
                      controlsEnabled: controlsEnabled,
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
  final bool controlsEnabled;
  final _SendFn send;

  const _FanControlsPanel({
    required this.fan,
    required this.controlsEnabled,
    required this.send,
  });

  @override
  ConsumerState<_FanControlsPanel> createState() => _FanControlsPanelState();
}

class _FanControlsPanelState extends ConsumerState<_FanControlsPanel> {
  String _colorType       = 'warm';
  double _brightnessValue = 0.7;
  bool   _isLightOn       = false;

  // ── Usage-log segment tracker ──────────────────────────────────────────────
  DateTime? _segmentStart;
  int   _segmentGear = 0;
  String? _segmentMode;

  // Speed saved when Nature mode activates — restored when switching to Smart/Reverse.
  int _preNatureSpeed = 0;

  @override
  void initState() {
    super.initState();
    final s = ref.read(activeFanStateProvider(widget.fan.deviceId));
    // Seed _preNatureSpeed so that if the fan is loaded from ObjectBox already
    // in Nature mode, a subsequent switch to Smart/Reverse has a speed to restore.
    if (s.activeMode == 'nature' && s.speed > 0) {
      _preNatureSpeed = s.speed;
    }
    // Restore lighting UI state from last persisted values.
    _colorType       = s.lastLightColorType;
    _brightnessValue = s.lastLightBrightness;
    _isLightOn       = s.lastLightIsOn;
  }

  /// Flush the completed segment to ObjectBox, then start a new one.
  /// Watts are read from the live fan state at flush time.
  void _flushSegment({required int newGear, required String? newMode}) {
    final start = _segmentStart;
    if (start != null && _segmentGear > 0) {
      final secs = DateTime.now().difference(start).inSeconds;
      if (secs > 0) {
        final watts = ref
            .read(activeFanStateProvider(widget.fan.deviceId))
            .lastWatts ?? 0;
        try {
          ref.read(usageLogRepositoryProvider).addLog(UsageLog(
            deviceId:    widget.fan.deviceId,
            startTime:   start,
            durationSecs: secs,
            gear:        _segmentGear,
            watts:       watts,
            mode:        _segmentMode,
          ));
        } on Object catch (_) {
          // Store teardown or disk-full; segment is lost but app must not crash.
        }
      }
    }
    _segmentStart = DateTime.now();
    _segmentGear  = newGear;
    _segmentMode  = newMode;
  }

  static String _timerLabel(int? code) => switch (code) {
    0x02 => '2H',
    0x04 => '4H',
    0x08 => '8H',
    _    => '',
  };

  void _onMode(String m) {
    final fan      = widget.fan;
    final fanState = ref.read(activeFanStateProvider(fan.deviceId));
    final notifier = ref.read(activeFanStateProvider(fan.deviceId).notifier);

    // Tapping the already-active mode toggles it off.
    if (fanState.activeMode == m) {
      _flushSegment(newGear: fanState.speed, newMode: null);
      notifier.setActiveMode(null);
      if (fanState.speed > 0) {
        unawaited(widget.send(BleFrameBuilder.setSpeed(fanState.speed),
            label: 'Speed ${fanState.speed}'));
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
      notifier.setActiveMode(m);
      if (restore > 0) notifier.updateSpeed(restore);
      _flushSegment(newGear: restore > 0 ? restore : fanState.speed, newMode: m);
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
    if (m == 'smart' && fanState.speed > 0 && fanState.speed < 3) {
      notifier.updateSpeed(3);
      unawaited(widget.send(BleFrameBuilder.setSpeed(3), label: 'Speed 3 (Smart)'));
    }
    _flushSegment(newGear: fanState.speed, newMode: m);
    notifier.setActiveMode(m);
    final frame = switch (m) {
      'reverse' => BleFrameBuilder.setReverse(),
      'smart'   => BleFrameBuilder.setSmart(),
      _         => null,
    };
    unawaited(widget.send(frame, label: 'Mode: $m'));
  }

  void _onBoost() {
    final fan      = widget.fan;
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

    if (fanState.isBoost) {
      _flushSegment(newGear: fanState.speed, newMode: fanState.activeMode);
      notifier.setBoostActive(false);
      final restoreFrame = switch (fanState.activeMode) {
        'reverse' => BleFrameBuilder.setReverse(),
        'smart'   => BleFrameBuilder.setSmart(),
        _         => null,
      };
      if (restoreFrame != null) {
        unawaited(widget.send(restoreFrame, label: 'Mode: ${fanState.activeMode}'));
      }
    } else {
      _flushSegment(newGear: fanState.speed, newMode: 'boost');
      notifier.setBoostActive(true);
      unawaited(widget.send(BleFrameBuilder.setBoost(), label: 'Boost'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fan      = widget.fan;
    final enabled  = widget.controlsEnabled;
    final fanState = ref.watch(activeFanStateProvider(fan.deviceId));

    return Column(
      children: [

        // ── Speed dial ──────────────────────────────────────────────────────
        RepaintBoundary(
          child: CircularSpeedDial(
            currentSpeed: fanState.speed,
            watts: fanState.lastWatts,
            rpm: fanState.lastRpm,
            enabled: enabled,
            isBoost: fanState.isBoost,
            isNature: fanState.activeMode == 'nature',
            disabledSpeeds: fanState.activeMode == 'smart' ? const {1, 2} : const {},
            onSpeedSelected: (s) {
              if (fanState.activeMode == 'smart' && s < 3) return;
              final notifier = ref.read(activeFanStateProvider(fan.deviceId).notifier);
              if (fanState.isBoost) {
                notifier.setBoostActive(false);
                if (fanState.activeMode == 'reverse') {
                  unawaited(widget.send(BleFrameBuilder.setReverse(), label: 'Mode: reverse'));
                } else if (fanState.activeMode == 'smart') {
                  unawaited(widget.send(BleFrameBuilder.setSmart(), label: 'Mode: smart'));
                }
              }
              _flushSegment(newGear: s, newMode: fanState.activeMode);
              notifier.updateSpeed(s);
              unawaited(widget.send(BleFrameBuilder.setSpeed(s), label: 'Speed $s'));
            },
          ),
        ),

        const SizedBox(height: 12),

        // ── Operating modes ─────────────────────────────────────────────────
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

        // ── Sleep timer ─────────────────────────────────────────────────────
        _SectionHeader(
          'SLEEP TIMER',
          trailing: fanState.activeTimerCode != null && fanState.activeTimerCode != 0
              ? Text(
                  '${_timerLabel(fanState.activeTimerCode)} REMAINING',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, color: kYellow,
                      fontWeight: FontWeight.w700, letterSpacing: 1.6),
                )
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
            ref.read(activeFanStateProvider(fan.deviceId).notifier).updateTimer(code);
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

        // ── Mood lighting ───────────────────────────────────────────────────
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
              ? Color.lerp(const Color(0xFF409CFF), const Color(0x1A409CFF), _blinkCtrl.value)!
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
      rim       = const Color(0x47FFFFFF);
      iconColor = const Color(0x8CFFFFFF);
      bgColor   = kCard;
      shadows   = const [BoxShadow(color: kHairline, blurRadius: 8)];
    } else if (isPowered) {
      rim       = kPowerOn;
      iconColor = kPowerOn;
      bgColor   = const Color(0x1A3FD37A);
      shadows   = const [
        BoxShadow(color: Color(0x8C3FD37A), blurRadius: 14),
        BoxShadow(color: Color(0x4D3FD37A), blurRadius: 28),
      ];
    } else {
      rim       = kPowerOff;
      iconColor = kPowerOff;
      bgColor   = const Color(0x14E5484D);
      shadows   = const [
        BoxShadow(color: Color(0x4DE5484D), blurRadius: 10),
        BoxShadow(color: Color(0x26E5484D), blurRadius: 22),
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
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 80)],
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
