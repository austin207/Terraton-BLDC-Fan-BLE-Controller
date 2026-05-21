// lib/features/control/lighting_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class LightingControlWidget extends StatelessWidget {
  final bool enabled;
  final bool isLightOn;
  final double colorTempValue; // 0.0 = warm, 1.0 = cool
  final VoidCallback onLightOn;
  final VoidCallback onLightOff;
  final void Function(double) onColorTemp;

  const LightingControlWidget({
    super.key,
    required this.enabled,
    required this.isLightOn,
    required this.colorTempValue,
    required this.onLightOn,
    required this.onLightOff,
    required this.onColorTemp,
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

          // ── Colour temperature: WARM | NEUTRAL | COOL ──────────────────────
          Opacity(
            opacity: enabled && isLightOn ? 1.0 : 0.4,
            child: Row(
              children: [
                Expanded(child: _TempBtn(label: 'Warm', isActive: colorTempValue < 0.33 && isLightOn, color: const Color(0xFFE6B85C), onTap: enabled && isLightOn ? () => onColorTemp(0.0) : null)),
                const SizedBox(width: 8),
                Expanded(child: _TempBtn(label: 'Neutral', isActive: colorTempValue >= 0.33 && colorTempValue < 0.67 && isLightOn, color: const Color(0xFFCFCFCF), onTap: enabled && isLightOn ? () => onColorTemp(0.5) : null)),
                const SizedBox(width: 8),
                Expanded(child: _TempBtn(label: 'Cool', isActive: colorTempValue >= 0.67 && isLightOn, color: const Color(0xFFDDEEFF), onTap: enabled && isLightOn ? () => onColorTemp(1.0) : null)),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Intensity slider ────────────────────────────────────────────────
          Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: _IntensitySlider(
              value: isLightOn ? colorTempValue : 0.0,
              enabled: enabled && isLightOn,
              onChanged: (v) {
                unawaited(HapticFeedback.selectionClick());
                onColorTemp(v);
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
                    boxShadow: [BoxShadow(color: kYellowGlow, blurRadius: 8)],
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

// ── Intensity slider ──────────────────────────────────────────────────────────

class _IntensitySlider extends StatelessWidget {
  final double value;
  final bool enabled;
  final void Function(double) onChanged;

  const _IntensitySlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: kCardElev,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 18, color: value > 0 && enabled ? kYellow : kTextMut),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: kYellow,
                    inactiveTrackColor: const Color(0x14FFFFFF),
                    thumbColor: kYellow,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                    overlayColor: kYellow.withAlpha(40),
                  ),
                  child: Slider(
                    value: value,
                    min: 0, max: 1,
                    onChanged: enabled ? onChanged : null,
                    semanticFormatterCallback: (_) =>
                        'Light intensity ${(value * 100).round()}%',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.wb_sunny_rounded, size: 22, color: value > 0.5 && enabled ? kYellow : kTextMut),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [0, 25, 50, 75, 100].map((p) => Text(
              '$p',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9, fontWeight: FontWeight.w600,
                color: p / 100 <= value && enabled ? kText : kTextDim,
                letterSpacing: 0.8,
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
