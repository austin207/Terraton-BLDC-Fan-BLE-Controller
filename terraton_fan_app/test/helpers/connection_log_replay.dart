// test/helpers/connection_log_replay.dart
//
// Permanent regression harness for field tester `ConnectionLogService`
// captures (Settings → Connection Log → Share). When a field bug report
// arrives with a capture attached, paste the raw text into a test as the
// `capture` argument to [replayConnectionLog] and assert on `.applied` — this
// drives the EXACT bytes the fan sent through the same pipeline production
// uses (`FrameStreamAssembler` → SyncFrame classification →
// `MachineStateSync`), under `fake_async` so the engine's debounce/session
// timers behave the way they did on the tester's phone.
//
// It exists because the failure mode this branch rewrites away (six dead
// field fixes across 3.0.19–3.0.26) was never reproducible from source
// reading alone — only from a real capture's exact byte-level timing. This
// harness turns "does the capture attached to bug report #N still misbehave"
// into a one-function regression test instead of a manual re-read of the log.
//
// The RX classification block below is a deliberate line-for-line mirror of
// `_ControlScreenState._subscribeNotify` (control_screen.dart) — including
// the fact that only watts/RPM (not runtime) set `chunkHasTelemetry`, and
// that `sync.addFrames` is skipped entirely when a chunk carries no
// state-bearing frames. Keep it in sync if that method's classification ever
// changes; this harness's whole value is proving PRODUCTION's classification
// against real captures, not a from-scratch reimplementation of it.
import 'package:fake_async/fake_async.dart';
import 'package:terraton_fan_app/core/ble/ble_response_parser.dart';
import 'package:terraton_fan_app/core/ble/machine_state_sync.dart';

/// Everything the pipeline did while replaying one capture.
class ReplayResult {
  /// Every `apply(tuple, via)` call the engine made, in order.
  final List<(MachineStateTuple, String)> applied;

  /// Every engine log line (`MachineStateSync`'s `log` sink), in order.
  final List<String> logs;

  /// The `vendorChecksum` flag for every poll the engine itself sent (via
  /// `sendPoll`) — NOT the TX lines replayed from the capture.
  final List<bool> polls;

  const ReplayResult(this.applied, this.logs, this.polls);
}

class _LogLine {
  final DateTime ts;
  final String kind;
  final String message;
  const _LogLine(this.ts, this.kind, this.message);
}

// `[<ISO8601 timestamp>] <KIND> <rest of line>` — see ConnectionLogService._add.
final RegExp _lineRe = RegExp(r'^\[(.+?)\]\s+(\S+)\s*(.*)$');

List<int>? _parseHex(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return null;
  final tokens = trimmed.split(RegExp(r'\s+'));
  try {
    return tokens.map((t) => int.parse(t, radix: 16)).toList();
  } on FormatException {
    return null;
  }
}

/// True for a state-query TX frame: the status poll (`55 AA 00 00 01 00 ..`)
/// or a Get Motor State poll (`55 AA 00 01 01 00 ..`), matched by prefix so
/// EITHER checksum variant (lab-verified vs. vendor-formula, see
/// get_motor_state / get_motor_state_vendor in commands.yaml) counts — the
/// checksum byte itself is intentionally not checked.
bool _isStateQueryTx(List<int> bytes) {
  if (bytes.length < 6) return false;
  if (bytes[0] != 0x55 || bytes[1] != 0xAA) return false;
  if (bytes[2] != 0x00 || bytes[4] != 0x01 || bytes[5] != 0x00) return false;
  return bytes[3] == 0x00 || bytes[3] == 0x01;
}

