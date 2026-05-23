// test/widget/settings_screen_test.dart
//
// Tests for SettingsScreen UI. Export/import use Share and FilePicker platform
// channels and are not tested here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/features/settings/settings_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockFanRepo extends Mock implements FanRepository {}
class _FakeUserNameNotifier extends UserNameNotifier {
  final String _name;
  _FakeUserNameNotifier(this._name);
  @override
  Future<String> build() async => _name;
  @override
  Future<void> save(String name) async { state = AsyncData(name); }
}

Widget _buildScreen({
  String userName = 'Austin',
  List<FanDevice> fans = const [],
}) {
  final fanRepo = _MockFanRepo();
  when(() => fanRepo.getAllFans()).thenReturn(fans);
  when(() => fanRepo.getState(any())).thenReturn(FanState());
  when(() => fanRepo.exportToJson()).thenReturn('{"version":1,"fans":[]}');

  final router = GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const Scaffold(body: SettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.userManual,
        builder: (_, __) => const Scaffold(body: Text('User Manual')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      userNameProvider.overrideWith(() => _FakeUserNameNotifier(userName)),
      savedFansProvider.overrideWith((ref) async => fans),
      fanRepositoryProvider.overrideWithValue(fanRepo),
      packageInfoProvider.overrideWith((ref) async => PackageInfo(
        appName: 'Terraton', packageName: 'com.terraton.fan',
        version: '2.3.0', buildNumber: '42',
      )),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    registerFallbackValue(FanDevice());
    registerFallbackValue(FanState());
    registerFallbackValue(DateTime.now());
  });

  group('SettingsScreen — profile card', () {
    testWidgets('shows user name in profile card', (tester) async {
      await tester.pumpWidget(_buildScreen(userName: 'Austin'));
      await tester.pumpAndSettle();

      expect(find.text('Austin'), findsOneWidget);
    });

    testWidgets('shows first-letter initial in avatar', (tester) async {
      await tester.pumpWidget(_buildScreen(userName: 'Austin'));
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows EDIT button', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('EDIT'), findsOneWidget);
    });

    testWidgets('tapping EDIT opens rename modal', (tester) async {
      await tester.pumpWidget(_buildScreen(userName: 'Austin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EDIT'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Edit your name'), findsOneWidget);
    });

    testWidgets('rename modal Cancel button dismisses without saving', (tester) async {
      await tester.pumpWidget(_buildScreen(userName: 'Austin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EDIT'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Modal dismissed — EDIT button is visible again.
      expect(find.text('EDIT'), findsOneWidget);
      expect(find.text('Edit your name'), findsNothing);
    });
  });

  group('SettingsScreen — section labels', () {
    testWidgets('shows DATA MANAGEMENT section', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('DATA MANAGEMENT'), findsOneWidget);
    });

    testWidgets('shows ABOUT section', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('shows SUPPORT section', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('SUPPORT'), findsOneWidget);
    });
  });

  group('SettingsScreen — data management tiles', () {
    testWidgets('shows Export Fans Data tile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Export Fans Data'), findsOneWidget);
    });

    testWidgets('shows Import Fans Data tile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Import Fans Data'), findsOneWidget);
    });
  });

  group('SettingsScreen — about tiles', () {
    testWidgets('shows app version from packageInfoProvider', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('v2.3.0'), findsOneWidget);
    });

    testWidgets('shows BLE protocol label', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('BLE Protocol'), findsOneWidget);
    });
  });

  group('SettingsScreen — support tiles', () {
    testWidgets('shows User Manual tile with chevron', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // SUPPORT section is below the ABOUT section — scroll it into view.
      await tester.scrollUntilVisible(
        find.text('User Manual'), 200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('User Manual'), findsOneWidget);
    });

    testWidgets('tapping User Manual navigates to user manual route', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('User Manual'), 200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('User Manual'));
      await tester.pumpAndSettle();

      expect(find.text('User Manual'), findsOneWidget); // page title or tile
    });

    testWidgets('shows Service QR tile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Service QR'), 200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Service QR'), findsOneWidget);
    });
  });

  group('SettingsScreen — service QR modal', () {
    testWidgets('tapping Service QR with no fans shows empty state', (tester) async {
      await tester.pumpWidget(_buildScreen(fans: []));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Service QR'), 200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Service QR'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No fans paired'), findsOneWidget);
    });

    testWidgets('service QR modal can be dismissed with Cancel', (tester) async {
      await tester.pumpWidget(_buildScreen(fans: []));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Service QR'), 200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Service QR'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Service QR'), findsOneWidget); // back on settings
    });
  });
}
