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
**Motor State poll:** non-standard fixed frame `[55 AA 00 01 01 00 01]` — do NOT pass through `buildFrame()`. Response: 3 frames — [1] `0x02` power, [2] `0x04` speed OR `0x21` active mode (mutually exclusive), [3] `0x22` timer. Frame [2] is exclusive truth; clear all other mode/speed highlight state. The app assembles the 3 frames atomically rather than assuming they arrive in one notification; see "Machine State assembly on reconnect" below.
**Notification chunking (CRITICAL):** the BLE60 bridges the MCU's UART output into notifications cut at ARBITRARY byte boundaries — not frame boundaries. A multi-frame burst (e.g. the 3-frame Motor State reply + runtime frame on connect, ~29 bytes) is routinely split MID-frame across notifications. All notify bytes therefore go through `FrameStreamAssembler` (`ble_response_parser.dart`), which carries partial tail bytes across notifications and skips junk (BLE60 AT strings, `FF` padding, `\r\n`). Never parse a notification statelessly with `parseAll` in production code — a mid-frame split silently drops the frame (this was the root cause of Smart mode + sleep timer loss on reconnect, fixed 2026-07-03). The assembler is reset on every (re)connect and on `paused`.

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
- **Boost is mutually exclusive with ALL modes** (Nature, Smart, Reverse) — activating Boost clears any active mode highlight, and activating any mode clears Boost. This matches the firmware's Machine-State model where frame [2] reports exactly one active state. (Boost+Reverse coexistence existed briefly and was removed 2026-07-02 — an IR-remote Boost press must un-highlight Reverse in the app.)
- **Nature blocks Boost activation** (`setBoostActive(true)` is a no-op while Nature is active; the UI clears Nature first via `_onBoost`).
- `setActiveMode(null)` (e.g. Reverse toggle-off) never touches `isBoost`.
- `applyMotorStateTruth` (the Machine State frame [2] path) is fully exclusive by construction.

### Machine State assembly on reconnect (`control_screen.dart`)

A getMotorState reply is always 3 frames (power, speed-or-mode, timer), but the BLE60 chunks the MCU's UART stream into notifications at arbitrary byte boundaries, so the frames may land in separate notifications — and may be cut mid-frame (see "Notification chunking" above; `FrameStreamAssembler` recovers mid-frame splits at the byte level before any of this logic runs). Applying frames live as they arrive is unsafe: the speed/mode gate needs the power frame applied first, so a split reply could silently drop the restored speed.

Fix: every Machine-State reply — any response carrying a `0x22` timer frame, whether it answers a poll we sent (`_awaitingMotorState`) or arrives spontaneously — is routed to the buffer (`_msPower`/`_msSpeed`/`_msMode`/`_msTimer`) instead of applied live (the `_subscribeNotify` gate is `_awaitingMotorState || isMotorStateResponse`), then flushed atomically by `_flushMachineState()` — either immediately once complete (power + frame [2] + timer, for both ON and OFF replies), or after a 300 ms debounce (`_msFlushTimer`) if a later frame is still in flight. A power=ON reply with no speed/mode yet (MCU still booting) is treated as incomplete, so the existing retry loops (`_scheduleConnectPolls`, `_scheduleWakePolls`) keep polling until the real state arrives; an ON reply whose **timer** frame is still missing likewise does not stop the connect retry polls (`received` requires frame [2] AND the timer — a getMotorState reply always carries a `0x22` frame, so this only triggers if one was genuinely lost). Watts/RPM/runtime frames are applied live even during this window (status-poll telemetry interleaves with the connect burst). The 90 s Smart/Nature/Reverse poll (`_updateMotorStatePoll`) also routes through this path via `_requestMotorState()`.

