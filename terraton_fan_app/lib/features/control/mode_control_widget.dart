// lib/features/control/mode_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// The operating-modes row. Which buttons appear — and in what order — is
/// driven entirely by [modes], a per-remote list from appliances.yaml
/// (`RemoteProfile.modes`). Recognised entries:
///
///   nature | smart | reverse  → mode-frame buttons, routed through [onMode]
///   boost                     → the Boost button, routed through [onBoost]
///   led                       → speed-indication LED toggle, routed through [onLed]
///
/// The widget holds no state: `activeMode` / `isBoost` / `ledOn` are supplied
/// by the caller and every tap is a single callback. Unknown entries are
/// ignored.
class ModeControlWidget extends StatelessWidget {
  /// Ordered mode-row buttons for the active remote.
  final List<String> modes;

  final String? activeMode;
  final bool isBoost;
  final bool ledOn;
  final bool enabled;

  // Firmware rejects Smart at speed 1/2 (case BOOST's SMART_MODE branch and
  // case IRSmartMode both gate on `TargetSpeed > 2`, unless Nature/Reverse is
  // active) — the BLE path still echoes a false "Smart set" confirmation
  // when rejected, so the app must not rely on that echo and must simply
  // never let the tap happen in the first place.
  final int currentSpeed;

  final void Function(String mode) onMode;
  final VoidCallback onBoost;
  final void Function(bool on) onLed;

  const ModeControlWidget({
    super.key,
    required this.modes,
    required this.activeMode,
    required this.isBoost,
    required this.enabled,
    required this.currentSpeed,
    required this.onMode,
    required this.onBoost,
    required this.onLed,
    this.ledOn = false,
  });

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

    final buttons = <Widget>[];
    for (var i = 0; i < modes.length; i++) {
      final child = _buttonFor(modes[i], smartDisabled: smartDisabled);
      if (child == null) continue;
      buttons.add(Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i == modes.length - 1 ? 0 : 8),
          child: child,
        ),
      ));
    }

    return Row(children: buttons);
  }

  Widget? _buttonFor(String mode, {required bool smartDisabled}) {
    switch (mode) {
      case 'nature':
        return _ModeBtn(
          assetPath: 'assets/icons/nature_plant.png',
          label: 'Nature',
          isActive: activeMode == 'nature',
          enabled: enabled,
          onTap: () => _fire(() => onMode('nature')),
        );
      case 'smart':
        return _ModeBtn(
          icon: Icons.auto_awesome_outlined,
          label: 'Smart',
          isActive: activeMode == 'smart',
          enabled: enabled && !smartDisabled,
          onTap: () => _fire(() => onMode('smart')),
        );
      case 'reverse':
        return _ModeBtn(
          icon: Icons.sync_rounded,
          label: 'Reverse',
          isActive: activeMode == 'reverse',
          enabled: enabled,
          onTap: () => _fire(() => onMode('reverse')),
        );
      case 'boost':
        // GestureDetector + ValueKey('boost_button') kept for widget tests and
        // to match the original hit target.
        return Semantics(
          button: true,
          label: 'Boost mode',
          selected: isBoost,
          enabled: enabled,
          child: GestureDetector(
            key: const ValueKey('boost_button'),
            onTap: enabled ? () => _fire(onBoost) : null,
            child: _ModeBtn(
              assetPath: 'assets/icons/boost_rocket.png',
              label: 'Boost',
              isActive: isBoost,
              enabled: enabled,
              onTap: null, // handled by the outer GestureDetector
            ),
          ),
        );
      case 'led':
        return _ModeBtn(
          key: const ValueKey('led_button'),
          icon: ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
          label: 'LED',
          isActive: ledOn,
          enabled: enabled,
          onTap: () => _fire(() => onLed(!ledOn)),
        );
      default:
        return null;
    }
  }

  void _fire(VoidCallback action) {
    unawaited(HapticFeedback.lightImpact());
    action();
  }
}

// ── Mode button ───────────────────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final IconData?  icon;       // Material icon (Smart / Reverse / LED)
  final String?    assetPath;  // PNG asset (Nature / Boost)
  final String     label;
  final bool       isActive;
  final bool       enabled;
  final VoidCallback? onTap;   // null for boost (outer GestureDetector handles it)

  const _ModeBtn({
    super.key,
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
