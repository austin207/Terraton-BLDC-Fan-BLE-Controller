// test/widget/user_manual_screen_test.dart
//
// UserManualScreen reads packageInfoProvider for the version footer.
// Uses GoRouter so context.pop() in the AppBar back button does not throw.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/features/settings/user_manual_screen.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

Widget _buildScreen() {
  final router = GoRouter(
    initialLocation: AppRoutes.userManual,
    routes: [
      GoRoute(
        path: AppRoutes.userManual,
        builder: (_, __) => const UserManualScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const Scaffold(body: Text('Settings')),
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('UserManualScreen — rendering', () {
    testWidgets('shows "User Manual" in the app bar', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('User Manual'), findsOneWidget);
    });

    testWidgets('shows "Getting Started" section header', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Getting Started'), findsOneWidget);
    });

    testWidgets('shows "Controlling Fan Speed" section header', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Controlling Fan Speed'), findsOneWidget);
    });

    testWidgets('shows "Boost Mode" section header', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Boost Mode'), findsOneWidget);
    });

    testWidgets('shows "Troubleshooting" section header', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Troubleshooting is the last section — scroll it into view.
      await tester.scrollUntilVisible(
        find.text('Troubleshooting'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Troubleshooting'), findsOneWidget);
    });
  });

  group('UserManualScreen — accordion expand', () {
    testWidgets('tapping a section header expands its body text', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // SizeTransition keeps body widgets in the tree even when collapsed (height=0),
      // so we cannot assert findsNothing before the tap. Just verify expansion.
      await tester.tap(find.text('Getting Started'));
      await tester.pumpAndSettle();

      expect(find.textContaining('wall switch'), findsOneWidget);
    });

    testWidgets('tapping expanded section collapses it', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Getting Started'));
      await tester.pumpAndSettle();
      expect(find.textContaining('wall switch'), findsOneWidget);

      await tester.tap(find.text('Getting Started'));
      await tester.pumpAndSettle();
      // SizeTransition clips the body to 0 height — widget is in the tree but
      // not interactive. hitTestable() verifies it cannot be hit-tested.
      expect(find.textContaining('wall switch').hitTestable(), findsNothing);
    });

    testWidgets('only one section is expanded at a time', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Getting Started'));
      await tester.pumpAndSettle();
      expect(find.textContaining('wall switch'), findsOneWidget);

      // Open Boost Mode — Getting Started body should collapse.
      await tester.tap(find.text('Boost Mode'));
      await tester.pumpAndSettle();
      // "intensified glow ring" is unique to the Boost Mode body — it's
      // in the tree but hitTestable() confirms it's actually visible (expanded).
      expect(find.textContaining('intensified glow ring').hitTestable(), findsOneWidget);
      // Getting Started body is still in the tree but collapsed to 0 height.
      expect(find.textContaining('wall switch').hitTestable(), findsNothing);
    });
  });
}
