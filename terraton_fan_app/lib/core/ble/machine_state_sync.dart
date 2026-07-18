// lib/core/ble/machine_state_sync.dart
//
// The Machine-State retrieval engine: decides WHEN an assembled state reply
// from the fan may be applied to the UI/DB. Replaces the confirm-before-demote
// guard, the _ms* reply buffer, the connect/wake poll loops, and the
// _awaitingMotorState flag that previously lived interleaved in
// _ControlScreenState — six field fixes died to their interactions.
//
// Design rules (see plan "Rewrite: Machine-State retrieval on reconnect"):
//
//  * NO baseline-dependent trust decisions. The old guard judged replies
//    against the persisted ObjectBox row, so anything that damaged that row
//    silently disabled the guard. Here replies are judged only against EACH
//    OTHER: during a connect/wake sync session a state is applied when two
//    consecutively assembled replies agree AND a state query of ours was sent
//    between them (so two stale replies flushed from the BLE60's UART backlog
//    in one burst can never confirm each other — they carry the same query
//    sequence number).
//  * A reply that is never confirmed is never applied. If the session expires
//    without agreement, NOTHING is applied and the UI stays blank — a timeout
//    must not promote a suspect reply to truth (the 3 s fallback of the old
//    guard did exactly that, and is the most plausible reading of the 3.0.26
//    field failure).
//  * Backlog is a connect-time phenomenon: outside a session the engine is a
//    plain atomic assembler — a steady-state poll reply (90 s mode poll,
//    timer-expiry check) applies on first assembly, and when the engine is
//    fully idle the widget dispatches frames live (command echoes, IR-remote
//    broadcasts).
//
// Shape tolerance (vendor docs check): the lab fan's Machine-State reply is
// 3 frames (power, speed XOR mode, timer 0x22), but Terraton's protocol doc
// specifies a status reply of power + mode/speed with NO timer field, and the
// tester's firmware is newer than the lab fan's. A reply is therefore a valid
// candidate with or without a 0x22 frame; a missing timer frame is NEUTRAL
// (never a clear). Poll frames alternate between the lab-verified checksum and
// the vendor-formula checksum for the same reason (commands.yaml).
//
// Pure Dart on purpose: no Flutter, no Riverpod, no ObjectBox — fully
// deterministic under fake_async, so the tester's Connection Log can be
// replayed byte-for-byte as a regression test.
import 'dart:async';

/// One parsed state-bearing frame, exactly one field non-null.
/// (Watts/RPM/runtime frames never reach the engine — they are telemetry and
/// stay on the widget's live path.)
class SyncFrame {
  final bool? power;
  final int? speed;
  final String? mode;
  final int? timer;

  const SyncFrame.power(bool this.power)
      : speed = null, mode = null, timer = null;
  const SyncFrame.speed(int this.speed)
      : power = null, mode = null, timer = null;
  const SyncFrame.mode(String this.mode)
      : power = null, speed = null, timer = null;
  const SyncFrame.timer(int this.timer)
      : power = null, speed = null, mode = null;
}

/// An assembled Machine-State reply: power + frame [2] (speed XOR mode) +
/// optionally the timer code. [querySeq] is the number of state queries that
/// had been sent when the reply's bytes arrived — the anti-backlog stamp.
class MachineStateTuple {
  final bool power;
  final int? speed;
  final String? mode;
  final int? timer;
  final int querySeq;

  const MachineStateTuple({
    required this.power,
    this.speed,
    this.mode,
    this.timer,
    required this.querySeq,
  });

  /// Agreement on the operating state. Timer codes must match only when both
  /// replies carry one — a reply without a 0x22 frame is neutral on the timer.
  bool sameStateAs(MachineStateTuple o) =>
      power == o.power &&
      speed == o.speed &&
      mode == o.mode &&
      (timer == null || o.timer == null || timer == o.timer);

  @override
  String toString() =>
      'power:${power ? 'on' : 'off'} speed:${speed ?? '-'} '
      'mode:${mode ?? '-'} timer:${timer ?? '-'} q:$querySeq';
}

enum SyncPhase {
  /// Not engaged — the widget dispatches state frames live.
  idle,

  /// One steady-state poll is in flight; the first assembled valid reply is
  /// applied immediately (atomic assembly, no agreement needed — the UART
  /// backlog only exists at connect time).
  awaitingReply,

  /// Connect/wake sync: polls are being retried and a state is applied only
  /// on agreement of two consecutive replies spanning a query boundary.
  session,
}

class MachineStateSync {
  /// Retry cadence within a session. The fan normally answers within ~150 ms;
  /// this only paces retries against a booting MCU.
  static const pollInterval = Duration(milliseconds: 1500);

  /// Max polls the session itself sends (the 3 s status poll keeps running
  /// independently and also counts as a query via [noteExternalStateQuery]).
  static const maxSessionPolls = 6;

