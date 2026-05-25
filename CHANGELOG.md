# Changelog

All notable changes to the Terraton BLDC Fan BLE Controller are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Fixed
- **Fan icon spins in list when BLE connected** (`fans_list_screen.dart`) — changed `spinning` condition from `isPowered` (read from `activeFanStateProvider`, which auto-disposes during back-navigation) to `isConnected` (read from `bleConnectionStateProvider`, which is a `StreamProvider` and always holds the last-emitted value). Eliminates the brief zero-watcher window that caused the provider to reset and return `isPowered = false`.

---

## [1.9.0] — 2026-05-25

### Added
- **Full-screen immersive QR scanner** (`qr_scan_screen.dart`) — replaced the small centred viewport with a full-screen camera feed. Dark semi-transparent overlay with a rounded transparent cutout, yellow corner-bracket markers, and an animated scan line with gradient glow. Frosted top controls bar (close + torch toggle) and bottom info panel with drag handle. Fan pairing, service-access token handling, and QR validation logic are unchanged.

### Fixed
- **BLE stays connected on Back** (`control_screen.dart`) — removed the explicit `_ble.disconnect()` from `_ControlScreenState.dispose()`. The fan remains connected when navigating back to the fans list, matching user expectation.
- **Fan status badge shows live BLE connection state** (`fans_list_screen.dart`) — badge is now wired to `bleConnectionStateProvider` + `connectedMacAddress`; shows green "Connected" for the currently connected fan and grey "Disconnected" otherwise.
- **Fan icon spins when connected** (`fans_list_screen.dart`) — `TerratonFanIcon` receives `spinning: isConnected` so the blade animation reflects live BLE connection state in the list.
- **`BleServiceImpl.connect()` same-MAC guard** (`ble_service.dart`) — returns immediately if already connected to the same MAC address, preventing redundant GATT discovery. Adds a clean teardown of any existing connection before connecting to a different device.

---

## [1.8.0] — 2026-05-25

### Added
- **Background usage tracking** (`control_screen.dart`) — `_FanControlsPanelState` mixes in `WidgetsBindingObserver`. On `AppLifecycleState.paused` (home button, screen lock, swipe to recents) it flushes the current usage segment to ObjectBox. On `AppLifecycleState.resumed` it re-seeds a new segment from the live fan state.
- **Android BLE foreground service** (`TerraBgService.kt`, `ble_foreground_service.dart`) — a persistent foreground service (`START_NOT_STICKY`) keeps the app process alive when swiped from recents. Dart communicates via a `MethodChannel("com.terraton/bg_service")` with `start`, `update`, and `stop` methods. The notification shows "Terraton Fan" with a live status label (e.g. "Speed 3 · 28 W").

### Fixed
- **Install Unknown Apps permission** (`settings_screen.dart`) — OTA installer now checks `Permission.requestInstallPackages` and routes to the system "Install Unknown Apps" settings page when not granted, rather than silently failing.

---

## [1.7.0] — 2026-05-24

### Fixed
- **OTA version check: UTF-8 BOM and charset mismatch** (`app_update_service.dart`) — GitHub Releases API returns assets as `application/octet-stream`, which Dart's `http` package decodes as Latin-1. Fixed by decoding `bodyBytes` explicitly as UTF-8 and stripping any leading BOM (`0xEF BB BF`) written by PowerShell 5.1's `Set-Content`.
- **OTA URL: removed redundant cache-busting query parameter** — GitHub release download URLs reject unknown query parameters; the appended timestamp caused spurious non-200 responses on some CDN nodes.
- **Design tokens: 7th pass** (`analytics_screen.dart`, others) — replaced all remaining hardcoded hex colour literals with `theme.dart` tokens, including the KSEB tariff cost strip and any other remaining sites across the codebase.
- **Code-review findings: passes 4 and 5** — additional lint, style, and null-safety fixes identified by `flutter-dart-code-review` across the codebase.

---

## [1.6.0] — 2026-05-24

### Added
- **Manual "Check for Updates" in Settings** (`settings_screen.dart`) — a "Check for Updates" row in the About section triggers the OTA version check on demand. Shows an in-progress indicator and opens the download bottom sheet (`UpdateDialog`) if a newer build is found.

---

## [1.5.0] — 2026-05-24

