# Terraton BLDC Fan BLE Controller — Implementation-Ready PRD

> **Target Agent:** Claude Code
> **Framework:** Flutter (Dart)
> **Platform:** Android
> **Flutter SDK:** >=3.41.0 (stable as of May 2026)
> **Dart SDK:** ^3.9.0
> **Status:** Implementation-ready. Do not ask clarifying questions. Follow build order in Section 5 exactly.

---

## 1. Title & Objective

### 1.1 Product Name
Terraton Fan Controller — Flutter BLE Android App

### 1.2 Objective
Build an Android Flutter application that connects to a Terraton BLDC ceiling fan over BLE v5.2 via the Amp'ed RF BLE60 module. The app supports two onboarding modes (toggled via a single constant), YAML-driven commands for future-proofing, real-time telemetry, and multi-fan management with custom nicknames.

### 1.3 Architecture Summary
```
Flutter App --BLE v5.2--> BLE60 Module --UART1--> Fan MCU --> BLDC Motor
```
The BLE60 is a radio bridge. The app writes framed request packets to the Write Characteristic. The fan responds on the Notify Characteristic. No server, no backend, no cloud.

---

## 1.4 Confirmed BLE Constants

These are confirmed by Terraton's firmware team (May 2026). They are the same for every Terraton fan unit. Defined once in `ble_constants.dart` and never written anywhere else.

```dart
// lib/core/ble/ble_constants.dart
const String kServiceUUID    = "00001827-0000-1000-8000-00805f9b34fb"; // BLE Mesh Proxy Service
const String kWriteCharUUID  = "00002adb-0000-1000-8000-00805f9b34fb"; // Mesh Proxy Data In
const String kNotifyCharUUID = "00002adc-0000-1000-8000-00805f9b34fb"; // Mesh Proxy Data Out (also Read/Notify)
```

The Notify characteristic (`0x2ADC`) is also the Read characteristic. Call `setNotifyValue(true)` on it to receive fan responses.

---

## 1.5 Onboarding Mode Toggle

Since all Terraton fans share the same UUIDs, individual fans are identified by their **BLE MAC address**, captured on first connection. Two onboarding modes are supported, switchable via a single constant:

```dart
// lib/core/config/app_config.dart

enum OnboardingMode {
  qrScan,   // User scans QR on fan packaging to get device identity
  bleScan,  // App shows BLE scan results; user selects fan from list
}

class AppConfig {
  /// Toggle this constant to switch onboarding mode.
  /// qrScan  : User scans QR code on fan packaging.
  /// bleScan : User selects fan from a BLE scan list.
  /// No other code changes are needed when toggling this.
  static const OnboardingMode onboardingMode = OnboardingMode.qrScan;

}

// ── Phase 2 (not in current build) ────────────────────────────────────────
// Remote command loading: app fetches commands.yaml from a hosted URL on launch,
// compares version field, updates local cache if newer, falls back to bundled
// asset on failure. Approved by Terraton. Implement in Phase 2.
// Planned URL: https://raw.githubusercontent.com/terraton/fan-app-config/main/commands.yaml
```

Both modes lead to the same result: a `FanDevice` stored in ObjectBox with a MAC address, nickname, and optional QR-sourced metadata. The control screen and all fan commands are identical in both modes.

---

## 1.6 YAML-Driven Commands

All BLE command definitions live in `assets/commands.yaml`. The `CommandLoader` class reads this file at app startup and provides frames to `BleFrameBuilder`. This means command bytes, new commands, or lighting codes can be updated by replacing the YAML file alone — no Dart code changes needed.

```
assets/
  commands.yaml    <-- single source of truth for all BLE commands
```

---

## 2. User Stories & Acceptance Criteria

### US-01a: QR Code Onboarding (OnboardingMode.qrScan)

Active when `AppConfig.onboardingMode == OnboardingMode.qrScan`.

**Acceptance Criteria:**
- [ ] AC-01a-1: "Add Fan" opens full-screen QR scanner via `mobile_scanner`.
- [ ] AC-01a-2: QR JSON validated for all 4 required fields: `device_id`, `model`, `fw_version`, and optionally `serial_number`.
- [ ] AC-01a-3: On valid QR: navigate to "Name Your Fan" screen pre-filled with `model` value.
- [ ] AC-01a-4: On invalid QR: show SnackBar "Invalid QR code. Please scan the code on your Terraton fan packaging." Keep scanner open.
- [ ] AC-01a-5: Camera permission: if denied, show dialog with "Open Settings" button.

**QR Payload Schema (QR mode):**
```json
{
  "device_id":  "TT-FAN-00123",
  "model":      "Terraton X1",
  "fw_version": "1.0"
}
```
Note: UUIDs are NOT in the QR. They are constants in `ble_constants.dart`. The QR carries identity only.

---

### US-01b: BLE Scan Onboarding (OnboardingMode.bleScan)

Active when `AppConfig.onboardingMode == OnboardingMode.bleScan`.

