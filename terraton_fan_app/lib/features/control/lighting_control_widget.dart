// lib/features/control/lighting_control_widget.dart
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: icon + label + ON/OFF toggle
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                  ),
                ),
                child: const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 22),
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
              // ON / OFF segmented toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToggleBtn(
                      label: 'ON',
                      active: isLightOn,
                      isLeft: true,
                      enabled: enabled,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onLightOn();
                      },
                    ),
                    _ToggleBtn(
                      label: 'OFF',
                      active: !isLightOn,
                      isLeft: false,
                      enabled: enabled,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onLightOff();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // WARM ←——— slider ———→ COOL
          Row(
            children: [
              Text(
                'WARM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                    activeTrackColor: Color.lerp(
                      const Color(0xFFF97316),
                      const Color(0xFF60A5FA),
                      colorTempValue,
                    ),
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: Color.lerp(
                      const Color(0xFFF97316),
                      const Color(0xFF60A5FA),
                      colorTempValue,
                    ),
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
              ),
              Text(
                'COOL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool isLeft;
  final bool enabled;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.isLeft,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.horizontal(
      left: isLeft ? const Radius.circular(7) : Radius.zero,
      right: !isLeft ? const Radius.circular(7) : Radius.zero,
    );
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active
                ? Colors.white
                : (enabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }
}
