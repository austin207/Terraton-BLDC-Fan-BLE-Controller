// lib/core/update/app_update_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String localVersion;
  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.localVersion,
  });
}

abstract final class AppUpdateService {
  static const _repo = 'austin207/Terraton-BLDC-Fan-BLE-Controller';
  // Tag-based URL — avoids GitHub's "latest release" redirect, which is
  // unreliable when the release tag itself is the string "latest".
  static const _versionUrl =
      'https://github.com/$_repo/releases/download/latest/version.json';
  static const _apkUrl =
      'https://github.com/$_repo/releases/download/latest/terraton-fan-arm64.apk';

  /// Core check — throws on network/HTTP/parse failure; returns null if up to date.
  static Future<UpdateInfo?> _doCheck() async {
    final pkgInfo    = await PackageInfo.fromPlatform();
    final localBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;

    // Cache-Control header asks CDN not to serve a stale response.
    // Query params are NOT used — GitHub release download URLs reject unknown
    // query parameters and return a non-200, which looks like a network error.
    final res = await http.get(
      Uri.parse(_versionUrl),
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final body          = jsonDecode(res.body) as Map<String, dynamic>;
    final remoteBuild   = (body['build_number'] as num).toInt();
    final remoteVersion = body['version'] as String;

    if (kDebugMode) debugPrint('[OTA] local=$localBuild remote=$remoteBuild');
    return remoteBuild > localBuild
        ? UpdateInfo(
            version: remoteVersion,
            buildNumber: remoteBuild,
            localVersion: pkgInfo.version,
          )
        : null;
  }

  /// Returns [UpdateInfo] if remote build_number > installed build, else null.
  /// Swallows all errors silently — safe for the automatic on-launch check.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      return await _doCheck();
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[OTA] checkForUpdate error: $e');
      return null;
    }
  }

  /// Same check as [checkForUpdate] but surfaces errors to the caller.
  /// Returns null if up to date; throws [Exception] on network/parse failure.
  /// Use this for the manual "Check for Updates" trigger in Settings.
  static Future<UpdateInfo?> checkForUpdateManual() => _doCheck();

  /// Streams the arm64 APK to a temp file.
  /// [onProgress] receives values from 0.0 to 1.0.
  /// Returns the [File] on success, or null on any failure.
  static Future<File?> downloadUpdate(void Function(double) onProgress) async {
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/terraton-update.apk');

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(_apkUrl));
        final res = await client.send(req);
        if (res.statusCode != 200) return null;

        final total    = res.contentLength ?? 0;
        var   received = 0;
        final sink     = file.openWrite();
        try {
          await for (final chunk in res.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) onProgress(received / total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        return file;
      } finally {
        client.close();
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[OTA] downloadUpdate error: $e');
      return null;
    }
  }

  /// Triggers the Android system package installer for [apkFile].
  static Future<void> installUpdate(File apkFile) async {
    await OpenFile.open(apkFile.path);
  }
}
