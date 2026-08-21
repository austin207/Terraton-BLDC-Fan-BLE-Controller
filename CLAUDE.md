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
**Checksum (app side):** `(0x55 + 0xAA + packetId + cmd + dataLen + Σdata) & 0xFF`. The **firmware** computes it differently — see the checksum bullet below — and the two only agree for 1-byte payloads.
**Status poll:** non-standard fixed frame `[55 AA 00 00 01 00 00]` — do NOT pass through `buildFrame()`. Reply is **2** frames: `0x23` watts + `0x24` RPM.
**Motor State poll:** non-standard fixed frame `[55 AA 00 01 01 00 01]` (`get_motor_state`) — do NOT pass through `buildFrame()`. Reply is **4** frames: [1] `0x02` power, [2] `0x04` speed **OR** `0x21` active mode, [3] `0x22` timer, [4] a duplicate of [3]. Each is applied on its own as it arrives, so any subset is fine.
⚠️ The vendor sibling `[55 AA 00 01 01 00 02]` (`get_motor_state_vendor`) is **never sent** — the firmware rejects it outright. See the checksum bullet.

**Firmware ground truth — full source `IRScan.c` (1658 lines) received 2026-08-21.** Read from the MCU source; outranks every capture-derived guess in this file. A complete defect list with line numbers and suggested fixes lives in **`FW_bug.md`** at the repo root.
- **Frame [2] IS exclusive.** `get_mc_state()` (`:1264`) is one if/else chain: `direction` → `21 03`, else `NatureFlage` → `21 02`, else `smart_mode` → `21 04`, else `OldTargetSpeed == 7` → `21 01`, else → `04 0N`. A `0x04` in a *poll* reply provably means no mode is running, and the app can never learn the speed while a mode is on. ⚠️ Earlier revisions of this file claimed the opposite, citing the 2026-07-04 capture. That reading was wrong — see the Smart bullet.
- **Speed 7 IS Boost.** There is no separate boost flag on the wire: `OldTargetSpeed == 7` is what makes `get_mc_state()` answer `21 01 01`. A Boost exit must therefore send a speed of 1–6; power-ON would restore `OldTargetSpeed = 7` and re-enter Boost.
- **`SetSpeed()` (`:179`) clears `NatureFlage` and `NatureWinFlag`, but NOT `smart_mode`.** So a BLE speed frame **does** exit Nature (the old "Nature cannot be exited over BLE" claim was wrong), and **cannot** exit Smart. Every IR remote speed button clears `smart_mode` (`:592` etc.); `case SPEED` (`:1357`) does not. That asymmetry is the root cause of the Smart bug — `FW_bug.md` item 1, a one-line firmware fix.
- **Only power-ON clears `smart_mode`** (`case POWER` on-branch, `:1347`), and it does not stop a running fan — the same branch restores `TargetSpeed = OldTargetSpeed` (`:1344`). This is how the app exits Smart. It does **not** clear `direction`, so it cannot exit Reverse.
- **`0x21` REVERSE is a toggle, not a set:** `direction ^= 0x01` (`:1396`), and the echo is an unconditional `21 01 03` (`:1402`) whichever direction resulted. The reply never says which way the fan now spins, and a duplicated or retried write flips twice — the intermittent-Reverse report. This is why `WriteQueue` keeps `retries: 0`, and why the app exits Reverse with a **speed** frame (`case SPEED` clears `direction` at `:1361`), never by re-sending Reverse.
- **`direction` masks everything else** (first branch of the chain), so a reversed fan never reports its speed, Nature, or Boost. Do not treat a missing speed there as a defect.
- **Setting any sleep timer clears Smart:** `case TIMER` does `smart_mode = 0` for codes 2/4/8 (`:1424`/`:1428`/`:1432`), **not** for code 0. The app is the only witness — `get_mc_state()` never reports Smart either way — so the highlight is cleared by the app at the moment it sends a nonzero timer code.
- **This, not frame-[2] ambiguity, explains the 2026-07-04 capture.** Smart was tapped at 16:48:09 and confirmed (`RX 21 01 04`); a 2 h timer was set at 16:48:12; every later reply says `04 01 06`. `case TIMER` had silently cleared `smart_mode`, so the chain fell through to the speed branch. Nothing about frame [2] is ambiguous.
- **The sleep-timer flag IS set, then wiped one tick later.** `SetAutoPower()` (`:197`) sets `IRControl.FlagAutoPower = 1`; `AutoPowerControl()` (`:857`) runs every tick, copies it into `AutoPowerState` and clears it (`:864`). `get_mc_state()` (`:1292`) gates the timer field on the flag that was just cleared, so it answers `22 01 00` forever. ⚠️ Earlier revisions said `case TIMER` "never sets" the flag — wrong mechanism, same conclusion: the app still owns the countdown.
- **Checksum:** `calculate_crc()` (`:1455`) sums **only** `[2]+[3]+[5](+[6])` — it omits the `55 AA` header and the length byte. The difference from a whole-frame sum is `0x55+0xAA+dataLen`, which is `0x100` for 1-byte payloads (cancels exactly) and `0x101` for 2-byte payloads (off by exactly +1). That is the whole story behind the "RPM quirk": `0x24` RPM and `0x08` runtime are the only 2-byte responses, and `_checksumOk` now keys on `dataLen`, not on the command byte. Before that fix every runtime reply was silently discarded.
- **`check_crc()` (`:1462`) uses the same formula for requests**, which is why the app's own request checksums work at all (1-byte payloads cancel), and why `get_motor_state_vendor` is dead — see below.

