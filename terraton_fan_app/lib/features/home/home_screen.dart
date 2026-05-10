// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/features/home/fan_card.dart';

FanDevice _demoFan() => FanDevice()
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
            onPressed: () => context.push(AppRoutes.settings),
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
    final displayFans = showDemo ? [_demoFan()] : fans;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Welcome back, User',
            style: TextStyle(
              fontSize: 14,
              color: Colors.blueGrey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (showDemo)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.science_outlined, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(
                  'Demo fan — add a real fan to replace this',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade700),
                ),
              ],
            ),
          ),
        ...displayFans.map((fan) => FanCard(key: ValueKey(fan.deviceId), fan: fan)),
      ],
    );
  }
}
