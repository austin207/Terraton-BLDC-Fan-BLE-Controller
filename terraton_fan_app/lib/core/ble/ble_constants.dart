// lib/core/ble/ble_constants.dart
// Single source of truth for all BLE UUIDs. Never write these elsewhere.

const String kServiceUUID    = "00001827-0000-1000-8000-00805f9b34fb"; // BLE Mesh Proxy Service
const String kWriteCharUUID  = "00002adb-0000-1000-8000-00805f9b34fb"; // Mesh Proxy Data In
const String kNotifyCharUUID = "00002adc-0000-1000-8000-00805f9b34fb"; // Mesh Proxy Data Out (Read/Notify)
