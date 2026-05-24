// lib/core/upload/data_upload_service.dart
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/core/upload/usage_summary_builder.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/models/usage_summary.dart';

abstract final class DataUploadService {
  static const _endpoint = 'https://terraton-ingest.bleappterraton.workers.dev/upload';

  // Injected at build time via --dart-define=UPLOAD_API_KEY=<secret>.
  // Defaults to '' (empty) which causes _post() to return false silently —
  // safe for debug/test builds where the key is not provided.
  static const _apiKey = String.fromEnvironment('UPLOAD_API_KEY', defaultValue: '');

  /// Fire-and-forget entry point. Call after app init on Wi-Fi if opted in.
  static Future<void> tryUpload(UsageLogRepository repo) async {
    if (_apiKey.isEmpty) return; // key not injected at build time
    if (!await AppSettings.loadUploadOptIn()) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) return;

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Only upload completed days — today's data is still accumulating.
    final allLogs = repo.getLogsInRange(DateTime(2020), today);
    if (allLogs.isEmpty) return;

    final uploadedDates = await AppSettings.loadUploadedDates();

    // Group by date → device, skipping already-uploaded dates.
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

    for (final entry in byDate.entries) {
      final dateKey = entry.key;
      var allOk = true;

      for (final deviceEntry in entry.value.byDevice.entries) {
        final summary = UsageSummaryBuilder.build(
          deviceEntry.key,
          entry.value.date,
          deviceEntry.value,
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
    } on Object {
      return false;
    }
  }
}

class _DateBucket {
  final DateTime date;
  final Map<String, List<UsageLog>> byDevice = {};
  _DateBucket(this.date);
}