**Acceptance Criteria:**
- [ ] AC-01b-1: "Add Fan" begins BLE scan filtered by `kServiceUUID`.
- [ ] AC-01b-2: Discovered fans shown as a list with their BLE remote ID (MAC address) and signal strength (RSSI).
- [ ] AC-01b-3: Already-saved fans (matched by MAC) shown with a "Already added" badge and excluded from selection.
- [ ] AC-01b-4: Tapping a discovered fan: navigates to "Name Your Fan" screen with a pre-filled default name "Terraton Fan".
- [ ] AC-01b-5: Scan timeout: 15 seconds. If nothing found: show "No fans found. Make sure your fan is powered on."
- [ ] AC-01b-6: "Refresh" button restarts scan.

---

### US-02: Name Your Fan Screen (both modes)

**Acceptance Criteria:**
- [ ] AC-02-1: `TextFormField` pre-filled with `model` value (QR mode) or "Terraton Fan" (BLE scan mode).
- [ ] AC-02-2: Validate: non-empty, max 30 characters, alphanumeric and spaces only.
- [ ] AC-02-3: "Save" persists `FanDevice` to ObjectBox. MAC address is captured on first connection, not at save time.
- [ ] AC-02-4: Navigate to control screen after save.

---

### US-03: Multi-Fan Home Screen

**Acceptance Criteria:**
- [ ] AC-03-1: Lists all saved fans as cards: nickname, model (if available), last connected time or "Never connected".
- [ ] AC-03-2: Tapping a card: navigates to control screen and begins BLE connection.
- [ ] AC-03-3: Long-press: bottom sheet with "Rename" and "Delete".
- [ ] AC-03-4: Delete: confirmation dialog before removing from ObjectBox.
- [ ] AC-03-5: FAB "+" always visible; triggers the active onboarding mode flow.
- [ ] AC-03-6: Empty state: illustration + "No fans added yet" + "Add Fan" button.

---

### US-04: BLE Connection Management

**Acceptance Criteria:**
- [ ] AC-04-1: Scan filtered by `kServiceUUID`. If fan has a saved MAC: auto-connect to it directly. If no MAC saved yet: connect to first discovered device and save its MAC to `FanDevice.macAddress`.
- [ ] AC-04-2: Connection banner: green "Connected", amber "Connecting...", red "Disconnected - Tap to retry".
- [ ] AC-04-3: Scan timeout: 10 seconds.
- [ ] AC-04-4: Auto-reconnect: 3 retries with 5-second intervals.
- [ ] AC-04-5: All control buttons disabled when not Connected.
- [ ] AC-04-6: BLE disconnected cleanly on leaving control screen.
- [ ] AC-04-7: Permissions: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` at app launch.
- [ ] AC-04-8: On connect: discover services, find write char by `kWriteCharUUID`, find notify char by `kNotifyCharUUID`, call `setNotifyValue(true)`.

---

### US-05: Fan Control Screen

**Acceptance Criteria:**
- [ ] AC-05-1: AppBar title shows fan nickname.
- [ ] AC-05-2: Power ON/OFF button prominent at top.
- [ ] AC-05-3: Circular arc dial (CustomPainter): 6 speed segments, each with a distinct colour. Speed 1: Green `#1E8449`, Speed 2: Blue `#1A56A0`, Speed 3: Violet `#7D3C98`, Speed 4: Yellow `#D4AC0D`, Speed 5: Orange `#D35400`, Speed 6: Red `#C0392B`. Active segment filled; others outlined. Tap sends corresponding speed frame.
- [ ] AC-05-4: Centre of dial shows live Watts and RPM (updated every 3 seconds).
- [ ] AC-05-5: BOOST button below the dial.
- [ ] AC-05-6: Mode row: NATURE, SMART, REVERSE. Active mode highlighted.
- [ ] AC-05-7: Timer row: 2H, 4H, 8H, OFF. Active timer highlighted.
- [ ] AC-05-8: Lighting section: ON, OFF buttons + colour temperature slider 2300K-6500K. If lighting command bytes are null in YAML: show SnackBar "Lighting commands pending from Terraton" on tap.
- [ ] AC-05-9: Each tap: `HapticFeedback.lightImpact()`.
- [ ] AC-05-10: Fan state updated from BLE response frames, not assumed locally.

---

### US-06: Real-Time Telemetry

**Acceptance Criteria:**
- [ ] AC-06-1: After connect, poll every 3 seconds: send `query_power` frame, wait 200ms, send `query_speed` frame.
- [ ] AC-06-2: Watts shown as integer e.g. "28 W" in dial centre.
- [ ] AC-06-3: RPM shown as integer e.g. "360 RPM" in dial centre.
- [ ] AC-06-4: No response within 5 seconds: show "--" for that value.
- [ ] AC-06-5: Polling timer cancelled on BLE disconnect and on screen dispose.

---

### US-07: Data Persistence & Backup

**Acceptance Criteria:**
- [ ] AC-07-1: All `FanDevice` records in ObjectBox (Android Auto Backup included automatically).
- [ ] AC-07-2: Settings "Export fans": serialise to JSON, share via `share_plus`.
- [ ] AC-07-3: Settings "Import fans": file picker, parse JSON, upsert by `device_id`, skip existing.

---

## 3. File Structure & Data Model

