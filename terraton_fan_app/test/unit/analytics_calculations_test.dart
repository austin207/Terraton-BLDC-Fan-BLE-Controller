// test/unit/analytics_calculations_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/analytics/analytics_calculations.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

UsageLog log({
  int durationSecs = 3600,
  int gear = 3,
  int watts = 30,
  int rpm = 0,
  String? mode,
  int? smartBaselineGear,
}) =>
    UsageLog(
      deviceId: 'dev1',
      startTime: DateTime(2026, 6, 1),
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
      rpm: rpm,
      mode: mode,
      smartBaselineGear: smartBaselineGear,
    );

void main() {
  group('traditionalWattsForSpeed', () {
    test('scales linearly: speed 6 = full 85 W', () {
      expect(AnalyticsCalculations.traditionalWattsForSpeed(6), 85.0);
    });

    test('speed 3 = half of 85 W', () {
      expect(AnalyticsCalculations.traditionalWattsForSpeed(3), 42.5);
    });

    test('speed 1 = one sixth of 85 W', () {
      expect(AnalyticsCalculations.traditionalWattsForSpeed(1),
          closeTo(85.0 / 6, 1e-9));
    });
  });

  group('sumKwh', () {
    test('empty list returns 0', () {
      expect(AnalyticsCalculations.sumKwh([]), 0.0);
    });

    test('sums kwh across segments', () {
      // 30 W for 1 h = 0.03 kWh; two of them = 0.06 kWh.
      final logs = [log(), log()];
      expect(AnalyticsCalculations.sumKwh(logs), closeTo(0.06, 1e-9));
    });

    test('segments with gear 0 contribute nothing (kwh getter gate)', () {
      expect(AnalyticsCalculations.sumKwh([log(gear: 0)]), 0.0);
    });
  });

  group('avgWatts', () {
    test('empty list returns 0', () {
      expect(AnalyticsCalculations.avgWatts([]), 0);
    });

    test('ignores segments with watts == 0 or gear == 0', () {
      final logs = [log(watts: 0), log(gear: 0)];
      expect(AnalyticsCalculations.avgWatts(logs), 0);
    });

    test('single segment returns its wattage', () {
      expect(AnalyticsCalculations.avgWatts([log(watts: 45)]), 45);
    });

    test('weights by duration, not by segment count', () {
      // 3 h at 20 W + 1 h at 60 W = (60+60)/4 = 30 W, not (20+60)/2 = 40 W.
      final logs = [
        log(durationSecs: 3 * 3600, watts: 20),
        log(durationSecs: 1 * 3600, watts: 60),
      ];
      expect(AnalyticsCalculations.avgWatts(logs), 30);
    });
  });

  group('avgRpm', () {
    test('empty list returns 0', () {
      expect(AnalyticsCalculations.avgRpm([]), 0);
    });

    test('ignores segments with rpm == 0', () {
      expect(AnalyticsCalculations.avgRpm([log(rpm: 0)]), 0);
    });

    test('weights by duration', () {
      // 1 h at 200 RPM + 3 h at 400 RPM = (200 + 1200)/4 = 350 RPM.
      final logs = [
        log(durationSecs: 1 * 3600, rpm: 200),
        log(durationSecs: 3 * 3600, rpm: 400),
      ];
      expect(AnalyticsCalculations.avgRpm(logs), 350);
    });
  });

  group('efficiency — input filtering', () {
    test('empty list returns 0', () {
      expect(AnalyticsCalculations.efficiency([]), 0);
    });

    test('non-smart segments return 0 (Smart-only metric)', () {
      final logs = [log(mode: null), log(mode: 'boost'), log(mode: 'reverse')];
      expect(AnalyticsCalculations.efficiency(logs), 0);
    });

    test('smart segment with zero duration is excluded', () {
      expect(
        AnalyticsCalculations.efficiency(
            [log(mode: 'smart', durationSecs: 0, smartBaselineGear: 4)]),
        0,
      );
    });

    test('smart segment with gear 0 is excluded', () {
      expect(
        AnalyticsCalculations.efficiency(
            [log(mode: 'smart', gear: 0, smartBaselineGear: 4)]),
        0,
      );
    });
  });

  group('efficiency — gradual step-down model', () {
    // Baseline B, runtime exactly B * 2h (full step-down window):
    // time is split as 2 h at each level B..1, so
    //   smartWh = Σ(level=1..B) wPer * level * 2   where wPer = 85/6
    //   tradWh  = wPer * B * (2B)
    // For B = 4: smartWh = wPer*(1+2+3+4)*2 = 20*wPer; tradWh = 32*wPer
    // → savings = (32-20)/32 = 37.5 % → rounds to 38.
    test('baseline 4, runtime exactly 8h → 38%', () {
      final l = log(
        mode: 'smart',
        gear: 4,
        smartBaselineGear: 4,
        durationSecs: 4 * AnalyticsCalculations.smartStepSecs,
      );
      expect(AnalyticsCalculations.efficiency([l]), 38);
    });

    // Runtime beyond the step-down window: extra time all at Speed 1.
    // B = 4, runtime = 8h step-down + 8h at speed 1:
    //   smartWh = 20*wPer + 8*1*wPer = 28*wPer; tradWh = 4*16*wPer = 64*wPer
    // → savings = 36/64 = 56.25 % → rounds to 56.
    test('baseline 4, runtime 16h (8h past step-down) → 56%', () {
      final l = log(
        mode: 'smart',
        gear: 4,
        smartBaselineGear: 4,
        durationSecs: 8 * AnalyticsCalculations.smartStepSecs,
      );
      expect(AnalyticsCalculations.efficiency([l]), 56);
    });

    // Runtime shorter than the step-down window: duration split evenly
    // across levels B..1. B = 4, runtime = 4h → 1h per level:
    //   smartWh = (1+2+3+4)*wPer = 10*wPer; tradWh = 4*4*wPer = 16*wPer
    // → savings = 6/16 = 37.5 % → rounds to 38.
    test('baseline 4, runtime 4h (partial step-down) → 38%', () {
      final l = log(
        mode: 'smart',
        gear: 4,
        smartBaselineGear: 4,
        durationSecs: 4 * 3600,
      );
      expect(AnalyticsCalculations.efficiency([l]), 38);
    });

    // Baseline 1 never steps down — Smart == traditional → 0 % savings.
    test('baseline 1 yields 0% (no step-down possible)', () {
      final l = log(
        mode: 'smart',
        gear: 1,
        smartBaselineGear: 1,
        durationSecs: 4 * 3600,
      );
      expect(AnalyticsCalculations.efficiency([l]), 0);
    });

    test('falls back to gear when smartBaselineGear is null', () {
      final withBaseline = log(
        mode: 'smart', gear: 4, smartBaselineGear: 4,
        durationSecs: 4 * AnalyticsCalculations.smartStepSecs,
      );
      final withoutBaseline = log(
        mode: 'smart', gear: 4, smartBaselineGear: null,
        durationSecs: 4 * AnalyticsCalculations.smartStepSecs,
      );
      expect(
        AnalyticsCalculations.efficiency([withoutBaseline]),
        AnalyticsCalculations.efficiency([withBaseline]),
      );
    });

    test('out-of-range baseline is clamped to 1..6', () {
      final l = log(
        mode: 'smart',
        gear: 3,
        smartBaselineGear: 99,
        durationSecs: 6 * AnalyticsCalculations.smartStepSecs,
      );
      final clamped = log(
        mode: 'smart',
        gear: 3,
        smartBaselineGear: 6,
        durationSecs: 6 * AnalyticsCalculations.smartStepSecs,
      );
      expect(
        AnalyticsCalculations.efficiency([l]),
        AnalyticsCalculations.efficiency([clamped]),
      );
    });

    test('multiple segments aggregate (not averaged per segment)', () {
      // Two identical segments must give the same % as one.
      final l = log(
        mode: 'smart', gear: 4, smartBaselineGear: 4,
        durationSecs: 4 * AnalyticsCalculations.smartStepSecs,
      );
      expect(AnalyticsCalculations.efficiency([l, l]),
          AnalyticsCalculations.efficiency([l]));
    });

    test('result is clamped to 0..100', () {
      final l = log(
        mode: 'smart', gear: 6, smartBaselineGear: 6,
        durationSecs: 100 * AnalyticsCalculations.smartStepSecs,
      );
      final pct = AnalyticsCalculations.efficiency([l]);
      expect(pct, inInclusiveRange(0, 100));
    });
  });

  group('efficiencyLabel', () {
    test('thresholds match spec', () {
      expect(AnalyticsCalculations.efficiencyLabel(100), 'Excellent Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(80),  'Excellent Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(79),  'Optimal Range');
      expect(AnalyticsCalculations.efficiencyLabel(60),  'Optimal Range');
      expect(AnalyticsCalculations.efficiencyLabel(59),  'Moderate Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(40),  'Moderate Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(39),  'Low Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(1),   'Low Efficiency');
      expect(AnalyticsCalculations.efficiencyLabel(0),   'No Data Yet');
    });
  });
}
