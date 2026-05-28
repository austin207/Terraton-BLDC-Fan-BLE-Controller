// test/widget/qr_scan_screen_test.dart
//
// QrScanScreen smoke tests — verify the screen builds and shows expected UI.
// Camera and QR detection are not exercised.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/features/onboarding/qr_scan_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockFanRepo extends Mock implements FanRepository {}

Widget _buildScreen(_MockFanRepo repo) {
  final router = GoRouter(
    initialLocation: AppRoutes.scanQr,
    routes: [
      GoRoute(path: AppRoutes.scanQr,  builder: (_, __) => const QrScanScreen()),
      GoRoute(path: AppRoutes.nameFan, builder: (_, __) => const Scaffold(body: Text('Name Fan'))),
      GoRoute(path: AppRoutes.control, builder: (_, __) => const Scaffold(body: Text('Control'))),
    ],
  );
  return ProviderScope(
    overrides: [
      fanRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late _MockFanRepo repo;

  setUpAll(() async {
    await CommandLoader.load();
    registerFallbackValue(FanDevice());
  });

  setUp(() {
    repo = _MockFanRepo();
    when(() => repo.getAllFans()).thenReturn([]);
    when(() => repo.saveFan(any())).thenAnswer((_) async {});
  });

  group('QrScanScreen — rendering', () {
    testWidgets('shows "Scan Fan QR Code" title', (tester) async {
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();

      expect(find.text('Scan Fan QR Code'), findsOneWidget);
    });

    testWidgets('shows camera placeholder when permission denied', (tester) async {
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();

      expect(find.text('Camera access required'), findsOneWidget);
    });
  });
}
