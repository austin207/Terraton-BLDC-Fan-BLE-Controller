// lib/core/ble/ble_response_parser.dart
// All protocol byte constants (header, packet IDs, command bytes) are read from
// assets/commands.yaml via CommandLoader — no values hardcoded here.

import 'package:terraton_fan_app/core/commands/command_loader.dart';

class FanResponse {
  final int command;
  final List<int> data;
  const FanResponse({required this.command, required this.data});
}

class BleResponseParser {
  static FanResponse? parse(List<int> bytes) {
    if (bytes.length < 6) return null;
    final header = CommandLoader.frameHeader;
    if (bytes[0] != header[0] || bytes[1] != header[1]) return null;
    if (bytes[2] != CommandLoader.responsePacketId) return null;
    final command = bytes[3];
    final dataLen = bytes[4];
    if (bytes.length < 5 + dataLen + 1) return null;
    final data = bytes.sublist(5, 5 + dataLen);
    final received = bytes[5 + dataLen];
    // Checksum = sum of ALL frame bytes before the checksum (including header).
    int sum = bytes[0] + bytes[1] + bytes[2] + bytes[3] + bytes[4];
    for (final b in data) { sum += b; }
    if ((sum & 0xFF) != received) return null;
    return FanResponse(command: command, data: data);
  }

  // Protocol: power reported as a single byte in watts (max 255 W).
  static int? parsePowerWatts(FanResponse r) {
    final cmd = CommandLoader.responseCommand('power_watts');
    return r.command == cmd && r.data.isNotEmpty ? r.data[0] : null;
  }

  // Speed reported as two bytes (high byte, low byte) — 16-bit RPM value.
  static int? parseRpm(FanResponse r) {
    final cmd = CommandLoader.responseCommand('running_rpm');
    return r.command == cmd && r.data.length >= 2
        ? (r.data[0] << 8) | r.data[1]
        : null;
  }

  static bool? parsePowerState(FanResponse r) {
    final cmd = CommandLoader.responseCommand('power');
    return r.command == cmd && r.data.isNotEmpty ? r.data[0] == 0x01 : null;
  }

  static int? parseSpeed(FanResponse r) {
    final cmd = CommandLoader.responseCommand('speed');
    if (r.command != cmd || r.data.isEmpty) return null;
    final s = r.data[0];
    return s >= 1 && s <= 6 ? s : null;
  }

  static int? parseTimer(FanResponse r) {
    final cmd = CommandLoader.responseCommand('timer');
    return r.command == cmd && r.data.isNotEmpty ? r.data[0] : null;
  }

  // Converts mode response byte to mode name string.
  // Mode data values (0x01–0x04) come from commands.yaml modes.actions.
  static String? parseModeString(FanResponse r) {
    final cmd = CommandLoader.responseCommand('mode');
    if (r.command != cmd || r.data.isEmpty) return null;
    return const <int, String>{
      0x01: 'boost',
      0x02: 'nature',
      0x03: 'reverse',
      0x04: 'smart',
    }[r.data[0]];
  }
}
