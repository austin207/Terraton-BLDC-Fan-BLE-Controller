// lib/features/settings/settings_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── DATA MANAGEMENT ───────────────────────────────────────────────
          const _SectionLabel('DATA MANAGEMENT'),
          _TileGroup(tiles: [
            _TileData(
              icon: Icons.upload_rounded,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF3B82F6),
              title: 'Export Fans Data',
              onTap: () => _export(context, ref),
            ),
            _TileData(
              icon: Icons.download_rounded,
              iconBg: const Color(0xFFF0FDF4),
              iconColor: const Color(0xFF22C55E),
              title: 'Import Fans Data',
              onTap: () => _import(context, ref),
            ),
          ]),

          // ── ABOUT ─────────────────────────────────────────────────────────
          const _SectionLabel('ABOUT'),
          const _TileGroup(tiles: [
            _TileData(
              icon: Icons.info_outline_rounded,
              iconBg: Color(0xFFF8FAFC),
              iconColor: Color(0xFF64748B),
              title: 'App Version',
              trailingText: 'v1.0.0 (Build 1)',
            ),
            _TileData(
              icon: Icons.devices_rounded,
              iconBg: Color(0xFFF8FAFC),
              iconColor: Color(0xFF64748B),
              title: 'Firmware Support',
              trailingWidget: Text(
                'Up to Date',
                style: TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
              ),
            ),
            _TileData(
              icon: Icons.bluetooth_rounded,
              iconBg: Color(0xFFF8FAFC),
              iconColor: Color(0xFF64748B),
              title: 'BLE Protocol',
              trailingText: 'BLE 5.2',
            ),
          ]),

          // ── SUPPORT ───────────────────────────────────────────────────────
          const _SectionLabel('SUPPORT'),
          _TileGroup(tiles: [
            _TileData(
              icon: Icons.menu_book_rounded,
              iconBg: const Color(0xFFFFFBEB),
              iconColor: const Color(0xFFD97706),
              title: 'User Manual',
              trailingWidget: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF94A3B8)),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User Manual coming soon.')),
              ),
            ),
          ]),

          // ── Terraton footer ───────────────────────────────────────────────
          const SizedBox(height: 56),
          Center(
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.wind_power_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  'TERRATON',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 3.5,
                    color: Colors.blueGrey.shade400,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SMART BLDC FAN CONTROL',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: Colors.blueGrey.shade300,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7F95),
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

// ── Grouped tile container ─────────────────────────────────────────────────────

class _TileData {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? trailingText;
  final Widget? trailingWidget;
  final VoidCallback? onTap;

  const _TileData({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.trailingText,
    this.trailingWidget,
    this.onTap,
  });
}

class _TileGroup extends StatelessWidget {
  final List<_TileData> tiles;
  const _TileGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            _SettingsTile(data: tiles[i], isFirst: i == 0, isLast: i == tiles.length - 1),
            if (i < tiles.length - 1)
              const Divider(height: 1, indent: 68, endIndent: 0, color: Color(0xFFF1F5F9)),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final _TileData data;
  final bool isFirst;
  final bool isLast;

  const _SettingsTile({required this.data, required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.vertical(
      top:    isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast  ? const Radius.circular(16) : Radius.zero,
    );

    Widget trailing;
    if (data.trailingWidget != null) {
      trailing = data.trailingWidget!;
    } else if (data.trailingText != null) {
      trailing = Text(
        data.trailingText!,
        style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      );
    } else if (data.onTap != null) {
      trailing = const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 22);
    } else {
      trailing = const SizedBox.shrink();
    }

    return InkWell(
      onTap: data.onTap,
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: data.iconBg, shape: BoxShape.circle),
              child: Icon(data.icon, color: data.iconColor, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                data.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
