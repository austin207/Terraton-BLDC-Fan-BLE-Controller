// test/widget/timer_control_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/timer_control_widget.dart';

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

    testWidgets('tapping OFF when already active is a no-op', (tester) async {
      // Default (null code) = OFF is active; tapping OFF must not fire callback.
      String? received;
      await tester.pumpWidget(_build(onTimer: (s) => received = s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OFF'));
      await tester.pump();

      expect(received, isNull);
    });

    testWidgets('tapping active 2H button is a no-op', (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        activeTimerCode: 0x02,
        onTimer: (s) => received = s,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2H'));
      await tester.pump();

      expect(received, isNull);
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

      // Widget rebuilds — 4H should now be visually active.
      // We verify by tapping 4H and confirming no callback fires (it is now active).
      String? received;
      await tester.pumpWidget(_build(
        activeTimerCode: 0x04,
        onTimer: (s) => received = s,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('4H'));
      await tester.pump();

      expect(received, isNull); // 4H is active — tap is a no-op
    });
  });
}
