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

### Startup sequence (`lib/main.dart`)

1. `CommandLoader.load()` — loads `assets/commands.yaml` into static singleton
2. `initObjectBox()` — opens ObjectBox store
3. `_requestPermissions()` — requests `bluetoothScan`, `bluetoothConnect`, `locationWhenInUse`
4. `_ensureBluetoothOn()` — Android only; calls `FlutterBluePlus.turnOn()` if adapter is off, showing the system enable-Bluetooth dialog
5. `runApp()`

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
- **Search via Bluetooth** → `/scan/ble` — BLE scan list; user picks device; 15 s timeout. `dispose()` calls `stopScan()` so the BLE hardware scan is halted when the user leaves.
- **Scan QR Code** → `/scan/qr` — reads `device_id`, `model`, `fw_version` from QR JSON.

Both paths end at `/name-fan` (receives a `FanDevice` as GoRouter `extra`), then `/control`.

> **Note:** The PRD (v7) specifies a compile-time toggle via `AppConfig.onboardingMode`. The actual implementation offers both modes at runtime via a bottom sheet picker. `app_config.dart` has been removed.

### Router (`lib/shared/router.dart`)

`/name-fan` and `/control` both require a `FanDevice` passed via GoRouter `extra`. If `extra` is `null` (deep link or back-stack restore), a GoRouter `redirect:` sends the user to `/` rather than rendering the wrong screen at the wrong URL. Never return a fallback widget from a `builder` — use `redirect` instead.

Route constants live in `AppRoutes` (`lib/shared/app_routes.dart`). The `/permission-required` route (`AppRoutes.permissionRequired`) renders `BlePermissionScreen` — it has no `extra` requirement and can be navigated to from anywhere.

### Home screen (`lib/features/home/home_screen.dart`)

Displays fans grouped by model using `_GroupedFanList`. Each model group has a section header with a count badge. The total fan count is shown above the list. When `savedFansProvider` returns an empty list (no fans saved yet), the `data:` handler falls back to `_demoFan()` so the home screen is never blank during presentations. The demo fan is pure UI — it is not persisted to ObjectBox.

### Riverpod providers (`lib/core/providers.dart`)

- `bleServiceProvider` — singleton `BleServiceImpl`; one BLE connection at a time.
- `bleConnectionStateProvider` — `StreamProvider` wrapping `connectionStateStream`.
- `fanRepositoryProvider` — singleton `FanRepositoryImpl` (ObjectBox).
- `savedFansProvider` — `FutureProvider` that returns `getAllFans()`; call `ref.invalidate(savedFansProvider)` after any write.
- `activeFanStateProvider` — `StateNotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>`; keyed by `deviceId`; updated by BLE notifications. Mutate only through its named `update*` methods.

**Riverpod 2.x constraint:** `ref.read()` is forbidden inside `dispose()`. Cache any needed service in `initState()` as a field (see `control_screen.dart`).

### Storage

ObjectBox entities: `FanDevice` (identity/metadata) and `FanState` (last-known control state).
`FanDevice.deviceId` is the stable primary key assigned at onboarding. `macAddress` starts empty and is filled by `FanRepository.updateMac()` on first successful BLE connection.
`FanState.==` and `hashCode` include `deviceId` — states from different fans must not compare equal.
`objectbox.g.dart` is generated — do not edit manually. Run `build_runner` after changing either model.

### BLE service implementation notes (`lib/core/ble/ble_service.dart`)

- `writeFrame` copies `_writeChar` to a local variable before the null check to eliminate a TOCTOU race between the check and the write.
- On connection failure, `_connStateSub` is cancelled before retrying so a stale listener cannot spawn a concurrent retry chain.
- `startScan` clears `_discovered` on every call — scan results briefly empty when the user hits Refresh.

### Commands YAML (`assets/commands.yaml`)

Single source of truth for all BLE command bytes. Adding a new command or filling in pending lighting bytes requires only a YAML edit — no Dart changes needed. `CommandLoader._safeGet()` returns `null` gracefully for missing keys and is typed `YamlMap?` (not `dynamic`); `BleFrameBuilder` propagates the `null`; `ControlScreen._send()` shows a SnackBar instead of crashing. Lighting commands are currently `null` — pending values from Terraton.

**To add a new command:** add it to `commands.yaml`, then call `CommandLoader.custom(['commands', 'your_section', 'action'], [0xXX])` or add a named method to `BleFrameBuilder`.

**Phase 2 (approved, not yet built):** Remote command loading — app fetches `commands.yaml` from a hosted URL on launch, compares `version` field, updates local cache if newer, falls back to bundled asset on failure. No app update needed to deploy new command bytes.

### Permission handling (`lib/features/permission/ble_permission_screen.dart`)

