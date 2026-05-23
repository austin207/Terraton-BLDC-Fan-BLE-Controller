// lib/features/splash/splash_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breatheCtrl;

  @override
  void initState() {
    super.initState();
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);

    unawaited(Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final scanGranted    = await Permission.bluetoothScan.status;
      final connectGranted = await Permission.bluetoothConnect.status;
      if (!mounted) return;
      final granted = (scanGranted.isGranted    || scanGranted.isLimited) &&
                      (connectGranted.isGranted || connectGranted.isLimited);
      if (!granted) {
        context.go(AppRoutes.permissionRequired);
        return;
      }
      // First launch → profile setup; returning user → home
      final firstLaunch = await AppSettings.isFirstLaunch();
      if (!mounted) return;
      context.go(firstLaunch ? AppRoutes.profileSetup : AppRoutes.home);
    }));
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(packageInfoProvider).valueOrNull?.version ?? '—';

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Aura rings
          AnimatedBuilder(
            animation: _breatheCtrl,
            builder: (_, __) {
              final t = _breatheCtrl.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow
                  Container(
                    width: 460,
                    height: 460,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kYellow.withAlpha(((0.04 + t * 0.16) * 255).round()),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.72],
                      ),
                    ),
                  ),
                  // Inner ring
                  Container(
                    width: 240 + t * 20,
                    height: 240 + t * 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kYellow.withAlpha(((0.08 + t * 0.10) * 255).round()),
                        width: 1,
                      ),
                    ),
                  ),
                  // Outer ring
                  Container(
                    width: 340 + t * 30,
                    height: 340 + t * 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kYellow.withAlpha(((0.05 + t * 0.05) * 255).round()),
                        width: 1,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Brand mark — centered within the rings
          AnimatedBuilder(
            animation: _breatheCtrl,
            builder: (_, child) => Transform.scale(
              scale: 0.97 + _breatheCtrl.value * 0.03,
              child: child,
            ),
            child: const BrandMark(height: 148, full: false),
          ),

          // Loading dots + version — bottom section
          Positioned(
            bottom: 48,
            child: Column(
              children: [
                const _BreatheDots(),
                const SizedBox(height: 14),
                Text(
                  'v$version · SMART BLDC',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: kTextDim,
                    letterSpacing: 2.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreatheDots extends StatefulWidget {
  const _BreatheDots();

  @override
  State<_BreatheDots> createState() => _BreathDotsState();
}

class _BreathDotsState extends State<_BreatheDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dotCtrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_dotCtrl.value - i * 0.15).clamp(0.0, 1.0);
            final opacity = 0.30 + 0.60 * math.sin(phase * math.pi);
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kYellow.withAlpha((opacity * 255).round()),
              ),
            );
          }),
        );
      },
    );
  }
}
