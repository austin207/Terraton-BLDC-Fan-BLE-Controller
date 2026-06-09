// lib/features/home/fans_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class FansListScreen extends ConsumerWidget {
  final ApplianceType? fanType;
  const FansListScreen({super.key, this.fanType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fansAsync = ref.watch(savedFansProvider);
    final title = fanType != null ? fanType!.pluralLabel : 'My Fans';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w700, color: kText,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          fansAsync.when(
            data: (fans) {
              final filtered = fanType != null
                  ? fans.where((f) => fanType!.matchesModel(f.model)).toList()
                  : fans;
              return _FanList(fans: filtered, fanType: fanType);
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: kYellow),
            ),
            error: (_, __) => const Center(
              child: Text('Could not load fans',
                  style: TextStyle(color: kTextMut)),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 26,
            child: _Fab(
              onTap: () {
                if (fanType != null) {
                  unawaited(_showConnectModal(context, ''));
                } else {
                  goToOnboarding(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fan model sheet ───────────────────────────────────────────────────────────

Future<void> _showFanModelSheet(BuildContext context, ApplianceType fanType) async {
  final model = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FanModelSheet(fanType: fanType),
  );
  if (model == null || !context.mounted) return;
  await _showConnectModal(context, model);
}

Future<void> _showConnectModal(BuildContext context, String model) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetCtx) => _ConnectModal(
      model: model,
      onScanQr: () {
        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        if (context.mounted) unawaited(context.push(AppRoutes.scanQr));
      },
      onAutoConnect: () {
        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        if (context.mounted) unawaited(context.push(AppRoutes.scanBle));
      },
    ),
  );
}

// ── _FanModelSheet ────────────────────────────────────────────────────────────

class _FanModelSheet extends StatelessWidget {
  final ApplianceType fanType;
  const _FanModelSheet({required this.fanType});

  @override
  Widget build(BuildContext context) {
    final models = fanType.modelNumbers;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      snap: true,
      snapSizes: const [0.65, 0.92],
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle + header (non-scrollable)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: kCardHi,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Fan Model',
                    style: GoogleFonts.manrope(
                      fontSize: 18, fontWeight: FontWeight.w700, color: kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fanType.displayName,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: kTextMut, letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${models.length} MODELS AVAILABLE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: kTextDim, letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Scrollable list
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                physics: const BouncingScrollPhysics(),
                itemCount: models.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FanModelCard(
                    model: models[i],
                    index: i + 1,
                    onTap: () => Navigator.of(context).pop(models[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable row card for a single fan model number.
/// Shows a numbered badge on the left, full model ID + status in the centre,
/// and a forward chevron on the right — consistent with the app's row language.
class FanModelCard extends StatefulWidget {
  final String model;
  final int index;
  final VoidCallback onTap;

  const FanModelCard({
    super.key,
    required this.model,
    required this.index,
    required this.onTap,
  });

  @override
  State<FanModelCard> createState() => _FanModelCardState();
}

class _FanModelCardState extends State<FanModelCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.model,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _pressed ? kCardElev : kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed ? kYellow.withAlpha(110) : kHairline,
            ),
            boxShadow: _pressed
                ? [const BoxShadow(color: kYellowGlow, blurRadius: 16, spreadRadius: -6)]
                : [],
          ),
          child: Row(
            children: [
              // Number badge — shows the sequential index (01, 02…)
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _pressed ? kYellow.withAlpha(38) : kYellow.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _pressed ? kYellow.withAlpha(100) : kYellow.withAlpha(38),
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.index.toString().padLeft(2, '0'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: _pressed ? kYellow : kYellow.withAlpha(180),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Model ID + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.model,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: _pressed ? kYellow : kText,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14, color: kTextDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Connect modal ─────────────────────────────────────────────────────────────

class _ConnectModal extends StatelessWidget {
  final String model;
  final VoidCallback onScanQr;
  final VoidCallback onAutoConnect;

  const _ConnectModal({
    required this.model,
    required this.onScanQr,
    required this.onAutoConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: kCardHi,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Connect Device',
              style: GoogleFonts.manrope(
                fontSize: 20, fontWeight: FontWeight.w700, color: kText,
              ),
            ),
            if (model.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Choose a connection method for $model',
                style: GoogleFonts.manrope(
                  fontSize: 13, color: kTextMut, height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ConnectOptionButton(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan QR Code',
              subtitle: 'Scan the QR sticker on your fan packaging',
              onTap: onScanQr,
            ),
            const SizedBox(height: 10),
            ConnectOptionButton(
              icon: Icons.bluetooth_searching_rounded,
              label: 'Automatic Connect',
              subtitle: 'Find and pair over Bluetooth automatically',
              onTap: onAutoConnect,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: kCardElev,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w600, color: kText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable large action button for the connect method selection.
class ConnectOptionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const ConnectOptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<ConnectOptionButton> createState() => _ConnectOptionButtonState();
}

class _ConnectOptionButtonState extends State<ConnectOptionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kYellow.withAlpha(_pressed ? 50 : 28),
                kYellow.withAlpha(_pressed ? 12 : 6),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kYellow.withAlpha(_pressed ? 100 : 55),
            ),
            boxShadow: _pressed
                ? [const BoxShadow(color: kYellowGlow, blurRadius: 20, spreadRadius: -6)]
                : [],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: kYellow.withAlpha(_pressed ? 50 : 28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: kYellow, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w700, color: kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 11, color: kTextDim, fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kTextDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Add fan',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: kYellow,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(color: kYellowGlow, blurRadius: 24, spreadRadius: 2),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.black, size: 26),
          ),
        ),
      );
}

// ── Fan list ──────────────────────────────────────────────────────────────────

class _FanList extends ConsumerWidget {
  final List<FanDevice> fans;
  final ApplianceType? fanType;
  const _FanList({required this.fans, this.fanType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fans.isEmpty) {
      final noun = fanType != null
          ? fanType!.pluralLabel.toLowerCase()
          : 'fans';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TerratonFanIcon(size: 64, color: kTextDim),
            const SizedBox(height: 16),
            Text(
              'No $noun paired yet.',
              style: GoogleFonts.manrope(
                fontSize: 16, color: kTextMut, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to add one.',
              style: GoogleFonts.manrope(fontSize: 13, color: kTextDim),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            '${fans.length} PAIRED · LONG-PRESS FOR OPTIONS',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: kTextMut, letterSpacing: 2.2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
            itemCount: fans.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RepaintBoundary(
                child: _FanRow(key: ValueKey(fans[i].deviceId), fan: fans[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Fan row ───────────────────────────────────────────────────────────────────

class _FanRow extends ConsumerStatefulWidget {
  final FanDevice fan;
  const _FanRow({super.key, required this.fan});

  @override
  ConsumerState<_FanRow> createState() => _FanRowState();
}

class _FanRowState extends ConsumerState<_FanRow> {
  bool _pressed = false;

  void _tap() {
    unawaited(context.push(AppRoutes.control, extra: widget.fan));
  }

  void _longPress() {
    unawaited(HapticFeedback.mediumImpact());
    _showActions();
  }

  void _showActions() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => _ActionSheet(
        fan: widget.fan,
        onRename: () {
          Navigator.of(sheetCtx).pop();
          _showRename();
        },
        onRemove: () {
          Navigator.of(sheetCtx).pop();
          _confirmDelete();
        },
        onClose: () => Navigator.of(sheetCtx).pop(),
      ),
    ));
  }

  void _showRename() => unawaited(_doRename());

  Future<void> _doRename() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _RenameSheet(initialName: widget.fan.nickname),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await ref.read(fanRepositoryProvider).renameFan(widget.fan.deviceId, name);
      if (mounted) ref.invalidate(savedFansProvider);
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rename failed. Please try again.')),
        );
      }
    }
  }

  void _confirmDelete() => unawaited(_doDelete());

  Future<void> _doDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Remove Device?',
            style: GoogleFonts.manrope(
              color: kText, fontWeight: FontWeight.w700,
            )),
        content: Text('Remove "${widget.fan.nickname}" from your device?',
            style: GoogleFonts.manrope(color: kTextMut)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: kTextMut))),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(fanRepositoryProvider).deleteFan(widget.fan.deviceId);
      if (mounted) ref.invalidate(savedFansProvider);
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remove failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connState    = ref.watch(bleConnectionStateProvider).valueOrNull;
    final connectedMac = ref.watch(bleServiceProvider).connectedMacAddress;
    final isConnected  = connState == BleConnectionState.connected &&
        widget.fan.macAddress.isNotEmpty &&
        connectedMac?.toLowerCase() == widget.fan.macAddress.toLowerCase();

    return GestureDetector(
      onTap: _tap,
      onLongPress: _longPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressed ? kCardElev : kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kHairline),
        ),
        child: Row(
          children: [
            // Fan icon
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: kCardHi,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TerratonFanIcon(
                size: 26,
                spinning: isConnected,
                color: isConnected ? kYellow : kTextDim,
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fan.nickname,
                    style: GoogleFonts.manrope(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: kText, letterSpacing: -0.2,
                    ),
                  ),
                  if (widget.fan.model.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.fan.model,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: kTextMut, letterSpacing: 0.8,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? kGreen : kTextDim,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        isConnected ? 'Connected' : 'Disconnected',
                        style: GoogleFonts.manrope(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: isConnected ? kGreen : kTextMut,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kTextDim, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Action sheet ──────────────────────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  final FanDevice fan;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  const _ActionSheet({
    required this.fan,
    required this.onRename,
    required this.onRemove,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 14),
            decoration: BoxDecoration(
              color: kCardHi, borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fan.nickname,
                    style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kText,
                    )),
                if (fan.model.isNotEmpty)
                  Text(fan.model.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: kTextMut, letterSpacing: 1.2,
                      )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.edit_outlined,
                  label: 'Rename Fan',
                  onTap: onRename,
                ),
                const SizedBox(height: 8),
                _ActionRow(
                  icon: Icons.delete_outline,
                  label: 'Remove Device',
                  danger: true,
                  onTap: onRemove,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(
                  backgroundColor: kCardElev,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text('Cancel',
                    style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w600, color: kText,
                    )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? kRed : kText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: danger ? kRed.withAlpha(30) : kYellow.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w600, color: color,
                  )),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: kTextDim),
          ],
        ),
      ),
    );
  }
}

// ── Rename sheet ──────────────────────────────────────────────────────────────

class _RenameSheet extends StatefulWidget {
  final String initialName;
  const _RenameSheet({required this.initialName});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();
  static final _nameRegex = RegExp(r'^[a-zA-Z0-9 ]+$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name cannot be empty';
    if (v.length > 30) return 'Max 30 characters';
    if (!_nameRegex.hasMatch(v)) return 'Alphanumeric and spaces only';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        left: 20, right: 20, top: 12,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: kCardHi, borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rename Fan',
                style: GoogleFonts.manrope(
                  fontSize: 20, fontWeight: FontWeight.w700, color: kText,
                )),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ctrl,
              maxLength: 30,
              autofocus: true,
              style: GoogleFonts.manrope(
                color: kText, fontSize: 15, fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Living Room Fan',
                hintStyle: GoogleFonts.manrope(color: kTextDim),
                counterText: '',
                suffix: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, v, __) => Text(
                    '${v.text.length}/30',
                    style: kMonoStyle(size: 11, color: kTextMut),
                  ),
                ),
              ),
              validator: _validate,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: kCardElev,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.manrope(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: kText,
                          )),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctrl,
                      builder: (_, v, __) {
                        final ok = v.text.trim().isNotEmpty;
                        return ElevatedButton(
                          onPressed: ok
                              ? () {
                                  if (_formKey.currentState!.validate()) {
                                    Navigator.of(context).pop(_ctrl.text.trim());
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ok ? kYellow : kCardElev,
                            foregroundColor: ok ? Colors.black : kTextDim,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text('Save',
                              style: GoogleFonts.manrope(
                                fontSize: 14, fontWeight: FontWeight.w700,
                              )),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
