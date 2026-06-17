// lib/features/control/circular_speed_dial.dart
// Class name kept as CircularSpeedDial for test compatibility.
// Implements the radial dot-ring design from the JSX fan-control.jsx spec.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show setEquals;
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
  final bool isNature;    // dial fully locked, leaf icon in centre
  final bool isSmart;     // dial fully locked, smart icon in centre
  final bool isReverse;   // dial fully locked, reverse icon in centre
  final Set<int> disabledSpeeds;
  final void Function(int speed) onSpeedSelected;

  const CircularSpeedDial({
    super.key,
    required this.currentSpeed,
    required this.watts,
    required this.rpm,
    required this.enabled,
    required this.isBoost,
    required this.onSpeedSelected,
    this.isNature = false,
    this.isSmart = false,
    this.isReverse = false,
    this.disabledSpeeds = const {},
  });

  @override
  Widget build(BuildContext context) {
    return _RadialDial(
      speed: currentSpeed,
      watts: watts,
      rpm: rpm,
      enabled: enabled,
      boost: isBoost,
      isNature: isNature,
      isSmart: isSmart,
      isReverse: isReverse,
      disabledSpeeds: disabledSpeeds,
      onSpeedTap: (s) {
        // Nature/Smart dim certain dots for visual feedback, but a tap on a
        // dimmed dot still registers — the control screen interprets it as
        // "exit Nature/Smart and apply this speed".
        if (!enabled) return;
        unawaited(HapticFeedback.lightImpact());
        onSpeedSelected(s);
      },
    );
  }
}

// ── Dot state enum ────────────────────────────────────────────────────────────

enum _DotState { selected, off }

/// Single source of truth for dot state — used by both _RadialDial (hit areas
/// / labels) and _DialPainter (canvas rendering) to prevent divergence.
_DotState _dotStateOf({
  required int index,
  required int speed,
  required bool boost,
  required bool enabled,
  bool isNature = false,
  bool isSmart = false,
  bool isReverse = false,
  Set<int> disabledSpeeds = const {},
}) {
  if (isNature || isSmart || isReverse) return _DotState.off;
  if (!enabled) return _DotState.off;
  // Boost overrides disabled-speed dimming so the full ring glows in BOOST+SMART/REVERSE.
  // Hit-target tappability still respects disabledSpeeds (handled separately).
  if (boost) return _DotState.selected;
  if (disabledSpeeds.contains(index + 1)) return _DotState.off;
  if (speed <= 0) return _DotState.off;
  if (index == speed - 1) return _DotState.selected;
  return _DotState.off;
}

// ── Radial dot-ring dial ──────────────────────────────────────────────────────

class _RadialDial extends StatelessWidget {
  final int speed;        // 0 = none; 1–6
  final int? watts;
  final int? rpm;
  final bool enabled;
  final bool boost;
  final bool isNature;
  final bool isSmart;
  final bool isReverse;
  final Set<int> disabledSpeeds;
  final void Function(int) onSpeedTap;

  const _RadialDial({
    required this.speed,
    required this.watts,
    required this.rpm,
    required this.enabled,
    required this.boost,
    required this.isNature,
    required this.isSmart,
    required this.isReverse,
    required this.disabledSpeeds,
    required this.onSpeedTap,
  });

  static const int _pos   = 6;       // 6 speed dots — boost has its own button
  static const double _size = 320;
  static const double _r    = 110;   // ring radius
  static const double _dotD = 14;    // dot diameter
  static const double _hitD = 48;    // hit target — 48 dp meets accessibility minimum
  static const double _lblR = 142;   // label radius

  Offset _polar(double cx, double cy, double radius, double angleDeg) {
    final a = (angleDeg - 90) * math.pi / 180;
    return Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
  }

