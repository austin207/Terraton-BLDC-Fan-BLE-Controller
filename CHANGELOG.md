# Changelog

All notable changes to the Terraton Fan BLE Controller are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.9.0] — 2026-05-25

### Added
- **Full-screen immersive QR scanner** (`qr_scan_screen.dart`) — replaced the small centred viewport with a full-screen camera feed. Dark semi-transparent overlay with a rounded transparent cutout, yellow corner bracket markers, and an animated scan line with gradient glow. Frosted top controls bar (close + torch toggle) and bottom info panel with drag handle. All logic (fan pairing, service access, QR validation) is unchanged — only the visual layer.

### Fixed
- **BLE stays connected on Back** (`control_screen.dart`) — removed the explicit `_ble.disconnect()` from `_ControlScreenState.dispose()`. The fan remains connected when navigating back to the fans list, matching user expectation.
- **Fan status badge shows live BLE connection state** (`fans_list_screen.dart`) — the badge is now wired to `bleConnectionStateProvider` + `connectedMacAddress`; shows green "Connected" for the currently connected fan and grey "Disconnected" otherwise.
- **Fan icon spins when fan is powered on** (`fans_list_screen.dart`) — `TerratonFanIcon` receives `spinning: isPowered` so the blade animation reflects the actual power state in the list.
- **`BleServiceImpl.connect()` same-MAC guard** (`ble_service.dart`) — returns immediately if already connected to the same MAC, preventing redundant GATT discovery. Also adds a clean teardown of any existing connection before connecting to a different device.

---

## [1.8.0] — 2026-05-25

### Added
- **Background usage tracking** (`control_screen.dart`) — `_FanControlsPanelState` now mixes in `WidgetsBindingObserver`. On `AppLifecycleState.paused` (home button, screen lock, swipe to recents) it flushes the current usage segment to ObjectBox. On `AppLifecycleState.resumed` it re-seeds a new segment from the live fan state.
- **Android BLE foreground service** (`TerraBgService.kt`, `ble_foreground_service.dart`) — a persistent foreground service keeps the app process alive when the user swipes it from recents. Dart calls the service via a `MethodChannel("com.terraton/bg_service")` with `start`, `update`, and `stop` methods. The notification shows "Terraton Fan" with a live label (e.g. "Speed 3 · 28W"). Service uses `START_NOT_STICKY` — it does not restart automatically after being force-killed.

### Fixed
- **Install Unknown Apps permission** (`settings_screen.dart`) — OTA installer now checks `Permission.requestInstallPackages` and routes to the system "Install Unknown Apps" settings page if not granted, rather than silently failing to open the APK.

---

## [1.7.0] — 2026-05-24

### Fixed
- **OTA version check: UTF-8 BOM and charset mismatch** (`ota_update_service.dart`) — GitHub Releases API response was being parsed with the wrong charset, causing a BOM (`﻿`) to prefix the version string and break the semver comparison. Fixed by explicitly decoding the response body as UTF-8 and stripping any leading BOM.
- **Design tokens: 7th pass** — replaced all remaining hardcoded hex colour literals with `theme.dart` tokens; covers the analytics tariff cost strip and any other remaining sites across the codebase.
- **OTA URL: removed redundant cache-busting query parameter** — the GitHub API already returns fresh data; the appended timestamp caused spurious cache misses on some CDN nodes.
- **Code-review passes 4 and 5** — resolved additional flutter-dart-code-review findings across the codebase.

---

## [1.6.0] — 2026-05-24

### Added
- **Manual "Check for Updates" in Settings** (`settings_screen.dart`) — a "Check for Updates" row in the About section triggers the OTA version check on demand without restarting the app. Shows an in-progress indicator and presents the "Download & Install" bottom sheet if a newer build is found.

---

## [1.5.0] — 2026-05-24

### Fixed
- **OTA: connectivity pre-check removed** — `connectivity_plus` vacuous-truth edge case where an empty network list was treated as "connected"; replaced with a direct HTTP attempt and error handling.
- **OTA: critical and high review findings** — null-safety gaps, unhandled exceptions, and missing `mounted` guards in the OTA update flow.
- **OTA: second-pass review findings** — additional lint and style fixes from a follow-up flutter-dart-code-review pass.

---

## [1.4.0] — 2026-05-24

### Fixed
- **OTA: first-pass review findings** — splash version string, permission handler call sites, and miscellaneous issues identified in the initial flutter-dart-code-review of the OTA update code.

---

## [1.3.0] — 2026-05-24

### Fixed
- **Build: skip version bump when pubspec already clean** (`build.ps1`) — the version bump step now checks whether `pubspec.yaml` was actually modified before creating a commit, preventing empty "chore: bump version" commits on re-runs.

---

## [1.2.0] — 2026-05-24

### Fixed
- **build.ps1: PS5.1 encoding issues** — replaced em dash characters with ASCII hyphens in string literals; fixed `pubspec.yaml` write encoding so the version string is stored as UTF-8 without a BOM.

---

## [1.1.0] — 2026-05-24

### Added
- **OTA self-update from GitHub Releases** (`ota_update_service.dart`) — on launch the app fetches the latest release from the GitHub API, compares `build_number` (`+N`), and offers a "Download & Install" sheet if a newer build is available. Download progress is shown inline; the APK is opened in the Android system installer on completion.
- **Interactive semver bump in build.ps1** — the release script now prompts **P**atch / **N**ew feature / **J**umbo (major) and increments `pubspec.yaml` automatically before building and publishing.

