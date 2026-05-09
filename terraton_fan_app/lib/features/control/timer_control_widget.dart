// lib/features/control/timer_control_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terraton_fan_app/shared/theme.dart';

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
      children: ['OFF', '2H', '4H', '8H'].map((label) {
        final isActive = label == activeLabel;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            selected: isActive,
            child: OutlinedButton(
              onPressed: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onTimer(label.toLowerCase());
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                backgroundColor: isActive ? kPrimary : null,
                foregroundColor: isActive ? Colors.white : null,
                side: const BorderSide(color: kPrimary),
              ),
              child: Text(label),
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _codeToLabel(int? code) => switch (code) {
    0x02 => '2H',
    0x04 => '4H',
    0x08 => '8H',
    _    => 'OFF',
  };
}
