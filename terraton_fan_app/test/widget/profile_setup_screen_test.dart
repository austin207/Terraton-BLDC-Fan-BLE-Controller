// test/widget/profile_setup_screen_test.dart
//
// Tests for ProfileSetupScreen UI behaviour only.
// The actual save path (AppSettings.markProfileSet / saveUserName) writes to
// the file system and is not exercised here to keep tests hermetic.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/features/onboarding/profile_setup_screen.dart';

// A lightweight UserNameNotifier substitute that avoids file I/O.
class _FakeUserNameNotifier extends UserNameNotifier {
  @override
  Future<String> build() async => '';
  @override
  Future<void> save(String name) async {
    state = AsyncData(name);
  }
}

Widget _buildScreen() => ProviderScope(
      overrides: [
        userNameProvider.overrideWith(() => _FakeUserNameNotifier()),
      ],
      child: const MaterialApp(home: ProfileSetupScreen()),
    );

// ProfileSetupScreen.initState schedules a 200 ms timer to request keyboard
// focus. Pump 300 ms explicitly so the fake clock fires the timer before
// pumpAndSettle() tries to verify the (now-stable) tree.
Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(_buildScreen());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  group('ProfileSetupScreen — rendering', () {
    testWidgets('shows "What should we call you?" headline', (tester) async {
      await _pump(tester);

      expect(find.textContaining('What should'), findsOneWidget);
    });

    testWidgets('shows step indicator', (tester) async {
      await _pump(tester);

      expect(find.textContaining('STEP 1 OF 1'), findsOneWidget);
    });

    testWidgets('shows Continue button', (tester) async {
      await _pump(tester);

      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('ProfileSetupScreen — button state', () {
    testWidgets('Continue button is inactive (onTap null) with empty field',
        (tester) async {
      await _pump(tester);

      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Continue'), matching: find.byType(InkWell))
            .first,
      );
      expect(inkWell.onTap, isNull);
    });

    testWidgets('Continue button is inactive with a single-character name',
        (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'A');
      await tester.pump();

      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Continue'), matching: find.byType(InkWell))
            .first,
      );
      expect(inkWell.onTap, isNull);
    });

    testWidgets('Continue button becomes active when name has 2+ characters',
        (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'Jo');
      await tester.pump();

      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Continue'), matching: find.byType(InkWell))
            .first,
      );
      expect(inkWell.onTap, isNotNull);
    });

    testWidgets('Continue button reacts to text changes dynamically',
        (tester) async {
      await _pump(tester);

      final finder = find
          .ancestor(of: find.text('Continue'), matching: find.byType(InkWell))
          .first;

      // Start with a long valid name.
      await tester.enterText(find.byType(TextField), 'Austin');
      await tester.pump();
      expect(tester.widget<InkWell>(finder).onTap, isNotNull);

      // Clear to one character — should disable.
      await tester.enterText(find.byType(TextField), 'A');
      await tester.pump();
      expect(tester.widget<InkWell>(finder).onTap, isNull);

      // Back to valid length.
      await tester.enterText(find.byType(TextField), 'Austin');
      await tester.pump();
      expect(tester.widget<InkWell>(finder).onTap, isNotNull);
    });
  });
}
