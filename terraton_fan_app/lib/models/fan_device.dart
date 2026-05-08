// lib/models/fan_device.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class FanDevice {
  @Id()
  int id = 0;

  // Unique serial identifier.
  // QR mode: from QR payload "device_id" field.
  // BLE scan mode: set to macAddress value on first save.
  @Unique()
  String deviceId = '';

  // BLE MAC address captured on first successful connection.
  // Empty string until first connection is established.
  String macAddress = '';

  // From QR payload (QR mode only). Empty string in BLE scan mode.
  String model = '';

  // User-defined nickname.
  String nickname = '';

  // From QR payload (QR mode only). Empty string in BLE scan mode.
  String fwVersion = '';

  @Property(type: PropertyType.date)
  DateTime addedAt = DateTime.now(); // was `late` — default prevents LateInitializationError

  @Property(type: PropertyType.date)
  DateTime? lastConnectedAt;
}
