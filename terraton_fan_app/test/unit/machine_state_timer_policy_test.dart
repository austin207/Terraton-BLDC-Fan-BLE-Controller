// test/unit/machine_state_timer_policy_test.dart
//
// Covers timerFromStateReply's rule that a Machine-State reply's 0x22 field
// of exactly 0 is NEUTRAL, not a clear, unless the fan is OFF. See
// test/unit/field_capture_2026_07_04_test.dart for the field capture proving
// this firmware's state-reply timer field does not report an active timer
// (it echoes 22 01 04 twice for a live 4 h timer, yet every Get Motor State
// reply in the same capture answers 22 01 00 with no timer-off command ever
// sent) — the field bug this function fixes.
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/machine_state_timer_policy.dart';

void main() {
  group('timerFromStateReply', () {
    test('OFF fan with a named code clears — an OFF fan has no countdown',
        () {
      expect(
        timerFromStateReply(power: false, replyTimer: 0x04),
        0,
        reason: 'a fan reported OFF cannot have a countdown running, so the '
            'timer chip must clear even though the reply named a code',
      );
    });

    test('OFF fan with no 0x22 frame clears', () {
      expect(
        timerFromStateReply(power: false, replyTimer: null),
        0,
        reason: 'an OFF fan clears the timer regardless of whether the '
            'reply carried a 0x22 frame at all',
      );
    });

    test('ON fan with no 0x22 frame is neutral (pre-existing rule)', () {
      expect(
        timerFromStateReply(power: true, replyTimer: null),
        isNull,
        reason: 'a reply with no timer frame at all is already documented '
            'as neutral and must never clear a live countdown',
      );
    });

    test(
        'ON fan with explicit code 0 is neutral — the field bug this '
        'function fixes', () {
      expect(
        timerFromStateReply(power: true, replyTimer: 0),
        isNull,
        reason: 'this firmware\'s state-reply 0x22 field does not report an '
            'active timer (field_capture_2026_07_04_test.dart): every state '
            'reply answers with code 0 even while a 4 h timer is live and '
            'the firmware itself keeps re-reporting it, so an explicit zero '
            'from a state reply must not clear a live countdown',
      );
    });

    test('ON fan with a nonzero code applies that code', () {
      for (final code in [0x02, 0x04, 0x08]) {
        expect(
          timerFromStateReply(power: true, replyTimer: code),
          code,
          reason: 'a nonzero code is real information the firmware chose to '
              'report and must still apply, so a timer set from the IR '
              'remote is discovered on reconnect (code 0x${code.toRadixString(16)})',
        );
      }
    });
  });
}
