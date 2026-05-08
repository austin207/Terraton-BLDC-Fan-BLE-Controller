// lib/models/fan_state.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class FanState {
  @Id()
  int id = 0;

  @Unique()
  String deviceId = '';

  int speed = 0;           // 0 = unknown; 1-6 = speed step
  bool isBoost = false;
  String? activeMode;      // "nature" | "smart" | "reverse" | null
  int? activeTimerCode;    // 0x02 | 0x04 | 0x08 | null
  bool isPowered = false;
  int? lastWatts;
  int? lastRpm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FanState &&
          speed == other.speed &&
          isBoost == other.isBoost &&
          activeMode == other.activeMode &&
          activeTimerCode == other.activeTimerCode &&
          isPowered == other.isPowered &&
          lastWatts == other.lastWatts &&
          lastRpm == other.lastRpm;

  @override
  int get hashCode => Object.hash(
      speed, isBoost, activeMode, activeTimerCode, isPowered, lastWatts, lastRpm);
}

// Nullable fields that may need explicit null use a getter param: () => null
extension FanStateCopyWith on FanState {
  FanState copyWith({
    int? speed,
    bool? isBoost,
    String? Function()? activeMode,
    int? Function()? activeTimerCode,
    bool? isPowered,
    int? lastWatts,
    int? lastRpm,
  }) =>
      FanState()
        ..id             = id
        ..deviceId       = deviceId
        ..speed          = speed           ?? this.speed
        ..isBoost        = isBoost         ?? this.isBoost
        ..activeMode     = activeMode      != null ? activeMode()      : this.activeMode
        ..activeTimerCode = activeTimerCode != null ? activeTimerCode() : this.activeTimerCode
        ..isPowered      = isPowered       ?? this.isPowered
        ..lastWatts      = lastWatts       ?? this.lastWatts
        ..lastRpm        = lastRpm         ?? this.lastRpm;
}
