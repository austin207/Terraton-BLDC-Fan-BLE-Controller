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
    ('nature',  'Nature',  Icons.air),
    ('smart',   'Smart',   Icons.auto_awesome_outlined),
    ('reverse', 'Reverse', Icons.sync),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _modes.map(((String key, String label, IconData icon) entry) {
        final isActive = activeMode == entry.$1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            selected: isActive,
            child: OutlinedButton.icon(
              onPressed: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onMode(entry.$1);
                    }
                  : null,
              icon: Icon(entry.$3, size: 16),
              label: Text(entry.$2),
              style: OutlinedButton.styleFrom(
                backgroundColor: isActive ? kPrimary : null,
                foregroundColor: isActive ? Colors.white : null,
                side: const BorderSide(color: kPrimary),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
