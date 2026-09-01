// lib/core/ble/ble_response_parser.dart
// All protocol byte constants (frame header, packet IDs, command bytes) are read
// from assets/commands.yaml via CommandLoader. The only literals here are the
// mode-byte → name mappings in parseModeString (response data semantics, not
// command bytes), kept inline because they're the inverse of modes.actions.

import 'package:terraton_fan_app/core/commands/command_loader.dart';

class FanResponse {
  final int command;
  final List<int> data;
  const FanResponse({required this.command, required this.data});
}

class BleResponseParser {
  // Firmware `calculate_crc()` (IRScan.c:1455) sums ONLY packetId + command +
  // the data bytes. It leaves out the 0x55 0xAA header and the length byte,
  // which this parser includes. The difference is 0x55 + 0xAA + dataLen:
  //
  //   dataLen 1 -> 0x55+0xAA+1 = 0x100 -> cancels, checksums agree exactly
  //   dataLen 2 -> 0x55+0xAA+2 = 0x101 -> our sum is exactly 1 too high
  //   dataLen 3 -> 0x55+0xAA+3 = 0x102 -> our sum is exactly 2 too high
  //
  // Verified against the 2026-07-04 field capture:
  //   55 AA 07 23 01 18 42  (1 byte) -> 0x07+0x23+0x18 = 0x42, agrees
  //   55 AA 07 24 02 01 68 94 (2 byte) -> 0x07+0x24+0x01+0x68 = 0x94, we get 0x95
  //
  // dataLen 3 is the widened 0x22 TIMER frame (2026-08-24 firmware fix,
  // remaining time as a raw 10s-unit uint16) — same arithmetic, one more byte.
  //
  // Keyed on dataLen, not on the command byte, because that is what the
  // firmware itself branches on. This also covers 0x08 runtime
  // (get_audit_data(), IRScan.c:1521), the protocol's other 2-byte response —
  // an RPM-only tolerance silently threw every runtime reply away.
  static bool _checksumOk(int computed, int received, int dataLen) {
    if ((computed & 0xFF) == received) return true;
    if (dataLen == 2) return ((computed - 1) & 0xFF) == received;
    if (dataLen == 3) return ((computed - 2) & 0xFF) == received;
    return false;
  }

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
    if (!_checksumOk(sum, received, dataLen)) return null;
    return FanResponse(command: command, data: data);
  }

  /// Scans [bytes] for ALL complete frames and returns them in order.
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
      if (_checksumOk(sum, received, dataLen)) {
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
    final t = r.data[0];
    // Only the four real codes (off / 2 h / 4 h / 8 h — commands.yaml
    // timers.actions), so an out-of-range byte in a junk 0x22 frame cannot arm
    // a phantom countdown. Mirrors parseSpeed's 1–6 range check.
    //
    // Keep 0x00 on the whitelist: it is what lets a genuine user Timer-OFF tap
    // round-trip. _applyFrame is what decides a REPORTED 0 is neutral.
    return const {0x00, 0x02, 0x04, 0x08}.contains(t) ? t : null;
  }

  // get_mc_state()'s 0x22 frame carries remaining sleep-timer time alongside
  // the unchanged duration code in data[0]. Two firmware shapes are handled
  // transparently, keyed on the payload length actually received:
  //
  //  - 3-byte payload (2026-08-24+ fix): data[1..2] is a big-endian uint16 in
  //    the MCU's own tick unit — raw 10s counts straight from
  //    AutoPowerState.CurrentTime/ShutDowntime, so this carries zero rounding
  //    error beyond the firmware's own ~10s internal tick.
  //  - 2-byte payload (the prior widened fix): data[1] alone, in 2-minute
  //    ticks ((ShutDowntime - CurrentTime) / 12 on the MCU) — kept so a fan
  //    not yet reflashed to the 3-byte firmware still degrades gracefully
  //    instead of losing remaining-time reporting entirely.
  //
  // Returns null for the original 1-byte frame shape (timer code only, no
  // remaining-time info at all) — callers must treat null as "unknown",
  // never as zero remaining.
  static int? parseTimerRemainingSeconds(FanResponse r) {
    final cmd = CommandLoader.responseCommand('timer');
    if (r.command != cmd) return null;
    if (r.data.length >= 3) return ((r.data[1] << 8) | r.data[2]) * 10;
    if (r.data.length == 2) return r.data[1] * 120;
    return null;
  }

  /// Response: `55 AA 07 08 02 HH LL CRC` — runtime = (HH<<8|LL) × 5 seconds.
  static int? parseRuntimeSeconds(FanResponse r) {
    final cmd = CommandLoader.responseCommand('runtime');
    if (r.command != cmd || r.data.length < 2) return null;
    return ((r.data[0] << 8) | r.data[1]) * 5;
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

/// Reassembles fan response frames from the raw BLE notification byte stream.
///
/// The BLE60 is a transparent UART→BLE bridge: it forwards the MCU's UART
/// output in notification-sized chunks cut at ARBITRARY byte boundaries (its
/// internal buffer flushes per connection event), not at frame boundaries. A
/// multi-frame burst — e.g. the 3-frame getMotorState reply plus a runtime
/// frame, ~29 bytes — is therefore routinely split MID-frame across two
/// notifications. Stateless per-notification parsing (parseAll) drops both
/// halves of such a frame silently.
///
/// This assembler buffers unconsumed tail bytes across chunks: a frame whose
/// end lies beyond the current buffer is retained until the next notification
/// completes it. Junk that is not a valid response frame (BLE60 AT strings,
/// 0xFF padding, \r\n separators) is skipped a byte at a time, exactly like
/// parseAll. Call [reset] whenever the stream context changes (new connection)
/// so a stale partial frame cannot merge with the next session's bytes.
class FrameStreamAssembler {
  // A retained tail is bounded by one max frame (~14 bytes); the cap is pure
  // insurance against a pathological byte stream.
  static const int _maxBuffer = 64;
  // Real frames carry at most 2 data bytes; anything larger is a corrupt
  // length byte and must not make the assembler wait for bytes that will
  // never come.
  static const int _maxDataLen = 8;

  final List<int> _buf = [];

  void reset() => _buf.clear();

  /// Adds one notification's bytes and returns every frame completed by them.
  List<FanResponse> addChunk(List<int> bytes) {
    _buf.addAll(bytes);
    final header = CommandLoader.frameHeader;
    final rspId  = CommandLoader.responsePacketId;
    final results = <FanResponse>[];
    var i = 0;
    while (i < _buf.length) {
      if (_buf[i] != header[0]) { i++; continue; }
      // Possible frame start. If the buffer ends before the frame can be
      // judged complete, stop and retain the tail for the next chunk.
      if (i + 1 >= _buf.length) break; // lone header byte at the tail
      if (_buf[i + 1] != header[1]) { i++; continue; }
      if (i + 5 >= _buf.length) break; // header seen, dataLen not yet arrived
      if (_buf[i + 2] != rspId) { i++; continue; }
      final dataLen = _buf[i + 4];
      if (dataLen > _maxDataLen) { i++; continue; } // corrupt length — junk
      final end = i + 5 + dataLen + 1;
      if (end > _buf.length) break; // frame split mid-frame — retain
      var sum = _buf[i] + _buf[i + 1] + _buf[i + 2] + _buf[i + 3] + _buf[i + 4];
      for (var j = i + 5; j < i + 5 + dataLen; j++) { sum += _buf[j]; }
      if (BleResponseParser._checksumOk(sum, _buf[end - 1], dataLen)) {
        results.add(FanResponse(
          command: _buf[i + 3],
          data: _buf.sublist(i + 5, i + 5 + dataLen),
        ));
        i = end;
      } else {
        i++; // false header inside other data — rescan from the next byte
      }
    }
    _buf.removeRange(0, i);
    if (_buf.length > _maxBuffer) {
      _buf.removeRange(0, _buf.length - _maxBuffer);
    }
    return results;
  }
}