### 3.1 Full File Structure
```
terraton_fan_app/
├── android/
│   └── app/src/main/AndroidManifest.xml
├── assets/
│   └── commands.yaml                         # BLE command definitions (SINGLE SOURCE OF TRUTH)
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── objectbox.g.dart                      # Generated
│   ├── core/
│   │   ├── config/
│   │   │   └── app_config.dart               # OnboardingMode toggle + app-wide constants
│   │   ├── ble/
│   │   │   ├── ble_constants.dart            # 3 confirmed UUIDs; never written elsewhere
│   │   │   ├── ble_frame_builder.dart        # Builds frames from CommandLoader data
│   │   │   ├── ble_response_parser.dart      # Parses all response frames
│   │   │   ├── ble_service.dart              # flutter_blue_plus implementation
│   │   │   └── ble_connection_state.dart     # BleConnectionState enum
│   │   ├── commands/
│   │   │   └── command_loader.dart           # Loads + parses commands.yaml at startup
│   │   └── storage/
│   │       ├── objectbox_store.dart
│   │       └── fan_repository.dart
│   ├── models/
│   │   ├── fan_device.dart                   # ObjectBox entity
│   │   └── fan_state.dart                    # ObjectBox entity
│   ├── features/
│   │   ├── home/
│   │   │   ├── home_screen.dart
│   │   │   └── fan_card.dart
│   │   ├── onboarding/
│   │   │   ├── qr_scan_screen.dart           # Used when OnboardingMode.qrScan
│   │   │   ├── ble_scan_screen.dart          # Used when OnboardingMode.bleScan
│   │   │   └── name_fan_screen.dart          # Shared by both modes
│   │   ├── control/
│   │   │   ├── control_screen.dart
│   │   │   ├── connection_banner.dart
│   │   │   ├── circular_speed_dial.dart
│   │   │   ├── mode_control_widget.dart
│   │   │   ├── timer_control_widget.dart
│   │   │   └── lighting_control_widget.dart
│   │   └── settings/
│   │       └── settings_screen.dart
│   └── shared/
│       ├── theme.dart
│       └── router.dart
├── test/
│   ├── unit/
│   │   ├── command_loader_test.dart          # YAML parsing and frame building
│   │   ├── ble_frame_builder_test.dart       # Frame byte verification
│   │   ├── ble_response_parser_test.dart
│   │   └── fan_repository_test.dart
│   └── widget/
│       └── control_screen_test.dart
└── pubspec.yaml
```

---

### 3.2 Data Models

#### FanDevice (ObjectBox entity)
```dart
// lib/models/fan_device.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class FanDevice {
  @Id()
  int id = 0;

  // Unique serial identifier.
  // QR mode: from QR payload "device_id" field.
  // BLE scan mode: set to macAddress value on first save (used as fallback key).
  @Unique()
  String deviceId = '';

  // BLE MAC address captured on first successful connection.
  // This is the actual BLE identity used for reconnection.
  // Empty string until first connection is established.
  String macAddress = '';

  // From QR payload (QR mode only). Empty string in BLE scan mode.
  String model = '';

  // User-defined nickname.
  String nickname = '';

  // From QR payload (QR mode only). Empty string in BLE scan mode.
  String fwVersion = '';

  @Property(type: PropertyType.date)
  late DateTime addedAt;

  @Property(type: PropertyType.date)
  DateTime? lastConnectedAt;
}
```

#### FanState (ObjectBox entity)
```dart
// lib/models/fan_state.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class FanState {
  @Id()
  int id = 0;

  @Unique()
  String deviceId = '';

  int speed = 0;              // 0 = unknown; 1-6 = speed step
  bool isBoost = false;
  String? activeMode;         // "nature" | "smart" | "reverse" | null
  int? activeTimerCode;       // 0x02 | 0x04 | 0x08 | null
  bool isPowered = false;
  int? lastWatts;
  int? lastRpm;
}
```

---

## 4. API Contracts & Logic

### 4.1 BLE Frame Structure

```
Byte 1 : 0x55          -- Header byte 1 (fixed)
Byte 2 : 0xAA          -- Header byte 2 (fixed)
Byte 3 : Packet ID     -- 0x06 = request; 0x07 = response
Byte 4 : Command       -- operation identifier
Byte 5 : Data Length   -- number of data bytes
Byte 6+ : Data         -- payload
Last   : Checksum      -- (packetId + command + dataLength + sum(data)) & 0xFF
```

---

### 4.2 commands.yaml — Full Definition

