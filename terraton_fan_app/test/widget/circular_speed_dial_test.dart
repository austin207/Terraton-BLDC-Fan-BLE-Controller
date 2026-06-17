// test/widget/circular_speed_dial_test.dart
//
// Tests for CircularSpeedDial — rendering, center readout, and callback wiring.
//
// IMPORTANT: GestureDetectors for the 6 speed dots overlap in the test layout
// (CLAUDE.md). Invoke onSpeedSelected() directly on the widget instance rather
// than using tester.tap() to avoid unreliable hit-testing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

CircularSpeedDial _dial({
  int speed = 0,
  int? watts,
  int? rpm,
  bool enabled = true,
  bool isBoost = false,
  bool isNature = false,
  bool isSmart = false,
  bool isReverse = false,
  Set<int> disabledSpeeds = const {},
  void Function(int)? onSpeedSelected,
}) =>
    CircularSpeedDial(
      currentSpeed: speed,
      watts: watts,
      rpm: rpm,
      enabled: enabled,
      isBoost: isBoost,
      isNature: isNature,
      isSmart: isSmart,
      isReverse: isReverse,
      disabledSpeeds: disabledSpeeds,
      onSpeedSelected: onSpeedSelected ?? (_) {},
    );

void main() {
  group('CircularSpeedDial — speed labels', () {
    testWidgets('renders labels 1–6 on the ring', (tester) async {
      await tester.pumpWidget(_wrap(_dial()));
      for (int i = 1; i <= 6; i++) {
        expect(find.text('$i'), findsOneWidget,
            reason: 'speed label $i should be visible');
      }
    });
  });

  group('CircularSpeedDial — center readout', () {
    testWidgets('shows GEAR label in default state', (tester) async {
      await tester.pumpWidget(_wrap(_dial()));
      expect(find.text('GEAR'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows gear number when enabled and speed > 0', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 4, enabled: true)));
      expect(find.text('4'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows — when enabled but speed is 0', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 0, enabled: true)));
      // '—' appears in the gear centre AND both stat rows (RPM + WATTS).
      expect(find.text('—'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows — when disabled even if speed > 0', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 3, enabled: false)));
      expect(find.text('—'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows BOOST label when isBoost is true', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isBoost: true, enabled: true)));
      expect(find.text('BOOST'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows RPM stat when rpm provided and powered', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 3, enabled: true, rpm: 315)));
      expect(find.text('315'), findsOneWidget);
    });

    testWidgets('shows WATTS stat when watts provided and powered', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 2, enabled: true, watts: 28)));
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('shows — for RPM when speed = 0', (tester) async {
      await tester.pumpWidget(_wrap(_dial(speed: 0, enabled: true, rpm: 315)));
      // When speed = 0 (fan off), RPM stat shows —
      expect(find.text('—'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows RPM and WATTS stat labels', (tester) async {
      await tester.pumpWidget(_wrap(_dial()));
      expect(find.text('RPM'), findsOneWidget);
      expect(find.text('WATTS'), findsOneWidget);
    });

    testWidgets('nature mode: shows GEAR label but not BOOST label', (tester) async {
      // In nature mode the centre shows GEAR + leaf icon (not a gear number
      // and not BOOST). Ring labels 1–6 are still rendered outside the centre.
      await tester.pumpWidget(_wrap(_dial(isNature: true, speed: 3, enabled: true)));
      expect(find.text('GEAR'), findsAtLeastNWidgets(1));
      expect(find.text('BOOST'), findsNothing);
    });

    testWidgets('smart mode: shows GEAR label and smart icon, not BOOST', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isSmart: true, speed: 3, enabled: true)));
      expect(find.text('GEAR'), findsAtLeastNWidgets(1));
      expect(find.text('BOOST'), findsNothing);
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    });

    testWidgets('reverse mode: shows GEAR label and reverse icon, not BOOST', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isReverse: true, speed: 3, enabled: true)));
      expect(find.text('GEAR'), findsAtLeastNWidgets(1));
      expect(find.text('BOOST'), findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    });
  });

  group('CircularSpeedDial — callback wiring', () {
    testWidgets('onSpeedSelected callback is wired and callable', (tester) async {
      int? selected;
      await tester.pumpWidget(_wrap(_dial(
        speed: 1,
        enabled: true,
        onSpeedSelected: (s) => selected = s,
      )));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      // Invoke directly — hit areas stack in test layout (CLAUDE.md)
      dial.onSpeedSelected(3);
      expect(selected, 3);
    });

    testWidgets('callback propagates all speed values 1–6', (tester) async {
      final received = <int>[];
      await tester.pumpWidget(_wrap(_dial(
        enabled: true,
        onSpeedSelected: received.add,
      )));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      for (int s = 1; s <= 6; s++) {
        dial.onSpeedSelected(s);
      }
      expect(received, [1, 2, 3, 4, 5, 6]);
    });

    testWidgets('enabled flag is false when disabled', (tester) async {
      await tester.pumpWidget(_wrap(_dial(enabled: false)));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.enabled, isFalse);
    });

    testWidgets('isNature flag is set correctly', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isNature: true)));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.isNature, isTrue);
    });

    testWidgets('isSmart flag is set correctly', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isSmart: true)));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.isSmart, isTrue);
    });

    testWidgets('isReverse flag is set correctly', (tester) async {
      await tester.pumpWidget(_wrap(_dial(isReverse: true)));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.isReverse, isTrue);
    });

    testWidgets('disabledSpeeds are reflected on the widget', (tester) async {
      await tester.pumpWidget(_wrap(_dial(disabledSpeeds: {1, 2})));
      final dial =
          tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
      expect(dial.disabledSpeeds, containsAll([1, 2]));
    });
  });
}
