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
  double _colorTempValue = 0.5;
  bool _isLightOn = false;
  late BleService _ble;
  DateTime? _lastWattsAt;
  DateTime? _lastRpmAt;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final repo = ref.read(fanRepositoryProvider);
    final mac  = widget.fan.macAddress.isNotEmpty ? widget.fan.macAddress : null;

    await _ble.startScan(targetMac: mac, timeoutSeconds: 10);
    if (!mounted) return;

    try {
      final returnedMac = await _ble.connect();
      if (!mounted) return;
      if (widget.fan.macAddress.isEmpty) {
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
    unawaited(_ble.disconnect());
    super.dispose();
  }

  Future<void> _send(List<int>? frame, {String? pendingMsg}) async {
    if (frame == null) {
      if (pendingMsg != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pendingMsg)));
      }
      return;
    }
    await _ble.writeFrame(frame);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<BluetoothAdapterState>>(
      bluetoothAdapterStateProvider,
      (prev, next) {
        if (prev?.hasValue != true) return; // skip initial emission
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
    final enabled   = connState == BleConnectionState.connected;
    final isDisconnected = connState == BleConnectionState.disconnected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.fan.nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
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
                    onSpeedSelected: (s) => _send(BleFrameBuilder.setSpeed(s)),
                  ),
                ),
                const SizedBox(height: 16),

                _BoostButton(
                  isBoost: fanState.isBoost,
                  enabled: enabled,
                  onBoost: () => _send(BleFrameBuilder.setBoost()),
                ),
                const SizedBox(height: 20),

                const _SectionHeader('OPERATING MODES'),
                const SizedBox(height: 8),
                ModeControlWidget(
                  activeMode: fanState.activeMode,
                  enabled: enabled,
                  onMode: (m) {
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
                    _send(
                      BleFrameBuilder.lightOn(),
                      pendingMsg: 'Lighting commands pending from Terraton',
                    );
                  },
                  onLightOff: () {
                    setState(() => _isLightOn = false);
                    _send(
                      BleFrameBuilder.lightOff(),
                      pendingMsg: 'Lighting commands pending from Terraton',
                    );
                  },
                  onColorTemp: (v) {
                    setState(() => _colorTempValue = v);
                    final byte = (v * 255).round();
                    _send(
                      BleFrameBuilder.lightColorTemp(byte),
                      pendingMsg: 'Lighting commands pending from Terraton',
                    );
                  },
                ),
              ],
            ),
          ),

          // Connection lost card — anchored to the bottom when disconnected
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
    final (String text, Color color) = switch (state) {
      BleConnectionState.connected    => ('● CONNECTED',     Colors.greenAccent.shade200),
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => ('● CONNECTING…',  Colors.amber.shade200),
      BleConnectionState.disconnected => ('DISCONNECTED',   Colors.white54),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade500,
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
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPowered ? kPrimary : Colors.grey.shade300,
          boxShadow: isPowered
              ? [BoxShadow(color: kPrimary.withAlpha(100), blurRadius: 16)]
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
              size: 36,
              color: isPowered ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoostButton extends StatelessWidget {
  final bool isBoost;
  final bool enabled;
  final VoidCallback onBoost;

  const _BoostButton({
    required this.isBoost,
    required this.enabled,
    required this.onBoost,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isBoost,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onBoost();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A2F5E),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: isBoost ? const BorderSide(color: Color(0xFF4A9FE8), width: 2) : null,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 20),
              SizedBox(width: 8),
              Text(
                'BOOST MODE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