```yaml
# assets/commands.yaml
# BLE command definitions for Terraton BLDC Fan Controller.
# Phase 1: bundled as an asset. Update by releasing a new app version.
# Phase 2 (approved, not yet built): hosted remotely; app fetches on launch
# and updates local cache when version is bumped. No app update needed.
# Set command or data to null for pending/unimplemented commands.
# New command sections added here are automatically available in the app.

version: "1.0"

protocol:
  header: [0x55, 0xAA]
  request_packet_id: 0x06
  response_packet_id: 0x07

# Special case: status poll uses a fixed non-standard frame
status_poll:
  frame: [0x55, 0xAA, 0x00, 0x00, 0x01, 0x00, 0x01]

commands:

  power:
    command: 0x02
    actions:
      on:  [0x01]
      off: [0x00]

  speed:
    command: 0x04
    steps:
      1: [0x01]
      2: [0x02]
      3: [0x03]
      4: [0x04]
      5: [0x05]
      6: [0x06]

  modes:
    command: 0x21
    actions:
      boost:   [0x01]
      nature:  [0x02]
      reverse: [0x03]
      smart:   [0x04]

  timers:
    command: 0x22
    actions:
      off: [0x00]
      2h:  [0x02]
      4h:  [0x04]
      8h:  [0x08]

  queries:
    power_consumption:
      command: 0x23
      data: [0x00]
    running_speed:
      command: 0x24
      data: [0x00]

  # Lighting commands pending from Terraton.
  # Set command and data values when received. No code changes needed.
  lighting:
    on:
      command: null
      data: null
    off:
      command: null
      data: null
    color_temp:
      command: null
      data_min: 0
      data_max: 255

response_commands:
  power:        0x02
  speed:        0x04
  mode:         0x21
  timer:        0x22
  power_watts:  0x23
  running_rpm:  0x24
```

---

### 4.3 CommandLoader

```dart
// lib/core/commands/command_loader.dart
// Phase 1: loads from bundled asset only.
// Phase 2 will add remote fetch + local cache (approved, not yet implemented).

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class CommandLoader {
  static YamlMap? _config;

  // Call once in main.dart before runApp.
  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/commands.yaml');
    _config = loadYaml(raw) as YamlMap;
  }

  static YamlMap get config {
    assert(_config != null, 'CommandLoader.load() must be called before use.');
    return _config!;
  }

  static String get loadedVersion => config['version']?.toString() ?? '0.0';

  // Builds a BLE request frame. Returns null if command or data is null (pending).
  static List<int>? buildFrame(int? commandByte, List<int>? data) {
    if (commandByte == null || data == null) return null;
    const reqId = 0x06;
    final len = data.length;
    int sum = reqId + commandByte + len;
    for (final b in data) sum += b;
    return [0x55, 0xAA, reqId, commandByte, len, ...data, sum & 0xFF];
  }

  static List<int> statusPoll() =>
      List<int>.from(config['status_poll']['frame'] as YamlList);

  static List<int>? power(String action) {
    final cmd = _safeGet(['commands', 'power']);
    if (cmd == null) return null;
    return buildFrame(cmd['command'] as int?, _toIntList(cmd['actions'][action]));
  }

  static List<int>? speed(int step) {
    assert(step >= 1 && step <= 6);
    final cmd = _safeGet(['commands', 'speed']);
    if (cmd == null) return null;
    return buildFrame(cmd['command'] as int?, _toIntList(cmd['steps'][step]));
  }

  static List<int>? mode(String action) {
    final cmd = _safeGet(['commands', 'modes']);
    if (cmd == null) return null;
    return buildFrame(cmd['command'] as int?, _toIntList(cmd['actions'][action]));
  }

  static List<int>? timer(String action) {
    final cmd = _safeGet(['commands', 'timers']);
    if (cmd == null) return null;
    return buildFrame(cmd['command'] as int?, _toIntList(cmd['actions'][action]));
  }

  static List<int>? queryPower() {
    final q = _safeGet(['commands', 'queries', 'power_consumption']);
    if (q == null) return null;
    return buildFrame(q['command'] as int?, _toIntList(q['data']));
  }

  static List<int>? querySpeed() {
    final q = _safeGet(['commands', 'queries', 'running_speed']);
    if (q == null) return null;
    return buildFrame(q['command'] as int?, _toIntList(q['data']));
  }

  static List<int>? lightOn() {
    final l = _safeGet(['commands', 'lighting', 'on']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, _toIntList(l['data']));
  }

  static List<int>? lightOff() {
    final l = _safeGet(['commands', 'lighting', 'off']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, _toIntList(l['data']));
  }

  static List<int>? lightColorTemp(int value) {
    final l = _safeGet(['commands', 'lighting', 'color_temp']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, [value]);
  }

  // Generic accessor for any new command section added to commands.yaml.
  // Usage: CommandLoader.custom(['commands', 'new_feature', 'action'], [0x01])
  // Returns null gracefully if key path does not exist.
  static List<int>? custom(List<String> path, List<int>? data) {
    final node = _safeGet(path);
    if (node == null) return null;
    final cmd = node is Map ? node['command'] as int? : node as int?;
    return buildFrame(cmd, data);
  }

  // Safe nested map access. Returns null on missing keys instead of throwing.
  static dynamic _safeGet(List<String> path) {
    dynamic node = config;
    for (final key in path) {
      if (node is! YamlMap || !node.containsKey(key)) return null;
      node = node[key];
    }
    return node;
  }

  static List<int>? _toIntList(dynamic yaml) {
    if (yaml == null) return null;
    return List<int>.from((yaml as YamlList).map((e) => e as int));
  }
}
```

---

### 4.4 BleFrameBuilder (thin wrapper over CommandLoader)

