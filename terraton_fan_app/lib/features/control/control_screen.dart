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

  bool _connecting = false;

  // Debug
  List<int>? _lastSentFrame;
  List<int>? _lastReceivedFrame;
  String     _lastSentLabel  = '';
  String?    _lastWriteError;

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
    } on Object catch (_) {
      // Connection failed — connectionStateStream emits disconnected, which
      // surfaces the ConnectionLostCard with a Retry button.
    } finally {
      if (mounted) _connecting = false;
    }
  }

  void _subscribeNotify() {
    unawaited(_notifySub?.cancel() ?? Future<void>.value());
    _notifySub = _ble.notifyStream.listen((bytes) {
      if (!mounted) return;
      setState(() => _lastReceivedFrame = bytes);
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
            // Speed > 0 from the module implies the fan is powered on.
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

      // Only query telemetry when fan is powered on — avoids flooding the
      // BLE module with query frames while the fan is off or during testing.
      final fanState = ref.read(activeFanStateProvider(widget.fan.deviceId));
      if (!fanState.isPowered) return;

      final pFrame = BleFrameBuilder.queryPower();
      final sFrame = BleFrameBuilder.querySpeed();
      try {
        if (pFrame != null) await _ble.writeFrame(pFrame);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        if (sFrame != null) await _ble.writeFrame(sFrame);
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
    if (mounted) {
      setState(() {
        _lastSentFrame  = frame;
        _lastSentLabel  = label;
        _lastWriteError = null;
      });
    }
    if (_isDemo) {
      _applyDemoFrame(frame);
      return;
    }
    try {
      await _ble.writeFrame(frame);
    } on Object catch (e) {
      // Surface write errors to the debug card; connection state stream handles reconnect.
      if (mounted) setState(() => _lastWriteError = e.toString());
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

    // Power button is always tappable when connected/demo.
    final enabled = _isDemo || connState == BleConnectionState.connected;
    // All other controls require the fan to also be powered on.
    final controlsEnabled   = enabled && fanState.isPowered;
    final isDisconnected     = !_isDemo && connState == BleConnectionState.disconnected;

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
            onPressed: () => unawaited(context.push(AppRoutes.settings)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 28, 20, isDisconnected ? 180 : 28),
            child: Column(
              children: [

                // ── Power button + hint ───────────────────────────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PowerButton(
                      isPowered: fanState.isPowered,
                      enabled: enabled,
                      onPower: (on) {
                        // Optimistic update — most modules don't echo a 0x02 response.
                        ref.read(activeFanStateProvider(widget.fan.deviceId).notifier)
                            .updatePower(on);
                        unawaited(_send(
                          on ? BleFrameBuilder.powerOn() : BleFrameBuilder.powerOff(),
                          label: on ? 'Power ON' : 'Power OFF',
                        ));
                      },
                    ),
                    const SizedBox(height: 8),
                    // Reserve space always so the layout doesn't jump
                    AnimatedOpacity(
                      opacity: enabled && !fanState.isPowered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: const Text(
                        'Tap to turn on',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Controls — grayed out until fan is powered on ─────────
                IgnorePointer(
                  ignoring: !controlsEnabled,
                  child: AnimatedOpacity(
                    opacity: controlsEnabled ? 1.0 : 0.55,
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
                        const SizedBox(height: 14),

                        // Boost button
                        _BoostButton(
                          isBoost: fanState.isBoost,
                          enabled: controlsEnabled,
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
                        const SizedBox(height: 12),

                        // Operating modes card
                        _SectionCard(
                          header: 'OPERATING MODES',
                          child: ModeControlWidget(
                            activeMode: fanState.activeMode,
                            enabled: controlsEnabled,
                            onMode: (m) {
                              final notifier = ref.read(activeFanStateProvider(widget.fan.deviceId).notifier);
                              if (fanState.activeMode == m) {
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
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Sleep timer card
                        _SectionCard(
                          header: 'SLEEP TIMER',
                          child: TimerControlWidget(
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
                        ),
                        const SizedBox(height: 10),

                        // Lighting card (already styled)
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

                // ── Debug card (always visible — outside the IgnorePointer) ─
                const SizedBox(height: 16),
                _DebugCard(
                  sentFrame: _lastSentFrame,
                  sentLabel: _lastSentLabel,
                  receivedFrame: _lastReceivedFrame,
                  writeCharStatus: _isDemo ? 'demo' : _ble.writeCharStatus,
                  connectStatus:   _isDemo ? 'demo' : _ble.connectStatus,
                  writeError: _lastWriteError,
                ),

              ],
            ),
          ),

          // ── Connection lost overlay ───────────────────────────────────
          if (isDisconnected)
            Positioned(
              bottom: 0, left: 0, right: 0,
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

          // Connect status line — surfaces retry attempts and timeouts so a
          // hanging "CONNECTING…" UI has visible diagnostic context.
          Row(
            children: [
              const Text('CONN ', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8), letterSpacing: 0.8,
              )),
              Expanded(
                child: Text(
                  connectStatus,
                  style: TextStyle(
                    fontSize: 10,
                    color: connectStatus == 'connected'
                        ? const Color(0xFF34D399)
                        : connectStatus.contains('failed')
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFFCD34D),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Char status line
          Row(
            children: [
              const Text('CHAR ', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8), letterSpacing: 0.8,
              )),
              Expanded(
                child: Text(
                  writeCharStatus,
                  style: TextStyle(
                    fontSize: 10,
                    color: writeCharStatus.startsWith('found')
                        ? const Color(0xFF34D399)
                        : writeCharStatus == 'pending' || writeCharStatus == 'disconnected'
                            ? const Color(0xFF64748B)
                            : const Color(0xFFFCA5A5),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sent frame
          _DebugRow(
            direction: 'TX',
            color: writeError != null
                ? const Color(0xFFFCA5A5)
                : const Color(0xFF34D399),
            label: sentFrame != null ? sentLabel : '—',
            hex: sentFrame != null ? _hex(sentFrame!) : '',
            decoded: sentFrame != null ? _frameLabel(sentFrame!) : '',
          ),

          // Write error (shown below TX if write failed)
          if (writeError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                'ERR: $writeError',
                style: const TextStyle(
                  fontSize: 10, fontFamily: 'monospace',
                  color: Color(0xFFFCA5A5), height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Received frame
          _DebugRow(
            direction: 'RX',
            color: const Color(0xFF818CF8),
            label: receivedFrame != null ? _frameLabel(receivedFrame!) : '—',
            hex: receivedFrame != null ? _hex(receivedFrame!) : '',
            decoded: '',
          ),
        ],
      ),
    );
  }
}

class _DebugRow extends StatelessWidget {
  final String direction;
  final Color color;
  final String label;
  final String hex;
  final String decoded;

  const _DebugRow({
    required this.direction,
    required this.color,
    required this.label,
    required this.hex,
    required this.decoded,
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
            child: Text(
              hex,
              style: const TextStyle(
                fontSize: 11, fontFamily: 'monospace',
                color: Color(0xFF94A3B8), letterSpacing: 0.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String header;
  final Widget child;
  const _SectionCard({required this.header, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(header),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7F95),
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Power button ──────────────────────────────────────────────────────────────

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
        duration: const Duration(milliseconds: 300),
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPowered ? kPrimary.withAlpha(14) : const Color(0xFFF1F5F9),
          border: Border.all(
            color: isPowered ? kPrimary.withAlpha(55) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPowered ? kPrimary : Colors.white,
              boxShadow: isPowered
                  ? [BoxShadow(color: kPrimary.withAlpha(80), blurRadius: 18, spreadRadius: 2)]
                  : [BoxShadow(color: Colors.black.withAlpha(14), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled
                    ? () {
                        unawaited(HapticFeedback.lightImpact());
                        onPower(!isPowered);
                      }
                    : null,
                child: Icon(
                  Icons.power_settings_new,
                  size: 30,
                  color: isPowered ? Colors.white : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Boost button ──────────────────────────────────────────────────────────────

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
    return Semantics(
      button: true,
      label: 'Boost mode',
      value: widget.isBoost ? 'active' : 'inactive',
      enabled: widget.enabled,
      child: GestureDetector(
        key: const ValueKey('boost_button'),
        onTap: widget.enabled
            ? () {
                unawaited(HapticFeedback.lightImpact());
                widget.onBoost();
              }
            : null,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: LayoutBuilder(
            builder: (_, constraints) => AnimatedBuilder(
              animation: _shimmerCtrl,
              child: _BoostLabel(enabled: widget.enabled),
              builder: (_, child) {
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
                    child: child,
                  );
                }

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
                      Positioned.fill(child: Center(child: child)),
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

class _BoostLabel extends StatelessWidget {
  final bool enabled;
  const _BoostLabel({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : Colors.grey.shade400;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          'BOOST MODE',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: color),
        ),
      ],
    );
  }
}
