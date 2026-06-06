// test/unit/usage_summary_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/upload/usage_summary_builder.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

final _date = DateTime(2026, 1, 1);

UsageLog _log({
  int durationSecs = 3600,
  int gear = 3,
  int watts = 50,
  int rpm = 0,
  int hour = 9,
  String? mode,
}) =>
    UsageLog(
      deviceId: 'dev1',
      startTime: DateTime(2026, 1, 1, hour),
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
      rpm: rpm,
      mode: mode,
    );

void main() {
  group('UsageSummaryBuilder.avgRpm', () {
    test('weights RPM by segment duration', () {
      // (300*100 + 200*300) / (100+300) = 90000/400 = 225
      final summary = UsageSummaryBuilder.build('dev1', _date, [
        _log(rpm: 300, durationSecs: 100),
        _log(rpm: 200, durationSecs: 300),
      ]);
      expect(summary, isNotNull);
      expect(summary!.avgRpm, closeTo(225, 1e-9));
    });

    test('segments with rpm == 0 are excluded from the RPM average', () {
      // Only the rpm>0 segment contributes; the 900 s rpm==0 segment is ignored.
      final summary = UsageSummaryBuilder.build('dev1', _date, [
        _log(rpm: 300, durationSecs: 100),
        _log(rpm: 0, durationSecs: 900),
      ]);
      expect(summary!.avgRpm, closeTo(300, 1e-9));
    });

    test('avgRpm is 0 when no segment reported RPM', () {
      final summary = UsageSummaryBuilder.build('dev1', _date, [
        _log(rpm: 0, durationSecs: 1800),
      ]);
      expect(summary!.avgRpm, 0.0);
    });

    test('gear == 0 (fan off) segments never contribute to RPM', () {
      final summary = UsageSummaryBuilder.build('dev1', _date, [
        _log(rpm: 400, gear: 0, durationSecs: 600), // off — skipped entirely
        _log(rpm: 250, gear: 2, durationSecs: 200),
      ]);
      expect(summary!.avgRpm, closeTo(250, 1e-9));
    });

    test('avg_rpm is serialized in toJson', () {
      final summary = UsageSummaryBuilder.build('dev1', _date, [
        _log(rpm: 280, durationSecs: 600),
      ]);
      expect(summary!.toJson()['avg_rpm'], closeTo(280, 1e-9));
    });
  });
}
