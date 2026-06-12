// test/unit/fan_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

void main() {
  FanState baseState() => FanState()
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
      final a = baseState();
      final b = a.copyWith();
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
    });

    test('updates speed', () {
      final s = baseState().copyWith(speed: 6);
      expect(s.speed, 6);
      expect(s.deviceId, 'dev1'); // unchanged
    });

    test('updates isPowered to false', () {
      expect(baseState().copyWith(isPowered: false).isPowered, isFalse);
    });

    test('updates isBoost to true', () {
      expect(baseState().copyWith(isBoost: true).isBoost, isTrue);
    });

    test('sets activeMode to a new non-null value via getter', () {
      expect(baseState().copyWith(activeMode: () => 'nature').activeMode, 'nature');
    });

    test('clears activeMode to null via getter', () {
      expect(baseState().copyWith(activeMode: () => null).activeMode, isNull);
    });

    test('omitting activeMode preserves existing value', () {
      // No getter passed → old value kept.
      expect(baseState().copyWith(speed: 1).activeMode, 'smart');
    });

    test('sets activeTimerCode via getter', () {
      expect(baseState().copyWith(activeTimerCode: () => 4).activeTimerCode, 4);
    });

    test('clears activeTimerCode to null via getter', () {
      expect(baseState().copyWith(activeTimerCode: () => null).activeTimerCode, isNull);
    });

    test('sets lastWatts via getter', () {
      expect(baseState().copyWith(lastWatts: () => 80).lastWatts, 80);
    });

    test('clears lastWatts to null via getter', () {
      expect(baseState().copyWith(lastWatts: () => null).lastWatts, isNull);
    });

    test('sets lastRpm via getter', () {
      expect(baseState().copyWith(lastRpm: () => 500).lastRpm, 500);
    });

    test('clears lastRpm to null via getter', () {
      expect(baseState().copyWith(lastRpm: () => null).lastRpm, isNull);
    });

    test('preserves id and deviceId through copy', () {
      final a = baseState()..id = 7;
      final b = a.copyWith(speed: 2);
      expect(b.id, 7);
      expect(b.deviceId, 'dev1');
    });
  });

  // ── Equality ────────────────────────────────────────────────────────────────

  group('FanState equality', () {
    test('two identical instances are equal', () {
      expect(baseState(), equals(baseState()));
    });

    test('not equal when speed differs', () {
      expect(baseState().copyWith(speed: 1), isNot(equals(baseState())));
    });

    test('not equal when isPowered differs', () {
      expect(baseState().copyWith(isPowered: false), isNot(equals(baseState())));
    });

    test('not equal when isBoost differs', () {
      expect(baseState().copyWith(isBoost: true), isNot(equals(baseState())));
    });

    test('not equal when activeMode differs', () {
      expect(baseState().copyWith(activeMode: () => null), isNot(equals(baseState())));
    });

    test('not equal when activeTimerCode differs', () {
      expect(baseState().copyWith(activeTimerCode: () => null), isNot(equals(baseState())));
    });

    test('not equal when lastWatts differs', () {
      expect(baseState().copyWith(lastWatts: () => null), isNot(equals(baseState())));
    });

    test('not equal when lastRpm differs', () {
      expect(baseState().copyWith(lastRpm: () => null), isNot(equals(baseState())));
    });

    test('not equal when deviceId differs', () {
      final other = baseState()..deviceId = 'dev2';
      expect(baseState(), isNot(equals(other)));
    });
  });

  // ── hashCode ────────────────────────────────────────────────────────────────

  group('FanState.hashCode', () {
    test('equal instances have the same hashCode', () {
      expect(baseState().hashCode, equals(baseState().hashCode));
    });

    test('different speed → different hashCode', () {
      expect(baseState().copyWith(speed: 1).hashCode, isNot(equals(baseState().hashCode)));
    });

    test('different activeMode → different hashCode', () {
      final a = baseState().copyWith(activeMode: () => 'nature');
      expect(a.hashCode, isNot(equals(baseState().hashCode)));
    });
  });
}
