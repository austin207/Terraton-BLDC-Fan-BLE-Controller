// lib/shared/router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';
import 'package:terraton_fan_app/features/splash/splash_screen.dart';
import 'package:terraton_fan_app/features/home/home_screen.dart';
import 'package:terraton_fan_app/features/home/appliance_types_screen.dart';
import 'package:terraton_fan_app/features/home/fans_list_screen.dart';
import 'package:terraton_fan_app/features/coming_soon/coming_soon_screen.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/features/onboarding/profile_setup_screen.dart';
import 'package:terraton_fan_app/features/onboarding/qr_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/ble_scan_screen.dart';
import 'package:terraton_fan_app/features/onboarding/name_fan_screen.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/permission/ble_permission_screen.dart';
import 'package:terraton_fan_app/features/settings/settings_screen.dart';
import 'package:terraton_fan_app/features/settings/user_manual_screen.dart';
import 'package:terraton_fan_app/features/legal/privacy_policy_screen.dart';
import 'package:terraton_fan_app/features/legal/terms_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.profileSetup,
      builder: (_, __) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.applianceTypes,
      builder: (_, state) => ApplianceTypesScreen(
        category: state.extra is ApplianceCategory
            ? state.extra! as ApplianceCategory
            : null,
      ),
    ),
    // Legacy /fan-types path — redirects to /appliance-types. Note: a string
    // redirect cannot carry GoRouter `extra`, so the category falls back to null
    // (ApplianceTypesScreen handles a null category gracefully). Callers that
    // need a specific category must push /appliance-types directly with `extra`.
    GoRoute(
      path: AppRoutes.fanTypes,
      redirect: (_, __) => AppRoutes.applianceTypes,
    ),
    GoRoute(
      path: AppRoutes.fans,
      builder: (_, state) => FansListScreen(
        fanType: state.extra is ApplianceType
            ? state.extra! as ApplianceType
            : null,
      ),
    ),
    GoRoute(
      path: AppRoutes.comingSoon,
      builder: (_, state) => ComingSoonScreen(
        applianceType: state.extra is ApplianceType
            ? state.extra! as ApplianceType
            : null,
      ),
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
      builder: (_, __) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          surfaceTintColor: Colors.transparent,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
              onPressed: () => ctx.pop(),
            ),
          ),
          title: Text('Settings',
              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
          centerTitle: true,
        ),
        body: const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.userManual,
      builder: (_, __) => const UserManualScreen(),
    ),
    GoRoute(
      path: AppRoutes.privacyPolicy,
      builder: (_, __) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: AppRoutes.terms,
      builder: (_, __) => const TermsScreen(),
    ),
  ],
);

/// Shows a dark bottom sheet letting the user pick QR scan or BLE scan.
void goToOnboarding(BuildContext context) {
  unawaited(showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 14),
            decoration: BoxDecoration(color: kCardHi, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Pair a new fan',
              style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: kText),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _OnboardRow(
                  icon: Icons.bluetooth_searching_rounded,
                  label: 'Bluetooth pairing',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    if (context.mounted) unawaited(context.push(AppRoutes.scanBle));
                  },
                ),
                const SizedBox(height: 8),
                _OnboardRow(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'QR code pairing',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    if (context.mounted) unawaited(context.push(AppRoutes.scanQr));
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: kCardElev,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Cancel',
                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
              ),
            ),
          ),
        ],
      ),
    ),
  ));
}

class _OnboardRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OnboardRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
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
              child: Icon(icon, size: 18, color: kYellow),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: kText)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: kTextDim),
          ],
        ),
      ),
    );
  }
}
