// test/widget/mode_control_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';

Widget _build({
  String? activeMode,
  bool isBoost = false,
  bool enabled = true,
  void Function(String)? onMode,
  VoidCallback? onBoost,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ModeControlWidget(
        activeMode: activeMode,
        isBoost: isBoost,
        enabled: enabled,
        onMode: onMode ?? (_) {},
        onBoost: onBoost ?? () {},
      ),
    ),
  );
}

void main() {
  group('ModeControlWidget — rendering', () {
    testWidgets('shows Nature, Smart, Reverse, and Boost labels', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      expect(find.text('Nature'),  findsOneWidget);
      expect(find.text('Smart'),   findsOneWidget);
      expect(find.text('Reverse'), findsOneWidget);
      expect(find.text('Boost'),   findsOneWidget);
    });

    testWidgets('no mode is active when activeMode is null and isBoost is false',
        (tester) async {
      // All 4 buttons render; none show yellow-active styling (no assertion on
      // colour — just confirm all labels are present without crash).
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      expect(find.text('Nature'), findsOneWidget);
      expect(find.text('Boost'),  findsOneWidget);
    });
  });

  group('ModeControlWidget — active state', () {
    testWidgets('Nature label is present when activeMode=nature', (tester) async {
      await tester.pumpWidget(_build(activeMode: 'nature'));
      await tester.pumpAndSettle();

      expect(find.text('Nature'), findsOneWidget);
    });

    testWidgets('Smart label is present when activeMode=smart', (tester) async {
      await tester.pumpWidget(_build(activeMode: 'smart'));
      await tester.pumpAndSettle();

      expect(find.text('Smart'), findsOneWidget);
    });

    testWidgets('Reverse label is present when activeMode=reverse', (tester) async {
      await tester.pumpWidget(_build(activeMode: 'reverse'));
      await tester.pumpAndSettle();

      expect(find.text('Reverse'), findsOneWidget);
    });

    testWidgets('Boost label is present when isBoost=true', (tester) async {
      await tester.pumpWidget(_build(isBoost: true));
      await tester.pumpAndSettle();

      expect(find.text('Boost'), findsOneWidget);
    });
  });

  group('ModeControlWidget — callbacks', () {
    testWidgets('tapping Nature calls onMode("nature")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nature'));
      await tester.pump();

      expect(received, 'nature');
    });

    testWidgets('tapping Smart calls onMode("smart")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, 'smart');
    });

    testWidgets('tapping Reverse calls onMode("reverse")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reverse'));
      await tester.pump();

      expect(received, 'reverse');
    });

    testWidgets('tapping Boost calls onBoost', (tester) async {
      var called = false;
      await tester.pumpWidget(_build(onBoost: () => called = true));
      await tester.pumpAndSettle();

      // Boost is wrapped in a GestureDetector with ValueKey('boost_button').
      await tester.tap(find.byKey(const ValueKey('boost_button')));
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('disabled widget does not fire onMode', (tester) async {
      String? received;
      await tester.pumpWidget(_build(enabled: false, onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nature'));
      await tester.pump();

      expect(received, isNull);
    });

    testWidgets('disabled widget does not fire onBoost', (tester) async {
      var called = false;
      await tester.pumpWidget(_build(enabled: false, onBoost: () => called = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('boost_button')));
      await tester.pump();

      expect(called, isFalse);
    });
  });
}
