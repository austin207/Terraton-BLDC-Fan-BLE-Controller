// test/unit/write_queue_test.dart
//
// WriteQueue, exercised as a pure serialising/pacing chain under fake_async.
// These encode the properties the queue exists to guarantee (see
// lib/core/ble/write_queue.dart):
//   * two `unawaited(enqueue(...))` calls in one synchronous turn still land
//     on the wire in call order — this is what protects the documented
//     mode-frame-before-speed-frame ordering;
//   * consecutive writes are paced apart by `gap`, driven entirely by
//     `Future.delayed` so `fake_async` controls it deterministically;
//   * a throwing `send` is retried, and a permanent failure surfaces on its
//     own enqueue() future without stalling later frames;
//   * reset() drops the pending chain for a fresh BLE connection.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/write_queue.dart';

void main() {
  group('WriteQueue — ordering', () {
    test('order is preserved across un-awaited enqueues', () {
      fakeAsync((async) {
        final sent = <List<int>>[];
        final q = WriteQueue(send: (f) async => sent.add(f));

        // No await between these three calls — exactly the pattern used by
        // callers that fire a mode frame then a speed frame in one turn.
        unawaited(q.enqueue([1]));
        unawaited(q.enqueue([2]));
        unawaited(q.enqueue([3]));

        async.elapse(const Duration(seconds: 1));

        expect(
          sent,
          [
            [1],
            [2],
            [3],
          ],
          reason: 'call order must be fixed at enqueue() time — this is the '
              'property that protects the documented mode-frame-before-'
              'speed-frame ordering when callers never await between calls',
        );
      });
    });
  });

  group('WriteQueue — pacing', () {
    test('the gap is enforced between consecutive writes', () {
      fakeAsync((async) {
        final sent = <List<int>>[];
        const gap = Duration(milliseconds: 60);
        final q = WriteQueue(send: (f) async => sent.add(f), gap: gap);

        unawaited(q.enqueue([1]));
        unawaited(q.enqueue([2]));

        async.elapse(gap - const Duration(milliseconds: 1));
        expect(
          sent,
          [
            [1],
          ],
          reason: 'frame 2 must not reach the wire before the pacing gap '
              'has fully elapsed — the BLE60 can mishandle writes landing '
              'in the same connection event',
        );
        expect(
          async.elapsed,
          lessThan(gap),
          reason: 'the fake clock must confirm the gap has not yet elapsed '
              'for the assertion above to mean anything',
        );

        async.elapse(const Duration(milliseconds: 2));
        expect(
          sent,
          [
            [1],
            [2],
          ],
          reason: 'once the gap has elapsed the next queued frame must go '
              'out',
        );
        expect(
          async.elapsed,
          greaterThanOrEqualTo(gap),
          reason: 'the fake clock must confirm the gap has elapsed for the '
              'assertion above to mean anything',
        );
      });
    });
  });

  group('WriteQueue — retry', () {
    test(
        'a send that throws once then succeeds is retried once and the '
        'enqueue future completes normally', () {
      fakeAsync((async) {
        var attempts = 0;
        final q = WriteQueue(
          send: (f) async {
            attempts++;
            if (attempts == 1) {
              throw Exception('transient BLE60 write failure');
            }
          },
          retryDelay: const Duration(milliseconds: 40),
        );

        var completedOk = false;
        Object? error;
        unawaited(q.enqueue([7]).then(
          (_) => completedOk = true,
          onError: (Object e) => error = e,
        ));

        async.elapse(const Duration(seconds: 1));

        expect(
          attempts,
          2,
          reason: 'the default retries:1 means exactly one retry after the '
              'first throw — not zero, not more',
        );
        expect(
          completedOk,
          true,
          reason: 'a write that succeeds on retry must resolve the '
              "caller's enqueue() future normally",
        );
        expect(
          error,
          isNull,
          reason: 'a write that eventually succeeds must not surface an '
              'error to the caller',
        );
      });
    });
  });

  group('WriteQueue — permanent failure', () {
    test(
        'a permanently failing write rethrows on its own future and does '
        'not stall later frames', () {
      fakeAsync((async) {
        final sent = <List<int>>[];
        final q = WriteQueue(
          send: (f) async {
            if (f.first == 1) throw Exception('fan never acked frame 1');
            sent.add(f);
          },
          retryDelay: const Duration(milliseconds: 10),
          gap: const Duration(milliseconds: 10),
        );

        Object? error;
        unawaited(q.enqueue([1]).catchError((Object e) {
          error = e;
        }));
        unawaited(q.enqueue([2]));

        async.elapse(const Duration(seconds: 1));

        expect(
          error,
          isNotNull,
          reason: 'a write that fails every attempt must surface the error '
              'on its own enqueue() future so a caller can react — an '
              'unacknowledged write must not fail silently',
        );
        expect(
          sent,
          [
            [2],
          ],
          reason: 'one permanently failing frame must not stall the queue '
              '— the next enqueued frame must still reach the wire',
        );
      });
    });
  });

  group('WriteQueue — reset', () {
    test(
        'reset() clears the pending chain so a fresh enqueue is not gated '
        'on stuck prior work', () {
      fakeAsync((async) {
        final sent = <List<int>>[];
        final blocker = Completer<void>();
        final q = WriteQueue(
          send: (f) async {
            if (f.first == 1) {
              await blocker.future; // deliberately never completes
            }
            sent.add(f);
          },
          gap: const Duration(milliseconds: 10),
        );

        unawaited(q.enqueue([1]));
        async.elapse(const Duration(milliseconds: 5));
        expect(
          sent,
          isEmpty,
          reason: 'frame 1 is deliberately stuck on an unresolved send() to '
              'simulate a connection that never returns',
        );

        q.reset();
        unawaited(q.enqueue([2]));
        async.elapse(const Duration(seconds: 1));

        expect(
          sent,
          [
            [2],
          ],
          reason: 'a new BLE connection must be able to write immediately — '
              'reset() must drop the old chain rather than wait behind it '
              'forever',
        );
      });
    });
  });

  // This is the configuration BleServiceImpl actually constructs. Firmware
  // Reverse is `direction ^= 0x01` — a toggle — and writes go out
  // unacknowledged, so a throw is no proof the frame missed the wire. A retry
  // of a write that did land flips the fan back, which is exactly the
  // "Reverse did nothing" field report. Pacing is the fix; retrying is not
  // safe for this command set.
  group('WriteQueue — retries: 0 (the BleServiceImpl configuration)', () {
    test('a send that throws is attempted exactly once, never re-sent', () {
      fakeAsync((async) {
        var attempts = 0;
        final q = WriteQueue(
          send: (f) async {
            attempts++;
            throw Exception('write reported a failure after the frame went out');
          },
          retries: 0,
          gap: const Duration(milliseconds: 60),
        );

        Object? error;
        unawaited(q.enqueue([0x55, 0xAA, 0x06, 0x21, 0x01, 0x03, 0x2A])
            .catchError((Object e) => error = e));
        async.elapse(const Duration(seconds: 2));

        expect(
          attempts,
          1,
          reason: 'a re-sent Reverse frame toggles direction a second time — '
              'the fan ends up back where it started and the user sees '
              '"Reverse did nothing"',
        );
        expect(
          error,
          isNotNull,
          reason: 'the failure must still reach the caller; suppressing '
              'retries must not also suppress the error signal',
        );
      });
    });

    test('order and pacing are unaffected by disabling retries', () {
      fakeAsync((async) {
        final sentAt = <int>[];
        final q = WriteQueue(
          send: (f) async => sentAt.add(async.elapsed.inMilliseconds),
          retries: 0,
          gap: const Duration(milliseconds: 60),
        );

        // The exact shape of the Reverse → Nature tap: two frames enqueued in
        // one synchronous turn, neither awaited.
        unawaited(q.enqueue([0x21, 0x03]));
        unawaited(q.enqueue([0x21, 0x02]));

        async.elapse(const Duration(seconds: 1));

        expect(sentAt.length, 2, reason: 'both frames must reach the wire');
        expect(
          sentAt[1] - sentAt[0],
          greaterThanOrEqualTo(60),
          reason: 'the second frame must not share a connection interval with '
              'the first — that is what cost the Nature frame in the field',
        );
      });
    });
  });
}
