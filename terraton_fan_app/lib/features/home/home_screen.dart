// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../shared/router.dart';
import 'fan_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fans = ref.watch(savedFansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terraton Fan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: fans.isEmpty ? _buildEmpty(context) : _buildList(context, ref, fans),
      floatingActionButton: FloatingActionButton(
        onPressed: () => goToOnboarding(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wind_power, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No fans added yet',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Fan'),
            onPressed: () => goToOnboarding(context),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, fans) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: fans.length,
      itemBuilder: (_, i) => FanCard(fan: fans[i]),
    );
  }
}
