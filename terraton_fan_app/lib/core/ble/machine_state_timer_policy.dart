// lib/core/ble/machine_state_timer_policy.dart
//
// What a trusted Machine-State reply may do to the sleep-timer chip.
//
// Returns 0 to clear the countdown, a timer code to set it, or null for
// "no change".
//
// Why a reported code of 0 is NEUTRAL rather than a clear: this firmware's
// state-reply 0x22 field does not report an active timer. Evidence in
// test/unit/field_capture_2026_07_04_test.dart — the firmware echoes
// 22 01 04 when a 4 h timer is set and spontaneously re-reports 22 01 04
// seconds later, yet answers every Get Motor State reply with 22 01 00, and
// the capture contains no timer-off command. Treating that 0 as a clear is
// what destroyed the countdown on every reconnect. A missing 0x22 frame was
// already treated as neutral; this extends the same rule to the explicit zero
// the firmware actually sends.
int? timerFromStateReply({required bool power, required int? replyTimer}) {
  if (!power) return 0;
  if (replyTimer == null || replyTimer == 0) return null;
  return replyTimer;
}
