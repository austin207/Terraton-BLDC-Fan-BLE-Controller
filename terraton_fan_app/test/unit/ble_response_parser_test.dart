// test/unit/ble_response_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/ble_response_parser.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';

// Response checksum = sum of ALL frame bytes before the checksum (including 0x55 0xAA) & 0xFF.
// Same formula as request frames, consistent across the full protocol.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });
  group('BleResponseParser.parse', () {
    test('returns null for too-short frame', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x07]), isNull);
    });

    test('returns null for wrong header', () {
      expect(BleResponseParser.parse([0x00, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A]), isNull);
    });

    test('returns null for wrong packet id', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x09]), isNull);
    });

    test('returns null for bad checksum', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0xFF]), isNull);
    });

    test('parses valid power-on response', () {
      // (0x55+0xAA+0x07+0x02+0x01+0x01) & 0xFF = 266 & 0xFF = 0x0A
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A]);
      expect(r, isNotNull);
      expect(r!.command, 0x02);
      expect(BleResponseParser.parsePowerState(r), true);
    });

    test('parses valid power-off response', () {
      // (0x55+0xAA+0x07+0x02+0x01+0x00) & 0xFF = 265 & 0xFF = 0x09
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x09]);
      expect(BleResponseParser.parsePowerState(r!), false);
    });

    test('parses speed response', () {
      // (0x55+0xAA+0x07+0x04+0x01+0x03) & 0xFF = 270 & 0xFF = 0x0E
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x04, 0x01, 0x03, 0x0E]);
      expect(BleResponseParser.parseSpeed(r!), 3);
    });

    test('parseSpeed returns null for out-of-range byte 0x00', () {
      // (0x55+0xAA+0x07+0x04+0x01+0x00) & 0xFF = 267 & 0xFF = 0x0B
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x04, 0x01, 0x00, 0x0B]);
      expect(BleResponseParser.parseSpeed(r!), isNull);
    });

    test('parseSpeed returns null for out-of-range byte 0x07', () {
      // (0x55+0xAA+0x07+0x04+0x01+0x07) & 0xFF = 274 & 0xFF = 0x12
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x04, 0x01, 0x07, 0x12]);
      expect(BleResponseParser.parseSpeed(r!), isNull);
    });

    test('parses watt response', () {
      // (0x55+0xAA+0x07+0x23+0x01+0x1C) & 0xFF = 326 & 0xFF = 0x46  (28 W)
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x23, 0x01, 0x1C, 0x46]);
      expect(BleResponseParser.parsePowerWatts(r!), 28);
    });

    test('parses RPM response — correct checksum', () {
      // (0x55+0xAA+0x07+0x24+0x02+0x01+0x68) & 0xFF = 405 & 0xFF = 0x95  (360 RPM)
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x24, 0x02, 0x01, 0x68, 0x95]);
      expect(BleResponseParser.parseRpm(r!), 360);
    });

    test('parses RPM response — firmware off-by-one checksum', () {
      // Real hardware frame: 55 AA 07 24 02 00 EC 17
      // Correct sum = (0x55+0xAA+0x07+0x24+0x02+0x00+0xEC) & 0xFF = 0x18
      // Firmware sends 0x17 (correct − 1). Must still parse to 236 RPM.
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x24, 0x02, 0x00, 0xEC, 0x17]);
      expect(BleResponseParser.parseRpm(r!), 236);
    });
  });

  group('BleResponseParser.parseAll', () {
    test('single frame — returns one result', () {
      // mode=smart frame (correct checksum)
      final results = BleResponseParser.parseAll(
          [0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C]);
      expect(results.length, 1);
      expect(BleResponseParser.parseModeString(results[0]), 'smart');
    });

    test('two concatenated frames — returns both', () {
      // Frame 1: mode=smart  55 AA 07 21 01 04 2C
      // Frame 2: RPM=236     55 AA 07 24 02 00 EC 17  (firmware off-by-one checksum)
      final combined = [
        0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C,
        0x55, 0xAA, 0x07, 0x24, 0x02, 0x00, 0xEC, 0x17,
      ];
      final results = BleResponseParser.parseAll(combined);
      expect(results.length, 2);
      expect(BleResponseParser.parseModeString(results[0]), 'smart');
      expect(BleResponseParser.parseRpm(results[1]), 236);
    });

    test('empty bytes — returns empty list', () {
      expect(BleResponseParser.parseAll([]), isEmpty);
    });

    test('garbage bytes — returns empty list', () {
      expect(BleResponseParser.parseAll([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]), isEmpty);
    });
  });

  group('BleResponseParser.parseModeString', () {
    test('byte 0x01 → boost', () {
      // (0x55+0xAA+0x07+0x21+0x01+0x01) & 0xFF = 297 & 0xFF = 0x29
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x01, 0x29]);
      expect(BleResponseParser.parseModeString(r!), 'boost');
    });

    test('byte 0x02 → nature', () {
      // (0x55+0xAA+0x07+0x21+0x01+0x02) & 0xFF = 298 & 0xFF = 0x2A
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x02, 0x2A]);
      expect(BleResponseParser.parseModeString(r!), 'nature');
    });

    test('byte 0x03 → reverse', () {
      // (0x55+0xAA+0x07+0x21+0x01+0x03) & 0xFF = 299 & 0xFF = 0x2B
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x03, 0x2B]);
      expect(BleResponseParser.parseModeString(r!), 'reverse');
    });

    test('byte 0x04 → smart', () {
      // (0x55+0xAA+0x07+0x21+0x01+0x04) & 0xFF = 300 & 0xFF = 0x2C
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2C]);
      expect(BleResponseParser.parseModeString(r!), 'smart');
    });

    test('unknown byte → null', () {
      // (0x55+0xAA+0x07+0x21+0x01+0xFF) & 0xFF = 551 & 0xFF = 0x27
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0xFF, 0x27]);
      expect(BleResponseParser.parseModeString(r!), isNull);
    });

    test('wrong command → null', () {
      // Power-on response frame (valid, parses successfully)
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A]);
      expect(BleResponseParser.parseModeString(r!), isNull);
    });
  });

  group('BleResponseParser.parseTimer — hardware byte-swap quirk', () {
    // Hardware firmware quirk: remote timer OFF arrives as raw 0x02 (not 0x00),
    // and remote timer 2H arrives as raw 0x00 (not 0x02).
    // parseTimer corrects this so updateTimer() receives the canonical codes.
    // Timer 4H (0x04) and 8H (0x08) are correct and pass through unchanged.

    test('raw 0x02 → canonical 0x00 (OFF)', () {
      // Frame: 55 AA 07 22 01 02 — checksum = (0x55+0xAA+0x07+0x22+0x01+0x02)&0xFF = 0x2B
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x22, 0x01, 0x02, 0x2B]);
      expect(BleResponseParser.parseTimer(r!), 0x00);
    });

    test('raw 0x00 → canonical 0x02 (2H)', () {
      // Frame: 55 AA 07 22 01 00 — checksum = (0x55+0xAA+0x07+0x22+0x01+0x00)&0xFF = 0x29
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x22, 0x01, 0x00, 0x29]);
      expect(BleResponseParser.parseTimer(r!), 0x02);
    });

    test('raw 0x04 → canonical 0x04 (4H, unchanged)', () {
      // Frame: 55 AA 07 22 01 04 — checksum = (0x55+0xAA+0x07+0x22+0x01+0x04)&0xFF = 0x2D
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x22, 0x01, 0x04, 0x2D]);
      expect(BleResponseParser.parseTimer(r!), 0x04);
    });

    test('raw 0x08 → canonical 0x08 (8H, unchanged)', () {
      // Frame: 55 AA 07 22 01 08 — checksum = (0x55+0xAA+0x07+0x22+0x01+0x08)&0xFF = 0x31
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x22, 0x01, 0x08, 0x31]);
      expect(BleResponseParser.parseTimer(r!), 0x08);
    });

    test('wrong command byte → null', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0A]);
      expect(BleResponseParser.parseTimer(r!), isNull);
    });
  });
}
