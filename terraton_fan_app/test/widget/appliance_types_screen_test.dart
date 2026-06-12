// test/widget/appliance_types_screen_test.dart
//
// Tests for ApplianceTypesScreen — type listing, subtitles, and tap navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/features/home/appliance_types_screen.dart';
import 'package:terraton_fan_app/models/appliance.dart';

const _comingSoonType = ApplianceType(
  id: 'ro_filter',
  displayName: 'RO Filter',
  modelPrefix: 'RF',
  iconPath: 'assets/icons/Ceiling fan.png',
  modelCount: 10,
  controls: [],
);

const _comingSoonCat = ApplianceCategory(
  id: 'water_filtration',
  displayName: 'Water Filtration',
  pluralLabel: 'Water Filters',
  iconPath: 'assets/icons/water_filter.png',
  comingSoon: true,
  types: [_comingSoonType],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ApplianceLoader.load();
  });

  GoRouter buildRouter({ApplianceCategory? category}) => GoRouter(
        initialLocation: '/appliance-types',
        routes: [
          GoRoute(
            path: '/appliance-types',
            builder: (_, __) => ApplianceTypesScreen(category: category),
          ),
          GoRoute(
            path: '/fans',
            builder: (_, state) => Scaffold(
              body: Text(
                  'fans:${(state.extra as ApplianceType?)?.id ?? "?"}'),
            ),
          ),
          GoRoute(
            path: '/coming-soon',
            builder: (_, state) => Scaffold(
              body: Text(
                  'coming-soon:${(state.extra as ApplianceType?)?.id ?? "?"}'),
            ),
          ),
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home')),
          ),
        ],
      );

  testWidgets('shows all type display names for fans category', (tester) async {
    final fansCat = ApplianceLoader.categoryById('fans')!;
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: fansCat)));
    await tester.pumpAndSettle();
    for (final type in fansCat.types) {
      expect(find.text(type.displayName), findsOneWidget,
          reason: '${type.displayName} should be listed');
    }
  });

  testWidgets('shows "N models" subtitle for non-comingSoon category',
      (tester) async {
    final fansCat = ApplianceLoader.categoryById('fans')!;
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: fansCat)));
    await tester.pumpAndSettle();
    final firstType = fansCat.types.first;
    expect(find.text('${firstType.modelCount} models'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows "Coming soon" subtitle for comingSoon category',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: _comingSoonCat)));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsWidgets);
  });

  testWidgets('tapping a type in non-comingSoon category navigates to /fans',
      (tester) async {
    final fansCat = ApplianceLoader.categoryById('fans')!;
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: fansCat)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fansCat.types.first.displayName));
    await tester.pumpAndSettle();
    expect(find.textContaining('fans:'), findsOneWidget);
  });

  testWidgets('tapping a type in comingSoon category navigates to /coming-soon',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: _comingSoonCat)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RO Filter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('coming-soon:'), findsOneWidget);
  });

  testWidgets('null category falls back to fans from ApplianceLoader',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pumpAndSettle();
    // Should fall back to fans → shows at least one fan type
    expect(find.text('Ceiling Fan'), findsOneWidget);
  });

  testWidgets('appBar title shows "Select <Category> Type"', (tester) async {
    final fansCat = ApplianceLoader.categoryById('fans')!;
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter(category: fansCat)));
    await tester.pumpAndSettle();
    expect(find.text('Select Fans Type'), findsOneWidget);
  });
}