```dart
// lib/core/ble/ble_frame_builder.dart
// All frames come from CommandLoader (YAML). This class is a typed facade.
// Do not hardcode any bytes here. Do not call BleFrameBuilder directly from
// UI widgets - always go through ControlScreenNotifier.

import '../commands/command_loader.dart';

class BleFrameBuilder {
  static List<int>  statusPoll()           => CommandLoader.statusPoll();
  static List<int>? powerOn()              => CommandLoader.power('on');
  static List<int>? powerOff()             => CommandLoader.power('off');
  static List<int>? setSpeed(int step)     => CommandLoader.speed(step);
  static List<int>? setBoost()             => CommandLoader.mode('boost');
  static List<int>? setNature()            => CommandLoader.mode('nature');
  static List<int>? setReverse()           => CommandLoader.mode('reverse');
  static List<int>? setSmart()             => CommandLoader.mode('smart');
  static List<int>? timerOff()             => CommandLoader.timer('off');
  static List<int>? timer2h()              => CommandLoader.timer('2h');
  static List<int>? timer4h()              => CommandLoader.timer('4h');
  static List<int>? timer8h()              => CommandLoader.timer('8h');
  static List<int>? queryPower()           => CommandLoader.queryPower();
  static List<int>? querySpeed()           => CommandLoader.querySpeed();
  static List<int>? lightOn()              => CommandLoader.lightOn();
  static List<int>? lightOff()             => CommandLoader.lightOff();
  static List<int>? lightColorTemp(int v)  => CommandLoader.lightColorTemp(v);
}
```

**Note:** All methods return `List<int>?`. If a command is pending (null in YAML), the method returns null. Callers must null-check before writing:
```dart
final frame = BleFrameBuilder.lightOn();
if (frame == null) {
  showSnackBar("Lighting commands pending from Terraton");
  return;
}
await bleService.writeFrame(frame);
```

---

### 4.5 Frame Verification Table

All frames verified against Terraton BLE Module Interfacing Protocol document.

| Operation | Frame (hex) | Checksum derivation |
|---|---|---|
| Status Poll | 55 AA 00 00 01 00 01 | Fixed |
| Power ON | 55 AA 06 02 01 01 0A | 06+02+01+01=0A |
| Power OFF | 55 AA 06 02 01 00 09 | 06+02+01+00=09 |
| Speed 1 | 55 AA 06 04 01 01 0C | 06+04+01+01=0C |
| Speed 2 | 55 AA 06 04 01 02 0D | 06+04+01+02=0D |
| Speed 3 | 55 AA 06 04 01 03 0E | 06+04+01+03=0E |
| Speed 4 | 55 AA 06 04 01 04 0F | 06+04+01+04=0F |
| Speed 5 | 55 AA 06 04 01 05 10 | 06+04+01+05=10 |
| Speed 6 | 55 AA 06 04 01 06 11 | 06+04+01+06=11 |
| Boost | 55 AA 06 21 01 01 29 | 06+21+01+01=29 |
| Nature | 55 AA 06 21 01 02 2A | 06+21+01+02=2A |
| Reverse | 55 AA 06 21 01 03 2B | 06+21+01+03=2B |
| Smart | 55 AA 06 21 01 04 2C | 06+21+01+04=2C |
| Timer OFF | 55 AA 06 22 01 00 29 | 06+22+01+00=29 |
| Timer 2H | 55 AA 06 22 01 02 2B | 06+22+01+02=2B |
| Timer 4H | 55 AA 06 22 01 04 2D | 06+22+01+04=2D |
| Timer 8H | 55 AA 06 22 01 08 31 | 06+22+01+08=31 |
| Query Power | 55 AA 06 23 01 00 2A | 06+23+01+00=2A |
| Query Speed | 55 AA 06 24 01 00 2B | 06+24+01+00=2B |

---

### 4.6 BleResponseParser

```dart
// lib/core/ble/ble_response_parser.dart

class FanResponse {
  final int command;
  final List<int> data;
  const FanResponse({required this.command, required this.data});
}

class BleResponseParser {

  static FanResponse? parse(List<int> bytes) {
    if (bytes.length < 6) return null;
    if (bytes[0] != 0x55 || bytes[1] != 0xAA) return null;
    if (bytes[2] != 0x07) return null;
    final command = bytes[3];
    final dataLen = bytes[4];
    if (bytes.length < 5 + dataLen + 1) return null;
    final data = bytes.sublist(5, 5 + dataLen);
    final received = bytes[5 + dataLen];
    int sum = bytes[2] + bytes[3] + bytes[4];
    for (final b in data) sum += b;
    if ((sum & 0xFF) != received) return null;
    return FanResponse(command: command, data: data);
  }

  static int?  parsePowerWatts(FanResponse r)  => r.command == 0x23 && r.data.isNotEmpty ? r.data[0] : null;
  static int?  parseRpm(FanResponse r)          => r.command == 0x24 && r.data.length >= 2 ? (r.data[0] << 8) | r.data[1] : null;
  static bool? parsePowerState(FanResponse r)   => r.command == 0x02 && r.data.isNotEmpty ? r.data[0] == 0x01 : null;
  static int?  parseSpeed(FanResponse r)        => r.command == 0x04 && r.data.isNotEmpty ? r.data[0] : null;
  static int?  parseMode(FanResponse r)         => r.command == 0x21 && r.data.isNotEmpty ? r.data[0] : null;
  static int?  parseTimer(FanResponse r)        => r.command == 0x22 && r.data.isNotEmpty ? r.data[0] : null;
}
```

