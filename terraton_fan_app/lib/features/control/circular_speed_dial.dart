// lib/features/control/circular_speed_dial.dart
// Class name kept as CircularSpeedDial for test compatibility.
// Implements the radial dot-ring design from the JSX fan-control.jsx spec.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class CircularSpeedDial extends StatelessWidget {
  final int currentSpeed;  // 0 = none; 1–6
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
    return _RadialDial(
      speed: currentSpeed,
      watts: watts,
      rpm: rpm,
      enabled: enabled,
      boost: isBoost,
      onSpeedTap: (s) {
        if (!enabled) return;
        unawaited(HapticFeedback.lightImpact());
        onSpeedSelected(s);
      },
    );
  }
}

// ── Radial dot-ring dial ──────────────────────────────────────────────────────

class _RadialDial extends StatelessWidget {
  final int speed;        // 0 = none; 1–6
  final int? watts;
  final int? rpm;
  final bool enabled;
  final bool boost;
  final void Function(int) onSpeedTap;

  const _RadialDial({
    required this.speed,
    required this.watts,
    required this.rpm,
    required this.enabled,
    required this.boost,
    required this.onSpeedTap,
  });

  static const int _pos   = 7;       // 7 indicators: speed 1–6 + boost placeholder
  static const double _size = 320;
  static const double _r    = 110;   // ring radius
  static const double _dotD = 14;    // dot diameter
  static const double _hitD = 36;    // hit target diameter
  static const double _lblR = 142;   // label radius

  Offset _polar(double cx, double cy, double radius, double angleDeg) {
    final a = (angleDeg - 90) * math.pi / 180;
    return Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
  }

  // State for each dot: 'selected', 'progress', 'off'
  String _stateOf(int i) {
    if (!enabled) return 'off';
    if (boost) return 'selected';
    if (speed <= 0) return 'off';
    if (i == speed - 1) return 'selected';
    if (i < speed - 1) return 'progress';
    return 'off';
  }