/// Replays a `ConnectionLogService` capture through
/// `FrameStreamAssembler` → SyncFrame classification → `MachineStateSync`.
///
/// Only `TX`/`RX` lines matter; `EV`/`FRM`/`MS` lines and blank/unparseable
/// lines are skipped. A session is started before any line is fed (mirrors
/// `_connect()` calling `_sync.startSession('connect')` immediately after
/// resetting the assembler). Real time between consecutive TX/RX lines is
/// replayed via `fake_async`'s `elapse`, capped at 5 s per gap so a capture
/// spanning minutes of idle connection doesn't blow past the session timeout
/// purely from wall-clock arithmetic, while near-zero gaps inside one BLE60
/// backlog burst stay a burst (no synthetic delay inserted).
ReplayResult replayConnectionLog(String capture) {
  final applied = <(MachineStateTuple, String)>[];
  final logs = <String>[];
  final polls = <bool>[];

  final lines = <_LogLine>[];
  for (final raw in capture.split('\n')) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final m = _lineRe.firstMatch(trimmed);
    if (m == null) continue;
    final kind = m.group(2)!;
    if (kind != 'TX' && kind != 'RX') continue;
    DateTime ts;
    try {
      ts = DateTime.parse(m.group(1)!);
    } on FormatException {
      continue;
    }
    lines.add(_LogLine(ts, kind, m.group(3) ?? ''));
  }

  fakeAsync((async) {
    final assembler = FrameStreamAssembler();
    final sync = MachineStateSync(
      sendPoll: polls.add,
      apply: (tuple, via) => applied.add((tuple, via)),
      log: logs.add,
    );
    sync.startSession('replay');

    DateTime? lastTs;
    for (final line in lines) {
      if (lastTs != null) {
        var delta = line.ts.difference(lastTs);
        if (delta.isNegative) delta = Duration.zero;
        if (delta > const Duration(seconds: 5)) {
          delta = const Duration(seconds: 5);
        }
        async.elapse(delta);
      }
      lastTs = line.ts;

      final bytes = _parseHex(line.message);
      if (bytes == null || bytes.isEmpty) continue;

      if (line.kind == 'TX') {
        if (_isStateQueryTx(bytes)) sync.noteExternalStateQuery();
        continue;
      }

      // RX — mirrors _subscribeNotify byte-for-byte (control_screen.dart).
      final responses = assembler.addChunk(bytes);
      if (responses.isEmpty) continue;

      // Telemetry pass: watts/RPM flag the chunk as telemetry-bearing.
      // Runtime frames are also non-state, but (mirroring production
      // exactly) do NOT set chunkHasTelemetry — only watts/RPM do.
      var hasTelemetry = false;
      for (final r in responses) {
        if (BleResponseParser.parsePowerWatts(r) != null) {
          hasTelemetry = true;
          continue;
        }
        if (BleResponseParser.parseRpm(r) != null) {
          hasTelemetry = true;
          continue;
        }
        // parseRuntimeSeconds(r) != null: telemetry, but intentionally not
        // classified into hasTelemetry — see comment above.
      }

      // State-bearing frames, in arrival order.
      final stateFrames = <SyncFrame>[];
      for (final r in responses) {
        final power = BleResponseParser.parsePowerState(r);
        if (power != null) {
          stateFrames.add(SyncFrame.power(power));
          continue;
        }
        final speed = BleResponseParser.parseSpeed(r);
        if (speed != null) {
          stateFrames.add(SyncFrame.speed(speed));
          continue;
        }
        final mode = BleResponseParser.parseModeString(r);
        if (mode != null) {
          stateFrames.add(SyncFrame.mode(mode));
          continue;
        }
        final timer = BleResponseParser.parseTimer(r);
        if (timer != null) stateFrames.add(SyncFrame.timer(timer));
      }
      if (stateFrames.isEmpty) continue;

      sync.addFrames(stateFrames, chunkHasTelemetry: hasTelemetry);
    }

    // Past the session timeout, so an unconfirmed candidate is definitively
    // resolved (discarded) rather than left pending on the caller's clock.
    async.elapse(MachineStateSync.sessionTimeout + const Duration(seconds: 1));
    async.flushMicrotasks();
    sync.dispose();
  });

  return ReplayResult(applied, logs, polls);
}
