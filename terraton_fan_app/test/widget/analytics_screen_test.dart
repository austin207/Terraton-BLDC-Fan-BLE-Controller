// test/widget/analytics_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/features/analytics/analytics_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:mocktail/mocktail.dart';

class _MockFanRepo      extends Mock implements FanRepository {}
class _MockLogRepo      extends Mock implements UsageLogRepository {}

// Builds an AnalyticsScreen with the given log data and optional fan list.
Widget _buildScreen({
  List<UsageLog> logs = const [],
  List<FanDevice> fans = const [],
  _MockFanRepo? fanRepo,
  _MockLogRepo? logRepo,
}) {
  final fr = fanRepo ?? _MockFanRepo();
  final lr = logRepo ?? _MockLogRepo();

  when(() => fr.getAllFans()).thenReturn(fans);
  when(() => fr.getState(any())).thenReturn(FanState());

  when(() => lr.getLogsInRange(any(), any())).thenReturn(logs);
  when(() => lr.getLogsForDevice(any(), any(), any())).thenReturn([]);
  when(() => lr.allDeviceIds()).thenReturn([]);
  when(() => lr.addLog(any())).thenReturn(null);
  when(() => lr.pruneBefore(any())).thenReturn(null);

  return ProviderScope(
    overrides: [
      fanRepositoryProvider.overrideWithValue(fr),
      usageLogRepositoryProvider.overrideWithValue(lr),
      savedFansProvider.overrideWith((ref) async => fans),
    ],
    child: const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
  );
}

FanDevice _fan(String id, String nick) => FanDevice()
  ..deviceId  = id
  ..nickname  = nick
  ..addedAt   = DateTime(2026, 1, 1);

UsageLog _log({
  String deviceId = 'd1',
  int watts = 40,
  int durationSecs = 3600,
  int gear = 3,
}) =>
    UsageLog(
      deviceId: deviceId,
      startTime: DateTime.now().subtract(const Duration(hours: 1)),
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
    );

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

  group('AnalyticsScreen — rendering', () {
    testWidgets('shows "Energy & savings" header', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Energy & savings'), findsOneWidget);
    });

    testWidgets('shows CONSUMED label', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('CONSUMED'), findsOneWidget);
    });

    testWidgets('shows Day / Week / Month range tabs', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Day'),   findsOneWidget);
      expect(find.text('Week'),  findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
    });

    testWidgets('shows EFFICIENCY label', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // EFFICIENCY card is below the default 600 px test viewport.
      // The ListView is the correct scroll target; using Scrollable.last would
      // accidentally pick up the TextField's internal Scrollable.
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('EFFICIENCY'), findsOneWidget);
    });
  });

  group('AnalyticsScreen — empty state', () {
    testWidgets('shows "Start using your fans" when no logs', (tester) async {
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Start using your fans'),
        findsOneWidget,
      );
    });

    testWidgets('does not show BY FAN section when no logs', (tester) async {
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      expect(find.text('BY FAN'), findsNothing);
    });
  });

  group('AnalyticsScreen — with data', () {
    testWidgets('shows "No Data Yet" efficiency label when no logs', (tester) async {
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('No Data Yet'), findsOneWidget);
    });

    testWidgets('shows non-zero kWh when logs have watts and gear', (tester) async {
      // 100 W × 1 h = 0.1 kWh
      final logs = [_log(watts: 100, durationSecs: 3600, gear: 3)];
      await tester.pumpWidget(_buildScreen(logs: logs));
      await tester.pumpAndSettle();

      // kWh value shown as toStringAsFixed(1) → "0.1"
      expect(find.textContaining('0.1'), findsWidgets);
    });

    testWidgets('shows BY FAN section when fans + logs are present', (tester) async {
      final fans = [_fan('d1', 'Bedroom')];
      final logs = [_log(deviceId: 'd1', watts: 50, durationSecs: 3600)];

      await tester.pumpWidget(_buildScreen(logs: logs, fans: fans));
      await tester.pumpAndSettle();

      // BY FAN is below the efficiency card — drag the ListView to scroll it in.
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('BY FAN'), findsOneWidget);
      expect(find.text('Bedroom'), findsWidgets);
    });
  });

  group('AnalyticsScreen — range tabs', () {
    testWidgets('tapping Day tab makes it active (no crash)', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();

      // Screen re-renders without error; Day tab text still present.
      expect(find.text('Day'), findsOneWidget);
    });

    testWidgets('tapping Month tab makes it active (no crash)', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('Month'), findsOneWidget);
    });

    testWidgets('ENERGY COST and UNITS USED cards are visible', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('ENERGY COST'), findsOneWidget);
      expect(find.text('UNITS USED'),  findsOneWidget);
    });
  });
}
