// lib/core/config/app_feature_config.dart
//
// Loads assets/app_config.yaml once at app startup (called from main.dart).
// All access after that is synchronous via static getters.
//
// Usage:
//   await AppFeatureConfig.load();        // in main(), before runApp()
//   AppFeatureConfig.autoUpdateEnabled    // OTA feature toggle

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

abstract final class AppFeatureConfig {
  static YamlMap? _config;

  /// Call once in main.dart before runApp.
  static Future<void> load() async {
    if (_config != null) return; // idempotent — no-op on repeat calls
    final raw = await rootBundle.loadString('assets/app_config.yaml');
    _config = loadYaml(raw) as YamlMap;
  }

  /// True unless explicitly set to `false` in app_config.yaml.
  static bool get autoUpdateEnabled =>
      (_config?['auto_update_enabled'] as bool?) ?? true;
}