  /// Hard stop for a session that never reaches agreement. Longer than
  /// maxSessionPolls × pollInterval so late replies to the last poll count.
  static const sessionTimeout = Duration(seconds: 12);

  /// How long a steady-state poll waits for its reply.
  static const awaitReplyWindow = Duration(milliseconds: 3500);

  /// Grace period for the frames of one reply to finish arriving when the
  /// BLE60 split it across notifications mid-burst.
  static const assembleDebounce = Duration(milliseconds: 300);

  /// Sends one Machine-State poll. [vendorChecksum] alternates per attempt —
  /// see get_motor_state_vendor in commands.yaml.
  final void Function(bool vendorChecksum) sendPoll;

  /// Applies an assembled state the engine has decided to trust. [via] is the
  /// decision that released it (for the MS log line).
  final void Function(MachineStateTuple state, String via) apply;

  /// MS diagnostic line sink (ConnectionLogService.machineState in prod).
  final void Function(String message) log;

  MachineStateSync({
    required this.sendPoll,
    required this.apply,
    required this.log,
  });

  SyncPhase _phase = SyncPhase.idle;
  SyncPhase get phase => _phase;

  /// True while state frames must be routed into [addFrames] instead of the
  /// widget's live dispatch.
  bool get engaged => _phase != SyncPhase.idle;

  // Monotonic count of state queries sent (session polls, steady-state polls,
  // and — via noteExternalStateQuery — the 3 s status poll, whose reply
  // carries state on newer firmware). Candidates are stamped with its value
  // as of the arrival of their bytes; agreement requires the stamp to have
  // advanced, i.e. the confirming reply answers a query sent AFTER the
  // candidate arrived. A single backlog flush is stamped uniformly and can
  // never self-confirm.
  int _querySeq = 0;

  // Partially assembled reply.
  bool? _pPower;
  int? _pSpeed;
  String? _pMode;
  int? _pTimer;
  int _partialSeq = 0;
  Timer? _debounce;

  // Session state.
  MachineStateTuple? _candidate;
  int _pollsSent = 0;
  Timer? _pollTimer;
  Timer? _sessionTimer;
  Timer? _awaitTimer;

