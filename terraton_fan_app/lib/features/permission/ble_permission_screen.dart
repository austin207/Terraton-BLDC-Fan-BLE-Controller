// lib/features/permission/ble_permission_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class BlePermissionScreen extends StatefulWidget {
  const BlePermissionScreen({super.key});

  @override
  State<BlePermissionScreen> createState() => _BlePermissionScreenState();
}

class _BlePermissionScreenState extends State<BlePermissionScreen> {
  bool _loading        = false;
  bool _permanentDeny  = false;
  String? _errorMsg;

  static const _required = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];

  Future<void> _request() async {
    setState(() { _loading = true; _errorMsg = null; });

    final statuses = await _required.request();

    if (!mounted) return;

    final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);
    final anyPermanent = statuses.values.any((s) => s.isPermanentlyDenied);

    if (allGranted) {
      // Best-effort: turn Bluetooth on now that we have permission.
      try {
        if (Platform.isAndroid &&
            FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
          await FlutterBluePlus.turnOn();
        }
      } on Object catch (_) {}
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    setState(() {
      _loading       = false;
      _permanentDeny = anyPermanent;
      _errorMsg = anyPermanent
          ? 'Permission permanently denied. Open Settings to grant access.'
          : 'Some permissions were denied. Please allow them to use the app.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withAlpha(60),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const FanIcon(size: 46),
              ),
              const SizedBox(height: 32),

              const Text(
                'Bluetooth Access Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2C4E),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Terraton Fan Controller needs Bluetooth permissions '
                'to scan for and connect to your fan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.blueGrey.shade600,
                ),
              ),
              const SizedBox(height: 8),

              // Permission list
              const _PermissionRow(
                icon: Icons.bluetooth,
                label: 'Bluetooth Scan & Connect',
                description: 'To find and pair with your fan',
              ),

              const SizedBox(height: 28),

              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_permanentDeny) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open App Settings'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _request,
                  child: const Text('Try Again'),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _request,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bluetooth, size: 18),
                    label: Text(_loading ? 'Requesting…' : 'Grant Permissions'),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => context.go(AppRoutes.home),
                child: Text(
                  'Use Demo Mode Instead',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blueGrey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPrimary.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: kPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
