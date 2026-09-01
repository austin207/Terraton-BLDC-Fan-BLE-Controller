// test/widget/mode_control_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/mode_control_widget.dart';

const _cf01 = ['nature', 'smart', 'reverse', 'boost'];
const _cf02 = ['led', 'smart', 'reverse', 'boost'];
const _cf03 = ['reverse', 'boost'];

Widget _build({
  List<String> modes = _cf01,
  String? activeMode,
  bool isBoost = false,
  bool ledOn = false,
  bool enabled = true,
  int currentSpeed = 3, // neutral default — keeps Smart enabled unless a test says otherwise
  void Function(String)? onMode,
  VoidCallback? onBoost,
  void Function(bool)? onLed,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ModeControlWidget(
        modes: modes,
        activeMode: activeMode,
        isBoost: isBoost,
        ledOn: ledOn,
        enabled: enabled,
        currentSpeed: currentSpeed,
        onMode: onMode ?? (_) {},
        onBoost: onBoost ?? () {},
        onLed: onLed ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('ModeControlWidget — rendering by remote', () {
    testWidgets('CF-01 shows Nature, Smart, Reverse, and Boost', (tester) async {
      await tester.pumpWidget(_build(modes: _cf01));
      await tester.pumpAndSettle();

      expect(find.text('Nature'),  findsOneWidget);
      expect(find.text('Smart'),   findsOneWidget);
      expect(find.text('Reverse'), findsOneWidget);
      expect(find.text('Boost'),   findsOneWidget);
      expect(find.text('LED'),     findsNothing);
    });

    testWidgets('CF-02 replaces Nature with an LED toggle', (tester) async {
      await tester.pumpWidget(_build(modes: _cf02));
      await tester.pumpAndSettle();

      expect(find.text('LED'),     findsOneWidget);
      expect(find.text('Nature'),  findsNothing);
      expect(find.text('Smart'),   findsOneWidget);
      expect(find.text('Reverse'), findsOneWidget);
      expect(find.text('Boost'),   findsOneWidget);
    });

    testWidgets('CF-03 shows only Reverse and Boost', (tester) async {
      await tester.pumpWidget(_build(modes: _cf03));
      await tester.pumpAndSettle();

      expect(find.text('Reverse'), findsOneWidget);
      expect(find.text('Boost'),   findsOneWidget);
      expect(find.text('Nature'),  findsNothing);
      expect(find.text('Smart'),   findsNothing);
      expect(find.text('LED'),     findsNothing);
    });
  });

  group('ModeControlWidget — active state', () {
    testWidgets('Nature label present when activeMode=nature', (tester) async {
      await tester.pumpWidget(_build(activeMode: 'nature'));
      await tester.pumpAndSettle();
      expect(find.text('Nature'), findsOneWidget);
    });

    testWidgets('Boost label present when isBoost=true', (tester) async {
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

  group('ModeControlWidget — LED toggle (CF-02)', () {
    testWidgets('tapping LED while off calls onLed(true)', (tester) async {
      bool? received;
      await tester.pumpWidget(
          _build(modes: _cf02, ledOn: false, onLed: (v) => received = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('led_button')));
      await tester.pump();
      expect(received, isTrue);
    });

    testWidgets('tapping LED while on calls onLed(false)', (tester) async {
      bool? received;
      await tester.pumpWidget(
          _build(modes: _cf02, ledOn: true, onLed: (v) => received = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('led_button')));
      await tester.pump();
      expect(received, isFalse);
    });

    testWidgets('disabled widget does not fire onLed', (tester) async {
      bool? received;
      await tester.pumpWidget(_build(
          modes: _cf02, enabled: false, onLed: (v) => received = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('led_button')));
      await tester.pump();
      expect(received, isNull);
    });
  });

  // Mirrors firmware's own gate — case BOOST's SMART_MODE branch (BLE) and
  // case IRSmartMode (remote) both reject Smart at speed 1/2. The BLE path
  // still echoes a false "Smart set" confirmation when rejected, so the app
  // must never let the tap happen in the first place rather than relying on
  // that echo.
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
        currentSpeed: 1,
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
        currentSpeed: 2,
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
        currentSpeed: 1,
        onMode: (m) => received = m,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart'));
      await tester.pump();
      expect(received, 'smart');
    });
  });
}