---

### 4.7 BleService Interface

```dart
abstract class BleService {
  // Scan by service UUID. If macAddress is non-empty, auto-connect to that device.
  Future<void> startScan({String? targetMac, int timeoutSeconds = 10});
  Future<void> stopScan();
  Future<String> connect();  // Returns MAC address of connected device
  Future<void> disconnect();
  Future<void> writeFrame(List<int> frame);
  Stream<List<int>>          get notifyStream;
  Stream<BleConnectionState> get connectionStateStream;
  BleConnectionState         get currentState;
  // Returns list of discovered devices for BLE scan onboarding mode.
  Stream<List<DiscoveredFan>> get scanResultsStream;
}

class DiscoveredFan {
  final String macAddress;
  final String name;   // BLE advertising name if available; else macAddress
  final int rssi;
  const DiscoveredFan({required this.macAddress, required this.name, required this.rssi});
}
```

---

### 4.8 Response Dispatch in ControlScreenNotifier

```dart
bleService.notifyStream.listen((bytes) {
  final response = BleResponseParser.parse(bytes);
  if (response == null) return;
  switch (response.command) {
    case 0x02: final v = BleResponseParser.parsePowerState(response); if (v != null) _updatePower(v);
    case 0x04: final v = BleResponseParser.parseSpeed(response);      if (v != null) _updateSpeed(v);
    case 0x21: final v = BleResponseParser.parseMode(response);       if (v != null) _updateMode(v);
    case 0x22: final v = BleResponseParser.parseTimer(response);      if (v != null) _updateTimer(v);
    case 0x23: final v = BleResponseParser.parsePowerWatts(response); if (v != null) _updateWatts(v);
    case 0x24: final v = BleResponseParser.parseRpm(response);        if (v != null) _updateRpm(v);
  }
});
```

---

### 4.9 Telemetry Polling

```dart
_telemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
  if (bleService.currentState != BleConnectionState.connected) return;
  final pFrame = BleFrameBuilder.queryPower();
  final sFrame = BleFrameBuilder.querySpeed();
  if (pFrame != null) await bleService.writeFrame(pFrame);
  await Future.delayed(const Duration(milliseconds: 200));
  if (sFrame != null) await bleService.writeFrame(sFrame);
});
```

---

### 4.10 FanRepository Interface

```dart
abstract class FanRepository {
  List<FanDevice> getAllFans();
  FanDevice? getFanByDeviceId(String deviceId);
  FanDevice? getFanByMac(String macAddress);
  Future<void> saveFan(FanDevice fan);
  Future<void> updateMac(String deviceId, String macAddress);
  Future<void> deleteFan(String deviceId);
  Future<void> renameFan(String deviceId, String newNickname);
  FanState getState(String deviceId);
  Future<void> saveState(FanState state);
  String exportToJson();
  Future<int> importFromJson(String json);
}
```

---

### 4.11 Export JSON Schema

```json
{
  "version": 1,
  "exported_at": "2026-05-01T10:00:00Z",
  "fans": [
    {
      "device_id":   "TT-FAN-00123",
      "mac_address": "A4:C1:38:2F:1B:9E",
      "model":       "Terraton X1",
      "nickname":    "Bedroom Fan",
      "fw_version":  "1.0",
      "added_at":    "2026-04-10T08:00:00Z"
    }
  ]
}
```

---

## 5. Sequenced Build Order

> Follow these steps in exact order. Each step must compile before proceeding.

### Step 1 - Project Scaffold & Dependencies

```bash
flutter create terraton_fan_app --org com.terraton --platforms android
cd terraton_fan_app
```

**pubspec.yaml:**
```yaml
environment:
  sdk: ^3.9.0
  flutter: ">=3.41.0"

dependencies:
  flutter:
    sdk: flutter

  # BLE v5.2; last updated Feb 2026
  flutter_blue_plus: ^2.2.1

  # QR scanner; last updated Apr 2026; requires Flutter >=3.29 (satisfied)
  mobile_scanner: ^7.2.0

  # YAML parsing for commands.yaml; last updated Dec 2024; SDK ^3.4.0 (satisfied)
  yaml: ^3.1.3


  # Local DB; last updated Mar 2026; actively maintained
  # Hive (abandoned Jun 2022) and Isar (abandoned Apr 2023) are NOT used.
  objectbox: ^5.3.1
  objectbox_flutter_libs: ^5.3.1

  # State management with annotation API; last updated Apr 2026
  flutter_riverpod: ^3.3.1
  riverpod_annotation: ^4.0.2

  # Navigation; last updated Apr 2026; requires Flutter >=3.35 (satisfied)
  go_router: ^17.2.3

  # File sharing; last updated Mar 2026; requires Flutter >=3.38.1 (satisfied)
  share_plus: ^13.1.0

  # File picker for import
  file_picker: ^11.0.2

  # Runtime permissions; last updated Feb 2026
  permission_handler: ^12.0.1

  path_provider: ^2.1.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  objectbox_generator: ^5.3.1
  riverpod_generator: ^4.0.3
  build_runner: ^2.15.0
  flutter_lints: ^6.0.0
  mocktail: ^1.0.5

flutter:
  assets:
    - assets/commands.yaml
```

