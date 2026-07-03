// test/unit/frame_stream_assembler_test.dart
//
// The BLE60 bridges the fan MCU's UART output into BLE notifications chunked
// at ARBITRARY byte boundaries — a multi-frame burst (e.g. the 3-frame
// getMotorState reply + runtime frame) is routinely split mid-frame across
// notifications. FrameStreamAssembler must recover every frame regardless of
// where the chunk boundaries fall; the old stateless parseAll dropped any
// frame split mid-frame (root cause of Smart mode + sleep timer loss on
// reconnect, reported 2026-07-03).
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/ble_response_parser.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';

// Response checksum = (0x55 + 0xAA + 0x07 + cmd + len + Σdata) & 0xFF.
const powerOn   = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A];
const powerOff  = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x09];
const modeSmart = [0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C];
const timer2h   = [0x55, 0xAA, 0x07, 0x22, 0x01, 0x02, 0x2B];
const speed5    = [0x55, 0xAA, 0x07, 0x04, 0x01, 0x05, 0x10];
// Runtime: 55 AA 07 08 02 00 64 → (0x106+0x08+0x02+0x00+0x64) & 0xFF = 0x74.
const runtime100 = [0x55, 0xAA, 0x07, 0x08, 0x02, 0x00, 0x64, 0x74];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  late FrameStreamAssembler asm;
  setUp(() => asm = FrameStreamAssembler());

  group('FrameStreamAssembler', () {
    test('parses a single whole frame in one chunk', () {
      final r = asm.addChunk(powerOn);
      expect(r, hasLength(1));
      expect(BleResponseParser.parsePowerState(r[0]), true);
    });

    test('parses a full Machine-State burst + runtime frame in one chunk', () {
      final r = asm.addChunk([...powerOn, ...modeSmart, ...timer2h, ...runtime100]);
      expect(r, hasLength(4));
      expect(BleResponseParser.parsePowerState(r[0]), true);
      expect(BleResponseParser.parseModeString(r[1]), 'smart');
      expect(BleResponseParser.parseTimer(r[2]), 0x02);
      expect(BleResponseParser.parseRuntimeSeconds(r[3]), 500);
    });

    test('REGRESSION: 21-byte reply split mid-timer-frame recovers all 3 frames', () {
      // Chunk boundary at byte 18 — inside the timer frame. The old parseAll
      // dropped the timer frame entirely, leaving the sleep timer chip OFF
      // after reconnect.
      final burst = [...powerOn, ...modeSmart, ...timer2h];
      final first  = asm.addChunk(burst.sublist(0, 18));
      final second = asm.addChunk(burst.sublist(18));
      expect(first, hasLength(2));
      expect(BleResponseParser.parseModeString(first[1]), 'smart');
      expect(second, hasLength(1));
      expect(BleResponseParser.parseTimer(second[0]), 0x02);
    });

    test('reply split mid-mode-frame recovers the mode frame', () {
      final burst = [...powerOn, ...modeSmart, ...timer2h];
      // Boundary at byte 10 — inside the mode frame.
      final first  = asm.addChunk(burst.sublist(0, 10));
      final second = asm.addChunk(burst.sublist(10));
      expect(first, hasLength(1));
      expect(BleResponseParser.parsePowerState(first[0]), true);
      expect(second, hasLength(2));
      expect(BleResponseParser.parseModeString(second[0]), 'smart');
      expect(BleResponseParser.parseTimer(second[1]), 0x02);
    });

    test('frame split across three chunks (header / middle / checksum)', () {
      expect(asm.addChunk(speed5.sublist(0, 2)), isEmpty);
      expect(asm.addChunk(speed5.sublist(2, 6)), isEmpty);
      final r = asm.addChunk(speed5.sublist(6));
      expect(r, hasLength(1));
      expect(BleResponseParser.parseSpeed(r[0]), 5);
    });

    test('split inside the 55 AA header itself (lone 0x55 tail)', () {
      expect(asm.addChunk(timer2h.sublist(0, 1)), isEmpty);
      final r = asm.addChunk(timer2h.sublist(1));
      expect(r, hasLength(1));
      expect(BleResponseParser.parseTimer(r[0]), 0x02);
    });

    test('skips junk before and between frames (AT strings, FF padding, CRLF)', () {
      final junkAt = 'AT-AB -BypassMode-'.codeUnits;
      final r = asm.addChunk([
        0xFF, 0xFF, ...junkAt, 0x0D, 0x0A,
        ...powerOn, 0x0D, 0x0A, ...timer2h,
      ]);
      expect(r, hasLength(2));
      expect(BleResponseParser.parsePowerState(r[0]), true);
      expect(BleResponseParser.parseTimer(r[1]), 0x02);
    });

    test('corrupt dataLen does not stall the stream — following frame parses', () {
      // Looks like a frame start but claims 0xFF data bytes: must be skipped
      // as junk, never held waiting for bytes that will never arrive.
      final r1 = asm.addChunk([0x55, 0xAA, 0x07, 0x22, 0xFF, 0x01]);
      expect(r1, isEmpty);
      final r2 = asm.addChunk(powerOn);
      expect(r2, hasLength(1));
      expect(BleResponseParser.parsePowerState(r2[0]), true);
    });

    test('bad checksum frame is skipped, embedded valid frame recovered', () {
      final corrupt = [0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0xEE]; // wrong cs
      final r = asm.addChunk([...corrupt, ...speed5]);
      expect(r, hasLength(1));
      expect(BleResponseParser.parseSpeed(r[0]), 5);
    });

    test('request-packetId frames (0x06 echo) are not parsed as responses', () {
      const requestEcho = [0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x09];
      final r = asm.addChunk([...requestEcho, ...powerOff]);
      expect(r, hasLength(1));
      expect(BleResponseParser.parsePowerState(r[0]), false);
    });

    test('reset() drops a pending partial so sessions cannot merge', () {
      // Old session ends mid-frame…
      expect(asm.addChunk(timer2h.sublist(0, 4)), isEmpty);
      asm.reset();
      // …new session's bytes must parse on their own, not merge with the tail.
      final r = asm.addChunk(powerOn);
      expect(r, hasLength(1));
      expect(BleResponseParser.parsePowerState(r[0]), true);
    });

    test('every possible split point of a 3-frame burst recovers all frames', () {
      final burst = [...powerOn, ...modeSmart, ...timer2h];
      for (var cut = 1; cut < burst.length; cut++) {
        final a = FrameStreamAssembler();
        final all = [
          ...a.addChunk(burst.sublist(0, cut)),
          ...a.addChunk(burst.sublist(cut)),
        ];
        expect(all, hasLength(3), reason: 'split at byte $cut lost a frame');
        expect(BleResponseParser.parsePowerState(all[0]), true,
            reason: 'split at byte $cut');
        expect(BleResponseParser.parseModeString(all[1]), 'smart',
            reason: 'split at byte $cut');
        expect(BleResponseParser.parseTimer(all[2]), 0x02,
            reason: 'split at byte $cut');
      }
    });
  });
}
