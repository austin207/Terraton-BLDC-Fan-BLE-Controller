# Terraton BLDC Fan BLE Controller

Android app that controls a Terraton BLDC ceiling fan over Bluetooth Low Energy 5.2 via an Amp'ed RF BLE60 module. Fully offline — no backend, no cloud, no internet required.

```
Flutter App  ──BLE 5.2──►  Amp'ed RF BLE60  ──UART──►  Fan MCU  ──►  BLDC Motor
```

---

## Features

| Category | Details |
|---|---|
| **Pairing** | BLE scan or QR code |
| **Fan control** | Power, 6 speed steps, Boost / Nature / Reverse / Smart modes, 2 / 4 / 8 h sleep timer |
| **Mood Lighting** | ON/OFF toggle + warm↔cool colour temperature slider *(command bytes pending from Terraton)* |
| **Telemetry** | Live watts and RPM polled every 3 s; stale values clear after 5 s |
| **Multi-fan** | Manage multiple fans from a single home screen |
| **Storage** | Fan metadata and last-known state persisted with ObjectBox |
| **Backup** | Export / import fan list as JSON |
| **Permissions** | Guided BT permission screen with retry, app-settings deep-link, demo-mode fallback |
| **User Manual** | In-app manual — 8 expandable sections |

---

## Architecture

### Data flow

```
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once at startup; static singleton
        │
        ▼
  BleFrameBuilder          ← typed facade; all frame construction lives here
        │
        ▼
  BleService / BleServiceImpl   (flutter_blue_plus)
        │  connect(mac) ────► GATT connect → service discovery → characteristic setup
        │  writeFrame()  ──► fan hardware
        │  notifyStream  ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox) ← persists FanDevice + FanState
```

### Startup sequence (`main.dart`)

1. `CommandLoader.load()` — loads `assets/commands.yaml` into static singleton
2. `initObjectBox()` — opens ObjectBox store
3. `FlutterBluePlus.turnOn()` — shows system BT enable dialog if adapter is off
4. `runApp()` — permission check handled in `SplashScreen` after 2 s delay

### State management

- **Riverpod 2.x** — `StateNotifierProvider.autoDispose.family` for per-fan control state, `FutureProvider` for the saved fan list
- **Navigation** — GoRouter with typed constants in `AppRoutes`; `nameFan` and `control` routes redirect to home if `extra == null`
- **Storage** — ObjectBox: `FanDevice` (identity/metadata) + `FanState` (last-known control state)

---

## BLE Protocol

### Connection

| Field | Value |
|---|---|
| Scan filter (advertisement) | `00001827-0000-1000-8000-00805f9b34fb` — BLE Mesh Proxy |
| Write characteristic | `00002adb-0000-1000-8000-00805f9b34fb` — Mesh Proxy Data In |
| Notify characteristic | `00002adc-0000-1000-8000-00805f9b34fb` — Mesh Proxy Data Out |

Service discovery also searches CC254X / HM-10, Nordic UART Service, and Microchip RN4870 profiles as fallbacks, in that priority order.

### Frame format

```
[ 0x55  0xAA  packetId  command  dataLen  ...data  checksum ]
```

- **Request:** `packetId = 0x06`
- **Response:** `packetId = 0x07`
- **Checksum:** sum of **every byte before the checksum**, including the `0x55 0xAA` header:

```
checksum = (0x55 + 0xAA + packetId + command + dataLen + Σ data) & 0xFF
```

### BLE60 bridge behaviour

The Amp'ed RF BLE60 is a BLE-to-UART transparent bridge. It buffers all incoming BLE writes and only flushes to the MCU UART when it receives `\r\n` (0x0D 0x0A). The app appends `0x0D 0x0A` to every frame automatically inside `BleServiceImpl.writeFrame()`.

On every new BLE connection the BLE60 also sends its own initialisation bytes over UART **before** any app data:

```
FF FF FF FF FF FF FF FF FF
AT-AB -CommandMode-\r\n
AT-AB BDAddress <mac>\r\n
AT-AB -BLE-ConnectionUp <addr>\r\n
AT-AB -BypassMode-\r\n          ← transparent mode starts here
```

**MCU firmware must scan for the `55 AA` header and skip all other bytes**, including these AT strings and the trailing `0D 0A` after each frame.

### Command table

Manually verified against hardware — these are the exact byte sequences the MCU accepts:

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
| Status poll | `55 AA 00 00 01 00 01` *(non-standard fixed frame)* |
| Lighting ON/OFF/colour temp | *Pending — command bytes not yet provided by Terraton* |

---

## Project Structure

