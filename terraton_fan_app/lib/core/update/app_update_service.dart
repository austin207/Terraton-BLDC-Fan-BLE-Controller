// lib/core/update/app_update_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  const UpdateInfo({required this.version, required this.buildNumber});
}

abstract final class AppUpdateService {
  static const _repo = 'austin207/Terraton-BLDC-Fan-BLE-Controller';
  static const _versionUrl =
      'https://github.com/$_repo/releases/latest/download/version.json';
  static const _apkUrl =
      'https://github.com/$_repo/releases/latest/download/terraton-fan-arm64.apk';

  /// Returns [UpdateInfo] if remote build_number > installed build, else null.
  /// Returns null silently on any network/parse error.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final remoteBuild = (body['build_number'] as num).toInt();
      final remoteVersion = body['version'] as String;

      return remoteBuild > localBuild
          ? UpdateInfo(version: remoteVersion, buildNumber: remoteBuild)
          : null;
    } on Exception {
      return null;
    }
  }

  /// Streams the arm64 APK to a temp file.
  /// [onProgress] receives values from 0.0 to 1.0.
  /// Returns the [File] on success, or null on any failure.
  static Future<File?> downloadUpdate(void Function(double) onProgress) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/terraton-update.apk');

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(_apkUrl));
        final res = await client.send(req);
        if (res.statusCode != 200) return null;

        final total = res.contentLength ?? 0;
        var received = 0;
        final sink = file.openWrite();

        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }

        await sink.flush();
        await sink.close();
        return file;
      } finally {
        client.close();
      }
    } on Exception {
      return null;
    }
  }

  /// Triggers the Android system package installer for [apkFile].
  static Future<void> installUpdate(File apkFile) async {
    await OpenFile.open(apkFile.path);
  }
}
