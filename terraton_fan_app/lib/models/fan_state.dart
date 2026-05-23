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

  // Lighting UI state — persisted so the panel restores on reconnect.
  String lastLightColorType  = 'warm'; // 'warm' | 'neutral' | 'cool'
  double lastLightBrightness = 0.7;
  bool   lastLightIsOn       = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FanState &&
          deviceId == other.deviceId &&
          speed == other.speed &&
          isBoost == other.isBoost &&
          activeMode == other.activeMode &&
          activeTimerCode == other.activeTimerCode &&
          isPowered == other.isPowered &&
          lastWatts == other.lastWatts &&
          lastRpm == other.lastRpm &&
          lastLightColorType == other.lastLightColorType &&
          lastLightBrightness == other.lastLightBrightness &&
          lastLightIsOn == other.lastLightIsOn;

  @override
  int get hashCode => Object.hash(
      deviceId, speed, isBoost, activeMode, activeTimerCode, isPowered,
      lastWatts, lastRpm, lastLightColorType, lastLightBrightness, lastLightIsOn);
}

// Nullable fields that may need explicit null use a getter param: () => null
extension FanStateCopyWith on FanState {
  FanState copyWith({
    int? speed,
    bool? isBoost,
    String? Function()? activeMode,
    int? Function()? activeTimerCode,
    bool? isPowered,
    int? Function()? lastWatts,
    int? Function()? lastRpm,
    String? lastLightColorType,
    double? lastLightBrightness,
    bool? lastLightIsOn,
  }) =>
      FanState()
        ..id                  = id
        ..deviceId            = deviceId
        ..speed               = speed               ?? this.speed
        ..isBoost             = isBoost             ?? this.isBoost
        ..activeMode          = activeMode          != null ? activeMode()      : this.activeMode
        ..activeTimerCode     = activeTimerCode     != null ? activeTimerCode() : this.activeTimerCode
        ..isPowered           = isPowered           ?? this.isPowered
        ..lastWatts           = lastWatts           != null ? lastWatts()       : this.lastWatts
        ..lastRpm             = lastRpm             != null ? lastRpm()         : this.lastRpm
        ..lastLightColorType  = lastLightColorType  ?? this.lastLightColorType
        ..lastLightBrightness = lastLightBrightness ?? this.lastLightBrightness
        ..lastLightIsOn       = lastLightIsOn       ?? this.lastLightIsOn;
}