**Notification chunking (CRITICAL):** the BLE60 bridges the MCU's UART output into notifications cut at ARBITRARY byte boundaries — not frame boundaries. A multi-frame burst (e.g. the 4-frame Motor State reply + runtime frame on connect, ~29 bytes) is routinely split MID-frame across notifications. All notify bytes therefore go through `FrameStreamAssembler` (`ble_response_parser.dart`), which carries partial tail bytes across notifications and skips junk (BLE60 AT strings, `FF` padding, `\r\n`). Never parse a notification statelessly with `parseAll` in production code — a mid-frame split silently drops the frame (this was the root cause of Smart mode + sleep timer loss on reconnect, fixed 2026-07-03). The assembler is reset on every (re)connect and on `paused`.

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
| Boost (speed 7) | `55 AA 06 21 01 01 28` |
| Nature | `55 AA 06 21 01 02 29` |
| Reverse | `55 AA 06 21 01 03 2A` |
| Smart | `55 AA 06 21 01 04 2B` |
| Timer OFF/2H/4H/8H | `55 AA 06 22 01 00/02/04/08 28/2A/2C/30` |
| Query Power (watts) | `55 AA 06 23 01 00 29` |
| Query Speed (RPM) | `55 AA 06 24 01 00 2A` |
| Get Motor State | `55 AA 00 01 01 00 01` |
| Get Motor State (vendor checksum) | `55 AA 00 01 01 00 02` — **rejected by firmware `check_crc()`; never sent** |
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