---

## [1.0.0] — 2026-05-23

### Added
- **AI training data pipeline** (`data_upload_service.dart`) — anonymised usage segments (gear, watts, mode, duration) are uploaded to a Cloudflare Worker (`terraton-ingest`) and stored in R2. Upload is gated behind an opt-in toggle and an API key injected at build time only.
- **AI Training section** in User Manual — plain-language explanation of what data is collected and how it is used.
- **Privacy Policy and Terms of Service screens** — accessible from Settings; rendered from bundled HTML via `WebView`.
- **MLOps + CI/CD** — GitHub Actions workflows for R2 data health check and model upload pipeline; local retraining via `ml/retrain.ps1`; XGBoost + Keras two-tower model pipeline targeting TFLite.
- **User Manual screen** (`user_manual_screen.dart`) — 8 expandable sections: Getting Started, Controlling Fan Speed, Boost Mode, Operating Modes, Sleep Timer, Mood Lighting, Managing Your Fans, Troubleshooting.
- **`BlePermissionScreen`** (`ble_permission_screen.dart`) — requests `bluetoothScan` + `bluetoothConnect`; shows per-state guidance (denied / permanently denied / granted); includes "Use Demo Mode Instead" escape hatch.
- **Demo mode** — full UI walkthrough without hardware; `_applyDemoFrame` parses BLE frames locally; triggered from the permission screen fallback.
- **Dual onboarding at runtime** — QR scan and BLE scan both available in one APK via a bottom-sheet picker; removed compile-time `--dart-define=BLE_SCAN` toggle.
- **Analytics screen** — kWh / cost / efficiency / per-fan breakdown; Day / Week / Month views; usage segments flushed by `_flushSegment()` on every mode/speed change.
- **`clearWatts()` / `clearRpm()`** in `ActiveFanStateNotifier` — 5-second stale telemetry timeout.
- **`AppRoutes` abstract final class** — single source of truth for all route path strings.
- **`FanState.==` / `hashCode`** — Riverpod suppresses rebuilds when `copyWith` produces equal state.
- **`kBoostColor`**, **`kDemoDeviceId`** design tokens — remove magic literals from widget files.
- **Accessibility**: `Semantics(selected:)` on mode, timer, and boost buttons; `Semantics(button:)` on speed arc segments; tooltips on icon buttons.
- **Unit tests** — command loader, frame builder, response parser, active fan state notifier, fan repository (14 tests each covering non-trivial paths).
- **Widget tests** — BLE permission screen, control screen (BLE lifecycle, demo mode, speed dial, mode/boost, telemetry).

### Changed
- **Sleep Timer control** — `AnimatedPositioned` sliding segmented control replaces four individual pill buttons; optimistic local state moves the pill instantly on tap.
- **Mood Lighting toggle** — matching sliding pill segmented control.
- **Speed dial arc** — single continuous `SweepGradient` replaces per-segment arcs; correct colour order green → red across speeds; `setEquals()` in `shouldRepaint` for `disabledSpeeds`.
- **Boost shimmer** — sharp shimmer stripe animation replaces `BoxShadow` glow; fire-gradient background (`0xBF2600 → 0xFF5500 → 0xCC2200`); boost toggle-off calls `updateMode(null)`.
- **`activeFanStateProvider`** — `autoDispose.family` keyed by `deviceId`; notifier released when not watched.
- **`savedFansProvider`** — `FutureProvider` (was `Provider`); queries run off the build thread.
- **`FanStateCopyWith` extension** — getter-pattern `copyWith` for nullable fields.
- **Portrait lock** — `SystemChrome.setPreferredOrientations([portraitUp])` in `main.dart`.
- **`analysis_options.yaml`** — strict-casts, strict-inference, strict-raw-types; key lints: `unawaited_futures`, `avoid_catches_without_on_clauses`, `always_use_package_imports`.

### Fixed
- **Nature mode BLE frame order** — mode frame sent BEFORE speed frame when exiting Nature; hardware ignores speed commands while Nature is active.
- **`BrandMark` PNG crop** — pixel-measured content bounds (x=123–421, y=203–272 on 537×464 canvas); `ClipRect` wraps `SizedBox` (content width), not `Align`.
- **`BleResponseParser.parseSpeed()` bounds check** — returns `null` for bytes outside 1–6 instead of crashing with `RangeError`.
- **Scan subscription leak** (`ble_scan_screen.dart`) — `if (!mounted) return` after `await _sub?.cancel()` prevents a new subscription being created after `dispose()`.
- **Per-item DB queries in BLE scan list** — replaced `getFanByMac()` per list item with a `Set<String>` pre-built from `savedFansProvider`; O(1) lookup.
- **`_notifyValueSub` leak** (`ble_service.dart`) — subscription cancelled before resubscribing on each reconnect and in `dispose()`.
- **All `context.mounted` guards** — added after every `await` in connect, timer, and notify callbacks.
- **`importFromJson` error handling** — `TypeError` from malformed JSON re-thrown as `FormatException`.
- **Service QR one-shot timer** — `Timer` stored and cancelled in `dispose()`; QR data cached as field.
- **`build.ps1` APK path** — updated for split-per-ABI output (`app-arm64-v8a-release.apk`).
- **App icon case-sensitivity** — `Icon.png` → `icon.png` (two-step rename for Android Linux filesystem).
