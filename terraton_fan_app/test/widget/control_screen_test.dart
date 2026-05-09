// test/widget/control_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/features/control/circular_speed_dial.dart';
import 'package:terraton_fan_app/features/control/control_screen.dart';
import 'package:terraton_fan_app/features/control/lighting_control_widget.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

class _MockBle  extends Mock implements BleService {}
class _MockRepo extends Mock implements FanRepository {}

FanDevice _testFan() => FanDevice()
  ..deviceId   = 'TT-001'
  ..macAddress = 'AA:BB:CC:DD:EE:FF'
  ..nickname   = 'Bedroom Fan'
  ..model      = 'Terraton X1'
  ..fwVersion  = '1.0'
  ..addedAt    = DateTime(2026, 1, 1);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    registerFallbackValue(<int>[]);
    registerFallbackValue(FanState());
  });

  late _MockBle  mockBle;
  late _MockRepo mockRepo;
  late StreamController<BleConnectionState> stateCtrl;
  late StreamController<List<int>>          notifyCtrl;

  setUp(() {
    mockBle    = _MockBle();
    mockRepo   = _MockRepo();
    stateCtrl  = StreamController<BleConnectionState>.broadcast();
    notifyCtrl = StreamController<List<int>>.broadcast();

    when(() => mockBle.connectionStateStream)
        .thenAnswer((_) => stateCtrl.stream);
    when(() => mockBle.notifyStream)
        .thenAnswer((_) => notifyCtrl.stream);
    when(() => mockBle.currentState)
        .thenReturn(BleConnectionState.disconnected);
    when(() => mockBle.scanResultsStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockBle.startScan(
              targetMac:      any(named: 'targetMac'),
              timeoutSeconds: any(named: 'timeoutSeconds'),
            ))
        .thenAnswer((_) async {});
    when(() => mockBle.connect())
        .thenAnswer((_) async => 'AA:BB:CC:DD:EE:FF');
    when(() => mockBle.disconnect())
        .thenAnswer((_) async {});
    when(() => mockBle.writeFrame(any()))
        .thenAnswer((_) async {});

    when(() => mockRepo.getState(any()))
        .thenReturn(FanState()..deviceId = 'TT-001');
    when(() => mockRepo.getAllFans()).thenReturn([]);
    when(() => mockRepo.saveState(any())).thenAnswer((_) async {});
    when(() => mockRepo.updateMac(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await stateCtrl.close();
    await notifyCtrl.close();
  });

  Widget buildScreen() => ProviderScope(
        overrides: [
          bleServiceProvider.overrideWithValue(mockBle),
          fanRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp(home: ControlScreen(fan: _testFan())),
      );

  // Pump the screen and emit a connected state.
  // Two extra pumps let stream delivery and StreamProvider rebuild complete.
  Future<void> pumpConnected(WidgetTester tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();       // fire addPostFrameCallback → _connect()
    await tester.pump();       // drain async microtasks from startScan/connect
    stateCtrl.add(BleConnectionState.connected);
    when(() => mockBle.currentState)
        .thenReturn(BleConnectionState.connected);
    await tester.pump();       // StreamProvider delivers event
    await tester.pump();       // widget rebuilds with enabled=true
  }

  // ── Helpers — invoke widget callbacks directly ─────────────────────────────
  // CircularSpeedDial: six GestureDetectors share the same pixel centre, so
  //   tester.tap() hits the overlaid Column instead of an arc segment.
  // Lighting / Boost: layout height exceeds the 600 px test viewport, placing
  //   widgets off-screen. For both cases the frame content (not gesture routing)
  //   is what the PRD requires us to test, so we invoke the callbacks directly.

  // ── Speed dial ─────────────────────────────────────────────────────────────

  group('speed dial', () {
    testWidgets('speed 1 sends correct frame', (tester) async {
      await pumpConnected(tester);

      tester
          .widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(1);
      await tester.pump();

      verify(
        () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x01, 0x0C]),
      ).called(1);
    });

    testWidgets('speed 3 sends correct frame', (tester) async {
      await pumpConnected(tester);

      tester
          .widget<CircularSpeedDial>(find.byType(CircularSpeedDial))
          .onSpeedSelected(3);
      await tester.pump();

      verify(
        () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x04, 0x01, 0x03, 0x0E]),
      ).called(1);
    });
  });

  // ── Boost ──────────────────────────────────────────────────────────────────

  testWidgets('boost sends correct frame', (tester) async {
    await pumpConnected(tester);

    final dial = tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
    expect(dial.enabled, true, reason: 'dial must be enabled in connected state');

    // Invoke the Scaffold-level onPressed directly from the ElevatedButton
    // widget reference (avoids off-screen tap offset issues).
    final boostFinder = find.widgetWithText(ElevatedButton, 'BOOST MODE');
    final boostButton = tester.widget<ElevatedButton>(boostFinder);
    expect(boostButton.onPressed, isNotNull,
        reason: 'BOOST button must be enabled when connected');
    boostButton.onPressed!();
    await tester.pump();

    verify(
      () => mockBle.writeFrame([0x55, 0xAA, 0x06, 0x21, 0x01, 0x01, 0x29]),
    ).called(1);
  });

  // ── Disabled state ─────────────────────────────────────────────────────────

  testWidgets('all controls disabled when disconnected — writeFrame never called',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(); // fire postFrameCallback
    await tester.pump(); // settle; state stream never emits connected

    final dial = tester.widget<CircularSpeedDial>(find.byType(CircularSpeedDial));
    expect(dial.enabled, false);

    final boostButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'BOOST MODE'),
    );
    expect(boostButton.onPressed, isNull);

    verifyNever(() => mockBle.writeFrame(any()));
  });

  // ── Lighting pending ───────────────────────────────────────────────────────

  testWidgets('light ON shows SnackBar and does not call writeFrame',
      (tester) async {
    await pumpConnected(tester);

    // LightingControlWidget may be scrolled off the 600 px test viewport.
    // Invoke onLightOn directly — the contract being tested is the frame
    // (null → SnackBar, no writeFrame call), not the tap geometry.
    final lightWidget = tester.widget<LightingControlWidget>(
      find.byType(LightingControlWidget),
    );
    lightWidget.onLightOn();
    await tester.pump(); // show SnackBar

    expect(
      find.text('Lighting commands pending from Terraton'),
      findsOneWidget,
    );
    verifyNever(() => mockBle.writeFrame(any()));
  });
}
