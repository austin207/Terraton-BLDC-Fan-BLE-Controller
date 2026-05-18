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
  // Optimistic label: updated immediately on tap so the pill slides without
  // waiting for the BLE round-trip. Reconciled in didUpdateWidget when the
  // confirmed activeTimerCode arrives from the fan.
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
      setState(() {
        _displayLabel = TimerControlWidget._codeToLabel(widget.activeTimerCode);
      });
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
    final activeIndex = TimerControlWidget._labels.indexOf(_displayLabel);

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final segWidth = (constraints.maxWidth - 6) / TimerControlWidget._labels.length;
          return Stack(
            children: [
              // ── Sliding white pill ──────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: 3 + activeIndex * segWidth,
                top: 3,
                bottom: 3,
                width: segWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Labels (above the pill) ─────────────────────────────────
              Row(
                children: TimerControlWidget._labels.asMap().entries.map((e) {
                  final label    = e.value;
                  final isActive = e.key == activeIndex;
                  return Expanded(
                    child: Semantics(
                      button: true,
                      label: label == 'OFF' ? 'Timer off' : '$label timer',
                      selected: isActive,
                      enabled: widget.enabled,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onTap(label),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? kPrimary
                                  : (widget.enabled
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFFCBD5E1)),
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
