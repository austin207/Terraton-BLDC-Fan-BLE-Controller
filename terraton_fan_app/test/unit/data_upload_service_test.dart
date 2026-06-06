// test/unit/data_upload_service_test.dart
//
// Tests for the two pure helpers in DataUploadService:
//   parseWeatherBody — Open-Meteo JSON shape validation (audit fix)
//   rollingMonthlyKwh — 30-day rolling energy window
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/upload/data_upload_service.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

UsageLog _log({
  String deviceId = 'dev1',
  required DateTime startTime,
  int durationSecs = 3600,
  int gear = 3,
  int watts = 50,
}) =>
    UsageLog(
      deviceId: deviceId,
      startTime: startTime,
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
    );

void main() {
  group('DataUploadService.parseWeatherBody — valid input', () {
    test('returns correct temp and humidity values', () {
      const body = '{"daily":{"temperature_2m_max":[34.5],'
          '"temperature_2m_min":[26.1],"relative_humidity_2m_mean":[78.0]}}';
      final r = DataUploadService.parseWeatherBody(body);
      expect(r, isNotNull);
      expect(r!['tempMax'],  closeTo(34.5, 1e-9));
      expect(r['tempMin'],   closeTo(26.1, 1e-9));
      expect(r['humidity'],  closeTo(78.0, 1e-9));
    });

    test('coerces integer JSON values to double', () {
      const body = '{"daily":{"temperature_2m_max":[34],'
          '"temperature_2m_min":[26],"relative_humidity_2m_mean":[78]}}';
      final r = DataUploadService.parseWeatherBody(body);
      expect(r, isNotNull);
      expect(r!['tempMax'], isA<double>());
    });
  });

  group('DataUploadService.parseWeatherBody — malformed input', () {
    test('returns null for a JSON array at root', () {
      expect(DataUploadService.parseWeatherBody('[1,2,3]'), isNull);
    });

    test('returns null when "daily" key is absent', () {
      expect(DataUploadService.parseWeatherBody('{"latitude":10.5}'), isNull);
    });

    test('returns null when "daily" is a list, not a map', () {
      expect(DataUploadService.parseWeatherBody('{"daily":[1,2,3]}'), isNull);
    });

    test('returns null when temperature_2m_max is absent', () {
      const body = '{"daily":{"temperature_2m_min":[26.1],'
          '"relative_humidity_2m_mean":[78]}}';
      expect(DataUploadService.parseWeatherBody(body), isNull);
    });

    test('returns null when a temperature list is empty', () {
      const body = '{"daily":{"temperature_2m_max":[],'
          '"temperature_2m_min":[26.1],"relative_humidity_2m_mean":[78]}}';
      expect(DataUploadService.parseWeatherBody(body), isNull);
    });

    test('returns null when a value is a string instead of a number', () {
      const body = '{"daily":{"temperature_2m_max":["hot"],'
          '"temperature_2m_min":[26.1],"relative_humidity_2m_mean":[78]}}';
      expect(DataUploadService.parseWeatherBody(body), isNull);
    });

    test('returns null when a value is JSON null', () {
      const body = '{"daily":{"temperature_2m_max":[null],'
          '"temperature_2m_min":[26.1],"relative_humidity_2m_mean":[78]}}';
      expect(DataUploadService.parseWeatherBody(body), isNull);
    });

    test('returns null for completely invalid JSON', () {
      expect(DataUploadService.parseWeatherBody('not json'), isNull);
    });

    test('returns null for empty string', () {
      expect(DataUploadService.parseWeatherBody(''), isNull);
    });
  });

  group('DataUploadService.rollingMonthlyKwh', () {
    // base = June 5, 2026 midnight local time
    // cutoff  = May 6  (base - 30 days)
    // dayEnd  = June 6 (base + 1 day)
    final base = DateTime(2026, 6, 5);

    test('sums all device logs within the 30-day window', () {
      final logs = [
        _log(startTime: DateTime(2026, 6, 4),  watts: 50, durationSecs: 3600), // 0.05 kWh
        _log(startTime: DateTime(2026, 5, 10), watts: 50, durationSecs: 3600), // 0.05 kWh
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        closeTo(0.10, 1e-9),
      );
    });

    test('includes log exactly at the 30-day cutoff boundary (>= cutoff)', () {
      // cutoff = May 6; a log at May 6 must be included
      final logs = [
        _log(startTime: DateTime(2026, 5, 6), watts: 50, durationSecs: 3600),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        closeTo(0.05, 1e-9),
      );
    });

    test('excludes log one day before the cutoff (< cutoff)', () {
      // May 5 is before May 6 cutoff → excluded
      final logs = [
        _log(startTime: DateTime(2026, 5, 5), watts: 50, durationSecs: 3600),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        0.0,
      );
    });

    test('includes log on upToDate itself', () {
      final logs = [
        _log(startTime: DateTime(2026, 6, 5), watts: 50, durationSecs: 3600),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        closeTo(0.05, 1e-9),
      );
    });

    test('excludes log after upToDate (next day)', () {
      final logs = [
        _log(startTime: DateTime(2026, 6, 6), watts: 50, durationSecs: 3600),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        0.0,
      );
    });

    test('excludes logs from a different device', () {
      final logs = [
        _log(deviceId: 'dev2', startTime: DateTime(2026, 6, 4),
            watts: 100, durationSecs: 7200),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        0.0,
      );
    });

    test('returns 0.0 when log list is empty', () {
      expect(DataUploadService.rollingMonthlyKwh('dev1', base, []), 0.0);
    });

    test('logs with gear == 0 contribute 0 kWh (fan off, kwh getter returns 0)', () {
      final logs = [
        _log(startTime: DateTime(2026, 6, 4), gear: 0, watts: 50, durationSecs: 3600),
      ];
      expect(
        DataUploadService.rollingMonthlyKwh('dev1', base, logs),
        0.0,
      );
    });
  });
}
