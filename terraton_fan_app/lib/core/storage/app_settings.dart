// lib/core/storage/app_settings.dart
// Simple JSON file for lightweight app-level settings (user name, first-launch flag).
// Uses path_provider (already a dep) — no new packages needed.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract final class AppSettings {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final f   = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }

  // ── User name ────────────────────────────────────────────────────────────────

  static Future<String> loadUserName() async {
    final m = await _read();
    return (m['user_name'] as String? ?? '').trim();
  }

  static Future<void> saveUserName(String name) async {
    final m = await _read();
    await _write({...m, 'user_name': name.trim()});
  }

  // ── First-launch flag ─────────────────────────────────────────────────────────
  // True until the user completes ProfileSetupScreen.

  // Override for tests — set to a synchronous supplier to avoid real file I/O
  // inside FakeAsync (which does not process real I/O events). Leave null in
  // production; the file-based path is used instead.
  // ignore: avoid_field_initializers_in_const_classes
  static Future<bool> Function()? firstLaunchOverride;

  static Future<bool> isFirstLaunch() async {
    if (firstLaunchOverride != null) return firstLaunchOverride!();
    final m = await _read();
    return (m['profile_set'] as bool?) != true;
  }

  static Future<void> markProfileSet() async {
    final m = await _read();
    await _write({...m, 'profile_set': true});
  }
}
