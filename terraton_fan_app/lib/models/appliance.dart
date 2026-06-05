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
  final List<String> controls;

  const ApplianceType({
    required this.id,
    required this.displayName,
    required this.modelPrefix,
    required this.iconPath,
    required this.modelCount,
    required this.controls,
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
      );

  /// e.g. "Ceiling Fans"
  String get pluralLabel => '${displayName}s';

  /// Generates `TN-CF-01` … `TN-CF-21` for this type.
  List<String> get modelNumbers => List.generate(
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
}
