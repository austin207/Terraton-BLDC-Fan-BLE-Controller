// test/widget/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/features/home/home_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockFanRepo      extends Mock implements FanRepository {}
class _MockUsageLogRepo extends Mock implements UsageLogRepository {}

// Minimal UserNameNotifier that avoids file I/O.
class _FakeUserNameNotifier extends UserNameNotifier {
  @override
  Future<String> build() async => 'Test';
  @override
  Future<void> save(String name) async { state = AsyncData(name); }
}

Widget _buildScreen(_MockFanRepo fanRepo, _MockUsageLogRepo logRepo) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
      GoRoute(path: AppRoutes.fans, builder: (_, __) => const Scaffold(body: Text('Fans Screen'))),
      GoRoute(path: AppRoutes.settings, builder: (_, __) => const Scaffold(body: Text('Settings'))),
      GoRoute(path: AppRoutes.scanBle, builder: (_, __) => const Scaffold(body: Text('BLE Scan'))),
      GoRoute(path: AppRoutes.scanQr,  builder: (_, __) => const Scaffold(body: Text('QR Scan'))),
      GoRoute(path: AppRoutes.userManual, builder: (_, __) => const Scaffold(body: Text('Manual'))),
      GoRoute(
        path: AppRoutes.control,
        redirect: (_, state) => state.extra == null ? AppRoutes.home : null,
        builder: (_, state) => Scaffold(body: Text('Control:${(state.extra! as FanDevice).nickname}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      userNameProvider.overrideWith(() => _FakeUserNameNotifier()),
      savedFansProvider.overrideWith((ref) async => []),
      fanRepositoryProvider.overrideWithValue(fanRepo),
      usageLogRepositoryProvider.overrideWithValue(logRepo),
      packageInfoProvider.overrideWith((ref) async => PackageInfo(
        appName: 'Terraton', packageName: 'com.terraton.fan',
        version: '1.0.0', buildNumber: '1',
      )),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    registerFallbackValue(FanState());
    registerFallbackValue(FanDevice());
    registerFallbackValue(UsageLog(
      deviceId: '', startTime: DateTime(0), durationSecs: 0, gear: 0, watts: 0,
    ));
    registerFallbackValue(DateTime.now());
  });

  late _MockFanRepo      fanRepo;
  late _MockUsageLogRepo logRepo;

  setUp(() {
    fanRepo = _MockFanRepo();
    logRepo = _MockUsageLogRepo();

    when(() => fanRepo.getState(any())).thenReturn(FanState());
    when(() => fanRepo.getAllFans()).thenReturn([]);
    when(() => fanRepo.saveState(any())).thenAnswer((_) async {});
    when(() => fanRepo.saveFan(any())).thenAnswer((_) async {});
    when(() => fanRepo.updateMac(any(), any())).thenAnswer((_) async {});
    when(() => fanRepo.renameFan(any(), any())).thenAnswer((_) async {});
    when(() => fanRepo.deleteFan(any())).thenAnswer((_) async {});

    when(() => logRepo.getLogsInRange(any(), any())).thenReturn([]);
    when(() => logRepo.getLogsForDevice(any(), any(), any())).thenReturn([]);
    when(() => logRepo.allDeviceIds()).thenReturn([]);
    when(() => logRepo.addLog(any())).thenReturn(null);
    when(() => logRepo.pruneBefore(any())).thenReturn(null);
  });

  group('HomeScreen — rendering', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('home tab is active by default — shows Fans tile', (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      // _HomeTab renders a "Fans" device tile and "0 paired" subtitle.
      expect(find.text('Fans'), findsOneWidget);
    });

    testWidgets('bottom nav shows all three tab icons', (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      // _BottomNav renders one icon per tab regardless of which is active.
      expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget); // Analytics
      expect(find.byIcon(Icons.home_rounded),      findsOneWidget); // Home
      expect(find.byIcon(Icons.settings_rounded),  findsOneWidget); // Settings
    });
  });

  group('HomeScreen — tab switching', () {
    // The active _BottomNav pill shows a Text label; inactive tabs show only
    // an icon.  Tap an icon to activate its tab, then assert the Text label
    // for that tab appears (and the previous one disappears).

    testWidgets('tapping Analytics icon switches to Analytics tab',
        (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      // Home is active by default — "Home" label is visible in the nav pill.
      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bar_chart_rounded));
      await tester.pumpAndSettle();

      // Analytics is now active — its label appears.
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('tapping Settings icon switches to Settings tab',
        (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('home tab shows "Home" label by default', (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      // The Home pill is active — its text label is rendered.
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('switching tabs then back to Home restores Home label', (tester) async {
      await tester.pumpWidget(_buildScreen(fanRepo, logRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bar_chart_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.home_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });
  });
}
