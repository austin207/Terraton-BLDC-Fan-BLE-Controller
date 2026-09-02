// lib/features/control/mode_control_widget.dart
import 'dart:async';
import 'dart:math' as math;
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
          iconBuilder: (color) => _LedBulbIcon(on: ledOn, color: color),
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
  final IconData?  icon;       // Material icon (Smart / Reverse)
  final String?    assetPath;  // PNG asset (Nature / Boost)
  /// Custom glyph builder, given the resolved active/idle colour (LED).
  final Widget Function(Color color)? iconBuilder;
  final String     label;
  final bool       isActive;
  final bool       enabled;
  final VoidCallback? onTap;   // null for boost (outer GestureDetector handles it)

  const _ModeBtn({
    super.key,
    this.icon,
    this.assetPath,
    this.iconBuilder,
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
    if (iconBuilder != null) {
      iconWidget = iconBuilder!(iconColor);
    } else if (assetPath != null) {
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

// ── LED bulb glyph ────────────────────────────────────────────────────────────
// A lightbulb with a power symbol in the glass; radiating rays + a faint fill
// animate in when [on]. Colour follows the mode-button palette.

class _LedBulbIcon extends StatelessWidget {
  final bool on;
  final Color color;
  const _LedBulbIcon({required this.on, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: on ? 1.0 : 0.0, end: on ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (_, t, __) => CustomPaint(
        size: const Size(24, 24),
        painter: _LedBulbPainter(color: color, glow: t),
      ),
    );
  }
}

class _LedBulbPainter extends CustomPainter {
  final Color color;
  final double glow; // 0 = off, 1 = fully lit

  _LedBulbPainter({required this.color, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = s * 0.45;          // glass centre, low enough to leave headroom for rays
    final glassR = s * 0.34;      // bigger glass — more room around the power glyph

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // Rays — seven, spread like the reference: one up, then diagonals and
    // horizontals down each side. Evenly spaced over the top 270°, leaving the
    // bottom clear for the screw base.
    if (glow > 0) {
      final rayPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.06
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: glow);
      // radians clockwise from straight up: 0, ±45°, ±90°, ±135°
      const rays = [-2.356, -1.571, -0.785, 0.0, 0.785, 1.571, 2.356];
      final inner = glassR + s * 0.06;
      final outer = inner + s * 0.115 * glow;
      for (final a in rays) {
        final dx = math.sin(a), dy = -math.cos(a);
        canvas.drawLine(
          Offset(cx + dx * inner, cy + dy * inner),
          Offset(cx + dx * outer, cy + dy * outer),
          rayPaint,
        );
      }
    }

    // Faint glass fill when lit.
    if (glow > 0) {
      canvas.drawCircle(
        Offset(cx, cy),
        glassR,
        Paint()..color = color.withValues(alpha: 0.20 * glow),
      );
    }

    // Glass + a short neck that meets the circle near its bottom.
    canvas.drawCircle(Offset(cx, cy), glassR, stroke);
    final neckTopY = cy + glassR * 0.82;
    final neck = Path()
      ..moveTo(cx - s * 0.17, neckTopY)
      ..lineTo(cx - s * 0.12, neckTopY + s * 0.085)
      ..lineTo(cx + s * 0.12, neckTopY + s * 0.085)
      ..lineTo(cx + s * 0.17, neckTopY);
    canvas.drawPath(neck, stroke);

    // Screw base — two ribs.
    for (var i = 0; i < 2; i++) {
      final y = neckTopY + s * 0.13 + i * s * 0.075;
      final half = s * 0.10 - i * s * 0.015;
      canvas.drawLine(
          Offset(cx - half, y), Offset(cx + half, y), stroke);
    }

    // Power glyph inside the glass — SAME size as before (fixed to s, not the
    // glass radius) so the bigger glass just gives it more breathing room.
    final gc = Offset(cx, cy + s * 0.01);
    final gr = s * 0.16;
    canvas.drawArc(
      Rect.fromCircle(center: gc, radius: gr),
      -math.pi / 2 + 0.62,       // start just past top
      2 * math.pi - 1.24,        // ~71° gap centred on top
      false,
      stroke,
    );
    canvas.drawLine(
      Offset(gc.dx, gc.dy - gr - s * 0.05),
      Offset(gc.dx, gc.dy - gr * 0.12),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_LedBulbPainter old) =>
      old.color != color || old.glow != glow;
}
