// test/unit/connection_log_replay_test.dart
//
// Proves the log-replay harness (test/helpers/connection_log_replay.dart)
// against a synthetic capture shaped exactly like the field bug this branch
// exists to fix: on connect, the BLE60 flushes a STALE Machine-State reply
// from its UART backlog buffer (queued while no phone was connected) before
// the fan's genuine current state arrives. The old confirm-before-demote
// guard trusted such a reply after ~1 s and persisted the wipe; the rewrite
// (MachineStateSync) must never apply a candidate that was never confirmed
// by a second, later-queried, agreeing reply.
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';

import '../helpers/connection_log_replay.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  // Frame bytes used across captures below (packetId 0x07 = response).
  // Checksum = (0x55 + 0xAA + 0x07 + cmd + dataLen + Σdata) & 0xFF.
  const staleOff   = '55 AA 07 02 01 00 09'; // power OFF
  const staleSpeed = '55 AA 07 04 01 05 10'; // stored speed 5
  const staleTimer = '55 AA 07 22 01 00 29'; // timer off
  const genuineOn    = '55 AA 07 02 01 01 0A'; // power ON
  const genuineSmart = '55 AA 07 21 01 04 2C'; // mode smart
  const genuineTimer4h = '55 AA 07 22 01 04 2D'; // timer 4h
  const getMotorStatePoll = '55 AA 00 01 01 00 01';

  final t0 = DateTime(2026, 7, 18, 10, 12, 13, 0);

  String rxLine(DateTime t, String hex) => '[${t.toIso8601String()}] RX $hex';
  String txLine(DateTime t, String hex) => '[${t.toIso8601String()}] TX $hex';

  test('stale backlog OFF is superseded by the confirmed genuine ON/Smart/4h '
      'reply — the OFF never applies', () {
    final tStaleRx = t0.add(const Duration(milliseconds: 5));
    final tPoll1   = tStaleRx.add(const Duration(milliseconds: 300));
    final tGenuine1 = tPoll1.add(const Duration(milliseconds: 15));
    final tPoll2    = tGenuine1.add(const Duration(milliseconds: 300));
    final tGenuine2 = tPoll2.add(const Duration(milliseconds: 15));

    final capture = [
      // 1. BLE60 backlog flush: one RX chunk carrying a full STALE OFF reply.
      rxLine(tStaleRx, '$staleOff $staleSpeed $staleTimer'),
      // 2. App's Get Motor State poll (retry cadence / connect burst).
      txLine(tPoll1, getMotorStatePoll),
      // 3. Genuine current state arrives.
      rxLine(tGenuine1, '$genuineOn $genuineSmart $genuineTimer4h'),
      // 4. Another poll, then the same genuine reply again — the
      //    confirmation across a query boundary.
      txLine(tPoll2, getMotorStatePoll),
      rxLine(tGenuine2, '$genuineOn $genuineSmart $genuineTimer4h'),
    ].join('\n');

    final result = replayConnectionLog(capture);

    expect(result.applied.length, 1);
    final (tuple, via) = result.applied.single;
    expect(tuple.power, true);
    expect(tuple.mode, 'smart');
    expect(tuple.timer, 0x04);
    expect(tuple.speed, isNull);
    expect(via, contains('agreement'));

    expect(result.applied.any((e) => e.$1.power == false), false,
        reason: 'the stale OFF backlog reply must never reach apply');
  });

  test('stale OFF with no follow-up (link died) — nothing applies once the '
      'session times out', () {
    final tStaleRx = t0.add(const Duration(milliseconds: 5));
    final capture = [
      rxLine(tStaleRx, '$staleOff $staleSpeed $staleTimer'),
    ].join('\n');

    final result = replayConnectionLog(capture);

    expect(result.applied, isEmpty,
        reason: 'an unconfirmed reply must never be promoted to truth, even '
            'after the session gives up');
  });

  test('a reply split mid-frame across two RX lines still assembles via the '
      "assembler's tail-carry", () {
    final tChunkA = t0.add(const Duration(milliseconds: 5));
    final tChunkB = tChunkA.add(const Duration(milliseconds: 10));
    final tConfirmPoll = tChunkB.add(const Duration(milliseconds: 300));
    final tConfirmRx = tConfirmPoll.add(const Duration(milliseconds: 15));

    // The mode frame (55 AA 07 21 01 04 2C) is split: chunk A carries the
    // power-ON frame plus the mode frame's header/cmd/dataLen only (missing
    // its data byte + checksum); chunk B completes it, followed immediately
    // by the full timer frame.
    final capture = [
      rxLine(tChunkA, '$genuineOn 55 AA 07 21 01'),
      rxLine(tChunkB, '04 2C $genuineTimer4h'),
      // The engine's own accelerated confirm poll fires internally as soon
      // as the split reply finalizes into a candidate; replay one more
      // external poll + matching reply so the agreement is unambiguous
      // regardless of that internal timing.
      txLine(tConfirmPoll, getMotorStatePoll),
      rxLine(tConfirmRx, '$genuineOn $genuineSmart $genuineTimer4h'),
    ].join('\n');

    final result = replayConnectionLog(capture);

    expect(result.applied.length, 1);
    final (tuple, _) = result.applied.single;
    expect(tuple.power, true);
    expect(tuple.mode, 'smart');
    expect(tuple.timer, 0x04);
    expect(tuple.speed, isNull);
  });
}
