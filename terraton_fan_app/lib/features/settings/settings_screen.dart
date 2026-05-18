// lib/features/settings/settings_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
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
          const _SectionLabel('DATA MANAGEMENT', isFirst: true),
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
          _TileGroup(tiles: [
            _TileData(
              icon: Icons.info_outline_rounded,
              iconBg: const Color(0xFFF8FAFC),
              iconColor: const Color(0xFF64748B),
              title: 'App Version',
              trailingText: ref.watch(packageInfoProvider).when(
                data: (info) => 'v${info.version} (${info.buildNumber})',
                loading: () => '…',
                error: (_, __) => 'v—',
              ),
            ),
            const _TileData(
              icon: Icons.devices_rounded,
              iconBg: Color(0xFFF8FAFC),
              iconColor: Color(0xFF64748B),
              title: 'Firmware Support',
              trailingWidget: _PillBadge(
                label: 'Up to Date',
                icon: Icons.check_circle_rounded,
                textColor: Color(0xFF16A34A),
                bg: Color(0xFFF0FDF4),
                border: Color(0xFFBBF7D0),
              ),
            ),
            const _TileData(
              icon: Icons.bluetooth_rounded,
              iconBg: Color(0xFFEFF6FF),
              iconColor: Color(0xFF3B82F6),
              title: 'BLE Protocol',
              trailingWidget: _PillBadge(
                label: 'BLE 5.2',
                textColor: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
                border: Color(0xFFBFDBFE),
              ),
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
              onTap: () => unawaited(context.push(AppRoutes.userManual)),
            ),
          ]),

          // ── Terraton footer ───────────────────────────────────────────────
          const SizedBox(height: 48),
          const Divider(height: 1, color: Color(0xFFEDF0F4)),
          const SizedBox(height: 36),
          Center(
            child: Column(
              children: [
                const FanIcon(size: 88, semanticLabel: 'Terraton fan'),
                const SizedBox(height: 12),
                Text(
                  'Terraton®',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: const Color(0xFF5F6368),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'SMART BLDC FAN CONTROL',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.6,
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
    if (!context.mounted) return;
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
      if (!context.mounted) return;
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

// ── Pill badge (trailing status indicator) ────────────────────────────────────

class _PillBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color textColor;
  final Color bg;
  final Color border;

  const _PillBadge({
    required this.label,
    this.icon,
    required this.textColor,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isFirst;
  const _SectionLabel(this.label, {this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, isFirst ? 4 : 20, 4, 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: data.iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: data.iconColor, size: 20),
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
