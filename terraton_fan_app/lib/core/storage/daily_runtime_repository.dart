// lib/core/storage/daily_runtime_repository.dart
import 'package:terraton_fan_app/models/daily_runtime.dart';
import 'package:terraton_fan_app/objectbox.g.dart';

abstract class DailyRuntimeRepository {
  /// Inserts or overwrites the runtime record for [deviceId] on [date].
  /// [date] must be local calendar midnight (no time component).
  void upsertForDate(String deviceId, DateTime date, int runtimeSecs);

  /// Returns all records for [deviceId] whose date falls in [from]..[to]
  /// (inclusive). Both bounds must be local calendar midnight.
  List<DailyRuntime> getRange(String deviceId, DateTime from, DateTime to);
}

class DailyRuntimeRepositoryImpl implements DailyRuntimeRepository {
  final Store _store;
  DailyRuntimeRepositoryImpl(this._store);

  Box<DailyRuntime> get _box => _store.box<DailyRuntime>();

  static R _use<T, R>(Query<T> q, R Function(Query<T>) fn) {
    try { return fn(q); } finally { q.close(); }
  }

  @override
  void upsertForDate(String deviceId, DateTime date, int runtimeSecs) {
    final existing = _use(
      _box.query(
        DailyRuntime_.deviceId.equals(deviceId)
            .and(DailyRuntime_.date.equals(date.millisecondsSinceEpoch)),
      ).build(),
      (q) => q.findFirst(),
    );
    if (existing != null) {
      existing.runtimeSecs = runtimeSecs;
      _box.put(existing);
    } else {
      _box.put(DailyRuntime(
        deviceId: deviceId,
        date: date,
        runtimeSecs: runtimeSecs,
      ));
    }
  }

  @override
  List<DailyRuntime> getRange(String deviceId, DateTime from, DateTime to) {
    return _use(
      _box.query(
        DailyRuntime_.deviceId.equals(deviceId).and(
          DailyRuntime_.date
              .greaterOrEqual(from.millisecondsSinceEpoch)
              .and(DailyRuntime_.date.lessOrEqual(to.millisecondsSinceEpoch)),
        ),
      ).build(),
      (q) => q.find(),
    );
  }
}
