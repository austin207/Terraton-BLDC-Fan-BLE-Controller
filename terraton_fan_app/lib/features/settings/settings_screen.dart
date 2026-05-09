// lib/features/settings/settings_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:terraton_fan_app/core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const _SectionHeader('DATA MANAGEMENT'),
          _SettingsTile(
            icon: Icons.upload_rounded,
            iconBg: Colors.blue.shade50,
            iconColor: Colors.blue.shade600,
            title: 'Export Fans Data',
            onTap: () => _export(context, ref),
          ),
          _SettingsTile(
            icon: Icons.download_rounded,
            iconBg: Colors.green.shade50,
            iconColor: Colors.green.shade600,
            title: 'Import Fans Data',
            onTap: () => _import(context, ref),
          ),

          const _SectionHeader('ABOUT'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconBg: Colors.grey.shade100,
            iconColor: Colors.grey.shade600,
            title: 'App Version',
            trailing: const Text('v1.0.0 (Build 1)',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          _SettingsTile(
            icon: Icons.devices_rounded,
            iconBg: Colors.grey.shade100,
            iconColor: Colors.grey.shade600,
            title: 'Firmware Support',
            trailing: Text('Up to Date',
                style: TextStyle(fontSize: 13, color: Colors.green.shade600, fontWeight: FontWeight.w600)),
          ),
          _SettingsTile(
            icon: Icons.bluetooth_rounded,
            iconBg: Colors.grey.shade100,
            iconColor: Colors.grey.shade600,
            title: 'BLE Protocol',
            trailing: const Text('BLE 5.2',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),

          const _SectionHeader('SUPPORT'),
          _SettingsTile(
            icon: Icons.menu_book_rounded,
            iconBg: Colors.amber.shade50,
            iconColor: Colors.amber.shade700,
            title: 'User Manual',
            trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User Manual coming soon.')),
              );
            },
          ),

          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(Icons.wind_power, size: 36, color: Colors.grey.shade300),
                const SizedBox(height: 6),
                Text(
                  'TERRATON',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 3,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final json = ref.read(fanRepositoryProvider).exportToJson();
    final dir  = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tmp = File('${dir.path}/terraton_fans_$timestamp.json');
    await tmp.writeAsString(json);
    try {
      await Share.shareXFiles([XFile(tmp.path)], text: 'Terraton Fan Export');
    } on Object catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed. Please try again.')),
        );
      }
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
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
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid backup file.')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right, color: Colors.grey.shade400) : null),
        onTap: onTap,
      ),
    );
  }
}
