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
        data: (fans) => _GroupedFanList(fans: fans.isNotEmpty ? fans : [_demoFan()]),
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

FanDevice _demoFan() => FanDevice()
  ..deviceId = 'demo-fan-001'
  ..model = 'Terraton AC-05-3'
  ..nickname = 'Living Room Fan'
  ..fwVersion = '1.0.0'
  ..addedAt = DateTime(2026, 5, 9)
  ..lastConnectedAt = DateTime(2026, 5, 9, 13, 30);

class _GroupedFanList extends StatelessWidget {
  final List<FanDevice> fans;
  const _GroupedFanList({required this.fans});

  @override
  Widget build(BuildContext context) {
    // Group fans by model, preserving insertion order.
    final grouped = <String, List<FanDevice>>{};
    for (final fan in fans) {
      final model = fan.model.isNotEmpty ? fan.model : 'Other';
      grouped.putIfAbsent(model, () => []).add(fan);
    }

    final totalCount = fans.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        // ── Fan count ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$totalCount fan${totalCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[500],
            ),
          ),
        ),

        // ── Grouped sections ───────────────────────────────────────────
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Row(
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey[600],
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entry.value.length}',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey[700], fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...entry.value.map((fan) => FanCard(key: ValueKey(fan.deviceId), fan: fan)),
        ],
      ],
    );
  }
}
