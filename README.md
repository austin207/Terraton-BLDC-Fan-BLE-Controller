# Terraton BLDC Fan BLE Controller

An Android app for controlling the Terraton BLDC ceiling fan over Bluetooth Low Energy v5.2 via an Amp'ed RF BLE60 module. Fully offline — no backend, no cloud.

---

## Features

- **Pair fans** via Bluetooth scan or QR code
- **Manage multiple fans** from a single home screen
- **Full fan control** — power, 6 speed steps, boost mode, nature/reverse/smart operating modes, 2/4/8-hour sleep timer
- **Mood Lighting** — ON/OFF toggle and warm↔cool colour temperature slider *(BLE command bytes pending from Terraton)*
- **Live telemetry** — real-time watts and RPM polled every 3 seconds; stale values clear after 5 s
- **Persistent storage** — fan metadata and last-known state saved with ObjectBox
- **Export / import** — back up and restore fan list as JSON
- **Bluetooth permission handling** — guided permission screen with retry, app-settings deep-link, and demo-mode fallback
- **In-app User Manual** — eight expandable sections covering setup, controls, modes, timer, lighting, and troubleshooting

---

## Architecture

```
Flutter App  ──BLE v5.2──►  BLE60 Module  ──UART1──►  Fan MCU  ──►  BLDC Motor
```

```
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once at startup; single source of truth for all BLE bytes
        │
        ▼
  BleFrameBuilder          ← typed facade; all frame construction lives here
        │
        ▼
  BleService (abstract) / BleServiceImpl (flutter_blue_plus)
        │  writeFrame() ──► fan hardware
        │  notifyStream ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox) ← persists FanDevice + FanState
```

**State management:** Riverpod 2.x — `StateNotifierProvider.autoDispose.family` for per-fan control state, `FutureProvider` for the fan list.

**Navigation:** GoRouter with typed route constants in `AppRoutes`.

**Storage:** ObjectBox — two entities: `FanDevice` (identity/metadata) and `FanState` (last-known control state).

---

## BLE Protocol

| Field | Value |
|---|---|
| Service UUID | `00001827-0000-1000-8000-00805f9b34fb` (BLE Mesh Proxy) |
| Write characteristic | `00002adb-0000-1000-8000-00805f9b34fb` |
| Notify characteristic | `00002adc-0000-1000-8000-00805f9b34fb` |

**Frame format:** `[0x55, 0xAA, packetId, command, dataLen, ...data, checksum]`
- Request: `packetId = 0x06` · Response: `packetId = 0x07`
- **Checksum:** lower byte of the sum of **all** bytes before the checksum (including `0x55` and `0xAA`):
  `checksum = (0x55 + 0xAA + packetId + command + dataLen + sum(data)) & 0xFF`

**BLE60 bridge note:** The Amp'ed RF BLE60 is a BLE-to-UART transparent bridge. It buffers incoming BLE writes and only flushes to the MCU's UART when it receives `\r\n` (0x0D 0x0A). The app appends `0x0D 0x0A` to every frame automatically. The MCU UART parser must scan for the `55 AA` header and ignore the trailing `0D 0A` bytes.

**Command table** — manually verified against hardware (exact frames the MCU accepts):

| Operation | Frame (hex) |
|---|---|
| Power ON | `55 AA 06 02 01 01 09` |
| Power OFF | `55 AA 06 02 01 00 08` |
| Speed 1 | `55 AA 06 04 01 01 0B` |
| Speed 2 | `55 AA 06 04 01 02 0C` |
| Speed 3 | `55 AA 06 04 01 03 0D` |
| Speed 4 | `55 AA 06 04 01 04 0E` |
| Speed 5 | `55 AA 06 04 01 05 0F` |
| Speed 6 | `55 AA 06 04 01 06 10` |
| Boost mode | `55 AA 06 21 01 01 28` |
| Nature mode | `55 AA 06 21 01 02 29` |
| Reverse mode | `55 AA 06 21 01 03 2A` |
| Smart mode | `55 AA 06 21 01 04 2B` |
| Timer OFF | `55 AA 06 22 01 00 28` |
| Timer 2 h | `55 AA 06 22 01 02 2A` |
| Timer 4 h | `55 AA 06 22 01 04 2C` |
| Timer 8 h | `55 AA 06 22 01 08 30` |
| Query power (watts) | `55 AA 06 23 01 00 29` |
| Query speed (RPM) | `55 AA 06 24 01 00 2A` |

