// test/widget/coming_soon_screen_test.dart
//
// Tests for ComingSoonScreen — badge, type name, "Got it" button, navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/features/coming_soon/coming_soon_screen.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

const _type = ApplianceType(
  id: 'ro_filter',
  displayName: 'RO Filter',
  modelPrefix: 'RF',
  iconPath: 'assets/icons/ro_filter.png',
  modelCount: 10,
  controls: [],
);

GoRouter _router({ApplianceType? type}) => GoRouter(
  initialLocation: '/coming-soon',
  routes: [
    GoRoute(
      path: '/coming-soon',
      builder: (_, __) => ComingSoonScreen(applianceType: type),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (_, __) => const Scaffold(body: Text('Home')),
    ),
  ],
);

void main() {
  testWidgets('shows the appliance type display name', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    expect(find.text('RO Filter'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows COMING SOON badge', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets('shows Got it button', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('appBar title shows pluralLabel of the type', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    // pluralLabel = displayName + 's' → "RO Filters"
    expect(find.text('RO Filters'), findsOneWidget);
  });

  testWidgets('null type shows generic "This device" text', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump();
    expect(find.text('This device'), findsAtLeastNWidgets(1));
  });

  testWidgets('null type shows "Coming Soon" in appBar', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pump();
    expect(find.text('Coming Soon'), findsOneWidget);
  });

  testWidgets('tapping Got it navigates to home when nothing to pop', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('body shows descriptive support text', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(type: _type)));
    await tester.pump();
    // Body copy contains the type name
    expect(find.textContaining('RO Filter'), findsAtLeastNWidgets(1));
  });
}
