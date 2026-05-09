// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/features/home/fan_card.dart';

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
        data: (fans) => fans.isEmpty ? _EmptyState() : _FanList(fans: fans),
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

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wind_power, size: 60, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Fans Added Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Scan your Terraton fan QR code to begin\ncontrolling your environment.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Scan to Add Fan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => goToOnboarding(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanList extends StatelessWidget {
  final List<FanDevice> fans;
  const _FanList({required this.fans});

  @override
  Widget build(BuildContext context) {
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
        ...fans.map((fan) => FanCard(key: ValueKey(fan.deviceId), fan: fan)),
      ],
    );
  }
}