**Confirm-before-demote (CRITICAL):** the CONTENT of a Machine-State reply to a poll we sent is not blindly trusted. The BLE60 buffers the MCU's UART output while no phone is connected and can flush that stale backlog (replies cut off mid-delivery by a disconnect, IR-remote broadcasts) into a new connection with valid checksums, and a just-woken MCU may answer the first poll with default state — one such stale reply used to wipe Smart + the sleep timer AND persist the wipe within ~1 s of reconnecting, then stop the retry polls (`received`/`_motorStateReceived`): the 2026-07-04 field bug that survived every transport-level fix. The guard therefore runs on **every** assembled Machine-State reply, on every path — not only replies to a poll we sent. (This universality is what finally closed the regression: the earlier fix armed the guard only while `_awaitingMotorState`, so a stale OFF landing on the live dispatch path *after* the awaiting window closed still wiped-and-persisted Smart + the timer, and persisting `isPowered=false` poisoned the ObjectBox baseline `_isStateDemotion` reads — silently disabling the guard on every later reconnect. Fixed 2026-07-04; the `_needsDemotionConfirm` armed-window flag was removed as redundant.) In `_flushMachineState`, a reply that DEMOTES the persisted last-known-good state (`_isStateDemotion`, baseline read from ObjectBox — NOT the blanked in-memory state) — power OFF while the DB says powered, plain speed while the DB has an active mode, timer code 0 while the DB has an unexpired timer — is held un-applied and the fan re-polled; the next assembled reply (past a 300 ms same-burst window for demoting frames) is applied unconditionally, and a 3 s fallback applies the held reply if no confirmation ever lands. An OFF reply after the persisted timer's expected expiry is EXPECTED truth and applies immediately, so the timer-shutdown path gains no latency; confirming/upgrading replies always apply on the first reply. A **bare** live power-off frame (a lone `0x02`=OFF with no `0x22`, so not a full Machine-State reply) is likewise demotion-gated: if the persisted baseline still holds an active mode or an unexpired timer it is re-polled (`_requestMotorState`) to confirm rather than persisting OFF; a plain powered fan (nothing to lose) powers off immediately. A trade-off: a genuine remote-initiated OFF that carries a full `0x22`-bearing Machine-State reply now reflects in the UI after the confirm round-trip (≤3 s) instead of instantly.

`ConnectionLogService` (`lib/core/diagnostics/connection_log_service.dart`) records timestamped events; Settings → Connection Log views/shares/clears it, so a field tester can capture exactly what the fan reported around a reconnect. Line kinds:

| Kind | Hooked in | Meaning |
| --- | --- | --- |
| `TX` / `RX` | `BleServiceImpl` | frame written / raw notification bytes **pre-reassembly** |
| `FRM` | `_subscribeNotify` | frames `FrameStreamAssembler` produced, as `cmd=data`. **Read against the `RX` line above it** — a frame present in RX but absent here was dropped by reassembly; the raw bytes alone can't show that |
| `MS` | `_flushMachineState` | assembled reply tuple + the persisted baseline + the outcome (`applied` / `HELD(demotes)+repoll` / `held(same-burst)` / `applied(confirm)`) |
| `EV` | `BleServiceImpl`, `_connect`, lifecycle | connect/disconnect, `app paused`/`app resumed`, and the restore baseline at connect |

`FRM` + `MS` exist because raw frame hex cannot distinguish **"the reply never arrived"** from **"the reply arrived and the guard held it"** — that ambiguity is why several fix attempts failed to converge. **The lab fan runs older firmware than field units**, so the frame tables above are only verified against lab firmware; when a field bug contradicts them, trust a tester's capture over this document.

⚠️ `handoff.md` (untracked, repo root) is **stale** — it documents v3.0.19 / `9be06f0` and predates `FrameStreamAssembler`, `ConnectionLogService`, and confirm-before-demote. Do not use it as a reference; this file is current.

