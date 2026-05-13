// test/widget/ble_permission_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/features/permission/ble_permission_screen.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

// ── Permission channel mock helpers ───────────────────────────────────────────
// permission_handler 11.x uses this method channel to resolve permissions.
// Status integer values: denied=0, granted=1, restricted=2, limited=3, permanentlyDenied=4

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
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

// ── Tests ───────────────────────────────────────────────────────────────────
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  tearDown(_clearPermissionMock);

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
      expect(find.text('Requesting…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('BlePermissionScreen — grant flow', () {
    testWidgets('shows loading indicator while permissions are in-flight',
        (tester) async {
      final completer = Completer<Map<int, int>>();
      _mockPermissionsInFlight(completer);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pump(); // trigger setState(_loading = true)

      expect(find.text('Requesting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Grant Permissions'), findsNothing);

      // Resolve so the stream doesn't leak after the test.
      completer.complete({});
      await tester.pumpAndSettle();
    });

    testWidgets('navigates to home when all permissions granted', (tester) async {
      _mockPermissions(1); // granted
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Permissions'));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
