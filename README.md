# Terraton BLDC Fan BLE Controller

Android app that controls a Terraton BLDC ceiling fan over Bluetooth Low Energy 5.2 via an Amp'ed RF BLE60 module. Fully offline — no backend, no cloud, no internet required.

```text
Flutter App  ──BLE 5.2──►  Amp'ed RF BLE60  ──UART──►  Fan MCU  ──►  BLDC Motor
```

---

## Features

| Category | Details |
| --- | --- |
| **Onboarding** | BLE scan or QR code pairing; profile setup on first launch |
| **Fan control** | Power, 6 speed steps, Boost / Nature / Reverse / Smart modes, 2 / 4 / 8 h sleep timer |
| **Nature mode** | Locks speed dial and disables other modes while active; restores pre-nature speed on switch to Smart/Reverse |
| **Mood Lighting** | ON/OFF toggle + warm↔cool colour temperature slider *(bytes pending from Terraton)* |
| **Telemetry** | Live watts and RPM polled every 3 s over BLE; stale values auto-clear after 5 s |
| **Analytics** | Energy consumption (kWh), estimated cost, avg wattage, efficiency vs. traditional fan; Day / Week / Month views with per-fan breakdown |
| **Multi-fan** | Manage multiple fans; grouped list with rename, remove, and long-press actions |
| **Storage** | Fan metadata + last-known state persisted with ObjectBox; usage logs for analytics |
| **Backup** | Export / import fan list as JSON |
| **Permissions** | Guided BT permission screen with retry, settings deep-link, demo-mode fallback |
| **Demo mode** | Full UI walkthrough without a physical fan; triggered from the permission fallback |
| **User Manual** | In-app manual — 8 expandable sections |

---

## Architecture

### Data flow

```text
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once at startup; static singleton
        │
        ▼
  BleFrameBuilder          ← typed facade; all frame construction lives here
        │                    returns null for pending/unknown commands
        ▼
  BleService / BleServiceImpl   (flutter_blue_plus)
        │  connect(mac) ────► GATT connect → service discovery → char setup
        │  writeFrame()  ──► fan hardware  (+0D 0A BLE60 flush terminator)
        │  notifyStream  ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox) ← persists FanDevice + FanState
  UsageLogRepository        ← persists per-session usage segments
```

### Startup sequence (`main.dart`)

1. `FlutterError.onError` + `platformDispatcher.onError` — global error handlers wired; `ErrorWidget.builder` overridden for dark-theme error screen
2. `CommandLoader.load()` — loads `assets/commands.yaml` into static singleton
3. `initObjectBox()` — opens ObjectBox store
4. `_ensureBluetoothOn()` — shows system BT enable dialog if adapter is off (permission errors silently swallowed; BlePermissionScreen handles retry)
5. `runApp(ProviderScope(TerratorApp()))` — permission check runs inside `SplashScreen` after 2 s delay

### State management

- **Riverpod 2.x** — `NotifierProvider.autoDispose.family` for per-fan live control state; `FutureProvider` for the saved fan list; `AsyncNotifierProvider` for the user name
- **Navigation** — GoRouter with typed constants in `AppRoutes`; `nameFan` and `control` routes guard against null `extra` via `redirect:` (never a fallback widget)
- **Storage** — ObjectBox: `FanDevice` (identity/metadata) + `FanState` (last-known control state) + `UsageLog` (energy telemetry segments)

### Nature mode state machine

```text
Idle ──────────────── tap Nature ──────────► Nature active
                      saves _preNatureSpeed    speed dial locked
                                               all modes inactive

Nature active ─── tap Smart/Reverse ──────► mode active
                   mode frame FIRST           speed restored (min 3 for Smart)
                   then speed frame

Nature active ─── tap Boost ──────────────► Boost active
                                             speed NOT restored
                                             Nature cleared silently
```

The BLE mode frame is always sent before the speed frame when exiting Nature — hardware ignores speed commands while Nature is active.

---

## BLE Protocol

### Connection

| Field | Value |
| --- | --- |
| Scan filter (advertisement) | `00001827-0000-1000-8000-00805f9b34fb` — BLE Mesh Proxy |
| Write characteristic | `00002adb-0000-1000-8000-00805f9b34fb` — Mesh Proxy Data In |
| Notify characteristic | `00002adc-0000-1000-8000-00805f9b34fb` — Mesh Proxy Data Out |

Service discovery also searches the Amp'ed RF proprietary service, CC254X / HM-10, Nordic UART Service, and Microchip RN4870 as fallbacks, in that priority order. First match wins.

### Frame format

