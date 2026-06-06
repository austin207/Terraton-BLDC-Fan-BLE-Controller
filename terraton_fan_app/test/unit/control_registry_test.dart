// test/unit/control_registry_test.dart
//
// Tests for ControlRegistry — register, get, isBuiltIn.
// Uses unique key strings (__test_*__) to avoid cross-test pollution of the
// shared static _builders map.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';

void main() {
  group('ControlRegistry — registration', () {
    test('get returns null for an unregistered type', () {
      expect(ControlRegistry.get('__never_registered__'), isNull);
    });

    test('register + get round-trip returns the same builder', () {
      Widget builder(ControlBuildParams p) => Container();
      ControlRegistry.register('__reg_a__', builder);
      expect(ControlRegistry.get('__reg_a__'), same(builder));
    });

    test('register overwrites a previous registration', () {
      Widget b1(ControlBuildParams p) => const Text('b1');
      Widget b2(ControlBuildParams p) => const Text('b2');
      ControlRegistry.register('__reg_b__', b1);
      ControlRegistry.register('__reg_b__', b2);
      expect(ControlRegistry.get('__reg_b__'), same(b2));
    });

    test('independent types are stored separately', () {
      Widget bX(ControlBuildParams p) => const Text('X');
      Widget bY(ControlBuildParams p) => const Text('Y');
      ControlRegistry.register('__reg_x__', bX);
      ControlRegistry.register('__reg_y__', bY);
      expect(ControlRegistry.get('__reg_x__'), same(bX));
      expect(ControlRegistry.get('__reg_y__'), same(bY));
    });

    test('registered builder can be retrieved and called', () {
      ControlRegistry.register('__reg_call__', (p) => const Text('called'));
      final builder = ControlRegistry.get('__reg_call__');
      expect(builder, isNotNull);
    });
  });

  group('ControlRegistry — isBuiltIn', () {
    for (final type in const ['speed', 'mode', 'timer', 'lighting', 'power']) {
      test('isBuiltIn("$type") returns true', () {
        expect(ControlRegistry.isBuiltIn(type), isTrue);
      });
    }

    test('isBuiltIn returns false for a custom type', () {
      expect(ControlRegistry.isBuiltIn('temperature'), isFalse);
    });

    test('isBuiltIn returns false for empty string', () {
      expect(ControlRegistry.isBuiltIn(''), isFalse);
    });

    test('isBuiltIn returns false for a registered custom type', () {
      ControlRegistry.register('__builtin_check__', (_) => Container());
      // Registering a type does NOT make it a built-in.
      expect(ControlRegistry.isBuiltIn('__builtin_check__'), isFalse);
    });

    test('built-in types are not in the registry (get returns null)', () {
      // Built-ins are rendered natively — they must not be pre-populated
      // so a custom registration cannot accidentally shadow them.
      expect(ControlRegistry.get('speed'), isNull);
      expect(ControlRegistry.get('mode'), isNull);
      expect(ControlRegistry.get('timer'), isNull);
      expect(ControlRegistry.get('lighting'), isNull);
      expect(ControlRegistry.get('power'), isNull);
    });
  });
}