  /// Starts (or restarts) a connect/wake sync session.
  void startSession(String reason) {
    _teardown();
    _phase = SyncPhase.session;
    log('session start ($reason)');
    _sendSessionPoll();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_pollsSent >= maxSessionPolls) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      _sendSessionPoll();
    });
    _sessionTimer = Timer(sessionTimeout, () {
      log('session expired — nothing applied; UI stays blank, status poll '
          'continues (an unconfirmed reply is never promoted to truth)');
      _teardown();
    });
  }

  /// One steady-state poll with atomic reply assembly (90 s mode poll,
  /// timer-expiry check, bare-OFF confirmation). No-op while a session is
  /// already polling.
  void requestOnce(String reason) {
    if (_phase == SyncPhase.session) return;
    _teardown();
    _phase = SyncPhase.awaitingReply;
    log('single poll ($reason)');
    _querySeq++;
    sendPoll(false);
    _awaitTimer = Timer(awaitReplyWindow, () {
      log('single poll reply window expired — nothing applied');
      _teardown();
    });
  }

  /// The widget sent a frame that can elicit a state-bearing reply (the 3 s
  /// status poll). Advances the query sequence so such replies can confirm a
  /// candidate on firmware that reports state in status replies.
  void noteExternalStateQuery() => _querySeq++;

  /// Ends any engagement (user command, disconnect, pause, dispose). The
  /// user's intent outranks the sync: subsequent frames flow live.
  void cancel(String reason) {
    if (engaged) log('cancelled ($reason)');
    _teardown();
  }

  void dispose() => _teardown();

  /// Feeds one notification chunk's parsed state frames while [engaged].
  ///
  /// [chunkHasTelemetry] flags watts/RPM in the same chunk: a 0x04 speed frame
  /// riding a telemetry burst with no 0x22 is the firmware's post-mains-restore
  /// status quirk carrying the STORED speed — it must not overwrite a mode
  /// already assembled from a real reply. (When no mode is buffered the speed
  /// is kept: on newer firmware a status reply carrying state is a legitimate
  /// candidate, and a wrong stored-speed candidate cannot win agreement twice
  /// against real replies.)
  void addFrames(List<SyncFrame> frames, {bool chunkHasTelemetry = false}) {
    if (!engaged) return;
    final chunkHasTimer = frames.any((f) => f.timer != null);
    // A telemetry-bearing chunk with no 0x22 is status-poll-shaped (the
    // firmware's 4-frame post-mains burst, or a newer-firmware status reply
    // that carries state). Such a chunk must never TEAR a partial Machine-
    // State reply still being assembled: its power frame does not start a new
    // reply, and its 0x04 is the stored speed — it must not null a mode
    // already assembled from the real reply. When the partial is empty it is
    // still a legitimate candidate source (newer firmware).
    final statusShaped = chunkHasTelemetry && !chunkHasTimer;
    final seqAtArrival = _querySeq;
    for (final f in frames) {
      if (!engaged) {
        // An apply mid-chunk ended the engagement; remaining frames are the
        // tail of the same backlog burst — nothing left to assemble.
        log('discarding chunk tail after apply');
        return;
      }
      if (f.power != null) {
        if (_pPower != null) {
          if (!statusShaped) {
            _finalizePartial(); // a new reply begins
            _pPower = f.power;
          }
          // status-shaped: keep the pending reply's power frame.
        } else {
          _pPower = f.power;
        }
      } else if (f.speed != null) {
        if (!(statusShaped && _pMode != null)) {
          _pSpeed = f.speed;
          _pMode = null;
        }
      } else if (f.mode != null) {
        _pMode = f.mode;
        _pSpeed = null;
      } else if (f.timer != null) {
        _pTimer = f.timer;
      }
      _partialSeq = seqAtArrival;
    }
    if (!_partialEmpty) {
      if (_partialComplete) {
        _finalizePartial();
      } else {
        _debounce?.cancel();
        _debounce = Timer(assembleDebounce, _finalizePartial);
      }
    }
  }

  bool get _partialEmpty =>
      _pPower == null && _pSpeed == null && _pMode == null && _pTimer == null;

  /// All 3 lab-protocol frames present. Shape-tolerant replies without a 0x22
  /// still finalize via the debounce.
  bool get _partialComplete =>
      _pPower != null && (_pSpeed != null || _pMode != null) && _pTimer != null;

  void _sendSessionPoll() {
    _pollsSent++;
    _querySeq++;
    // Odd attempts use the lab-verified checksum, even attempts the
    // vendor-formula one — whichever the firmware answers wins.
    sendPoll(_pollsSent.isEven);
  }

  void _finalizePartial() {
    _debounce?.cancel();
    _debounce = null;
    final power = _pPower;
    final speed = _pSpeed;
    final mode = _pMode;
    final timer = _pTimer;
    final seq = _partialSeq;
    _pPower = null;
    _pSpeed = null;
    _pMode = null;
    _pTimer = null;
    if (!engaged) return;

    if (power == null) {
      // Orphan frame [2]/timer with no power frame — a torn backlog fragment
      // or a stray echo. Never applicable on its own.
      log('discard fragment{speed:${speed ?? '-'} mode:${mode ?? '-'} '
          'timer:${timer ?? '-'}} — no power frame');
      return;
    }
    if (power && speed == null && mode == null) {
      // Bare ON: an MCU still booting after a mains cycle answers this way.
      // Not applicable — the session/steady polls keep retrying.
      log('discard bare ON — no speed/mode yet (MCU booting?); polling on');
      return;
    }

    final tuple = MachineStateTuple(
      power: power,
      speed: speed,
      mode: mode,
      timer: timer,
      querySeq: seq,
    );

    if (_phase == SyncPhase.awaitingReply) {
      log('reply{$tuple} => applied (steady-state single reply)');
      _teardown();
      apply(tuple, 'steady-state single reply');
      return;
    }

    // Session: agreement required.
    final c = _candidate;
    if (c != null && tuple.sameStateAs(c) && tuple.querySeq > c.querySeq) {
      // Confirmed across a query boundary — merge (a timer-less confirming
      // reply keeps the candidate's timer code) and apply.
      final agreed = MachineStateTuple(
        power: tuple.power,
        speed: tuple.speed,
        mode: tuple.mode,
        timer: tuple.timer ?? c.timer,
        querySeq: tuple.querySeq,
      );
      log('reply{$tuple} agrees with candidate{$c} => applied');
      _teardown();
      apply(agreed, 'session agreement (2 replies)');
      return;
    }
    log(c == null
        ? 'reply{$tuple} => candidate (first reply is never applied alone)'
        : (tuple.sameStateAs(c)
            ? 'reply{$tuple} matches candidate{$c} but no query boundary '
                '(same backlog burst) => candidate refreshed'
            : 'reply{$tuple} contradicts candidate{$c} => candidate replaced'));
    _candidate = tuple;
    // Confirm as fast as possible instead of waiting out the retry cadence.
    if (_pollsSent < maxSessionPolls) _sendSessionPoll();
  }

  void _teardown() {
    _debounce?.cancel();
    _debounce = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _awaitTimer?.cancel();
    _awaitTimer = null;
    _pPower = null;
    _pSpeed = null;
    _pMode = null;
    _pTimer = null;
    _candidate = null;
    _pollsSent = 0;
    _phase = SyncPhase.idle;
  }
}
