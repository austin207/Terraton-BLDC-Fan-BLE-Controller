// test/unit/app_update_service_test.dart
//
// Tests for AppUpdateService.parseVersionResponse — the BOM-stripping and
// JSON-shape validation that guards against TypeError crashes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/update/app_update_service.dart';

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

Uint8List _bom(Object value) {
  final core = utf8.encode(jsonEncode(value));
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...core]);
}

void main() {
  group('AppUpdateService.parseVersionResponse — version comparison', () {
    test('returns UpdateInfo when remote build > local', () {
      final info = AppUpdateService.parseVersionResponse(
        _json({'version': '4.0.0', 'build_number': 40}),
        30, '3.0.0',
      );
      expect(info, isNotNull);
      expect(info!.version, '4.0.0');
      expect(info.buildNumber, 40);
      expect(info.localVersion, '3.0.0');
    });

    test('returns null when remote build == local (up to date)', () {
      final info = AppUpdateService.parseVersionResponse(
        _json({'version': '3.0.0', 'build_number': 30}),
        30, '3.0.0',
      );
      expect(info, isNull);
    });

    test('returns null when remote build < local', () {
      final info = AppUpdateService.parseVersionResponse(
        _json({'version': '2.0.0', 'build_number': 20}),
        30, '3.0.0',
      );
      expect(info, isNull);
    });

    test('accepts build_number as a float (num coercion)', () {
      // Some JSON serialisers emit 40.0 instead of 40.
      final info = AppUpdateService.parseVersionResponse(
        _json({'version': '4.0.0', 'build_number': 40.0}),
        30, '3.0.0',
      );
      expect(info?.buildNumber, 40);
    });
  });

  group('AppUpdateService.parseVersionResponse — apk_sha256', () {
    test('parses apk_sha256 when present, lowercased', () {
      final info = AppUpdateService.parseVersionResponse(
        _json({
          'version': '4.0.0',
          'build_number': 40,
          'apk_sha256': 'ABCDEF0123456789',
        }),
        30, '3.0.0',
      );
      expect(info?.apkSha256, 'abcdef0123456789');
    });

    test('apkSha256 is null when field is absent (older releases)', () {
      final info = AppUpdateService.parseVersionResponse(
        _json({'version': '4.0.0', 'build_number': 40}),
        30, '3.0.0',
      );
      expect(info, isNotNull);
      expect(info!.apkSha256, isNull);
    });

    test('apkSha256 is null when field is empty or wrong type', () {
      final empty = AppUpdateService.parseVersionResponse(
        _json({'version': '4.0.0', 'build_number': 40, 'apk_sha256': ''}),
        30, '3.0.0',
      );
      expect(empty!.apkSha256, isNull);

      final wrongType = AppUpdateService.parseVersionResponse(
        _json({'version': '4.0.0', 'build_number': 40, 'apk_sha256': 123}),
        30, '3.0.0',
      );
      expect(wrongType!.apkSha256, isNull);
    });
  });

  group('AppUpdateService.parseVersionResponse — BOM stripping', () {
    test('strips UTF-8 BOM (0xEF BB BF) and parses correctly', () {
      final info = AppUpdateService.parseVersionResponse(
        _bom({'version': '4.0.0', 'build_number': 40}),
        30, '3.0.0',
      );
      expect(info, isNotNull);
      expect(info!.version, '4.0.0');
    });

    test('BOM-prefixed up-to-date payload returns null', () {
      final info = AppUpdateService.parseVersionResponse(
        _bom({'version': '3.0.0', 'build_number': 30}),
        30, '3.0.0',
      );
      expect(info, isNull);
    });
  });

  group('AppUpdateService.parseVersionResponse — malformed input', () {
    test('throws FormatException when response is a JSON array', () {
      expect(
        () => AppUpdateService.parseVersionResponse(_json([1, 2, 3]), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when response is a JSON string', () {
      expect(
        () => AppUpdateService.parseVersionResponse(_json('hello'), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when response is a JSON number', () {
      expect(
        () => AppUpdateService.parseVersionResponse(_json(42), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when build_number field is missing', () {
      expect(
        () => AppUpdateService.parseVersionResponse(
            _json({'version': '4.0.0'}), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when version field is missing', () {
      expect(
        () => AppUpdateService.parseVersionResponse(
            _json({'build_number': 40}), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when build_number is a string, not a num', () {
      expect(
        () => AppUpdateService.parseVersionResponse(
            _json({'version': '4.0.0', 'build_number': '40'}), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when version is a number, not a string', () {
      expect(
        () => AppUpdateService.parseVersionResponse(
            _json({'version': 4, 'build_number': 40}), 30, '3.0.0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for empty byte array (not valid JSON)', () {
      expect(
        () => AppUpdateService.parseVersionResponse(
            Uint8List(0), 30, '3.0.0'),
        throwsA(anything),
      );
    });
  });
}
