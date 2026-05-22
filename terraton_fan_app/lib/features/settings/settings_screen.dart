// lib/features/settings/settings_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
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
            onTap: () => _showServiceQr(context),
          ),
        ]),

        // Footer
        const SizedBox(height: 48),
        const Divider(height: 1, color: kHairline),
        const SizedBox(height: 36),
        Center(
          child: Column(
            children: [
              const TerratonFanIcon(size: 48),
              const SizedBox(height: 12),
              Text('Terraton®',
                  style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w600, color: kTextMut,
                  )),
              const SizedBox(height: 3),
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

  void _showServiceQr(BuildContext context) {
    unawaited(showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(168),
      builder: (_) => const _ServiceQrModal(),
    ));
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
    Future.delayed(const Duration(milliseconds: 80), () {
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
                  BoxShadow(color: Color(0xB3000000), blurRadius: 80),
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
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.close_rounded, color: kTextMut, size: 16),
                      ),
                    ),
                  ),
                  // Pencil chip
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFEC00),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x47FFEC00)),
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
                      border: Border.all(color: const Color(0x52FFEC00)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x0FFFEC00), blurRadius: 0, spreadRadius: 4),
                        BoxShadow(color: kYellowGlow, blurRadius: 22),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
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
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            onSubmitted: (_) => unawaited(_save()),
                          ),
                        ),
                        if (_ctrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => _ctrl.clear(),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: kCardHi, borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.close_rounded, color: kTextMut, size: 14),
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

// ── Service QR modal ──────────────────────────────────────────────────────────

class _ServiceQrModal extends StatefulWidget {
  const _ServiceQrModal();

  @override
  State<_ServiceQrModal> createState() => _ServiceQrModalState();
}

class _ServiceQrModalState extends State<_ServiceQrModal> {
  static const _ttl = 15 * 60; // 15 minutes in seconds
  int _remaining = _ttl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _remaining = _ttl;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = math.max(0, _remaining - 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _mins => (_remaining ~/ 60).toString().padLeft(2, '0');
  String get _secs => (_remaining % 60).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(22),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [kCardElev, kSurface],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: kHairlineStrong),
                boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 80)],
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
                      child: const Icon(Icons.close_rounded, color: kTextMut, size: 16),
                    ),
                  ),
                  // QR chip
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFEC00),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x47FFEC00)),
                      boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 24)],
                    ),
                    child: const Icon(Icons.qr_code_rounded, color: kYellow, size: 22),
                  ),
                  const SizedBox(height: 18),
                  Text('Service QR',
                      style: GoogleFonts.manrope(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: kText, letterSpacing: -0.2,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    'Let a Terraton technician temporarily access and control your fans by scanning the code below.',
                    style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.45),
                  ),
                  const SizedBox(height: 18),

                  // QR card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x38FFEC00)),
                      boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 22)],
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: const CustomPaint(
                            size: Size(184, 184),
                            painter: _FakeQrPainter(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('SVC-9F3A·BLDC52',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: kText, letterSpacing: 1.6,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Countdown + regenerate
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kHairline),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: kYellow,
                            boxShadow: [BoxShadow(color: kYellowGlow, blurRadius: 8)],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('EXPIRES IN',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9, fontWeight: FontWeight.w700,
                                    color: kTextMut, letterSpacing: 1.8,
                                  )),
                              const SizedBox(height: 2),
                              Text('$_mins:$_secs',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 16, fontWeight: FontWeight.w700,
                                    color: kText, letterSpacing: 0.4,
                                  )),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(_startTimer),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: kHairlineStrong),
                            ),
                            child: Text('REGENERATE',
                                style: GoogleFonts.manrope(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: kText, letterSpacing: 0.6,
                                )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

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
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kYellow, foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text('Share',
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

// ── FakeQR painter ────────────────────────────────────────────────────────────
// Deterministic pseudo-random module pattern + 3 finder boxes.
// Seeded so every render is identical (matches JSX FakeQR logic).

class _FakeQrPainter extends CustomPainter {
  const _FakeQrPainter();

  static const _n = 25;

  bool _rng(int i, int j) {
    final v = math.sin(i * 12.9898 + j * 78.233) * 43758.5453;
    return (v - v.truncateToDouble()) > 0.5;
  }

  bool _inFinder(int i, int j) {
    bool f(int oi, int oj) => i >= oi && i < oi + 7 && j >= oj && j < oj + 7;
    return f(0, 0) || f(0, _n - 7) || f(_n - 7, 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final black = Paint()..color = Colors.black;
    final white = Paint()..color = Colors.white;

    canvas.drawRect(Offset.zero & size, white);

    // Data modules
    for (var i = 0; i < _n; i++) {
      for (var j = 0; j < _n; j++) {
        if (!_inFinder(i, j) && _rng(i, j)) {
          canvas.drawRect(Rect.fromLTWH(j * cell, i * cell, cell, cell), black);
        }
      }
    }

    // Finder patterns
    for (final corner in [(0, 0), (0, _n - 7), (_n - 7, 0)]) {
      final (oi, oj) = corner;
      canvas.drawRect(Rect.fromLTWH(oj * cell, oi * cell, 7 * cell, 7 * cell), black);
      canvas.drawRect(Rect.fromLTWH((oj + 1) * cell, (oi + 1) * cell, 5 * cell, 5 * cell), white);
      canvas.drawRect(Rect.fromLTWH((oj + 2) * cell, (oi + 2) * cell, 3 * cell, 3 * cell), black);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
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
