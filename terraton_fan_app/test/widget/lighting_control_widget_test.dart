// test/widget/lighting_control_widget_test.dart
//
// Tests for LightingControlWidget — label, ON/OFF toggle, colour type buttons,
// brightness slider presence, and disabled-state guard.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/lighting_control_widget.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

LightingControlWidget _widget({
  bool enabled = true,
  bool isLightOn = false,
  String colorType = 'warm',
  double brightness = 0.6,
  VoidCallback? onLightOn,
  VoidCallback? onLightOff,
  void Function(String)? onColorTypeChanged,
  void Function(double)? onBrightness,
}) =>
    LightingControlWidget(
      enabled: enabled,
      isLightOn: isLightOn,
      colorType: colorType,
      brightnessValue: brightness,
      onLightOn: onLightOn ?? () {},
      onLightOff: onLightOff ?? () {},
      onColorTypeChanged: onColorTypeChanged ?? (_) {},
      onBrightness: onBrightness ?? (_) {},
    );

void main() {
  group('LightingControlWidget — labels', () {
    testWidgets('shows Mood Lighting label', (tester) async {
      await tester.pumpWidget(_wrap(_widget()));
      expect(find.text('Mood Lighting'), findsOneWidget);
    });

    testWidgets('shows ON and OFF toggle labels', (tester) async {
      await tester.pumpWidget(_wrap(_widget()));
      expect(find.text('ON'), findsOneWidget);
      expect(find.text('OFF'), findsOneWidget);
    });

    testWidgets('shows Warm, Neutral, Cool colour buttons', (tester) async {
      await tester.pumpWidget(_wrap(_widget()));
      expect(find.text('Warm'), findsOneWidget);
      expect(find.text('Neutral'), findsOneWidget);
      expect(find.text('Cool'), findsOneWidget);
    });
  });

  group('LightingControlWidget — ON/OFF toggle', () {
    testWidgets('tapping ON calls onLightOn', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_widget(
        enabled: true,
        isLightOn: false,
        onLightOn: () => called = true,
      )));
      await tester.tap(find.text('ON'));
      expect(called, isTrue);
    });

    testWidgets('tapping OFF calls onLightOff', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_widget(
        enabled: true,
        isLightOn: true,
        onLightOff: () => called = true,
      )));
      await tester.tap(find.text('OFF'));
      expect(called, isTrue);
    });

    testWidgets('toggle does nothing when !enabled', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_widget(
        enabled: false,
        onLightOn: () => called = true,
        onLightOff: () => called = true,
      )));
      await tester.tap(find.text('ON'));
      await tester.tap(find.text('OFF'));
      expect(called, isFalse);
    });
  });

  group('LightingControlWidget — colour type buttons', () {
    testWidgets('tapping Neutral calls onColorTypeChanged with "neutral"',
        (tester) async {
      String? changed;
      await tester.pumpWidget(_wrap(_widget(
        enabled: true,
        isLightOn: true,
        colorType: 'warm',
        onColorTypeChanged: (t) => changed = t,
      )));
      await tester.tap(find.text('Neutral'));
      expect(changed, 'neutral');
    });

    testWidgets('tapping Cool calls onColorTypeChanged with "cool"',
        (tester) async {
      String? changed;
      await tester.pumpWidget(_wrap(_widget(
        enabled: true,
        isLightOn: true,
        colorType: 'warm',
        onColorTypeChanged: (t) => changed = t,
      )));
      await tester.tap(find.text('Cool'));
      expect(changed, 'cool');
    });

    testWidgets('colour buttons disabled when !enabled', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_widget(
        enabled: false,
        isLightOn: true,
        onColorTypeChanged: (_) => called = true,
      )));
      await tester.tap(find.text('Warm'));
      expect(called, isFalse);
    });

    testWidgets('colour buttons disabled when light is off', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_widget(
        enabled: true,
        isLightOn: false,
        onColorTypeChanged: (_) => called = true,
      )));
      await tester.tap(find.text('Warm'));
      expect(called, isFalse);
    });
  });

  group('LightingControlWidget — brightness slider', () {
    testWidgets('brightness slider semantics widget is present', (tester) async {
      await tester.pumpWidget(_wrap(_widget(enabled: true, isLightOn: true, brightness: 0.6)));
      // The _IntensitySlider sets Semantics(value: '60%') — verify it's in tree
      expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            (w.properties.value?.endsWith('%') ?? false)),
        findsOneWidget,
      );
    });
  });
}
