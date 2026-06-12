// lib/models/usage_log.dart
import 'package:objectbox/objectbox.dart';

/// One continuous-operation segment logged while the fan is running.
/// Written when gear/mode/power state changes or when the fan turns off.
@Entity()
class UsageLog {
  @Id()
  int id = 0;

  String deviceId = '';

  /// UTC epoch ms — when this segment started.
  @Property(type: PropertyType.date)
  DateTime startTime = DateTime(0);

  /// Seconds this state lasted before the next change.
  int durationSecs = 0;

  /// Speed gear 1–6; 0 = fan was off during this segment.
  int gear = 0;

  /// Average watt reading across the segment; 0 = no poll response received.
  int watts = 0;

  /// Average RPM across the segment; 0 = no poll response received.
  int rpm = 0;

  /// Active mode: 'smart' | 'reverse' | 'nature' | 'boost' | null (normal).
  String? mode;

  /// Speed (1-6) active immediately before Smart Mode was enabled for this
  /// segment. Only set when mode == 'smart'; used as the efficiency baseline.
  int? smartBaselineGear;

  UsageLog({
    this.id = 0,
    required this.deviceId,
    required this.startTime,
    required this.durationSecs,
    required this.gear,
    required this.watts,
    this.rpm = 0,
    this.mode,
    this.smartBaselineGear,
  });

  /// Energy in kWh for this segment.
  double get kwh =>
      (watts > 0 && gear > 0) ? watts * durationSecs / 3600.0 / 1000.0 : 0.0;
}
