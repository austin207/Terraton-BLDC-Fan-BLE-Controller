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
**Motor State poll:** non-standard fixed frame `[55 AA 00 01 01 00 01]` (`get_motor_state`) — do NOT pass through `buildFrame()`. A vendor-checksum-formula sibling frame also exists: `[55 AA 00 01 01 00 02]` (`get_motor_state_vendor`) — unverified against lab firmware (the lab fan only answers the `…01` variant); it's polled because Terraton's protocol doc computes a different checksum for this frame, and a checksum-validating field firmware could silently drop whichever variant it disagrees with. Response: normally 3 frames — [1] `0x02` power, [2] `0x04` speed OR `0x21` active mode (mutually exclusive), [3] `0x22` timer — but reply assembly is shape-tolerant: a reply with no `0x22` frame is still a valid state reply (it matches the vendor doc's own Status Check, cmd `0x00`, whose documented reply shape carries no timer field at all). ⚠️ **Frame [2] is NOT exclusive truth on field firmware** (corrected 2026-07-30 from captures; **cause established from firmware source 2026-08-01**). `get_mc_state()` builds frame [2] from a four-branch chain, first match wins: `direction` → `21 01 03` REVERSE; else `IRControl.NatureFlage` → `21 01 02` NATURE; else `mcFRState.OldTargetSpeed == 7` → `21 01 01` BOOST; **else** the raw speed `04 01 NN`. **Smart has no branch at all** — `case BOOST: SMART_MODE` does `smart_mode = 1; SpeedCnt = 6; SetSpeed(6)`, and 6 ≠ 7, so the else fires and a fan in Smart is reported as `04 01 06` forever. This is a **Smart-specific omission, NOT a general "modes are lost at speed 6"**: Nature and Boost have their own branches and report correctly at every speed (Boost *is* speed 7 internally, which is why it is detected by `OldTargetSpeed == 7` rather than a flag). Evidence for the behaviour — `test/unit/field_capture_2026_07_04_test.dart`: the user taps Smart at speed 5, the firmware raises the fan to 6 itself, and then every state reply says `04 01 06` and never `21 01 04`, while the app sends no speed command at all. Applying the old exclusivity rule is what deleted Nature/Smart/Boost on every reconnect (fixed in `f30d9f1`). A mode is now cleared **only** by an explicit `0x21` reporting a different mode, a trusted `power == false`, or the user's own action. A frame [2] carrying a **mode** is still applied exclusively (`applyMotorStateTruth`). The trade-off is **narrower than first documented**: `case SPEED` clears `boost_flag` but never `IRControl.NatureFlage`, so a speed command does not exit Nature in firmware either — the fan keeps reporting `21 01 02`, and the app keeping its highlight matches firmware truth. A genuinely stale highlight is therefore confined to Smart (never reported) and to whatever the IR path clears without telling us. Escalated to Terraton: add a `smart_mode` branch, and report mode and speed in the same reply. The app assembles frames atomically rather than assuming they arrive in one notification; see "Machine-State retrieval on reconnect — MachineStateSync" below.
**Firmware ground truth (from Terraton's `Process_Response()` / `get_mc_state()` source, received 2026-08-01).** These are read from the MCU source, not inferred from captures, and outrank any capture-derived guess in this file:
- **`0x21` REVERSE is a toggle, not a set:** `direction ^= 0x01`. The echo is always `21 01 03` regardless of which direction resulted, so the reply never says which way the fan now spins. A duplicated or retried reverse write flips twice and looks like "Reverse did nothing" — this is the mechanism behind the intermittent-Reverse reports, together with the unpaced double write (`WriteQueue`, S10).
- **`direction` masks everything else** (first branch of the chain above), so a reversed fan **never reports its speed, Nature, or Boost**. The app cannot learn speed while in reverse — do not treat a missing speed there as a defect.
- **Power-OFF does not clear `direction`.** It resets `mcFRState.FR/FlagFR/FRStatus` but leaves `direction` set, so a state reply can claim `21 01 03` on a fan the firmware just forced forward.
- **Setting any sleep timer clears Smart:** `case TIMER` does `smart_mode = 0` for codes 2/4/8 (**not** for code 0). A user setting a timer while in Smart silently leaves Smart — a firmware feature conflict, not an app bug. The app is the only witness: `get_mc_state()` never reports Smart either way, so the highlight can only be cleared by the app at the moment it sends a nonzero timer code.
- **Nature cannot be exited over BLE at all.** In the supplied source `IRControl.NatureFlage` is set by `case BOOST`/`NATURE` and cleared *only* by `case POWER` (both branches). `case SPEED` clears `boost_flag` and nothing else. So the app's "tap Nature again to exit" (which sends a bare speed frame) does not exit Nature in firmware: the fan keeps modulating, keeps reporting `21 01 02`, and the next state reply re-lights the highlight the tap just cleared. Only a power cycle exits. Escalated; do not paper over it app-side.
- **The trailing `send_response()` is load-bearing, not a bug.** `Process_Response()` ends with an unconditional `calculate_crc(); send_response(); MotorStatusSave();`, and `get_mc_state()` depends on it: that function sends frames [1] and [2] itself, then *builds* the `0x22` timer frame and returns without sending, leaving the trailing block to emit it. `case HEARTBEAT` is almost certainly symmetric — `send_status()` emits watts and leaves RPM for the trailing send — which is what produces the hardware-verified **2** frames per status poll. ⚠️ A 2026-08-01 revision of this file claimed the trailing send re-emits a *stale* frame once per poll; that was inference, not source, and the 2-frame count contradicts it (a stale extra frame would make it 3). The agreement rule's real justification is the BLE60 backlog flush, which is capture-evidenced — do not weaken the rule, but do not cite this mechanism for it either. Unresolved without `send_status()` and `calculate_crc()`: the documented RPM checksum quirk (`0x24` is the only 2-byte payload).

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
| Get Motor State (vendor checksum) | `55 AA 00 01 01 00 02` — unverified on lab firmware; lab fan answers the `…01` variant only |
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

**Field-scoped persistence (`FanRepository` / `ActiveFanStateNotifier`).** `FanState` is written through four scoped read-modify-write methods on `FanRepository` — `saveOperatingState` (`isPowered`/`isBoost`/`speed`/`activeMode`), `saveTimerState` (`activeTimerCode`/`timerActivatedAt`), `saveTelemetry` (`lastWatts`/`lastRpm`/`lastRuntimeSecs`), `saveLighting` (`lastLightColorType`/`lastLightBrightness`/`lastLightIsOn`) — modeled on the pre-existing `saveOpenSegment` pattern. Every `ActiveFanStateNotifier` mutator (`lib/core/providers.dart`) persists through exactly one of these (`_persistOperating`/`_persistTimer`/`_persistTelemetry`/`_persistLighting`); there is no whole-row writer left in that path — the old `update()` + whole-row `saveState`-per-mutation funnel is gone, along with `_restorePending`, `_toPersist`, and `markRestored()`. Consequence: a telemetry or runtime write is now structurally **unable** to touch `isPowered`/`activeMode` — `updateRuntime()` calls `_persistTelemetry()`, which can only ever construct a write to the telemetry fields, so the 2026-07-17 field bug (a `queryRuntime` reply riding the same notification burst as a Machine-State reply wiped `isPowered`/`activeMode` from the DB microseconds before the old demotion guard read them) cannot recur. `resetOnConnect()` is pure in-memory display-blanking **by construction**: it assigns `state` directly and calls no persist method at all, so there is no leak window to guard and nothing analogous to the old `markRestored()` is needed.

### BLE service implementation notes (`lib/core/ble/ble_service.dart`)

- **Every write is serialised and paced through `WriteQueue`** (`lib/core/ble/write_queue.dart`, wired in 2026-08-07). `writeFrame()` only enqueues; `_writeFrameNow()` performs the write, logs `TX`, and appends the BLE60's `\r\n`. The queue is `reset()` wherever `_writeChar` is nulled. **Why:** the BLE60 flushes to the MCU UART only on `\r\n` and the MCU parses one `request_frame` at a time, so two writes issued in one connection interval cost the second frame. Every control path that sends more than one frame per tap was affected — most visibly Reverse→Nature/Smart (`_onMode`), which must send exit-reverse *then* the mode because firmware's NATURE/SMART branches never clear `direction` and `get_mc_state()` tests `direction` first. In the field the exit-reverse frame landed, the mode frame did not, and the fan just returned to its previous speed with no mode set — the "first tap does nothing" report. Same mechanism as the ~400 µs dropped speed frame in `test/unit/field_capture_2026_07_04_test.dart`.
- **`retries: 0` on that queue is load-bearing — do not enable retries.** Firmware Reverse is `direction ^= 0x01`, a *toggle*, and writes go out `writeWithoutResponse`, so a throw is not proof the frame missed the wire. Re-sending a Reverse frame that did land flips the fan back — the "Reverse is intermittent" report. Pacing is the fix; retry is not safe for this command set. `_writeGap` (60 ms) is a named constant in `ble_service.dart`: **raise it first** if a multi-frame action still fails on hardware.
- `writeFrame` copies `_writeChar` to a local variable before the null check (eliminates TOCTOU race).
- On connection failure, `_connStateSub` is cancelled before retry so a stale listener cannot spawn concurrent retry chains.
- `startScan` clears `_discovered` and `_scanCache` on every call — scan results briefly empty when user hits Refresh.
- **Do NOT call `startScan()` before `connect()`** — it clears `_scanCache`, destroying the live `BluetoothDevice` that carries the correct BLE address type. Control screen calls `_ble.connect(mac)` directly without scanning first.
- The BLE60 uses a random BLE address. `BluetoothDevice.fromId(mac)` guesses public type. Always use the live device from `_scanCache` on first connection; `fromId()` is fine for reconnects after Android has cached the address type.
- `disconnect()` cancels `_notifyValueSub` (in addition to `_connStateSub`) before tearing down the GATT link — without this, the previous session's listener survives into the next `connect()` and can deliver the BLE60's backlog flush into the new session's stream.
- On `connect()`, any prior `_notifyValueSub` is cancelled and the new listener is attached to `onValueReceived` **before** `setNotifyValue(true)` is called — `setNotifyValue(true)` is what triggers the BLE60 to flush the UART backlog it buffered while no phone was connected, so the listener must already be in place and no stale listener may still be attached, or the flush can race `_rxAssembler.reset()` or land on a dead subscription entirely.

### Commands YAML (`assets/commands.yaml`)

Single source of truth for all BLE command bytes. Adding a new command requires only a YAML edit — no Dart changes.

`CommandLoader._safeGet()` returns `null` gracefully for missing keys; `BleFrameBuilder` propagates `null`; `ControlScreen._send()` shows a SnackBar instead of crashing. Lighting commands are currently `null` — pending bytes from Terraton.

`get_motor_state_vendor` (`…00 02`) is the vendor-checksum-formula sibling of `get_motor_state` (`…00 01`) — see the Motor State poll bullet above and the MachineStateSync section for why the app polls both. `CommandLoader.getMotorStateVendor()` falls back to `getMotorState()` (the lab-verified `…01` frame) when the `get_motor_state_vendor` key is missing from a stale/cached `commands.yaml`, so `MachineStateSync`'s alternating poll never sends a malformed frame even against an older asset bundle.

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
- `applyMotorStateTruth` (the Machine State frame [2] path) is fully exclusive by construction — but it is now reached **only for a mode-bearing frame [2]**. A speed-bearing frame [2] no longer calls it at all (see the ⚠️ note under "Motor State poll"), so `applyMotorStateTruth(null)` is dead in production. Mutual exclusivity among modes is unchanged; what changed is that a reported *speed* is no longer treated as proof that no mode is active.

### Machine-State retrieval on reconnect — MachineStateSync (`lib/core/ble/machine_state_sync.dart`)

A getMotorState reply is always power + frame [2] (speed OR mode) + optionally a `0x22` timer code, but the BLE60 chunks the MCU's UART stream into notifications at arbitrary byte boundaries (see "Notification chunking" above — `FrameStreamAssembler` recovers mid-frame splits at the byte level before any of this logic runs) and can flush a stale UART backlog it buffered while no phone was connected into a fresh connection, with valid checksums. The old design's answer to this was a "confirm-before-demote" guard that trusted an assembled reply only when it didn't demote the ObjectBox-persisted last-known-good state — six consecutive attempts to make that guard hold failed in the field: a slow/interleaved reply corrupting the restore even after frame reassembly (2026-07-03), a stale reply that wiped Smart + the sleep timer and persisted the wipe within ~1 s of reconnecting because every trust decision read a DB baseline any unrelated write could poison (2026-07-04), a `queryRuntime` reply riding the same notification burst as the Machine-State reply and poisoning that exact baseline on every single connect (2026-07-17), and finally the 3.0.26 report that the bug was still happening — traced to the guard's own 3 s timeout fallback applying the unconfirmed held reply it was supposed to be protecting against.

`MachineStateSync` replaces the entire mechanism — not another patch to it — with one pure-Dart, dependency-free class (no Flutter/Riverpod/ObjectBox imports), fully unit-tested in `test/unit/machine_state_sync_test.dart` under a fake clock. It owns three things the widget used to interleave across a dozen fields: **tuple assembly** (absorbing the old `_msPower`/`_msSpeed`/`_msMode`/`_msTimer` buffer and its 300 ms debounce for a reply split across notifications), **session polling** (absorbing `_scheduleConnectPolls`/`_scheduleWakePolls`/`_awaitingMotorState` and its 3500 ms safety-net timeout), and **the trust decision** (replacing `_isStateDemotion`, the demotion-hold/same-burst/3 s-fallback machinery, and the ObjectBox baseline read entirely). `control_screen.dart` only classifies parsed frames into `SyncFrame`s (`_subscribeNotify`) and renders whatever tuple the engine emits, via `_applyMachineState`.

**Sessions vs. single polls.** `_sync.startSession(reason)` starts a connect/wake sync session: on `_connect()` (`'connect'`), on a spontaneous remote power-ON while the app thought the fan was off (`'remote wake'`, from `_dispatchLive`), and after `_powerOnWithRestore()` (`'post power-on restore'`). `_sync.requestOnce(reason)` fires one atomic single poll that applies on its first valid assembled reply, no agreement needed (backlog risk is a connect-time phenomenon) — the 90 s Smart/Nature/Reverse poll (`_updateMotorStatePoll`), the sleep-timer-expiry check, and the live-path's "status-poll stored-speed vs. active mode" disambiguation; it is a no-op while a session is already running. Any explicit user command routed through `_send` calls `_sync.cancel('user command…')` first — user intent always outranks an in-flight sync — and `didChangeAppLifecycleState(paused)` cancels too (`_sync.cancel('app paused')`).

**The agreement rule (CRITICAL, replaces confirm-before-demote).** During a session, a state applies ONLY when two consecutively assembled replies agree on `(power, frame[2])` — the timer code is compared only when BOTH replies carry one, so a reply with no `0x22` frame is neutral and can never clear a countdown on its own — AND the confirming reply's `querySeq` is strictly greater than the candidate's. Every tuple is stamped with the engine's monotonic query counter as of the arrival of its bytes; `noteExternalStateQuery()` bumps that counter for state queries sent outside the engine (the 3 s status poll — newer field firmware may report state in every status reply per the vendor doc, see below). Consequence: a BLE60 backlog flush, however many stale replies it contains, arrives as one burst stamped with the same `querySeq` and can therefore **never confirm itself** — no decision ever reads the ObjectBox baseline, so the entire "poisoned baseline disables the guard" failure class that killed all six previous fixes is structurally gone, not patched again.

**Unconfirmed is NEVER applied.** A session that reaches its poll cap (`maxSessionPolls = 6`, ~1.5 s apart) or its hard timeout (`sessionTimeout = 12 s`) with no agreement applies NOTHING — the UI stays blank/unknown and the 90 s poll retries later. **Never reintroduce a timeout fallback that applies a held/unconfirmed reply** — the old 3 s demotion fallback doing exactly that is the most plausible cause of the 3.0.26 field failure it was meant to prevent.

**Tuple validity.** A bare power-ON reply with no frame [2] is discarded (the MCU is still booting after a mains cycle) and polling continues; an OFF-only reply (no frame [2], no timer) is a valid tuple; a power-less fragment (frame [2]/timer with no power byte — a torn backlog fragment) is discarded outright and never applicable on its own. A telemetry-bearing chunk with no `0x22` (`chunkHasTelemetry` — e.g. the firmware's **4-frame post-mains-restore status quirk** `0x02 0x04 0x23 0x24`, power frame present but no timer) is status-shaped: it never tears a reply still being assembled, and never nulls an already-buffered mode with its stored-speed `0x04` frame — on the live steady-state path this same quirk routes through `_sync.requestOnce('status-poll stored-speed vs active mode')` instead of clearing an active mode/boost highlight outright. A second power frame arriving in a NON-status chunk finalizes the current partial reply — this is what splits two concatenated backlog replies apart instead of merging them into one garbage tuple.

**Dual-checksum polling.** Session polls alternate the lab-verified Get Motor State frame (`get_motor_state`, `…00 01`) with the vendor-formula variant (`get_motor_state_vendor`, `…00 02`) because Terraton's protocol doc computes a different checksum for this frame than the one hardware-verified against the lab fan, and a checksum-validating newer firmware could silently drop whichever variant it disagrees with; duplicate answers from firmware that accepts both are harmless under the agreement rule (they simply agree with each other). This is also why assembly is shape-tolerant: the vendor doc documents Status Check (cmd `0x00`) — not the lab-observed Get Motor State (cmd `0x01`, which appears nowhere in the vendor doc) — as its state-retrieval mechanism, with a reply carrying ON/OFF status, fan mode/running status, power, and speed, and explicitly **no timer field**. A reply is therefore a valid state candidate with or without a `0x22` frame.

**Steady state (engine idle).** `_dispatchLive` applies frames directly: a chunk shaped like a full reply (power + `0x22` timer) applies atomically via `_applyMachineState`, so a stored-speed frame can't re-light a fan its own power frame just reported OFF; a genuine remote-initiated OFF applies instantly (an improvement over the old confirm-before-demote path's ≤3 s delay), with full OFF semantics — no speed/mode/countdown survives an OFF; a spontaneous ON while the app thought the fan was off starts a wake session so the dial fills with confirmed state instead of an optimistic guess.

**Trade-off.** Every connect now costs one extra poll round-trip (~200–300 ms) before state renders, versus applying the first reply optimistically — accepted deliberately: firmware is display truth, and the UI stays blank until retrieval succeeds rather than showing a value that might be wrong.

**Log-replay harness.** `test/helpers/connection_log_replay.dart` (`replayConnectionLog(String capture) → ReplayResult{applied, logs, polls}`) parses the `RX`/`TX` lines of a tester's Connection Log capture and replays them through the assembler + frame classification + `MachineStateSync`, byte-for-byte. When a field capture arrives, paste it into a test as a permanent regression of that firmware's exact stream.

**Persistence.** State the engine releases is written through `FanRepository`'s field-scoped writers, not a whole-row persist — see "Field-scoped persistence" in the Storage section below; that's what makes `resetOnConnect()`'s display blank unable to leak into ObjectBox regardless of what races it during a session.

`ConnectionLogService` (`lib/core/diagnostics/connection_log_service.dart`) records timestamped events; Settings → Connection Log views/shares/clears it, so a field tester can capture exactly what the fan reported around a reconnect. Line kinds:

| Kind | Hooked in | Meaning |
| --- | --- | --- |
| `TX` / `RX` | `BleServiceImpl` | frame written / raw notification bytes **pre-reassembly** |
| `FRM` | `_subscribeNotify` | frames `FrameStreamAssembler` produced, as `cmd=data`. **Read against the `RX` line above it** — a frame present in RX but absent here was dropped by reassembly; the raw bytes alone can't show that |
| `MS` | `MachineStateSync` (via its `log` callback) | one line per sync-engine event: session start, each assembled reply (`reply{…}`) and its decision — `candidate` (first reply, never applied alone), `agrees with candidate{…} => applied`, `matches candidate{…} but no query boundary (same backlog burst) => candidate refreshed`, `contradicts candidate{…} => candidate replaced` — a discarded fragment/bare-ON, `session expired — nothing applied`, or a cancel reason (`user command…`, `app paused`) |
| `EV` | `BleServiceImpl`, `_connect`, lifecycle | connect/disconnect, `app paused`/`app resumed`, and the restore baseline at connect |

`FRM` + `MS` exist because raw frame hex cannot distinguish **"the reply never arrived"** from **"the reply arrived and the engine is holding it pending agreement"** — that ambiguity is why several fix attempts on the old design failed to converge. **The lab fan runs older firmware than field units**, so the frame tables above are only verified against lab firmware; when a field bug contradicts them, trust a tester's capture over this document.

⚠️ `handoff.md` (untracked, repo root) is **stale** — it documents v3.0.19 / `9be06f0` and predates `FrameStreamAssembler`, `ConnectionLogService`, and `MachineStateSync`. Do not use it as a reference; this file is current.

### Power-on memory restore (`control_screen.dart`)

The firmware stores its last operating state (EEPROM, `MotorStatusSave()`) and restores part of it on power-ON. ⚠️ **Corrected 2026-08-01 from firmware source** — this section previously claimed a bare BLE powerOn (`0x02 0x01`) triggers no restore at all. It does: `case POWER` with data `1` sets `IRControl.TargetSpeed = mcFRState.OldTargetSpeed`, so the **speed comes back by itself**. What it explicitly wipes in the same branch is the mode — `NatureWinFlag = 0; IRControl.NatureFlage = 0; smart_mode = 0`, with `boost_flag` re-derived solely from `OldTargetSpeed == 7`. Consequence for `_powerOnWithRestore()`: re-sending the stored **speed** is redundant but harmless (it agrees with what the firmware already did), while re-sending the stored **mode** is the part that actually matters, because the firmware just cleared it. ⚠️ **With one exception that is an active bug: `reverse` must never be restored.** `case POWER` does *not* clear `direction`, so a fan switched off while reversed still has `direction == 1` and its OFF state reply reports `21 01 03`; that lands in `_offStateMode`, and `_powerOnWithRestore()` (`control_screen.dart:622`) re-sends `setReverse()` — which is `direction ^= 0x01` and therefore flips the fan **forward** while the app optimistically highlights Reverse. Boost/Nature/Smart are absolute writes and restore correctly; Reverse is the only toggle in the set. `_ensurePoweredOn()`'s rule — restore a speed, never a mode — is unaffected and still correct. The app captures the memory the same way: frame [2] of a power-OFF Machine-State reply carries the firmware's stored last speed/mode (the "stale last value"); it is captured into `_offStateSpeed`/`_offStateMode` (never shown while OFF — the dial stays unlit) and re-sent by `_powerOnWithRestore()` when the user taps Power ON, followed by a `MachineStateSync` session (`_sync.startSession('post power-on restore')`) to confirm against firmware truth. `_ensurePoweredOn()` (auto power-on when tapping any control while off) restores only a **speed** memory, never a mode — a restored mode (e.g. Nature) would swallow the user's own command (hardware ignores speed while Nature is active). Captured memory is cleared whenever a powered Machine-State reply arrives.

### Sleep-timer countdown (`control_screen.dart` + `providers.dart`)

In practice the fan reports `22 01 00` for any BLE-set timer regardless of what is running (see the timer-policy paragraph below for why — it is a firmware flag bug, not a design limit), so the countdown start timestamp has to be app-side (`FanState.timerActivatedAt`, persisted). `_TimerCountdown` ticks at 1 Hz and renders `Xh Ym Zs REMAINING`. `updateTimer` resolves the start time as: explicit (user tap) → current state (same code) → `DateTime.now()` (count down from detection — used for timers set from the IR remote while disconnected; an upper bound by design). `resetOnConnect()` **never touches the timer fields and never persists anything** (see "Field-scoped persistence" in the Storage section — it assigns `state` directly, in-memory only): the countdown keeps ticking through every disconnect — background, Bluetooth off, even a full app kill (the fresh notifier's `build()` reloads it from ObjectBox) — and the next Machine-State reply then confirms it (same code keeps the start time via the current-state rule) or corrects it (OFF reply → `updateTimer(0)` clears; different **nonzero** code → fresh start; a reported code of **0 while powered is NEUTRAL** — see the timer-policy paragraph below). A start time implying the timer already expired is discarded (firmware says ACTIVE, so it's wrong). Do NOT reintroduce a timer clear or an ObjectBox write in `resetOnConnect` — persisting the blank destroys the start timestamp whenever the restore is interrupted (this was the 2026-07-03 "timer shows OFF after reconnect" field bug). `_syncTimerExpirySchedule` (a `ref.listen` in `_ControlScreenState.build`) fires `_sync.requestOnce('sleep-timer expiry check')` ~2 s after expected expiry, then `requestOnce('sleep-timer expiry retry')` 10 s later if the fan still shows powered with a timer code — because the firmware's timer-driven shutdown is never pushed; status polls carry only watts/RPM. An OFF reply force-clears the timer chip (`updateTimer(0)`) only once `MachineStateSync` actually releases it: during a session that means the two-reply agreement rule (see MachineStateSync above) — a single OFF or timer-code-0 reply while the persisted timer is still unexpired is just a candidate until a second, later-`querySeq` reply confirms it; on the live steady-state path (engine idle) a genuine OFF applies immediately, since backlog risk only exists at connect time. A reply with no `0x22` frame at all is timer-**neutral** and never clears the countdown (matches the vendor doc's status reply, which carries no timer field). An expired-while-disconnected timer shows `0s REMAINING` for ≤~2 s on reconnect until the confirming reply lands (deliberately no widget-side self-clear). While the app is backgrounded the countdown is also visible as an ongoing notification, rendered by Android with **no BLE and no Dart timer** — see "Ongoing notification" under App lifecycle. The fan performs its own shutdown at T-0 (hardware-confirmed; only the *reporting* is broken, per the timer-policy paragraph below), so the app never enforces the power-off.

**Timer policy — a state reply's code `0` is NEUTRAL, not a cancellation** (`lib/core/ble/machine_state_timer_policy.dart`, added 2026-07-30 in `aebfe6f`). ⚠️ **Cause corrected 2026-08-01 from firmware source.** This was previously recorded as an accepted hardware limit ("the fan only reports timer on/off"). It is not a limit — it is a **wrong-flag bug**. `case TIMER` calls `SetAutoPower(720/1440/2880)` but **never sets `IRControl.FlagAutoPower`**; it only ever *clears* that flag, in the `request_frame[5] == 0` branch. `get_mc_state()` gates the timer frame on exactly that flag, so a timer set over BLE reports `22 01 00` for its entire life. When the flag *is* set (the IR-remote path), the field carries `AutoPowerState.ShutDowntime / 360` — i.e. **remaining whole hours**, since 720 units = 2 h ⇒ 10 s per unit. The fan is already capable of a live countdown; it is reading the wrong variable. Evidence in `test/unit/field_capture_2026_07_04_test.dart` is consistent to the byte: the `22 01 04` seen on the wire is `case TIMER`'s echo of `request_frame[5]` (a pure echo, not a state read), while **every** Get Motor State reply says `22 01 00`, and the capture contains no timer-off command — the user never cancelled.

**If Terraton fixes the flag, the app needs a decision first.** A 4 h timer will then report `4 → 3 → 2 → 1 → 0`, and `parseTimer` whitelists only `{0x00, 0x02, 0x04, 0x08}`, so codes 3 and 1 would be dropped. Do **not** widen that set reflexively: `parseTimer != null` is what classifies a burst as a Machine-State reply, so a wider whitelist lets a junk `0x22` byte reroute a whole response set (the reason the range check exists). The neutral-zero rule below stays correct either way — under a fixed firmware the final hour still reports `0`, which must not read as a cancellation. Because `parseTimer` whitelists `0x00`, that became `timer: 0` and `updateTimer(0)` nulled both `activeTimerCode` and `timerActivatedAt` **and persisted the clear**, destroying the countdown on every reconnect (the "timer doesn't show the countdown after reopening" field report). The rule is one pure, import-free function so it cannot couple to storage:

```dart
int? timerFromStateReply({required bool power, required int? replyTimer}) {
  if (!power) return 0;                                   // an OFF fan has no countdown
  if (replyTimer == null || replyTimer == 0) return null;  // neutral — no change
  return replyTimer;
}
```

Both timer writes in `_applyMachineState` funnel through it. **Surviving clear paths:** a trusted `power == false`; the user tapping Timer OFF (optimistic, unchanged); and a **lone** `0x22` frame on the live path — a genuine spontaneous IR-remote broadcast, including a remote cancellation while connected. That last split is structural, not a special case: `_dispatchLive`'s atomic pre-branch already routes any chunk carrying power **and** timer into `_applyMachineState`, so only a standalone `0x22` reaches the live timer branch. **Do NOT "fix" `_dispatchLive`'s timer branch for consistency, and do NOT remove `0x00` from `parseTimer`'s whitelist** — the remote-cancel path depends on both. Excluded deliberately: an expiry self-heal for a timer cancelled from the remote *while disconnected*, since deciding that requires reading the persisted `timerActivatedAt` — exactly the trust-decision-reads-storage coupling that killed six earlier fixes. Residual cost is a phantom chip bounded by ≤8 h, cleared by the next OFF reply or user tap.

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
- **`paused`** (screen off OR app backgrounded — home button, app switch): cancel the telemetry timer, `_refreshOngoingNotification(linkReleased: true)`, then `_ble.disconnect()`. Releasing the single GATT connection frees the fan for another phone. The notification is **no longer stopped unconditionally** — see "Ongoing notification" below; it stops only when there is no armed sleep timer, so it can't linger showing stale telemetry. `linkReleased: true` is required because `_ble.currentState` can still read `connected` while the pause-initiated disconnect is in flight.
- **`resumed`**: if `_ble.currentState != connected`, call `_connect()`. Because the BLE60 allows only one connection, `connect()` fails gracefully with an `'in use by another device'` status (GATT 133, see `ble_service.dart`) when another phone holds the fan — so resume **never steals** an active connection. The connect attempt *is* the "is another phone using it?" check; there is no separate probe (the fan stops advertising when connected elsewhere, and scan-before-connect is forbidden).
- `inactive` / `hidden` / `detached`: no-op.

Demo mode (`_isDemo`) skips all of the above. Observer is registered in `initState` and removed first thing in `dispose`.

### Ongoing notification (`_refreshOngoingNotification`, `control_screen.dart` + `TerraBgService.kt`)

One decision point owns the foreground-service notification; **never call `BleForegroundService` directly from a new site.** Two things justify a notification: live telemetry while the fan runs, and an armed sleep timer. **The timer outranks the connection** — the app deliberately drops BLE on pause, so the countdown must survive with nothing connected behind it. It is driven off the `ref.listen` on `activeFanStateProvider` in `_ControlScreenState.build`, which is also how a Timer tap in `_FanControlsPanel` (a different State object) arms it; `_ongoingNotifKey` de-dupes so the platform channel is only touched when the rendered content changes.

**The countdown is rendered by Android, not by Dart** — `setWhen(endAt).setUsesChronometer(true).setChronometerCountDown(true)` (API 24+; `minSdk` is 23, so 23 falls back to the static label). Nothing on the Dart side stays awake, so Doze, timer throttling and engine backgrounding are all irrelevant. **Do not replace this with a periodic `update()` from a Dart timer** — that is exactly the fragility the chronometer avoids. `TerraBgService` also posts a delayed swap to "Sleep timer finished" so the chronometer doesn't sit at 0:00; a late fire is harmless because the app re-confirms real state on resume.

The notification is started from the foreground (the Timer tap / a powered state reply), never first-started from inside the `paused` branch — that is what keeps it clear of the Android 12+ ban on starting a foreground service from the background. Scope limit: it is owned by `ControlScreen`, and `dispose()` still stops it, so the countdown lives while the control screen is alive (including backgrounded) — not after the user leaves the fan screen or kills the app. ⚠️ The manifest declares `foregroundServiceType="connectedDevice"` and this notification now outlives the BLE link; verify on Android 14+ that `startForeground()` still succeeds.

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
