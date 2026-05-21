// lib/features/control/timer_control_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class TimerControlWidget extends StatefulWidget {
  final int? activeTimerCode; // 0x02, 0x04, 0x08, null, or 0x00 — all mean OFF
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
  State<TimerControlWidget> createState() => _TimerControlWidgetState();
}

class _TimerControlWidgetState extends State<TimerControlWidget> {
  late String _displayLabel;

  @override
  void initState() {
    super.initState();
    _displayLabel = TimerControlWidget._codeToLabel(widget.activeTimerCode);
  }

  @override
  void didUpdateWidget(TimerControlWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTimerCode != widget.activeTimerCode) {
      setState(() => _displayLabel = TimerControlWidget._codeToLabel(widget.activeTimerCode));
    }
  }

  void _onTap(String label) {
    if (!widget.enabled || label == _displayLabel) return;
    setState(() => _displayLabel = label);
    unawaited(HapticFeedback.lightImpact());
    widget.onTimer(label.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: TimerControlWidget._labels.asMap().entries.map((e) {
        final label    = e.value;
        final isActive = label == _displayLabel;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: e.key < TimerControlWidget._labels.length - 1 ? 8 : 0,
            ),
            child: Semantics(
              button: true,
              label: label == 'OFF' ? 'Timer off' : '$label timer',
              selected: isActive,
              enabled: widget.enabled,
              child: GestureDetector(
                onTap: () => _onTap(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 50,
                  decoration: BoxDecoration(
                    color: isActive ? kYellow : kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isActive ? kYellow : kHairline),
                    boxShadow: isActive
                        ? [BoxShadow(color: kYellow.withAlpha(46), blurRadius: 18, spreadRadius: -4)]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.black : (widget.enabled ? kText : kTextDim),
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
