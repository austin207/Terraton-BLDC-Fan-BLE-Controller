// lib/core/diagnostics/crash_log_service.dart
//
// Lightweight field-crash visibility without a third-party SDK: the global
// error handlers in main.dart append every uncaught error here, and Settings
// surfaces the log so a tester can read or share it when reporting a bug.
// Fan control is fully offline, so nothing is ever sent automatically.
import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract final class CrashLogService {
  static const _fileName = 'crash_log.txt';

  /// Keep the log bounded — oldest entries are dropped past this size.
  static const _maxBytes = 64 * 1024;

  /// Serialises appends so two near-simultaneous errors can't interleave.
  static Future<void> _pending = Future<void>.value();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Appends one error entry. Never throws — a failing crash logger must not
  /// cascade (it is called from inside the global error handlers).
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    required String source,
  }) {
    final next = _pending.then((_) async {
      try {
        final f     = await _file();
        final stamp = DateTime.now().toIso8601String();
        // Cap each entry so one pathological stack can't blow the file up.
        final stackStr = (stack ?? StackTrace.empty).toString();
        final entry = '[$stamp] $source: $error\n'
            '${stackStr.length > 4000 ? stackStr.substring(0, 4000) : stackStr}\n'
            '────\n';

        var existing = '';
        if (await f.exists()) existing = await f.readAsString();
        var combined = existing + entry;
        if (combined.length > _maxBytes) {
          combined = combined.substring(combined.length - _maxBytes);
        }
        await f.writeAsString(combined, flush: true);
      } on Object catch (_) {
        // Crash logging is best-effort by definition.
      }
    });
    _pending = next;
    return next;
  }

  /// Full log contents, or null when no crashes have been recorded.
  static Future<String?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      return content.trim().isEmpty ? null : content;
    } on Exception {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } on Exception {
      // Nothing to do — the log simply persists until the next clear.
    }
  }
}
