// test/unit/appliance_loader_test.dart
//
// Tests for ApplianceLoader — YAML parsing, lookup helpers, and model matching.
// Runs against appliances.yaml (tester variant; no --dart-define passed in tests).
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ApplianceLoader.load();
  });

  group('ApplianceLoader — category loading', () {
    test('loads 4 appliance categories', () {
      expect(ApplianceLoader.categories.length, 4);
    });

    test('first category is fans', () {
      expect(ApplianceLoader.categories.first.id, 'fans');
    });

    test('fans category is NOT comingSoon', () {
      expect(ApplianceLoader.categoryById('fans')!.comingSoon, isFalse);
    });

    test('all non-fan categories are comingSoon', () {
      for (final cat in ApplianceLoader.categories.skip(1)) {
        expect(cat.comingSoon, isTrue,
            reason: '${cat.id} should be comingSoon');
      }
    });

    test('categoryById returns null for an unknown id', () {
      expect(ApplianceLoader.categoryById('unknown'), isNull);
    });

    test('pluralLabel override is applied (water_filtration → "Water Filters")', () {
      expect(ApplianceLoader.categoryById('water_filtration')!.pluralLabel,
          'Water Filters');
    });
  });

  group('ApplianceLoader — type loading', () {
    test('fans category has 5 types', () {
      expect(ApplianceLoader.categoryById('fans')!.types.length, 5);
    });

    test('allTypes contains 12 types across all categories', () {
      // fans(5) + water(2) + air(2) + energy(3)
      expect(ApplianceLoader.allTypes.length, 12);
    });

    test('typeById returns the correct type', () {
      expect(ApplianceLoader.typeById('ceiling_fan')?.id, 'ceiling_fan');
    });

    test('typeById returns null for an unknown id', () {
      expect(ApplianceLoader.typeById('unknown_type'), isNull);
    });

    test('ceiling_fan has speed, mode, timer, lighting controls', () {
      final cf = ApplianceLoader.typeById('ceiling_fan')!;
      expect(cf.controls,
          containsAll(['speed', 'mode', 'timer', 'lighting']));
    });

    test('exhaust_fan has no mode control', () {
      expect(ApplianceLoader.typeById('exhaust_fan')!.hasControl('mode'),
          isFalse);
    });

    test('table_fan has speed and mode but no lighting', () {
      final tf = ApplianceLoader.typeById('table_fan')!;
      expect(tf.hasControl('speed'), isTrue);
      expect(tf.hasControl('mode'),  isTrue);
      expect(tf.hasControl('lighting'), isFalse);
    });
  });

  group('ApplianceLoader — typeForModel lookup', () {
    test('TN-CF-03 → ceiling_fan', () {
      expect(ApplianceLoader.typeForModel('TN-CF-03')?.id, 'ceiling_fan');
    });

    test('TN-PF-01 → pedestal_fan', () {
      expect(ApplianceLoader.typeForModel('TN-PF-01')?.id, 'pedestal_fan');
    });

    test('TN-TF-21 → table_fan', () {
      expect(ApplianceLoader.typeForModel('TN-TF-21')?.id, 'table_fan');
    });

    test('TN-WF-05 → wall_fan', () {
      expect(ApplianceLoader.typeForModel('TN-WF-05')?.id, 'wall_fan');
    });

    test('TN-EF-01 → exhaust_fan', () {
      expect(ApplianceLoader.typeForModel('TN-EF-01')?.id, 'exhaust_fan');
    });

    test('lookup is case-insensitive', () {
      expect(ApplianceLoader.typeForModel('tn-cf-01')?.id, 'ceiling_fan');
    });

    test('returns null for an empty string (legacy fan, no stored model)', () {
      expect(ApplianceLoader.typeForModel(''), isNull);
    });

    test('returns null for a completely unknown prefix', () {
      expect(ApplianceLoader.typeForModel('TN-XX-01'), isNull);
    });

    test('returns null for a string that is not a TN-prefixed model', () {
      expect(ApplianceLoader.typeForModel('GENERIC-FAN'), isNull);
    });
  });

  group('ApplianceLoader — ApplianceType helpers', () {
    test('modelNumbers generates TN-CF-01 … TN-CF-21 for ceiling_fan', () {
      final nums = ApplianceLoader.typeById('ceiling_fan')!.modelNumbers;
      expect(nums.first, 'TN-CF-01');
      expect(nums.last,  'TN-CF-21');
      expect(nums.length, 21);
    });

    test('modelNumbers for ro_filter generates 10 entries', () {
      expect(ApplianceLoader.typeById('ro_filter')!.modelNumbers.length, 10);
    });

    test('matchesModel returns true for a matching TN-CF-xx string', () {
      expect(
          ApplianceLoader.typeById('ceiling_fan')!.matchesModel('TN-CF-07'),
          isTrue);
    });

    test('matchesModel returns true for empty string (legacy fans)', () {
      expect(ApplianceLoader.typeById('ceiling_fan')!.matchesModel(''), isTrue);
    });

    test('matchesModel returns false for a different prefix', () {
      expect(
          ApplianceLoader.typeById('ceiling_fan')!.matchesModel('TN-TF-01'),
          isFalse);
    });

    test('pluralLabel appends s to displayName', () {
      expect(ApplianceLoader.typeById('ceiling_fan')!.pluralLabel,
          'Ceiling Fans');
    });
  });

  group('ApplianceLoader — idempotent load', () {
    test('calling load() a second time is a no-op', () async {
      final countBefore = ApplianceLoader.categories.length;
      await ApplianceLoader.load();
      expect(ApplianceLoader.categories.length, countBefore);
    });
  });
}
