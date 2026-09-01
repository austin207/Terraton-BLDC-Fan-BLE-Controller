// test/widget/mode_control_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';

Widget _build({
  String? activeMode,
  bool isBoost = false,
  bool enabled = true,
  int currentSpeed = 3,   // neutral default — keeps Smart enabled unless a test says otherwise
  void Function(String)? onMode,
  VoidCallback? onBoost,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ModeControlWidget(
        activeMode: activeMode,
        isBoost: isBoost,
        enabled: enabled,
        currentSpeed: currentSpeed,
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

  // Mirrors firmware's own gate — case BOOST's SMART_MODE branch (BLE) and
  // case IRSmartMode (remote) both reject Smart at speed 1/2. The BLE path
  // still echoes a false "Smart set" confirmation when rejected (a firmware
  // inconsistency, not mirrored here), so the app must never let the tap
  // happen in the first place rather than relying on that echo.
  //
  // Deliberately scoped to when the dial is actually SHOWING a plain speed
  // of 1 or 2 — i.e. no other mode chip lit. While Boost/Nature/Reverse is
  // active, `currentSpeed` is a stale pre-mode value (never updated by a
  // 0x04 frame while a mode is running), and firmware already handles Smart
  // engaged from Nature/Reverse on its own (forces a fixed Speed-4 start
  // regardless of the prior speed) — so that staleness must NOT gate Smart.
  group('ModeControlWidget — Smart disabled at speed 1/2', () {
    testWidgets('speed 1 does not fire onMode("smart")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(currentSpeed: 1, onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, isNull);
    });

    testWidgets('speed 2 does not fire onMode("smart")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(currentSpeed: 2, onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, isNull);
    });

    testWidgets('speed 3+ still fires onMode("smart")', (tester) async {
      String? received;
      await tester.pumpWidget(_build(currentSpeed: 3, onMode: (m) => received = m));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, 'smart');
    });

    testWidgets('speed 1/2 does not disable Nature, Reverse, or Boost', (tester) async {
      String? receivedMode;
      var boostCalled = false;
      await tester.pumpWidget(_build(
        currentSpeed: 1,
        onMode: (m) => receivedMode = m,
        onBoost: () => boostCalled = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nature'));
      await tester.pump();
      expect(receivedMode, 'nature');

      receivedMode = null;
      await tester.tap(find.text('Reverse'));
      await tester.pump();
      expect(receivedMode, 'reverse');

      await tester.tap(find.byKey(const ValueKey('boost_button')));
      await tester.pump();
      expect(boostCalled, isTrue);
    });

    testWidgets('a stale speed 1/2 does NOT block Smart while Reverse is active',
        (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        activeMode: 'reverse',
        currentSpeed: 1,   // stale pre-Reverse speed — must not gate Smart here
        onMode: (m) => received = m,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, 'smart');
    });

    testWidgets('a stale speed 1/2 does NOT block Smart while Nature is active',
        (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        activeMode: 'nature',
        currentSpeed: 2,   // stale pre-Nature speed — must not gate Smart here
        onMode: (m) => received = m,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, 'smart');
    });

    testWidgets('a stale speed 1/2 does NOT block Smart while Boost is active',
        (tester) async {
      String? received;
      await tester.pumpWidget(_build(
        isBoost: true,
        currentSpeed: 1,   // stale pre-Boost speed — must not gate Smart here
        onMode: (m) => received = m,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Smart'));
      await tester.pump();

      expect(received, 'smart');
    });
  });
}
