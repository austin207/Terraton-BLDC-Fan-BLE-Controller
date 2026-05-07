// lib/features/control/control_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/ble_connection_state.dart';
import '../../core/ble/ble_frame_builder.dart';
import '../../core/ble/ble_response_parser.dart';
import '../../core/ble/ble_service.dart';
import '../../core/providers.dart';
import '../../models/fan_device.dart';
import 'connection_banner.dart';
import 'circular_speed_dial.dart';
import 'mode_control_widget.dart';
import 'timer_control_widget.dart';
import 'lighting_control_widget.dart';

class ControlScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const ControlScreen({super.key, required this.fan});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  Timer? _telemetryTimer;
  StreamSubscription? _notifySub;
  double _colorTempValue = 0.5;
  late BleService _ble;

  @override
  void initState() {
    super.initState();
    // Cache before postFrameCallback — ref.read() is forbidden inside dispose()
    // in Riverpod 2.x because _isDisposed is set before super.unmount().
    _ble = ref.read(bleServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final ble  = ref.read(bleServiceProvider);
    final repo = ref.read(fanRepositoryProvider);
    final mac  = widget.fan.macAddress.isNotEmpty ? widget.fan.macAddress : null;

    await ble.startScan(targetMac: mac, timeoutSeconds: 10);
    try {
      final returnedMac = await ble.connect();
      if (widget.fan.macAddress.isEmpty) {
        await repo.updateMac(widget.fan.deviceId, returnedMac);
        ref.invalidate(savedFansProvider);
      }
    } catch (_) {}

    _startTelemetry();
    _subscribeNotify();
  }

  void _subscribeNotify() {
    final ble = ref.read(bleServiceProvider);
    _notifySub = ble.notifyStream.listen((bytes) {
      final response = BleResponseParser.parse(bytes);
      if (response == null) return;
      final notifier = ref.read(activeFanStateProvider.notifier);
      switch (response.command) {
        case 0x02:
          final v = BleResponseParser.parsePowerState(response);
          if (v != null) notifier.updatePower(v);
        case 0x04:
          final v = BleResponseParser.parseSpeed(response);
          if (v != null) notifier.updateSpeed(v);
        case 0x21:
          final v = BleResponseParser.parseMode(response);
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
      final ble = ref.read(bleServiceProvider);
      if (ble.currentState != BleConnectionState.connected) return;
      final pFrame = BleFrameBuilder.queryPower();
      final sFrame = BleFrameBuilder.querySpeed();
      if (pFrame != null) await ble.writeFrame(pFrame);
      await Future.delayed(const Duration(milliseconds: 200));
      if (sFrame != null) await ble.writeFrame(sFrame);
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _notifySub?.cancel();
    _ble.disconnect();
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
    await ref.read(bleServiceProvider).writeFrame(frame);
  }

  @override
  Widget build(BuildContext context) {
    final fanState  = ref.watch(activeFanStateProvider);
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
                  // Power button
                  _PowerButton(
                    isPowered: fanState.isPowered,
                    enabled: enabled,
                    onPower: (on) => _send(
                      on ? BleFrameBuilder.powerOn() : BleFrameBuilder.powerOff(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Speed dial
                  CircularSpeedDial(
                    currentSpeed: fanState.speed,
                    watts: fanState.lastWatts,
                    rpm: fanState.lastRpm,
                    enabled: enabled,
                    onSpeedSelected: (s) => _send(BleFrameBuilder.setSpeed(s)),
                  ),
                  const SizedBox(height: 16),

                  // Boost button
                  ElevatedButton(
                    onPressed: enabled
                        ? () {
                            HapticFeedback.lightImpact();
                            _send(BleFrameBuilder.setBoost());
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fanState.isBoost
                          ? Colors.deepOrange
                          : null,
                    ),
                    child: const Text('BOOST'),
                  ),
                  const SizedBox(height: 16),

                  // Mode row
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

                  // Timer row
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

                  // Lighting
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
    return GestureDetector(
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
          color: isPowered ? const Color(0xFF1A56A0) : Colors.grey.shade300,
          boxShadow: isPowered
              ? [BoxShadow(color: const Color(0xFF1A56A0).withAlpha(100), blurRadius: 16)]
              : null,
        ),
        child: Icon(
          Icons.power_settings_new,
          size: 36,
          color: isPowered ? Colors.white : Colors.grey.shade600,
        ),
      ),
    );
  }
}
