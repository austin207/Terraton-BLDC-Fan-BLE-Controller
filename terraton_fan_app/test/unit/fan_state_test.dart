// test/unit/fan_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

void main() {
  FanState _base() => FanState()
    ..deviceId        = 'dev1'
    ..speed           = 3
    ..isBoost         = false
    ..activeMode      = 'smart'
    ..activeTimerCode = 2
    ..isPowered       = true
    ..lastWatts       = 45
    ..lastRpm         = 300;

  // ── copyWith ────────────────────────────────────────────────────────────────

  group('FanState.copyWith', () {
    test('returns new instance with identical values when no args given', () {
      final a = _base();
      final b = a.copyWith();
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
    });

    test('updates speed', () {
      final s = _base().copyWith(speed: 6);
      expect(s.speed, 6);
      expect(s.deviceId, 'dev1'); // unchanged
    });

    test('updates isPowered to false', () {
      expect(_base().copyWith(isPowered: false).isPowered, isFalse);
    });

    test('updates isBoost to true', () {
      expect(_base().copyWith(isBoost: true).isBoost, isTrue);
    });

    test('sets activeMode to a new non-null value via getter', () {
      expect(_base().copyWith(activeMode: () => 'nature').activeMode, 'nature');
    });

    test('clears activeMode to null via getter', () {
      expect(_base().copyWith(activeMode: () => null).activeMode, isNull);
    });

    test('omitting activeMode preserves existing value', () {
      // No getter passed → old value kept.
      expect(_base().copyWith(speed: 1).activeMode, 'smart');
    });

    test('sets activeTimerCode via getter', () {
      expect(_base().copyWith(activeTimerCode: () => 4).activeTimerCode, 4);
    });

    test('clears activeTimerCode to null via getter', () {
      expect(_base().copyWith(activeTimerCode: () => null).activeTimerCode, isNull);
    });

    test('sets lastWatts via getter', () {
      expect(_base().copyWith(lastWatts: () => 80).lastWatts, 80);
    });

    test('clears lastWatts to null via getter', () {
      expect(_base().copyWith(lastWatts: () => null).lastWatts, isNull);
    });

    test('sets lastRpm via getter', () {
      expect(_base().copyWith(lastRpm: () => 500).lastRpm, 500);
    });

    test('clears lastRpm to null via getter', () {
      expect(_base().copyWith(lastRpm: () => null).lastRpm, isNull);
    });

    test('preserves id and deviceId through copy', () {
      final a = _base()..id = 7;
      final b = a.copyWith(speed: 2);
      expect(b.id, 7);
      expect(b.deviceId, 'dev1');
    });
  });

  // ── Equality ────────────────────────────────────────────────────────────────

  group('FanState equality', () {
    test('two identical instances are equal', () {
      expect(_base(), equals(_base()));
    });

    test('not equal when speed differs', () {
      expect(_base().copyWith(speed: 1), isNot(equals(_base())));
    });

    test('not equal when isPowered differs', () {
      expect(_base().copyWith(isPowered: false), isNot(equals(_base())));
    });

    test('not equal when isBoost differs', () {
      expect(_base().copyWith(isBoost: true), isNot(equals(_base())));
    });

    test('not equal when activeMode differs', () {
      expect(_base().copyWith(activeMode: () => null), isNot(equals(_base())));
    });

    test('not equal when activeTimerCode differs', () {
      expect(_base().copyWith(activeTimerCode: () => null), isNot(equals(_base())));
    });

    test('not equal when lastWatts differs', () {
      expect(_base().copyWith(lastWatts: () => null), isNot(equals(_base())));
    });

    test('not equal when lastRpm differs', () {
      expect(_base().copyWith(lastRpm: () => null), isNot(equals(_base())));
    });

    test('not equal when deviceId differs', () {
      final other = _base()..deviceId = 'dev2';
      expect(_base(), isNot(equals(other)));
    });
  });

  // ── hashCode ────────────────────────────────────────────────────────────────

  group('FanState.hashCode', () {
    test('equal instances have the same hashCode', () {
      expect(_base().hashCode, equals(_base().hashCode));
    });

    test('different speed → different hashCode', () {
      expect(_base().copyWith(speed: 1).hashCode, isNot(equals(_base().hashCode)));
    });

    test('different activeMode → different hashCode', () {
      final a = _base().copyWith(activeMode: () => 'nature');
      expect(a.hashCode, isNot(equals(_base().hashCode)));
    });
  });
}
