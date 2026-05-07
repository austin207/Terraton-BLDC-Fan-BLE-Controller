// lib/features/control/circular_speed_dial.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme.dart';

class CircularSpeedDial extends StatelessWidget {
  final int currentSpeed; // 0 = none; 1-6
  final int? watts;
  final int? rpm;
  final bool enabled;
  final void Function(int speed) onSpeedSelected;

  const CircularSpeedDial({
    super.key,
    required this.currentSpeed,
    required this.watts,
    required this.rpm,
    required this.enabled,
    required this.onSpeedSelected,
  });

  static const double _startAngle = -math.pi * 0.85;
  static const double _totalSweep = math.pi * 1.70;
  static const double _gap = 0.05;

  @override
  Widget build(BuildContext context) {
    final segAngle = (_totalSweep - _gap * 6) / 6;

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 6; i++)
            GestureDetector(
              onTap: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onSpeedSelected(i + 1);
                    }
                  : null,
              child: CustomPaint(
                size: const Size(260, 260),
                painter: _SegmentPainter(
                  speedIndex: i,
                  color: kSpeedColors[i],
                  startAngle: _startAngle + i * (segAngle + _gap),
                  sweepAngle: segAngle,
                  active: currentSpeed == i + 1,
                  enabled: enabled,
                ),
              ),
            ),
          // Centre readout
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                watts != null ? '$watts W' : '-- W',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                rpm != null ? '$rpm RPM' : '-- RPM',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              if (currentSpeed > 0)
                Text(
                  'Speed $currentSpeed',
                  style: TextStyle(
                    fontSize: 13,
                    color: kSpeedColors[currentSpeed - 1],
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  final int    speedIndex;
  final Color  color;
  final double startAngle;
  final double sweepAngle;
  final bool   active;
  final bool   enabled;

  const _SegmentPainter({
    required this.speedIndex,
    required this.color,
    required this.startAngle,
    required this.sweepAngle,
    required this.active,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.55;
    final c      = enabled ? color : color.withAlpha(80);

    final outerRect = Rect.fromCircle(center: centre, radius: outerR);
    final innerRect = Rect.fromCircle(center: centre, radius: innerR);

    final path = Path()
      ..arcTo(outerRect, startAngle, sweepAngle, false)
      ..arcTo(innerRect, startAngle + sweepAngle, -sweepAngle, false)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..style = active ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = c,
    );

    // Speed number label at arc midpoint
    final mid    = startAngle + sweepAngle / 2;
    final labelR = (outerR + innerR) / 2;
    final lx     = centre.dx + labelR * math.cos(mid);
    final ly     = centre.dy + labelR * math.sin(mid);

    final tp = TextPainter(
      text: TextSpan(
        text: '${speedIndex + 1}',
        style: TextStyle(
          color: active ? Colors.white : c,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.active != active || old.enabled != enabled;
}
