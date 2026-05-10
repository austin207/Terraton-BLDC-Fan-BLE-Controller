// lib/shared/fan_icon.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 3-blade ceiling fan propeller icon matching the Terraton design.
/// Drop-in replacement for Icon(Icons.wind_power, size: X, color: Y).
class FanIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FanIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FanPainter(color: color)),
    );
  }
}

class _FanPainter extends CustomPainter {
  final Color color;
  const _FanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = size.width * 0.46; // blade tip radius
    final hubR = R * 0.11;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(i * 2 * math.pi / 3);

      // Blade pointing in the –Y direction (upward).
      // Right side = leading edge (convex, sweeps outward).
      // Left side  = trailing edge (concave, swept-back).
      final path = Path()
        ..moveTo(R * 0.10, -R * 0.12)
        ..cubicTo(R * 0.32, -R * 0.22, R * 0.50, -R * 0.58, R * 0.36, -R * 0.88)
        ..cubicTo(R * 0.24, -R * 0.99, -R * 0.04, -R * 0.99, -R * 0.18, -R * 0.88)
        ..cubicTo(-R * 0.30, -R * 0.65, -R * 0.18, -R * 0.35, -R * 0.10, -R * 0.12)
        ..close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }

    canvas.drawCircle(Offset(cx, cy), hubR, paint);
  }

  @override
  bool shouldRepaint(_FanPainter old) => old.color != color;
}
