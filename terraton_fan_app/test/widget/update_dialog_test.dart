// test/widget/update_dialog_test.dart
//
// Tests for UpdateDialog idle phase — header content and button labels.
// Does not test download/install phases (they call static AppUpdateService
// methods that would require platform channels or network).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/update/app_update_service.dart';
import 'package:terraton_fan_app/features/update/update_dialog.dart';

const _info = UpdateInfo(
  version: '4.0.0',
  buildNumber: 40,
  localVersion: '3.0.0',
);

Widget _wrapDirect() => MaterialApp(
      home: Scaffold(body: UpdateDialog(info: _info)),
    );

void main() {
  group('UpdateDialog — idle phase rendering', () {
    testWidgets('shows "Update Available" heading', (tester) async {
      await tester.pumpWidget(_wrapDirect());
      expect(find.text('Update Available'), findsOneWidget);
    });

    testWidgets('shows version transition string', (tester) async {
      await tester.pumpWidget(_wrapDirect());
      expect(find.text('v3.0.0 → v4.0.0'), findsOneWidget);
    });

    testWidgets('shows Later button', (tester) async {
      await tester.pumpWidget(_wrapDirect());
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('shows Update Now button', (tester) async {
      await tester.pumpWidget(_wrapDirect());
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('shows descriptive body text', (tester) async {
      await tester.pumpWidget(_wrapDirect());
      expect(
        find.textContaining('new version'),
        findsOneWidget,
      );
    });
  });

  group('UpdateDialog — Later button dismissal', () {
    testWidgets('Later button dismisses the bottom sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: ctx,
                  builder: (_) => UpdateDialog(info: _info),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Update Available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update Available'), findsNothing);
    });
  });
}
