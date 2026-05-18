// lib/features/home/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/features/home/fan_card.dart';

final _kDemoFan = FanDevice()
  ..deviceId   = '__demo__'
  ..macAddress = ''
  ..nickname   = 'Living Room Fan'
  ..model      = 'Terraton X1'
  ..fwVersion  = '1.0'
  ..addedAt    = DateTime(2026, 1, 1);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fansAsync = ref.watch(savedFansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Fans', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => unawaited(context.push(AppRoutes.settings)),
          ),
        ],
      ),
      body: fansAsync.when(
        data: (fans) => _FanList(fans: fans, showDemo: fans.isEmpty),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load fans')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => goToOnboarding(context),
        tooltip: 'Add Fan',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FanList extends StatelessWidget {
  final List<FanDevice> fans;
  final bool showDemo;
  const _FanList({required this.fans, this.showDemo = false});

  @override
  Widget build(BuildContext context) {
    final displayFans = showDemo ? [_kDemoFan] : fans;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // ── Header ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '${displayFans.length} fan${displayFans.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A56A0),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Demo banner ───────────────────────────────────────────────────
        if (showDemo)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Icon(Icons.science_outlined, size: 15, color: Colors.amber.shade700),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Demo mode — add a real fan to get started',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Fan cards ─────────────────────────────────────────────────────
        ...displayFans.map((fan) => FanCard(key: ValueKey(fan.deviceId), fan: fan)),
      ],
    );
  }
}
