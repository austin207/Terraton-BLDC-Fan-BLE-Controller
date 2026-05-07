// lib/features/onboarding/qr_scan_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/fan_device.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _checkCamera();
  }

  Future<void> _checkCamera() async {
    final status = await Permission.camera.status;
    if (status.isDenied) {
      final result = await Permission.camera.request();
      if (!result.isGranted && mounted) {
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text('Camera access is needed to scan QR codes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final deviceId  = json['device_id']  as String?;
      final model     = json['model']      as String?;
      final fwVersion = json['fw_version'] as String?;

      if (deviceId == null || model == null || fwVersion == null) {
        _showInvalidSnack();
        return;
      }

      _handled = true;
      final fan = FanDevice()
        ..deviceId  = deviceId
        ..model     = model
        ..fwVersion = fwVersion
        ..nickname  = model
        ..addedAt   = DateTime.now();

      if (mounted) context.push('/name-fan', extra: fan);
    } catch (_) {
      _showInvalidSnack();
    }
  }

  void _showInvalidSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Invalid QR code. Please scan the code on your Terraton fan packaging.'),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Fan QR Code')),
      body: MobileScanner(
        controller: _ctrl,
        onDetect: _onDetect,
      ),
    );
  }
}