```bash
flutter pub get
flutter analyze   # No issues found!
```

---

### Step 2 - Android Permissions

**android/app/src/main/AndroidManifest.xml** inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
```

Set `minSdkVersion 21` in `android/app/build.gradle`.

---

### Step 3 - Config & Constants

1. Create `assets/commands.yaml` exactly as in Section 4.2.
2. Create `lib/core/config/app_config.dart` exactly as in Section 1.5.
3. Create `lib/core/ble/ble_constants.dart` exactly as in Section 1.4.
4. Note: Phase 2 will add remote fetch from a hosted URL. For Phase 1, the bundled asset is the only source.

---

### Step 4 - Data Models & ObjectBox

1. Create `lib/models/fan_device.dart` as in Section 3.2.
2. Create `lib/models/fan_state.dart` as in Section 3.2.
3. Run: `flutter pub run build_runner build --delete-conflicting-outputs`
4. Verify: `objectbox.g.dart` generated.
5. Create `lib/core/storage/objectbox_store.dart` with `openStore()` singleton.

---

### Step 5 - Command Loader

1. Create `lib/core/commands/command_loader.dart` exactly as in Section 4.3.
2. Create `lib/core/ble/ble_frame_builder.dart` exactly as in Section 4.4.
3. Unit tests in `test/unit/command_loader_test.dart`:
   - `CommandLoader.load()` with bundled asset parses without error.
   - `CommandLoader.power('on')` returns `[0x55,0xAA,0x06,0x02,0x01,0x01,0x0A]`.
   - `CommandLoader.speed(3)` returns `[0x55,0xAA,0x06,0x04,0x01,0x03,0x0E]`.
   - `CommandLoader.mode('nature')` returns `[0x55,0xAA,0x06,0x21,0x01,0x02,0x2A]`.
   - `CommandLoader.timer('4h')` returns `[0x55,0xAA,0x06,0x22,0x01,0x04,0x2D]`.
   - `CommandLoader.lightOn()` returns null (pending in YAML).
   - `CommandLoader.custom(['commands','nonexistent','action'], [0x01])` returns null gracefully when key absent.
   - All 19 frames in Section 4.5 verified byte-for-byte.
4. Unit tests in `test/unit/ble_frame_builder_test.dart`:
   - All `BleFrameBuilder.*()` methods return correct frames via CommandLoader.

---

### Step 6 - Fan Repository

1. Create `lib/core/storage/fan_repository.dart` implementing Section 4.10.
2. `importFromJson`: validate version field; require `device_id`, `mac_address`, `nickname` per fan; skip existing `device_id`.
3. Unit tests in `test/unit/fan_repository_test.dart`.

---

### Step 7 - BLE Layer

1. Create `lib/core/ble/ble_connection_state.dart`.
2. Create `lib/core/ble/ble_response_parser.dart` as in Section 4.6.
3. Create `lib/core/ble/ble_service.dart` implementing Section 4.7:
   - `startScan`: always filter by `Guid(kServiceUUID)`.
   - If `targetMac` provided: ignore other devices; connect only to matching MAC.
   - If no `targetMac`: expose all discovered devices via `scanResultsStream`.
   - On `connect()`: discover services, cache write + notify chars by constants, `setNotifyValue(true)`, subscribe to `onValueReceived`, return MAC address string.
   - Auto-reconnect: 3 retries, 5-second intervals.
4. Unit tests in `test/unit/ble_response_parser_test.dart`.

---

### Step 8 - Riverpod Providers

Create `lib/core/providers.dart` using `riverpod_annotation`. Run build_runner after.

```dart
@riverpod BleService bleService(Ref ref) => BleServiceImpl();
@riverpod Stream<BleConnectionState> bleConnectionState(Ref ref) => ref.watch(bleServiceProvider).connectionStateStream;
@riverpod FanRepository fanRepository(Ref ref) => FanRepositoryImpl();
@riverpod List<FanDevice> savedFans(Ref ref) => ref.watch(fanRepositoryProvider).getAllFans();

@riverpod
class ActiveFan extends _$ActiveFan {
  @override FanDevice? build() => null;
  void set(FanDevice fan) => state = fan;
}

