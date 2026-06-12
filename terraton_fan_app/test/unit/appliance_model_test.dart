// test/unit/appliance_model_test.dart
//
// Tests for ApplianceType and ApplianceCategory — constructor fields, derived
// helpers (pluralLabel, modelNumbers, matchesModel, hasControl), and fromYaml.
// Does NOT cover ApplianceLoader (see appliance_loader_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/appliance.dart';

const _ceilingFan = ApplianceType(
  id: 'ceiling_fan',
  displayName: 'Ceiling Fan',
  modelPrefix: 'CF',
  iconPath: 'assets/icons/ceiling_fan.png',
  modelCount: 21,
  controls: ['speed', 'mode', 'timer', 'lighting'],
);

void main() {
  group('ApplianceType — construction', () {
    test('stores id and displayName', () {
      expect(_ceilingFan.id, 'ceiling_fan');
      expect(_ceilingFan.displayName, 'Ceiling Fan');
    });

    test('stores modelPrefix and modelCount', () {
      expect(_ceilingFan.modelPrefix, 'CF');
      expect(_ceilingFan.modelCount, 21);
    });

    test('stores controls list', () {
      expect(_ceilingFan.controls,
          containsAll(['speed', 'mode', 'timer', 'lighting']));
    });
  });

  group('ApplianceType — pluralLabel', () {
    test('appends s to displayName', () {
      expect(_ceilingFan.pluralLabel, 'Ceiling Fans');
    });

    test('appends s correctly for non-fan names', () {
      const type = ApplianceType(
        id: 'ro_filter', displayName: 'RO Filter',
        modelPrefix: 'RF', iconPath: '', modelCount: 10, controls: [],
      );
      expect(type.pluralLabel, 'RO Filters');
    });
  });

  group('ApplianceType — modelNumbers', () {
    test('generates TN-CF-01 … TN-CF-21', () {
      final nums = _ceilingFan.modelNumbers;
      expect(nums.length, 21);
      expect(nums.first, 'TN-CF-01');
      expect(nums.last, 'TN-CF-21');
    });

    test('single-digit entries have leading zero', () {
      final nums = _ceilingFan.modelNumbers;
      expect(nums[0], 'TN-CF-01');
      expect(nums[8], 'TN-CF-09');
    });

    test('two-digit entries have no leading zero', () {
      final nums = _ceilingFan.modelNumbers;
      expect(nums[9], 'TN-CF-10');
      expect(nums[20], 'TN-CF-21');
    });

    test('modelCount = 5 generates 5 entries', () {
      const type = ApplianceType(
        id: 't', displayName: 'T', modelPrefix: 'TT',
        iconPath: '', modelCount: 5, controls: [],
      );
      expect(type.modelNumbers.length, 5);
    });
  });

  group('ApplianceType — matchesModel', () {
    test('empty string returns true (legacy fan)', () {
      expect(_ceilingFan.matchesModel(''), isTrue);
    });

    test('matching TN-CF-07 returns true', () {
      expect(_ceilingFan.matchesModel('TN-CF-07'), isTrue);
    });

    test('matching TN-CF-01 returns true', () {
      expect(_ceilingFan.matchesModel('TN-CF-01'), isTrue);
    });

    test('different prefix TN-TF-01 returns false', () {
      expect(_ceilingFan.matchesModel('TN-TF-01'), isFalse);
    });

    test('matching is case-insensitive', () {
      expect(_ceilingFan.matchesModel('tn-cf-03'), isTrue);
    });

    test('prefix without trailing hyphen returns false', () {
      // 'TN-CF' does not start with 'TN-CF-'
      expect(_ceilingFan.matchesModel('TN-CF'), isFalse);
    });

    test('unrelated string returns false', () {
      expect(_ceilingFan.matchesModel('GENERIC-FAN'), isFalse);
    });
  });

  group('ApplianceType — hasControl', () {
    test('returns true for a declared control', () {
      expect(_ceilingFan.hasControl('speed'), isTrue);
      expect(_ceilingFan.hasControl('lighting'), isTrue);
    });

    test('returns false for an undeclared control', () {
      expect(_ceilingFan.hasControl('temperature'), isFalse);
    });

    test('returns false for empty string', () {
      expect(_ceilingFan.hasControl(''), isFalse);
    });

    test('exhaust fan has no mode control (modelPrefix EF)', () {
      const ef = ApplianceType(
        id: 'exhaust_fan', displayName: 'Exhaust Fan',
        modelPrefix: 'EF', iconPath: '', modelCount: 5, controls: ['speed'],
      );
      expect(ef.hasControl('mode'), isFalse);
      expect(ef.hasControl('speed'), isTrue);
    });
  });

  group('ApplianceCategory — construction', () {
    test('stores id and displayName', () {
      const cat = ApplianceCategory(
        id: 'fans', displayName: 'Fans', pluralLabel: 'Fans',
        iconPath: 'assets/icons/fans.png', types: [_ceilingFan],
      );
      expect(cat.id, 'fans');
      expect(cat.displayName, 'Fans');
    });

    test('comingSoon defaults to false', () {
      const cat = ApplianceCategory(
        id: 'x', displayName: 'X', pluralLabel: 'Xs',
        iconPath: '', types: [],
      );
      expect(cat.comingSoon, isFalse);
    });

    test('comingSoon can be set to true', () {
      const cat = ApplianceCategory(
        id: 'x', displayName: 'X', pluralLabel: 'Xs',
        iconPath: '', types: [], comingSoon: true,
      );
      expect(cat.comingSoon, isTrue);
    });

    test('pluralLabel stored verbatim', () {
      const cat = ApplianceCategory(
        id: 'water_filtration',
        displayName: 'Water Filtration',
        pluralLabel: 'Water Filters',
        iconPath: '',
        types: [],
      );
      expect(cat.pluralLabel, 'Water Filters');
    });

    test('types list is accessible', () {
      const cat = ApplianceCategory(
        id: 'fans', displayName: 'Fans', pluralLabel: 'Fans',
        iconPath: '', types: [_ceilingFan],
      );
      expect(cat.types, hasLength(1));
      expect(cat.types.first.id, 'ceiling_fan');
    });
  });

  group('ApplianceType.fromYaml', () {
    test('parses all required fields', () {
      final yaml = <Object?, Object?>{
        'id': 'ceiling_fan',
        'displayName': 'Ceiling Fan',
        'modelPrefix': 'CF',
        'icon': 'assets/icons/ceiling_fan.png',
        'modelCount': 21,
        'controls': <Object?>['speed', 'mode'],
      };
      final type = ApplianceType.fromYaml(yaml);
      expect(type.id, 'ceiling_fan');
      expect(type.displayName, 'Ceiling Fan');
      expect(type.modelPrefix, 'CF');
      expect(type.modelCount, 21);
      expect(type.controls, ['speed', 'mode']);
    });

    test('modelCount defaults to 21 when absent', () {
      final yaml = <Object?, Object?>{
        'id': 't', 'displayName': 'T', 'modelPrefix': 'T', 'icon': '',
      };
      expect(ApplianceType.fromYaml(yaml).modelCount, 21);
    });

    test('controls defaults to empty list when absent', () {
      final yaml = <Object?, Object?>{
        'id': 't', 'displayName': 'T', 'modelPrefix': 'T', 'icon': '',
      };
      expect(ApplianceType.fromYaml(yaml).controls, isEmpty);
    });
  });

  group('ApplianceCategory.fromYaml', () {
    test('parses category and nested types', () {
      final yaml = <Object?, Object?>{
        'id': 'fans',
        'displayName': 'Fans',
        'icon': 'assets/icons/fans.png',
        'types': <Object?>[
          <Object?, Object?>{
            'id': 'ceiling_fan', 'displayName': 'Ceiling Fan',
            'modelPrefix': 'CF', 'icon': '',
          },
        ],
      };
      final cat = ApplianceCategory.fromYaml(yaml);
      expect(cat.id, 'fans');
      expect(cat.types.length, 1);
      expect(cat.types.first.id, 'ceiling_fan');
    });

    test('pluralLabel defaults to displayName + s', () {
      final yaml = <Object?, Object?>{
        'id': 'x', 'displayName': 'Fan', 'icon': '',
      };
      expect(ApplianceCategory.fromYaml(yaml).pluralLabel, 'Fans');
    });

    test('pluralLabel override is applied', () {
      final yaml = <Object?, Object?>{
        'id': 'water_filtration',
        'displayName': 'Water Filtration',
        'pluralLabel': 'Water Filters',
        'icon': '',
      };
      expect(ApplianceCategory.fromYaml(yaml).pluralLabel, 'Water Filters');
    });

    test('comingSoon defaults to false', () {
      final yaml = <Object?, Object?>{
        'id': 'x', 'displayName': 'X', 'icon': '',
      };
      expect(ApplianceCategory.fromYaml(yaml).comingSoon, isFalse);
    });

    test('comingSoon: true is parsed', () {
      final yaml = <Object?, Object?>{
        'id': 'x', 'displayName': 'X', 'icon': '', 'comingSoon': true,
      };
      expect(ApplianceCategory.fromYaml(yaml).comingSoon, isTrue);
    });
  });
}