Three further guards keep a slow or interleaved reply from corrupting the restore (root causes of the 2026-07-03 "Smart + timer lost on reconnect even after frame reassembly" field bug):
- `_markAwaitingMotorState`'s safety-net timeout is **3500 ms** — deliberately longer than the 1.5 s retry-poll period, so the flag stays continuously true through a retry burst and for 3.5 s after the final retry. A reply slower than one poll cycle (typical from a just-rebooted MCU or after a BT adapter cycle) is still buffered atomically instead of falling onto the reorder-vulnerable live path. Never shrink this below the poll period.
- The firmware's **4-frame post-mains-restore status poll** (`0x02 0x04 0x23 0x24` — power frame present, but no `0x22`) is NOT a mode exit: on the live path, a bare `0x04` accompanied by a `0x02` in the same response set does not clear an active mode/boost highlight; the app re-requests Machine State instead. In `_bufferMachineState`, a `0x04` riding a telemetry burst (watts/RPM in the same response set) does not null an already-buffered `_msMode`.
- `resetOnConnect()` blanks the UI **for display only** and never touches the timer fields — see the sleep-timer section. Skipping the ObjectBox write in `resetOnConnect` is NOT sufficient on its own: `update()` persists the whole `FanState` row, so the next write of any kind re-persists the blank. `resetOnConnect` therefore also arms `_restorePending`, and `ActiveFanStateNotifier._toPersist` merges the operating fields (`isPowered`/`activeMode`/`speed`/`isBoost`) from the stored row until the window closes. **This is what makes the demotion baseline trustworthy — without it the guard below is dead on arrival** (the 2026-07-17 field bug: a `queryRuntime` reply rides the same notification burst as the Machine-State reply, so `updateRuntime()` wiped `isPowered`/`activeMode` from the DB microseconds before `_isStateDemotion` read it, on every single connect). The window is closed by `markRestored()` — called from `_applyMachineState` (firmware truth that cleared the gate) and from `_send` (explicit user intent; the status/motor-state/runtime polls bypass `_send` and call `writeFrame` directly, so they cannot close it).

### Power-on memory restore (`control_screen.dart`)

The firmware stores its last operating state (EEPROM) and restores it when the **IR remote's** ON button is pressed — but a bare BLE powerOn (`0x02 0x01`) does NOT trigger that restore. The app compensates: frame [2] of a power-OFF Machine-State reply carries the firmware's stored last speed/mode (the "stale last value"); it is captured into `_offStateSpeed`/`_offStateMode` (never shown while OFF — the dial stays unlit) and re-sent by `_powerOnWithRestore()` when the user taps Power ON, followed by a `_scheduleWakePolls()` burst to confirm against firmware truth. `_ensurePoweredOn()` (auto power-on when tapping any control while off) restores only a **speed** memory, never a mode — a restored mode (e.g. Nature) would swallow the user's own command (hardware ignores speed while Nature is active). Captured memory is cleared whenever a powered Machine-State reply arrives.

### Sleep-timer countdown (`control_screen.dart` + `providers.dart`)

The fan reports only WHICH duration is active (`0x22` code: 2H/4H/8H), never remaining time, so the countdown start timestamp is app-side (`FanState.timerActivatedAt`, persisted). `_TimerCountdown` ticks at 1 Hz and renders `Xh Ym Zs REMAINING`. `updateTimer` resolves the start time as: explicit (user tap) → current state (same code) → `DateTime.now()` (count down from detection — used for timers set from the IR remote while disconnected; an upper bound by design). `resetOnConnect()` **never touches the timer fields and never persists its blank** (it sets `state` directly, in-memory only, instead of `update()`): the countdown keeps ticking through every disconnect — background, Bluetooth off, even a full app kill (the fresh notifier's `build()` reloads it from ObjectBox) — and the Machine-State reply then confirms it (same code keeps the start time via the current-state rule) or corrects it (OFF reply / code 0 → `updateTimer(0)` clears; different code → fresh start). A start time implying the timer already expired is discarded (firmware says ACTIVE, so it's wrong). Do NOT reintroduce a timer clear or an ObjectBox write in `resetOnConnect` — persisting the blank destroys the start timestamp whenever the restore is interrupted (this was the 2026-07-03 "timer shows OFF after reconnect" field bug). `_syncTimerExpirySchedule` (a `ref.listen` in `_ControlScreenState.build`) fires `_requestMotorState()` ~2 s after expected expiry (+ one 10 s retry) because the firmware's timer-driven shutdown is never pushed — status polls carry only watts/RPM. An OFF Machine-State reply force-clears the timer chip (`updateTimer(0)`) — but only after passing the confirm-before-demote gate (see the Machine State assembly section): a single OFF or timer-code-0 reply while the persisted timer is still unexpired is held and re-confirmed before it may clear anything. An expired-while-disconnected timer shows `0s REMAINING` for ≤~2 s on reconnect until the (immediately-applied, since expiry makes OFF expected) reply lands (deliberately no widget-side self-clear).

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
