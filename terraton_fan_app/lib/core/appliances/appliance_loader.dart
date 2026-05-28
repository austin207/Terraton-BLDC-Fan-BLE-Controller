// lib/core/appliances/appliance_loader.dart
//
// Loads assets/appliances.yaml once at app startup (called from main.dart).
// All access after that is synchronous via static getters.
//
// Usage:
//   await ApplianceLoader.load();           // in main(), before runApp()
//   ApplianceLoader.categories             // all categories
//   ApplianceLoader.categoryById('fans')   // single category
//   ApplianceLoader.typeById('ceiling_fan')
//   ApplianceLoader.typeForModel('TN-CF-01')

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:terraton_fan_app/models/appliance.dart';

abstract final class ApplianceLoader {
  static List<ApplianceCategory> _categories = const [];

  /// All loaded appliance categories in declaration order.
  static List<ApplianceCategory> get categories => _categories;

  /// All [ApplianceType]s across every category, in declaration order.
  static List<ApplianceType> get allTypes =>
      [for (final c in _categories) ...c.types];

  /// Loads and parses `assets/appliances.yaml`.
  /// Must be called (and awaited) in `main()` before `runApp()`.
  static Future<void> load() async {
    if (_categories.isNotEmpty) return; // idempotent — no-op on repeat calls
    final raw = await rootBundle.loadString('assets/appliances.yaml');
    final doc = loadYaml(raw) as YamlMap;
    _categories = (doc['appliances'] as YamlList)
        .cast<YamlMap>()
        .map((a) => ApplianceCategory.fromYaml(a.cast<Object?, Object?>()))
        .toList(growable: false);
  }

  /// Returns the [ApplianceCategory] with [id], or null if not found.
  static ApplianceCategory? categoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Returns the [ApplianceType] with [id] (searched across all categories),
  /// or null if not found.
  static ApplianceType? typeById(String id) {
    for (final cat in _categories) {
      for (final t in cat.types) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// Returns the [ApplianceType] whose model prefix matches [model]
  /// (e.g. `'TN-CF-03'` → ceiling_fan).
  /// Returns null for empty strings (legacy BLE-paired fans with no stored model).
  static ApplianceType? typeForModel(String model) {
    if (model.isEmpty) return null;
    for (final cat in _categories) {
      for (final t in cat.types) {
        // Skip the empty-string shortcut in matchesModel — we want an exact prefix hit.
        if (model.toUpperCase().startsWith('TN-${t.modelPrefix}-')) return t;
      }
    }
    return null;
  }

  /// Returns the [ApplianceCategory] that owns the type matching [model].
  static ApplianceCategory? categoryForModel(String model) {
    if (model.isEmpty) return null;
    for (final cat in _categories) {
      for (final t in cat.types) {
        if (model.toUpperCase().startsWith('TN-${t.modelPrefix}-')) return cat;
      }
    }
    return null;
  }
}