```text
[ 0x55  0xAA  packetId  command  dataLen  ...data  checksum ]
```

- **Request:** `packetId = 0x06`
- **Response:** `packetId = 0x07`
- **Checksum:** sum of **every byte before the checksum**, including the `0x55 0xAA` header:

```text
checksum = (0x55 + 0xAA + packetId + command + dataLen + Σ data) & 0xFF
```

### BLE60 bridge behaviour

The Amp'ed RF BLE60 is a BLE-to-UART transparent bridge. It buffers all incoming BLE writes and only flushes to the MCU UART when it receives `\r\n` (0x0D 0x0A). The app appends `0x0D 0x0A` to every frame automatically inside `BleServiceImpl.writeFrame()`.

On every new BLE connection the BLE60 also sends its own initialisation bytes over UART **before** any app data:

```text
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
| --- | --- |
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

```text
terraton_fan_app/
├── assets/
│   ├── commands.yaml              # Single source of truth for all BLE command bytes
│   ├── icon/                      # Launcher icon
│   ├── icons/                     # PNG mode icons (nature_plant, boost_rocket)
│   └── logos/                     # terraton-full.png, terraton-mark.png
├── lib/
│   ├── core/
│   │   ├── ble/
│   │   │   ├── ble_constants.dart         # All UUID constants (only location)
│   │   │   ├── ble_connection_state.dart  # Enum: disconnected/scanning/connecting/connected
│   │   │   ├── ble_frame_builder.dart     # Typed facade — returns null for pending commands
│   │   │   ├── ble_response_parser.dart   # Validates response frames; byte → name mapping
│   │   │   └── ble_service.dart           # BleServiceImpl: scan/connect/disconnect/write
│   │   ├── commands/
│   │   │   └── command_loader.dart        # YAML singleton; buildFrame(); statusPoll(); custom()
│   │   ├── providers.dart                 # All Riverpod providers; ActiveFanStateNotifier
│   │   └── storage/
│   │       ├── app_settings.dart          # JSON file: user name, first-launch flag
│   │       ├── fan_repository.dart        # ObjectBox CRUD + JSON export/import
│   │       ├── objectbox_store.dart       # Singleton Store init
│   │       └── usage_log_repository.dart  # Usage log read/write for analytics
│   ├── features/
│   │   ├── analytics/
│   │   │   └── analytics_screen.dart      # kWh / cost / efficiency / per-fan breakdown
│   │   ├── control/
│   │   │   ├── circular_speed_dial.dart   # Radial dot-ring speed selector + centre readout
│   │   │   ├── connection_banner.dart     # ConnectionLostCard overlay (bottom-anchored)
│   │   │   ├── control_screen.dart        # Main fan control; telemetry timer; BLE notify dispatch
│   │   │   ├── lighting_control_widget.dart
│   │   │   ├── mode_control_widget.dart   # Nature / Smart / Reverse / Boost buttons
│   │   │   └── timer_control_widget.dart  # OFF / 2H / 4H / 8H selector
│   │   ├── home/
│   │   │   ├── fan_card.dart              # Fan card (legacy light-theme; used in FansListScreen)
│   │   │   ├── fans_list_screen.dart      # Dark-theme fan list with long-press actions
│   │   │   └── home_screen.dart           # Bottom-nav shell (Analytics / Home / Settings tabs)
│   │   ├── onboarding/
│   │   │   ├── ble_scan_screen.dart       # BLE scan list; 15 s timeout; stopScan on dispose
│   │   │   ├── name_fan_screen.dart       # Nickname entry after scan/QR
│   │   │   ├── profile_setup_screen.dart  # "What should we call you?" — shown on first launch
│   │   │   └── qr_scan_screen.dart        # Reads device_id / model / fw_version from QR JSON
│   │   ├── permission/
│   │   │   └── ble_permission_screen.dart # Permission request; settings deep-link; demo fallback
│   │   ├── settings/
│   │   │   ├── settings_screen.dart       # Profile edit; data export/import; about; service QR
│   │   │   └── user_manual_screen.dart    # 8-section expandable manual
│   │   └── splash/
│   │       └── splash_screen.dart         # 2 s hold; checks permissions; routes to profile/home
│   ├── models/
│   │   ├── fan_device.dart                # ObjectBox entity: identity + metadata
│   │   ├── fan_state.dart                 # ObjectBox entity: last-known control state + copyWith
│   │   └── usage_log.dart                 # ObjectBox entity: per-session energy segment
│   └── shared/
│       ├── app_routes.dart                # Route path constants
│       ├── brand_mark.dart                # Terraton wordmark/icon with pixel-precise PNG crop
│       ├── fan_icon.dart                  # Static fan vector icon (light-theme)
│       ├── router.dart                    # GoRouter config + goToOnboarding() bottom sheet
│       ├── terraton_fan_icon.dart         # Animated spinning fan icon (dark-theme)
│       └── theme.dart                     # kBg / kCard / kYellow / kText / kSpeedColors / etc.
├── test/
│   ├── unit/
│   │   ├── active_fan_state_notifier_test.dart
│   │   ├── ble_frame_builder_test.dart
│   │   ├── ble_response_parser_test.dart
│   │   ├── command_loader_test.dart
│   │   └── fan_repository_test.dart
│   └── widget/
│       ├── ble_permission_screen_test.dart
│       └── control_screen_test.dart
└── objectbox.g.dart                       # Generated — do not edit; run build_runner to regenerate
```

---

## Getting Started

### Requirements

- Flutter 3.29+ with Dart 3.8+
- Android device (API 21+) or emulator with BLE support
- Android SDK

### Emulator

Two AVDs are configured: **S24 Ultra** and **Medium Phone API 36.0**.

```powershell
# From repo root — launch S24 Ultra emulator
.\launch-emulator.ps1

