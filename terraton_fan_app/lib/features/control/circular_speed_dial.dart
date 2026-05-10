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
  final bool isBoost;
  final void Function(int speed) onSpeedSelected;

  const CircularSpeedDial({
    super.key,
    required this.currentSpeed,
    required this.watts,
    required this.rpm,
    required this.enabled,
    required this.isBoost,
    required this.onSpeedSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Decorative arc with white disc and telemetry ─────────────────────
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // White disc behind the arc (speedometer look)
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: isBoost
                          ? const Color(0xFFFF6600).withAlpha(60)
                          : Colors.black.withAlpha(18),
                      blurRadius: isBoost ? 28 : 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
              // Arc — gap opens at the BOTTOM
              CustomPaint(
                size: const Size(260, 260),
                painter: _DecorativeArcPainter(
                  currentSpeed: currentSpeed,
                  enabled: enabled,
                  isBoost: isBoost,
                ),
              ),
              // Telemetry text centred in the disc
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    watts != null ? '$watts W' : '-- W',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: isBoost
                          ? const Color(0xFFFF6600)
                          : (enabled ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rpm != null ? '$rpm RPM' : '-- RPM',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isBoost
                          ? const Color(0xFFFF8C00).withAlpha(180)
                          : (enabled ? const Color(0xFF94A3B8) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 3×2 speed button grid ─────────────────────────────────────────────
        SizedBox(
          width: 300,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: List.generate(6, (i) {
              final speed    = i + 1;
              final isActive = speed == currentSpeed; // exclusive single-button selection
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
                        color: isActive ? kPrimary : const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                      boxShadow: isActive
                          ? [BoxShadow(color: kPrimary.withAlpha(50), blurRadius: 8, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$speed',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? Colors.white
                              : (enabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
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
  final bool isBoost;

  const _DecorativeArcPainter({
    required this.currentSpeed,
    required this.enabled,
    required this.isBoost,
  });

  // Gap centred at the bottom (π/2 = 6 o'clock).
  // Gap width ≈ 110°  →  arc sweeps ≈ 250°
  static const double _gapDeg    = 110.0;
  static const double _startAngle = (90 + _gapDeg / 2) * math.pi / 180;
  static const double _totalSweep = (360 - _gapDeg)    * math.pi / 180;
  static const double _segGap     = 0.04;

  // Energetic warm gradient used when boost is active
  static const List<Color> _boostColors = [
    Color(0xFFFFB300),
    Color(0xFFFF8C00),
    Color(0xFFFF6600),
    Color(0xFFFF4500),
    Color(0xFFFF3300),
    Color(0xFFDC2626),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final segAngle = (_totalSweep - _segGap * 6) / 6;
    final centre   = Offset(size.width / 2, size.height / 2);
    final radius   = size.width / 2 - 16;

    for (int i = 0; i < 6; i++) {
      final start = _startAngle + i * (segAngle + _segGap);

      Color segColor;
      bool  isFilled;

      if (isBoost) {
        isFilled = true;
        final c  = _boostColors[i];
        segColor = enabled ? c : c.withAlpha(70);
      } else {
        isFilled = currentSpeed > 0 && i + 1 <= currentSpeed; // progressive fill
        final c  = kSpeedColors[i];
        if (isFilled) {
          segColor = enabled ? c : c.withAlpha(70);
        } else {
          segColor = c.withAlpha(enabled ? 90 : 40);
        }
      }

      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        segAngle,
        false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = isFilled ? 13.0 : 7.0
          ..strokeCap   = StrokeCap.round
          ..color       = segColor,
      );
    }
  }

  @override
  bool shouldRepaint(_DecorativeArcPainter old) =>
      old.currentSpeed != currentSpeed ||
      old.enabled != enabled ||
      old.isBoost != isBoost;
}
