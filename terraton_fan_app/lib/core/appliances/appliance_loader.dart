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
import 'package:terraton_fan_app/shared/app_config.dart';

abstract final class ApplianceLoader {
  static List<ApplianceCategory> _categories = const [];

  /// All loaded appliance categories in declaration order.
  static List<ApplianceCategory> get categories => _categories;

  /// All [ApplianceType]s across every category, in declaration order.
  static List<ApplianceType> get allTypes =>
      [for (final c in _categories) ...c.types];

  /// Loads and parses the appropriate appliances YAML for the current variant.
  /// Must be called (and awaited) in `main()` before `runApp()`.
  static Future<void> load() async {
    if (_categories.isNotEmpty) return; // idempotent — no-op on repeat calls
    final asset = kIsClientVariant
        ? 'assets/appliances_client.yaml'
        : 'assets/appliances.yaml';
    final raw = await rootBundle.loadString(asset);
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

  /// Universal fallback layout — every built-in section, the classic four modes.
  /// Used for a non-empty model string that matches no known type prefix
  /// (old QR payloads, hand-typed values); preserves the pre-remote-profile
  /// behaviour of "unknown model → show everything".
  static const RemoteProfile _allControls = RemoteProfile(
    model: '',
    name: 'Fan',
    controls: ['speed', 'mode', 'timer', 'lighting'],
    modes: ['nature', 'smart', 'reverse', 'boost'],
  );

  /// Resolves the remote layout for a fan's stored [model].
  ///
  /// Resolution order:
  ///   1. exact match against any type's `remotes:` entry (`TN-CF-01/02/03`);
  ///   2. known type prefix → that type's first remote (e.g. an unknown
  ///      `TN-CF-09` falls back to CF-01), or its legacy four-mode profile
  ///      when the type declares no remotes (table / pedestal / wall / exhaust);
  ///   3. empty model (legacy BLE-paired fan) → the ceiling fan's first remote
  ///      (CF-01), so those fans get a concrete layout and can be switched via
  ///      "Change remote";
  ///   4. anything else → [_allControls].
  static RemoteProfile remoteForModel(String model) {
    final up = model.trim().toUpperCase();

    for (final t in allTypes) {
      final r = t.remoteFor(up);
      if (r != null) return r;
    }

    final type = typeForModel(up);
    if (type != null) {
      return type.remotes.isNotEmpty
          ? type.remotes.first
          : RemoteProfile.legacy(type);
    }

    if (up.isEmpty) {
      final ceiling = typeById('ceiling_fan');
      if (ceiling != null && ceiling.remotes.isNotEmpty) {
        return ceiling.remotes.first;
      }
    }

    return _allControls;
  }

}