# Launch and immediately run the app once boot finishes
.\launch-emulator.ps1 -Run

# Emulator already running — just start the app
.\launch-emulator.ps1 -RunOnly
```

> **Emulator already on but no app?**
>
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
flutter test test/widget/control_screen_test.dart

# Regenerate ObjectBox & Riverpod code (run after editing models or providers)
dart run build_runner build --delete-conflicting-outputs
```

### Adding a new BLE command

1. Add the entry to `assets/commands.yaml` under the appropriate section (set `command: null` if bytes are not yet known).
2. Add a named method to `BleFrameBuilder` calling `CommandLoader.custom([...], data)`.
3. Wire it to the UI in `ControlScreen._send()`.
4. If the fan sends a response, add a `parse*` helper to `BleResponseParser` and dispatch it in `ControlScreen._subscribeNotify()`.

No other files need changing — the YAML is the single source of truth for all byte values.

### Design tokens

All colours, typography, and spacing live in `lib/shared/theme.dart`. Use the named constants (`kYellow`, `kBg`, `kCard`, `kText`, `kTextMut`, `kSpeedColors`, etc.) — do not hardcode hex values in widget files.

---

## Hard Constraints

| Constraint | Rule |
| --- | --- |
| UUID constants | Live **only** in `ble_constants.dart` — never duplicated |
| Command bytes | Live **only** in `assets/commands.yaml` — never hardcoded in Dart |
| BLE writes | Always go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()` |
| Storage | ObjectBox only — no Hive, Isar, or SharedPreferences for fan data |
| Platform | Android only — no iOS build target |
| Connections | One fan at a time — single active BLE connection |
| Network | No backend, no HTTP — Phase 1 is fully offline |

---

## Known Issues & Open Items

These are verified findings from a full codebase audit. All previously identified issues from the `ui-revamp` review cycle have been resolved.

### Open (not yet fixed)

| Severity | File | Description |
| --- | --- | --- |
| MEDIUM | `fan_card.dart` | Light-theme hardcoded colours (`Colors.white` bottom sheet background, `Color(0xFF1E293B)` text) clash with the app's dark theme. The card was ported from an earlier light-theme design and not yet migrated to dark-theme constants. |
| MEDIUM | `fans_list_screen.dart:275` | Fan status badge hardcoded to "Disconnected". It does not reflect live BLE connection state — the `bleConnectionStateProvider` is not wired into the list screen. |
| MEDIUM | `fans_list_screen.dart:180`, `fan_card.dart:167` | `.then((name) async { await repo.rename... })` pattern: the async work inside `.then()` is fire-and-forget. Rename/delete failures are silently dropped in production (debug mode catches them via the ObjectBox `assert(false)` in `ActiveFanStateNotifier.update`). |
| LOW | `splash_screen.dart:131` | Version string `v1.0.0 · SMART BLDC` is hardcoded. Should be read from `package_info_plus` (`packageInfoProvider`) to stay in sync with `pubspec.yaml`. |

### Fixed in `ui-revamp` (2026-05-23)

| Fix | Commit |
| --- | --- |
| Nature mode: locks speed dial, saves/restores pre-nature speed, correct BLE frame order | `fadcaeb` |
| `BrandMark`: pixel-precise PNG crop using measured content bounds (537×464 canvas, content x=123–421, y=203–272) | `fadcaeb` |
| Settings rename modal: all `InputBorder` variants suppressed; clear button is plain `Icon`, not a styled container | `fadcaeb` |
| Profile screen logo padding 20→28 px to match content grid | `fadcaeb` |
| `_onMode`/`_onBoost` extracted to named methods; `_FanControlsPanelState.build()` under 100 lines | `9b87be6` |
| Double `context.mounted` guard in `_import` removed | `9b87be6` |
| `_DialPainter.shouldRepaint`: `disabledSpeeds.length` replaced with `setEquals()` | `d6beb6a` |
| `UserNameNotifier.build()` exception scope narrowed from `Object` to `Exception` | `d6beb6a` |
| Service QR: one-shot expiry `Timer` stored and cancelled in `dispose()`; QR data cached as field (not rebuilt every second tick) | `1df872b` |
| `_LineChartPainter.shouldRepaint`: identity comparison replaced with `listEquals()` | `3806dc6` |
| `kDemoDeviceId` extracted to `app_routes.dart`; magic string `'__demo__'` removed from all call-sites | `3806dc6` |
| `_connect()`: QR-only device with no MAC now shows "Bluetooth Not Linked" dialog with "Scan for Fan" action | `40e5f0b` |

---

## Test Coverage

| File | What it covers |
| --- | --- |
| `test/unit/command_loader_test.dart` | YAML config parsing; `buildFrame()` checksum correctness; `statusPoll()` fixed frame; null handling for pending commands |
| `test/unit/ble_frame_builder_test.dart` | All `BleFrameBuilder` facades map to correct command bytes |
| `test/unit/ble_response_parser_test.dart` | Response frame validation (header, packet ID, checksum); `parsePowerState`, `parseSpeed`, `parseModeString`, `parseTimer`, `parseRpm`, `parsePowerWatts` |
| `test/unit/active_fan_state_notifier_test.dart` | State transitions: power, speed, mode, boost, timer; Nature mode blocks boost; `setActiveMode` / `setBoostActive` invariants |
| `test/unit/fan_repository_test.dart` | ObjectBox save / load / delete / rename; `importFromJson` validation (version check, field length limits, duplicate skip) |
| `test/widget/ble_permission_screen_test.dart` | Permission request flow; "Open App Settings" branch; demo-mode fallback |
| `test/widget/control_screen_test.dart` | BLE connection lifecycle; demo mode; speed dial callbacks; mode/boost button state; telemetry frame dispatch |

**Not yet covered:** `HomeScreen`, `FansListScreen`, `AnalyticsScreen`, `SplashScreen`, onboarding flow (QR, BLE scan, naming), settings export/import end-to-end.

---

## Dependencies

| Package | Version | Purpose |
| --- | --- | --- |
| `flutter_blue_plus` | ^2.2.1 | BLE scan, connect, GATT write/notify |
| `mobile_scanner` | ^6.0.4 | QR code scanning |
| `objectbox` / `objectbox_flutter_libs` | ^4.0.3 | Local database |
| `flutter_riverpod` | ^2.6.1 | State management |
| `go_router` | ^14.6.1 | Declarative routing |
| `yaml` | ^3.1.3 | `commands.yaml` parsing |
| `share_plus` | ^10.1.2 | JSON export via share sheet |
| `file_picker` | ^8.1.6 | JSON import |
| `permission_handler` | ^11.3.1 | Runtime BT permissions |
| `package_info_plus` | ^8.3.0 | App version in Settings |
| `path_provider` | ^2.1.5 | Temp dir for export file |
| `google_fonts` | ^6.2.1 | Manrope + JetBrains Mono |

---

## Roadmap

| Phase | Feature | Status |
| --- | --- | --- |
| 1 | BLE connectivity | ✅ Complete |
| 1 | Full fan control — power, speed, modes, timers | ✅ Complete |
| 1 | Live telemetry — watts and RPM | ✅ Complete |
| 1 | Multi-fan management and persistence | ✅ Complete |
| 1 | QR code and BLE scan onboarding | ✅ Complete |
| 1 | Permissions screen, splash, demo mode | ✅ Complete |
| 1 | Profile setup + user name personalisation | ✅ Complete |
| 1 | Analytics — energy, cost, efficiency | ✅ Complete |
| 1 | In-app User Manual | ✅ Complete |
| 2 | Lighting control | ⏳ UI complete — awaiting command bytes from Terraton |
| 2 | Live connection status in fan list | 📋 Planned |
| 2 | Remote command updates (fetch `commands.yaml` from URL) | 📋 Planned |
| 2 | Migrate `fan_card.dart` to dark-theme constants | 📋 Planned |

---

## Author

Antony Austin — College Project, May 2026
