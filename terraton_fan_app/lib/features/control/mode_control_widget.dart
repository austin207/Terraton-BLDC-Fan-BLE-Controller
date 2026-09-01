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
  // Firmware rejects Smart at speed 1/2 (case BOOST's SMART_MODE branch and
  // case IRSmartMode both gate on `TargetSpeed > 2`, unless Nature/Reverse is
  // active) — the BLE path still echoes a false "Smart set" confirmation
  // when rejected, so the app must not rely on that echo and must simply
  // never let the tap happen in the first place.
  final int currentSpeed;
  final void Function(String mode) onMode;
  final VoidCallback onBoost;

  const ModeControlWidget({
    super.key,
    required this.activeMode,
    required this.isBoost,
    required this.enabled,
    required this.currentSpeed,
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
    // Only blocks Smart when the dial is actually SHOWING a plain speed of
    // 1 or 2 — i.e. no other mode chip is lit. While Boost/Nature/Reverse is
    // active, `currentSpeed` is a stale pre-mode value (no 0x04 frame ever
    // arrives while a mode is running), and firmware already handles Smart
    // engaged from Nature/Reverse on its own (forces a fixed Speed-4 start
    // regardless of what came before) — so that stale value must not gate
    // Smart here too.
    final smartDisabled = !isBoost && activeMode == null &&
        (currentSpeed == 1 || currentSpeed == 2);

    return Row(
      children: [
        // 3 mode buttons
        ..._modes.map((entry) {
          final isActive = activeMode == entry.mode;
          final btnEnabled = entry.mode == 'smart' ? (enabled && !smartDisabled) : enabled;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ModeBtn(
                icon: entry.icon,
                assetPath: entry.assetPath,
                label: entry.label,
                isActive: isActive,
                enabled: btnEnabled,
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
