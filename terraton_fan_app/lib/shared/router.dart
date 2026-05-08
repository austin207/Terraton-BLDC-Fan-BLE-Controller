// lib/shared/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/features/home/home_screen.dart';
import 'package:terraton_fan_app/features/onboarding/qr_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/ble_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/name_fan_screen.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/settings/settings_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.scanQr,
      builder: (_, __) => const QrScanScreen(),
    ),
    GoRoute(
      path: AppRoutes.scanBle,
      builder: (_, __) => const BleScanScreen(),
    ),
    GoRoute(
      path: AppRoutes.nameFan,
      builder: (context, state) {
        // Redirect to home if extra is missing (e.g. deep link or back-stack restore).
        final fan = state.extra as FanDevice?;
        if (fan == null) return const HomeScreen();
        return NameFanScreen(fan: fan);
      },
    ),
    GoRoute(
      path: AppRoutes.control,
      builder: (context, state) {
        final fan = state.extra as FanDevice?;
        if (fan == null) return const HomeScreen();
        return ControlScreen(fan: fan);
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
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
            onTap: () {
              Navigator.of(sheetCtx).pop();
              context.push(AppRoutes.scanBle);
            },
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan QR Code'),
            subtitle: const Text('Scan the QR code on your fan packaging'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              context.push(AppRoutes.scanQr);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
