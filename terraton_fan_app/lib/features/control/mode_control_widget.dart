// lib/features/control/mode_control_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ModeControlWidget extends StatelessWidget {
  final String? activeMode;
  final bool enabled;
  final void Function(String mode) onMode;

  const ModeControlWidget({
    super.key,
    required this.activeMode,
    required this.enabled,
    required this.onMode,
  });

  static const _modes = [
    ('nature',  'Nature',  Icons.air_rounded),
    ('smart',   'Smart',   Icons.auto_awesome_outlined),
    ('reverse', 'Reverse', Icons.sync_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _modes.map(((String key, String label, IconData icon) entry) {
        final isActive = activeMode == entry.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              selected: isActive,
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        onMode(entry.$1);
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.$3,
                        size: 15,
                        color: isActive
                            ? Colors.white
                            : (enabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        entry.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : (enabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
