// lib/core/storage/usage_log_repository.dart
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/objectbox.g.dart';

abstract class UsageLogRepository {
  void addLog(UsageLog log);
  List<UsageLog> getLogsInRange(DateTime from, DateTime to);
  List<UsageLog> getLogsForDevice(String deviceId, DateTime from, DateTime to);
  List<String> allDeviceIds();
  void pruneBefore(DateTime cutoff);
}

class UsageLogRepositoryImpl implements UsageLogRepository {
  final Store _store;
  UsageLogRepositoryImpl(this._store);

  Box<UsageLog> get _box => _store.box<UsageLog>();

  @override
  void addLog(UsageLog log) => _box.put(log);

  @override
  List<UsageLog> getLogsInRange(DateTime from, DateTime to) {
    final q = _box.query(
      UsageLog_.startTime
          .greaterOrEqual(from.millisecondsSinceEpoch)
          .and(UsageLog_.startTime.lessOrEqual(to.millisecondsSinceEpoch)),
    ).build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  @override
  List<UsageLog> getLogsForDevice(String deviceId, DateTime from, DateTime to) {
    final q = _box.query(
      UsageLog_.deviceId.equals(deviceId).and(
        UsageLog_.startTime
            .greaterOrEqual(from.millisecondsSinceEpoch)
            .and(UsageLog_.startTime.lessOrEqual(to.millisecondsSinceEpoch)),
      ),
    ).build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  @override
  List<String> allDeviceIds() {
    final ids = <String>{};
    for (final log in _box.getAll()) {
      ids.add(log.deviceId);
    }
    return ids.toList();
  }

  @override
  void pruneBefore(DateTime cutoff) {
    final q = _box
        .query(UsageLog_.startTime.lessThan(cutoff.millisecondsSinceEpoch))
        .build();
    final List<int> ids;
    try {
      ids = q.find().map((l) => l.id).toList();
    } finally {
      q.close();
    }
    _box.removeMany(ids);
  }
}
