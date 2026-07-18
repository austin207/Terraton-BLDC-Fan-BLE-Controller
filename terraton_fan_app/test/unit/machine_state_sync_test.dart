// test/unit/machine_state_sync_test.dart
//
// The Machine-State retrieval engine, exercised as a pure state machine under
// fake_async. These encode the trust rules the six failed reconnect fixes
// never nailed down:
//   * a state applies only when two consecutively assembled replies agree
//     ACROSS a query boundary — a stale BLE60 backlog burst, however many
//     replies it contains, can never confirm itself;
//   * a reply that is never confirmed is never applied — a timeout leaves the
//     UI blank instead of promoting the suspect reply to truth (the old 3 s
//     fallback did the opposite, the most plausible reading of the 3.0.26
//     field failure);
//   * outside a session, one assembled reply applies directly (steady state
//     has no backlog).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/machine_state_sync.dart';

class _Harness {
  final polls = <bool>[]; // vendorChecksum flag per poll the engine sent
  final applied = <(MachineStateTuple, String)>[];
  final logs = <String>[];
  late final MachineStateSync sync;

  _Harness() {
    sync = MachineStateSync(
      sendPoll: polls.add,
      apply: (t, via) => applied.add((t, via)),
      log: logs.add,
    );
  }
}

// Reply shorthands.
const _on4h = [
  SyncFrame.power(true),
  SyncFrame.mode('smart'),
  SyncFrame.timer(0x04),
];
const _offStale = [
  SyncFrame.power(false),
  SyncFrame.speed(5),
  SyncFrame.timer(0x00),
];

