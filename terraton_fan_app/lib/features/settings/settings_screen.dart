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
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/core/update/app_update_service.dart';
import 'package:terraton_fan_app/features/update/update_dialog.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_config.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/features/settings/service_qr_modal.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(userNameProvider);
    final userName  = nameAsync.valueOrNull ?? '';
    final initial   = userName.isNotEmpty ? userName[0].toUpperCase() : 'T';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // ── Profile card ──────────────────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [kYellowFill, kYellowFaint],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kYellowBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: kYellow,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 18)],
                ),
                alignment: Alignment.center,
                child: Text(initial,
                    style: GoogleFonts.manrope(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black,
                    )),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  userName.isNotEmpty ? userName : 'Terraton User',
                  style: GoogleFonts.manrope(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kText,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showRenameModal(context, ref, userName),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kHairlineStrong),
                  ),
                  child: Text('EDIT',
                      style: GoogleFonts.manrope(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: kText, letterSpacing: 0.6,
                      )),
                ),
              ),
            ],
          ),
        ),

        // DATA MANAGEMENT
        const _SectionLabel('DATA MANAGEMENT'),
        _SettingsGroup(tiles: [
          _SettingRow(
            iconBg: kBlueFill,
            iconColor: kBlue,
            icon: Icons.upload_rounded,
            label: 'Export Fans Data',
            divider: true,
            onTap: () => _export(context, ref),
          ),
          _SettingRow(
            iconBg: kGreenFill,
            iconColor: kGreen,
            icon: Icons.download_rounded,
            label: 'Import Fans Data',
            onTap: () => _import(context, ref),
          ),
        ]),

        // AI TRAINING
        const _SectionLabel('AI TRAINING'),
        const _DataSharingGroup(),

        // ABOUT
        const _SectionLabel('ABOUT'),
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
          if (!kIsClientVariant) const _UpdateCheckTile(divider: true),
          const _SettingRow(
            iconBg: kCardHi,
            iconColor: kText,
            icon: Icons.devices_rounded,
            label: 'Firmware Support',
            trailingPill: _PillData(label: '✓ Up to Date', color: kGreen),
            divider: true,
          ),
          const _SettingRow(
            iconBg: kBlueFill,
            iconColor: kBlue,
            icon: Icons.bluetooth_rounded,
            label: 'BLE Protocol',
            trailingPill: _PillData(label: 'BLE 5.2', color: kBlue, outlined: true),
          ),
        ]),

        // SUPPORT
        const _SectionLabel('SUPPORT'),
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
            onTap: () {
              final fans = (ref.read(savedFansProvider).valueOrNull ?? [])
                  .where((f) => !f.isServiceAccess)
                  .toList();
              _showServiceQr(context, fans);
            },
          ),
        ]),

        // LEGAL
        const _SectionLabel('LEGAL'),
        _SettingsGroup(tiles: [
          _SettingRow(
            iconBg: kBlueFill,
            iconColor: kBlue,
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            chevron: true,
            divider: true,
            onTap: () => unawaited(context.push(AppRoutes.privacyPolicy)),
          ),
          _SettingRow(
            iconBg: kBlueFill,
            iconColor: kBlue,
            icon: Icons.gavel_rounded,
            label: 'Terms of Service',
            chevron: true,
            onTap: () => unawaited(context.push(AppRoutes.terms)),
          ),
        ]),

        // Footer
        const SizedBox(height: 48),
        const Divider(height: 1, color: kHairline),
        const SizedBox(height: 36),
        Center(
          child: Column(
            children: [
              // Full Terraton branding: power-T icon + wordmark
              const BrandMark(height: 40, alignment: Alignment.center),
              const SizedBox(height: 8),
              Text('SMART BLDC FAN CONTROL',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9, letterSpacing: 1.6, color: kTextDim,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  void _showRenameModal(BuildContext context, WidgetRef ref, String current) {
    unawaited(showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(168),
      builder: (_) => _RenameModal(
        initialName: current,
        onSave: (name) async {
          await ref.read(userNameProvider.notifier).save(name);
        },
      ),
    ));
  }

  void _showServiceQr(BuildContext context, List<FanDevice> fans) {
    unawaited(showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(168),
      builder: (_) => ServiceQrModal(fans: fans),
    ));
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final json = ref.read(fanRepositoryProvider).exportToJson();
    final dir  = await getTemporaryDirectory();
    if (!context.mounted) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tmp = File('${dir.path}/terraton_fans_$timestamp.json');
    await tmp.writeAsString(json);
    if (!context.mounted) return;
    try {
      await Share.shareXFiles([XFile(tmp.path)], text: 'Terraton Fan Export');
    } on Exception catch (_) {
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
    final String json;
    try {
      json = await File(result.files.single.path!).readAsString();
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
      }
      return;
    }
    try {
      final count = await ref.read(fanRepositoryProvider).importFromJson(json);
      if (!context.mounted) return;
      ref.invalidate(savedFansProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count fan(s).')),
      );
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid backup file.')),
        );
      }
    }
  }
}

// ── Rename modal ──────────────────────────────────────────────────────────────

class _RenameModal extends StatefulWidget {
  final String initialName;
  final Future<void> Function(String) onSave;

  const _RenameModal({required this.initialName, required this.onSave});

  @override
  State<_RenameModal> createState() => _RenameModalState();
}

class _RenameModalState extends State<_RenameModal> {
  late final TextEditingController _ctrl;