  @override
  Widget build(BuildContext context) {
    const cx = _size / 2;
    const cy = _size / 2;
    final angStep = 360.0 / _pos;

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          // SVG-style ring + arc + dots painted via CustomPaint
          CustomPaint(
            size: const Size(_size, _size),
            painter: _DialPainter(
              speed: speed,
              boost: boost,
              enabled: enabled,
              pos: _pos,
              r: _r,
              dotD: _dotD,
              angStep: angStep,
            ),
          ),

          // Hit areas for speed 1–6 (no hit area for 7th boost dot; boost is
          // controlled from the mode section)
          for (int i = 0; i < 6; i++) ...[
            Builder(builder: (_) {
              final ang = i * angStep;
              final pos = _polar(cx, cy, _r, ang);
              return Positioned(
                left: pos.dx - _hitD / 2,
                top: pos.dy - _hitD / 2,
                width: _hitD,
                height: _hitD,
                child: Semantics(
                  button: true,
                  label: 'Speed ${i + 1}',
                  enabled: enabled,
                  child: GestureDetector(
                    onTap: enabled ? () => onSpeedTap(i + 1) : null,
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            }),
          ],

          // Static numeric labels (outside ring) — non-interactive
          for (int i = 0; i < _pos; i++) ...[
            Builder(builder: (_) {
              final ang = i * angStep;
              final pos = _polar(cx, cy, _lblR, ang);
              final isLast = i == 6; // lightning = boost indicator
              final lit = _stateOf(i) != 'off';
              final color = lit ? kText : (enabled ? kTextMut : kTextDim);
              return Positioned(
                left: pos.dx - 16,
                top: pos.dy - 16,
                width: 32,
                height: 32,
                child: Center(
                  child: isLast
                      ? Icon(Icons.bolt_rounded, size: 16, color: color)
                      : Text('${i + 1}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13, fontWeight: FontWeight.w700, color: color,
                          )),
                ),
              );
            }),
          ],

          // Center readout
          Positioned.fill(
            child: _CenterReadout(
              speed: speed,
              watts: watts,
              rpm: rpm,
              boost: boost,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dial painter ──────────────────────────────────────────────────────────────

class _DialPainter extends CustomPainter {
  final int speed;
  final bool boost;
  final bool enabled;
  final int pos;
  final double r;
  final double dotD;
  final double angStep;

  const _DialPainter({
    required this.speed,
    required this.boost,
    required this.enabled,
    required this.pos,
    required this.r,
    required this.dotD,
    required this.angStep,
  });

  Offset _polar(double cx, double cy, double radius, double angleDeg) {
    final a = (angleDeg - 90) * math.pi / 180;
    return Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
  }

  String _stateOf(int i) {
    if (!enabled) return 'off';
    if (boost) return 'selected';
    if (speed <= 0) return 'off';
    if (i == speed - 1) return 'selected';
    if (i < speed - 1) return 'progress';
    return 'off';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dark core circle
    canvas.drawCircle(
      Offset(cx, cy), r - 16,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.4),
          colors: [const Color(0xFF1F1F1F), const Color(0xFF0A0A0A)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r - 16))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy), r - 16,
      Paint()
        ..color = const Color(0x0AFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Full thin track ring (only when not boost)
    if (!boost) {
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = const Color(0x1AFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Boost: glowing closed ring
    if (enabled && boost) {
      final paint = Paint()
        ..color = kYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(cx, cy), r, paint);
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = kYellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Active arc from dot 0 → selected dot
    if (enabled && !boost && speed > 1) {
      final startRad = (0 - 90) * math.pi / 180;
      final sweepRad = (speed - 1) * angStep * math.pi / 180;
      final arcPaint = Paint()
        ..color = const Color(0xFFC2B100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startRad, sweepRad, false, arcPaint,
      );
    }

    // Tick marks + dots at each position
    for (int i = 0; i < pos; i++) {
      final ang = i * angStep;
      final st = _stateOf(i);

      // Tick (short radial mark inside ring)
      final tickOuter = _polar(cx, cy, r - 10, ang);
      final tickInner = _polar(cx, cy, r - 18, ang);
      final tickColor = st == 'selected' ? kYellow
          : st == 'progress' ? const Color(0xFFC2B100)
          : const Color(0x38FFFFFF);
      canvas.drawLine(
        tickInner, tickOuter,
        Paint()
          ..color = tickColor
          ..strokeWidth = st == 'selected' ? 2 : 1.5
          ..strokeCap = StrokeCap.round,
      );

      // Dot on the ring
      final dotPos = _polar(cx, cy, r, ang);
      final dotFill = st == 'selected' ? kYellow
          : st == 'progress' ? const Color(0xFFC2B100)
          : const Color(0xFF1A1A1A);
      final dotStroke = st == 'selected' ? kYellow
          : st == 'progress' ? const Color(0xFFC2B100)
          : const Color(0x38FFFFFF);

      // Bloom/glow for selected dot
      if (st == 'selected') {
        canvas.drawCircle(
          dotPos, dotD / 2 + 6,
          Paint()
            ..color = kYellow.withAlpha(40)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.drawCircle(
          dotPos, dotD / 2 + 3,
          Paint()
            ..color = kYellow.withAlpha(20)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      canvas.drawCircle(
        dotPos, dotD / 2,
        Paint()..color = dotFill,
      );
      canvas.drawCircle(
        dotPos, dotD / 2,
        Paint()
          ..color = dotStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.speed != speed || old.boost != boost || old.enabled != enabled;
}

// ── Center readout ────────────────────────────────────────────────────────────

class _CenterReadout extends StatelessWidget {
  final int speed;
  final int? watts;
  final int? rpm;
  final bool boost;
  final bool enabled;

  const _CenterReadout({
    required this.speed,
    required this.watts,
    required this.rpm,
    required this.boost,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (boost) ...[
          Text('BOOST',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.8,
              )),
          const SizedBox(height: 8),
          Icon(Icons.bolt_rounded, size: 60, color: kYellow,
              shadows: [Shadow(color: kYellow.withAlpha(128), blurRadius: 20)]),
        ] else ...[
          Text('GEAR',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              )),
          const SizedBox(height: 2),
          Text(
            enabled && speed > 0 ? '$speed' : '—',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 80, fontWeight: FontWeight.w600,
              color: enabled ? kText : kTextDim,
              letterSpacing: -3,
              height: 1,
            ),
          ),
        ],
        const SizedBox(height: 14),
        // RPM | WATTS stat row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Stat(
              label: 'RPM',
              value: (enabled && (speed > 0 || boost)) ? (rpm != null ? '$rpm' : '—') : '—',
            ),
            Container(width: 1, height: 28, color: kHairline, margin: const EdgeInsets.symmetric(horizontal: 18)),
            _Stat(
              label: 'WATTS',
              value: (enabled && (speed > 0 || boost)) ? (watts != null ? '$watts' : '—') : '—',
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18, fontWeight: FontWeight.w600, color: kText, height: 1,
            )),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9, fontWeight: FontWeight.w600, color: kTextDim, letterSpacing: 1.8,
            )),
      ],
    );
  }
}