**Field-scoped persistence (`FanRepository` / `ActiveFanStateNotifier`).** `FanState` is written through four scoped read-modify-write methods on `FanRepository` — `saveOperatingState` (`isPowered`/`isBoost`/`speed`/`activeMode`), `saveTimerState` (`activeTimerCode`/`timerActivatedAt`), `saveTelemetry` (`lastWatts`/`lastRpm`/`lastRuntimeSecs`), `saveLighting` (`lastLightColorType`/`lastLightBrightness`/`lastLightIsOn`) — modeled on the pre-existing `saveOpenSegment` pattern. Every `ActiveFanStateNotifier` mutator (`lib/core/providers.dart`) persists through exactly one of these (`_persistOperating`/`_persistTimer`/`_persistTelemetry`/`_persistLighting`); there is no whole-row writer left in that path — the old `update()` + whole-row `saveState`-per-mutation funnel is gone, along with `_restorePending`, `_toPersist`, and `markRestored()`. Consequence: a telemetry or runtime write is now structurally **unable** to touch `isPowered`/`activeMode` — `updateRuntime()` calls `_persistTelemetry()`, which can only ever construct a write to the telemetry fields, so the 2026-07-17 field bug (a `queryRuntime` reply riding the same notification burst as a Machine-State reply wiped `isPowered`/`activeMode` from the DB microseconds before the old demotion guard read them) cannot recur. `resetTelemetryOnConnect()` is pure in-memory display-blanking **by construction**: it assigns `state` directly and calls no persist method at all, so there is no leak window to guard.

### BLE service implementation notes (`lib/core/ble/ble_service.dart`)

- **Every write is serialised and paced through `WriteQueue`** (`lib/core/ble/write_queue.dart`, wired in 2026-08-07). `writeFrame()` only enqueues; `_writeFrameNow()` performs the write, logs `TX`, and appends the BLE60's `\r\n`. The queue is `reset()` wherever `_writeChar` is nulled. **Why:** the BLE60 flushes to the MCU UART only on `\r\n` and the MCU parses one `request_frame` at a time (`read_request()`, `IRScan.c:1483`), so two writes issued in one connection interval cost the second frame. Since the dumb-remote rewrite every *tap* sends exactly one frame, so the case that now depends on this is the **3 s poll**, which enqueues `statusPoll()` and Get Motor State in one synchronous turn. Unpaced, the fan would answer only the first and the display would never update.
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

`get_motor_state_vendor` (`…00 02`) is the vendor-doc checksum sibling of `get_motor_state` (`…00 01`). **It is never sent.** `check_crc()` sums `request_frame[2]+[3]+[5]` only, giving `0x00+0x01+0x00 = 0x01`, so the `…02` frame fails validation, `read_request()` never sets `recv_flag`, and `Process_Response()` is never called. The poll used to alternate the two variants, which meant every second tick got no reply and the display effectively updated every 6 s. The key is kept in `commands.yaml` for reference only.

**To add a new command:** add it to `commands.yaml`, then call `CommandLoader.custom(['commands', 'your_section', 'action'], [0xXX])` or add a named method to `BleFrameBuilder`.

**Phase 2 (approved, not yet built):** Remote command loading — fetch `commands.yaml` from a hosted URL on launch, compare `version` field, update local cache if newer, fall back to bundled asset on failure.

### The control screen is a dumb remote (rewritten 2026-08-16)

**The whole contract, in two sentences.** A button press sends that button's hex
frame and does nothing else — no local state write, no injected power-on, no
send-sequencing. A single 3 s poll asks the fan what it is doing, and every frame
that comes back is applied directly to its own field. The spec lives in
`test/widget/dumb_remote_contract_test.dart` as four tables (button→bytes,
button→no local change, frame→one field, poll cadence); read that first.

This replaced `MachineStateSync` and everything around it. That engine — plus the
six "confirm-before-demote" fixes before it — existed to decide *whether to
believe* a reply, because the BLE60 replays a stale UART backlog into every fresh
connection with valid checksums. A 3 s repeating poll answers that differently: a
wrong value is corrected on the next tick, so nothing needs to be judged. Deleted
outright: `lib/core/ble/machine_state_sync.dart`,
`lib/core/ble/machine_state_timer_policy.dart` (its one rule survives inlined —
see the timer section), `_dispatchLive`, `_applyMachineState`,
`_powerOnWithRestore`, `_ensurePoweredOn`, `_syncTimerExpirySchedule`,
`_updateMotorStatePoll`, `_offStateSpeed`/`_offStateMode`, `_recentlyPoweredOn`,
`_preNatureSpeed`, and the notifier's `updateMode` / `setActiveMode` /
`setBoostActive` / `applyMotorStateTruth` / `resetOnConnect`.

