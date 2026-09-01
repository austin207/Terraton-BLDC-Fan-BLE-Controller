// lib/models/appliance.dart
//
// Strongly-typed models for the appliances.yaml config.
// Loaded once at startup by ApplianceLoader; never instantiated by hand.

/// One appliance category shown as a tile on the Home screen.
/// e.g. "Fans", "Lights", "ACs".
class ApplianceCategory {
  final String id;
  final String displayName;
  final String pluralLabel;
  final String iconPath;
  final List<ApplianceType> types;

  /// When true, this category's types are not yet supported: selecting a type
  /// shows the Coming Soon page instead of the pairing / fan-list flow.
  final bool comingSoon;

  const ApplianceCategory({
    required this.id,
    required this.displayName,
    required this.pluralLabel,
    required this.iconPath,
    required this.types,
    this.comingSoon = false,
  });

  factory ApplianceCategory.fromYaml(Map<Object?, Object?> yaml) {
    final displayName = yaml['displayName'] as String;
    return ApplianceCategory(
      id:          yaml['id']          as String,
      displayName: displayName,
      pluralLabel: yaml['pluralLabel'] as String? ?? '${displayName}s',
      iconPath:    yaml['icon']        as String,
      comingSoon:  yaml['comingSoon']  as bool? ?? false,
      types: (yaml['types'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(ApplianceType.fromYaml)
          .toList(growable: false),
    );
  }
}

/// One appliance sub-type within a category (e.g. "Ceiling Fan" inside "Fans").
/// Owns the model-prefix, icon, and the list of controls the device exposes.
class ApplianceType {
  final String id;
  final String displayName;

  /// Two-letter prefix used to generate model IDs: `TN-<prefix>-01` … `TN-<prefix>-N`.
  final String modelPrefix;
  final String iconPath;
  final int modelCount;

  /// Ordered list of control-type strings that appear in the control screen.
  /// Built-in types: speed, mode, timer, lighting, power.
  /// Any other string must be registered in ControlRegistry before runApp().
  ///
  /// Used as the fallback layout for a model of this type that matches no
  /// [remotes] entry; a matched model uses its [RemoteProfile.controls] instead.
  final List<String> controls;

  /// Per-model remote layouts. When non-empty, a fan of this type shows one of
  /// these (chosen by its stored model ID) rather than the type-level defaults,
  /// and the pairing picker offers exactly these models. Empty for every type
  /// that has a single universal remote.
  final List<RemoteProfile> remotes;

  const ApplianceType({
    required this.id,
    required this.displayName,
    required this.modelPrefix,
    required this.iconPath,
    required this.modelCount,
    required this.controls,
    this.remotes = const [],
  });

  factory ApplianceType.fromYaml(Map<Object?, Object?> yaml) => ApplianceType(
        id:          yaml['id']          as String,
        displayName: yaml['displayName'] as String,
        modelPrefix: yaml['modelPrefix'] as String,
        iconPath:    yaml['icon']        as String,
        modelCount:  yaml['modelCount']  as int? ?? 21,
        controls: (yaml['controls'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(growable: false),
        remotes: (yaml['remotes'] as List<Object?>? ?? const [])
            .cast<Map<Object?, Object?>>()
            .map(RemoteProfile.fromYaml)
            .toList(growable: false),
      );

  /// e.g. "Ceiling Fans"
  String get pluralLabel => '${displayName}s';

  /// The model IDs offered when pairing a fan of this type.
  /// Derives from [remotes] when the type declares them; otherwise the
  /// generated `TN-<prefix>-01` … sequence.
  List<String> get modelNumbers => remotes.isNotEmpty
      ? remotes.map((r) => r.model).toList(growable: false)
      : List.generate(
          modelCount,
          (i) => 'TN-$modelPrefix-${(i + 1).toString().padLeft(2, '0')}',
          growable: false,
        );

  /// Returns true when [model] belongs to this type.
  /// An empty model string returns true so that legacy BLE-paired fans
  /// (no stored model) are never hidden from any category view.
  bool matchesModel(String model) {
    if (model.isEmpty) return true;
    return model.toUpperCase().startsWith('TN-$modelPrefix-');
  }

  /// Whether this type declares [controlType] (e.g. 'speed', 'lighting').
  bool hasControl(String controlType) => controls.contains(controlType);

  /// The [RemoteProfile] for [model], or null when this type has no `remotes:`
  /// or none match. Match is case-insensitive and exact on the model ID.
  RemoteProfile? remoteFor(String model) {
    final up = model.toUpperCase();
    for (final r in remotes) {
      if (r.model == up) return r;
    }
    return null;
  }
}

/// One physical remote layout bound to a specific fan model (e.g. `TN-CF-01`).
/// Declared under a type's `remotes:` list in appliances.yaml. Drives which
/// control sections and which mode-row buttons the control screen renders.
class RemoteProfile {
  /// Model ID this remote is bound to, upper-cased (e.g. `TN-CF-02`).
  final String model;

  /// Short display name shown in the pairing / change-remote picker (e.g. `CF-02`).
  final String name;

  /// Ordered control-type strings shown for this remote — same vocabulary as
  /// [ApplianceType.controls] (speed | mode | timer | lighting | custom).
  final List<String> controls;

  /// Ordered mode-row buttons: `nature` | `smart` | `reverse` | `boost` | `led`.
  /// Only rendered when `controls` contains `mode`.
  final List<String> modes;

  const RemoteProfile({
    required this.model,
    required this.name,
    required this.controls,
    required this.modes,
  });

  factory RemoteProfile.fromYaml(Map<Object?, Object?> yaml) => RemoteProfile(
        model: (yaml['model'] as String).toUpperCase(),
        name:  yaml['name'] as String,
        controls: (yaml['controls'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(growable: false),
        modes: (yaml['modes'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(growable: false),
      );

  /// Synthesises the single implicit remote for a type that declares no
  /// `remotes:` — its own controls plus the classic four-mode row.
  factory RemoteProfile.legacy(ApplianceType type) => RemoteProfile(
        model: '',
        name:  type.displayName,
        controls: type.controls,
        modes: const ['nature', 'smart', 'reverse', 'boost'],
      );

  bool hasControl(String controlType) => controls.contains(controlType);
  bool hasMode(String mode) => modes.contains(mode);
}
