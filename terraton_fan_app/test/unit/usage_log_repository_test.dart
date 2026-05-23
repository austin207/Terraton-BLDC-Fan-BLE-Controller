// test/unit/usage_log_repository_test.dart
//
// Tests an in-memory UsageLogRepository that mirrors the interface contract
// without touching ObjectBox or native libraries.
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/models/usage_log.dart';

// ── In-memory implementation ──────────────────────────────────────────────────

class _FakeUsageLogRepo implements UsageLogRepository {
  final List<UsageLog> _logs = [];
  int _nextId = 1;

  @override
  void addLog(UsageLog log) {
    log.id = _nextId++;
    _logs.add(log);
  }

  @override
  List<UsageLog> getLogsInRange(DateTime from, DateTime to) => _logs
      .where((l) => !l.startTime.isBefore(from) && !l.startTime.isAfter(to))
      .toList();

  @override
  List<UsageLog> getLogsForDevice(String deviceId, DateTime from, DateTime to) =>
      _logs
          .where((l) =>
              l.deviceId == deviceId &&
              !l.startTime.isBefore(from) &&
              !l.startTime.isAfter(to))
          .toList();

  @override
  List<String> allDeviceIds() =>
      _logs.map((l) => l.deviceId).toSet().toList();

  @override
  void pruneBefore(DateTime cutoff) =>
      _logs.removeWhere((l) => l.startTime.isBefore(cutoff));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

UsageLog _log({
  required String deviceId,
  required DateTime startTime,
  int durationSecs = 60,
  int gear = 3,
  int watts = 40,
}) =>
    UsageLog(
      deviceId: deviceId,
      startTime: startTime,
      durationSecs: durationSecs,
      gear: gear,
      watts: watts,
    );

void main() {
  late _FakeUsageLogRepo repo;

  setUp(() => repo = _FakeUsageLogRepo());

  group('addLog / getLogsInRange', () {
    test('getLogsInRange returns empty list when no logs added', () {
      final from = DateTime(2026, 1, 1);
      final to   = DateTime(2026, 12, 31);
      expect(repo.getLogsInRange(from, to), isEmpty);
    });

    test('returns log whose startTime is within [from, to]', () {
      final t = DateTime(2026, 5, 10, 12, 0);
      repo.addLog(_log(deviceId: 'd1', startTime: t));

      final result = repo.getLogsInRange(
        DateTime(2026, 5, 10),
        DateTime(2026, 5, 11),
      );
      expect(result, hasLength(1));
      expect(result.first.deviceId, 'd1');
    });

    test('excludes log whose startTime is before range', () {
      repo.addLog(_log(deviceId: 'd1', startTime: DateTime(2026, 5, 9)));

      final result = repo.getLogsInRange(
        DateTime(2026, 5, 10),
        DateTime(2026, 5, 11),
      );
      expect(result, isEmpty);
    });

    test('excludes log whose startTime is after range', () {
      repo.addLog(_log(deviceId: 'd1', startTime: DateTime(2026, 5, 12)));

      final result = repo.getLogsInRange(
        DateTime(2026, 5, 10),
        DateTime(2026, 5, 11),
      );
      expect(result, isEmpty);
    });

    test('inclusive boundary — log at exactly "from" is included', () {
      final from = DateTime(2026, 5, 10);
      repo.addLog(_log(deviceId: 'd1', startTime: from));
      expect(repo.getLogsInRange(from, DateTime(2026, 5, 11)), hasLength(1));
    });

    test('inclusive boundary — log at exactly "to" is included', () {
      final to = DateTime(2026, 5, 11);
      repo.addLog(_log(deviceId: 'd1', startTime: to));
      expect(repo.getLogsInRange(DateTime(2026, 5, 10), to), hasLength(1));
    });

    test('returns all logs within range across multiple devices', () {
      final day = DateTime(2026, 5, 10);
      repo.addLog(_log(deviceId: 'a', startTime: day));
      repo.addLog(_log(deviceId: 'b', startTime: day));
      repo.addLog(_log(deviceId: 'c', startTime: DateTime(2026, 4, 1))); // out
      expect(
        repo.getLogsInRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31)),
        hasLength(2),
      );
    });
  });

  group('getLogsForDevice', () {
    test('filters by deviceId', () {
      final t = DateTime(2026, 5, 10);
      repo.addLog(_log(deviceId: 'aaa', startTime: t));
      repo.addLog(_log(deviceId: 'bbb', startTime: t));

      final result = repo.getLogsForDevice(
        'aaa',
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31),
      );
      expect(result, hasLength(1));
      expect(result.first.deviceId, 'aaa');
    });

    test('returns empty when device has no logs in range', () {
      repo.addLog(_log(deviceId: 'aaa', startTime: DateTime(2026, 3, 1)));
      expect(
        repo.getLogsForDevice('aaa', DateTime(2026, 5, 1), DateTime(2026, 5, 31)),
        isEmpty,
      );
    });
  });

  group('allDeviceIds', () {
    test('returns empty when no logs', () {
      expect(repo.allDeviceIds(), isEmpty);
    });

    test('returns unique device ids', () {
      final t = DateTime(2026, 5, 1);
      repo.addLog(_log(deviceId: 'x', startTime: t));
      repo.addLog(_log(deviceId: 'y', startTime: t));
      repo.addLog(_log(deviceId: 'x', startTime: t)); // duplicate

      final ids = repo.allDeviceIds();
      expect(ids, containsAll(['x', 'y']));
      expect(ids, hasLength(2));
    });
  });

  group('pruneBefore', () {
    test('removes logs whose startTime is before the cutoff', () {
      final cutoff = DateTime(2026, 5, 1);
      repo.addLog(_log(deviceId: 'd', startTime: DateTime(2026, 4, 30))); // old
      repo.addLog(_log(deviceId: 'd', startTime: DateTime(2026, 5, 2)));  // new

      repo.pruneBefore(cutoff);

      expect(
        repo.getLogsInRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        hasLength(1),
      );
    });

    test('keeps logs at exactly the cutoff', () {
      final cutoff = DateTime(2026, 5, 1);
      repo.addLog(_log(deviceId: 'd', startTime: cutoff));

      repo.pruneBefore(cutoff);

      expect(
        repo.getLogsInRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        hasLength(1),
      );
    });

    test('no-op when all logs are after cutoff', () {
      repo.addLog(_log(deviceId: 'd', startTime: DateTime(2026, 6, 1)));
      repo.pruneBefore(DateTime(2026, 5, 1));
      expect(
        repo.getLogsInRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        hasLength(1),
      );
    });
  });
}