  _DotState _stateOf(int i) => _dotStateOf(
    index: i, speed: speed, boost: boost, enabled: enabled,
    isNature: isNature, isSmart: isSmart, isReverse: isReverse,
    disabledSpeeds: disabledSpeeds,
  );

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
              isNature: isNature,
              isSmart: isSmart,
              isReverse: isReverse,
              disabledSpeeds: disabledSpeeds,
              pos: _pos,
              r: _r,
              dotD: _dotD,
              angStep: angStep,
            ),
          ),

          // Hit areas for speed 1–6; nature + disabled speeds block taps
          for (int i = 0; i < 6; i++) ...[
            Builder(builder: (_) {
              final ang = i * angStep;
              final pos = _polar(cx, cy, _r, ang);
              // Dimmed dots (Nature/Smart-disabled) remain tappable — tapping
              // them exits Nature/Smart and applies the selected speed.
              final tappable = enabled;
              return Positioned(
                left: pos.dx - _hitD / 2,
                top: pos.dy - _hitD / 2,
                width: _hitD,
                height: _hitD,
                child: Semantics(
                  button: true,
                  label: 'Speed ${i + 1}',
                  enabled: tappable,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: tappable ? () => onSpeedTap(i + 1) : null,
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            }),
          ],

          // Numeric labels 1–6 (outside ring) — non-interactive
          for (int i = 0; i < _pos; i++) ...[
            Builder(builder: (_) {
              final ang = i * angStep;
              final pos = _polar(cx, cy, _lblR, ang);
              final lit = _stateOf(i) != _DotState.off;
              final isUnavailable = isNature || isSmart || isReverse || disabledSpeeds.contains(i + 1);
              final color = lit ? kText : (enabled && !isUnavailable ? kTextMut : kTextDim);
              return Positioned(
                left: pos.dx - 16,
                top: pos.dy - 16,
                width: 32,
                height: 32,
                child: Center(
                  child: Text('${i + 1}',
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
              isNature: isNature,
              isSmart: isSmart,
              isReverse: isReverse,
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
  final bool isNature;
  final bool isSmart;
  final bool isReverse;
  final Set<int> disabledSpeeds;
  final int pos;
  final double r;
  final double dotD;
  final double angStep;

  const _DialPainter({
    required this.speed,
    required this.boost,
    required this.enabled,
    required this.isNature,
    required this.isSmart,
    required this.isReverse,
    required this.disabledSpeeds,
    required this.pos,
    required this.r,
    required this.dotD,
    required this.angStep,
  });

  Offset _polar(double cx, double cy, double radius, double angleDeg) {
    final a = (angleDeg - 90) * math.pi / 180;
    return Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
  }

  _DotState _stateOf(int i) => _dotStateOf(
    index: i, speed: speed, boost: boost, enabled: enabled,
    isNature: isNature, isSmart: isSmart, isReverse: isReverse,
    disabledSpeeds: disabledSpeeds,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Dark core circle
    canvas.drawCircle(
      Offset(cx, cy), r - 16,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.4),
          colors: [kDialCoreTop, kDialCoreBot],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r - 16))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy), r - 16,
      Paint()
        ..color = kGridLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Full thin track ring (only when not boost; always when locked mode to keep ring visible)
    if (!boost || isNature || isSmart || isReverse) {
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = kHairlineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Boost: glowing closed ring (suppressed during any locked mode)
    if (enabled && boost && !isNature && !isSmart && !isReverse) {
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

    // Active arc: suppressed during any locked mode
    if (enabled && !boost && !isNature && !isSmart && !isReverse && speed > 1) {
      final startRad = (0 - 90) * math.pi / 180;
      final sweepRad = (speed - 1) * angStep * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startRad, sweepRad, false,
        Paint()
          ..color = kYellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tick marks + dots at each position
    for (int i = 0; i < pos; i++) {
      final ang = i * angStep;
      final st = _stateOf(i);

      // Tick (short radial mark inside ring)
      final tickOuter = _polar(cx, cy, r - 10, ang);
      final tickInner = _polar(cx, cy, r - 18, ang);
      final tickColor = st == _DotState.selected ? kYellow : kDialTick;
      canvas.drawLine(
        tickInner, tickOuter,
        Paint()
          ..color = tickColor
          ..strokeWidth = st == _DotState.selected ? 2 : 1.5
          ..strokeCap = StrokeCap.round,
      );

      // Dot on the ring — selected: bright yellow glow; off: dark fill covers arc
      final dotPos = _polar(cx, cy, r, ang);
      final dotFill   = st == _DotState.selected ? kYellow : kCardElev;
      final dotStroke = st == _DotState.selected ? kYellow : kDialTick;

      // Bloom/glow for selected dot
      if (st == _DotState.selected) {
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
      old.speed != speed || old.boost != boost || old.enabled != enabled
      || old.isNature != isNature || old.isSmart != isSmart || old.isReverse != isReverse
      || !setEquals(old.disabledSpeeds, disabledSpeeds);
}

// ── Center readout ────────────────────────────────────────────────────────────

class _CenterReadout extends StatelessWidget {
  final int speed;
  final int? watts;
  final int? rpm;
  final bool boost;
  final bool isNature;
  final bool isSmart;
  final bool isReverse;
  final bool enabled;

  const _CenterReadout({
    required this.speed,
    required this.watts,
    required this.rpm,
    required this.boost,
    required this.isNature,
    required this.isSmart,
    required this.isReverse,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isNature) ...[
          Text('GEAR',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              )),
          const SizedBox(height: 8),
          Image.asset(
            'assets/icons/nature_plant.png',
            width: 60, height: 60,
            color: kNatureGreen,
            colorBlendMode: BlendMode.srcIn,
          ),
        ] else if (isSmart) ...[
          Text('GEAR',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              )),
          const SizedBox(height: 8),
          const Icon(Icons.auto_awesome_outlined, size: 60, color: kYellow),
        ] else if (isReverse) ...[
          Text('GEAR',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              )),
          const SizedBox(height: 8),
          const Icon(Icons.sync_rounded, size: 60, color: kYellow),
        ] else if (boost) ...[
          Text('BOOST',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.8,
              )),
          const SizedBox(height: 8),
          Image.asset(
            'assets/icons/boost_rocket.png',
            width: 60, height: 60,
            color: kYellow,
            colorBlendMode: BlendMode.srcIn,
          ),
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
              value: (enabled && (speed > 0 || boost || isNature || isSmart || isReverse)) ? (rpm != null ? '$rpm' : '—') : '—',
            ),
            Container(width: 1, height: 28, color: kHairline, margin: const EdgeInsets.symmetric(horizontal: 18)),
            _Stat(
              label: 'WATTS',
              value: (enabled && (speed > 0 || boost || isNature || isSmart || isReverse)) ? (watts != null ? '$watts' : '—') : '—',
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
