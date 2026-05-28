// test/widget/fans_list_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/features/home/fans_list_screen.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

class _MockRepo extends Mock implements FanRepository {}

FanDevice _fan(String id, String nick, {String model = 'Terraton X1'}) =>
    FanDevice()
      ..deviceId = id
      ..nickname = nick
      ..model    = model
      ..addedAt  = DateTime(2026, 1, 1);

// Build FansListScreen inside a minimal GoRouter so context.pop() and
// context.push() do not throw a GoRouter-not-in-tree error.
Widget _buildScreen({
  required AsyncValue<List<FanDevice>> fansValue,
  required _MockRepo repo,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.fans,
    routes: [
      GoRoute(path: AppRoutes.fans, builder: (_, __) => const FansListScreen()),
      GoRoute(
        path: AppRoutes.control,
        redirect: (_, state) => state.extra == null ? AppRoutes.fans : null,
        builder: (_, state) =>
            Scaffold(body: Text('Control:${(state.extra! as FanDevice).nickname}')),
      ),
      GoRoute(path: AppRoutes.home,    builder: (_, __) => const Scaffold(body: Text('Home'))),
      GoRoute(path: AppRoutes.scanBle, builder: (_, __) => const Scaffold(body: Text('BLE'))),
      GoRoute(path: AppRoutes.scanQr,  builder: (_, __) => const Scaffold(body: Text('QR'))),
    ],
  );
  return ProviderScope(
    overrides: [
      savedFansProvider.overrideWith(
        (ref) => switch (fansValue) {
          AsyncData(:final value) => Future.value(value),
          _ => Completer<List<FanDevice>>().future, // never resolves → loading state
        },
      ),
      fanRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
    await ApplianceLoader.load();
    registerFallbackValue(FanState());
    registerFallbackValue(FanDevice());
  });

  late _MockRepo mockRepo;

  setUp(() {
    mockRepo = _MockRepo();
    when(() => mockRepo.getState(any())).thenReturn(FanState());
    when(() => mockRepo.saveState(any())).thenAnswer((_) async {});
    when(() => mockRepo.getAllFans()).thenReturn([]);
    when(() => mockRepo.saveFan(any())).thenAnswer((_) async {});
    when(() => mockRepo.renameFan(any(), any())).thenAnswer((_) async {});
    when(() => mockRepo.deleteFan(any())).thenAnswer((_) async {});
    when(() => mockRepo.updateMac(any(), any())).thenAnswer((_) async {});
  });

  // ── Loading ─────────────────────────────────────────────────────────────────

  group('FansListScreen — loading', () {
    testWidgets('shows loading indicator while fans future is pending', (tester) async {
      await tester.pumpWidget(
        _buildScreen(fansValue: const AsyncLoading(), repo: mockRepo),
      );
      await tester.pump(); // one frame — loading state

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ── Empty state ─────────────────────────────────────────────────────────────

  group('FansListScreen — empty state', () {
    testWidgets('shows empty message when no fans paired', (tester) async {
      await tester.pumpWidget(
        _buildScreen(fansValue: const AsyncData([]), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('No fans paired yet.'), findsOneWidget);
      expect(find.text('Tap + to add one.'), findsOneWidget);
    });
  });

  // ── Populated list ──────────────────────────────────────────────────────────

  group('FansListScreen — populated list', () {
    testWidgets('shows each fan nickname', (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('a', 'Bedroom'), _fan('b', 'Living Room')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bedroom'), findsOneWidget);
      expect(find.text('Living Room'), findsOneWidget);
    });

    testWidgets('shows paired count in header', (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('a', 'Bedroom'), _fan('b', 'Kitchen')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 PAIRED'), findsOneWidget);
    });

    testWidgets('shows model name below nickname', (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('a', 'Bedroom', model: 'T-100')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('T-100'), findsOneWidget);
    });
  });

  // ── FAB ─────────────────────────────────────────────────────────────────────

  group('FansListScreen — FAB', () {
    testWidgets('tapping FAB opens the onboarding bottom sheet', (tester) async {
      await tester.pumpWidget(
        _buildScreen(fansValue: const AsyncData([]), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Add fan'));
      await tester.pumpAndSettle();

      expect(find.text('Pair a new fan'), findsOneWidget);
      expect(find.text('Bluetooth pairing'), findsOneWidget);
      expect(find.text('QR code pairing'), findsOneWidget);
    });
  });

  // ── Long-press actions ──────────────────────────────────────────────────────

  group('FansListScreen — long-press actions', () {
    testWidgets('long-press opens action sheet with Rename and Remove options',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('aa', 'My Fan')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('My Fan'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Fan'), findsOneWidget);
      expect(find.text('Remove Device'), findsOneWidget);
    });

    testWidgets('cancel in action sheet dismisses without calling repo',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('aa', 'My Fan')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('My Fan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.renameFan(any(), any()));
      verifyNever(() => mockRepo.deleteFan(any()));
    });

    testWidgets('rename flow calls renameFan with correct deviceId and new name',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('aa', 'My Fan')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      // Open action sheet.
      await tester.longPress(find.text('My Fan'));
      await tester.pumpAndSettle();

      // Tap Rename Fan.
      await tester.tap(find.text('Rename Fan'));
      await tester.pumpAndSettle();

      // Rename sheet is now visible — type new name into its TextFormField.
      expect(find.text('Rename Fan'), findsOneWidget); // rename sheet title
      await tester.enterText(find.byType(TextFormField), 'Office Fan');
      await tester.pumpAndSettle();

      // Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => mockRepo.renameFan('aa', 'Office Fan')).called(1);
    });

    testWidgets('delete flow calls deleteFan after user confirms', (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('aa', 'My Fan')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      // Open action sheet.
      await tester.longPress(find.text('My Fan'));
      await tester.pumpAndSettle();

      // Tap Remove Device.
      await tester.tap(find.text('Remove Device'));
      await tester.pumpAndSettle();

      // Confirmation dialog.
      expect(find.text('Remove Device?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      verify(() => mockRepo.deleteFan('aa')).called(1);
    });

    testWidgets('cancelling the delete dialog does not call deleteFan',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        fansValue: AsyncData([_fan('aa', 'My Fan')]),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('My Fan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Device'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.deleteFan(any()));
    });
  });
}
