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

  // ── Tariff (₹ / kWh) ────────────────────────────────────────────────────────

  static Future<double> loadTariff({double fallback = 5.4}) async {
    final m = await _read();
    final v = m['tariff'];
    if (v is num) {
      final d = v.toDouble();
      if (d >= 0 && d <= 999) return d;
    }
    return fallback;
  }

  static Future<void> saveTariff(double tariff) async {
    final m = await _read();
    await _write({...m, 'tariff': tariff});
  }

  // ── AI training data opt-in ───────────────────────────────────────────────
  // Override for tests — avoids real file I/O inside widget test pumps.
  // ignore: avoid_field_initializers_in_const_classes
  static Future<bool> Function()? uploadOptInOverride;

  static Future<bool> loadUploadOptIn() async {
    if (uploadOptInOverride != null) return uploadOptInOverride!();
    final m = await _read();
    return (m['upload_opt_in'] as bool?) == true;
  }

  static Future<void> saveUploadOptIn(bool value) async {
    final m = await _read();
    await _write({...m, 'upload_opt_in': value});
  }

  // ── Uploaded date tracking (avoids re-uploading the same day) ────────────

  static Future<Set<String>> loadUploadedDates() async {
    final m = await _read();
    final raw = m['uploaded_dates'];
    if (raw is List) return raw.cast<String>().toSet();
    return {};
  }

  static Future<void> markDateUploaded(String date) async {
    final m     = await _read();
    final dates = ((m['uploaded_dates'] as List?)?.cast<String>() ?? <String>[]).toSet()
      ..add(date);
    await _write({...m, 'uploaded_dates': dates.toList()});
  }
}
