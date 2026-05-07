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
}
