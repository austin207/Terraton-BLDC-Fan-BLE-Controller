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
    testWidgets('shows "Energy Usage" header', (tester) async {
      // userName is empty in test env → "Your Energy Usage" fallback.
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('Energy Usage'), findsOneWidget);
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
    testWidgets('shows firmware-runtime info message', (tester) async {
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('firmware-reported cumulative runtime'),
        findsOneWidget,
      );
    });

    testWidgets('does not show BY FAN section (section removed)', (tester) async {
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      expect(find.text('BY FAN'), findsNothing);
    });
  });

  group('AnalyticsScreen — with data', () {
    testWidgets('shows "No Runtime Data" when fan has no runtime', (tester) async {
      // FanState() has speed=0, lastRuntimeSecs=null → effPct=0 → "No Runtime Data".
      await tester.pumpWidget(_buildScreen(logs: []));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('No Runtime Data'), findsOneWidget);
    });

    testWidgets('shows 0.000 kWh when no runtime data available', (tester) async {
      // No lastRuntimeSecs → dailyKwh=0 → weekly total=0.000.
      final logs = [_log(watts: 100, durationSecs: 3600, gear: 3)];
      await tester.pumpWidget(_buildScreen(logs: logs));
      await tester.pumpAndSettle();

      expect(find.textContaining('0.000'), findsWidgets);
    });

    testWidgets('BY FAN section is never shown (removed from design)', (tester) async {
      final fans = [_fan('d1', 'Bedroom')];
      final logs = [_log(deviceId: 'd1', watts: 50, durationSecs: 3600)];

      await tester.pumpWidget(_buildScreen(logs: logs, fans: fans));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('BY FAN'), findsNothing);
    });

    testWidgets('derives weekly kWh from firmware runtime — formula test',
        (tester) async {
      // Fan added 7 days ago; 7 h total runtime (1 h/day avg); gear 3 = 10 W.
      // dailyKwh = 10 × (7×3600 / 7) / 3_600_000 = 0.01
      // weekly   = 0.01 × 7 = 0.07  → displayed as '0.070'.
      final fr = _MockFanRepo();
      final lr = _MockLogRepo();
      final now  = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final fan7 = FanDevice()
        ..deviceId  = 'd1'
        ..nickname  = 'Test Fan'
        ..addedAt   = today.subtract(const Duration(days: 7));
      final stateWithRuntime = FanState()
        ..deviceId        = 'd1'
        ..speed           = 3
        ..lastRuntimeSecs = 7 * 3600;

      when(() => fr.getAllFans()).thenReturn([fan7]);
      when(() => fr.getState(any())).thenReturn(stateWithRuntime);
      when(() => lr.getLogsInRange(any(), any())).thenReturn([]);
      when(() => lr.getLogsForDevice(any(), any(), any())).thenReturn([]);
      when(() => lr.allDeviceIds()).thenReturn([]);
      when(() => lr.addLog(any())).thenReturn(null);
      when(() => lr.pruneBefore(any())).thenReturn(null);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          fanRepositoryProvider.overrideWithValue(fr),
          usageLogRepositoryProvider.overrideWithValue(lr),
          savedFansProvider.overrideWith((ref) async => [fan7]),
          connectedFanDeviceIdProvider.overrideWith((ref) => 'd1'),
        ],
        child: const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
      ));
      await tester.pumpAndSettle();

      // Default range is Week → '0.070'.
      expect(find.textContaining('0.070'), findsWidgets);
    });

    testWidgets('shows efficiency percentage when runtime data is present',
        (tester) async {
      // gear 3 = 10 W → effPct = ((85-10)/85*100).round() = 88 → Excellent Efficiency.
      final fr = _MockFanRepo();
      final lr = _MockLogRepo();
      final fan = _fan('d1', 'Test Fan');
      final stateWithRuntime = FanState()
        ..deviceId        = 'd1'
        ..speed           = 3
        ..lastRuntimeSecs = 3600;

      when(() => fr.getAllFans()).thenReturn([fan]);
      when(() => fr.getState(any())).thenReturn(stateWithRuntime);
      when(() => lr.getLogsInRange(any(), any())).thenReturn([]);
      when(() => lr.getLogsForDevice(any(), any(), any())).thenReturn([]);
      when(() => lr.allDeviceIds()).thenReturn([]);
      when(() => lr.addLog(any())).thenReturn(null);
      when(() => lr.pruneBefore(any())).thenReturn(null);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          fanRepositoryProvider.overrideWithValue(fr),
          usageLogRepositoryProvider.overrideWithValue(lr),
          savedFansProvider.overrideWith((ref) async => [fan]),
          connectedFanDeviceIdProvider.overrideWith((ref) => 'd1'),
        ],
        child: const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Excellent Efficiency'), findsOneWidget);
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

  group('AnalyticsScreen — month range dropdown', () {
    testWidgets('dropdown is hidden on Day/Week and shown on Month', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Default range is Week — no month-range pill.
      expect(find.text('1 Month'), findsNothing);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      // Compact pill defaults to "1 Month".
      expect(find.text('1 Month'), findsOneWidget);
    });

    testWidgets('selecting "3 Months" updates the pill without crashing',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      // Open the dropdown menu and pick 3 Months.
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 Months').last);
      await tester.pumpAndSettle();

      expect(find.text('3 Months'), findsOneWidget);
      expect(find.text('1 Month'), findsNothing);
    });
  });
}
