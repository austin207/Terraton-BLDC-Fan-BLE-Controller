// lib/shared/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/qr_scan_screen.dart';
import '../features/onboarding/ble_scan_screen.dart';
import '../features/onboarding/name_fan_screen.dart';
import '../features/control/control_screen.dart';
import '../features/settings/settings_screen.dart';
import '../models/fan_device.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/scan/qr',
      builder: (_, __) => const QrScanScreen(),
    ),
    GoRoute(
      path: '/scan/ble',
      builder: (_, __) => const BleScanScreen(),
    ),
    GoRoute(
      path: '/name-fan',
      builder: (context, state) {
        final fan = state.extra as FanDevice;
        return NameFanScreen(fan: fan);
      },
    ),
    GoRoute(
      path: '/control',
      builder: (context, state) {
        final fan = state.extra as FanDevice;
        return ControlScreen(fan: fan);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
  ],
);

/// Shows a bottom sheet letting the user pick QR scan or BLE scan.
void goToOnboarding(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('How would you like to add your fan?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: const Text('Search via Bluetooth'),
            subtitle: const Text('Scan for nearby fans'),
            onTap: () { Navigator.pop(sheetCtx); context.push('/scan/ble'); },
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan QR Code'),
            subtitle: const Text('Scan the QR code on your fan packaging'),
            onTap: () { Navigator.pop(sheetCtx); context.push('/scan/qr'); },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
