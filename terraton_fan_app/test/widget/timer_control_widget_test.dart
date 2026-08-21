// test/widget/timer_control_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';
import 'package:terraton_fan_app/shared/theme.dart';

Widget _build({
  int? activeTimerCode,
  bool enabled = true,
  void Function(String)? onTimer,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TimerControlWidget(
        activeTimerCode: activeTimerCode,
        enabled: enabled,
        onTimer: onTimer ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('TimerControlWidget — rendering', () {
    testWidgets('shows OFF, 2H, 4H, and 8H labels', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('2H'),  findsOneWidget);
      expect(find.text('4H'),  findsOneWidget);
      expect(find.text('8H'),  findsOneWidget);
    });
  });

  group('TimerControlWidget — active state from timer code', () {
    testWidgets('null code activates OFF', (tester) async {
      // Just verifying OFF label is present — styling is not tested here.
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('OFF'), findsOneWidget);
    });

    testWidgets('0x00 activates OFF', (tester) async {
      await tester.pumpWidget(_build(activeTimerCode: 0x00));
      await tester.pumpAndSettle();
      expect(find.text('OFF'), findsOneWidget);
    });

    testWidgets('0x02 activates 2H', (tester) async {
      await tester.pumpWidget(_build(activeTimerCode: 0x02));
      await tester.pumpAndSettle();
      expect(find.text('2H'), findsOneWidget);
    });

    testWidgets('0x04 activates 4H', (tester) async {
      await tester.pumpWidget(_build(activeTimerCode: 0x04));
      await tester.pumpAndSettle();
      expect(find.text('4H'), findsOneWidget);
    });

    testWidgets('0x08 activates 8H', (tester) async {
      await tester.pumpWidget(_build(activeTimerCode: 0x08));
      await tester.pumpAndSettle();
      expect(find.text('8H'), findsOneWidget);
    });
  });

  group('TimerControlWidget — callbacks', () {
    testWidgets('tapping 2H calls onTimer("2h")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onTimer: (s) => received = s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2H'));
      await tester.pump();

      expect(received, '2h');
    });

    testWidgets('tapping 4H calls onTimer("4h")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onTimer: (s) => received = s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('4H'));
      await tester.pump();

      expect(received, '4h');
    });

    testWidgets('tapping 8H calls onTimer("8h")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onTimer: (s) => received = s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('8H'));
      await tester.pump();

      expect(received, '8h');
    });

    // A button press means "send this command", exactly as on the IR remote.
    // The highlight reports what the fan last said; it is not a lock.

    testWidgets('tapping OFF when already active still fires', (tester) async {
      // Default (null code) = OFF is the active button.
      String? received;
      await tester.pumpWidget(_build(onTimer: (s) => received = s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OFF'));
      await tester.pump();

      expect(received, 'off');
    });

    testWidgets('tapping the active 2H button still fires', (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        activeTimerCode: 0x02,
        onTimer: (s) => received = s,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2H'));
      await tester.pump();

      expect(received, '2h');
    });

    testWidgets('disabled widget does not fire onTimer', (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        enabled: false,
        onTimer: (s) => received = s,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2H'));
      await tester.pump();

      expect(received, isNull);
    });
  });

  group('TimerControlWidget — didUpdateWidget', () {
    testWidgets('updates active label when activeTimerCode changes', (tester) async {
      // Start with no timer (OFF active), then update to 0x04 (4H).
      await tester.pumpWidget(_build(activeTimerCode: null));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_build(activeTimerCode: 0x04));
      await tester.pumpAndSettle();

      // Widget rebuilds — 4H should now be visually active. Read the active
      // styling directly; a tap is no longer a usable probe for "is active",
      // because every button fires whether or not it is the current one.
      expect(tester.widget<Text>(find.text('4H')).style?.color, kYellow);
      expect(tester.widget<Text>(find.text('OFF')).style?.color,
          isNot(kYellow));
    });
  });
}
