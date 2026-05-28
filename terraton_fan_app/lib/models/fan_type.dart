// lib/models/fan_type.dart

/// Every Terraton fan category shown in the Fan Types screen.
/// Each case owns its model prefix so model IDs are generated dynamically
/// without hardcoded lists.
enum FanType {
  ceiling('Ceiling Fan', 'CF'),
  table('Table Fan', 'TF'),
  pedestal('Pedestal Fan', 'PF'),
  wall('Wall Fan', 'WF'),
  exhaust('Exhaust Fan', 'EF');

  const FanType(this.label, this.prefix);

  final String label;
  final String prefix;

  /// "Ceiling Fans", "Table Fans", etc.
  String get pluralLabel => '${label}s';

  /// Generates TN-XX-01 … TN-XX-21 for this category.
  List<String> get modelNumbers => List.generate(
        21,
        (i) => 'TN-$prefix-${(i + 1).toString().padLeft(2, '0')}',
      );

  /// Returns true when [model] belongs to this category.
  /// An empty model string returns true so that legacy BLE-paired fans
  /// (which have no model stored) are never hidden from any category.
  bool matchesModel(String model) {
    if (model.isEmpty) return true;
    return model.toUpperCase().startsWith('TN-$prefix-');
  }
}