`SplashScreen` waits 2 s, then checks `bluetoothScan` + `bluetoothConnect` via `permission_handler`. Both must be granted (AND logic) — if either is missing, it navigates to `/permission-required` (`BlePermissionScreen`). That screen requests both permissions, offers "Open App Settings" when permanently denied, and has a "Use Demo Mode Instead" escape hatch that goes home without permissions. `locationWhenInUse` is NOT requested — `BLUETOOTH_SCAN` is declared with `neverForLocation` in the manifest, making location unnecessary on API 31+.

`_ensureBluetoothOn()` in `main.dart` and the mid-session `FlutterBluePlus.turnOn()` call in `app.dart` are both wrapped in `try/on Object catch (_)` — a denied `BLUETOOTH_CONNECT` permission would otherwise crash.

### Arc gradient in `CircularSpeedDial`

The arc spans 145° → 395° (crosses the 360° boundary). Using `SweepGradient(startAngle: 145°, endAngle: 395°)` triggers a 2π wrap bug: `TileMode.clamp` pins any angular position < `startAngle` (i.e. 0°–35° = the bottom-right end of the arc) to the first gradient colour (Green), making the arc look backwards.

**Fix:** rotate the canvas by `+_startAngle`, draw the arc from 0 to `filledSweep`, use `SweepGradient(startAngle: 0, endAngle: _totalSweep)`. This places the arc start at screen angle `_startAngle` and keeps the entire arc within the gradient's 0–_totalSweep window with no wrapping. Note: `canvas.rotate(+_startAngle)` is correct — positive rotation places local angle 0 at screen angle `_startAngle`. The negative sign was incorrect and produced a gap on the left instead of at the bottom.

```dart
canvas.save();
canvas.translate(centre.dx, centre.dy);
canvas.rotate(_startAngle);  // positive — places arc start at screen angle _startAngle
canvas.translate(-centre.dx, -centre.dy);
canvas.drawArc(arcRect, 0, filledSweep, false, paint);
canvas.restore();
```

The same canvas-rotation trick is applied to the boost overlay arc (uses a 4-colour warm gradient: amber → orange → red-orange → deep red).

### Boost button animation (`_BoostButton` in `control_screen.dart`)

`_BoostButton` is a `StatefulWidget` with a single `AnimationController` (`_shimmerCtrl`, 2000 ms linear repeat). When boost is active it renders:

1. A `ClipRRect(radius: 14)` wrapping a `Stack`
2. A `Positioned.fill` `DecoratedBox` with a `LinearGradient([0xFFBF2600, 0xFFFF5500, 0xFFCC2200])`
3. A 90 dp wide `Positioned` shimmer stripe that sweeps left→right via `_shimmerCtrl.value * (width + shimmerW) - shimmerW`

No `BackdropFilter` or `BoxShadow` blur — edges stay sharp. Tapping active boost calls `updateMode(null)` (no BLE frame) to deactivate; tapping inactive boost sends the boost frame.

### Control screen telemetry

Polls every 3 seconds after connect: `queryPower` frame → 200 ms delay → `querySpeed` frame. A `mounted` check runs after the delay before the second write. Responses arrive on `notifyStream` and are dispatched by command byte (`0x02`–`0x24`) to the appropriate `ActiveFanStateNotifier.update*()` method.

### Speed dial colours (AC-05-3)

Speed 1 `#22C55E` (Green) · Speed 2 `#06B6D4` (Cyan) · Speed 3 `#3B82F6` (Blue) · Speed 4 `#8B5CF6` (Violet) · Speed 5 `#F97316` (Orange) · Speed 6 `#EF4444` (Red)

These are defined in `kSpeedColors` (`lib/shared/theme.dart`) and used as the arc gradient colour stops in the same order — so Speed 1 is always at the arc start (green) and Speed 6 at the end (red).

---

## UI Design Reference (`uiDesigns/tera1–4.jpg`)

These are the approved Figma-exported designs. Use them as the source of truth for any UI work. Current implementation diverges from the designs in several areas — those gaps are marked **[NOT YET BUILT]** or **[DIFFERS]**.

### Splash Screen *(tera1 — V1)*
- Terraton fan logo (rounded blue square with fan propeller icon) centred on a light-grey background.
- "TERRATON" in bold, "SMART BLDC FAN CONTROL" subtitle beneath.
- Three dot page indicators at the bottom (animated — `AnimationController` 900 ms repeat).
- **Current implementation** (`lib/features/splash/splash_screen.dart`): splash exists; logo, title, and animated dots match the design. After a 2 s delay, checks `bluetoothScan` + `bluetoothConnect` permissions — routes to `/permission-required` if denied, else to `/home`.

