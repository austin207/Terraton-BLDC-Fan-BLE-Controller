// lib/core/ble/ble_response_parser.dart

class FanResponse {
  final int command;
  final List<int> data;
  const FanResponse({required this.command, required this.data});
}

class BleResponseParser {
  static FanResponse? parse(List<int> bytes) {
    if (bytes.length < 6) return null;
    if (bytes[0] != 0x55 || bytes[1] != 0xAA) return null;
    if (bytes[2] != 0x07) return null;
    final command = bytes[3];
    final dataLen = bytes[4];
    if (bytes.length < 5 + dataLen + 1) return null;
    final data = bytes.sublist(5, 5 + dataLen);
    final received = bytes[5 + dataLen];
    int sum = bytes[2] + bytes[3] + bytes[4];
    for (final b in data) { sum += b; }
    if ((sum & 0xFF) != received) return null;
    return FanResponse(command: command, data: data);
  }

  static int?  parsePowerWatts(FanResponse r) =>
      r.command == 0x23 && r.data.isNotEmpty ? r.data[0] : null;

  static int?  parseRpm(FanResponse r) =>
      r.command == 0x24 && r.data.length >= 2 ? (r.data[0] << 8) | r.data[1] : null;

  static bool? parsePowerState(FanResponse r) =>
      r.command == 0x02 && r.data.isNotEmpty ? r.data[0] == 0x01 : null;

  static int? parseSpeed(FanResponse r) {
    if (r.command != 0x04 || r.data.isEmpty) return null;
    final s = r.data[0];
    return s >= 1 && s <= 6 ? s : null;
  }

  static int?  parseMode(FanResponse r) =>
      r.command == 0x21 && r.data.isNotEmpty ? r.data[0] : null;

  static int?  parseTimer(FanResponse r) =>
      r.command == 0x22 && r.data.isNotEmpty ? r.data[0] : null;

  // Converts mode response byte to mode name string.
  // Keeps protocol byte values out of business logic (providers.dart).
  static String? parseModeString(FanResponse r) {
    if (r.command != 0x21 || r.data.isEmpty) return null;
    return const <int, String>{
      0x01: 'boost',
      0x02: 'nature',
      0x03: 'reverse',
      0x04: 'smart',
    }[r.data[0]];
  }
}
