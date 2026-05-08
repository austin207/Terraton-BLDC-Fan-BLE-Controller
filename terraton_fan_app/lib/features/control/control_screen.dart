// lib/features/control/control_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  late BleService _ble;

  @override
  void initState() {
    super.initState();
    // Cache before postFrameCallback — ref.read() throws inside dispose()
    // in Riverpod 2.x because _isDisposed is set before super.unmount().
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
          if (v != null) notifier.updateWatts(v);
        case 0x24:
          final v = BleResponseParser.parseRpm(response);
          if (v != null) notifier.updateRpm(v);
      }
    });
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      if (_ble.currentState != BleConnectionState.connected) return;
      final pFrame = BleFrameBuilder.queryPower();
      final sFrame = BleFrameBuilder.querySpeed();
      if (pFrame != null) await _ble.writeFrame(pFrame);
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
    final fanState  = ref.watch(activeFanStateProvider(widget.fan.deviceId));
    final connState = ref.watch(bleConnectionStateProvider).value
        ?? BleConnectionState.disconnected;
    final enabled   = connState == BleConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: Text(widget.fan.nickname)),
      body: Column(
        children: [
          ConnectionBanner(
            state: connState,
            onRetry: _connect,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
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

                  CircularSpeedDial(
                    currentSpeed: fanState.speed,
                    watts: fanState.lastWatts,
                    rpm: fanState.lastRpm,
                    enabled: enabled,
                    onSpeedSelected: (s) => _send(BleFrameBuilder.setSpeed(s)),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: enabled
                        ? () {
                            HapticFeedback.lightImpact();
                            _send(BleFrameBuilder.setBoost());
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fanState.isBoost
                          ? kBoostColor
                          : null,
                    ),
                    child: const Text('BOOST'),
                  ),
                  const SizedBox(height: 16),

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
                  const SizedBox(height: 16),

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
                  const SizedBox(height: 24),

                  LightingControlWidget(
                    enabled: enabled,
                    colorTempValue: _colorTempValue,
                    onLightOn: () => _send(
                      BleFrameBuilder.lightOn(),
                      pendingMsg: 'Lighting commands pending from Terraton',
                    ),
                    onLightOff: () => _send(
                      BleFrameBuilder.lightOff(),
                      pendingMsg: 'Lighting commands pending from Terraton',
                    ),
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
          ),
        ],
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
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onPower(!isPowered);
              }
            : null,
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
          child: Icon(
            Icons.power_settings_new,
            size: 36,
            color: isPowered ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
