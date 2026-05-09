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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wb_sunny_rounded, color: Colors.amber.shade600, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Mood Lighting',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                // ON / OFF segmented buttons
                Row(
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
              ],
            ),
            const SizedBox(height: 14),
            // Colour temperature slider
            Row(
              children: [
                Text('WARM', style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                Expanded(
                  child: Slider(
                    value: colorTempValue,
                    min: 0,
                    max: 1,
                    activeColor: Color.lerp(Colors.orange.shade400, Colors.lightBlue.shade300, colorTempValue),
                    semanticFormatterCallback: (_) =>
                        'Colour temperature ${(colorTempValue * 100).round()}%',
                    onChanged: enabled ? onColorTemp : null,
                  ),
                ),
                Text('COOL', style: TextStyle(fontSize: 11, color: Colors.lightBlue.shade700, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
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
      left: isLeft ? const Radius.circular(8) : Radius.zero,
      right: !isLeft ? const Radius.circular(8) : Radius.zero,
    );
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.grey.shade100,
          borderRadius: radius,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : (enabled ? Colors.grey.shade600 : Colors.grey.shade400),
          ),
        ),
      ),
    );
  }
}
