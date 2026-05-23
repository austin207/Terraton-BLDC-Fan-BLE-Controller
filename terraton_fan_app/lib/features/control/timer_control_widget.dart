// lib/features/control/timer_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class TimerControlWidget extends StatelessWidget {
  final int? activeTimerCode; // 0x02=2H, 0x04=4H, 0x08=8H; null/0x00 = OFF
  final bool enabled;
  final void Function(String action) onTimer;

  const TimerControlWidget({
    super.key,
    required this.activeTimerCode,
    required this.enabled,
    required this.onTimer,
  });

  static const _labels = ['OFF', '2H', '4H', '8H'];

  static String _codeToLabel(int? code) => switch (code) {
    0x02 => '2H',
    0x04 => '4H',
    0x08 => '8H',
    _    => 'OFF',
  };

  @override
  Widget build(BuildContext context) {
    // Derive display state from the provider-driven prop so the label is always
    // in sync with the canonical fan state — no local shadow that can diverge.
    final displayLabel = _codeToLabel(activeTimerCode);

    return Row(
      children: _labels.asMap().entries.map((e) {
        final label    = e.value;
        final isActive = label == displayLabel;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: e.key < _labels.length - 1 ? 8 : 0,
            ),
            child: Semantics(
              button: true,
              label: label == 'OFF' ? 'Timer off' : '$label timer',
              selected: isActive,
              enabled: enabled,
              child: GestureDetector(
                onTap: !enabled || isActive ? null : () {
                  unawaited(HapticFeedback.lightImpact());
                  onTimer(label.toLowerCase());
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 50,
                  decoration: BoxDecoration(
                    color: isActive ? kYellow.withAlpha(28) : kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isActive ? kYellow.withAlpha(100) : kHairline),
                    boxShadow: isActive
                        ? [BoxShadow(color: kYellow.withAlpha(22), blurRadius: 14, spreadRadius: -4)]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isActive ? kYellow : (enabled ? kText : kTextDim),
                      letterSpacing: 0.06,
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
}
