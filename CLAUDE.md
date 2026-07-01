# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Overview

Android Flutter app that controls a Terraton BLDC ceiling fan over BLE v5.2 via an Amp'ed RF BLE60 module. Fan control is fully offline over BLE — no network is required to operate a fan. The only HTTP calls are to a Cloudflare Worker and are non-essential: an anonymous launch ping, an opt-in once-per-day usage upload (Wi-Fi only), and the OTA update check.

```text
Flutter App --BLE v5.2--> BLE60 Module --UART1--> Fan MCU --> BLDC Motor
```

The app writes framed packets to the Write Characteristic; the fan responds on the Notify Characteristic. The BLE60 is a transparent UART bridge — it only flushes to the MCU when it receives `\r\n` (0x0D 0x0A), which `writeFrame()` appends automatically.

---

## RTK Usage

RTK is installed at `~/.local/bin/rtk.exe`. The bash auto-rewrite hook does not fire on native Windows, so **always prefix commands explicitly** with `rtk` when running in the Bash tool:

| Instead of | Use |
|---|---|
| `flutter test ...` | `rtk flutter test ...` |
| `flutter analyze ...` | `rtk flutter analyze ...` |
| `git status` | `rtk git status` |
| `git diff` | `rtk git diff` |
| `git log` | `rtk git log` |
| `git add / commit / push` | `rtk git add` / `rtk git commit` / `rtk git push` |
| `dart run build_runner ...` | `rtk dart run build_runner ...` |

Use `rtk gain` to check cumulative token savings.

---

## Commands

All Flutter commands run from `terraton_fan_app/`.

```powershell
# Analyze
rtk flutter analyze --no-fatal-infos

# Run all tests
rtk flutter test

# Single test file
rtk flutter test test/unit/ble_frame_builder_test.dart
rtk flutter test test/widget/control_screen_test.dart

# Build — saves to builds/ and publishes to GitHub Releases (run from repo root)
.\build.ps1

# Regenerate ObjectBox & Riverpod code (run after editing models or providers)
rtk dart run build_runner build --delete-conflicting-outputs
```

---

## Architecture

### Startup sequence (`lib/main.dart`)

1. `FlutterError.onError` + `platformDispatcher.onError` — global error handlers; `ErrorWidget.builder` overridden with dark-theme error screen
2. `CommandLoader.load()` — loads `assets/commands.yaml` into static singleton
3. `initObjectBox()` — opens ObjectBox store
4. `_ensureBluetoothOn()` — Android only; calls `FlutterBluePlus.turnOn()` if adapter is off; permission errors silently swallowed (BlePermissionScreen handles retry)
5. `runApp(ProviderScope(TerratorApp()))` — permission check runs inside `SplashScreen` after 2 s delay; routes to `/profile-setup` (first launch) or `/home`

### Data flow

```text
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once in main.dart before runApp; static singleton
        │
        ▼
  BleFrameBuilder          ← typed facade; returns null for pending/unknown commands
        │
        ▼
  BleService (abstract) / BleServiceImpl (flutter_blue_plus)
        │  connect(mac) ──► GATT connect → service discovery → char setup
        │  writeFrame()  ──► fan hardware  (+0D 0A BLE60 flush terminator)
        │  notifyStream  ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox)     ← persists FanDevice + FanState
  UsageLogRepository (ObjectBox) ← persists per-session energy segments (analytics)
```

### BLE Protocol

**Request frame:** `[0x55, 0xAA, 0x06, <cmd>, <len>, ...data, <checksum>]`
**Response frame:** same but byte[2] is `0x07`.
**Checksum:** `(0x55 + 0xAA + packetId + cmd + dataLen + Σdata) & 0xFF` — includes the full header.
**Status poll:** non-standard fixed frame `[55 AA 00 00 01 00 00]` — do NOT pass through `buildFrame()`.
**Motor State poll:** non-standard fixed frame `[55 AA 00 01 01 00 01]` — do NOT pass through `buildFrame()`. Response: 3 frames — [1] `0x02` power, [2] `0x04` speed OR `0x21` active mode (mutually exclusive), [3] `0x22` timer. Frame [2] is exclusive truth; clear all other mode/speed highlight state. The BLE60/MCU may split or reorder these 3 frames across notifications (especially right after a mains power-cycle reboot) — the app assembles them atomically rather than assuming same-notification order; see "Machine State assembly on reconnect" below.