---

## Project Structure

```
terraton_fan_app/
├── assets/
│   └── commands.yaml          # Single source of truth for all BLE command bytes
├── lib/
│   ├── core/
│   │   ├── ble/               # BleService, BleFrameBuilder, BleResponseParser, constants
│   │   ├── commands/          # CommandLoader — parses commands.yaml at startup
│   │   ├── providers.dart     # All Riverpod providers
│   │   └── storage/           # FanRepository interface + ObjectBox implementation
│   ├── features/
│   │   ├── control/           # ControlScreen, CircularSpeedDial, mode/timer/lighting widgets
│   │   ├── home/              # HomeScreen, FanCard
│   │   ├── onboarding/        # BleScanScreen, QrScanScreen, NameFanScreen
│   │   ├── permission/        # BlePermissionScreen — handles denied/revoked BT permissions
│   │   ├── settings/          # SettingsScreen (export/import, about), UserManualScreen
│   │   └── splash/            # SplashScreen — animated dots, permission routing
│   ├── models/                # FanDevice, FanState (ObjectBox entities)
│   └── shared/                # AppRoutes, GoRouter config, theme
└── test/
    ├── unit/                  # CommandLoader, BleFrameBuilder, BleResponseParser,
    │                          #   FanRepository, ActiveFanStateNotifier (111 tests total)
    └── widget/                # ControlScreen widget tests
```

---

## Getting Started

### Requirements

- Flutter 3.29+ with Dart 3.8+
- Android device or emulator (API 21+)
- Android SDK with build tools

### Build & run

```powershell
# From terraton_fan_app/
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # regenerate ObjectBox code
flutter run
```

### Release APK (from repo root)

```powershell
.\build.ps1
```

The signed APK is saved to `builds/` and published to GitHub Releases.

---

## Development

```powershell
# Analyze
flutter analyze --no-fatal-infos

# Run all tests
flutter test

# Run a single test file
flutter test test/unit/ble_frame_builder_test.dart

# Regenerate ObjectBox & Riverpod code after editing models or providers
dart run build_runner build --delete-conflicting-outputs
```

### Adding a new BLE command

1. Add the command bytes to `assets/commands.yaml` under the appropriate section.
2. Add a named method to `BleFrameBuilder` that calls `CommandLoader.custom(...)`.
3. If the fan responds, add a `parse*` method to `BleResponseParser` and a dispatch case in `ControlScreen._subscribeNotify()`.
4. No other files need changing — the YAML is the single source of truth.

---

## Hard Constraints

- UUID constants live **only** in `ble_constants.dart`
- Command bytes live **only** in `assets/commands.yaml` — never hardcoded in Dart
- All BLE writes go through `BleFrameBuilder` → `CommandLoader`
- ObjectBox only for fan data — no Hive, Isar, or SharedPreferences
- Android only — no iOS build
- Single active BLE connection — one fan at a time
- No backend, no HTTP in Phase 1

---

## Roadmap

| Phase | Feature | Status |
|---|---|---|
| 1 | Core BLE control (power, speed, modes, timer, telemetry) | ✅ Complete |
| 1 | Multi-fan management & persistence | ✅ Complete |
| 1 | QR + BLE onboarding | ✅ Complete |
| 1 | Splash screen + BT permission screen | ✅ Complete |
| 1 | In-app User Manual | ✅ Complete |
| 2 | Lighting control (UI complete) | ⏳ Pending BLE command bytes from Terraton |
| 2 | Remote command loading (fetch updated `commands.yaml` from URL) | 📋 Planned |

---

## Author

Antony Austin — College Project, May 2026
