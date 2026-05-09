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

  @override
  Widget build(BuildContext context) {
    return _ButtonRow(
      items: const ['NATURE', 'SMART', 'REVERSE'],
      activeKey: activeMode?.toUpperCase(),
      enabled: enabled,
      onSelect: (k) {
        HapticFeedback.lightImpact();
        onMode(k.toLowerCase());
      },
    );
  }
}

class _ButtonRow extends StatelessWidget {
  final List<String> items;
  final String? activeKey;
  final bool enabled;
  final void Function(String) onSelect;

  const _ButtonRow({
    required this.items,
    required this.activeKey,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items.map((k) {
        final isActive = k == activeKey;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            selected: isActive,
            child: OutlinedButton(
              onPressed: enabled ? () => onSelect(k) : null,
              style: OutlinedButton.styleFrom(
                backgroundColor: isActive ? kPrimary : null,
                foregroundColor: isActive ? Colors.white : null,
                side: const BorderSide(color: kPrimary),
              ),
              child: Text(k),
            ),
          ),
        );
      }).toList(),
    );
  }
}