**BLE UUIDs (defined only in `ble_constants.dart`):**
- Scan filter: `00001827-0000-1000-8000-00805f9b34fb` (BLE Mesh Proxy)
- Write char: `00002adb-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data In)
- Notify char: `00002adc-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data Out — call `setNotifyValue(true)`)

Service discovery also searches: Amp'ed RF proprietary (26cc3fc2/26cc3fc1), CC254X/HM-10 (0000ffe1), Nordic UART Service, Microchip RN4870 — first match wins.

**Verified command frames:**

| Operation | Frame (hex) |
| --------- | ----------- |
| Power ON | `55 AA 06 02 01 01 09` |
| Power OFF | `55 AA 06 02 01 00 08` |
| Speed 1–6 | `55 AA 06 04 01 0N checksum` |
| Boost | `55 AA 06 21 01 01 28` |
| Nature | `55 AA 06 21 01 02 29` |
| Reverse | `55 AA 06 21 01 03 2A` |
| Smart | `55 AA 06 21 01 04 2B` |
| Timer OFF/2H/4H/8H | `55 AA 06 22 01 00/02/04/08 28/2A/2C/30` |
| Query Power (watts) | `55 AA 06 23 01 00 29` |
| Query Speed (RPM) | `55 AA 06 24 01 00 2A` |
| Get Motor State | `55 AA 00 01 01 00 01` |
| Query Runtime | `55 AA 00 08 01 00 08` — response: `55 AA 07 08 02 HH LL CRC`; runtime = `(HH<<8\|LL) × 5` seconds. Sent on connect + every 90 s via `_runtimeTimer`. Updates `FanState.lastRuntimeSecs`. |

### Onboarding flow

`goToOnboarding(context)` in `router.dart` shows a bottom sheet with two options:
- **Bluetooth pairing** → `/scan/ble` — BLE scan list; 15 s timeout; `dispose()` calls `stopScan()`
- **QR code pairing** → `/scan/qr` — reads `device_id`, `model`, `fw_version` from QR JSON

Both paths end at `/name-fan` (receives `FanDevice` as GoRouter `extra`), then `/control`.

### Home screen architecture (`lib/features/home/home_screen.dart`)

`HomeScreen` is an `IndexedStack` shell with a floating bottom nav. Three tabs:
- **0 = Analytics** (`AnalyticsScreen`) — kWh / cost / efficiency / per-fan breakdown
- **1 = Home** (`_HomeTab`) — greeting, "Fans" tile (pushes `FansListScreen`), usage card
- **2 = Settings** (`SettingsScreen`)

`FansListScreen` (`/fans`) is a separate route pushed from the Home tab. It shows all paired fans with long-press rename/remove actions. Status badges are wired to `bleConnectionStateProvider` + `connectedMacAddress` — show green "Connected" when the displayed fan matches the live BLE connection.

### Router (`lib/shared/router.dart`)

`/name-fan` and `/control` both require a `FanDevice` passed via GoRouter `extra`. If `extra` is `null`, a `redirect:` sends the user to `/` — never use a fallback widget in `builder`, always use `redirect`.

Route constants live in `AppRoutes` (`lib/shared/app_routes.dart`).

### Riverpod providers (`lib/core/providers.dart`)

- `bleServiceProvider` — singleton `BleServiceImpl`; one BLE connection at a time
- `bluetoothAdapterStateProvider` — `StreamProvider<BluetoothAdapterState>`
- `bleConnectionStateProvider` — `StreamProvider<BleConnectionState>`
- `fanRepositoryProvider` — singleton `FanRepositoryImpl` (ObjectBox)
- `usageLogRepositoryProvider` — singleton `UsageLogRepositoryImpl` (ObjectBox)
- `dailyRuntimeRepositoryProvider` — singleton `DailyRuntimeRepositoryImpl` (ObjectBox); backs per-day firmware runtime tracking
- `savedFansProvider` — `FutureProvider` returning `getAllFans()`; call `ref.invalidate(savedFansProvider)` after any write
- `connectedFanDeviceIdProvider` — `StateProvider<String?>`; set by `_ControlScreenState` on connect, cleared on dispose; lets `AnalyticsScreen` watch live state without knowing the deviceId up front
- `activeFanStateProvider` — `NotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>`; keyed by `deviceId`; mutate only through named `update*` / `set*` methods; exposes `updateRuntime(int secs)` which persists `lastRuntimeSecs` to ObjectBox
- `userNameProvider` — `AsyncNotifierProvider<UserNameNotifier, String>`; persisted to `app_settings.json`
- `packageInfoProvider` — `FutureProvider<PackageInfo>`

