// lib/features/control/lighting_control_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LightingControlWidget extends StatelessWidget {
  final bool enabled;
  final double colorTempValue; // 0.0-1.0
  final VoidCallback onLightOn;
  final VoidCallback onLightOff;
  final void Function(double) onColorTemp;

  const LightingControlWidget({
    super.key,
    required this.enabled,
    required this.colorTempValue,
    required this.onLightOn,
    required this.onLightOff,
    required this.onColorTemp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Lighting', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onLightOn();
                    }
                  : null,
              child: const Text('ON'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onLightOff();
                    }
                  : null,
              child: const Text('OFF'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('2300K', style: TextStyle(fontSize: 11, color: Colors.orange)),
            Expanded(
              child: Slider(
                value: colorTempValue,
                min: 0,
                max: 1,
                onChanged: enabled ? onColorTemp : null,
              ),
            ),
            const Text('6500K', style: TextStyle(fontSize: 11, color: Colors.lightBlue)),
          ],
        ),
      ],
    );
  }
}
