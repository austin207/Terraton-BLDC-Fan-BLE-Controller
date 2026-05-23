// lib/features/control/mode_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ModeControlWidget extends StatelessWidget {
  final String? activeMode;
  final bool isBoost;
  final bool enabled;
  final void Function(String mode) onMode;
  final VoidCallback onBoost;

  const ModeControlWidget({
    super.key,
    required this.activeMode,
    required this.isBoost,
    required this.enabled,
    required this.onMode,
    required this.onBoost,
  });

  // Nature uses a custom PNG asset; Smart and Reverse use Material icons.
  static const _modes = [
    _ModeEntry('nature',  'Nature',  null, 'assets/icons/nature_plant.png'),
    _ModeEntry('smart',   'Smart',   Icons.auto_awesome_outlined, null),
    _ModeEntry('reverse', 'Reverse', Icons.sync_rounded, null),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 3 mode buttons
        ..._modes.map((entry) {
          final isActive = activeMode == entry.mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ModeBtn(
                icon: entry.icon,
                assetPath: entry.assetPath,
                label: entry.label,
                isActive: isActive,
                enabled: enabled,
                onTap: () {
                  unawaited(HapticFeedback.lightImpact());
                  onMode(entry.mode);
                },
              ),
            ),
          );
        }),

        // Boost button — 4th column; GestureDetector key required by tests
        Expanded(
          child: Semantics(
            button: true,
            label: 'Boost mode',
            selected: isBoost,
            enabled: enabled,
            child: GestureDetector(
              key: const ValueKey('boost_button'),
              onTap: enabled
                  ? () {
                      unawaited(HapticFeedback.lightImpact());
                      onBoost();
                    }
                  : null,
              child: _ModeBtn(
                assetPath: 'assets/icons/boost_rocket.png',
                label: 'Boost',
                isActive: isBoost,
                enabled: enabled,
                onTap: null, // handled by outer GestureDetector
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Mode entry descriptor ─────────────────────────────────────────────────────

class _ModeEntry {
  final String mode;
  final String label;
  final IconData? icon;
  final String? assetPath;
  const _ModeEntry(this.mode, this.label, this.icon, this.assetPath);
}

// ── Mode button ───────────────────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final IconData?  icon;       // Material icon (Smart / Reverse)
  final String?    assetPath;  // PNG asset (Nature / Boost)
  final String     label;
  final bool       isActive;
  final bool       enabled;
  final VoidCallback? onTap;   // null for boost (outer GestureDetector handles it)

  const _ModeBtn({
    this.icon,
    this.assetPath,
    required this.label,
    required this.isActive,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isActive ? kYellow : (enabled ? kText : kTextDim);

    // Render PNG asset with color filter so it adopts the active/idle palette.
    Widget iconWidget;
    if (assetPath != null) {
      iconWidget = Image.asset(
        assetPath!,
        width: 20, height: 20,
        color: iconColor,
        // srcIn: treat all non-transparent pixels as the target color.
        colorBlendMode: BlendMode.srcIn,
      );
    } else {
      iconWidget = Icon(icon, size: 20, color: iconColor);
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        height: 80,
        decoration: BoxDecoration(
          color: isActive ? kYellow.withAlpha(28) : kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? kYellow.withAlpha(100) : kHairline),
          boxShadow: isActive
              ? [BoxShadow(color: kYellow.withAlpha(22), blurRadius: 14, spreadRadius: -4)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? kYellow : (enabled ? kText : kTextDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
