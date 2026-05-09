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
        title: const Text('Terraton Fan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: fansAsync.when(
        data: (fans) =>
            fans.isEmpty ? const _EmptyState() : _FanList(fans: fans),
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF1A56A0).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wind_power, size: 52, color: Color(0xFF1A56A0)),
            ),
            const SizedBox(height: 20),
            const Text(
              'No fans added yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the + button to pair your Terraton fan via Bluetooth or QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Fan'),
              onPressed: () => goToOnboarding(context),
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
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: fans.length,
      itemBuilder: (_, i) => FanCard(key: ValueKey(fans[i].deviceId), fan: fans[i]),
    );
  }
}