```
terraton_fan_app/
├── assets/
│   └── commands.yaml              # Single source of truth for all BLE command bytes
├── lib/
│   ├── core/
│   │   ├── ble/
│   │   │   ├── ble_constants.dart         # All UUID constants (only location)
│   │   │   ├── ble_connection_state.dart  # Enum: disconnected/scanning/connecting/connected
│   │   │   ├── ble_frame_builder.dart     # Typed facade — returns null for pending commands
│   │   │   ├── ble_response_parser.dart   # Validates response frames; byte → name mapping
│   │   │   └── ble_service.dart           # BleServiceImpl: scan/connect/disconnect/writeFrame
│   │   ├── commands/
│   │   │   └── command_loader.dart        # YAML singleton; buildFrame(); custom()
│   │   ├── providers.dart                 # All Riverpod providers; ActiveFanStateNotifier
│   │   └── storage/
│   │       ├── fan_repository.dart        # ObjectBox CRUD + JSON export/import
│   │       └── objectbox_store.dart       # Singleton Store init
│   ├── features/
│   │   ├── control/                       # ControlScreen, speed dial, mode/timer/lighting widgets
│   │   ├── home/                          # HomeScreen, FanCard
│   │   ├── onboarding/                    # BleScanScreen, QrScanScreen, NameFanScreen
│   │   ├── permission/                    # BlePermissionScreen
│   │   ├── settings/                      # SettingsScreen, UserManualScreen
│   │   └── splash/                        # SplashScreen
│   ├── models/                            # FanDevice, FanState (ObjectBox entities)
│   └── shared/                            # AppRoutes, GoRouter, theme, FanIcon
└── test/
    ├── unit/                              # 110+ unit tests: frames, parser, repository, state
    └── widget/                            # ControlScreen widget tests
```

---

## Getting Started

### Requirements

- Flutter 3.29+ with Dart 3.8+
- Android device (API 21+) or emulator
- Android SDK

### Emulator

Two AVDs are configured: **S24 Ultra** and **Medium Phone API 36.0**.

```powershell
# From repo root — launch S24 Ultra emulator
.\launch-emulator.ps1

# Launch and immediately run the app once boot finishes
.\launch-emulator.ps1 -Run

# Emulator is already running — just start the app
.\launch-emulator.ps1 -RunOnly
```

> **Emulator already on but no app?**
> The quickest way is:
> ```powershell
> cd terraton_fan_app; flutter run -d emulator-5554
> ```

### Run locally

```powershell
# From terraton_fan_app/
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # regenerate ObjectBox code
flutter run                    # auto-selects the connected device/emulator
flutter run -d emulator-5554   # target a specific emulator by ID
```

### Release APK

```powershell
# From repo root
.\build.ps1
```

Signed APK is saved to `builds/` and published to GitHub Releases automatically.

---

## Development

```powershell
# Static analysis
flutter analyze --no-fatal-infos

# All tests
flutter test

# Single test file
flutter test test/unit/ble_frame_builder_test.dart

# Regenerate ObjectBox & Riverpod code (run after editing models or providers)
dart run build_runner build --delete-conflicting-outputs
```

### Adding a new BLE command

1. Add the entry to `assets/commands.yaml` under the appropriate section (set `command: null` if bytes are not yet known).
2. Add a named method to `BleFrameBuilder` calling `CommandLoader.custom([...], data)`.
3. Wire it to the UI in `ControlScreen._send()`.
4. If the fan sends a response, add a `parse*` helper to `BleResponseParser` and dispatch it in `ControlScreen._subscribeNotify()`.

No other files need changing — the YAML is the single source of truth for all byte values.

---

## Hard Constraints

| Constraint | Rule |
|---|---|
| UUID constants | Live **only** in `ble_constants.dart` — never duplicated |
| Command bytes | Live **only** in `assets/commands.yaml` — never hardcoded in Dart |
| BLE writes | Always go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()` |
| Storage | ObjectBox only — no Hive, Isar, or SharedPreferences |
| Platform | Android only — no iOS build target |
| Connections | One fan at a time — single active BLE connection |
| Network | No backend, no HTTP — Phase 1 is fully offline |

---

## Roadmap

| Phase | Feature | Status |
|---|---|---|
| 1 | BLE connectivity on all Android phones | ✅ Complete |
| 1 | Full fan control — power, speed, modes, timers | ✅ Complete |
| 1 | Live telemetry — watts and RPM | ✅ Complete |
| 1 | Multi-fan management and persistence | ✅ Complete |
| 1 | QR code and BLE scan onboarding | ✅ Complete |
| 1 | Permissions screen, splash, demo mode | ✅ Complete |
| 1 | In-app User Manual | ✅ Complete |
| 2 | Lighting control | ⏳ UI complete — awaiting command bytes from Terraton |
| 2 | Remote command updates (fetch `commands.yaml` from URL) | 📋 Planned |

---

## Author

Antony Austin — College Project, May 2026
