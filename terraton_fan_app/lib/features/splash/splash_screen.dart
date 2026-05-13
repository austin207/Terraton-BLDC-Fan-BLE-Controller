// lib/features/splash/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final scanGranted    = await Permission.bluetoothScan.status;
      final connectGranted = await Permission.bluetoothConnect.status;
      if (!mounted) return;
      final granted = (scanGranted.isGranted    || scanGranted.isLimited) &&
                      (connectGranted.isGranted || connectGranted.isLimited);
      context.go(granted ? AppRoutes.home : AppRoutes.permissionRequired);
    });
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimary.withAlpha(70),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const FanIcon(size: 54),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'TERRATON',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Color(0xFF1A2C4E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SMART BLDC FAN CONTROL',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 2.5,
                      color: Colors.blueGrey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 52),
            child: AnimatedBuilder(
              animation: _dotCtrl,
              builder: (_, __) {
                final active = (_dotCtrl.value * 3).floor() % 3;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final isActive = i == active;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isActive ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isActive ? kPrimary : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
