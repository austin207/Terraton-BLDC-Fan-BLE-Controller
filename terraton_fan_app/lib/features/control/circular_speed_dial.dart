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
        GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: List.generate(6, (i) {
              final speed    = i + 1;
              final isActive = speed == currentSpeed;
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

  // Warm energy gradient for boost mode arc
  static const List<Color> _boostGradientColors = [
    Color(0xFFFFAA00),
    Color(0xFFFF6600),
    Color(0xFFFF3300),
    Color(0xFFDC2626),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final segAngle   = (_totalSweep - _segGap * 6) / 6;
    final centre     = Offset(size.width / 2, size.height / 2);
    final radius     = size.width / 2 - 16;
    final arcRect    = Rect.fromCircle(center: centre, radius: radius);
    final shaderRect = Offset.zero & size;

    // ── Background track: thin dimmed rings always visible ────────────────
    for (int i = 0; i < 6; i++) {
      final start = _startAngle + i * (segAngle + _segGap);
      canvas.drawArc(
        arcRect, start, segAngle, false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeCap   = StrokeCap.round
          ..color       = kSpeedColors[i].withAlpha(enabled ? 38 : 20),
      );
    }

    // ── Filled overlay: ONE continuous arc with smooth gradient ──────────
    // The arc runs from _startAngle to _startAngle + filledSweep on screen,
    // but that range crosses the 2π wrap (395° > 360°). SweepGradient with
    // TileMode.clamp would pin any angle < startAngle to the first colour,
    // making the final segment show green instead of red.
    //
    // Fix: rotate the canvas by −_startAngle so the arc spans [0, filledSweep]
    // in the rotated system. SweepGradient(0, _totalSweep) then maps cleanly
    // without crossing 2π. The rotation is around the sweep centre so the
    // shader alignment is preserved.
    if (isBoost || currentSpeed > 0) {
      final filledSweep = isBoost
          ? _totalSweep
          : currentSpeed * segAngle + (currentSpeed - 1) * _segGap;

      final gradient = isBoost
          ? const SweepGradient(
              startAngle: -0.08,
              endAngle: _totalSweep,
              colors: _boostGradientColors,
              tileMode: TileMode.clamp,
            )
          : const SweepGradient(
              startAngle: -0.08,
              endAngle: _totalSweep,
              colors: kSpeedColors,
              tileMode: TileMode.clamp,
            );

      final paint = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 13.0
        ..strokeCap   = StrokeCap.round;

      if (enabled) {
        paint.shader = gradient.createShader(shaderRect);
      } else {
        paint.color = isBoost
            ? const Color(0xFFFF6600).withAlpha(55)
            : kSpeedColors[currentSpeed - 1].withAlpha(55);
      }

      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(_startAngle);
      canvas.translate(-centre.dx, -centre.dy);
      canvas.drawArc(arcRect, 0, filledSweep, false, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DecorativeArcPainter old) =>
      old.currentSpeed != currentSpeed ||
      old.enabled != enabled ||
      old.isBoost != isBoost;
}
