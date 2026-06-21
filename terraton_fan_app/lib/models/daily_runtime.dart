// lib/models/daily_runtime.dart
import 'package:objectbox/objectbox.dart';

/// One record per fan per calendar day.
/// Written on every firmware runtime-poll response; the firmware resets its
/// counter daily, so the latest value in a day is that day's total fan-on time.
@Entity()
class DailyRuntime {
  @Id()
  int id = 0;

  @Index()
  String deviceId = '';

  /// Local calendar date stored as midnight (no time component).
  @Property(type: PropertyType.date)
  DateTime date = DateTime(0);

  /// Seconds the fan was running on this calendar day.
  int runtimeSecs = 0;

  DailyRuntime({
    this.id = 0,
    required this.deviceId,
    required this.date,
    required this.runtimeSecs,
  });
}
