// lib/core/update/app_update_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  /// Parses a raw `version.json` byte response into [UpdateInfo].
  ///
  /// Strips the UTF-8 BOM that PowerShell 5.1 writes, validates the JSON shape,
  /// and returns null when [localBuild] is already up to date.
  /// Throws [FormatException] for any malformed input.
  ///
  /// Exposed for unit testing; prefer [checkForUpdate] in production code.
  @visibleForTesting
  static UpdateInfo? parseVersionResponse(
      Uint8List bytes, int localBuild, String localVersion) {
    final trimmed = (bytes.length >= 3 &&
            bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        ? bytes.sublist(3)
        : bytes;
    // Validate shape before casting — a non-object JSON value would throw a
    // TypeError (an Error), which `on Exception` in checkForUpdate does NOT catch.
    final decoded = jsonDecode(utf8.decode(trimmed));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('version.json is not a JSON object');
    }
    final remoteBuildRaw   = decoded['build_number'];
    final remoteVersionRaw = decoded['version'];
    if (remoteBuildRaw is! num || remoteVersionRaw is! String) {
      throw const FormatException('version.json missing build_number/version');
    }
    final remoteBuild = remoteBuildRaw.toInt();
    if (kDebugMode) debugPrint('[OTA] local=$localBuild remote=$remoteBuild');
    return remoteBuild > localBuild
        ? UpdateInfo(
            version: remoteVersionRaw,
            buildNumber: remoteBuild,
            localVersion: localVersion,
          )
        : null;
  }

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
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    // GitHub serves release assets as application/octet-stream — Dart's http
    // package defaults to Latin-1 for that content type, so res.body is wrong.
    // Decode bodyBytes as UTF-8 explicitly.
    return parseVersionResponse(res.bodyBytes, localBuild, pkgInfo.version);
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
  /// Returns null on success, or an error message string on failure.
  ///
  /// On Android 8+ the "Install Unknown Apps" special permission must be
  /// granted by the user. If it isn't, [Permission.requestInstallPackages]
  /// opens the correct system settings page for the user to enable it.
  static Future<String?> installUpdate(File apkFile) async {
    if (!await Permission.requestInstallPackages.isGranted) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        return 'Enable "Install Unknown Apps" for Terraton Fan in system settings, then try again.';
      }
    }
    final result = await OpenFile.open(apkFile.path);
    if (result.type != ResultType.done) {
      return result.message.isNotEmpty
          ? result.message
          : 'Could not open the installer. Please install the APK manually.';
    }
    return null;
  }
}