### Fixed
- **OTA: removed connectivity pre-check** (`app_update_service.dart`) — `connectivity_plus` has a vacuous-truth edge case where an empty network-type list is treated as "connected". Replaced with a direct HTTP attempt and proper error handling.
- **OTA: critical and high code-review findings** — null-safety gaps, unhandled exceptions, and missing `mounted` guards in the OTA update flow.
- **OTA: second-pass code-review findings** — additional lint and style fixes.

---

## [1.4.0] — 2026-05-24

### Fixed
- **OTA: first-pass code-review findings** (`app_update_service.dart`, `splash_screen.dart`) — splash version string now reads from `packageInfoProvider` instead of being hardcoded; permission handler call sites corrected; miscellaneous issues identified in the initial `flutter-dart-code-review` of the OTA update code.

---

## [1.3.0] — 2026-05-24

### Fixed
- **Build: skip version bump when pubspec already clean** (`build.ps1`) — the version bump step now checks `git status --porcelain` on `pubspec.yaml` before committing, preventing empty "chore: bump version" commits on re-runs where the file was not actually modified.

---

## [1.2.0] — 2026-05-24

### Fixed
- **`build.ps1` PowerShell 5.1 encoding issues** — replaced em dash characters (`—`) with ASCII hyphens (`-`) in string literals (PS5.1 parses CP1252, not UTF-8, causing parse errors). Fixed `pubspec.yaml` write to use `UTF8Encoding($false)` so the version string is stored as UTF-8 without a BOM.

---

## [1.1.0] — 2026-05-24

### Added
- **OTA self-update from GitHub Releases** (`app_update_service.dart`, `update_dialog.dart`) — on launch the app fetches `version.json` from the GitHub Releases `latest` tag, compares `build_number`, and presents the `UpdateDialog` bottom sheet if a newer build is available. The dialog streams the arm64 APK download with a live progress bar, then hands off to the Android system installer via `open_file`.
- **Interactive semver bump in `build.ps1`** — the release script now prompts **P**atch / mi**N**or / ma**J**or / **S**kip and increments `pubspec.yaml` automatically before building and publishing to GitHub Releases.

---

## [1.0.0] — 2026-05-23

### Added

#### Core app and BLE
- **Full Flutter app** — complete Terraton BLDC Fan BLE Controller; Android only, API 21+
- **BLE connectivity** (`ble_service.dart`) — `connect(mac)` does GATT connect → service discovery → characteristic setup; `writeFrame()` appends `0x0D 0x0A` for the BLE60 UART flush; `notifyStream` dispatches fan responses
- **Dual onboarding** — BLE scan list (15 s timeout) and full-screen QR scanner both available in one APK via a bottom-sheet picker; no compile-time flags
- **Commands YAML** (`assets/commands.yaml`) — single source of truth for all BLE command bytes; adding a new command requires only a YAML edit
- **Reactive BT enable prompt** (`app.dart`, `main.dart`) — shows the system Bluetooth enable dialog on startup and re-prompts mid-session if the adapter is turned off

#### Fan control
- **Power, speed, modes, timer** — Power ON/OFF; speed steps 1–6 via `CircularSpeedDial` (radial dot-ring with bloom glow); Boost / Nature / Reverse / Smart modes; 2 / 4 / 8 h sleep timer with sliding segmented control
- **Nature mode state machine** — saves `_preNatureSpeed` on entry; mode frame sent BEFORE speed frame on exit (hardware ignores speed while Nature is active); restores speed on Smart/Reverse, skips restore on Boost
- **Mood lighting toggle + colour temperature slider** (`lighting_control_widget.dart`) — UI complete; command bytes pending from Terraton
- **Boost shimmer animation** — fire-gradient background with sharp shimmer stripe; Boost and Reverse/Smart can coexist simultaneously
- **Live telemetry** — watts and RPM polled every 3 s via status-poll frame; stale values cleared by `clearWatts()` / `clearRpm()` after 5 s with no response

