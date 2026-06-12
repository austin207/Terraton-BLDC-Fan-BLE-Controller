// test/unit/usage_summary_test.dart
//
// Tests for UsageSummary — construction, immutability of collections, toJson.
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/usage_summary.dart';

UsageSummary _make({
  String period = '2026-06-05',
  List<double> gearDist = const [0.0, 0.2, 0.3, 0.2, 0.2, 0.1],
  Map<String, double> modeDist = const {'normal': 0.8, 'nature': 0.2},
  List<int>? hourlyUsage,
}) {
  final hourly = hourlyUsage ??
      List.generate(24, (i) => i >= 7 && i <= 22 ? 1 : 0);
  return UsageSummary(
    period: period,
    deviceHash: 'abcd1234abcd1234',
    gearDist: gearDist,
    modeDist: modeDist,
    hourlyUsage: hourly,
    avgSessionMins: 45.0,
    sessions: 3,
    totalKwh: 0.25,
    avgWatts: 40.0,
    avgRpm: 310.0,
    tempMaxC: 34.5,
    tempMinC: 26.1,
    humidityPct: 78.0,
    tariffPerKwh: 5.0,
    ksebSlab: 2,
    monthlyKwhEst: 7.5,
  );
}

void main() {
  group('UsageSummary — scalar fields', () {
    test('period is stored correctly', () {
      expect(_make(period: '2026-01-15').period, '2026-01-15');
    });

    test('deviceHash is stored correctly', () {
      expect(_make().deviceHash, 'abcd1234abcd1234');
    });

    test('numeric fields are stored correctly', () {
      final s = _make();
      expect(s.avgSessionMins, 45.0);
      expect(s.sessions, 3);
      expect(s.totalKwh, closeTo(0.25, 1e-12));
      expect(s.avgWatts, 40.0);
      expect(s.avgRpm, 310.0);
      expect(s.tempMaxC, closeTo(34.5, 1e-9));
      expect(s.tempMinC, closeTo(26.1, 1e-9));
      expect(s.humidityPct, closeTo(78.0, 1e-9));
      expect(s.tariffPerKwh, 5.0);
      expect(s.ksebSlab, 2);
      expect(s.monthlyKwhEst, 7.5);
    });
  });

  group('UsageSummary — collections', () {
    test('gearDist has the correct length', () {
      expect(_make().gearDist, hasLength(6));
    });

    test('gearDist values are preserved', () {
      final dist = [0.1, 0.2, 0.3, 0.2, 0.1, 0.1];
      expect(_make(gearDist: dist).gearDist, dist);
    });

    test('modeDist entries are preserved', () {
      final s = _make();
      expect(s.modeDist, containsPair('normal', closeTo(0.8, 1e-9)));
      expect(s.modeDist, containsPair('nature', closeTo(0.2, 1e-9)));
    });

    test('hourlyUsage has 24 entries', () {
      expect(_make().hourlyUsage, hasLength(24));
    });
  });

  group('UsageSummary — immutability', () {
    test('gearDist is unmodifiable', () {
      final s = _make();
      expect(() => s.gearDist.add(0.0), throwsUnsupportedError);
    });

    test('modeDist is unmodifiable', () {
      final s = _make();
      expect(() => s.modeDist['test'] = 1.0, throwsUnsupportedError);
    });

    test('hourlyUsage is unmodifiable', () {
      final s = _make();
      expect(() => s.hourlyUsage.add(0), throwsUnsupportedError);
    });
  });

  group('UsageSummary — toJson', () {
    test('contains all expected keys', () {
      final json = _make().toJson();
      const expectedKeys = [
        'period', 'device_hash', 'gear_dist', 'mode_dist', 'hourly_usage',
        'avg_session_mins', 'sessions', 'total_kwh', 'avg_watts', 'avg_rpm',
        'temp_max_c', 'temp_min_c', 'humidity_pct',
        'tariff_per_kwh', 'kseb_slab', 'monthly_kwh_est',
      ];
      for (final key in expectedKeys) {
        expect(json.containsKey(key), isTrue, reason: 'missing key: $key');
      }
    });

    test('period value is preserved in JSON', () {
      expect(_make(period: '2026-03-01').toJson()['period'], '2026-03-01');
    });

    test('sessions value is preserved in JSON', () {
      expect(_make().toJson()['sessions'], 3);
    });

    test('gear_dist list is preserved in JSON', () {
      final dist = [0.1, 0.2, 0.3, 0.4, 0.0, 0.0];
      expect(_make(gearDist: dist).toJson()['gear_dist'], dist);
    });

    test('hourly_usage list is preserved in JSON', () {
      final hourly = List.generate(24, (i) => i.isEven ? 1 : 0);
      expect(_make(hourlyUsage: hourly).toJson()['hourly_usage'], hourly);
    });

    test('numeric JSON values match constructor args', () {
      final json = _make().toJson();
      expect(json['total_kwh'], closeTo(0.25, 1e-12));
      expect(json['avg_watts'], 40.0);
      expect(json['temp_max_c'], closeTo(34.5, 1e-9));
      expect(json['kseb_slab'], 2);
      expect(json['monthly_kwh_est'], 7.5);
    });
  });
}
