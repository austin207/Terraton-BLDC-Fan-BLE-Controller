// test/unit/app_settings_test.dart
//
// Tests for AppSettings — round-trip JSON file I/O for user name and
// first-launch flag.
//
// path_provider is redirected to a temp directory so the tests are hermetic.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';

// ── Fake path provider ────────────────────────────────────────────────────────

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('app_settings_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Start each test with a clean slate.
    final file = File('${tempDir.path}/app_settings.json');
    if (await file.exists()) await file.delete();
  });

  group('AppSettings — user name', () {
    test('loadUserName returns empty string when no file exists', () async {
      expect(await AppSettings.loadUserName(), '');
    });

    test('saveUserName then loadUserName round-trips the name', () async {
      await AppSettings.saveUserName('Austin');
      expect(await AppSettings.loadUserName(), 'Austin');
    });

    test('saveUserName trims surrounding whitespace', () async {
      await AppSettings.saveUserName('  Austin  ');
      expect(await AppSettings.loadUserName(), 'Austin');
    });

    test('saveUserName overwrites a previously saved name', () async {
      await AppSettings.saveUserName('Alice');
      await AppSettings.saveUserName('Bob');
      expect(await AppSettings.loadUserName(), 'Bob');
    });

    test('saveUserName preserves other keys in the file', () async {
      await AppSettings.markProfileSet(); // writes profile_set: true
      await AppSettings.saveUserName('Carol');
      // profile_set should survive the user-name update
      expect(await AppSettings.isFirstLaunch(), isFalse);
      expect(await AppSettings.loadUserName(), 'Carol');
    });
  });

  group('AppSettings — first launch', () {
    test('isFirstLaunch returns true when no file exists', () async {
      expect(await AppSettings.isFirstLaunch(), isTrue);
    });

    test('isFirstLaunch returns true before markProfileSet', () async {
      await AppSettings.saveUserName('Test');
      expect(await AppSettings.isFirstLaunch(), isTrue);
    });

    test('markProfileSet makes isFirstLaunch return false', () async {
      await AppSettings.markProfileSet();
      expect(await AppSettings.isFirstLaunch(), isFalse);
    });

    test('markProfileSet is idempotent', () async {
      await AppSettings.markProfileSet();
      await AppSettings.markProfileSet();
      expect(await AppSettings.isFirstLaunch(), isFalse);
    });

    test('markProfileSet preserves user name', () async {
      await AppSettings.saveUserName('Austin');
      await AppSettings.markProfileSet();
      expect(await AppSettings.loadUserName(), 'Austin');
    });
  });
}
