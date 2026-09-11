// lib/features/control/lighting_control_widget.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class LightingControlWidget extends StatelessWidget {
  final bool enabled;
  final bool isLightOn;
  final double brightnessValue; // 0.0 = off/dim, 1.0 = full brightness
  final VoidCallback onLightOn;
  final VoidCallback onLightOff;
  final void Function(double) onBrightness;

  // ── Colour-temperature selection — DORMANT ──────────────────────────────────
  // Terraton ships a single (cool) light for now, so the Warm/Neutral/Cool row
  // is hidden. Left fully wired so it can be brought back by flipping
  // [showColorTemp] to true when Terraton adds tunable-white hardware.
  final String colorType; // 'warm' | 'neutral' | 'cool'
  final void Function(String) onColorTypeChanged;
  final bool showColorTemp;

  const LightingControlWidget({
    super.key,
    required this.enabled,
    required this.isLightOn,
    required this.brightnessValue,
    required this.onLightOn,
    required this.onLightOff,
    required this.onBrightness,
    this.colorType = 'cool',
    this.onColorTypeChanged = _noOpColorType,
    this.showColorTemp = false,
  });

  static void _noOpColorType(String _) {}

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: bulb icon + label + ON/OFF toggle ─────────────────────
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: kYellow.withAlpha(25),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  tween: Tween(
                    end: isLightOn ? brightnessValue.clamp(0.0, 1.0) : 0.0,
                  ),
                  builder: (_, v, __) => CustomPaint(
                    size: const Size(20, 20),
                    painter: _BrightnessGlyphPainter(
                      value: v,
                      color: enabled ? kYellow : kYellow.withAlpha(120),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('CoolLight',
                    style: GoogleFonts.manrope(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kText,
                    )),
              ),
              _LightToggle(
                isOn: isLightOn,
                enabled: enabled,
                onLightOn: onLightOn,
                onLightOff: onLightOff,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Colour type: WARM | NEUTRAL | COOL — DORMANT (see showColorTemp) ─
          if (showColorTemp) ...[
            Opacity(
              opacity: enabled && isLightOn ? 1.0 : 0.4,
              child: Row(
                children: [
                  Expanded(child: _TempBtn(label: 'Warm',    isActive: colorType == 'warm'    && isLightOn, color: kLightWarm,    onTap: enabled && isLightOn ? () => onColorTypeChanged('warm')    : null)),
                  const SizedBox(width: 8),
                  Expanded(child: _TempBtn(label: 'Neutral', isActive: colorType == 'neutral' && isLightOn, color: kLightNeutral, onTap: enabled && isLightOn ? () => onColorTypeChanged('neutral') : null)),
                  const SizedBox(width: 8),
                  Expanded(child: _TempBtn(label: 'Cool',    isActive: colorType == 'cool'    && isLightOn, color: kLightCool,    onTap: enabled && isLightOn ? () => onColorTypeChanged('cool')    : null)),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Brightness slider ──────────────────────────────────────────────
          Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: _IntensitySlider(
              value: isLightOn ? brightnessValue : 0.0,
              enabled: enabled && isLightOn,
              onChanged: (v) {
                unawaited(HapticFeedback.selectionClick());
                onBrightness(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Light ON/OFF toggle ───────────────────────────────────────────────────────

class _LightToggle extends StatelessWidget {
  final bool isOn;
  final bool enabled;
  final VoidCallback onLightOn;
  final VoidCallback onLightOff;

  static const _labels = ['ON', 'OFF'];

  const _LightToggle({
    required this.isOn,
    required this.enabled,
    required this.onLightOn,
    required this.onLightOff,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 34,
      decoration: BoxDecoration(
        color: kCardHi,
        borderRadius: BorderRadius.circular(50),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final segW = (constraints.maxWidth - 6) / _labels.length;
          final activeIndex = isOn ? 0 : 1;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: 3 + activeIndex * segW,
                top: 3, bottom: 3, width: segW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kYellow.withAlpha(38),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: kYellow.withAlpha(100)),
                    boxShadow: [BoxShadow(color: kYellow.withAlpha(22), blurRadius: 6)],
                  ),
                ),
              ),
              Row(
                children: _labels.asMap().entries.map((e) {
                  final label    = e.value;
                  final isActive = e.key == activeIndex;
                  return Expanded(
                    child: Semantics(
                      button: true, label: '$label light',
                      selected: isActive, enabled: enabled,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: enabled
                            ? () {
                                unawaited(HapticFeedback.lightImpact());
                                (label == 'ON' ? onLightOn : onLightOff)();
                              }
                            : null,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isActive ? kYellow : kTextMut,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Colour temperature button — DORMANT (rendered only when showColorTemp) ────

class _TempBtn extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback? onTap;

  const _TempBtn({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label colour temperature',
      selected: isActive,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          height: 56,
          decoration: BoxDecoration(
            color: isActive ? color : kCardElev,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? color.withAlpha(200) : kLightSwatchOff,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: color.withAlpha(136), blurRadius: 20, spreadRadius: -4)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: isActive ? kCardElev : const Color(0xFF6F6F6F),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Intensity slider (custom tick-line design) ────────────────────────────────

class _IntensitySlider extends StatefulWidget {
  final double value;
  final bool enabled;
  final void Function(double) onChanged;

  const _IntensitySlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_IntensitySlider> createState() => _IntensitySliderState();
}

class _IntensitySliderState extends State<_IntensitySlider> {
  static const _steps = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

  // Visual-only handle position while a drag is in progress. Each real
  // brightness command makes the fan's firmware beep (SetBuzzer on every
  // accepted CoolLight frame), so sending one per level crossed mid-drag
  // turned a single scrub into a burst of beeps. A drag now only repaints
  // locally as the finger moves and sends exactly one command — the final
  // level — on release, matching the "one gesture, one command" beep a tap
  // already produces. Null when no drag is in progress (display = widget.value).
  double? _dragValue;

  // On release _dragValue is NOT cleared immediately — widget.value (poll
  // truth) only catches up once the fan's echo arrives, ~100 ms later, so
  // clearing right away made the handle visibly snap back to the stale old
  // position for a frame before jumping forward again. Keep showing the
  // dragged-to position until didUpdateWidget below sees the real value
  // arrive, with this as a safety net in case it never does (dropped write).
  Timer? _dragConfirmTimeout;

  double _nearest(double x) =>
      _steps.reduce((a, b) => (x - a).abs() <= (x - b).abs() ? a : b);

  double _snap(double localX, double width) =>
      _nearest((localX / width).clamp(0.0, 1.0));

  // A tap jumps straight to a level — one deliberate action, sent immediately.
  void _tap(double localX, double width) {
    if (!widget.enabled) return;
    final snapped = _snap(localX, width);
    if (snapped != widget.value) {
      unawaited(HapticFeedback.selectionClick());
      widget.onChanged(snapped);
    }
  }

  void _dragUpdate(double localX, double width) {
    if (!widget.enabled) return;
    final snapped = _snap(localX, width);
    if (snapped != _dragValue) {
      unawaited(HapticFeedback.selectionClick());
      setState(() => _dragValue = snapped);
    }
  }

  void _dragEnd() {
    final v = _dragValue;
    if (v == null) return;
    if (widget.enabled && v != widget.value) {
      widget.onChanged(v);
      // Hold the dragged-to position on screen — see _dragValue doc comment —
      // until the real value arrives (didUpdateWidget) or this fires first.
      _dragConfirmTimeout?.cancel();
      _dragConfirmTimeout = Timer(const Duration(seconds: 3), _clearDragOverride);
    } else {
      _clearDragOverride();
    }
  }

  // The gesture arena can cancel a recognized drag (e.g. a scroll ancestor
  // steals it) — just snap the handle back, no command was promised yet.
  void _dragCancel() => _clearDragOverride();

  void _clearDragOverride() {
    _dragConfirmTimeout?.cancel();
    _dragConfirmTimeout = null;
    if (_dragValue != null) setState(() => _dragValue = null);
  }

  @override
  void didUpdateWidget(covariant _IntensitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The fan's echo (or the next poll tick) landed and matches what this
    // drag sent — safe to hand the display back to widget.value now, with
    // no visible jump since they're equal.
    if (_dragValue != null && widget.value == _dragValue) {
      _clearDragOverride();
    }
  }

  @override
  void dispose() {
    _dragConfirmTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = _dragValue ?? widget.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: kCardElev,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: LayoutBuilder(
        builder: (_, box) {
          final w = box.maxWidth;
          return Semantics(
            slider: true,
            value: '${(displayValue * 100).round()}%',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _tap(d.localPosition.dx, w),
              onHorizontalDragUpdate: (d) => _dragUpdate(d.localPosition.dx, w),
              onHorizontalDragEnd: (_) => _dragEnd(),
              onHorizontalDragCancel: _dragCancel,
              child: CustomPaint(
                size: Size(w, 50),
                painter: _TickPainter(
                  value: displayValue,
                  enabled: widget.enabled,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  final double value;
  final bool enabled;

  static const _steps  = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const _labels = ['0', '20', '40', '60', '80', '100'];

  static const _kDimText = kTextDim;
  static const _kLitText = kText;

  // Pre-laid painters for dim and lit variants — avoids TextPainter.layout()
  // inside paint(), which executes on every frame during slider drags.
  final List<TextPainter> _tpsDim;
  final List<TextPainter> _tpsLit;

  static List<TextPainter> _makeTps(Color color) => List.unmodifiable(
    _labels.map((l) => TextPainter(
      text: TextSpan(
        text: l,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()),
  );

  _TickPainter({required this.value, required this.enabled})
      : _tpsDim = _makeTps(_kDimText),
        _tpsLit = _makeTps(_kLitText);

  @override
  void paint(Canvas canvas, Size size) {
    const trackY   = 14.0;
    const handleR  =  6.0;
    const tickHalf =  5.0;
    const labelTop = 26.0;

    const kInactive = Color(0x28FFFFFF);

    final active = enabled ? kYellow : kYellow.withAlpha(0x50);
    final inactive = kInactive;

    // Full track
    canvas.drawLine(
      const Offset(0, trackY), Offset(size.width, trackY),
      Paint()..color = inactive..strokeWidth = 1.5..strokeCap = StrokeCap.round,
    );
    // Active fill up to handle position
    if (value > 0) {
      canvas.drawLine(
        const Offset(0, trackY), Offset(size.width * value, trackY),
        Paint()..color = active..strokeWidth = 1.5..strokeCap = StrokeCap.round,
      );
    }

    for (int i = 0; i < _steps.length; i++) {
      final x        = size.width * _steps[i];
      final isHandle = _steps[i] == value;
      final isPassed = _steps[i] < value;

      // Handle dot or tick mark
      if (isHandle) {
        canvas.drawCircle(
          Offset(x, trackY), handleR,
          Paint()..color = active..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawLine(
          Offset(x, trackY - tickHalf), Offset(x, trackY + tickHalf),
          Paint()
            ..color = isPassed ? active : inactive
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }

      final tp = (isHandle && enabled) ? _tpsLit[i] : _tpsDim[i];
      final lx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, labelTop));
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.value != value || old.enabled != enabled;
}

// ── Brightness glyph (CoolLight header icon) ──────────────────────────────────
// One icon, six states mirroring the slider steps: 0.0 → a crossed "off" circle,
// then 0.2‑1.0 → a filled sun that grows disc + rays from small to XL.

class _BrightnessGlyphPainter extends CustomPainter {
  final double value; // 0.0‑1.0, matching brightnessValue
  final Color color;

  const _BrightnessGlyphPainter({required this.value, required this.color});

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Level 0 — light off / zero brightness: circle with a diagonal slash.
    if (value <= 0.001) {
      const r = 5.0;
      canvas.drawCircle(c, r, stroke);
      canvas.drawLine(
        c + const Offset(-6.4, -6.4), c + const Offset(6.4, 6.4), stroke,
      );
      return;
    }

    // Levels 1‑5 — sun, scaled by how far past the first step we are.
    // Low end: small hub, rays are detached dots at a wide gap. As brightness
    // rises the hub grows and rays lengthen — but hub, gap and ray length are
    // Hub, gap and ray length all step evenly across the five levels so no one
    // jump stands out; the two extra rays land only at the very top (100%).
    final t = ((value - 0.2) / 0.8).clamp(0.0, 1.0);
    final discR  = _lerp(2.3, 4.2, t);
    final gap    = _lerp(2.8, 1.7, t);
    final rayLen = _lerp(0.0, 2.8, t);
    final rayW   = _lerp(2.0, 2.2, t);
    final inner  = discR + gap;

    final rayCount = t >= 0.95 ? 10 : 8; // fuller sunburst at 100% only

    canvas.drawCircle(c, discR, Paint()..color = color..style = PaintingStyle.fill);

    final rayPaint = Paint()
      ..color = color
      ..strokeWidth = rayW
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < rayCount; i++) {
      final a = -math.pi / 2 + i * (2 * math.pi / rayCount);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * inner, c + dir * (inner + rayLen), rayPaint);
    }
  }

  @override
  bool shouldRepaint(_BrightnessGlyphPainter old) =>
      old.value != value || old.color != color;
}
