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

> **RPM checksum quirk:** responses for command `0x24` (RPM) arrive with
> `checksum = (correct − 1) & 0xFF`. The parser accepts both the exact and the
> off-by-one value (`BleResponseParser._checksumOk`).

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

## Adding a new command

1. Add the entry to `assets/commands.yaml` (set `command: null` if bytes are TBD).
2. Add a named method to `BleFrameBuilder` calling `CommandLoader.custom([...], data)`.
3. Wire it to the UI in `ControlScreen._send()`.
4. If the fan replies, add a `parse*` helper to `BleResponseParser` and dispatch it
   in `ControlScreen._subscribeNotify()`.

`CommandLoader._safeGet()` returns `null` for missing keys, `BleFrameBuilder`
propagates the `null`, and `ControlScreen._send()` shows a SnackBar instead of
crashing — so a YAML entry with `command: null` degrades gracefully.