**Riverpod 2.x constraint:** `ref.read()` is forbidden inside `dispose()`. Cache needed services in `initState()` as a field.

### Storage

ObjectBox entities: `FanDevice` (identity/metadata), `FanState` (last-known control state), `UsageLog` (energy segment per mode/speed change), `DailyRuntime` (one record per fan per calendar day; upserted from the runtime-query response every 90 s).
`FanDevice.deviceId` is the stable primary key. `macAddress` starts empty; filled by `FanRepository.updateMac()` on first successful BLE connection.
`FanState.==` and `hashCode` include `deviceId`.
`DailyRuntime` keyed by `(deviceId, date)` (local midnight); never treat a missing day as zero — `AnalyticsCalculations.normalizeDailyRuntimes` fills gaps with the average of available days.
`objectbox.g.dart` is generated — run `build_runner` after changing any model.

### BLE service implementation notes (`lib/core/ble/ble_service.dart`)

- `writeFrame` copies `_writeChar` to a local variable before the null check (eliminates TOCTOU race).
- On connection failure, `_connStateSub` is cancelled before retry so a stale listener cannot spawn concurrent retry chains.
- `startScan` clears `_discovered` and `_scanCache` on every call — scan results briefly empty when user hits Refresh.
- **Do NOT call `startScan()` before `connect()`** — it clears `_scanCache`, destroying the live `BluetoothDevice` that carries the correct BLE address type. Control screen calls `_ble.connect(mac)` directly without scanning first.
- The BLE60 uses a random BLE address. `BluetoothDevice.fromId(mac)` guesses public type. Always use the live device from `_scanCache` on first connection; `fromId()` is fine for reconnects after Android has cached the address type.

### Commands YAML (`assets/commands.yaml`)

Single source of truth for all BLE command bytes. Adding a new command requires only a YAML edit — no Dart changes.

`CommandLoader._safeGet()` returns `null` gracefully for missing keys; `BleFrameBuilder` propagates `null`; `ControlScreen._send()` shows a SnackBar instead of crashing. Lighting commands are currently `null` — pending bytes from Terraton.

**To add a new command:** add it to `commands.yaml`, then call `CommandLoader.custom(['commands', 'your_section', 'action'], [0xXX])` or add a named method to `BleFrameBuilder`.

**Phase 2 (approved, not yet built):** Remote command loading — fetch `commands.yaml` from a hosted URL on launch, compare `version` field, update local cache if newer, fall back to bundled asset on failure.

### Nature mode logic (`lib/features/control/control_screen.dart`)

`_preNatureSpeed: int` on `_FanControlsPanelState`. Seeded in `initState()` from ObjectBox if fan loads already in nature.

Three paths out of Nature — **BLE frame order is critical** (mode frame must go before speed frame; hardware ignores speed while Nature is active):
1. **→ Smart or Reverse:** `_preNatureSpeed` restored (min 3 for Smart); mode frame sent FIRST, then speed frame
2. **→ Boost:** skip speed restore; Nature cleared, Boost activated
3. **Toggle off (tap same mode):** send speed frame only, no mode frame

Mode callbacks (`_onMode`, `_onBoost`) are named methods on `_FanControlsPanelState` — not inline lambdas in `build()`. They use `ref.read` (correct for event handlers, not `ref.watch`).

### Mode mutual exclusivity (Boost / Nature / Smart / Reverse)

Enforced in `ActiveFanStateNotifier` (`setBoostActive`, `setActiveMode`, `updateMode` — `lib/core/providers.dart`), not in the UI handlers, so both the live-toggle path and the remote-notification path stay consistent:
- **Boost ↔ Nature** — mutually exclusive (Nature blocks Boost activation; Boost clears Nature).
- **Boost ↔ Smart** — mutually exclusive (activating either clears the other).
- **Boost ↔ Reverse** — may coexist (both can be active at once).
- `applyMotorStateTruth` (the Machine State frame [2] path) is always fully exclusive regardless of the above — the firmware reports exactly one state (a speed or a single mode) at a time.

### Machine State assembly on reconnect (`control_screen.dart`)

A getMotorState reply is always 3 frames (power, speed-or-mode, timer), but the BLE60/MCU may split or reorder them across separate notifications — most commonly right after a mains power-cycle, when the fan MCU has just rebooted. Applying frames live as they arrive is unsafe: the speed/mode gate needs the power frame applied first, so a split reply could silently drop the restored speed.

