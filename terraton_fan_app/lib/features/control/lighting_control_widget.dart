// lib/features/control/lighting_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const _warmColor = Color(0xFFF97316); // orange
  static const _coolColor = Color(0xFF60A5FA); // blue

  @override
  Widget build(BuildContext context) {
    final thumbColor = Color.lerp(_warmColor, _coolColor, colorTempValue)!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: sun icon + label + ON/OFF toggle ──────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.light_mode_outlined, color: Color(0xFFF59E0B), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Mood Lighting',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              // Segmented ON / OFF toggle — sliding pill
              _LightToggle(
                isOn: isLightOn,
                enabled: enabled,
                onLightOn: onLightOn,
                onLightOff: onLightOff,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── WARM ←—[gradient track]—→ COOL ───────────────────────────────
          Row(
            children: [
              const Text(
                'WARM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFEA580C),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Gradient track always visible end-to-end
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 5,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_warmColor, Color(0xFFFBBF24), _coolColor],
                            ),
                          ),
                        ),
                      ),
                      // Slider with transparent track — only the thumb shows
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 5,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          disabledActiveTrackColor: Colors.transparent,
                          disabledInactiveTrackColor: Colors.transparent,
                          thumbColor: thumbColor,
                          disabledThumbColor: thumbColor.withAlpha(120),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                          overlayColor: thumbColor.withAlpha(30),
                        ),
                        child: Slider(
                          value: colorTempValue,
                          min: 0,
                          max: 1,
                          semanticFormatterCallback: (_) =>
                              'Colour temperature ${(colorTempValue * 100).round()}%',
                          onChanged: enabled ? onColorTemp : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Text(
                'COOL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    final activeIndex = isOn ? 0 : 1;

    return Container(
      width: 88,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(50),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final segWidth = (constraints.maxWidth - 6) / _labels.length;
          return Stack(
            children: [
              // ── Sliding white pill ────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: 3 + activeIndex * segWidth,
                top: 3,
                bottom: 3,
                width: segWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Labels (above the pill) ───────────────────────────────
              Row(
                children: _labels.asMap().entries.map((e) {
                  final label    = e.value;
                  final isActive = e.key == activeIndex;
                  return Expanded(
                    child: Semantics(
                      button: true,
                      label: '$label light',
                      selected: isActive,
                      enabled: enabled,
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
                              color: isActive
                                  ? kPrimary
                                  : (enabled
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFFCBD5E1)),
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
