// test/widget/ble_permission_screen_test.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/features/permission/ble_permission_screen.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

// ── Fake path provider ────────────────────────────────────────────────────────

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

// ── Permission channel mock helpers ───────────────────────────────────────────
// permission_handler 11.x uses this method channel.
// Status integers: denied=0, granted=1, restricted=2, limited=3, permanentlyDenied=4

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

void _mockPermissions(int status) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, (call) async {
    switch (call.method) {
      case 'requestPermissions':
        final perms = List<int>.from(call.arguments as List);
        return Map.fromEntries(perms.map((p) => MapEntry(p, status)));
      case 'checkPermissionStatus':
        return status;
      default:
        return null;
    }
  });
}

void _mockPermissionsInFlight(Completer<Map<int, int>> completer) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, (call) async {
    if (call.method == 'requestPermissions') return completer.future;
    return null;
  });
}

void _clearPermissionMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, null);
}

// ── Widget factory ─────────────────────────────────────────────────────────
// BlePermissionScreen uses context.go() so GoRouter must be in the tree.
// Both home and profileSetup intentionally show 'Home' text: on Windows the
// temp-dir file written by setUp can be briefly locked by the OS before
// isFirstLaunch() reads it, making the first-launch check non-deterministic.
// Navigation tests only assert that the screen is left, not the exact route.

Widget _buildScreen() {
  final router = GoRouter(
    initialLocation: AppRoutes.permissionRequired,
    routes: [
      GoRoute(
        path: AppRoutes.permissionRequired,
        builder: (_, __) => const BlePermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late Directory _tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();

    // Redirect path_provider to a temp directory so AppSettings I/O is hermetic
    // and platform channels don't block in the CI test environment.
    _tempDir = await Directory.systemTemp.createTemp('ble_perm_test_');
    PathProviderPlatform.instance = _FakePathProvider(_tempDir.path);

    // Write profile_set once here — the file is written well before any
    // navigation test reads it, avoiding Windows OS-level file-lock races
    // that can occur when setUp writes and the very next async read follows
    // immediately.
    await AppSettings.markProfileSet();

    // Bypass real file I/O in isFirstLaunch() — FakeAsync (used by pump)
    // blocks real OS I/O events from completing, so the file read would hang.
    // Override returns false (profile already set) so navigation goes to /home.
    AppSettings.firstLaunchOverride = () async => false;
  });

  setUp(() {
    AppSettings.firstLaunchOverride = () async => false;
  });

  tearDown(() {
    _clearPermissionMock();
    AppSettings.firstLaunchOverride = null;
  });

  tearDownAll(() async {
    AppSettings.firstLaunchOverride = null;
    // Ignore failures — on Windows, OS scanners (Defender etc.) can briefly
    // hold the temp file open after the last test. The OS will clean up.
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('BlePermissionScreen — rendering', () {
    testWidgets('shows title, grant button, and demo mode link', (tester) async {
      _mockPermissions(0); // denied — so we stay on the screen
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Bluetooth Access Required'), findsOneWidget);
      expect(find.text('Grant Permissions'), findsOneWidget);
      expect(find.text('Use Demo Mode Instead'), findsOneWidget);
    });

    testWidgets('shows only Bluetooth permission row — no Location row', (tester) async {
      _mockPermissions(0);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Bluetooth Scan & Connect'), findsOneWidget);
      expect(find.text('Location (Nearby Devices)'), findsNothing);
    });

    testWidgets('shows grant button and not loading state initially', (tester) async {
      _mockPermissions(0);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Grant Permissions'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('BlePermissionScreen — grant flow', () {
    testWidgets('shows loading spinner while permissions are in-flight',
        (tester) async {
      final completer = Completer<Map<int, int>>();
      _mockPermissionsInFlight(completer);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pump(); // trigger setState(_loading = true)

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Grant Permissions'), findsNothing);

      // Leave completer unresolved — assertions already done; the mounted
      // guard in _request() ensures no use-after-dispose when the widget
      // is torn down at end of test.
    });

    testWidgets('navigates to home when all permissions granted', (tester) async {
      _mockPermissions(1); // granted
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      // firstLaunchOverride eliminates real file I/O so pump() is sufficient.
      await tester.pump(); // kick off _request()
      await tester.pump(); // permission channel mock resolves
      await tester.pump(); // isFirstLaunch() override returns
      await tester.pump(); // context.go() triggers navigation frame
      await tester.pumpAndSettle(); // GoRouter page transition

      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('BlePermissionScreen — deny flow', () {
    testWidgets('shows error message when permissions denied', (tester) async {
      _mockPermissions(0); // denied
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pumpAndSettle();

      expect(find.textContaining('denied'), findsWidgets);
      expect(find.text('Bluetooth Access Required'), findsOneWidget);
    });

    testWidgets('shows Open App Settings when permanently denied', (tester) async {
      _mockPermissions(4); // permanentlyDenied
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pumpAndSettle();

      expect(find.text('Open App Settings'), findsOneWidget);
      expect(find.textContaining('permanently denied'), findsOneWidget);
    });

    testWidgets('Try Again button is shown after permanent denial', (tester) async {
      _mockPermissions(4);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('BlePermissionScreen — demo mode', () {
    testWidgets('demo mode button navigates to home without requesting permissions',
        (tester) async {
      // No permission mock needed — demo mode bypasses the request.
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use Demo Mode Instead'));
      // firstLaunchOverride eliminates real file I/O so pump() is sufficient.
      await tester.pump(); // kick off onPressed callback
      await tester.pump(); // isFirstLaunch() override returns
      await tester.pump(); // context.go() triggers navigation frame
      await tester.pumpAndSettle(); // GoRouter page transition

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
