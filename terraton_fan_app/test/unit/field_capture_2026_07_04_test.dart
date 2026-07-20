// test/unit/field_capture_2026_07_04_test.dart
//
// A real field tester `ConnectionLogService` capture (2026-07-04, fan MAC
// 00:04:3E:8B:03:24) spanning FOUR separate connect/disconnect cycles,
// including one failed connect attempt between cycles 3 and 4. Unlike the
// synthetic captures in connection_log_replay_test.dart (single connect, no
// reconnect), this exercises the EV-segmentation fix in
// test/helpers/connection_log_replay.dart: each `EV connected …` line must
// reset the frame assembler and start a fresh MachineStateSync session, and
// each `EV disconnect…` / `EV connect failed…` line must cancel any
// in-flight session — otherwise the replay would (wrongly) treat all four
// cycles as one continuous session, corrupting the query-boundary bookkeeping
// the agreement rule depends on.
//
// The capture's final line is genuinely truncated mid-frame (the tester's
// paste cut off) — that's real field data, not a mistake, and the harness
// (via FrameStreamAssembler's tail-carry) must tolerate it gracefully rather
// than crashing or throwing.
//
// Ground truth for what each segment actually resolves to was NOT
// hand-derived and then matched — it was observed by running
// replayConnectionLog against this exact capture and reading the emitted
// `MachineStateSync` log lines (`MS` in a real Connection Log). The
// assertions below encode that OBSERVED, engine-produced behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';

import '../helpers/connection_log_replay.dart';

