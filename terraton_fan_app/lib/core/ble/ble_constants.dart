// lib/core/ble/ble_constants.dart
// Single source of truth for all BLE UUIDs. Never write these elsewhere.

// Advertised service UUID — what the BLE60 module puts in its advertisement
// packet. The working APK (20260519_125522) used only this Mesh Proxy UUID
// for both scan and GATT, which is why the module was discoverable in the
// scan list. Used as the scan filter.
const String kAdvServiceUUID = "00001827-0000-1000-8000-00805f9b34fb"; // BLE Mesh Proxy (advertised)

// GATT service UUID — the actual proprietary service the module exposes
// after a GATT connection is established. Confirmed by the firmware team.
const String kServiceUUID    = "26cc3fc0-6241-f5b4-5347-63a3097f6764"; // Amp'ed RF BLE60 proprietary service
const String kWriteCharUUID  = "26cc3fc2-6241-f5b4-5347-63a3097f6764"; // Write characteristic
const String kNotifyCharUUID = "26cc3fc1-6241-f5b4-5347-63a3097f6764"; // Read / Notify characteristic
