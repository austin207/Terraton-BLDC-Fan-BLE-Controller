// lib/core/diagnostics/connection_log_service.dart
//
// Field visibility into the BLE link without a debugger: every frame written
// to the fan (TX), every notification received from it (RX), and every
// connection lifecycle event is appended here with a timestamp. Settings
// surfaces the log so a tester can share exactly what the fan reported around
// a reconnect — the class of bug that cannot be reproduced without the
// hardware in hand. Fan control is fully offline; nothing is ever uploaded
// automatically (same policy as CrashLogService).
import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract final class ConnectionLogService {
  static const _fileName = 'connection_log.txt';

  /// Keep the log bounded — oldest entries are dropped past this size.
  /// ~128 KB holds several hours of 3-second polling, comfortably spanning
  /// a disconnect/reconnect repro plus the session that preceded it.
  static const _maxBytes = 128 * 1024;

  /// Lines waiting to be appended; drained in one write per flush so the
  /// 3-second poll cadence doesn't turn into one file write per frame.
  static final List<String> _pendingLines = [];

  /// Serialises file access so overlapping flushes can't interleave.
  static Future<void> _writeChain = Future<void>.value();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  /// Connection lifecycle event (connect attempt/result, disconnect, …).
  static void event(String message) => _add('EV', message);

  /// Frame written to the fan.
  static void tx(List<int> bytes) => _add('TX', _hex(bytes));

  /// Raw notification bytes received from the fan (pre-reassembly).
  static void rx(List<int> bytes) => _add('RX', _hex(bytes));

  static void _add(String kind, String message) {
    _pendingLines.add('[${DateTime.now().toIso8601String()}] $kind $message');
    _scheduleFlush();
  }

  /// Chains a flush onto the write queue. Never throws — logging must not be
  /// able to break fan control (e.g. path_provider unavailable in tests).
  static void _scheduleFlush() {
    _writeChain = _writeChain.then((_) async {
      if (_pendingLines.isEmpty) return;
      final batch = _pendingLines.join('\n');
      _pendingLines.clear();
      try {
        final f = await _file();
        var existing = '';
        if (await f.exists()) existing = await f.readAsString();
        var combined = existing.isEmpty ? '$batch\n' : '$existing$batch\n';
        if (combined.length > _maxBytes) {
          combined = combined.substring(combined.length - _maxBytes);
        }
        await f.writeAsString(combined, flush: true);
      } on Object catch (_) {
        // Best-effort by definition.
      }
    });
  }

  /// Full log contents, or null when nothing has been recorded.
  static Future<String?> read() async {
    try {
      // Let any queued appends land first so the view is current.
      await _writeChain;
      final f = await _file();
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      return content.trim().isEmpty ? null : content;
    } on Object {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _writeChain;
      _pendingLines.clear();
      final f = await _file();
      if (await f.exists()) await f.delete();
    } on Object {
      // Nothing to do — the log simply persists until the next clear.
    }
  }
}