Fix: while awaiting a reply we sent (`_awaitingMotorState`), frames are buffered (`_msPower`/`_msSpeed`/`_msMode`/`_msTimer`) instead of applied live, then flushed atomically by `_flushMachineState()` — either immediately once complete, or after a 300 ms debounce (`_msFlushTimer`) if a later frame is still in flight. A power=ON reply with no speed/mode yet (MCU still booting) is treated as incomplete, so the existing retry loops (`_scheduleConnectPolls`, `_scheduleWakePolls`) keep polling until the real state arrives. Watts/RPM/runtime frames are applied live even during this window (status-poll telemetry interleaves with the connect burst). The 90 s Smart/Nature/Reverse poll (`_updateMotorStatePoll`) also routes through this path via `_requestMotorState()`. `resetOnConnect()` clears the persisted timer too, so a stale value can't flash before the real one lands.

### CircularSpeedDial (`lib/features/control/circular_speed_dial.dart`)

Radial dot-ring design (class name preserved for test compatibility):
- 6 dots + tick marks on a ring (radius 110dp, canvas 320dp square)
- `_DialPainter` (CustomPainter): dark core circle, thin track ring, yellow arc when `speed > 1`, dots with bloom glow for selected state
- `_dotStateOf()` — single source of truth for dot state; used by BOTH painter and hit-area logic
- Hit areas: 48dp `GestureDetector` (meets accessibility minimum) centered on each dot; `HitTestBehavior.opaque`
- `shouldRepaint` uses `setEquals(old.disabledSpeeds, disabledSpeeds)` from `foundation.dart`
- Nature mode: `isNature: true` disables all dots and shows a leaf icon in the centre

### BrandMark (`lib/shared/brand_mark.dart`)

`terraton-full.png` (537×464 px) has large transparent whitespace. Pixel-measured content bounds: x=123–421, y=203–272.

Rendering pattern (crop to exact content bounds):

```text
Align > ClipRect > SizedBox(contentW × height) > OverflowBox > Transform.translate > Image
```

`ClipRect` MUST wrap `SizedBox` (content width), NOT `Align` (full parent width). Wrapping `Align` allows the overflowed image to paint outside `contentW`.

### Control screen telemetry (`lib/features/control/control_screen.dart`)

Polls every 3 seconds after connect via a single `statusPoll()` frame (non-standard fixed frame). Responses arrive on `notifyStream` and are dispatched by command byte:
- `0x02` → power on/off
- `0x04` → speed (1–6)
- `0x21` → mode string
- `0x22` → timer code
- `0x23` → watts
- `0x24` → RPM

Polls on every 3 s tick regardless of power state. **Response frame count (hardware-verified):** normally 2 frames — `0x23` watts + `0x24` RPM. **Exception:** the very first status poll after the fan is connected to mains power AND turned on via the app returns **4 frames** — `0x02` (power state), `0x04` (speed), `0x23` (watts), `0x24` (RPM) — so the fan can restore any state that reset during the power-off period. Subsequent polls in the same session return 2 frames. The response handler in `_subscribeNotify` already dispatches all four frame types; no special casing needed. Stale values (no response in 5 s) cleared by `notifier.clearWatts()` / `notifier.clearRpm()`.

### App lifecycle: disconnect on background, reconnect on resume (`control_screen.dart`)

`_ControlScreenState` is a `WidgetsBindingObserver`. `didChangeAppLifecycleState`:
- **`paused`** (screen off OR app backgrounded — home button, app switch): cancel the telemetry timer, `BleForegroundService.stop()`, then `_ble.disconnect()`. Releasing the single GATT connection frees the fan for another phone. The foreground notification is stopped so it can't linger showing stale telemetry.
- **`resumed`**: if `_ble.currentState != connected`, call `_connect()`. Because the BLE60 allows only one connection, `connect()` fails gracefully with an `'in use by another device'` status (GATT 133, see `ble_service.dart`) when another phone holds the fan — so resume **never steals** an active connection. The connect attempt *is* the "is another phone using it?" check; there is no separate probe (the fan stops advertising when connected elsewhere, and scan-before-connect is forbidden).
- `inactive` / `hidden` / `detached`: no-op.

Demo mode (`_isDemo`) skips all of the above. Observer is registered in `initState` and removed first thing in `dispose`.

**Note:** this is independent of Cloudflare usage upload — that runs at app startup in `main.dart` (`DevicePingService.ping()` + `DataUploadService.tryUpload()`), gated by opt-in + Wi-Fi + once-per-day. Dropping the BLE link on background does not affect uploads.

