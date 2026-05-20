// lib/core/ble/ble_constants.dart
// Single source of truth for all BLE UUIDs. Never write these elsewhere.

// ── Scan filter ──────────────────────────────────────────────────────────────
// What the BLE60 puts in its advertisement packet (BLE Mesh Proxy profile).
const String kAdvServiceUUID = "00001827-0000-1000-8000-00805f9b34fb";

// ── BLE Mesh Proxy standard characteristics (confirmed working with BLE60) ───
// The BLE60 advertises 0x1827 (Mesh Proxy Service) and exposes these standard
// Mesh Proxy Data In/Out characteristics. Confirmed working in APK f793216.
const String kMeshProxyDataInUUID  = "00002adb-0000-1000-8000-00805f9b34fb"; // Write
const String kMeshProxyDataOutUUID = "00002adc-0000-1000-8000-00805f9b34fb"; // Notify

// ── Firmware-team GATT UUIDs (proprietary Amp'ed RF service) ────────────────
const String kServiceUUID    = "26cc3fc0-6241-f5b4-5347-63a3097f6764";
const String kWriteCharUUID  = "26cc3fc2-6241-f5b4-5347-63a3097f6764";
const String kNotifyCharUUID = "26cc3fc1-6241-f5b4-5347-63a3097f6764";

// ── Standard UART-over-BLE fallback UUIDs ───────────────────────────────────
// Serial Bluetooth Terminal (the app confirmed to work with BLE60) searches
// for these profiles in priority order. If the BLE60's actual write char is
// one of these, the service discovery below will find it.

// HM-10 / CC254X (most common for Amp'ed RF / Chinese BLE modules)
const String kCC254xServiceUUID  = "0000ffe0-0000-1000-8000-00805f9b34fb";
const String kCC254xCharUUID     = "0000ffe1-0000-1000-8000-00805f9b34fb"; // RW

// Nordic UART Service (NUS)
const String kNusServiceUUID     = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String kNusWriteCharUUID   = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // Write
const String kNusNotifyCharUUID  = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // Notify

// Microchip RN4870 / RN4871
const String kMicrochipServiceUUID  = "49535343-fe7d-4ae5-8fa9-9fafd205e455";
const String kMicrochipWriteCharUUID = "49535343-8841-43f4-a8d4-ecbe34729bb3"; // Write
const String kMicrochipNotifyCharUUID = "49535343-1e4d-4bd9-ba61-23c647249616"; // Notify
