// lib/features/control/lighting_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class LightingControlWidget extends StatelessWidget {
  final bool enabled;
  final bool isLightOn;
  final String colorType; // 'warm' | 'neutral' | 'cool'
  final double brightnessValue; // 0.0 = off/dim, 1.0 = full brightness
  final VoidCallback onLightOn;
  final VoidCallback onLightOff;
  final void Function(String) onColorTypeChanged;
  final void Function(double) onBrightness;

  const LightingControlWidget({
    super.key,
    required this.enabled,
    required this.isLightOn,
    required this.colorType,
    required this.brightnessValue,
    required this.onLightOn,
    required this.onLightOff,
    required this.onColorTypeChanged,
    required this.onBrightness,
  });

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
                child: const Icon(Icons.light_mode_rounded, color: kYellow, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Mood Lighting',
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

          // ── Colour type: WARM | NEUTRAL | COOL (independent selection) ────────
          Opacity(
            opacity: enabled && isLightOn ? 1.0 : 0.4,
            child: Row(
              children: [
                Expanded(child: _TempBtn(label: 'Warm',    isActive: colorType == 'warm'    && isLightOn, color: const Color(0xFFE6B85C), onTap: enabled && isLightOn ? () => onColorTypeChanged('warm')    : null)),
                const SizedBox(width: 8),
                Expanded(child: _TempBtn(label: 'Neutral', isActive: colorType == 'neutral' && isLightOn, color: const Color(0xFFCFCFCF), onTap: enabled && isLightOn ? () => onColorTypeChanged('neutral') : null)),
                const SizedBox(width: 8),
                Expanded(child: _TempBtn(label: 'Cool',    isActive: colorType == 'cool'    && isLightOn, color: const Color(0xFFDDEEFF), onTap: enabled && isLightOn ? () => onColorTypeChanged('cool')    : null)),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Brightness slider (independent of colour type) ──────────────────
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
                    color: kYellow,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [const BoxShadow(color: kYellowGlow, blurRadius: 8)],
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
                              color: isActive ? Colors.black : kTextMut,
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

// ── Colour temperature button ─────────────────────────────────────────────────

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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        height: 56,
        decoration: BoxDecoration(
          color: isActive ? color : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color.withAlpha(200) : const Color(0xFF2A2A2A),
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
            color: isActive ? const Color(0xFF1A1A1A) : const Color(0xFF6F6F6F),
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

  double _nearest(double x) =>
      _steps.reduce((a, b) => (x - a).abs() <= (x - b).abs() ? a : b);

  void _pick(double localX, double width) {
    if (!widget.enabled) return;
    final snapped = _nearest((localX / width).clamp(0.0, 1.0));
    if (snapped != widget.value) {
      unawaited(HapticFeedback.selectionClick());
      widget.onChanged(snapped);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            value: '${(widget.value * 100).round()}%',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition.dx, w),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, w),
              child: CustomPaint(
                size: Size(w, 50),
                painter: _TickPainter(
                  value: widget.value,
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

  const _TickPainter({required this.value, required this.enabled});

  @override
  void paint(Canvas canvas, Size size) {
    const trackY   = 14.0;
    const handleR  =  6.0;
    const tickHalf =  5.0;
    const labelTop = 26.0;

    const kYellowC  = Color(0xFFFFEC00);
    const kInactive = Color(0x28FFFFFF);
    const kDimText  = Color(0xFF5C5C58);
    const kLitText  = Color(0xFFF4F4F2);

    final active   = enabled ? kYellowC : const Color(0x50FFEC00);
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

      // Label below tick / handle
      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: (isHandle && enabled) ? kLitText : kDimText,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final lx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, labelTop));
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.value != value || old.enabled != enabled;
}
