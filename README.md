# Terraton BLDC Fan BLE Controller

Android app that controls a Terraton BLDC ceiling fan over Bluetooth Low Energy 5.2 via an Amp'ed RF BLE60 module.

```text
Flutter App  ──BLE 5.2──►  Amp'ed RF BLE60  ──UART──►  Fan MCU  ──►  BLDC Motor
```

---

## Features

| Category | Details |
| --- | --- |
| **Onboarding** | BLE scan or full-screen immersive QR code scanner (dark overlay, corner brackets, animated scan line); profile setup on first launch |
| **Fan control** | Power, 6 speed steps, Boost / Nature / Reverse / Smart modes, 2 / 4 / 8 h sleep timer |
| **Nature mode** | Locks speed dial and disables other modes while active; restores pre-nature speed on switch to Smart/Reverse |
| **Mood Lighting** | ON/OFF toggle + warm↔cool colour temperature slider *(bytes pending from Terraton)* |
| **Telemetry** | Live watts and RPM polled every 3 s over BLE; stale values auto-clear after 5 s |
| **Analytics** | Energy consumption (kWh), estimated cost, avg wattage, efficiency vs. traditional fan; Day / Week / Month views with per-fan breakdown |
| **Background tracking** | Usage segments flushed on app pause/close via `WidgetsBindingObserver`; Android foreground service keeps the process alive when swiped from recents |
| **Data upload** | Anonymised daily usage summaries (gear distribution, mode distribution, hourly usage, kWh, weather, KSEB tariff slab) uploaded to Cloudflare R2 for AI training (opt-in; API key injected at build time only) |
| **Multi-fan** | Manage multiple fans; live connection status badge with spinning icon; rename, remove, and long-press actions |
| **Storage** | Fan metadata + last-known state persisted with ObjectBox; usage logs for analytics |
| **Backup** | Export / import fan list as JSON |
| **OTA updates** | Automatic on-launch check + manual "Check for Updates" in Settings; downloads arm64 APK from GitHub Releases with live progress bar; hands off to Android system installer |
| **Service QR** | Generate a time-limited QR code (3-hour countdown) for a Terraton technician to scan with their own copy of the app; regenerate button resets the clock |
| **Permissions** | Guided BT permission screen with retry, settings deep-link, and demo-mode fallback |
| **Demo mode** | Full UI walkthrough without a physical fan; triggered from the permission fallback |
| **User Manual** | In-app manual — 8 expandable sections |
| **Legal** | Privacy Policy and Terms of Service screens accessible from Settings |

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
        │
        ▼
  UsageSummaryBuilder       ← aggregates daily logs into a feature vector
        │
        ▼
  DataUploadService         ← async upload to Cloudflare Worker (opt-in, key injected at build time)
