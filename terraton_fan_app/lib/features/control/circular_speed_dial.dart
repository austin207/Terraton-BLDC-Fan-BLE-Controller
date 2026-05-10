// lib/features/control/circular_speed_dial.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class CircularSpeedDial extends StatelessWidget {
  final int currentSpeed; // 0 = none; 1–6
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative rainbow arc with telemetry
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // White disc behind the arc — gives a "speedometer" look
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: const Size(260, 260),
                painter: _DecorativeArcPainter(
                  currentSpeed: currentSpeed,
                  enabled: enabled,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    watts != null ? '$watts W' : '-- W',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: enabled ? Colors.black87 : Colors.grey.shade400,
                    ),
                  ),
                  Text(
                    rpm != null ? '$rpm RPM' : '-- RPM',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 3×2 speed button grid
        SizedBox(
          width: 280,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.8,
            children: List.generate(6, (i) {
              final speed = i + 1;
              final isActive = currentSpeed == speed;
              return Semantics(
                button: true,
                label: 'Speed $speed',
                selected: isActive,
                child: GestureDetector(
                  onTap: enabled
                      ? () {
                          HapticFeedback.lightImpact();
                          onSpeedSelected(speed);
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isActive ? kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? kPrimary : Colors.grey.shade200,
                        width: 1.5,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: kPrimary.withAlpha(60),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$speed',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? (isActive ? Colors.white : Colors.black87)
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _DecorativeArcPainter extends CustomPainter {
  final int currentSpeed;
  final bool enabled;

  const _DecorativeArcPainter({required this.currentSpeed, required this.enabled});

  static const double _startAngle = -math.pi * 0.85;
  static const double _totalSweep = math.pi * 1.70;
  static const double _gap = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final segAngle = (_totalSweep - _gap * 6) / 6;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    for (int i = 0; i < 6; i++) {
      final start = _startAngle + i * (segAngle + _gap);
      final isActive = currentSpeed == i + 1;
      final baseColor = kSpeedColors[i];
      final color = enabled ? baseColor : baseColor.withAlpha(70);

      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        segAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 14.0 : 7.0
          ..strokeCap = StrokeCap.round
          ..color = isActive ? color : color.withAlpha(enabled ? 140 : 60),
      );
    }
  }

  @override
  bool shouldRepaint(_DecorativeArcPainter old) =>
      old.currentSpeed != currentSpeed || old.enabled != enabled;
}
