// lib/shared/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/features/splash/splash_screen.dart';
import 'package:terraton_fan_app/features/home/home_screen.dart';
import 'package:terraton_fan_app/features/onboarding/qr_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/ble_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/name_fan_screen.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/permission/ble_permission_screen.dart';
import 'package:terraton_fan_app/features/settings/settings_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.permissionRequired,
      builder: (_, __) => const BlePermissionScreen(),
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
      // Deep links and back-stack restores arrive without a FanDevice extra;
      // redirect to home so the URL reflects where the user actually lands.
      redirect: (_, state) => state.extra == null ? AppRoutes.home : null,
      builder: (_, state) => NameFanScreen(fan: state.extra! as FanDevice),
    ),
    GoRoute(
      path: AppRoutes.control,
      redirect: (_, state) => state.extra == null ? AppRoutes.home : null,
      builder: (_, state) => ControlScreen(fan: state.extra! as FanDevice),
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