**Do not reintroduce any of the following.** Each is a layer that was deliberately
removed, and each will look like a reasonable improvement to someone reading only
the symptom:

| Tempting to add back | Why it is gone |
| --- | --- |
| Optimistic highlight on tap | The display is poll truth. The fan echoes every accepted command in ~100 ms, so the lag is an echo round-trip, not 3 s |
| Auto power-on before a control tap | One button = one frame. Tapping Speed 4 on an off fan sends only the speed frame |
| Re-sending the stored speed/mode on Power ON | Firmware `case POWER` already restores `OldTargetSpeed` itself; and re-sending a stored Reverse *flips the fan the wrong way*, since Reverse is `direction ^= 1` |
| Exit-reverse-before-mode, mode-before-speed, Smart's `max(3, …)` floor | All send-sequencing. Gone |
| "Tapping the active button is a no-op" | Every press sends a frame, including on the active one. Tapping a **lit** chip sends that mode's *exit* frame — see the mode-exit section below — never nothing |
| Any trust/agreement/confirm rule on replies | The poll's repetition *is* the correction mechanism |

**The receive path** is `_applyFrame(FanResponse, notifier)` in
`control_screen.dart`, called once per frame that `FrameStreamAssembler` produces:
`0x23`→watts, `0x24`→RPM, `0x08`→runtime + `DailyRuntime` upsert, `0x02`→power,
`0x04`→speed, `0x21`→mode highlight, `0x22`→timer. `FrameStreamAssembler` is
load-bearing and stays: the BLE60 cuts the MCU's UART stream at arbitrary byte
boundaries, so without it a split reply is silently dropped and polling itself
becomes unreliable.

**A `0x04` frame sets the speed and NOTHING else. No exceptions.** Not even
Reverse — the old exception is gone.

This is a deliberate split, not an oversight about what `0x04` means. Frame [2]
of a *poll* reply genuinely is exclusive (`get_mc_state()`, `IRScan.c:1264`), so
a `0x04` there does mean "no mode". But the identical bytes also arrive as the
echo of a speed tap (`case SPEED`, `:1357`), which clears `direction`,
`NatureFlage` and `boost_flag` but **not** `smart_mode`. The receive path cannot
tell an echo from a poll reply, so acting on `0x04` would unlight Smart for one
tick and then relight it. It acts on neither.

**Turning a chip off is therefore owned by the tap path**, where we know which
frame we just sent. Two places do it, both in `_FanControlsPanel`:

| Tap | Frame sent | Chips cleared locally |
| --- | --- | --- |
| lit `nature` / `boost` / `reverse` chip | `setSpeed(speed)`, speed clamped to 1–6, else 3 | that chip |
| lit `smart` chip | `powerOn()` | that chip |
| any speed dot | `setSpeed(n)` | `nature`, `boost`, `reverse` — **Smart stays lit** |
| timer 2h/4h/8h | that timer frame | `smart` only |

Every row is read straight from the firmware, not inferred: see the ground-truth
bullets above and `FW_bug.md`. Boost exits via a speed frame because **speed 7 is
Boost** — `powerOn()` would restore `OldTargetSpeed = 7` and re-enter it. Reverse
exits via a speed frame because `powerOn()` never touches `direction` and
re-sending Reverse would flip the fan back.

These local `setModeHighlight(null)` calls are the **second and last** sanctioned
optimistic write on this screen, alongside the sleep timer. They are required,
not a convenience: none of the exit frames produce a `0x21` reply, so without
them a chip could never turn off.

**A `power == false` frame** clears power, both mode chips and the timer, but
**keeps the speed**. Not a judgement call: firmware's power-off branch runs
`ClearModes()` and clears `FlagAutoPower`, while `OldTargetSpeed` survives and is
restored on the next power-on. Keeping the speed also avoids fighting the `0x04`
frame arriving two bytes later in the same burst.

