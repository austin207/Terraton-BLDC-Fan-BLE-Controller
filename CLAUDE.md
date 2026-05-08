# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Overview

Android Flutter app that controls a Terraton BLDC ceiling fan over BLE v5.2 via an Amp'ed RF BLE60 module. Fully offline — no backend, no cloud, no HTTP in Phase 1.

```
Flutter App --BLE v5.2--> BLE60 Module --UART1--> Fan MCU --> BLDC Motor
```

The app writes framed packets to the Write Characteristic; the fan responds on the Notify Characteristic.

---

## Commands

All Flutter commands run from `terraton_fan_app/`.

```powershell
# Analyze
flutter analyze --no-fatal-infos

# Run all tests
flutter test

# Run a single test file
flutter test test/unit/ble_frame_builder_test.dart
flutter test test/widget/control_screen_test.dart

# Build — saves to builds/ and publishes to GitHub Releases (run from repo root)
.\build.ps1

# Regenerate ObjectBox & Riverpod code (run after editing models or providers)
dart run build_runner build --delete-conflicting-outputs
```

---

## Architecture

### Data flow

```
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once in main.dart before runApp; static singleton
        │
        ▼
  BleFrameBuilder          ← typed facade; all frame construction goes here
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

### BLE Protocol

Request frame: `[0x55, 0xAA, 0x06, <cmd>, <len>, ...data, <checksum>]`
Response frame: same but byte 3 is `0x07` instead of `0x06`.
Checksum: `(packetId + command + dataLen + sum(data)) & 0xFF`
Status poll uses a fixed non-standard 7-byte frame: `[55 AA 00 00 01 00 01]`

**Confirmed BLE UUIDs (same for every Terraton unit — defined only in `ble_constants.dart`):**
- Service: `00001827-0000-1000-8000-00805f9b34fb` (BLE Mesh Proxy)
- Write char: `00002adb-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data In)
- Notify char: `00002adc-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data Out — also Read/Notify; call `setNotifyValue(true)`)

**Verified frame table (from Terraton BLE Module Interfacing Protocol):**

| Operation | Frame (hex) |
|-----------|-------------|
| Power ON | `55 AA 06 02 01 01 0A` |
| Power OFF | `55 AA 06 02 01 00 09` |
| Speed 1–6 | `55 AA 06 04 01 0N (06+04+01+N)` |
| Boost | `55 AA 06 21 01 01 29` |
| Nature | `55 AA 06 21 01 02 2A` |
| Reverse | `55 AA 06 21 01 03 2B` |
| Smart | `55 AA 06 21 01 04 2C` |
| Timer OFF/2H/4H/8H | `55 AA 06 22 01 00/02/04/08 29/2B/2D/31` |
| Query Power | `55 AA 06 23 01 00 2A` |
| Query Speed | `55 AA 06 24 01 00 2B` |

### Onboarding flow

`goToOnboarding(context)` in `router.dart` shows a bottom sheet with two options:
- **Search via Bluetooth** → `/scan/ble` — BLE scan list; user picks device; 15 s timeout.
- **Scan QR Code** → `/scan/qr` — reads `device_id`, `model`, `fw_version` from QR JSON.

Both paths end at `/name-fan` (receives a `FanDevice` as GoRouter `extra`), then `/control`.

> **Note:** The PRD (v7) specifies a compile-time toggle via `AppConfig.onboardingMode`. The actual implementation offers both modes at runtime via a bottom sheet picker. `app_config.dart` has been removed.

### Riverpod providers (`lib/core/providers.dart`)

- `bleServiceProvider` — singleton `BleServiceImpl`; one BLE connection at a time.
- `bleConnectionStateProvider` — `StreamProvider` wrapping `connectionStateStream`.
- `fanRepositoryProvider` — singleton `FanRepositoryImpl` (ObjectBox).
- `savedFansProvider` — derives from repo; call `ref.invalidate(savedFansProvider)` after writes.
- `activeFanProvider` — `StateNotifierProvider<FanDevice?>` set when user opens a fan.
- `activeFanStateProvider` — `StateNotifierProvider<FanState>` updated by BLE notifications; mutate only through its named `update*` methods.

**Riverpod 2.x constraint:** `ref.read()` is forbidden inside `dispose()`. Cache any needed service in `initState()` as a field (see `control_screen.dart:37`).

### Storage

ObjectBox entities: `FanDevice` (identity/metadata) and `FanState` (last-known control state).
`FanDevice.deviceId` is the stable primary key assigned at onboarding. `macAddress` starts empty and is filled by `FanRepository.updateMac()` on first successful BLE connection.
`objectbox.g.dart` is generated — do not edit manually. Run `build_runner` after changing either model.

### Commands YAML (`assets/commands.yaml`)

Single source of truth for all BLE command bytes. Adding a new command or filling in pending lighting bytes requires only a YAML edit — no Dart changes needed. `CommandLoader._safeGet()` returns `null` gracefully for missing keys; `BleFrameBuilder` propagates the `null`; `ControlScreen._send()` shows a SnackBar instead of crashing. Lighting commands are currently `null` — pending values from Terraton.

**To add a new command:** add it to `commands.yaml`, then call `CommandLoader.custom(['commands', 'your_section', 'action'], [0xXX])` or add a named method to `BleFrameBuilder`.

**Phase 2 (approved, not yet built):** Remote command loading — app fetches `commands.yaml` from a hosted URL on launch, compares `version` field, updates local cache if newer, falls back to bundled asset on failure. No app update needed to deploy new command bytes.

### Control screen telemetry

Polls every 3 seconds after connect: `queryPower` frame → 200 ms delay → `querySpeed` frame. Responses arrive on `notifyStream` and are dispatched by command byte (`0x02`–`0x24`) to the appropriate `ActiveFanStateNotifier.update*()` method.

### Speed dial colours (AC-05-3)

Speed 1 `#1E8449` · Speed 2 `#1A56A0` · Speed 3 `#7D3C98` · Speed 4 `#D4AC0D` · Speed 5 `#D35400` · Speed 6 `#C0392B`

---

## Hard Constraints (from PRD §6.1)

- UUID constants live only in `ble_constants.dart`. Never written elsewhere.
- Command bytes live only in `assets/commands.yaml`. Never hardcoded in Dart.
- All BLE writes go through `BleFrameBuilder` → `CommandLoader`. Never call `writeFrame` with raw literals.
- ObjectBox only for fan data (no Hive, no Isar, no SharedPreferences).
- Android only. No iOS build.
- Single active BLE connection — one fan at a time.
- No voice control (hardware feature — VC10 chip; not this app's concern).
- No backend. No HTTP calls in Phase 1.

---

## Testing notes

- **Unit tests** use `_FakeRepo` — an in-memory `FanRepository` implementation — to avoid the ObjectBox native library in unit tests.
- **Widget tests** mock `BleService` and `FanRepository` with mocktail. `CommandLoader.load()` must be called in `setUpAll`.
- `StreamProvider` in widget tests needs **4 pump cycles** to deliver a connection state change: `pump()` ×2 (postFrameCallback + microtask drain), add event to stream, `pump()` ×2 (stream delivery + widget rebuild).
- `CircularSpeedDial` stacks 6 `GestureDetector`s at the same centre — `tester.tap()` is intercepted by the overlaid `Column`. Invoke `dial.onSpeedSelected(n)` directly in tests.
- `LightingControlWidget` and the BOOST button sit below the 600 px test viewport — obtain the widget with `tester.widget<...>(find.byType(...))` and call its callback directly.
