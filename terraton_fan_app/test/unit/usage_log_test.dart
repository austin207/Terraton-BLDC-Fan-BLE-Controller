// test/unit/usage_log_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

UsageLog _log({
  String deviceId = 'dev1',
  int durationSecs = 3600,
  int gear = 3,
  int watts = 50,
  String? mode,
}) =>
    UsageLog(
      deviceId: deviceId,
      startTime: DateTime(2026, 1, 1),
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
      mode: mode,
    );

void main() {
  group('UsageLog defaults', () {
    test('id defaults to 0', () {
      expect(_log().id, 0);
    });

    test('mode defaults to null when not supplied', () {
      expect(_log().mode, isNull);
    });

    test('mode is preserved when supplied', () {
      expect(_log(mode: 'nature').mode, 'nature');
    });
  });

  group('UsageLog.kwh', () {
    test('returns 0 when watts is 0', () {
      expect(_log(watts: 0).kwh, 0.0);
    });

    test('returns 0 when gear is 0', () {
      expect(_log(gear: 0).kwh, 0.0);
    });

    test('returns 0 when both watts and gear are 0', () {
      expect(_log(watts: 0, gear: 0).kwh, 0.0);
    });

    test('100 W for 1 hour (3600 s) = 0.1 kWh', () {
      expect(_log(watts: 100, durationSecs: 3600).kwh, closeTo(0.1, 1e-9));
    });

    test('50 W for 30 min (1800 s) = 0.025 kWh', () {
      expect(_log(watts: 50, durationSecs: 1800).kwh, closeTo(0.025, 1e-9));
    });

    test('0 W for any duration = 0 kWh', () {
      expect(_log(watts: 0, durationSecs: 7200).kwh, 0.0);
    });

    test('formula: watts * durationSecs / 3_600_000', () {
      const w = 45;
      const d = 1234;
      expect(_log(watts: w, durationSecs: d).kwh,
          closeTo(w * d / 3600.0 / 1000.0, 1e-12));
    });
  });
}