void main() {
  group('MachineStateSync — session agreement', () {
    test('two agreeing replies across a query boundary apply exactly once', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');
        expect(h.polls.length, 1);

        h.sync.addFrames(_on4h); // candidate — never applied alone
        expect(h.applied, isEmpty);
        // The engine polls again immediately to confirm fast.
        expect(h.polls.length, 2);

        h.sync.addFrames(_on4h); // answers the confirm poll → agreement
        expect(h.applied.length, 1);
        final (t, via) = h.applied.single;
        expect(t.power, true);
        expect(t.mode, 'smart');
        expect(t.timer, 0x04);
        expect(via, contains('agreement'));
        expect(h.sync.engaged, false); // session over
      });
    });

    test('a backlog flush of two identical stale replies in ONE chunk cannot '
        'self-confirm', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        // The BLE60 flushes its buffered UART backlog as one burst: two full
        // stale OFF replies arrive in a single notification. Same query
        // sequence → agreement is impossible no matter how many there are.
        h.sync.addFrames([..._offStale, ..._offStale]);
        expect(h.applied, isEmpty);

        // The genuine state then confirms normally.
        h.sync.addFrames(_on4h);
        expect(h.applied, isEmpty); // contradicts the stale candidate
        h.sync.addFrames(_on4h);
        expect(h.applied.length, 1);
        expect(h.applied.single.$1.power, true);
        expect(h.applied.single.$1.mode, 'smart');
      });
    });

    test('stale OFF then genuine twice — the OFF is never applied', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        h.sync.addFrames(_offStale); // candidate
        h.sync.addFrames(_on4h);     // contradicts → replaces candidate
        h.sync.addFrames(_on4h);     // agrees → applied

        expect(h.applied.length, 1);
        expect(h.applied.single.$1.power, true);
        expect(h.applied.every((e) => e.$1.power), true,
            reason: 'the stale OFF must never reach apply');
      });
    });

    test('no agreement before the session times out → NOTHING applied', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        h.sync.addFrames(_offStale); // lone suspect reply, never confirmed
        async.elapse(MachineStateSync.sessionTimeout +
            const Duration(seconds: 1));

        // The old 3 s fallback applied the held reply here — wiping Smart +
        // the timer with unconfirmed state. The rewrite refuses: blank UI,
        // baseline untouched, status poll keeps running.
        expect(h.applied, isEmpty);
        expect(h.sync.engaged, false);
        expect(h.polls.length, lessThanOrEqualTo(MachineStateSync.maxSessionPolls));
      });
    });

    test('poll frames alternate lab and vendor checksums', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');
        async.elapse(const Duration(seconds: 10)); // exhaust the retry cadence

        expect(h.polls.length, MachineStateSync.maxSessionPolls);
        for (var i = 0; i < h.polls.length; i++) {
          // Poll #1 (index 0) is the lab-verified frame; every second one is
          // the vendor-formula variant.
          expect(h.polls[i], (i + 1).isEven,
              reason: 'poll ${i + 1} used the wrong checksum variant');
        }
      });
    });

    test('reply split across chunks assembles via the debounce; a timer-less '
        'confirming reply keeps the candidate timer', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        // First reply arrives torn: power in one chunk, mode later, no timer.
        h.sync.addFrames(const [SyncFrame.power(true)]);
        h.sync.addFrames(const [SyncFrame.mode('smart')]);
        expect(h.applied, isEmpty);
        async.elapse(MachineStateSync.assembleDebounce +
            const Duration(milliseconds: 50)); // finalize {ON, smart, -}

        // Second reply carries the timer too; shapes agree (timer neutral).
        h.sync.addFrames(_on4h);
        expect(h.applied.length, 1);
        expect(h.applied.single.$1.timer, 0x04);
      });
    });

    test('a bare ON (booting MCU) is discarded, never a candidate', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        h.sync.addFrames(const [SyncFrame.power(true)]);
        async.elapse(MachineStateSync.assembleDebounce +
            const Duration(milliseconds: 50));
        expect(h.applied, isEmpty);

        // Real state then confirms normally.
        h.sync.addFrames(_on4h);
        h.sync.addFrames(_on4h);
        expect(h.applied.length, 1);
      });
    });

    test('a status-shaped chunk (telemetry, no 0x22) cannot tear a partial '
        'reply or null its mode', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');

        // Machine-State reply arrives split: power + mode, timer in flight.
        h.sync.addFrames(const [SyncFrame.power(true), SyncFrame.mode('smart')]);
        // A 4-frame status poll interleaves: power + stored speed + watts/RPM.
        h.sync.addFrames(
          const [SyncFrame.power(true), SyncFrame.speed(5)],
          chunkHasTelemetry: true,
        );
        // The reply's timer frame finally lands → the partial completes.
        h.sync.addFrames(const [SyncFrame.timer(0x04)]);

        // Candidate must be {ON, smart, 4h} — not torn into {ON, speed 5}.
        h.sync.addFrames(_on4h); // confirm
        expect(h.applied.length, 1);
        expect(h.applied.single.$1.mode, 'smart');
        expect(h.applied.single.$1.speed, isNull);
      });
    });

    test('user action cancels the session; later frames are ignored', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');
        h.sync.addFrames(_offStale);
        h.sync.cancel('user command');
        expect(h.sync.engaged, false);

        h.sync.addFrames(_on4h); // not engaged → no-op
        expect(h.applied, isEmpty);
      });
    });
  });

  group('MachineStateSync — steady-state single poll', () {
    test('requestOnce applies the first assembled reply immediately', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.requestOnce('test');
        expect(h.polls, [false]); // lab-verified frame only

        h.sync.addFrames(_on4h);
        expect(h.applied.length, 1);
        expect(h.applied.single.$2, contains('single reply'));
        expect(h.sync.engaged, false);
      });
    });

    test('an expired await window applies nothing', () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.requestOnce('test');
        async.elapse(MachineStateSync.awaitReplyWindow +
            const Duration(milliseconds: 100));
        expect(h.sync.engaged, false);

        h.sync.addFrames(_on4h); // too late — engine idle
        expect(h.applied, isEmpty);
      });
    });

    test('requestOnce during a session is a no-op (the session polls cover it)',
        () {
      fakeAsync((async) {
        final h = _Harness();
        h.sync.startSession('test');
        final pollsBefore = h.polls.length;
        h.sync.requestOnce('interleaved');
        expect(h.polls.length, pollsBefore);
        expect(h.sync.phase, SyncPhase.session);
      });
    });
  });
}