**Polling** — one `_pollTimer` at 3 s (`_startPoll`) writing two frames per tick,
paced 60 ms apart by `WriteQueue`: `statusPoll()` for watts/RPM and Get Motor
State for power/speed-or-mode/timer. **Both frames are the same on every tick** —
the checksum-variant alternation is gone, because the firmware provably rejects
the vendor variant (see the `get_motor_state_vendor` note above). `_runtimeTimer` stays separate
at 90 s; polling it at 3 s would be 30× the ObjectBox writes for no display gain.
Stale watts/RPM still clear after 5 s.

**Mutator no-op guards are mandatory, not cosmetic.** ~6 frames now arrive per
3 s tick. Every `ActiveFanStateNotifier` mutator returns early when the value is
unchanged; without that, each frame allocates a new `FanState` (identity-compared,
so Riverpod rebuilds the whole screen) and fires an ObjectBox write, several times
a second, forever.

`resetTelemetryOnConnect()` (replacing `resetOnConnect`) blanks only
`lastWatts`/`lastRpm`. Power/speed/mode are deliberately **not** blanked: the app
disconnects on every background and reconnects on every resume, so blanking them
would collapse the dial visibly on every resume, and they are the fan's own memory
— the first poll tick corrects anything stale.

**Known trade-offs, accepted:**
- A Nature/Smart highlight can stay lit after the fan has left that mode, on any
  firmware where a speed command clears modes internally (the newer
  `TERRATON_FIRMWARE_SAMPLE.c` does). The alternative reinstates the
  Smart-vanishes bug on current field firmware.
- An IR-remote **Timer OFF** while connected is unobservable — the chip stays lit
  until power-off or countdown end.
- A stale backlog reply can flash a wrong value for up to one 3 s tick on connect.

### Connection Log (`lib/core/diagnostics/connection_log_service.dart`)

Records timestamped events to a rolling 128 KB file; Settings -> Connection Log
views/shares/clears it, so a field tester can capture exactly what the fan
reported. Line kinds:

| Kind | Hooked in | Meaning |
| --- | --- | --- |
| `TX` / `RX` | `BleServiceImpl` | frame written / raw notification bytes **pre-reassembly** |
| `FRM` | `_subscribeNotify` | frames `FrameStreamAssembler` produced, as `cmd=data`. **Read against the `RX` line above it** - a frame present in RX but absent here was dropped by reassembly; the raw bytes alone can't show that |
| `MS` | `_applyFrame` | one line per applied state frame - `power=on/off`, `speed=N`, `mode=NAME`, `timer=N`. Read against the `FRM` line above it: a frame in `FRM` with no `MS` line either carried telemetry or was a `0x22` code of 0 (deliberately ignored) |
| `EV` | `BleServiceImpl`, `_connect`, lifecycle | connect/disconnect, `app paused`/`app resumed`, and the restore baseline at connect |

The three levels exist because raw frame hex cannot distinguish **"the reply never
arrived"** from **"the reply arrived and was dropped in reassembly"** from **"the
reply arrived and changed nothing"**. `RX` is what the BLE60 sent, `FRM` is what
survived reassembly, `MS` is what actually moved. **The lab fan runs older
firmware than field units**, so when a field bug contradicts the frame tables
above, trust a tester's capture over this document.

### Mode highlight (`setModeHighlight`)

One method sets which chip is lit, from a `0x21` frame's mode name (or `null` to
clear). `isBoost` and `activeMode` are one UI concept stored in two columns, so
writing both is writing one field — a `0x21` naming exactly one mode necessarily
unlights the others. That is reading the byte, not inferring from it.

It deliberately does **not** touch `isPowered` (only a `0x02` frame may) and has
no nature-blocks-boost rule — firmware's `case BOOST` calls `ClearModes()`
unconditionally, so that was app policy the fan never shared.

