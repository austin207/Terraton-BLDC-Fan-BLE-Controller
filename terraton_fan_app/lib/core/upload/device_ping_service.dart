// lib/core/upload/device_ping_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';

abstract final class DevicePingService {
  static const _endpoint = 'https://terraton-ingest.bleappterraton.workers.dev/ping';

  /// Fire-and-forget on every app launch. No opt-in required — payload is
  /// fully anonymous (hashed install ID + app version only).
  static Future<void> ping() async {
    try {
      final installId = await AppSettings.loadOrCreateInstallId();
      final deviceHash = sha256
          .convert(utf8.encode(installId))
          .toString()
          .substring(0, 16);

      final info = await PackageInfo.fromPlatform();
      final appVersion = '${info.version}+${info.buildNumber}';

      await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_hash': deviceHash,
              'app_version': appVersion,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } on Exception {
      // Silent — ping failure must never affect app startup.
    }
  }
}
