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

  /// Watt reading from BLE; 0 = no reading received yet.
  int watts = 0;

  /// Active mode: 'smart' | 'reverse' | 'nature' | 'boost' | null (normal).
  String? mode;

  UsageLog({
    this.id = 0,
    required this.deviceId,
    required this.startTime,
    required this.durationSecs,
    required this.gear,
    required this.watts,
    this.mode,
  });

  /// Energy in kWh for this segment.
  double get kwh =>
      (watts > 0 && gear > 0) ? watts * durationSecs / 3600.0 / 1000.0 : 0.0;
}
