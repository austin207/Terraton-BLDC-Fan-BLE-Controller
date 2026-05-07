// lib/features/control/timer_control_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TimerControlWidget extends StatelessWidget {
  final int? activeTimerCode; // 0x02, 0x04, 0x08, or null (OFF)
  final bool enabled;
  final void Function(String action) onTimer;

  const TimerControlWidget({
    super.key,
    required this.activeTimerCode,
    required this.enabled,
    required this.onTimer,
  });

  @override
  Widget build(BuildContext context) {
    final activeLabel = _codeToLabel(activeTimerCode);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['2H', '4H', '8H', 'OFF'].map((label) {
        final isActive = label == activeLabel;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(
            onPressed: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onTimer(label.toLowerCase());
                  }
                : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: isActive ? const Color(0xFF1A56A0) : null,
              foregroundColor: isActive ? Colors.white : null,
              side: const BorderSide(color: Color(0xFF1A56A0)),
            ),
            child: Text(label),
          ),
        );
      }).toList(),
    );
  }

  static String _codeToLabel(int? code) {
    switch (code) {
      case 0x02: return '2H';
      case 0x04: return '4H';
      case 0x08: return '8H';
      default:   return 'OFF';
    }
  }
}
