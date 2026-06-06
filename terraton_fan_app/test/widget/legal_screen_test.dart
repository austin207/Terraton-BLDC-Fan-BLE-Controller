// test/widget/legal_screen_test.dart
//
// Tests for LegalScreen, PrivacyPolicyScreen, and TermsScreen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/legal/legal_screen.dart';
import 'package:terraton_fan_app/features/legal/privacy_policy_screen.dart';
import 'package:terraton_fan_app/features/legal/terms_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('LegalScreen', () {
    testWidgets('shows title in appBar', (tester) async {
      await tester.pumpWidget(_wrap(const LegalScreen(
        title: 'Test Policy',
        lastUpdated: 'June 2026',
        sections: [
          LegalSection('Section A', 'Body text A'),
          LegalSection('Section B', 'Body text B'),
        ],
      )));
      expect(find.text('Test Policy'), findsOneWidget);
    });

    testWidgets('shows last-updated line', (tester) async {
      await tester.pumpWidget(_wrap(const LegalScreen(
        title: 'Policy',
        lastUpdated: 'June 2026',
        sections: [],
      )));
      expect(find.textContaining('June 2026'), findsOneWidget);
    });

    testWidgets('renders all section headings', (tester) async {
      await tester.pumpWidget(_wrap(const LegalScreen(
        title: 'Policy',
        lastUpdated: 'May 2026',
        sections: [
          LegalSection('Heading 1', 'Body 1'),
          LegalSection('Heading 2', 'Body 2'),
          LegalSection('Heading 3', 'Body 3'),
        ],
      )));
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('Heading 2'), findsOneWidget);
      expect(find.text('Heading 3'), findsOneWidget);
    });

    testWidgets('renders all section body texts', (tester) async {
      await tester.pumpWidget(_wrap(const LegalScreen(
        title: 'Policy',
        lastUpdated: 'May 2026',
        sections: [
          LegalSection('H1', 'Body text here'),
        ],
      )));
      expect(find.text('Body text here'), findsOneWidget);
    });

    testWidgets('empty sections list renders without crash', (tester) async {
      await tester.pumpWidget(_wrap(const LegalScreen(
        title: 'Empty Policy',
        lastUpdated: 'May 2026',
        sections: [],
      )));
      expect(find.text('Empty Policy'), findsOneWidget);
    });
  });

  group('PrivacyPolicyScreen', () {
    testWidgets('title is Privacy Policy', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPolicyScreen()));
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('shows at least one section heading', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPolicyScreen()));
      // First section heading from the static list
      expect(find.text('What data we collect'), findsOneWidget);
    });
  });

  group('TermsScreen', () {
    testWidgets('renders without crash (smoke test)', (tester) async {
      await tester.pumpWidget(_wrap(const TermsScreen()));
      // TermsScreen extends LegalScreen — just verify it renders
      expect(find.byType(LegalScreen), findsOneWidget);
    });
  });
}
