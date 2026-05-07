// lib/features/home/fan_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../models/fan_device.dart';

class FanCard extends ConsumerWidget {
  final FanDevice fan;
  const FanCard({super.key, required this.fan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastConnected = fan.lastConnectedAt == null
        ? 'Never connected'
        : _formatDate(fan.lastConnectedAt!);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ref.read(activeFanProvider.notifier).set(fan);
          context.push('/control', extra: fan);
        },
        onLongPress: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.wind_power, size: 40, color: Color(0xFF1A56A0)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fan.nickname,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    if (fan.model.isNotEmpty)
                      Text(fan.model,
                          style: const TextStyle(color: Colors.grey)),
                    Text(lastConnected,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.blueGrey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: fan.nickname);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Fan'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nickname'),
          maxLength: 30,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref.read(fanRepositoryProvider).renameFan(fan.deviceId, name);
                // Refresh list
                ref.invalidate(savedFansProvider);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Fan?'),
        content: Text('Remove "${fan.nickname}" from your device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(fanRepositoryProvider).deleteFan(fan.deviceId);
              ref.invalidate(savedFansProvider);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1)   return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)    return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
