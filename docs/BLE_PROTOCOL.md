# BLE Protocol Reference

How the app talks to a Terraton BLDC fan over Bluetooth Low Energy 5.2 via the
Amp'ed RF BLE60 UART bridge.

```text
Flutter App  ──BLE 5.2──►  Amp'ed RF BLE60  ──UART──►  Fan MCU  ──►  BLDC Motor
```

> **Single source of truth:** every command byte lives in
> [`terraton_fan_app/assets/commands.yaml`](../terraton_fan_app/assets/commands.yaml).
> The tables below are the human-readable mirror of that file — never hardcode
> bytes in Dart.

---

## Connection

| Field | UUID | Meaning |
| --- | --- | --- |
| Scan filter (advertisement) | `00001827-0000-1000-8000-00805f9b34fb` | BLE Mesh Proxy |
| Write characteristic | `00002adb-0000-1000-8000-00805f9b34fb` | Mesh Proxy Data In |
| Notify characteristic | `00002adc-0000-1000-8000-00805f9b34fb` | Mesh Proxy Data Out — `setNotifyValue(true)` |

All UUIDs are defined only in
[`lib/core/ble/ble_constants.dart`](../terraton_fan_app/lib/core/ble/ble_constants.dart).
Service discovery also searches these fallbacks, **first match wins**, in priority
order: Amp'ed RF proprietary (`26cc3fc2`/`26cc3fc1`), CC254X / HM-10 (`0000ffe1`),
Nordic UART Service, Microchip RN4870.

The BLE60 uses a **random** BLE address. The live `BluetoothDevice` from the scan
cache carries the correct address type and must be used on first connection;
`BluetoothDevice.fromId(mac)` is only safe for reconnects after Android has cached
the type. **Never scan before connecting** — `startScan()` clears the scan cache.

---

## Frame format

```text
[ 0x55  0xAA  packetId  command  dataLen  ...data  checksum ]
```

| Part | Request | Response |
| --- | --- | --- |
| Header | `0x55 0xAA` | `0x55 0xAA` |
| `packetId` (byte 2) | `0x06` | `0x07` |

**Checksum** — sum of every byte before the checksum, including the header:

```text
checksum = (0x55 + 0xAA + packetId + command + dataLen + Σ data) & 0xFF
```

> **The firmware does NOT use that formula.** `calculate_crc()` (`IRScan.c:1455`)
> sums only `packetId + command + Σ data` — it omits the `55 AA` header and the
> `dataLen` byte. The difference is `0x55 + 0xAA + dataLen`, so:
>
> | dataLen | difference | effect |
> | --- | --- | --- |
> | 1 | `0x100` | cancels exactly — both formulas agree |
> | 2 | `0x101` | the formula above is exactly **+1** too high |
>
> That is the whole of the old "RPM checksum quirk": `0x24` (RPM) and `0x08`
> (runtime) are the only 2-byte responses. `BleResponseParser._checksumOk`
> therefore keys the tolerance on **dataLen == 2**, not on the command byte.
> Keying it on `0x24` alone silently discarded every runtime reply.
>
> `check_crc()` (`IRScan.c:1462`) applies the same formula to requests. Our
> request checksums work because every request carries a 1-byte payload.

---

## BLE60 bridge behaviour

The BLE60 is a transparent BLE-to-UART bridge. It buffers incoming BLE writes and
only flushes to the MCU UART when it receives `\r\n` (`0x0D 0x0A`). The app appends
`0x0D 0x0A` to every frame automatically in `BleServiceImpl.writeFrame()`.

On every new BLE connection the BLE60 first emits its own init bytes over UART
**before** any app data:

```text
FF FF FF FF FF FF FF FF FF
AT-AB -CommandMode-\r\n
AT-AB BDAddress <mac>\r\n
AT-AB -BLE-ConnectionUp <addr>\r\n
AT-AB -BypassMode-\r\n          ← transparent mode starts here
```

**MCU firmware must scan for the `55 AA` header and skip all other bytes** —
including these AT strings and the trailing `0D 0A` after each frame.

**The same rule applies in the phone direction — with reassembly.** The BLE60
forwards the MCU's UART output in notification-sized chunks cut at **arbitrary
byte boundaries**, not frame boundaries. A multi-frame burst (e.g. the 4-frame
Motor State reply plus a runtime frame on connect, ~29 bytes) is routinely
split **mid-frame** across two notifications. The app therefore never parses a
notification in isolation: `FrameStreamAssembler`
(`lib/core/ble/ble_response_parser.dart`) buffers unconsumed tail bytes across
notifications, completes split frames when the next chunk arrives, and skips
junk (AT strings, `FF` padding, `\r\n`) while scanning for `55 AA`. Stateless
per-notification parsing silently drops any mid-frame-split frame — that was
the root cause of Smart mode and the sleep timer being lost on reconnect
(fixed 2026-07-03). The assembler is reset on every (re)connect so a stale
partial frame can't merge with the next session's bytes.

