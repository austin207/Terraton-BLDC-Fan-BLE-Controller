// lib/features/control/mode_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ModeControlWidget extends StatelessWidget {
  final String? activeMode;
  final bool isBoost;
  final bool enabled;
  final void Function(String mode) onMode;
  final VoidCallback onBoost;

  const ModeControlWidget({
    super.key,
    required this.activeMode,
    required this.isBoost,
    required this.enabled,
    required this.onMode,
    required this.onBoost,
  });

  static const _modes = [
    ('nature',  'Nature',  Icons.air_rounded),
    ('smart',   'Smart',   Icons.auto_awesome_outlined),
    ('reverse', 'Reverse', Icons.sync_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 3 mode buttons
        ..._modes.map(((String, String, IconData) entry) {
          final isActive = activeMode == entry.$1 && !isBoost;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ModeBtn(
                icon: entry.$3,
                label: entry.$2,
                isActive: isActive,
                enabled: enabled,
                onTap: () {
                  unawaited(HapticFeedback.lightImpact());
                  onMode(entry.$1);
                },
              ),
            ),
          );
        }),

        // Boost button — 4th column; GestureDetector key required by tests
        Expanded(
          child: Semantics(
            button: true,
            label: 'Boost mode',
            selected: isBoost,
            enabled: enabled,
            child: GestureDetector(
              key: const ValueKey('boost_button'),
              onTap: enabled
                  ? () {
                      unawaited(HapticFeedback.lightImpact());
                      onBoost();
                    }
                  : null,
              child: _ModeBtn(
                icon: Icons.bolt_rounded,
                label: 'Boost',
                isActive: isBoost,
                enabled: enabled,
                onTap: null, // handled by outer GestureDetector
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool enabled;
  final VoidCallback? onTap;

  const _ModeBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        height: 80,
        decoration: BoxDecoration(
          color: isActive ? kYellow : kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? kYellow : kHairline),
          boxShadow: isActive
              ? [BoxShadow(color: kYellow.withAlpha(46), blurRadius: 18, spreadRadius: -4)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon, size: 20,
              color: isActive ? Colors.black : (enabled ? kText : kTextDim),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.black : (enabled ? kText : kTextDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
