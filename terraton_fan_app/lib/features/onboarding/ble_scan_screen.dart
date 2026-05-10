// lib/features/onboarding/ble_scan_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class BleScanScreen extends ConsumerStatefulWidget {
  const BleScanScreen({super.key});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen> {
  List<DiscoveredFan> _results = [];
  bool _scanning = true;
  bool _timedOut = false;
  StreamSubscription<List<DiscoveredFan>>? _sub;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth is off. Please enable Bluetooth to scan for fans.'),
        ));
      }
      if (Platform.isAndroid) unawaited(FlutterBluePlus.turnOn());
      return;
    }

    setState(() { _scanning = true; _timedOut = false; _results = []; });
    final ble = ref.read(bleServiceProvider);

    await _sub?.cancel();
    if (!mounted) return;
    _sub = ble.scanResultsStream.listen((fans) {
      if (mounted) setState(() => _results = fans);
    });

    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() { _scanning = false; _timedOut = _results.isEmpty; });
    });

    await ble.startScan(timeoutSeconds: 15);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    ref.read(bleServiceProvider).stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedMacs = {
      for (final f in ref.watch(savedFansProvider).value ?? const <FanDevice>[])
        if (f.macAddress.isNotEmpty) f.macAddress,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Fan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh scan',
            onPressed: _startScan,
          ),
        ],
      ),
      body: Builder(builder: (_) {
        if (_scanning && _results.isEmpty) {
          return const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning for fans…'),
            ],
          ));
        }
        if (_timedOut) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No fans found.',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              const Text('Make sure your fan is powered on.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                onPressed: _startScan,
              ),
            ],
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _results.length,
          itemBuilder: (_, i) {
            final fan = _results[i];
            final alreadyAdded = savedMacs.contains(fan.macAddress);
            return Card(
              child: ListTile(
                leading: const FanIcon(size: 24, color: kPrimary),
                title: Text(fan.name),
                subtitle: Text(fan.macAddress),
                trailing: alreadyAdded
                    ? Chip(
                        label: const Text('Already added',
                            style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.grey.shade200,
                      )
                    : Semantics(
                        label: 'Signal strength: ${_rssiLabel(fan.rssi)}',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.signal_cellular_alt,
                                size: 16,
                                color: _rssiColor(fan.rssi)),
                            Text('${fan.rssi} dBm',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                enabled: !alreadyAdded,
                onTap: alreadyAdded ? null : () {
                  final device = FanDevice()
                    ..deviceId   = fan.macAddress
                    ..macAddress = fan.macAddress
                    ..nickname   = ''
                    ..addedAt    = DateTime.now();
                  context.push(AppRoutes.nameFan, extra: device);
                },
              ),
            );
          },
        );
      }),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -80) return Colors.orange;
    return Colors.red;
  }

  String _rssiLabel(int rssi) {
    if (rssi >= -60) return 'strong';
    if (rssi >= -80) return 'fair';
    return 'weak';
  }
}
