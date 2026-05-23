// test/widget/ble_scan_screen_test.dart
//
// BleScanScreen smoke tests — verify the screen builds and shows expected UI.
// BLE hardware and scan results are not exercised; BleService is mocked.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart' as app;
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/features/onboarding/ble_scan_screen.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockBleService extends Mock implements BleService {}

Widget _buildScreen(_MockBleService ble) {
  final router = GoRouter(
    initialLocation: AppRoutes.scanBle,
    routes: [
      GoRoute(path: AppRoutes.scanBle,  builder: (_, __) => const BleScanScreen()),
      GoRoute(path: AppRoutes.nameFan,  builder: (_, __) => const Scaffold(body: Text('Name Fan'))),
    ],
  );
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      // savedFansProvider reads fanRepositoryProvider → ObjectBox; stub empty list.
      savedFansProvider.overrideWith((_) async => []),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late _MockBleService ble;

  setUpAll(() async {
    await CommandLoader.load();
    registerFallbackValue(<int>[]);
  });

  setUp(() {
    ble = _MockBleService();
    when(() => ble.scanResultsStream).thenAnswer((_) => const Stream.empty());
    when(() => ble.connectionStateStream).thenAnswer((_) => const Stream.empty());
    when(() => ble.currentState).thenReturn(app.BleConnectionState.disconnected);
    when(() => ble.startScan(timeoutSeconds: any(named: 'timeoutSeconds')))
        .thenAnswer((_) async {});
    when(() => ble.stopScan()).thenAnswer((_) async {});
  });

  group('BleScanScreen — rendering', () {
    testWidgets('shows app bar title "Select Your Fan"', (tester) async {
      await tester.pumpWidget(_buildScreen(ble));
      await tester.pump(); // permission check in addPostFrameCallback

      expect(find.text('Select Your Fan'), findsOneWidget);
    });

    testWidgets('shows brand mark', (tester) async {
      await tester.pumpWidget(_buildScreen(ble));
      await tester.pump();

      // BrandMark renders an Image widget.
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
