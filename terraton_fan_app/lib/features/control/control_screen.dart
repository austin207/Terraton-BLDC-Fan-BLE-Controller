// lib/features/control/control_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final repo = ref.read(fanRepositoryProvider);
    final mac  = widget.fan.macAddress.isNotEmpty ? widget.fan.macAddress : null;

    await _ble.startScan(targetMac: mac, timeoutSeconds: 10);
    if (!mounted) return;

    try {
      final returnedMac = await _ble.connect();
      if (!mounted) return;
      if (widget.fan.macAddress.isEmpty && !_isDemo) {
        await repo.updateMac(widget.fan.deviceId, returnedMac);
        if (!mounted) return;
        ref.invalidate(savedFansProvider);
      }
    } on Object catch (_) {
      if (!mounted) return;
      return;
    }

    _startTelemetry();
    _subscribeNotify();
  }

  void _subscribeNotify() {
    _notifySub = _ble.notifyStream.listen((bytes) {
      if (!mounted) return;
      final response = BleResponseParser.parse(bytes);
      if (response == null) return;
      final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
      switch (response.command) {
        case 0x02:
          final v = BleResponseParser.parsePowerState(response);
          if (v != null) notifier.updatePower(v);
        case 0x04:
          final v = BleResponseParser.parseSpeed(response);
          if (v != null) notifier.updateSpeed(v);
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

      final pFrame = BleFrameBuilder.queryPower();
      final sFrame = BleFrameBuilder.querySpeed();
      if (pFrame != null) await _ble.writeFrame(pFrame);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (sFrame != null) await _ble.writeFrame(sFrame);
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _notifySub?.cancel();
    if (!_isDemo) unawaited(_ble.disconnect());
    super.dispose();
  }

  // In demo mode: apply the frame directly to local state instead of writing BLE.
  // Frame format: [0x55, 0xAA, 0x06, cmd, dataLen, data..., checksum]
  void _applyDemoFrame(List<int> frame) {
    if (frame.length < 6) return;
    final cmd  = frame[3];
    final data = frame[5];
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

  Future<void> _send(List<int>? frame, {String? pendingMsg}) async {
    if (frame == null) {
      // Suppress snackbars in demo mode (lighting is locally toggled via setState)
      if (pendingMsg != null && mounted && !_isDemo) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pendingMsg)));
      }
      return;
    }
    if (_isDemo) {
      _applyDemoFrame(frame);
      return;
    }
    await _ble.writeFrame(frame);
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
    final enabled       = _isDemo || connState == BleConnectionState.connected;
    final isDisconnected = !_isDemo && connState == BleConnectionState.disconnected;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black54),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.fan.nickname,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87)),
            _connectionStatusLabel(connState),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, isDisconnected ? 180 : 24),
            child: Column(
              children: [
                _PowerButton(
                  isPowered: fanState.isPowered,
                  enabled: enabled,
                  onPower: (on) => _send(
                    on ? BleFrameBuilder.powerOn() : BleFrameBuilder.powerOff(),
                  ),
                ),
                const SizedBox(height: 24),

                RepaintBoundary(
                  child: CircularSpeedDial(
                    currentSpeed: fanState.speed,
                    watts: fanState.lastWatts,
                    rpm: fanState.lastRpm,
                    enabled: enabled,
                    isBoost: fanState.isBoost,
                    onSpeedSelected: (s) => _send(BleFrameBuilder.setSpeed(s)),
                  ),
                ),
                const SizedBox(height: 16),

                _BoostButton(
                  isBoost: fanState.isBoost,
                  enabled: enabled,
                  onBoost: () {
                    if (fanState.isBoost) {
                      // Toggle off — no protocol cancel command; clear local state.
                      ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                          .updateMode(null);
                    } else {
                      _send(BleFrameBuilder.setBoost());
                    }
                  },
                ),
                const SizedBox(height: 20),

                const _SectionHeader('OPERATING MODES'),
                const SizedBox(height: 8),
                ModeControlWidget(
                  activeMode: fanState.activeMode,
                  enabled: enabled,
                  onMode: (m) {
                    if (fanState.activeMode == m) {
                      // Toggle off — no protocol command exists to cancel a mode;
                      // clear local state so the button deselects visually.
                      ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                          .updateMode(null);
                      return;
                    }
                    final frame = switch (m) {
                      'nature'  => BleFrameBuilder.setNature(),
                      'reverse' => BleFrameBuilder.setReverse(),
                      'smart'   => BleFrameBuilder.setSmart(),
                      _         => null,
                    };
                    _send(frame);
                  },
                ),
                const SizedBox(height: 20),

                const _SectionHeader('SLEEP TIMER'),
                const SizedBox(height: 8),
                TimerControlWidget(
                  activeTimerCode: fanState.activeTimerCode,
                  enabled: enabled,
                  onTimer: (a) {
                    final frame = switch (a) {
                      '2h'  => BleFrameBuilder.timer2h(),
                      '4h'  => BleFrameBuilder.timer4h(),
                      '8h'  => BleFrameBuilder.timer8h(),
                      _     => BleFrameBuilder.timerOff(),
                    };
                    _send(frame);
                  },
                ),
                const SizedBox(height: 20),

                LightingControlWidget(
                  enabled: enabled,
                  isLightOn: _isLightOn,
                  colorTempValue: _colorTempValue,
                  onLightOn: () {
                    setState(() => _isLightOn = true);
                    _send(BleFrameBuilder.lightOn(),
                        pendingMsg: 'Lighting commands pending from Terraton');
                  },
                  onLightOff: () {
                    setState(() => _isLightOn = false);
                    _send(BleFrameBuilder.lightOff(),
                        pendingMsg: 'Lighting commands pending from Terraton');
                  },
                  onColorTemp: (v) {
                    setState(() => _colorTempValue = v);
                    final byte = (v * 255).round();
                    _send(BleFrameBuilder.lightColorTemp(byte),
                        pendingMsg: 'Lighting commands pending from Terraton');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          if (isDisconnected)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ConnectionLostCard(onRetry: _connect),
            ),
        ],
      ),
    );
  }

  Widget _connectionStatusLabel(BleConnectionState state) {
    if (_isDemo) {
      return Text('● DEMO MODE',
          style: TextStyle(fontSize: 11, color: Colors.amber.shade700, letterSpacing: 0.5));
    }
    final (String text, Color color) = switch (state) {
      BleConnectionState.connected    => ('● CONNECTED',    const Color(0xFF16A34A)),
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => ('● CONNECTING…', const Color(0xFFF59E0B)),
      BleConnectionState.disconnected => ('DISCONNECTED',  Colors.black45),
    };
    return Text(text, style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.5));
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7F95),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool isPowered;
  final bool enabled;
  final void Function(bool) onPower;

  const _PowerButton({
    required this.isPowered,
    required this.enabled,
    required this.onPower,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Power',
      value: isPowered ? 'on' : 'off',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPowered ? kPrimary : Colors.grey.shade300,
          boxShadow: isPowered
              ? [BoxShadow(color: kPrimary.withAlpha(80), blurRadius: 20, spreadRadius: 2)]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPower(!isPowered);
                  }
                : null,
            child: Icon(
              Icons.power_settings_new,
              size: 32,
              color: isPowered ? Colors.white : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoostButton extends StatefulWidget {
  final bool isBoost;
  final bool enabled;
  final VoidCallback onBoost;

  const _BoostButton({
    required this.isBoost,
    required this.enabled,
    required this.onBoost,
  });

  @override
  State<_BoostButton> createState() => _BoostButtonState();
}

class _BoostButtonState extends State<_BoostButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  bool get _showShimmer => widget.isBoost && widget.enabled;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (_showShimmer) _shimmerCtrl.repeat();
  }

  @override
  void didUpdateWidget(_BoostButton old) {
    super.didUpdateWidget(old);
    final wasShimmer = old.isBoost && old.enabled;
    if (_showShimmer && !wasShimmer) {
      _shimmerCtrl.repeat();
    } else if (!_showShimmer && wasShimmer) {
      _shimmerCtrl
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bolt,
          size: 20,
          color: widget.enabled ? Colors.white : Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        Text(
          'BOOST MODE',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: widget.enabled ? Colors.white : Colors.grey.shade400,
          ),
        ),
      ],
    );

    return Semantics(
      selected: widget.isBoost,
      child: GestureDetector(
        key: const ValueKey('boost_button'),
        onTap: widget.enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onBoost();
              }
            : null,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: LayoutBuilder(
            builder: (_, constraints) => AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (_, __) {
                if (!_showShimmer) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? const Color(0xFF1A2F5E)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: label,
                  );
                }

                // Sharp gradient background + moving shimmer stripe
                const shimmerW = 90.0;
                final shimX = _shimmerCtrl.value *
                    (constraints.maxWidth + shimmerW) -
                    shimmerW;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFBF2600),
                                Color(0xFFFF5500),
                                Color(0xFFCC2200),
                              ],
                              begin: Alignment(-1, -0.5),
                              end: Alignment(1, 0.5),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: shimX,
                        top: 0,
                        bottom: 0,
                        width: shimmerW,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white.withAlpha(0),
                                Colors.white.withAlpha(45),
                                Colors.white.withAlpha(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(child: Center(child: label)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
