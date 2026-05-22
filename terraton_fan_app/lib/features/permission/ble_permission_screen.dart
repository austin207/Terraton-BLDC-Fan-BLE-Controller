// lib/features/permission/ble_permission_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
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

    final allGranted  = statuses.values.every((s) => s.isGranted || s.isLimited);
    final anyPermanent = statuses.values.any((s) => s.isPermanentlyDenied);

    if (allGranted) {
      try {
        if (Platform.isAndroid &&
            FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
          await FlutterBluePlus.turnOn();
        }
      } on Object catch (_) {}
      if (!mounted) return;
      final firstLaunch = await AppSettings.isFirstLaunch();
      if (!mounted) return;
      context.go(firstLaunch ? AppRoutes.profileSetup : AppRoutes.home);
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
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 12, 32, 4),
              child: BrandMark(height: 40),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Fan icon with glow
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kYellow.withAlpha(20),
                  border: Border.all(color: kYellow.withAlpha(50)),
                  boxShadow: [const BoxShadow(color: kYellowGlow, blurRadius: 40)],
                ),
                child: const TerratonFanIcon(size: 70),
              ),
              const SizedBox(height: 32),

              Text(
                'Bluetooth Access Required',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 22, fontWeight: FontWeight.w800, color: kText,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Terraton Fan Controller needs Bluetooth permissions '
                'to scan for and connect to your fan.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14, height: 1.55, color: kTextMut,
                ),
              ),
              const SizedBox(height: 28),

              // Permission row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kHairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: kYellow.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bluetooth_rounded, size: 18, color: kYellow),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bluetooth Scan & Connect',
                              style: GoogleFonts.manrope(
                                fontSize: 13, fontWeight: FontWeight.w600, color: kText,
                              )),
                          Text('To find and pair with your fan',
                              style: GoogleFonts.manrope(fontSize: 11, color: kTextMut)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Error message
              if (_errorMsg != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: kRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kRed.withAlpha(80)),
                  ),
                  child: Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(fontSize: 13, color: kRed),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_permanentDeny) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => unawaited(openAppSettings()),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open App Settings'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _request,
                  child: Text('Try Again',
                      style: GoogleFonts.manrope(color: kTextMut, fontSize: 13)),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _request,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text('Grant Permissions',
                            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              TextButton(
                onPressed: _loading ? null : () async {
                  final firstLaunch = await AppSettings.isFirstLaunch();
                  if (!context.mounted) return;
                  context.go(firstLaunch ? AppRoutes.profileSetup : AppRoutes.home);
                },
                child: Text(
                  'Use Demo Mode Instead',
                  style: GoogleFonts.manrope(fontSize: 13, color: kTextDim),
                ),
              ),
                ],         // closes inner Column children
              ),           // closes inner Column
            ),             // closes Padding
          ),               // closes Expanded
        ],                 // closes outer Column children
      ),                   // closes outer Column
      ),                   // closes SafeArea
    );
  }
}
