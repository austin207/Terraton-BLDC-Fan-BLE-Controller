// test/widget/splash_screen_test.dart
//
// Smoke tests for SplashScreen — verifies initial render and version string.
//
// The splash screen sets a 2-second Future.delayed in initState plus an
// infinite AnimationController. Strategy:
// - Mock the permission channel to return "denied" (0) so the timer callback
//   navigates predictably (→ /permission-required).
// - Set AppSettings.firstLaunchOverride to avoid real file I/O in FakeAsync.
// - After assertions, pump 3 seconds to fire the pending timer so the test
//   framework's timer-leak check passes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/features/splash/splash_screen.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

const _permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

GoRouter _splashRouter() => GoRouter(
      initialLocation: AppRoutes.splash,
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (_, __) => const SplashScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: AppRoutes.permissionRequired,
          builder: (_, __) => const Scaffold(body: Text('permission-required')),
        ),
        GoRoute(
          path: AppRoutes.profileSetup,
          builder: (_, __) => const Scaffold(body: Text('profile-setup')),
        ),
      ],
    );

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Terraton Fan',
      packageName: 'com.terraton.fan',
      version: '3.0.0',
      buildNumber: '30',
      buildSignature: '',
      installerStore: null,
    );
    // Return PermissionStatus.denied (0) for all permission checks.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permChannel, (call) async {
      if (call.method == 'checkPermissionStatus') return 0;
      if (call.method == 'requestPermissions') return <int, int>{};
      return null;
    });
    // Avoid real file I/O inside FakeAsync.
    AppSettings.firstLaunchOverride = () async => false;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permChannel, null);
    AppSettings.firstLaunchOverride = null;
  });

  testWidgets('renders without crash (smoke test)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: _splashRouter()),
      ),
    );
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    // Fire the pending 2s timer to avoid test-framework timer-leak failure.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });

  testWidgets('shows SMART BLDC subtitle text', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: _splashRouter()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('SMART BLDC'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });

  testWidgets('shows version from packageInfoProvider after it resolves',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: _splashRouter()),
      ),
    );
    await tester.pump(); // first frame + schedules async
    await tester.pump(); // FutureProvider resolves → rebuild with version
    expect(find.textContaining('3.0.0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
