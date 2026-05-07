// lib/features/settings/settings_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Export Fans'),
            subtitle: const Text('Share fan list as JSON'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import Fans'),
            subtitle: const Text('Import from a JSON backup'),
            onTap: () => _import(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final json = ref.read(fanRepositoryProvider).exportToJson();
    final tmp  = await File(
      '${Directory.systemTemp.path}/terraton_fans_export.json',
    ).writeAsString(json);
    await Share.shareXFiles([XFile(tmp.path)], text: 'Terraton Fan Export');
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    final json = await File(result.files.single.path!).readAsString();
    try {
      final count = await ref.read(fanRepositoryProvider).importFromJson(json);
      ref.invalidate(savedFansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $count fan(s).')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid backup file.')),
        );
      }
    }
  }
}
