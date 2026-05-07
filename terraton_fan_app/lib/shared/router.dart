// lib/shared/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/config/app_config.dart';
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

/// Navigates to the correct onboarding screen based on AppConfig.onboardingMode.
void goToOnboarding(BuildContext context) {
  if (AppConfig.onboardingMode == OnboardingMode.qrScan) {
    context.push('/scan/qr');
  } else {
    context.push('/scan/ble');
  }
}