  bool get _valid => _ctrl.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
    _ctrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  final _focusNode = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_valid) return;
    await widget.onSave(_ctrl.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // stop propagation
            child: Container(
              margin: const EdgeInsets.all(22),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kCardElev, kSurface],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: kHairlineStrong),
                boxShadow: const [
                  BoxShadow(color: kModalShadow, blurRadius: 80),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Close ×
                  Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 32, height: 32,
                        child: Icon(Icons.close_rounded, color: kTextMut, size: 16),
                      ),
                    ),
                  ),
                  // Pencil chip
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: kYellowFill,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kYellowBorderHi),
                      boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 24)],
                    ),
                    child: const Icon(Icons.edit_rounded, color: kYellow, size: 20),
                  ),
                  const SizedBox(height: 18),
                  Text('Edit your name',
                      style: GoogleFonts.manrope(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: kText, letterSpacing: -0.2,
                      )),
                  const SizedBox(height: 6),
                  Text('This is the name shown on your home screen.',
                      style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.45)),
                  const SizedBox(height: 20),

                  // YOUR NAME label
                  Text('YOUR NAME',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: kYellow, letterSpacing: 2.4,
                      )),
                  const SizedBox(height: 8),

                  // Input container
                  Container(
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kYellowGlow),
                      boxShadow: const [
                        BoxShadow(color: kYellowDim, blurRadius: 0, spreadRadius: 4),
                        BoxShadow(color: kYellowGlow, blurRadius: 22),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focusNode,
                            maxLength: 32,
                            style: GoogleFonts.manrope(
                              fontSize: 16, fontWeight: FontWeight.w600, color: kText,
                            ),
                            cursorColor: kYellow,
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(vertical: 13),
                            ),
                            onSubmitted: (_) => unawaited(_save()),
                          ),
                        ),
                        if (_ctrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => _ctrl.clear(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close_rounded, color: kTextMut, size: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('2–32 characters',
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: kTextDim, letterSpacing: 0.8)),
                      Text('${_ctrl.text.length}/32',
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: kTextDim, letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              backgroundColor: kCardHi,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('Cancel',
                                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _valid ? () => unawaited(_save()) : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kYellow,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: kCardHi,
                              disabledForegroundColor: kTextDim,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text('Save',
                                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ── AI training data sharing group ───────────────────────────────────────────

class _DataSharingGroup extends StatefulWidget {
  const _DataSharingGroup();

  @override
  State<_DataSharingGroup> createState() => _DataSharingGroupState();
}

class _DataSharingGroupState extends State<_DataSharingGroup> {
  bool _optIn = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOptIn());
  }

  Future<void> _loadOptIn() async {
    try {
      final v = await AppSettings.loadUploadOptIn();
      if (mounted) setState(() { _optIn = v; _loaded = true; });
    } on Exception catch (_) {
      if (mounted) setState(() { _loaded = true; });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _optIn = value);
    try {
      await AppSettings.saveUploadOptIn(value);
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() => _optIn = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save preference. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kYellow.withAlpha(30),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.auto_graph_rounded, color: kYellow, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contribute to AI Training',
                        style: GoogleFonts.manrope(
                          fontSize: 15, fontWeight: FontWeight.w600, color: kText,
                        ),
                      ),
                      Text(
                        'Share anonymous usage data to improve energy optimisation suggestions.',
                        style: GoogleFonts.manrope(fontSize: 11, color: kTextMut, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _loaded
                    ? Switch(
                        value: _optIn,
                        onChanged: (v) => unawaited(_toggle(v)),
                        activeColor: kYellow,
                        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                        thumbColor: WidgetStateProperty.resolveWith(
                          (s) => s.contains(WidgetState.selected) ? Colors.black : kTextMut,
                        ),
                      )
                    : const SizedBox(width: 51, height: 31),
              ],
            ),
          ),
          const Divider(height: 1, indent: 70, color: kHairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: kTextDim, size: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Data is anonymised using a one-way hash — your device ID is never sent. '
                    'Uploaded on Wi-Fi only, once per day.',
                    style: GoogleFonts.manrope(fontSize: 10, color: kTextDim, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Manual update check tile ──────────────────────────────────────────────────

class _UpdateCheckTile extends StatefulWidget {
  final bool divider;
  const _UpdateCheckTile({this.divider = false});

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final info = await AppUpdateService.checkForUpdateManual();
      if (!mounted) return;
      if (info != null) {
        unawaited(UpdateDialog.show(context, info));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're up to date.")),
        );
      }
    } on SocketException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No internet connection.")),
        );
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request timed out. Try again.")),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        final msg = e.toString().contains('HTTP')
            ? "Update server error. Try again later."
            : "Couldn't read update info. Try again.";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: _checking ? null : () => unawaited(_check()),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kYellowFill,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: kYellow, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Check for Updates',
                      style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w600, color: kText,
                      )),
                ),
                if (_checking)
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kYellow),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: kTextMut, size: 20),
              ],
            ),
          ),
        ),
        if (widget.divider) const Divider(height: 1, indent: 70, color: kHairline),
      ],
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
  final List<Widget> tiles;
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
            style: GoogleFonts.manrope(
              fontSize: 11, fontWeight: FontWeight.w700, color: pill.color,
            )),
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
        if (divider) const Divider(height: 1, indent: 70, color: kHairline),
      ],
    );
  }
}
