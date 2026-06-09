// lib/shared/terraton_fan_icon.dart
//
// Vector-drawn Terraton fan icon — exact translation of Icon.fan from
// components.jsx.  Draws 4 curved blades + a filled centre dot, all at
// native Flutter resolution (no PNG, no raster artefacts).
//
// Optional `spinning` flag drives a continuous rotation animation, matching
// the JSX `tn-spin` keyframe used in home.jsx FanIcon.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class TerratonFanIcon extends StatefulWidget {
  final double size;
  final Color color;
  final bool spinning;
  /// If provided, renders this image asset instead of the custom-painted blades.
  /// The spin animation still applies when [spinning] is true.
  final String? imagePath;

  const TerratonFanIcon({
    super.key,
    this.size = 24,
    this.color = kYellow,
    this.spinning = false,
    this.imagePath,
  });

  @override
  State<TerratonFanIcon> createState() => _TerratonFanIconState();
}

class _TerratonFanIconState extends State<TerratonFanIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.spinning) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(TerratonFanIcon old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !old.spinning) {
      _ctrl.repeat();
    } else if (!widget.spinning && old.spinning) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = widget.imagePath != null
        ? Image.asset(
            widget.imagePath!,
            width: widget.size,
            height: widget.size,
            color: widget.color,
            colorBlendMode: BlendMode.srcIn,
          )
        : CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _TerratonFanPainter(color: widget.color),
          );

    if (!widget.spinning) return icon;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: icon,
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
// Coordinates are in the SVG viewBox (0 0 24 24) from components.jsx Icon.fan.
// The canvas is pre-scaled so (0,0)-(24,24) maps to (0,0)-(size,size).

class _TerratonFanPainter extends CustomPainter {
  final Color color;
  const _TerratonFanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from 24×24 viewBox to actual widget size
    final s = size.width / 24.0;
    canvas.scale(s, s);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color.withAlpha(20) // rgba(255,236,0,0.08)
      ..style = PaintingStyle.fill;

    // ── Four blades — each is three chained cubic bezier segments ────────────
    // Converted from SVG relative `c` commands (each dx/dy is relative to the
    // *start* of that particular cubic, not to the previous control point).

    // Blade 1 — top  (M 12,10 → 6,5 → 9,2 → 12,7)
    final b1 = Path()
      ..moveTo(12, 10)
      ..cubicTo(9, 9, 6, 7, 6, 5)
      ..cubicTo(6, 3.5, 7.5, 2, 9, 2)
      ..cubicTo(11, 2, 12.5, 4, 12, 7);

    // Blade 2 — right (M 14,12 → 19,6 → 22,9 → 17,12)
    final b2 = Path()
      ..moveTo(14, 12)
      ..cubicTo(15, 9, 17, 6, 19, 6)
      ..cubicTo(20.5, 6, 22, 7.5, 22, 9)
      ..cubicTo(22, 11, 20, 12.5, 17, 12);

    // Blade 3 — bottom (M 12,14 → 18,19 → 15,22 → 12,17)
    final b3 = Path()
      ..moveTo(12, 14)
      ..cubicTo(15, 15, 18, 17, 18, 19)
      ..cubicTo(18, 20.5, 16.5, 22, 15, 22)
      ..cubicTo(13, 22, 11.5, 20, 12, 17);

    // Blade 4 — left  (M 10,12 → 5,18 → 2,15 → 7,12)
    final b4 = Path()
      ..moveTo(10, 12)
      ..cubicTo(9, 15, 7, 18, 5, 18)
      ..cubicTo(3.5, 18, 2, 16.5, 2, 15)
      ..cubicTo(2, 13, 4, 11.5, 7, 12);

    for (final blade in [b1, b2, b3, b4]) {
      canvas.drawPath(blade, fill);
      canvas.drawPath(blade, stroke);
    }

    // Centre dot (r=2, filled with solid accent colour)
    canvas.drawCircle(const Offset(12, 12), 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TerratonFanPainter old) => old.color != color;
}