### Home Screen — Empty State *(tera1 — V4)* **[DIFFERS]**
- Title: "My Fans". Settings gear icon in AppBar.
- Empty state: large faded fan icon, "No Fans Added Yet", subtitle "Scan your Terraton fan QR code to begin controlling your environment."
- Full-width "Scan to Add Fan" button with search icon.
- FAB (+) in bottom-right corner.
- **Current implementation** falls back to `_demoFan()` instead of showing the empty state. Design intent is a proper empty state — remove the demo fan fallback when building production UI.

### Home Screen — Fan Cards *(tera1 — V3)* **[DIFFERS]**
- Title: "My Fans" with "Welcome back, User" subtitle.
- Each card shows: fan icon, nickname (bold), model (e.g. "Terraton X1"), live status badge (dot + label).
- Status badge colours: green "Connected", grey "Disconnected", amber "Connecting…".
- Chevron right on each card. FAB (+) in bottom-right.
- **Current implementation** groups by model with a count badge header and shows last-connected time instead of live status. Cards do not yet show the connection-status badge.

### Home Screen — Long Press (options sheet) *(tera2 — V1)*
- Bottom sheet on long-press of a fan card.
- Two options: **Rename Fan** (pencil icon, "Change the display name of this device") and **Remove Device** (trash icon, "Unpair and remove from your account").
- **Cancel** button at the bottom.
- Matches current implementation. Note: design labels say "Rename Fan" / "Remove Device" — code currently uses "Rename" / "Delete".

### Name Your Fan Screen *(tera2 — V2)* **[DIFFERS]**
- Fan icon in a circle with a green "DETECTED" pill badge.
- "Name Your Fan" heading. Subtitle: "Terraton X1 detected! Give it a nickname to easily identify it later."
- Text field with placeholder "Living Room Fan" and character counter "15 / 30".
- Green info card: "Nickname Requirements" with checkmark icon listing the three rules.
- Full-width "Save & Continue" button.
- **Current implementation** has a plain `TextFormField` form; missing the detected badge, requirements info card, and uses "Save" instead of "Save & Continue".

### Control Screen — Active *(tera3 — V20)*
- AppBar: back arrow, fan nickname, settings gear, "• CONNECTED" green status label below the title.
- **Power button**: blue filled circle with power icon, centred at the top.
- **Telemetry arc**: smooth rainbow-gradient arc (decorative display only, NOT interactive). Shows watts (e.g. "28 W") and RPM (e.g. "360 RPM") in the centre of the arc.
- **Speed selector**: 6 rectangular buttons in a 2-row × 3-column grid. Active speed button is filled blue.
- **Boost**: full-width dark-blue button labelled "⚡ BOOST MODE".
- **Operating Modes**: section header "OPERATING MODES" in small caps; Nature / Smart / Reverse chip-style buttons.
- **Sleep Timer**: section header "SLEEP TIMER"; OFF / 2H / 4H / 8H buttons.
- **Mood Lighting**: card row with sun icon, "Mood Lighting" label, and a single ON/OFF toggle switch (not two separate buttons). Below: "WARM" ← slider → "COOL" colour temperature slider.

> **Speed selector design vs current**: The design uses a decorative arc (display only) plus a 3×2 button grid for speed selection. The current implementation uses `CircularSpeedDial` where the arc segments themselves are tappable. When refactoring: separate the arc visual from speed selection buttons.

> **Mood Lighting design vs current**: Design uses a `Switch` widget for ON/OFF. Current uses two `OutlinedButton` widgets.

### Control Screen — Disconnected *(tera4 — V2)*
- AppBar shows "DISCONNECTED" (grey, no dot).
- All controls are visually ghosted/disabled. Arc shows "-- W" / "-- RPM".
- **Connection Lost card**: bottom-anchored card with a clock icon, "Connection Lost" heading, "Fan not found. Is it powered on and within range?" body, and a "Retry Connection" full-width blue button.
- **Current implementation** (`connection_banner.dart`) renders the `ConnectionLostCard` as a bottom-anchored overlay — matches the design intent.

### Settings Screen *(tera4 — V1)* **[DIFFERS]**
- Back arrow, "Settings" title (centred, bold).
- **DATA MANAGEMENT** section: "Export Fans Data" (upload icon), "Import Fans Data" (download icon) — matches current implementation.
- **ABOUT** section — built; displays App Version (from `package_info_plus`), and static "BLE 5.2" protocol string.
- **SUPPORT** section — stub only; "User Manual" row present but URL not yet provided by Terraton.
- Terraton fan logo centred at the bottom of the screen.

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
- `_BoostButton` is a `StatefulWidget` (owns `_shimmerCtrl`). In tests, find it via `find.byType(_BoostButton)` or by the `ValueKey('boost_button')` on its root `GestureDetector`, then invoke the `onBoost` callback directly.