---

## Command table

Manually verified against real hardware.

| Operation | Request (hex) | Response (hex) |
| --- | --- | --- |
| Power ON | `55 AA 06 02 01 01 09` | `55 AA 07 02 01 01 0A` |
| Power OFF | `55 AA 06 02 01 00 08` | `55 AA 07 02 01 00 09` |
| Speed 1 | `55 AA 06 04 01 01 0B` | `55 AA 07 04 01 01 0C` |
| Speed 2 | `55 AA 06 04 01 02 0C` | `55 AA 07 04 01 02 0D` |
| Speed 3 | `55 AA 06 04 01 03 0D` | `55 AA 07 04 01 03 0E` |
| Speed 4 | `55 AA 06 04 01 04 0E` | `55 AA 07 04 01 04 0F` |
| Speed 5 | `55 AA 06 04 01 05 0F` | `55 AA 07 04 01 05 10` |
| Speed 6 | `55 AA 06 04 01 06 10` | `55 AA 07 04 01 06 11` |
| Boost mode | `55 AA 06 21 01 01 28` | `55 AA 07 21 01 01 29` |
| Nature mode | `55 AA 06 21 01 02 29` | `55 AA 07 21 01 02 2A` |
| Reverse mode | `55 AA 06 21 01 03 2A` | `55 AA 07 21 01 03 2B` |
| Smart mode | `55 AA 06 21 01 04 2B` | `55 AA 07 21 01 04 2C` |
| Timer OFF | `55 AA 06 22 01 00 28` | `55 AA 07 22 01 00 29` |
| Timer 2 h | `55 AA 06 22 01 02 2A` | `55 AA 07 22 01 02 2B` |
| Timer 4 h | `55 AA 06 22 01 04 2C` | `55 AA 07 22 01 04 2D` |
| Timer 8 h | `55 AA 06 22 01 08 30` | `55 AA 07 22 01 08 31` |
| Query power (watts) | `55 AA 06 23 01 00 29` | `55 AA 07 23 01 WW cs` — `WW` = watts byte |
| Query speed (RPM) | `55 AA 06 24 01 00 2A` | `55 AA 07 24 02 HH LL cs` — RPM = `(HH << 8) \| LL` |
| Status poll | `55 AA 00 00 01 00 00` *(non-standard fixed frame — do **not** pass through `buildFrame()`)* | See below |
| Motor State poll | `55 AA 00 01 01 00 01` *(non-standard fixed frame — do **not** pass through `buildFrame()`)* | See below — 4 frames, each applied independently |
| Query runtime | `55 AA 00 08 01 00 08` *(non-standard fixed frame — do **not** pass through `buildFrame()`)* | `55 AA 07 08 02 HH LL cs` — runtime = `(HH << 8) \| LL) × 5` seconds |
| Lighting ON/OFF/colour temp | *Pending — bytes not yet provided by Terraton* | *Pending* |

### Response byte → handler

| Command byte | Meaning | Parser |
| --- | --- | --- |
| `0x02` | Power on/off | `parsePowerState` |
| `0x04` | Speed 1–6 | `parseSpeed` |
| `0x21` | Mode (`0x01` boost, `0x02` nature, `0x03` reverse, `0x04` smart) | `parseModeString` |
| `0x22` | Timer code | `parseTimer` |
| `0x23` | Watts | `parsePowerWatts` |
| `0x24` | RPM (2 bytes) | `parseRpm` |
| `0x08` | Runtime (2 bytes) — `(HH << 8 \| LL) × 5` seconds | `parseRuntimeSeconds` |

**Mode highlight (app-side):** a `0x21` frame names exactly one mode, so applying
it lights that chip and unlights the others — that is reading the byte, not
inferring. **No received frame ever clears a chip**, `0x04` included and with no
exception for Reverse.

A chip is turned off only by a tap, using the frame the firmware actually honours
as an exit for that mode:

| Tap | Frame sent | Firmware reason |
| --- | --- | --- |
| lit Nature / Boost / Reverse chip | `setSpeed(1..6)` | `SetSpeed()` clears `NatureFlage` (`:187`); `case SPEED` clears `direction` (`:1361`) and `boost_flag` (`:1369`) |
| lit Smart chip | Power ON | only `case POWER`'s on-branch clears `smart_mode` (`:1347`), and it keeps the speed (`:1344`) |
| any speed dot | `setSpeed(n)` | clears Nature / Boost / Reverse — **Smart stays lit**, `case SPEED` does not clear it |
| timer 2h / 4h / 8h | that timer frame | `case TIMER` clears `smart_mode` (`:1424`/`:1428`/`:1432`) |

Boost exits with a speed frame because **speed 7 is Boost** — Power ON would
restore `OldTargetSpeed = 7` and re-enter it. Reverse exits with a speed frame
because Power ON never touches `direction`, and because re-sending Reverse
(`direction ^= 1`, `:1396`) would flip the fan back.

