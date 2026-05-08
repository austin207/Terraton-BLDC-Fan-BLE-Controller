// test/unit/ble_response_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/ble_response_parser.dart';

void main() {
  group('BleResponseParser.parse', () {
    test('returns null for too-short frame', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x07]), isNull);
    });

    test('returns null for wrong header', () {
      expect(BleResponseParser.parse([0x00, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0B]), isNull);
    });

    test('returns null for wrong packet id', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x0A]), isNull);
    });

    test('returns null for bad checksum', () {
      expect(BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0xFF]), isNull);
    });

    test('parses valid power-on response', () {
      // 0x07+0x02+0x01+0x01 = 0x0B
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0B]);
      expect(r, isNotNull);
      expect(r!.command, 0x02);
      expect(BleResponseParser.parsePowerState(r), true);
    });

    test('parses valid power-off response', () {
      // 0x07+0x02+0x01+0x00 = 0x0A
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x00, 0x0A]);
      expect(BleResponseParser.parsePowerState(r!), false);
    });

    test('parses speed response', () {
      // 0x07+0x04+0x01+0x03 = 0x0F
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x04, 0x01, 0x03, 0x0F]);
      expect(BleResponseParser.parseSpeed(r!), 3);
    });

    test('parses watt response', () {
      // 0x07+0x23+0x01+0x1C = 7+35+1+28 = 71 = 0x47 (28W)
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x23, 0x01, 0x1C, 0x47]);
      expect(BleResponseParser.parsePowerWatts(r!), 28);
    });

    test('parses RPM response', () {
      // RPM = 0x01 0x68 = 360; checksum 0x07+0x24+0x02+0x01+0x68 = 0x96
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x24, 0x02, 0x01, 0x68, 0x96]);
      expect(BleResponseParser.parseRpm(r!), 360);
    });
  });

  group('BleResponseParser.parseModeString', () {
    // Checksum for mode frames: 0x07 + 0x21 + 0x01 + modeByteValue
    test('byte 0x01 → boost', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x01, 0x2A]);
      expect(BleResponseParser.parseModeString(r!), 'boost');
    });

    test('byte 0x02 → nature', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x02, 0x2B]);
      expect(BleResponseParser.parseModeString(r!), 'nature');
    });

    test('byte 0x03 → reverse', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x03, 0x2C]);
      expect(BleResponseParser.parseModeString(r!), 'reverse');
    });

    test('byte 0x04 → smart', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0x04, 0x2D]);
      expect(BleResponseParser.parseModeString(r!), 'smart');
    });

    test('unknown byte → null', () {
      // checksum: 0x07+0x21+0x01+0xFF = 0x128 & 0xFF = 0x28
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x21, 0x01, 0xFF, 0x28]);
      expect(BleResponseParser.parseModeString(r!), isNull);
    });

    test('wrong command → null', () {
      final r = BleResponseParser.parse([0x55, 0xAA, 0x07, 0x02, 0x01, 0x01, 0x0B]);
      expect(BleResponseParser.parseModeString(r!), isNull);
    });
  });
}
