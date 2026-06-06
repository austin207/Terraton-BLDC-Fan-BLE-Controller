// test/widget/router_redirect_test.dart
//
// Tests for GoRouter redirect guards defined in lib/shared/router.dart.
//   • /name-fan without extra   → redirects to /
//   • /control  without extra   → redirects to /
//   • /fan-types                → redirects to /appliance-types
//
// Uses a lightweight test router with the same redirect logic to avoid pulling
// in complex screen widgets (SplashScreen timer, ControlScreen providers, etc.).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

GoRouter _buildRouter() => GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: AppRoutes.applianceTypes,
          builder: (_, __) =>
              const Scaffold(body: Text('appliance-types')),
        ),
        GoRoute(
          path: AppRoutes.fanTypes,
          redirect: (_, __) => AppRoutes.applianceTypes,
        ),
        GoRoute(
          path: AppRoutes.nameFan,
          redirect: (_, state) =>
              state.extra == null ? AppRoutes.home : null,
          builder: (_, state) => Scaffold(
            body: Text('name-fan:${(state.extra! as FanDevice).deviceId}'),
          ),
        ),
        GoRoute(
          path: AppRoutes.control,
          redirect: (_, state) =>
              state.extra == null ? AppRoutes.home : null,
          builder: (_, state) => Scaffold(
            body: Text('control:${(state.extra! as FanDevice).deviceId}'),
          ),
        ),
      ],
    );

FanDevice _fan() => FanDevice()
  ..deviceId = 'TT-001'
  ..macAddress = 'AA:BB:CC:DD:EE:FF'
  ..nickname = 'Test Fan'
  ..model = 'TN-CF-01'
  ..addedAt = DateTime(2026, 1, 1);

void main() {
  group('Redirect guards — null extra', () {
    testWidgets('/name-fan without extra redirects to home', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(AppRoutes.nameFan); // no extra
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.textContaining('name-fan:'), findsNothing);
    });

    testWidgets('/control without extra redirects to home', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(AppRoutes.control); // no extra
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.textContaining('control:'), findsNothing);
    });
  });

  group('Redirect guards — with extra', () {
    testWidgets('/name-fan with FanDevice extra does NOT redirect', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(AppRoutes.nameFan, extra: _fan());
      await tester.pumpAndSettle();

      expect(find.textContaining('name-fan:TT-001'), findsOneWidget);
    });

    testWidgets('/control with FanDevice extra does NOT redirect', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(AppRoutes.control, extra: _fan());
      await tester.pumpAndSettle();

      expect(find.textContaining('control:TT-001'), findsOneWidget);
    });
  });

  group('Legacy /fan-types redirect', () {
    testWidgets('/fan-types redirects to /appliance-types', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(AppRoutes.fanTypes);
      await tester.pumpAndSettle();

      expect(find.text('appliance-types'), findsOneWidget);
    });
  });
}
