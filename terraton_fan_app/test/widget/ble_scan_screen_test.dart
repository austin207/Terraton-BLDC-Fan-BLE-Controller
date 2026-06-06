// test/widget/ble_scan_screen_test.dart
//
// BleScanScreen widget tests — rendering and scan-result behaviour.
// BleService is mocked. The flutter_blue_plus platform interface is stubbed
// to report BluetoothAdapterState.on so _startScan() is not short-circuited.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart' as app;
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/features/onboarding/ble_scan_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockBleService extends Mock implements BleService {}

// ── flutter_blue_plus platform stub ──────────────────────────────────────────
// Overrides getAdapterState to return "on" so BleScanScreen._startScan() does
// not bail out at the FlutterBluePlus.adapterStateNow check.
final class _FakeBluePlusPlatform extends FlutterBluePlusPlatform {
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
          BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
}

// ── Permission channel mock ───────────────────────────────────────────────────
// permission_handler 11.x: denied=0, granted=1.
// Mirrors the helper in ble_permission_screen_test.dart.
const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

void _mockPermissionsGranted() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, (call) async {
    switch (call.method) {
      case 'requestPermissions':
        final perms = List<int>.from(call.arguments as List);
        return Map.fromEntries(perms.map((p) => MapEntry(p, 1)));
      case 'checkPermissionStatus':
        return 1; // granted
      default:
        return null;
    }
  });
}

void _clearPermissionMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, null);
}

// ── Widget helpers ────────────────────────────────────────────────────────────

Widget _buildScreen(_MockBleService ble, {List<FanDevice> savedFans = const []}) {
  final router = GoRouter(
    initialLocation: AppRoutes.scanBle,
    routes: [
      GoRoute(path: AppRoutes.scanBle,  builder: (_, __) => const BleScanScreen()),
      GoRoute(path: AppRoutes.nameFan,  builder: (_, __) => const Scaffold(body: Text('Name Fan'))),
      GoRoute(path: AppRoutes.control,  builder: (_, __) => const Scaffold(body: Text('Control Screen'))),
    ],
  );
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      savedFansProvider.overrideWith((_) async => savedFans),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late _MockBleService ble;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    registerFallbackValue(<int>[]);

    // Prime FlutterBluePlus._adapterStateNow = on so adapterStateNow returns
    // BluetoothAdapterState.on throughout all scan screen tests.
    FlutterBluePlusPlatform.instance = _FakeBluePlusPlatform();
    await FlutterBluePlus.adapterState.first;
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

  tearDown(_clearPermissionMock);

  // ── Smoke / rendering ───────────────────────────────────────────────────────

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

  // ── Scan results — already-added fan ───────────────────────────────────────
  // startScan() is kept in-flight via a Completer so the scan screen does not
  // set _timedOut=true before we can push results through the stream.

  group('BleScanScreen — already-paired fan in scan results', () {
    testWidgets(
        'already-paired fan appears with Reconnect badge and navigates to control',
        (tester) async {
      _mockPermissionsGranted();

      final savedFan = FanDevice()
        ..deviceId   = 'AA:BB:CC:DD:EE:FF'
        ..macAddress = 'AA:BB:CC:DD:EE:FF'
        ..nickname   = 'Living Room Fan'
        ..addedAt    = DateTime.now();

      final scanCtrl    = StreamController<List<DiscoveredFan>>();
      final startedScan = Completer<void>();
      when(() => ble.scanResultsStream).thenAnswer((_) => scanCtrl.stream);
      when(() => ble.startScan(timeoutSeconds: any(named: 'timeoutSeconds')))
          .thenAnswer((_) => startedScan.future); // stays in-flight until we complete

      await tester.pumpWidget(_buildScreen(ble, savedFans: [savedFan]));
      await tester.pump(); // postFrameCallback → permissions → _startScan → _sub wired
      await tester.pump(); // savedFansProvider resolves
      await tester.pump(); // any remaining rebuilds

      // Push the already-paired fan while the scan is still in-flight.
      scanCtrl.add([
        const DiscoveredFan(
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Terraton Fan',
            rssi: -65),
      ]);
      await tester.pump(); // _results updated → list rendered

      // Fan appears in the list.
      expect(find.text('Terraton Fan'), findsOneWidget);
      // Shows "Reconnect" (not "Added") — confirms the badge change.
      expect(find.text('Reconnect'), findsOneWidget);
      // No 50 % dimming on the row.
      final dimmedOpacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.5);
      expect(dimmedOpacities, isEmpty);

      // Tapping navigates to the control screen, not name-fan.
      await tester.tap(find.text('Terraton Fan'));
      await tester.pumpAndSettle();
      expect(find.text('Control Screen'), findsOneWidget);
      expect(find.text('Name Fan'), findsNothing);

      startedScan.complete();
      await scanCtrl.close();
    });

    testWidgets(
        'new (un-paired) device shows signal strength and navigates to name-fan',
        (tester) async {
      _mockPermissionsGranted();

      final scanCtrl    = StreamController<List<DiscoveredFan>>();
      final startedScan = Completer<void>();
      when(() => ble.scanResultsStream).thenAnswer((_) => scanCtrl.stream);
      when(() => ble.startScan(timeoutSeconds: any(named: 'timeoutSeconds')))
          .thenAnswer((_) => startedScan.future);

      // No saved fans — empty repository.
      await tester.pumpWidget(_buildScreen(ble));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      scanCtrl.add([
        const DiscoveredFan(
            macAddress: 'FF:EE:DD:CC:BB:AA', name: 'New Fan', rssi: -55),
      ]);
      await tester.pump();

      expect(find.text('New Fan'), findsOneWidget);
      // Signal dBm indicator visible for new devices.
      expect(find.textContaining('dBm'), findsOneWidget);
      // No Reconnect badge for an un-paired device.
      expect(find.text('Reconnect'), findsNothing);

      await tester.tap(find.text('New Fan'));
      await tester.pumpAndSettle();
      expect(find.text('Name Fan'), findsOneWidget);

      startedScan.complete();
      await scanCtrl.close();
    });
  });
}
