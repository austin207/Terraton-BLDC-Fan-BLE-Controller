// test/widget/connection_banner_test.dart
//
// ConnectionLostCard is a pure stateless widget — no providers needed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/connection_banner.dart';

Widget _card({VoidCallback? onRetry, String? connectStatus}) =>
    MaterialApp(
      home: Scaffold(
        body: ConnectionLostCard(
          onRetry: onRetry ?? () {},
          connectStatus: connectStatus,
        ),
      ),
    );

void main() {
  group('ConnectionLostCard — rendering', () {
    testWidgets('shows "Fan is disconnected" heading', (tester) async {
      await tester.pumpWidget(_card());
      expect(find.text('Fan is disconnected'), findsOneWidget);
    });

    testWidgets('shows "Is the fan powered on…" subtitle', (tester) async {
      await tester.pumpWidget(_card());
      expect(find.textContaining('within range'), findsOneWidget);
    });

    testWidgets('shows Reconnect button', (tester) async {
      await tester.pumpWidget(_card());
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('shows bluetooth disabled icon', (tester) async {
      await tester.pumpWidget(_card());
      expect(find.byIcon(Icons.bluetooth_disabled_rounded), findsOneWidget);
    });
  });

  group('ConnectionLostCard — connect status', () {
    testWidgets('does not show status container when connectStatus is null',
        (tester) async {
      await tester.pumpWidget(_card(connectStatus: null));
      // No monospace-style diagnostic text should be present.
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('does not show status container when connectStatus is empty',
        (tester) async {
      await tester.pumpWidget(_card(connectStatus: ''));
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('shows connectStatus text when non-empty', (tester) async {
      await tester.pumpWidget(_card(connectStatus: 'Connecting…'));
      expect(find.text('Connecting…'), findsOneWidget);
    });

    testWidgets('shows "failed" status text when provided', (tester) async {
      await tester.pumpWidget(_card(connectStatus: 'Connection failed: timeout'));
      expect(find.textContaining('failed'), findsOneWidget);
    });
  });

  group('ConnectionLostCard — interaction', () {
    testWidgets('tapping Reconnect calls onRetry', (tester) async {
      var called = false;
      await tester.pumpWidget(_card(onRetry: () => called = true));
      await tester.tap(find.text('Reconnect'));
      expect(called, isTrue);
    });
  });
}