### Sleep-timer countdown (`control_screen.dart` + `providers.dart`)

**The one surviving piece of app-side logic, and the one surviving optimistic
write.** Everything else on this screen is poll-driven; the timer cannot be,
because the fan does not report a running one.

The fan answers `22 01 00` for any BLE-set timer regardless of what is armed —
a firmware **consumed-flag bug**, not a design limit. `SetAutoPower()`
(`IRScan.c:197`) *does* set `IRControl.FlagAutoPower = 1`. But
`AutoPowerControl()` (`:857`) runs on every tick, copies the flag into
`AutoPowerState` and clears the original one tick later (`:864`) — and
`get_mc_state()` (`:1292`) gates the timer field on exactly the flag that was
just cleared. So it is essentially always 0. The live countdown does exist, in
`AutoPowerState.ShutDowntime`/`.CurrentTime`, which `get_mc_state()` never reads.
The fix is `FW_bug.md` item 2. Evidence to the byte in the 2026-07-04 field
capture: `TX 55 AA 06 22 01 02` at 16:48:12 is acknowledged (`RX 22 01 02`), yet
**every** later Get Motor State reply says `22 01 00`, and the capture contains
no timer-off command.

So the app owns both ends of the countdown:

- **Start.** The Timer tap writes `updateTimer(code, activatedAt: DateTime.now())`
  optimistically, persisted as `FanState.timerActivatedAt` via `saveTimerState`.
  `updateTimer` resolves the start time as explicit (user tap) → current state
  (same code) → `DateTime.now()` (count down from detection, used for timers set
  from the IR remote while disconnected; an upper bound by design). A start time
  implying the timer already expired is discarded.
- **Display.** `_TimerCountdown` ticks at 1 Hz and renders `Xh Ym Zs REMAINING`.
- **End.** `_scheduleTimerExpiry(FanState)` — a one-shot `Timer` armed from the
  `ref.listen` in `build()`, firing `updateTimer(0)` at the expected zero. It
  **keeps running while the app is backgrounded**, which is the point: that is
  when there is no poll and no BLE link to observe the fan shutting itself off.

**A reported `0x22` code of `0` is NEUTRAL, never a cancellation.** The rule that
used to live in `machine_state_timer_policy.dart` is now one guard in
`_applyFrame`: `if (timer != null && timer != 0)`. Reading that zero as a clear
kills the countdown within one poll tick of arming it — the "timer resets on
reconnect" field bug. **Do not remove `0x00` from `parseTimer`'s whitelist**
either; it is what lets a genuine user Timer-OFF tap round-trip.

**The only three things that clear the chip:** the user tapping Timer OFF; a
`power == false` frame (firmware clears `FlagAutoPower` in its power-off branch,
so this is fact, not inference); and the expiry one-shot above. Nothing the poll
reports can clear it on its own.

**If Terraton fixes the flag,** a 4 h timer will report `4 → 3 → 2 → 1 → 0` in
`data[0]`, and `parseTimer` whitelists only `{0x00, 0x02, 0x04, 0x08}` — codes 3
and 1 would be dropped. Note the newer `TERRATON_FIRMWARE_SAMPLE.c` does **not**
do that: it keeps the constant code in `data[0]` and puts remaining hours in
`data[1]`, which the current parser simply ignores. Either way the neutral-zero
rule stays correct, since the final hour still reports `0`.

While the app is backgrounded the countdown is also visible as an ongoing
notification, rendered by Android with **no BLE and no Dart timer** — see
"Ongoing notification" below. The fan performs its own shutdown at T-0
(hardware-confirmed; only the *reporting* is broken), so the app never enforces
the power-off.

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

Polls every 3 seconds after connect (`_startPoll`), writing BOTH `statusPoll()` and a Get Motor State frame per tick. Responses arrive on `notifyStream`, go through `FrameStreamAssembler`, and are dispatched one frame at a time by `_applyFrame`:
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
