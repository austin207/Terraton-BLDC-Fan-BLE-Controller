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
    final f = await _file();
    await f.writeAsString(jsonEncode(data));
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

  static Future<bool> isFirstLaunch() async {
    final m = await _read();
    return (m['profile_set'] as bool?) != true;
  }

  static Future<void> markProfileSet() async {
    final m = await _read();
    await _write({...m, 'profile_set': true});
  }
}