```

### Startup sequence (`main.dart`)

1. `FlutterError.onError` + `platformDispatcher.onError` — global error handlers; `ErrorWidget.builder` overridden for dark-theme error screen
2. `CommandLoader.load()` — loads `assets/commands.yaml` into static singleton
3. `initObjectBox()` — opens ObjectBox store
4. `_ensureBluetoothOn()` — shows system BT enable dialog if adapter is off (permission errors silently swallowed; BlePermissionScreen handles retry)
5. `runApp(ProviderScope(TerratorApp()))` — `TerratorApp` (`app.dart`) re-prompts the BT enable dialog whenever the adapter is turned off mid-session; permission check runs inside `SplashScreen` after 2 s delay

### State management

- **Riverpod 2.x** — `NotifierProvider.autoDispose.family` for per-fan live control state; `FutureProvider` for the saved fan list; `AsyncNotifierProvider` for the user name
- **Navigation** — GoRouter with typed constants in `AppRoutes`; `nameFan` and `control` routes guard against null `extra` via `redirect:` (never a fallback widget)
- **Storage** — ObjectBox: `FanDevice` (identity/metadata) + `FanState` (last-known control state) + `UsageLog` (energy telemetry segments) + `UsageSummary` (daily feature vector for upload)

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
│   ├── app.dart                   # TerratorApp root widget; re-prompts BT enable on mid-session turn-off
│   ├── main.dart                  # Entry point: error handlers, CommandLoader, ObjectBox, runApp
│   ├── core/
│   │   ├── background/
│   │   │   └── ble_foreground_service.dart  # MethodChannel wrapper for Android foreground service
│   │   ├── ble/
│   │   │   ├── ble_constants.dart           # All UUID constants (only location)
│   │   │   ├── ble_connection_state.dart    # Enum: disconnected/scanning/connecting/connected
│   │   │   ├── ble_frame_builder.dart       # Typed facade — returns null for pending commands
│   │   │   ├── ble_response_parser.dart     # Validates response frames; byte → name mapping
│   │   │   └── ble_service.dart             # BleServiceImpl: scan/connect/disconnect/write
│   │   ├── commands/
│   │   │   └── command_loader.dart          # YAML singleton; buildFrame(); statusPoll(); custom()
│   │   ├── providers.dart                   # All Riverpod providers; ActiveFanStateNotifier
│   │   ├── storage/
│   │   │   ├── app_settings.dart            # JSON file: user name, first-launch flag, opt-in prefs
│   │   │   ├── fan_repository.dart          # ObjectBox CRUD + JSON export/import
│   │   │   ├── objectbox_store.dart         # Singleton Store init
│   │   │   └── usage_log_repository.dart    # Usage log read/write for analytics
│   │   ├── update/
│   │   │   └── app_update_service.dart      # OTA check, APK download with progress, system installer handoff
│   │   └── upload/
│   │       ├── data_upload_service.dart     # Cloudflare Worker upload (opt-in; key injected at build time)
│   │       └── usage_summary_builder.dart   # Aggregates daily UsageLogs into a UsageSummary feature vector
│   ├── features/
│   │   ├── analytics/
│   │   │   └── analytics_screen.dart        # kWh / cost / efficiency / per-fan breakdown
│   │   ├── control/
│   │   │   ├── circular_speed_dial.dart     # Radial dot-ring speed selector + centre readout
│   │   │   ├── connection_banner.dart       # ConnectionLostCard overlay (bottom-anchored)
│   │   │   ├── control_screen.dart          # Main fan control; telemetry timer; BLE notify dispatch
│   │   │   ├── lighting_control_widget.dart
│   │   │   ├── mode_control_widget.dart     # Nature / Smart / Reverse / Boost buttons
│   │   │   └── timer_control_widget.dart    # OFF / 2H / 4H / 8H selector
│   │   ├── home/
│   │   │   ├── fans_list_screen.dart        # Dark-theme fan list; live status badge; spinning icon; long-press actions
│   │   │   └── home_screen.dart             # Bottom-nav shell (Analytics / Home / Settings tabs)
│   │   ├── legal/
│   │   │   ├── legal_screen.dart            # Reusable scrollable legal screen (shared by PP and ToS)
│   │   │   ├── privacy_policy_screen.dart   # Privacy Policy content
│   │   │   └── terms_screen.dart            # Terms of Service content
│   │   ├── onboarding/
│   │   │   ├── ble_scan_screen.dart         # BLE scan list; 15 s timeout; stopScan on dispose
│   │   │   ├── name_fan_screen.dart         # Nickname entry after scan/QR
│   │   │   ├── profile_setup_screen.dart    # "What should we call you?" — shown on first launch
│   │   │   └── qr_scan_screen.dart          # Full-screen immersive QR scanner with overlay cutout
│   │   ├── permission/
│   │   │   └── ble_permission_screen.dart   # Permission request; settings deep-link; demo fallback
│   │   ├── settings/
│   │   │   ├── service_qr_modal.dart        # Time-limited service QR (3h countdown + regenerate)
│   │   │   ├── settings_screen.dart         # Profile edit; data export/import; OTA check; service QR; legal links
│   │   │   └── user_manual_screen.dart      # 8-section expandable manual
│   │   ├── splash/
│   │   │   └── splash_screen.dart           # 2 s hold; checks permissions; routes to profile/home
│   │   └── update/
│   │       └── update_dialog.dart           # OTA bottom sheet: idle → downloading (progress bar) → installing → error
│   ├── models/
│   │   ├── fan_device.dart                  # ObjectBox entity: identity + metadata
│   │   ├── fan_state.dart                   # ObjectBox entity: last-known control state + copyWith
│   │   ├── usage_log.dart                   # ObjectBox entity: per-session energy segment
│   │   └── usage_summary.dart              # Daily feature vector for AI upload (gear dist, mode dist, weather, KSEB slab)
│   └── shared/
│       ├── app_routes.dart                  # Route path constants + kDemoDeviceId
│       ├── brand_mark.dart                  # Terraton wordmark/icon with pixel-precise PNG crop
│       ├── fan_icon.dart                    # Static fan vector icon (light-theme)
│       ├── router.dart                      # GoRouter config + goToOnboarding() bottom sheet
│       ├── terraton_fan_icon.dart           # Animated spinning fan icon (dark-theme)
│       └── theme.dart                       # kBg / kCard / kYellow / kText / kSpeedColors / etc.
├── android/
│   └── app/src/main/kotlin/com/terraton/terraton_fan_app/
│       ├── MainActivity.kt                  # MethodChannel handler for bg_service start/update/stop
│       └── TerraBgService.kt               # Android foreground service; persistent "Fan running" notification
├── test/
│   ├── flutter_test_config.dart             # Global test setup (CommandLoader preload)
│   ├── generate_icon_test.dart
│   ├── unit/
│   │   ├── active_fan_state_notifier_test.dart
│   │   ├── app_settings_test.dart
│   │   ├── ble_frame_builder_test.dart
│   │   ├── ble_response_parser_test.dart
│   │   ├── command_loader_test.dart
│   │   ├── fan_device_test.dart
│   │   ├── fan_repository_test.dart
│   │   ├── fan_state_test.dart
│   │   ├── usage_log_repository_test.dart
│   │   └── usage_log_test.dart
│   └── widget/
│       ├── analytics_screen_test.dart
│       ├── ble_permission_screen_test.dart
│       ├── ble_scan_screen_test.dart
│       ├── connection_banner_test.dart
│       ├── control_screen_test.dart
│       ├── fans_list_screen_test.dart
│       ├── home_screen_test.dart
│       ├── mode_control_widget_test.dart
│       ├── name_fan_screen_test.dart
│       ├── profile_setup_screen_test.dart
│       ├── qr_scan_screen_test.dart
│       ├── settings_screen_test.dart
│       ├── timer_control_widget_test.dart
│       └── user_manual_screen_test.dart
└── objectbox.g.dart                         # Generated — do not edit; run build_runner to regenerate
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

There are two branches to build from depending on which architecture you want to ship.

#### Stable build (`main`)

The production-ready version with all fan types hardcoded in Dart:

```powershell
git checkout main
git pull
.\build.ps1
```

#### Config-driven build (`feature/config-driven-appliances`)

The experimental version where adding a new appliance category only requires editing `assets/appliances.yaml`:

```powershell
git checkout feature/config-driven-appliances
git pull
.\build.ps1
```

Always `git pull` before building so you compile the latest committed code, not a stale local snapshot.

Once the config-driven branch is approved for production, merge it to `main` and all future builds will use it:

```powershell
git checkout main
git merge feature/config-driven-appliances
git push
.\build.ps1
```

The APK is saved to `builds/` and published to GitHub Releases automatically. The build script prompts for a **P**atch / **N**ew feature / **J**umbo (major) version bump and increments `pubspec.yaml` accordingly.

> **API key:** The Cloudflare upload key is read from a gitignored `secrets.env` at build time via `--dart-define=UPLOAD_API_KEY=<secret>`. Debug builds skip the upload silently.

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
| API key | `UPLOAD_API_KEY` must never appear in committed source — injected via `--dart-define` at build time from a gitignored `secrets.env` |

---

## Test Coverage

### Unit tests

| File | What it covers |
| --- | --- |
| `test/unit/command_loader_test.dart` | YAML config parsing; `buildFrame()` checksum correctness; `statusPoll()` fixed frame; null handling for pending commands |
| `test/unit/ble_frame_builder_test.dart` | All `BleFrameBuilder` facades map to correct command bytes |
| `test/unit/ble_response_parser_test.dart` | Response frame validation (header, packet ID, checksum); `parsePowerState`, `parseSpeed`, `parseModeString`, `parseTimer`, `parseRpm`, `parsePowerWatts` |
| `test/unit/active_fan_state_notifier_test.dart` | State transitions: power, speed, mode, boost, timer; Nature mode blocks boost; `setActiveMode` / `setBoostActive` invariants |
| `test/unit/fan_repository_test.dart` | ObjectBox save / load / delete / rename; `importFromJson` validation (version check, field length limits, duplicate skip) |
| `test/unit/fan_device_test.dart` | FanDevice default field values |
| `test/unit/fan_state_test.dart` | FanState.copyWith round-trip; equality and hashCode |
| `test/unit/app_settings_test.dart` | AppSettings JSON file I/O; user name and first-launch flag persistence |
| `test/unit/usage_log_test.dart` | UsageLog kWh calculation |
| `test/unit/usage_log_repository_test.dart` | In-memory repo: add / get / date-range query / delete |

### Widget tests

| File | What it covers |
| --- | --- |
| `test/widget/control_screen_test.dart` | BLE connection lifecycle; demo mode; speed dial callbacks; mode/boost button state; telemetry frame dispatch |
| `test/widget/ble_permission_screen_test.dart` | Permission request flow; "Open App Settings" branch; demo-mode fallback |
| `test/widget/home_screen_test.dart` | IndexedStack bottom-nav shell; tab switching |
| `test/widget/fans_list_screen_test.dart` | Fan list render; live connection status badge; long-press rename/delete actions |
| `test/widget/analytics_screen_test.dart` | Day/Week/Month view switching; kWh and cost display with mock usage logs |
| `test/widget/ble_scan_screen_test.dart` | Scan list render; already-paired badge; timeout behaviour |
| `test/widget/qr_scan_screen_test.dart` | Full-screen QR scanner overlay render; torch toggle |
| `test/widget/name_fan_screen_test.dart` | Nickname validation; submit routing |
| `test/widget/profile_setup_screen_test.dart` | First-launch name input and routing |
| `test/widget/settings_screen_test.dart` | Profile edit; export/import; OTA check trigger; service QR open |
| `test/widget/user_manual_screen_test.dart` | Section expand/collapse |
| `test/widget/mode_control_widget_test.dart` | Nature/Smart/Reverse/Boost button enabled/active states |
| `test/widget/timer_control_widget_test.dart` | OFF/2H/4H/8H selector state and callback |
| `test/widget/connection_banner_test.dart` | ConnectionLostCard render and retry callback |

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
| `permission_handler` | ^11.3.1 | Runtime BT + camera permissions |
| `package_info_plus` | ^8.3.0 | App version in Settings and OTA check |
| `path_provider` | ^2.1.5 | Temp dir for APK download and export file |
| `path` | ^1.9.1 | File path manipulation |
| `google_fonts` | ^6.2.1 | Manrope + JetBrains Mono |
| `qr_flutter` | ^4.1.0 | Service-access QR code generation |
| `http` | ^1.2.2 | Cloudflare upload + OTA version check + APK download |
| `crypto` | ^3.0.3 | SHA-256 payload hash for upload deduplication; device ID anonymisation |
| `connectivity_plus` | ^6.0.3 | Network availability check before upload |
| `open_file` | ^3.3.2 | Opens downloaded APK in Android system installer |
| `cupertino_icons` | ^1.0.8 | iOS-style icons (used sparingly) |

---

## Roadmap

| Phase | Feature | Status |
| --- | --- | --- |
| 1 | BLE connectivity | ✅ Complete |
| 1 | Full fan control — power, speed, modes, timers | ✅ Complete |
| 1 | Live telemetry — watts and RPM | ✅ Complete |
| 1 | Multi-fan management and persistence | ✅ Complete |
| 1 | QR code and BLE scan onboarding | ✅ Complete |
| 1 | Full-screen immersive QR scanner | ✅ Complete |
| 1 | Live connection status + spinning icon in fan list | ✅ Complete |
| 1 | Permissions screen, splash, demo mode | ✅ Complete |
| 1 | Profile setup + user name personalisation | ✅ Complete |
| 1 | Analytics — energy, cost, efficiency | ✅ Complete |
| 1 | In-app User Manual | ✅ Complete |
| 1 | Background usage tracking + Android foreground service | ✅ Complete |
| 1 | Service QR for technician access | ✅ Complete |
| 1 | Privacy Policy + Terms of Service | ✅ Complete |
| 2 | OTA self-update from GitHub Releases | ✅ Complete |
| 2 | Lighting control | ⏳ UI complete — awaiting command bytes from Terraton |
| 2 | AI training data upload (Cloudflare Worker + R2) | ✅ Complete |
| 2 | Remote command updates (fetch `commands.yaml` from URL) | 📋 Planned |

---

## Author

Antony Austin — College Project, May 2026
