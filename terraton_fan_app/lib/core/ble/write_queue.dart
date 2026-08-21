// lib/core/ble/write_queue.dart
//
// The serialising, pacing write queue that fixes the BLE60's lost-second-
// frame failure mode: several control paths fire two writes back-to-back in
// one synchronous turn without awaiting (e.g. a mode frame then a speed
// frame). A field capture caught the mode frame echoed and the speed frame,
// issued ~400 us later, silently dropped. Writes also go out as
// writeWithoutResponse, so there is no ack, no failure signal, and no retry
// anywhere else in the codebase.
//
// Pure Dart on purpose: no Flutter, no Riverpod, no ObjectBox, no
// flutter_blue_plus — fully deterministic under fake_async (see
// test/unit/write_queue_test.dart). Wired into BleServiceImpl since
// 2026-08-07: every writeFrame() call goes through it.
import 'dart:async';

/// Serialises and paces BLE frame writes.
///
/// Why this exists: several control paths fire two frames back-to-back in one
/// synchronous turn (a mode frame then a speed frame). Unpaced and
/// unacknowledged, the second frame is routinely lost by the BLE60 bridge —
/// observed in a field capture where a Reverse mode frame was echoed and the
/// speed frame issued ~400 us later was not. The bridge only flushes to the
/// MCU UART on \r\n, so writes need spacing, and an unacknowledged write gives
/// no failure signal to retry on.
class WriteQueue {
  WriteQueue({
    required this.send,
    this.gap = const Duration(milliseconds: 60),
    this.retries = 1,
    this.retryDelay = const Duration(milliseconds: 40),
  });

  /// Performs the actual write. Must complete or throw.
  final Future<void> Function(List<int> frame) send;

  /// Enforced spacing between consecutive writes.
  final Duration gap;

  /// Extra attempts after the first failure.
  final int retries;

  final Duration retryDelay;

  // Serialises every write. Callers routinely do
  // `unawaited(enqueue(a)); unawaited(enqueue(b));` in one synchronous turn —
  // ordering is fixed the moment enqueue() runs (see enqueue() below), not by
  // whichever `send` future happens to settle first.
  Future<void> _chain = Future<void>.value();

  /// Queues [frame] for write, preserving call order even when the caller
  /// never awaits the returned future.
  ///
  /// The chain link is appended synchronously — before any `await` — so two
  /// back-to-back unawaited calls still land on the wire in the order they
  /// were made. One frame's permanent failure (after retries) is swallowed
  /// on the internal chain copy so it can never stall later frames; the
  /// future returned here is the *unswallowed* one, so the caller can still
  /// observe the error.
  Future<void> enqueue(List<int> frame) {
    final scheduled = _chain.then((_) => _run(frame));
    _chain = scheduled.catchError((Object _) {});
    return scheduled;
  }

  /// Drops the pending chain so a fresh BLE connection starts clean. Any
  /// write already in flight is left to finish (or hang) on its own — it
  /// simply no longer gates anything enqueued after this call.
  void reset() {
    _chain = Future<void>.value();
  }

  Future<void> _run(List<int> frame) async {
    final maxAttempts = 1 + retries;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await send(frame);
        lastError = null;
        break;
      } on Object catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }

    // Trailing delay, not elapsed-time measurement: this is what
    // `fake_async` intercepts (no DateTime.now(), no Stopwatch), and pacing
    // the *next* queued write matters more than shaving the gap off a
    // permanent failure.
    await Future<void>.delayed(gap);

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace ?? StackTrace.current);
    }
  }
}
