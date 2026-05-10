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
      children: ['OFF', '2H', '4H', '8H'].map((label) {
        final isActive = label == activeLabel;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              selected: isActive,
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        onTimer(label.toLowerCase());
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 42,
                  decoration: BoxDecoration(
                    color: isActive ? kPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive ? kPrimary : const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                    boxShadow: isActive
                        ? [BoxShadow(color: kPrimary.withAlpha(40), blurRadius: 8, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? Colors.white
                            : (enabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ),
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
