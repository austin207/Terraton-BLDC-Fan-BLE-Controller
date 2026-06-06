// lib/core/upload/data_upload_service.dart
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/core/upload/usage_summary_builder.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/models/usage_summary.dart';

abstract final class DataUploadService {
  static const _endpoint = 'https://terraton-ingest.bleappterraton.workers.dev/upload';

  // Injected at build time via --dart-define=UPLOAD_API_KEY=<secret>.
  // Defaults to '' (empty) which causes tryUpload() to return early silently --
  // safe for debug/test builds where the key is not provided.
  static const _apiKey = String.fromEnvironment('UPLOAD_API_KEY', defaultValue: '');

  // Open-Meteo — central Kerala coordinates (no API key required).
  static const _lat = 10.5;
  static const _lon = 76.27;

  /// Fire-and-forget entry point. Call after app init on Wi-Fi if opted in.
  static Future<void> tryUpload(UsageLogRepository repo) async {
    if (_apiKey.isEmpty) return;
    if (!await AppSettings.loadUploadOptIn()) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) return;

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Only upload completed days — today's data is still accumulating.
    final allLogs = repo.getLogsInRange(
      DateTime(2020),
      today.subtract(const Duration(milliseconds: 1)),
    );
    if (allLogs.isEmpty) return;

    final uploadedDates = await AppSettings.loadUploadedDates();
    final tariff        = await AppSettings.loadTariff();

    // Group logs by date → device, skipping already-uploaded dates.
    final byDate = <String, _DateBucket>{};
    for (final log in allLogs) {
      final local = log.startTime.toLocal();
      final key   = '${local.year}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      if (uploadedDates.contains(key)) continue;
      final bucket = byDate.putIfAbsent(
        key, () => _DateBucket(DateTime(local.year, local.month, local.day)),
      );
      bucket.byDevice.putIfAbsent(log.deviceId, () => <UsageLog>[]).add(log);
    }

    // Weather cache — one fetch per date, shared across all devices for that day.
    final weatherCache = <String, _WeatherData?>{};

    for (final entry in byDate.entries) {
      final dateKey = entry.key;
      var allOk = true;

      weatherCache[dateKey] ??= await _fetchWeather(dateKey);
      final wx = weatherCache[dateKey];

      for (final deviceEntry in entry.value.byDevice.entries) {
        final mKwh = _rollingMonthlyKwh(deviceEntry.key, entry.value.date, allLogs);

        final summary = UsageSummaryBuilder.build(
          deviceEntry.key,
          entry.value.date,
          deviceEntry.value,
          tempMaxC:      wx?.tempMax    ?? -1,
          tempMinC:      wx?.tempMin    ?? -1,
          humidityPct:   wx?.humidity   ?? -1,
          tariffPerKwh:  tariff,
          monthlyKwhEst: mKwh,
        );
        if (summary == null) continue;
        if (!await _post(summary)) {
          allOk = false;
          break;
        }
      }

      if (allOk) await AppSettings.markDateUploaded(dateKey);
    }
  }

  // ── Weather ───────────────────────────────────────────────────────────────────

  /// Parses an Open-Meteo daily-forecast JSON response body.
  ///
  /// Returns a `{'tempMax', 'tempMin', 'humidity'}` map on success, or null for
  /// any malformed/missing field.  Exposed for unit testing.
  @visibleForTesting
  static Map<String, double>? parseWeatherBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final daily = decoded['daily'];
      if (daily is! Map<String, dynamic>) return null;
      final maxList = daily['temperature_2m_max'];
      final minList = daily['temperature_2m_min'];
      final humList = daily['relative_humidity_2m_mean'];
      if (maxList is! List || maxList.isEmpty ||
          minList is! List || minList.isEmpty ||
          humList is! List || humList.isEmpty) {
        return null;
      }
      final tMax = maxList.first;
      final tMin = minList.first;
      final hum  = humList.first;
      if (tMax is! num || tMin is! num || hum is! num) return null;
      return {
        'tempMax':  tMax.toDouble(),
        'tempMin':  tMin.toDouble(),
        'humidity': hum.toDouble(),
      };
    } on Exception {
      return null;
    }
  }

  static Future<_WeatherData?> _fetchWeather(String dateStr) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_lat&longitude=$_lon'
        '&daily=temperature_2m_max,temperature_2m_min,relative_humidity_2m_mean'
        '&start_date=$dateStr&end_date=$dateStr'
        '&timezone=Asia%2FKolkata',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final parsed = parseWeatherBody(res.body);
      if (parsed == null) return null;
      return _WeatherData(
        tempMax:  parsed['tempMax']!,
        tempMin:  parsed['tempMin']!,
        humidity: parsed['humidity']!,
      );
    } on Exception {
      return null;
    }
  }

  // ── Tariff helpers ────────────────────────────────────────────────────────────

  /// Rolling 30-day kWh for one device, ending on (and including) [upToDate].
  /// Exposed for unit testing.
  @visibleForTesting
  static double rollingMonthlyKwh(
      String deviceId, DateTime upToDate, List<UsageLog> allLogs) =>
      _rollingMonthlyKwh(deviceId, upToDate, allLogs);

  static double _rollingMonthlyKwh(
    String deviceId,
    DateTime upToDate,
    List<UsageLog> allLogs,
  ) {
    final cutoff  = upToDate.subtract(const Duration(days: 30));
    final dayEnd  = upToDate.add(const Duration(days: 1));
    return allLogs
        .where((l) =>
            l.deviceId == deviceId &&
            !l.startTime.toLocal().isBefore(cutoff) &&
            l.startTime.toLocal().isBefore(dayEnd))
        .fold(0.0, (sum, l) => sum + l.kwh);
  }

  // ── Upload ────────────────────────────────────────────────────────────────────

  static Future<bool> _post(UsageSummary summary) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type':  'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(summary.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _DateBucket {
  final DateTime date;
  final Map<String, List<UsageLog>> byDevice = {};
  _DateBucket(this.date);
}

class _WeatherData {
  final double tempMax;
  final double tempMin;
  final double humidity;
  const _WeatherData({
    required this.tempMax,
    required this.tempMin,
    required this.humidity,
  });
}