#### UI / design
- **Dark theme** — `kBg` (#111) background, `kYellow` (#FFD600) accent, Manrope + JetBrains Mono typefaces
- **Terraton brand assets** — `terraton-full.png` wordmark, `terraton-mark.png`, animated `TerratonFanIcon` widget (spinning when connected), `BrandMark` widget with pixel-precise PNG crop
- **Custom mode icons** — RGBA background-removed PNG for Nature (plant) and Boost (rocket)
- **Portrait lock** — `SystemChrome.setPreferredOrientations([portraitUp])` in `main.dart`

#### Screens and features
- **Analytics screen** — kWh / estimated cost / avg wattage / efficiency vs. 85 W traditional fan; Day / Week / Month views; per-fan breakdown; live KSEB tariff input
- **Live usage logging** — usage segments (gear, watts, mode, duration) flushed by `_flushSegment()` on every mode/speed change and stored in `UsageLogRepository`
- **User Manual** (`user_manual_screen.dart`) — 8 expandable sections: Getting Started, Controlling Fan Speed, Boost Mode, Operating Modes, Sleep Timer, Mood Lighting, Managing Your Fans, Troubleshooting
- **Service access QR** (`service_qr_modal.dart`) — generates a time-locked JSON QR code (3-hour countdown + regenerate button) for Terraton technician access; accessible from Settings
- **BLE permission screen** (`ble_permission_screen.dart`) — requests `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`; per-state guidance (denied / permanently denied / granted); "Open App Settings" deep-link; "Use Demo Mode Instead" fallback
- **Demo mode** — full UI walkthrough without hardware; `kDemoDeviceId = '__demo__'`; `_applyDemoFrame` parses frames locally
- **Profile setup** (`profile_setup_screen.dart`) — "What should we call you?" shown on first launch; user name persisted in `app_settings.json` and displayed on Home and Settings
- **Backup: export / import** (`fan_repository.dart`) — export fan list as JSON via `share_plus`; import via `file_picker` with version check and field-length validation
- **Home screen shell** (`home_screen.dart`) — `IndexedStack` with floating bottom nav; three tabs: Analytics / Home / Settings
- **Fan list screen** (`fans_list_screen.dart`) — long-press rename and remove with confirmation bottom sheet

#### AI training pipeline
- **Cloudflare data upload** (`data_upload_service.dart`) — anonymised daily `UsageSummary` vectors (gear distribution, mode distribution, hourly usage, kWh, avg watts, weather, KSEB tariff slab) uploaded to a Cloudflare Worker (`terraton-ingest`) and stored in R2; gated behind opt-in toggle and build-time API key
- **Weather features** — Open-Meteo daily tempMax, tempMin, humidity fetched for central Kerala coordinates; `-1.0` sentinel when fetch fails
- **KSEB tariff features** — tariff per kWh (user-configurable) and KSEB LT domestic slab (1–8) derived from fan's rolling 30-day kWh estimate
- **ML training pipeline** (`ml/`) — XGBoost + two-tower Keras model targeting TFLite; retraining via `ml/retrain.ps1`
- **CI/CD** — GitHub Actions for R2 data health check and model upload pipeline
- **AI Training section** in User Manual

#### Legal and security
- **Privacy Policy + Terms of Service** (`privacy_policy_screen.dart`, `terms_screen.dart`) — bundled native screens (no WebView); accessible from Settings
- **Cloudflare Worker hardening** (`cloudflare/`) — authentication, rate limiting, and input validation pre-launch security pass

#### Storage and state
- **ObjectBox entities** — `FanDevice` (identity/metadata), `FanState` (last-known control state), `UsageLog` (per-session energy segment)
- **`activeFanStateProvider`** — `AutoDisposeFamilyNotifier` keyed by `deviceId`; `update*` / `set*` named methods; auto-disposes when unwatched
- **`savedFansProvider`** — `FutureProvider`; queries run off the build thread; `ref.invalidate()` after any write
- **`AppRoutes`** — single source of truth for all route path constants
- **`FanState.==` / `hashCode`** — Riverpod suppresses rebuilds on `copyWith` when state is equal

#### Build tooling
- **`build.ps1`** — cleans, runs `build_runner`, builds split-per-ABI APKs (~20 MB each vs. ~80 MB fat APK), writes `version.json`, publishes arm64 + arm7 + x86_64 APKs to GitHub Releases
- **`launch-emulator.ps1`** — launches S24 Ultra or Medium Phone AVD with `-Run` / `-RunOnly` flags

### Changed
- **Sliding segmented controls** — Sleep Timer and Mood Lighting use `AnimatedPositioned` sliding pill; optimistic local state moves the pill instantly on tap
- **Speed dial arc** — single continuous `SweepGradient` replaces per-segment arcs; correct green→yellow→red colour order across speeds 1–6; `setEquals()` in `shouldRepaint`
- **`FanStateCopyWith` extension** — getter-pattern `copyWith` for nullable fields

### Fixed
- **BLE connection path** — iterative fixes over the initial BLE debugging period: `\r\n` flush terminator for BLE60 UART bridge; live scan-result device used for first connection to preserve BLE address type (BLE60 uses a random address); Mesh Proxy UUIDs confirmed as correct; removed `autoConnect`, `mtu`, and `clearGattCache` calls that blocked connection on some Android stacks; `connect(mac)` replaces the `startScan(targetMac)` hack; GATT_ERROR 133 handled with a single retry
- **Checksum formula** (`command_loader.dart`) — `0x55 + 0xAA` header bytes included in the checksum sum (was previously excluded)
- **Nature mode BLE frame order** (`control_screen.dart`) — mode frame sent BEFORE speed frame when exiting Nature; hardware ignores speed commands while Nature is active
- **Service QR leaks** (`service_qr_modal.dart`) — `Timer` stored and cancelled in `dispose()`; QR data cached as a field to prevent rebuild on every tick
- **`BleResponseParser.parseSpeed()` bounds check** — returns `null` for bytes outside 1–6 instead of crashing with `RangeError`
- **Scan subscription leak** (`ble_scan_screen.dart`) — `if (!mounted) return` after `await _sub?.cancel()` prevents a new subscription being created after `dispose()`
- **Per-item DB queries in BLE scan list** — replaced `getFanByMac()` per list item with a `Set<String>` pre-built from `savedFansProvider`; O(1) lookup
- **`_notifyValueSub` leak** (`ble_service.dart`) — subscription cancelled before resubscribing on each reconnect and in `dispose()`
- **`context.mounted` guards** — added after every `await` in connect, timer, and notify callbacks
- **`importFromJson` error handling** — `TypeError` from malformed JSON re-thrown as `FormatException`
- **BLE scan dialog shown for QR-paired devices** — fans paired via QR (no MAC yet) now surface the BLE scan dialog on first control-screen open
- **Profile setup shown on first launch** — correctly routes to `/profile-setup` after BT permission grant on first launch
- **`shouldRepaint` set equality** (`circular_speed_dial.dart`) — uses `setEquals()` from `foundation.dart` for `disabledSpeeds`
- **BrandMark PNG crop** (`brand_mark.dart`) — pixel-measured content bounds (x=123–421, y=203–272 on 537×464 canvas); `ClipRect` wraps `SizedBox` (content width), not `Align`
- **App icon** — removed adaptive icon black ring; renamed `Icon.png` → `icon.png`; removed adaptive background config
- **Multiple code-review passes** (passes 1–9) — lint, null-safety, async `.then()` callbacks replaced with `await`, `AppRoutes` usage consistent, `unawaited_futures`, `Semantics(selected:)` on mode/timer/boost buttons, `Semantics(button:)` on speed arc segments, `TextPainter` leak, `_BoostButton` extraction, `RepaintBoundary` on dial

### Tests
- **Unit tests** — `CommandLoader` (YAML parsing, checksum, status poll), `BleFrameBuilder` (all facades), `BleResponseParser` (frame validation, all parse methods), `ActiveFanStateNotifier` (all state transitions, Nature/Boost exclusivity), `FanRepository` (CRUD, JSON import/export), `FanDevice` (defaults), `FanState` (copyWith, equality), `AppSettings` (JSON round-trip), `UsageLog` (kWh calculation), `UsageLogRepository` (add/get/range/delete)
- **Widget tests** — `ControlScreen` (BLE lifecycle, demo mode, speed dial, mode/boost, telemetry), `BlePermissionScreen` (flow, settings deep-link, demo fallback), `HomeScreen` (tab switching), `FansListScreen` (render, status badge, long-press), `AnalyticsScreen` (view switching, kWh/cost display), `BleScanScreen` (render, paired badge), `QrScanScreen` (overlay render, torch toggle), `NameFanScreen` (validation, routing), `ProfileSetupScreen` (input, routing), `SettingsScreen` (profile edit, export/import, OTA check, service QR), `UserManualScreen` (section expand/collapse), `ModeControlWidget` (enabled/active states), `TimerControlWidget` (selector state, callback), `ConnectionBanner` (render, retry)