@riverpod
class ActiveFanState extends _$ActiveFanState {
  @override
  FanState build() {
    final id = ref.watch(activeFanProvider)?.deviceId ?? '';
    return ref.watch(fanRepositoryProvider).getState(id);
  }
  void update(FanState s) => state = s;
}
```

---

### Step 9 - App Shell

1. `lib/shared/theme.dart`: Primary `Color(0xFF1A56A0)`, background `Color(0xFFF5F7FA)`, Material 3. Speed colour array per AC-05-3.
2. `lib/shared/router.dart`: GoRouter routes:
   ```
   /           -> HomeScreen
   /scan/qr    -> QrScanScreen     (only reachable when OnboardingMode.qrScan)
   /scan/ble   -> BleScanScreen    (only reachable when OnboardingMode.bleScan)
   /name-fan   -> NameFanScreen    (shared; receives FanDevice as extra)
   /control    -> ControlScreen    (receives FanDevice as extra)
   /settings   -> SettingsScreen
   ```
   The FAB on HomeScreen navigates to `/scan/qr` or `/scan/ble` based on `AppConfig.onboardingMode`.
3. `lib/main.dart`: `await CommandLoader.load()`, `initObjectBox()`, `ProviderScope`, `runApp()`.

---

### Step 10 - Screens

**10a. HomeScreen**: Watch `savedFansProvider`. FAB routes based on `AppConfig.onboardingMode`. Empty state. `FanCard` list.

**10b. FanCard**: Nickname, model, last connected. `onTap`: set `activeFanProvider`, go to `/control`. `onLongPress`: Rename/Delete bottom sheet.

**10c. QrScanScreen** (qrScan mode only):
- Full-screen `MobileScanner`.
- Parse JSON with 3 required fields: `device_id`, `model`, `fw_version`.
- Valid: navigate to `/name-fan` with partial `FanDevice` (no MAC yet).
- Invalid: SnackBar, keep scanning.

**10d. BleScanScreen** (bleScan mode only):
- `initState`: `bleService.startScan()` with no targetMac.
- Watch `scanResultsStream`: show `ListView` of `DiscoveredFan` items (name/MAC + RSSI bars).
- Already-saved fans (matched by MAC via `fanRepository.getFanByMac(mac)`): show grey badge "Already added", disable tap.
- Tap undiscovered fan: navigate to `/name-fan` with `FanDevice(deviceId: mac, macAddress: mac, nickname: '')`.
- Refresh button restarts scan.
- 15-second timeout with "No fans found" state.

**10e. NameFanScreen** (shared):
- Receives `FanDevice` as GoRouter extra.
- TextField pre-filled with `fan.model.isNotEmpty ? fan.model : 'Terraton Fan'`.
- Validate and save. Navigate to `/control`.

**10f. ControlScreen**:
- `initState`: `bleService.startScan(targetMac: activeFan.macAddress.isNotEmpty ? activeFan.macAddress : null)`.
- On connect: if `fan.macAddress.isEmpty`: call `fanRepository.updateMac(fan.deviceId, returnedMac)`.
- Start telemetry timer (Section 4.9). Subscribe to notifyStream (Section 4.8).
- `dispose`: disconnect, cancel timer.
- Body: `ConnectionBanner`, Power button, `CircularSpeedDial`, `ModeControlWidget`, `TimerControlWidget`, `LightingControlWidget`.

**10g-10k.** ConnectionBanner, CircularSpeedDial, ModeControlWidget, TimerControlWidget, LightingControlWidget — per acceptance criteria in US-05. LightingControlWidget checks `BleFrameBuilder.lightOn() == null` to show pending SnackBar.

**10l. SettingsScreen**: Export (share_plus) and Import (file_picker) per US-07.

---

### Step 11 - Widget Tests

`test/widget/control_screen_test.dart` with mocked `BleService`:
- Speed 1 tap: `writeFrame([0x55,0xAA,0x06,0x04,0x01,0x01,0x0C])`.
- Speed 3 tap: `writeFrame([0x55,0xAA,0x06,0x04,0x01,0x03,0x0E])`.
- Boost tap: `writeFrame([0x55,0xAA,0x06,0x21,0x01,0x01,0x29])`.
- All buttons disabled when `BleConnectionState.disconnected`.
- Light button when null: SnackBar shown, `writeFrame` NOT called.

---

### Step 12 - Final Checks

```bash
flutter analyze              # No issues found!
flutter test                 # All tests passed
flutter build apk --release  # Clean build
```

---

## 6. Constraints & Non-Goals

### 6.1 Hard Constraints
- **UUID constants in one file only**: `ble_constants.dart`. No UUID string anywhere else.
- **Commands in YAML only**: `assets/commands.yaml`. No command byte hardcoded in Dart.
- **No backend**: Fully offline. No HTTP calls in Phase 1. Remote command loading is approved for Phase 2 but not implemented here.
- **Framed packets only**: Every write uses `BleFrameBuilder` which reads from `CommandLoader`.
- **No voice control**: Hardware feature (VC10 chip). No speech code in this app.
- **ObjectBox only**: No Hive, no Isar, no SharedPreferences for fan data.
- **Android only**: No iOS build.
- **Single active BLE connection**: One fan at a time.
- **Onboarding toggle is compile-time only**: `AppConfig.onboardingMode` is a `const`. Not a runtime setting. Both flows are fully implemented; only one is active per build.

### 6.2 Non-Goals
- iOS build
- Voice commands (hardware feature)
- Cloud sync or accounts
- WiFi control
- Fan firmware OTA
- Smart home integration
- Energy history charts
- Scheduling
- Dark mode
- Push notifications

### 6.3 Assumptions
- All Terraton fans share the same 3 UUIDs (confirmed May 2026).
- Individual fans identified by BLE MAC address captured on first connect.
- YAML commands file is bundled as an asset; updated by replacing the file and rebuilding.
- Lighting command bytes will follow the same frame structure as other commands; only byte values are pending.
- Minimum Android API: 21.
- Flutter 3.41.x / Dart 3.9.x.
