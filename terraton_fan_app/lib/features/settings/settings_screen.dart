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
import 'package:terraton_fan_app/shared/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Profile card
        const SizedBox(height: 8),
        _ProfileCard(),

        // DATA MANAGEMENT
        _SectionLabel('DATA MANAGEMENT'),
        _SettingsGroup(tiles: [
          _SettingRow(
            iconBg: const Color(0x26507FFF),
            iconColor: const Color(0xFF7AA7FF),
            icon: Icons.upload_rounded,
            label: 'Export Fans Data',
            divider: true,
            onTap: () => _export(context, ref),
          ),
          _SettingRow(
            iconBg: const Color(0x207AE582),
            iconColor: kGreen,
            icon: Icons.download_rounded,
            label: 'Import Fans Data',
            onTap: () => _import(context, ref),
          ),
        ]),

        // ABOUT
        _SectionLabel('ABOUT'),
        _SettingsGroup(tiles: [
          _SettingRow(
            iconBg: kCardHi,
            iconColor: kText,
            icon: Icons.info_outline_rounded,
            label: 'App Version',
            trailingText: ref.watch(packageInfoProvider).when(
              data: (info) => 'v${info.version} (${info.buildNumber})',
              loading: () => '…',
              error: (_, __) => 'v—',
            ),
            divider: true,
          ),
          const _SettingRow(
            iconBg: kCardHi,
            iconColor: kText,
            icon: Icons.devices_rounded,
            label: 'Firmware Support',
            trailingPill: _PillData(label: '✓ Up to Date', color: kGreen),
            divider: true,
          ),
          const _SettingRow(
            iconBg: Color(0x207AA7FF),
            iconColor: Color(0xFF7AA7FF),
            icon: Icons.bluetooth_rounded,
            label: 'BLE Protocol',
            trailingPill: _PillData(label: 'BLE 5.2', color: Color(0xFF7AA7FF), outlined: true),
          ),
        ]),

        // SUPPORT
        _SectionLabel('SUPPORT'),
        _SettingsGroup(tiles: [
          _SettingRow(
            iconBg: kYellow.withAlpha(38),
            iconColor: kYellow,
            icon: Icons.menu_book_rounded,
            label: 'User Manual',
            chevron: true,
            onTap: () => unawaited(context.push(AppRoutes.userManual)),
            divider: true,
          ),
          _SettingRow(
            iconBg: kYellow.withAlpha(38),
            iconColor: kYellow,
            icon: Icons.qr_code_rounded,
            label: 'Service QR',
            chevron: true,
          ),
        ]),

        // Footer
        const SizedBox(height: 48),
        Divider(height: 1, color: kHairline),
        const SizedBox(height: 36),
        Center(
          child: Column(
            children: [
              const Icon(Icons.air_rounded, size: 48, color: kYellow),
              const SizedBox(height: 12),
              Text('Terraton®',
                  style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w600, color: kTextMut,
                  )),
              const SizedBox(height: 3),
              Text('SMART BLDC FAN CONTROL',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9, letterSpacing: 1.6, color: kTextDim, fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      ],
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

// ── Profile card ──────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const userName = 'Terraton User';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0x14FFEC00), Color(0x03FFEC00)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x38FFEC00)),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: kYellow,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: kYellowGlow, blurRadius: 18)],
            ),
            alignment: Alignment.center,
            child: Text('T',
                style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(userName,
                style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kHairlineStrong),
            ),
            child: Text('EDIT',
                style: GoogleFonts.manrope(
                  fontSize: 11, fontWeight: FontWeight.w600, color: kText, letterSpacing: 0.6,
                )),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: kTextMut, letterSpacing: 2.2,
          )),
    );
  }
}

// ── Settings group ────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final List<_SettingRow> tiles;
  const _SettingsGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kHairline),
      ),
      child: Column(children: tiles),
    );
  }
}

// ── Pill data ─────────────────────────────────────────────────────────────────

class _PillData {
  final String label;
  final Color color;
  final bool outlined;
  const _PillData({required this.label, required this.color, this.outlined = false});
}

// ── Setting row ───────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String label;
  final String? trailingText;
  final _PillData? trailingPill;
  final bool chevron;
  final bool divider;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.label,
    this.trailingText,
    this.trailingPill,
    this.chevron = false,
    this.divider = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget? trailing;
    if (trailingText != null) {
      trailing = Text(trailingText!,
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: kTextMut));
    } else if (trailingPill != null) {
      final pill = trailingPill!;
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: pill.outlined ? Colors.transparent : pill.color.withAlpha(34),
          borderRadius: BorderRadius.circular(100),
          border: pill.outlined ? Border.all(color: pill.color.withAlpha(102)) : null,
        ),
        child: Text(pill.label,
            style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: pill.color)),
      );
    } else if (chevron) {
      trailing = const Icon(Icons.chevron_right_rounded, color: kTextMut, size: 20);
    }

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w600, color: kText,
                      )),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
        if (divider) Divider(height: 1, indent: 70, color: kHairline),
      ],
    );
  }
}
