// test/unit/crash_log_service_test.dart
//
// Tests for CrashLogService — append, bounded size, read, clear.
// path_provider is redirected to a temp directory so the tests are hermetic.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:terraton_fan_app/core/diagnostics/crash_log_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('crash_log_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on Object catch (_) {}
  });

  setUp(() async {
    await CrashLogService.clear();
  });

  group('CrashLogService — read', () {
    test('returns null when nothing recorded', () async {
      expect(await CrashLogService.read(), isNull);
    });
  });

  group('CrashLogService — record', () {
    test('records error with source tag and stack trace', () async {
      await CrashLogService.record(
        StateError('boom'), StackTrace.current, source: 'flutter');

      final log = await CrashLogService.read();
      expect(log, isNotNull);
      expect(log, contains('flutter: Bad state: boom'));
      expect(log, contains('crash_log_service_test'));
    });

    test('appends — both entries survive', () async {
      await CrashLogService.record(
          StateError('first'), null, source: 'flutter');
      await CrashLogService.record(
          StateError('second'), null, source: 'async');

      final log = await CrashLogService.read();
      expect(log, contains('first'));
      expect(log, contains('second'));
      expect(log!.indexOf('first'), lessThan(log.indexOf('second')));
    });

    test('null stack trace is tolerated', () async {
      await CrashLogService.record(StateError('x'), null, source: 'async');
      expect(await CrashLogService.read(), contains('Bad state: x'));
    });

    test('log is bounded — oldest entries dropped past 64 KB', () async {
      // ~3 KB per entry → 40 entries ≈ 120 KB raw, must be trimmed to ≤64 KB
      // keeping the newest entries.
      final filler = 'x' * 3000;
      for (var i = 0; i < 40; i++) {
        await CrashLogService.record(
            StateError('entry$i $filler'), null, source: 'flutter');
      }
      final log = await CrashLogService.read();
      expect(log!.length, lessThanOrEqualTo(64 * 1024));
      expect(log, contains('entry39'));     // newest kept
      expect(log, isNot(contains('entry0 '))); // oldest dropped
    });
  });

  group('CrashLogService — clear', () {
    test('clear removes the log', () async {
      await CrashLogService.record(StateError('boom'), null, source: 'flutter');
      await CrashLogService.clear();
      expect(await CrashLogService.read(), isNull);
    });

    test('clear when no log exists is a no-op', () async {
      await CrashLogService.clear();
      await CrashLogService.clear();
      expect(await CrashLogService.read(), isNull);
    });
  });
}
