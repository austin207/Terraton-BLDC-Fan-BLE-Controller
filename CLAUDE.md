# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

# Build (both onboarding variants, uploads to GitHub Releases)
# Run from repo root:
.\build.ps1

# Regenerate ObjectBox & Riverpod generated code (run after editing models or providers)
dart run build_runner build --delete-conflicting-outputs
```

## Architecture

### Data flow

```
assets/commands.yaml
        │
        ▼
  CommandLoader (singleton, loaded in main.dart before runApp)
        │
        ▼
  BleFrameBuilder (typed facade — never hardcode bytes outside here)
        │
        ▼
  BleService (abstract) / BleServiceImpl (flutter_blue_plus)
        │  writeFrame() ──► fan hardware
        │  notifyStream ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox) — persists FanDevice + FanState
```

### BLE protocol

Frames are `[0x55, 0xAA, 0x06, <cmd>, <len>, ...data, <checksum>]`. Checksum is the low byte of the sum of bytes 2–end-of-data. Response frames use packet ID `0x07` instead of `0x06`. Status poll uses a fixed non-standard 7-byte frame. All command bytes and data values live exclusively in `assets/commands.yaml` — never hardcode them in Dart. `CommandLoader.buildFrame()` handles framing and checksum.

### State management (Riverpod)

- `bleServiceProvider` — singleton `BleServiceImpl`; one BLE connection at a time.
- `bleConnectionStateProvider` — `StreamProvider` wrapping `BleService.connectionStateStream`.
- `fanRepositoryProvider` — singleton `FanRepositoryImpl` (ObjectBox).
- `savedFansProvider` — derives from `fanRepositoryProvider`; invalidate with `ref.invalidate(savedFansProvider)` after writes.
- `activeFanProvider` — `StateNotifierProvider<FanDevice?>` set when user opens a fan.
- `activeFanStateProvider` — `StateNotifierProvider<FanState>` mirrors ObjectBox and live BLE notifications; mutated only through its named `update*` methods.

**Riverpod 2.x constraint**: `ref.read()` is forbidden inside `dispose()` because the provider is already marked disposed before `dispose()` is called. Cache any needed services in `initState()` as fields (see `control_screen.dart:37`).

### Onboarding flow

`goToOnboarding(context)` in `router.dart` shows a bottom sheet with two options:
- **Search via Bluetooth** → `/scan/ble` (`BleScanScreen`) — scans BLE, user picks device from list.
- **Scan QR Code** → `/scan/qr` (`QrScanScreen`) — reads MAC from QR code.

Both screens navigate to `/name-fan` (passing a `FanDevice` as `extra`), which saves the device and goes to `/control`.

### Storage

ObjectBox stores `FanDevice` (identity/metadata) and `FanState` (last-known control state). `FanDevice.deviceId` is the stable primary key (assigned at onboarding); `macAddress` may be empty until first BLE connection and is filled in by `FanRepository.updateMac()`.

`objectbox.g.dart` is generated — do not edit it manually. Run `build_runner` after changing `FanDevice` or `FanState`.

### Commands YAML (`assets/commands.yaml`)

Adding a new command requires only a YAML edit — no Dart changes. Set `command: null` / `data: null` for unimplemented commands; `CommandLoader` and `BleFrameBuilder` return `null` gracefully, and `ControlScreen._send()` shows a pending snackbar instead of crashing. Lighting commands are currently `null` pending values from Terraton.

## Testing notes

- **Unit tests** use `_FakeRepo` (in-memory `FanRepository` implementation) to avoid the ObjectBox native library dependency. Do not use `ObjectBox` or its generated code in unit tests.
- **Widget tests** mock `BleService` and `FanRepository` with mocktail. `CommandLoader.load()` must be called in `setUpAll`.
- `StreamProvider` in widget tests needs **4 pump cycles** to deliver a connection state change: `pump()` × 2 (postFrameCallback + microtask drain), add state to stream, `pump()` × 2 (stream delivery + widget rebuild).
- `CircularSpeedDial` stacks 6 `GestureDetector`s at the same centre — `tester.tap()` hits the overlaid `Column`. Test speed changes by calling `dial.onSpeedSelected(n)` directly on the widget.