const _capture = r'''
[2026-07-04T16:48:05.736571] EV connect 00:04:3E:8B:03:24 attempt 1/3
[2026-07-04T16:48:07.864516] EV connected 00:04:3E:8B:03:24 | write char: found bf8796f1 | NoResp+WithResp | svcs:[1800, 1801, 180a, 26cc3fc0]
[2026-07-04T16:48:07.864866] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:07.865702] TX 55 AA 00 08 01 00 08
[2026-07-04T16:48:07.902155] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 05 10 55 AA 07 22 01 00 29
[2026-07-04T16:48:09.912997] TX 55 AA 06 21 01 04 2B
[2026-07-04T16:48:10.010534] RX 55 AA 07 21 01 04 2C
[2026-07-04T16:48:10.865952] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:10.936683] RX 55 AA 07 23 01 18 42 55 AA 07 24 02 01 68 94
[2026-07-04T16:48:12.471249] TX 55 AA 06 22 01 02 2A
[2026-07-04T16:48:12.593266] RX 55 AA 07 22 01 02 2B
[2026-07-04T16:48:13.865685] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:13.954015] RX 55 AA 07 23 01 1B 45 55 AA 07 24 02 01 77 A3
[2026-07-04T16:48:14.163856] EV disconnect() requested
[2026-07-04T16:48:22.492291] EV connect 00:04:3E:8B:03:24 attempt 1/3
[2026-07-04T16:48:24.055317] EV connected 00:04:3E:8B:03:24 | write char: found bf8796f1 | NoResp+WithResp | svcs:[1800, 1801, 180a, 26cc3fc0]
[2026-07-04T16:48:24.056602] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:24.059267] TX 55 AA 00 08 01 00 08
[2026-07-04T16:48:24.147794] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 06 11 55 AA 07 22 01 00 29
[2026-07-04T16:48:24.148745] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:25.560529] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:25.655580] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 06 11 55 AA 07 22 01 00 29
[2026-07-04T16:48:27.059191] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:27.171333] RX 55 AA 07 23 01 1B 45 55 AA 07 24 02 01 81 AD
[2026-07-04T16:48:29.458884] TX 55 AA 06 22 01 04 2C
[2026-07-04T16:48:29.559254] RX 55 AA 07 22 01 04 2D
[2026-07-04T16:48:30.057507] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:30.144337] RX 55 AA 07 23 01 1B 45 55 AA 07 24 02 01 82 AE
[2026-07-04T16:48:32.597627] EV disconnect() requested
[2026-07-04T16:48:35.175327] EV connect 00:04:3E:8B:03:24 attempt 1/3
[2026-07-04T16:48:37.071475] EV connected 00:04:3E:8B:03:24 | write char: found bf8796f1 | NoResp+WithResp | svcs:[1800, 1801, 180a, 26cc3fc0]
[2026-07-04T16:48:37.072399] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:37.074872] TX 55 AA 00 08 01 00 08
[2026-07-04T16:48:37.164202] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 06 11 55 AA 07 22 01 00 29
[2026-07-04T16:48:37.165231] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:38.576150] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:40.073531] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:40.080720] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:40.194145] RX 55 AA 07 23 01 1C 46 55 AA 07 24 02 01 88 B4
[2026-07-04T16:48:43.073470] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:43.160144] RX 55 AA 07 23 01 1C 46 55 AA 07 24 02 01 82 AE
[2026-07-04T16:48:44.374189] RX 55 AA 07 22 01 04 2D
[2026-07-04T16:48:46.073468] TX 55 AA 00 00 01 00 00
[2026-07-04T16:48:46.177082] RX 55 AA 07 23 01 1B 45 55 AA 07 24 02 01 80 AC
[2026-07-04T16:48:47.207152] EV disconnect() requested
[2026-07-04T16:48:47.998764] EV connect 00:04:3E:8B:03:24 attempt 1/3
[2026-07-04T16:48:48.374976] EV connect failed: attempt 1 failed: PlatformException(requestMtu, device is disconnected, null, null)
[2026-07-04T16:48:55.008259] EV connect 00:04:3E:8B:03:24 attempt 2/3
[2026-07-04T16:48:57.328220] EV connected 00:04:3E:8B:03:24 | write char: found bf8796f1 | NoResp+WithResp | svcs:[1800, 1801, 180a, 26cc3fc0]
[2026-07-04T16:48:57.328945] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:57.331364] TX 55 AA 00 08 01 00 08
[2026-07-04T16:48:57.392501] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 06 11 55 AA 07 22 01 00 29
[2026-07-04T16:48:57.393073] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:58.832709] TX 55 AA 00 01 01 00 01
[2026-07-04T16:48:58.906290] RX 55 AA 07 02 01 01 0A 55 AA 07 04 01 06 11 55 AA 07 22 01 00 29
[2026-07-04T16:49:00.329482] TX 55 AA 00 00 01 00 00
[2026-07-04T16:49:00.415662] RX 55 AA 07 23 01 1B 45 55 AA 07 24 02 01 84 B0
[2026-07-04T16:49:00.503773] TX 55 AA 06 21 01 02 29
[2026-07-04T16:49:00.610628] RX 55 AA 07 21 01 0
''';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  test(
      'field capture 2026-07-04 (4 reconnect cycles): each EV-connected line '
      'starts an independent session, and the truncated trailing frame does '
      'not crash the replay', () {
    final result = replayConnectionLog(_capture);

    // The capture contains exactly 4 "EV connected …" lines (successful
    // connections — distinct from the "EV connect … attempt N/3" attempt
    // announcements, of which there are 5). Each must start its own fresh
    // session. Before the EV-segmentation fix, the harness ignored EV lines
    // entirely and ran the whole capture as ONE unbroken session — that
    // would merge all 4 cycles' query-boundary bookkeeping together, which
    // is exactly the bug this fix corrects.
    final sessionStarts =
        result.logs.where((l) => l == 'session start (connect)').toList();
    expect(sessionStarts.length, 4,
        reason: 'each of the capture\'s 4 "EV connected" lines must start '
            'its own independent MachineStateSync session; a merged single '
            'session across all 4 reconnects is the bug the EV-segmentation '
            'fix corrects');

    // A session left with an unresolved candidate when the link drops must
    // be explicitly cancelled (not silently abandoned) so nothing leaks into
    // the next connect. Segments 1 and 3 below both disconnect mid-session
    // with an unconfirmed candidate still pending, so this must fire twice;
    // segments 2 and 4 both resolve (apply) before their disconnect, which
    // already tears the session down, so cancel() is a no-op there and logs
    // nothing (see the per-segment checks below).
    final cancelled =
        result.logs.where((l) => l == 'cancelled (disconnect)').toList();
    expect(cancelled.length, 2,
        reason: 'segments 1 and 3 disconnect while a candidate is still '
            'unconfirmed and must be cancelled explicitly; segments 2 and 4 '
            'already resolved via agreement before their disconnect, so no '
            'cancel log line is expected for those two');

    // No session in this capture ever reaches its 12 s timeout — every
    // segment is short enough that its outcome (agreement or disconnect) is
    // decided first. This confirms the EV segmentation is what resolves each
    // segment, not the replay's blanket trailing timeout.
    expect(result.logs.any((l) => l.contains('session expired')), isFalse,
        reason: 'every one of the 4 segments is resolved by either a '
            'confirmed agreement or an EV disconnect before the 12 s session '
            'timeout would fire — none should time out');

    // --- Segment 1: 16:48:07 connect -> 16:48:14 disconnect -----------------
    // Only one full (power + speed/mode + timer) reply ever arrives: the
    // connect-time reply reporting power ON / speed 5 / timer off. The
    // live "Smart mode" tap (TX at 09.912997) and "2h timer" tap (TX at
    // 12.471249) that follow land as bare mode-only / timer-only echoes with
    // NO power byte. By MachineStateSync's own documented rule ("Orphan
    // frame [2]/timer with no power frame ... never applicable on its
    // own"), such fragments can never become or confirm a candidate — so
    // nothing from segment 1 is ever applied, and the live mode/timer taps
    // are invisible to the sync engine while a session is in flight.
    expect(
      result.logs.any((l) =>
          l.contains('=> candidate (first reply is never applied alone)') &&
          l.contains('speed:5')),
      isTrue,
      reason: 'segment 1\'s only full reply (power on, speed 5, timer off) '
          'must become a candidate, never an immediate apply — a single '
          'reply is never trusted alone',
    );
    expect(
      result.logs.any((l) =>
          l.contains('discard fragment') &&
          l.contains('mode:smart') &&
          l.contains('no power frame')),
      isTrue,
      reason: 'the live "Smart mode" tap\'s echo (mode-only, no power byte) '
          'must be discarded as an orphan fragment rather than confirming '
          'or replacing the speed-5 candidate',
    );
    expect(
      result.logs.any((l) =>
          l.contains('discard fragment') &&
          l.contains('timer:2') &&
          l.contains('no power frame')),
      isTrue,
      reason: 'the live "2h timer" tap\'s echo (timer-only, no power byte) '
          'must likewise be discarded, not treated as confirmation',
    );

    // --- Segment 2: 16:48:24 connect -> 16:48:32 disconnect -----------------
    // Two full replies arrive, independently queried (a state-query TX sits
    // between them at 24.148745 and 25.560529), both reporting power ON /
    // speed 6 / timer off. This is a genuine two-reply agreement across a
    // real query boundary — proof the engine applies confirmed state and
    // isn't just being reflexively conservative.
    expect(
      result.logs.any((l) =>
          l.contains('agrees with candidate') &&
          l.contains('=> applied') &&
          l.contains('speed:6')),
      isTrue,
      reason: 'segment 2\'s second reply (power on, speed 6, timer off) '
          'independently agrees with the first across a real query boundary '
          '(a state-query TX was sent between them) and must apply',
    );

    // --- Segment 3: 16:48:37 connect -> 16:48:47 disconnect -----------------
    // Exactly one full reply arrives (power ON / speed 6 / timer off, at
    // 37.164202). A later timer-only fragment (44.374189, no power byte)
    // cannot confirm it. No second full reply ever arrives before the link
    // drops at 47.207152 — so segment 3 must resolve to "nothing applied",
    // via an explicit cancel on disconnect (not a session timeout). This is
    // the segment the field-bug report submitter was least sure about.
    expect(
      result.logs.any((l) =>
          l.contains('=> candidate (first reply is never applied alone)') &&
          l.contains('speed:6') &&
          l.contains('q:21')),
      isTrue,
      reason: 'segment 3\'s only full reply becomes a candidate (query '
          'stamp 21, distinguishing it from segment 2\'s and segment 4\'s '
          'candidates in the shared, monotonically increasing query '
          'sequence)',
    );
    expect(
      result.logs.any((l) =>
          l.contains('discard fragment') &&
          l.contains('timer:4') &&
          l.contains('no power frame')),
      isTrue,
      reason: 'the later timer-only echo in segment 3 has no power byte and '
          'must be discarded as an orphan fragment rather than confirming '
          'the pending speed-6 candidate',
    );

    // --- Segment 4: 16:48:57 connect, capture ends mid-reply at 16:49:00 ---
    // Same two-reply-agreement shape as segment 2: two independently-queried
    // full replies (57.392501 and 58.906290, a state-query TX sits between
    // them) both report power ON / speed 6 / timer off, and the trailing
    // line (a truncated mode-frame RX cut off mid-byte) must not crash the
    // replay or corrupt this already-resolved outcome.
    expect(
      result.logs.any((l) =>
          l.contains('agrees with candidate') &&
          l.contains('=> applied') &&
          l.contains('speed:6') &&
          l.contains('q:38')),
      isTrue,
      reason: 'segment 4\'s second reply (query stamp 38) agrees with its '
          'candidate (query stamp 34) across a real query boundary and must '
          'apply, exactly like segment 2 — and the capture\'s truncated '
          'final line must not prevent or corrupt this',
    );

    // --- Overall: exactly 2 applies across all 4 segments -------------------
    // Segments 1 and 3 never apply (single unconfirmed reply each); segments
    // 2 and 4 each apply once via genuine two-reply agreement. Every applied
    // tuple reports the SAME real state (power on, speed 6, no active mode,
    // timer off) because that was genuinely the fan's state at both of those
    // reconnects — not because the engine is just echoing one stale value.
    expect(result.applied.length, 2,
        reason: 'only segments 2 and 4 ever reach two-reply agreement; '
            'segments 1 and 3 must contribute nothing to result.applied');

    final (tuple2, via2) = result.applied[0];
    expect(tuple2.power, isTrue, reason: 'segment 2 apply: fan was on');
    expect(tuple2.speed, 6, reason: 'segment 2 apply: speed gear 6');
    expect(tuple2.mode, isNull, reason: 'segment 2 apply: no active mode');
    expect(tuple2.timer, 0, reason: 'segment 2 apply: timer off');
    expect(via2, 'session agreement (2 replies)',
        reason: 'segment 2 applied via genuine two-reply session agreement, '
            'not the steady-state single-reply path');

    final (tuple4, via4) = result.applied[1];
    expect(tuple4.power, isTrue, reason: 'segment 4 apply: fan was on');
    expect(tuple4.speed, 6, reason: 'segment 4 apply: speed gear 6');
    expect(tuple4.mode, isNull, reason: 'segment 4 apply: no active mode');
    expect(tuple4.timer, 0, reason: 'segment 4 apply: timer off');
    expect(via4, 'session agreement (2 replies)',
        reason: 'segment 4 applied via genuine two-reply session agreement, '
            'same as segment 2');
  });
}
