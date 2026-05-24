// lib/core/upload/usage_summary_builder.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/models/usage_summary.dart';

abstract final class UsageSummaryBuilder {
  /// Builds a [UsageSummary] for [deviceId] on [date] from [logs].
  /// Returns null if there are no active (gear > 0) segments for that day.
  ///
  /// Weather values default to -1.0 (missing sentinel) when the caller
  /// could not fetch them. The training pipeline handles -1 as NaN.
  static UsageSummary? build(
    String deviceId,
    DateTime date,
    List<UsageLog> logs, {
    double tempMaxC      = -1,
    double tempMinC      = -1,
    double humidityPct   = -1,
    double tariffPerKwh  = 5.4,
    double monthlyKwhEst = 0,
  }) {
    final dayLogs = logs.where((l) => _sameDay(l.startTime.toLocal(), date)).toList();
    if (dayLogs.isEmpty) return null;

    final gearSecs = List.filled(6, 0.0);
    final modeSecs = <String, double>{};
    final hourly   = List.filled(24, 0);
    double totalSecs     = 0;
    double weightedWatts = 0;
    double totalKwh      = 0;
    int    validSecs     = 0;
    int    activeLogs    = 0;

    for (final log in dayLogs) {
      if (log.gear <= 0) continue;
      activeLogs++;
      totalSecs += log.durationSecs;
      gearSecs[(log.gear - 1).clamp(0, 5)] += log.durationSecs;

      final mode = log.mode ?? 'normal';
      modeSecs[mode] = (modeSecs[mode] ?? 0) + log.durationSecs;

      hourly[log.startTime.toLocal().hour] = 1;

      if (log.watts > 0) {
        totalKwh      += log.kwh;
        weightedWatts += log.watts * log.durationSecs;
        validSecs     += log.durationSecs;
      }
    }

    if (activeLogs == 0) return null;

    final gearDist = gearSecs
        .map((s) => totalSecs > 0 ? s / totalSecs : 0.0)
        .toList();
    final modeDist = modeSecs.map(
      (k, v) => MapEntry(k, totalSecs > 0 ? v / totalSecs : 0.0),
    );
    final avgWatts       = validSecs > 0 ? weightedWatts / validSecs : 0.0;
    final avgSessionMins = totalSecs / activeLogs / 60;

    final deviceHash = sha256
        .convert(utf8.encode(deviceId))
        .toString()
        .substring(0, 16);

    final dateStr = '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return UsageSummary(
      period:         dateStr,
      deviceHash:     deviceHash,
      gearDist:       gearDist,
      modeDist:       modeDist,
      hourlyUsage:    hourly,
      avgSessionMins: avgSessionMins,
      sessions:       activeLogs,
      totalKwh:       totalKwh,
      avgWatts:       avgWatts,
      tempMaxC:       tempMaxC,
      tempMinC:       tempMinC,
      humidityPct:    humidityPct,
      tariffPerKwh:   tariffPerKwh,
      ksebSlab:       _ksebSlab(monthlyKwhEst),
      monthlyKwhEst:  monthlyKwhEst,
    );
  }

  // KSEB LT domestic slab based on the fan's estimated monthly consumption.
  // Total household consumption is not known, so this is a rough proxy —
  // but the model can still learn cost-sensitivity patterns from it.
  static int _ksebSlab(double monthlyKwh) {
    if (monthlyKwh <= 50)  return 1;  // ₹3.15 / unit
    if (monthlyKwh <= 100) return 2;  // ₹3.70 / unit
    if (monthlyKwh <= 150) return 3;  // ₹4.50 / unit
    if (monthlyKwh <= 200) return 4;  // ₹5.80 / unit
    if (monthlyKwh <= 250) return 5;  // ₹6.70 / unit
    if (monthlyKwh <= 300) return 6;  // ₹7.50 / unit
    if (monthlyKwh <= 350) return 7;  // ₹7.90 / unit
    return 8;                          // ₹8.20 / unit
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
