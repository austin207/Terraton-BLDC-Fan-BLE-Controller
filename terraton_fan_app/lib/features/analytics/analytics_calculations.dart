// lib/features/analytics/analytics_calculations.dart
//
// Pure aggregation math for the Analytics screen, extracted so the formulas
// can be pinned with table-driven unit tests (the screen's State class is not
// unit-testable). No Flutter imports — operates only on model lists.
import 'package:terraton_fan_app/models/daily_runtime.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

abstract final class AnalyticsCalculations {
  /// Wattage of a comparable traditional (non-BLDC) ceiling fan at top speed.
  static const double traditionalWatts = 85.0;

  /// Smart Mode steps down one speed level every 2 hours.
  static const int smartStepSecs = 2 * 3600;

  /// Per-speed wattage, scaled linearly from the [traditionalWatts] baseline.
  static double traditionalWattsForSpeed(int speed) =>
      traditionalWatts * speed / 6;

  /// Total energy in kWh across [logs].
  static double sumKwh(List<UsageLog> logs) =>
      logs.fold(0.0, (s, l) => s + l.kwh);

  /// Duration-weighted average wattage across active segments.
  static int avgWatts(List<UsageLog> logs) {
    final active = logs.where((l) => l.watts > 0 && l.gear > 0).toList();
    if (active.isEmpty) return 0;
    final totalSecs = active.fold(0, (s, l) => s + l.durationSecs);
    if (totalSecs == 0) return 0;
    return (active.fold(0.0, (s, l) => s + l.watts * l.durationSecs) / totalSecs)
        .round();
  }

  /// Duration-weighted average RPM across active segments.
  static int avgRpm(List<UsageLog> logs) {
    final active = logs.where((l) => l.rpm > 0 && l.gear > 0).toList();
    if (active.isEmpty) return 0;
    final totalSecs = active.fold(0, (s, l) => s + l.durationSecs);
    if (totalSecs == 0) return 0;
    return (active.fold(0.0, (s, l) => s + l.rpm * l.durationSecs) / totalSecs)
        .round();
  }

  /// Smart Mode efficiency: compares each Smart segment's modelled consumption
  /// against what the baseline speed (active immediately before Smart was
  /// enabled) would have consumed over the same runtime.
  ///
  /// Smart Mode consumption models a gradual reduction from the baseline speed
  /// down to Speed 1 — the first [smartStepSecs] per speed level (baseline..1)
  /// are spent stepping down through those levels; any remaining runtime is
  /// spent entirely at Speed 1. Segments shorter than the full step-down are
  /// split evenly across the levels.
  ///
  /// Returns a whole-number percentage clamped to 0–100; 0 when no Smart
  /// segments exist.
  static int efficiency(List<UsageLog> logs) {
    final smart = logs
        .where((l) => l.mode == 'smart' && l.gear > 0 && l.durationSecs > 0)
        .toList();
    if (smart.isEmpty) return 0;

    double totalTraditionalWh = 0;
    double totalSmartWh = 0;

    for (final l in smart) {
      final baseline = (l.smartBaselineGear ?? l.gear).clamp(1, 6);
      totalTraditionalWh +=
          traditionalWattsForSpeed(baseline) * l.durationSecs / 3600.0;

      final reductionTotalSecs = smartStepSecs * baseline;
      final levelSecs = <int, int>{};
      if (l.durationSecs <= reductionTotalSecs) {
        final perLevel = l.durationSecs / baseline;
        for (var level = 1; level <= baseline; level++) {
          levelSecs[level] = perLevel.round();
        }
      } else {
        for (var level = 1; level <= baseline; level++) {
          levelSecs[level] = smartStepSecs;
        }
        levelSecs[1] = (levelSecs[1] ?? 0) + (l.durationSecs - reductionTotalSecs);
      }
      for (final entry in levelSecs.entries) {
        totalSmartWh +=
            traditionalWattsForSpeed(entry.key) * entry.value / 3600.0;
      }
    }

    if (totalTraditionalWh == 0) return 0;
    return ((totalTraditionalWh - totalSmartWh) / totalTraditionalWh * 100)
        .round()
        .clamp(0, 100);
  }

  /// Human-readable label for an [efficiency] percentage.
  static String efficiencyLabel(int pct) {
    if (pct >= 80) return 'Excellent Efficiency';
    if (pct >= 60) return 'Optimal Range';
    if (pct >= 40) return 'Moderate Efficiency';
    if (pct > 0)   return 'Low Efficiency';
    return 'No Data Yet';
  }

  // ── Daily-runtime based kWh ──────────────────────────────────────────────

  /// Normalises [records] across every day in [[from]..[to]] (both inclusive).
  /// Days without a record are filled with the average of days that have data.
  /// Returns one runtime value in seconds per day (real or estimated).
  static List<double> normalizeDailyRuntimes(
      List<DailyRuntime> records, DateTime from, DateTime to) {
    final n = to.difference(from).inDays + 1;
    if (n <= 0) return const [];
    final avg = records.isEmpty
        ? 0.0
        : records.fold(0.0, (s, r) => s + r.runtimeSecs) / records.length;
    return List.generate(n, (i) {
      final day = DateTime(from.year, from.month, from.day + i);
      final matches = records.where((r) => _sameDay(r.date, day));
      return matches.isEmpty ? avg : matches.first.runtimeSecs.toDouble();
    });
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Total kWh for [records] in [[from]..[to]] at [gearWatts] watts.
  /// Missing days are estimated with the historical average.
  static double rangeKwh(
      List<DailyRuntime> records, DateTime from, DateTime to, int gearWatts) {
    if (gearWatts == 0) return 0.0;
    return normalizeDailyRuntimes(records, from, to)
        .fold(0.0, (s, secs) => s + gearWatts * secs / 3_600_000);
  }

  /// Per-point kWh list for chart rendering at [gearWatts] watts.
  ///
  /// When [splitDay] is true (Day range: a single [from] == [to] day) the
  /// day's total kWh is split into 6 equal 4-hour buckets so the chart has
  /// the same number of points as Week/Month charts.
  static List<double> chartKwh(
      List<DailyRuntime> records, DateTime from, DateTime to, int gearWatts,
      {bool splitDay = false}) {
    final daily = normalizeDailyRuntimes(records, from, to)
        .map((secs) => gearWatts * secs / 3_600_000)
        .toList();
    if (splitDay && daily.length == 1) {
      final v = daily.first / 6;
      return List.filled(6, v);
    }
    return daily;
  }
}
