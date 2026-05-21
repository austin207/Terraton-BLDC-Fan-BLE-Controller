// lib/features/control/control_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
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
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ControlScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const ControlScreen({super.key, required this.fan});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  Timer? _telemetryTimer;
  StreamSubscription<List<int>>? _notifySub;
  double _colorTempValue = 0.3;
  bool _isLightOn = false;
  late BleService _ble;
  DateTime? _lastWattsAt;
  DateTime? _lastRpmAt;

  bool _connecting = false;
  bool _showDisconnectAlert = false;

  // Debug state isolated in a ValueNotifier so only _DebugCard rebuilds on
  // each BLE notification — not the entire ControlScreen.
  final _debug = ValueNotifier(const _DebugSnapshot());

  bool get _isDemo => widget.fan.deviceId == '__demo__';

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    if (!_isDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final mac = widget.fan.macAddress.isNotEmpty ? widget.fan.macAddress : null;
    if (mac == null) return;

    _connecting = true;
    try {
      final returnedMac = await _ble.connect(mac);
      if (!mounted) return;

      if (widget.fan.macAddress.isEmpty && !_isDemo) {
        final repo = ref.read(fanRepositoryProvider);
        await repo.updateMac(widget.fan.deviceId, returnedMac);
        widget.fan.macAddress = returnedMac;
        if (!mounted) return;
        ref.invalidate(savedFansProvider);
      }

      _lastWattsAt = null;
      _lastRpmAt   = null;
      _startTelemetry();
      _subscribeNotify();
    } on Error {
      rethrow;
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
      switch (response.command) {
        case 0x02:
          final v = BleResponseParser.parsePowerState(response);
          if (v != null) notifier.updatePower(v);
        case 0x04:
          final v = BleResponseParser.parseSpeed(response);
          if (v != null) {
            notifier.updateSpeed(v);
            if (v > 0) notifier.updatePower(true);
          }
        case 0x21:
          final v = BleResponseParser.parseModeString(response);
          if (v != null) notifier.updateMode(v);
        case 0x22:
          final v = BleResponseParser.parseTimer(response);
          if (v != null) notifier.updateTimer(v);
        case 0x23:
          final v = BleResponseParser.parsePowerWatts(response);
          if (v != null) { notifier.updateWatts(v); _lastWattsAt = DateTime.now(); }
        case 0x24:
          final v = BleResponseParser.parseRpm(response);
          if (v != null) { notifier.updateRpm(v); _lastRpmAt = DateTime.now(); }
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
    _telemetryTimer?.cancel();
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
    switch (cmd) {
      case 0x02: notifier.updatePower(data == 0x01);
      case 0x04: notifier.updateSpeed(data);
      case 0x21:
        notifier.updateMode(switch (data) {
          0x01 => 'boost',
          0x02 => 'nature',
          0x03 => 'reverse',
          0x04 => 'smart',
          _    => null,
        });
      case 0x22: notifier.updateTimer(data);
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.fan.nickname,
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
            _connStatusLabel(connState),
          ],
        ),
        centerTitle: true,
        actions: [
          // Bluetooth icon top-right
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

                // ── Power button — 3-state: green (on) / red (off) / grey (disconnected)
                _PowerButton(
                  isPowered: fanState.isPowered,
                  isConnected: enabled, // true when connected or demo
                  onTap: () {
                    // Disconnected & trying to turn on → show alert instead
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

                // ── Controls — dimmed when fan is off ──────────────────────
                IgnorePointer(
                  ignoring: !controlsEnabled,
                  child: AnimatedOpacity(
                    opacity: controlsEnabled ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      children: [

                        // Speed dial
                        RepaintBoundary(
                          child: CircularSpeedDial(
                            currentSpeed: fanState.speed,
                            watts: fanState.lastWatts,
                            rpm: fanState.lastRpm,
                            enabled: controlsEnabled,
                            isBoost: fanState.isBoost,
                            onSpeedSelected: (s) {
                              ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                                  .updateSpeed(s);
                              unawaited(_send(BleFrameBuilder.setSpeed(s), label: 'Speed $s'));
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Operating modes (4-col grid including Boost)
                        const _SectionHeader('OPERATING MODES'),
                        const SizedBox(height: 10),
                        ModeControlWidget(
                          activeMode: fanState.activeMode,
                          isBoost: fanState.isBoost,
                          enabled: controlsEnabled,
                          onMode: (m) {
                            final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
                            if (fanState.activeMode == m && !fanState.isBoost) {
                              notifier.updateMode(null);
                              return;
                            }
                            notifier.updateMode(m);
                            final frame = switch (m) {
                              'nature'  => BleFrameBuilder.setNature(),
                              'reverse' => BleFrameBuilder.setReverse(),
                              'smart'   => BleFrameBuilder.setSmart(),
                              _         => null,
                            };
                            unawaited(_send(frame, label: 'Mode: $m'));
                          },
                          onBoost: () {
                            final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
                            if (fanState.isBoost) {
                              notifier.updateMode(null);
                            } else {
                              notifier.updateMode('boost');
                              unawaited(_send(BleFrameBuilder.setBoost(), label: 'Boost'));
                            }
                          },
                        ),

                        const SizedBox(height: 20),

                        // Sleep timer
                        _SectionHeader('SLEEP TIMER',
                            trailing: fanState.activeTimerCode != null && fanState.activeTimerCode != 0
                                ? Text(
                                    '${_timerLabel(fanState.activeTimerCode)} REMAINING',
                                    style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10, color: kYellow, fontWeight: FontWeight.w700, letterSpacing: 1.6),
                                  )
                                : null),
                        const SizedBox(height: 10),
                        TimerControlWidget(
                          activeTimerCode: fanState.activeTimerCode,
                          enabled: controlsEnabled,
                          onTimer: (a) {
                            final code = switch (a) {
                              '2h' => 0x02,
                              '4h' => 0x04,
                              '8h' => 0x08,
                              _    => 0x00,
                            };
                            ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                                .updateTimer(code);
                            final frame = switch (a) {
                              '2h'  => BleFrameBuilder.timer2h(),
                              '4h'  => BleFrameBuilder.timer4h(),
                              '8h'  => BleFrameBuilder.timer8h(),
                              _     => BleFrameBuilder.timerOff(),
                            };
                            unawaited(_send(frame, label: 'Timer: $a'));
                          },
                        ),

                        const SizedBox(height: 20),

                        // Lighting
                        LightingControlWidget(
                          enabled: controlsEnabled,
                          isLightOn: _isLightOn,
                          colorTempValue: _colorTempValue,
                          onLightOn: () {
                            setState(() => _isLightOn = true);
                            unawaited(_send(BleFrameBuilder.lightOn(),
                                pendingMsg: 'Lighting commands pending from Terraton'));
                          },
                          onLightOff: () {
                            setState(() => _isLightOn = false);
                            unawaited(_send(BleFrameBuilder.lightOff(),
                                pendingMsg: 'Lighting commands pending from Terraton'));
                          },
                          onColorTemp: (v) {
                            setState(() => _colorTempValue = v);
                            final byte = (v * 255).round().clamp(0, 255);
                            unawaited(_send(BleFrameBuilder.lightColorTemp(byte),
                                pendingMsg: 'Lighting commands pending from Terraton'));
                          },
                        ),

                      ],
                    ),
                  ),
                ),

                // ── Debug card ─────────────────────────────────────────────
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
            ),
          ),

          // Connection lost card (bottom-anchored, persistent while disconnected)
          if (isDisconnected)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: ConnectionLostCard(
                onRetry: _connect,
                connectStatus: _isDemo ? null : _ble.connectStatus,
              ),
            ),

          // Disconnect alert (centered modal — shown when user taps power while disconnected)
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

  Widget _connStatusLabel(BleConnectionState state) {
    if (_isDemo) {
      return Text('● DEMO MODE',
          style: GoogleFonts.manrope(fontSize: 10, color: Colors.amber.shade400,
              fontWeight: FontWeight.w700, letterSpacing: 1.5));
    }
    final (String text, Color color) = switch (state) {
      BleConnectionState.connected    => ('CONNECTED',    kYellow),
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => ('CONNECTING…', kYellowSoft),
      BleConnectionState.disconnected => ('DISCONNECTED', kTextDim),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state == BleConnectionState.connected)
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: kYellow,
              boxShadow: [BoxShadow(color: kYellowGlow, blurRadius: 6)],
            ),
          ),
        Text(text,
            style: GoogleFonts.manrope(fontSize: 10, color: color,
                fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ],
    );
  }

  static String _timerLabel(int? code) => switch (code) {
    0x02 => '2H',
    0x04 => '4H',
    0x08 => '8H',
    _    => '',
  };
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
              ? Color.lerp(const Color(0xFF409CFF), const Color(0xFF80BCFF), _blinkCtrl.value)!
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

// ── Power button — 3 visual states matching fan-control.jsx palette ─────────
//   green  : connected + powered on
//   red    : connected + powered off
//   grey   : disconnected (no BLE link)

class _PowerButton extends StatelessWidget {
  final bool isPowered;
  final bool isConnected; // true when BLE connected or demo
  final VoidCallback onTap;

  const _PowerButton({
    required this.isPowered,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Colours from fan-control.jsx palette
    final Color rim, iconColor, bgColor;
    final List<BoxShadow> shadows;

    if (!isConnected) {
      rim       = const Color(0x47FFFFFF);
      iconColor = const Color(0x8CFFFFFF);
      bgColor   = kCard;
      shadows   = const [BoxShadow(color: Color(0x0FFFFFFF), blurRadius: 8)];
    } else if (isPowered) {
      rim       = const Color(0xFF3FD37A);
      iconColor = const Color(0xFF3FD37A);
      bgColor   = const Color(0x1A3FD37A);
      shadows   = const [
        BoxShadow(color: Color(0x8C3FD37A), blurRadius: 14),
        BoxShadow(color: Color(0x4D3FD37A), blurRadius: 28),
      ];
    } else {
      rim       = const Color(0xFFE5484D);
      iconColor = const Color(0xFFE5484D);
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: rim, width: 1.5),
            boxShadow: shadows,
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            size: 26,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

// ── Disconnect alert overlay ──────────────────────────────────────────────────
// Shown as a centered modal (matching DisconnectAlert in fan-control.jsx) when
// the user taps the power button while the fan is not connected.

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
        color: Colors.black.withAlpha(178), // rgba(0,0,0,0.7)
        child: Center(
          child: GestureDetector(
            onTap: () {}, // stop propagation
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
                  // BT icon chip
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFEC00),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x47FFEC00)),
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
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700, color: kText,
                          ),
                        ),
                        const TextSpan(text: ' before powering it on.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
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
                    width: double.infinity,
                    height: 46,
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
    final cmd = bytes[3];
    final data = bytes.length > 5 ? bytes[5] : null;
    return switch (cmd) {
      0x02 => data == 0x01 ? 'Power ON' : 'Power OFF',
      0x04 => 'Speed ${data ?? '?'}',
      0x21 => switch (data) {
        0x01 => 'Boost',
        0x02 => 'Nature',
        0x03 => 'Reverse',
        0x04 => 'Smart',
        _    => 'Mode ?',
      },
      0x22 => switch (data) {
        0x00 => 'Timer OFF',
        0x02 => 'Timer 2h',
        0x04 => 'Timer 4h',
        0x08 => 'Timer 8h',
        _    => 'Timer ?',
      },
      0x23 => 'Query Power',
      0x24 => 'Query Speed',
      _    => 'cmd=0x${cmd.toRadixString(16).toUpperCase()}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3A5F)),
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
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('DEBUG', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: Color(0xFF60A5FA), letterSpacing: 1.2,
                )),
              ),
              const Spacer(),
              const Text('BLE FRAMES', style: TextStyle(
                fontSize: 10, color: Color(0xFF475569), letterSpacing: 1.0,
              )),
            ],
          ),
          const SizedBox(height: 10),
          _StatusRow(label: 'CONN', value: connectStatus,
            color: connectStatus == 'connected' ? const Color(0xFF34D399)
              : connectStatus.contains('failed') ? const Color(0xFFFCA5A5)
              : const Color(0xFFFCD34D)),
          const SizedBox(height: 6),
          _StatusRow(label: 'CHAR', value: writeCharStatus,
            color: writeCharStatus.startsWith('found') ? const Color(0xFF34D399)
              : writeCharStatus == 'pending' || writeCharStatus == 'disconnected'
                ? const Color(0xFF64748B)
                : const Color(0xFFFCA5A5)),
          const SizedBox(height: 10),
          _DebugRow(
            direction: 'TX',
            color: writeError != null ? const Color(0xFFFCA5A5) : const Color(0xFF34D399),
            label: sentFrame != null ? sentLabel : '—',
            hex: sentFrame != null ? _hex(sentFrame!) : '',
          ),
          if (writeError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text('ERR: $writeError', style: const TextStyle(
                fontSize: 10, fontFamily: 'monospace',
                color: Color(0xFFFCA5A5), height: 1.4,
              )),
            ),
          ],
          const SizedBox(height: 10),
          _DebugRow(
            direction: 'RX',
            color: const Color(0xFF818CF8),
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
        color: Color(0xFF94A3B8), letterSpacing: 0.8,
      )),
      Expanded(
        child: Text(value,
          style: TextStyle(fontSize: 10, color: color, fontFamily: 'monospace'),
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
              fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0),
            )),
          ],
        ),
        if (hex.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(hex, style: const TextStyle(
              fontSize: 11, fontFamily: 'monospace',
              color: Color(0xFF94A3B8), letterSpacing: 0.5, height: 1.6,
            )),
          ),
        ],
      ],
    );
  }
}