---

## Status poll: 2-frame vs 4-frame response

The control screen polls every 3 s with the fixed status-poll frame. Responses
arrive on the notify characteristic and `BleResponseParser.parseAll()` handles any
number of frames concatenated in one notification.

- **Normal poll → 2 frames:** `0x23` (watts) + `0x24` (RPM).
- **First poll after a fresh power-on → 4 frames:** `0x02` (power), `0x04` (speed),
  `0x23` (watts), `0x24` (RPM).

The 4-frame response happens once — on the first poll after the fan is connected to
mains **and** turned on via the app — so the fan can restore complete state that
may have reset while it was disconnected from power. Subsequent polls in the same
session return 2 frames. The notify handler dispatches all frame types
unconditionally, so no special-casing is needed.

---

## Motor State poll (a.k.a. Machine State poll)

Sent on every 3 s poll tick, alongside the status poll. Both frames are enqueued
in one synchronous turn and paced 60 ms apart by `WriteQueue`.

| Frame | Command byte | Meaning |
| --- | --- | --- |
| 1 | `0x02` | Power state — `data[0] == 0x01` = on |
| 2 | `0x04` **or** `0x21` | Speed (1–6) **or** active mode |
| 3 | `0x22` | Timer code |
| 4 | `0x22` | Duplicate of frame [3] — see below |

Any subset is fine: **each frame is applied on its own as it arrives**, straight
to its own field. There is no reply assembly, no ordering rule, and no trust
decision — see "The control screen is a dumb remote" in [CLAUDE.md](../CLAUDE.md).
Frames may still be split mid-frame across notifications, which is why
`FrameStreamAssembler` runs first (see "BLE60 bridge behaviour" above).

**Frame [2] IS exclusive.** `get_mc_state()` (`IRScan.c:1264`) is a single
if/else chain: `direction` → `21 03`, else `NatureFlage` → `21 02`, else
`smart_mode` → `21 04`, else `OldTargetSpeed == 7` → `21 01`, else → `04 0N`.
A `0x04` here provably means no mode is running, and the app can never learn the
speed while a mode is on. (Earlier revisions of this doc claimed the opposite.)

**The app still never changes a mode chip on a `0x04`.** The same bytes also
arrive as the echo of a speed tap (`case SPEED`, `:1357`), which clears
`direction`, `NatureFlage` and `boost_flag` but **not** `smart_mode`. The receive
path cannot tell an echo from a poll reply, so it acts on neither; turning a chip
off happens on the tap path instead.

**There is a 4th frame.** `get_mc_state()` sends its three frames itself, then
`Process_Response()`'s unconditional trailing `calculate_crc(); send_response();`
(`:1450`) emits a duplicate of frame [3]. Harmless — a reported `0x22` code of 0
is ignored.

**No checksum alternation.** Only `55 AA 00 01 01 00 01` is ever sent. The vendor
doc's `55 AA 00 01 01 00 02` is **rejected by the fan**: `check_crc()` computes
`0x00 + 0x01 + 0x00 = 0x01`, so `read_request()` never sets `recv_flag` and
`Process_Response()` is never called. The app used to alternate the two, which
meant every second tick got no reply at all.

**Sleep-timer note:** frame [3] reports `22 01 00` for any BLE-set timer whatever
is armed. `SetAutoPower()` (`:197`) *does* set `IRControl.FlagAutoPower`, but
`AutoPowerControl()` (`:857`) consumes and clears it one tick later (`:864`) — and
`get_mc_state()` (`:1292`) gates the timer field on exactly that flag. The app
therefore owns the countdown start, display and end. A reported code of `0` is
**neutral, never a cancellation**. See `FW_bug.md` item 2.

---

## Runtime query

Sent once on connect and every 90 s via `_runtimeTimer`.

```text
Request:  55 AA 00 08 01 00 08
Response: 55 AA 07 08 02 HH LL cs
```

`runtime seconds = (HH << 8 | LL) × 5`

The firmware reports cumulative daily runtime (resets at midnight). Each response is
upserted to `DailyRuntimeRepository` keyed by `(deviceId, localDate)` — the latest
value for the day overwrites the previous one. Never treat a missing day as zero;
fill gaps with the average of available days (`AnalyticsCalculations.normalizeDailyRuntimes`).

---

## Adding a new command

1. Add the entry to `assets/commands.yaml` (set `command: null` if bytes are TBD).
2. Add a named method to `BleFrameBuilder` calling `CommandLoader.custom([...], data)`.
3. Wire it to the UI in `ControlScreen._send()`.
4. If the fan replies, add a `parse*` helper to `BleResponseParser` and dispatch it
   in `ControlScreen._subscribeNotify()`.

`CommandLoader._safeGet()` returns `null` for missing keys, `BleFrameBuilder`
propagates the `null`, and `ControlScreen._send()` shows a SnackBar instead of
crashing — so a YAML entry with `command: null` degrades gracefully.