### Permission handling (`lib/features/permission/ble_permission_screen.dart`)

`SplashScreen` waits 2 s, then checks `bluetoothScan` + `bluetoothConnect`. Routes to `/permission-required` if either is missing. `BlePermissionScreen` requests both permissions, offers "Open App Settings" when permanently denied, and has a "Use Demo Mode Instead" escape hatch. `locationWhenInUse` is NOT requested — manifest declares `neverForLocation`, making location unnecessary on API 31+.

### Demo mode

Demo fan has `deviceId == kDemoDeviceId` (`'__demo__'`); `_isDemo` getter in `ControlScreen` bypasses all BLE calls. `_applyDemoFrame` parses BLE frames locally and updates state via notifier — same result as real hardware.

`kDemoDeviceId` is defined in `lib/shared/app_routes.dart` and imported by `control_screen.dart`, `fan_card.dart`, and `qr_scan_screen.dart`.

### Analytics (`lib/features/analytics/analytics_screen.dart`)

Real data from `UsageLogRepository`. Usage segments are flushed by `_FanControlsPanelState._flushSegment(newGear, newMode)` on every mode/speed change. Segment includes: `deviceId`, `startTime`, `durationSecs`, `gear`, `watts`, `mode`. Energy in kWh = `watts × durationSecs / 3_600_000`. Efficiency is computed against a `_traditionalWatts = 85.0 W` baseline.

---

## Hard Constraints (from PRD §6.1)

- UUID constants live only in `ble_constants.dart` — never duplicated
- Command bytes live only in `assets/commands.yaml` — never hardcoded in Dart
- All BLE writes go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()`
- ObjectBox only for fan data (no Hive, no Isar, no SharedPreferences)
- Android only — no iOS build
- Single active BLE connection — one fan at a time
- Fan control is fully offline over BLE — never gate fan operation on network. The only HTTP is the anonymous launch ping (`DevicePingService`), the opt-in daily usage upload (`DataUploadService`, Wi-Fi only), and the OTA update check (`AppUpdateService`) — all to a Cloudflare Worker, all non-essential
- Design tokens (`kYellow`, `kBg`, `kCard`, `kText`, etc.) from `lib/shared/theme.dart` — no hardcoded hex colours in widget files

---

## Known Open Issues (from 2026-05-23 audit)

| Severity | File | Issue |
| --- | --- | --- |
| ~~MEDIUM~~ | ~~`fan_card.dart`~~ | ~~Light-theme hardcoded colours (`Colors.white` bottom sheet, `0xFF1E293B` text) clash with dark theme~~ | **N/A — file removed; content absorbed into `fans_list_screen.dart` which uses proper tokens** |
| ~~MEDIUM~~ | ~~`fans_list_screen.dart:275`~~ | ~~Status badge hardcoded "Disconnected"; not wired to `bleConnectionStateProvider`~~ | **Fixed 2026-05-24** |
| ~~MEDIUM~~ | ~~`fans_list_screen.dart:180`, `fan_card.dart:167`~~ | ~~Async work in `.then()` callback; rename/delete errors silently dropped in release~~ | **Fixed 2026-05-24** |
| ~~LOW~~ | ~~`splash_screen.dart:131`~~ | ~~Version string hardcoded; should read from `packageInfoProvider`~~ | **Fixed — reads `ref.watch(packageInfoProvider).valueOrNull?.version ?? '—'`** |

---

## Testing notes

- **Unit tests** use `_FakeRepo` — an in-memory `FanRepository` — to avoid the ObjectBox native library
- **Widget tests** mock `BleService` and `FanRepository` with mocktail; `CommandLoader.load()` must be called in `setUpAll`
- `StreamProvider` in widget tests needs **4 pump cycles** to deliver a connection state change: `pump()` ×2, add stream event, `pump()` ×2
- `CircularSpeedDial` stacks 6 `GestureDetector`s at the same centre — `tester.tap()` is intercepted by the overlaid Column; invoke `dial.onSpeedSelected(n)` directly
- `LightingControlWidget` and the boost button sit below the 600 px test viewport — obtain the widget with `tester.widget<...>(find.byType(...))` and call its callback directly
- `_BoostButton` is a `StatefulWidget` (owns `_shimmerCtrl`); find it via `ValueKey('boost_button')` on its outer `GestureDetector`
- Power-gate: `controlsEnabled = enabled && fanState.isPowered` — tests that check dial or boost state must emit a power-on BLE response frame first
