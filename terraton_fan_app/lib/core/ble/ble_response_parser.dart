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
  // Hardware quirk: RPM responses (cmd 0x24) arrive with checksum = (correct − 1) & 0xFF.
  // All other responses use the standard formula. Accept both.
  static bool _checksumOk(int computed, int received) =>
      (computed & 0xFF) == received || ((computed - 1) & 0xFF) == received;

  /// Parses a single frame starting at byte 0.
  /// Returns null if the bytes do not form a valid response frame.
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
    int sum = bytes[0] + bytes[1] + bytes[2] + bytes[3] + bytes[4];
    for (final b in data) { sum += b; }
    if (!_checksumOk(sum, received)) return null;
    return FanResponse(command: command, data: data);
  }

  /// Scans [bytes] for ALL complete response frames and returns them in order.
  ///
  /// The hardware sometimes concatenates multiple frames into one BLE notification
  /// (e.g. a mode frame immediately followed by an RPM frame). Calling parse()
  /// on such a notification would only see the first frame; this method finds all.
  static List<FanResponse> parseAll(List<int> bytes) {
    final header = CommandLoader.frameHeader;
    final rspId  = CommandLoader.responsePacketId;
    final results = <FanResponse>[];
    int i = 0;
    while (i <= bytes.length - 6) {
      if (bytes[i] != header[0] || bytes[i + 1] != header[1]) { i++; continue; }
      if (bytes[i + 2] != rspId) { i++; continue; }
      final command = bytes[i + 3];
      final dataLen = bytes[i + 4];
      final end = i + 5 + dataLen + 1;
      if (end > bytes.length) { i++; continue; } // incomplete frame — skip and keep scanning
      final data     = bytes.sublist(i + 5, i + 5 + dataLen);
      final received = bytes[i + 5 + dataLen];
      int sum = bytes[i] + bytes[i + 1] + bytes[i + 2] + bytes[i + 3] + bytes[i + 4];
      for (final b in data) { sum += b; }
      if (_checksumOk(sum, received)) {
        results.add(FanResponse(command: command, data: data));
      }
      i = end;
    }
    return results;
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
    if (r.command != cmd || r.data.isEmpty) return null;
    final raw = r.data[0];
    // Hardware firmware quirk: timer OFF and 2H notification bytes are swapped
    // relative to the command bytes we send.
    // Remote/status Timer OFF  arrives as 0x02  → map to 0x00 (OFF).
    // Remote/status Timer 2H   arrives as 0x00  → map to 0x02 (2H).
    // Timer 4H (0x04) and 8H (0x08) are correct.
    return switch (raw) {
      0x00 => 0x02,
      0x02 => 0x00,
      _    => raw,
    };
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
