# Terraton fan firmware — bug report

Source reviewed: `IRScan.c` (1658 lines), received 2026-08-21.
All line numbers refer to that file.

Every item below was read from the source. Where a bug was also seen on real
hardware, the evidence is the field capture taken on 2026-07-04 (fan MAC
`00:04:3E:8B:03:24`), quoted inline.

Severity key:

| | Meaning |
|---|---|
| **A** | User-visible fault. App cannot work around it correctly. |
| **B** | User-visible fault. App can work around it, but the workaround is fragile. |
| **C** | Wrong or dead code with no user-visible effect today. |

---

## Summary

| # | Severity | Area | One line |
|---|---|---|---|
| 1 | A | Smart mode | BLE speed command does not clear `smart_mode`; IR remote does |
| 2 | A | Sleep timer | `get_mc_state()` reads a flag that is wiped one tick after it is set |
| 3 | A | Reverse | Reverse echo always says `03`, whichever direction results |
| 4 | A | Nature | Nature cannot be exited by any BLE mode command |
| 5 | B | Checksum | `calculate_crc()` omits the header and length byte |
| 6 | B | UART parser | A `0x55` data byte resets the receive state machine |
| 7 | B | Smart mode | Setting a sleep timer silently turns Smart off |
| 8 | C | Smart mode | `SmartMode()` is dead code — Smart never steps its speed down |
| 9 | C | Motor state | `get_mc_state()` emits a duplicate trailing frame |
| 10 | C | IR remote | 1-hour timer button sends no response |
| 11 | C | Heartbeat | `heartbeat()` mode chain is missing the Smart branch |

---

## 1. `case SPEED` does not clear `smart_mode` — Severity A

**Where:** `Process_Response()`, `case SPEED`, `:1357-1371`.

Every IR remote speed button clears `smart_mode`:

```c
case IRSpeed4:
    SetSpeed(4);
    boost_flag = 0;
    smart_mode = 0;        // :627
```

The BLE path does not:

```c
case SPEED:
    SetSpeed(request_frame[5]);
    if (direction) { direction = 0; MoveForward(); get_mc_state(); }
    boost_flag = 0;        // :1369  -- smart_mode never touched
```

`SetSpeed()` (`:179`) clears `NatureFlage` and `NatureWinFlag`, but not
`smart_mode`.

**Effect:** once Smart is on, the app cannot turn it off with any speed command.
`get_mc_state()` keeps answering `21 01 04` forever. The remote can leave Smart;
the app cannot. This is the main cause of the reported Smart mode fault.

**Fix:** add `smart_mode = 0;` to `case SPEED`, matching `:592`, `:605`, `:614`,
`:627`, `:644`, `:657`.

---

## 2. Sleep timer is never reported — Severity A

**Where:** `SetAutoPower()` `:197`, `AutoPowerControl()` `:857`, `get_mc_state()` `:1292`.

`SetAutoPower()` sets the flag:

```c
void SetAutoPower(uint16 TimeSet) {
    IRControl.FlagAutoPower = 1;
    AutoPowerState.ShutDowntime = TimeSet;
}
```

`AutoPowerControl()` runs on every tick and consumes it immediately:

```c
if (IRControl.FlagAutoPower) {
    AutoPowerState.FlagAutoPower = 1;
    AutoPowerState.Timer10sec = 0;
    AutoPowerState.CurrentTime = 0;
    IRControl.FlagAutoPower = 0;      // :864 -- cleared here
}
```

`get_mc_state()` then tests the flag that was just cleared:

```c
if (IRControl.FlagAutoPower) {
    response_frame[5] = AutoPowerState.ShutDowntime / 360;
} else {
    response_frame[5] = 0x00;         // :1297 -- always this branch
}
```

**Evidence.** From the 2026-07-04 capture — a 2-hour timer is set, and every
later state reply still says `22 01 00`:

```
16:48:12.471  TX 55 AA 06 22 01 02      <- set 2h timer
16:48:12.593  RX 55 AA 07 22 01 02      <- command echo, correct
16:48:24.147  RX ... 55 AA 07 22 01 00  <- state reply says "no timer"
16:48:37.164  RX ... 55 AA 07 22 01 00  <- and again
```

**Effect:** the fan cannot report an armed timer or the time left, so the app has
to run its own countdown and guess. The fan does shut down correctly at T-0; only
the reporting is broken.

**Fix:** read the live state instead of the consumed flag:

```c
if (AutoPowerState.FlagAutoPower) {
    response_frame[3] = TIMER;
    response_frame[5] = (AutoPowerState.ShutDowntime
                       - AutoPowerState.CurrentTime) / 360;
}
```

That gives a real countdown in whole hours, which is what the app needs.

---

## 3. Reverse echo does not report the resulting direction — Severity A

**Where:** `Process_Response()`, `case BOOST`, `:1395-1404`.

```c
if (request_frame[5] == REVERSE_MODE) {
    direction ^= 0x01;                 // :1396 toggle
    if (direction) MoveReverse(); else MoveForward();
    response_frame[5] = REVERSE_MODE;  // :1402 always 0x03
}
```

Reverse is a toggle, but the reply is the constant `21 01 03` whether the fan
ended up reversed or forward.

**Effect:** the app cannot tell "reverse started" from "reverse stopped". Combined
with the toggle, one duplicated or retried frame flips the fan back and looks
like "Reverse did nothing". This is why the app must not retry BLE writes.

**Fix:** report what actually happened:

```c
response_frame[5] = direction ? REVERSE_MODE : SPEED;   // or the new speed
```

Reporting the resulting direction would let the app drop its local workaround
entirely.

---

## 4. Nature cannot be exited by a mode command — Severity A

**Where:** `case BOOST` `:1373-1413`.

`IRControl.NatureFlage` is set at `:1390` and cleared only inside `SetSpeed()`
(`:187`) and in `case POWER` (`:1335`, `:1346`).

Sending Boost, Reverse or Smart while Nature is running:

- Boost calls `SetSpeed(7)` → clears Nature. Works by accident.
- Smart calls `SetSpeed(6)` → clears Nature. Works by accident.
- **Reverse calls neither** → `NatureFlage` stays 1. The fan keeps modulating its
  speed while also running in reverse, and `get_mc_state()` reports `21 01 03`
  because `direction` is tested first (`:1273`).

**Effect:** Nature + Reverse can both be active at once, and the reply only
mentions one of them.

**Fix:** clear the other mode flags at the top of `case BOOST`, the way
`ClearModes()` is used elsewhere, rather than relying on `SetSpeed()` side
effects in three of the four branches.

---

## 5. `calculate_crc()` omits the header and length byte — Severity B

**Where:** `:1455-1460`.

```c
if (response_frame[4] == 0x01)
    response_frame[6] = response_frame[2] + response_frame[3] + response_frame[5];
else if (response_frame[4] == 0x02)
    response_frame[7] = response_frame[2] + response_frame[3]
                      + response_frame[5] + response_frame[6];
```

The `0x55 0xAA` header and the length byte `[4]` are both left out. `check_crc()`
(`:1462`) does the same for requests.

This is not just a style difference, because the omission does not cancel evenly:

| Payload | Missing amount | Effect on a header-inclusive checksum |
|---|---|---|
| 1 byte | `0x55 + 0xAA + 1 = 0x100` | cancels exactly — the two agree |
| 2 bytes | `0x55 + 0xAA + 2 = 0x101` | off by exactly 1 |

**Evidence,** same capture, one of each:

```
55 AA 07 23 01 18 42       1 byte:  0x07+0x23+0x18       = 0x42  agrees
55 AA 07 24 02 01 68 94    2 bytes: 0x07+0x24+0x01+0x68  = 0x94  off by one
```

**Effect:** any host that checksums the whole frame — the natural reading of the
protocol document — accepts 1-byte replies and rejects 2-byte ones. That is RPM
(`0x24`) and runtime (`0x08`). Runtime was being silently discarded in our app
until we widened the tolerance.

**Fix:** include `[0]`, `[1]` and `[4]` in both `calculate_crc()` and
`check_crc()`, so the checksum covers the whole frame and both payload sizes
behave the same.

**Related:** because `check_crc()` uses this formula, the vendor-documented
"Get Motor State" frame `55 AA 00 01 01 00 02` is **rejected** by the fan —
`0x00 + 0x01 + 0x00 = 0x01`, not `0x02`. Only `55 AA 00 01 01 00 01` is accepted.

---

## 6. A `0x55` data byte resets the UART receive state machine — Severity B

**Where:** `read_request()` `:1483-1507`.

```c
if (UT_DR == 0x55) {              // :1485 -- unconditional
    request_frame[0] = UT_DR;
    recv_index = 1;
    header_flag = 1;
}
```

This test runs on every byte, with no check on `header_flag`. Any byte inside a
frame whose value is `0x55` restarts reception from the header.

**Effect:** every request carrying `0x55` as a data or checksum byte is dropped
and, worse, resynchronises the parser to the wrong offset. It happens not to
affect the current fan command set, but it will break the moment a command uses
that value.

**Fix:** only accept the header when not already mid-frame:

```c
if (UT_DR == 0x55 && header_flag == 0) { ... }
```

Also consider a receive timeout, so a truncated frame cannot leave the parser
stuck at `header_flag == 2` indefinitely.

---

## 7. Setting a sleep timer turns Smart off — Severity B

**Where:** `case TIMER` `:1414-1435`.

```c
if (request_frame[5] == 2) { SetAutoPower(720);  smart_mode = 0; }  // :1422
if (request_frame[5] == 4) { SetAutoPower(1440); smart_mode = 0; }  // :1426
if (request_frame[5] == 8) { SetAutoPower(2880); smart_mode = 0; }  // :1430
```

Code `0` does not do this.

**Evidence,** from the 2026-07-04 capture. Smart is confirmed on, then a 2-hour
timer is set, and Smart is gone from every later reply:

```
16:48:09.912  TX 55 AA 06 21 01 04      <- Smart on
16:48:10.010  RX 55 AA 07 21 01 04      <- fan confirms Smart
16:48:12.471  TX 55 AA 06 22 01 02      <- 2h timer
16:48:24.147  RX ... 55 AA 07 04 01 06  <- reports speed 6, no mode
```

**Effect:** a user arming a sleep timer silently leaves Smart. Nothing reports it,
because of bug 2 the timer is not reported either, so the app has no way to
observe the change. Two features that should compose cancel each other.

Please confirm whether this is intended. If it is, it should at least be
reported; if not, remove the three assignments.

---

## 8. `SmartMode()` is dead code — Severity C

**Where:** `SmartMode()` `:1145-1153`, `smartDelayCount` `:73`.

```c
uint16 smartDelayCount = 0;          // :73  declared, initialised to 0

void SmartMode(void) {
    if (smartDelayCount == 900) {    // :1147  only read, never written
        if (SpeedCnt > 1) { SpeedCnt--; SetSpeed(SpeedCnt); }
    }
}
```

`smartDelayCount` is never incremented anywhere in the file. The condition can
never be true.

**Effect:** Smart mode never steps its speed down. It sets speed 6 once
(`:1407-1408`) and stays there. Smart is currently just "run at speed 6".

Note this also makes the app's Smart efficiency estimate wrong — it models a
step-down that never happens.

**Fix:** increment `smartDelayCount` on the same tick that calls `SmartMode()`,
and reset it after each step:

```c
if (smart_mode) { smartDelayCount++; SmartMode(); }
```

with `smartDelayCount = 0;` inside the `== 900` branch. Please confirm the
intended step interval — 900 ticks is far short of the 2 hours the product
description implies.

---

## 9. `get_mc_state()` emits a duplicate trailing frame — Severity C

**Where:** `get_mc_state()` `:1264-1301`, `Process_Response()` `:1450-1451`.

`get_mc_state()` sends all three of its frames itself — power (`:1271`),
speed-or-mode (`:1290`), timer (`:1299`). Control then returns to
`Process_Response()`, which unconditionally ends with:

```c
calculate_crc();
send_response();
MotorStatusSave();
```

`response_frame` still holds the timer frame, so it is transmitted a second time.
A Motor State poll returns **4** frames, not 3.

Compare `send_status()` (`:1239`), which is written correctly for this pattern —
it comments out its own second send (`:1258-1259`) and lets the trailing block
emit the RPM frame, giving exactly 2 frames.

**Effect:** harmless today, but it wastes UART bandwidth on every poll and makes
the frame count inconsistent between the two commands.

**Fix:** either drop the last `calculate_crc(); send_response();` pair from
`get_mc_state()`, or move the trailing send in `Process_Response()` into the
cases that need it.

---

## 10. IR 1-hour timer button sends no response — Severity C

**Where:** `case IRAUTOPOWER1H` `:675-679`.

```c
case IRAUTOPOWER1H:
    SetAutoPower(360);
    break;                    // no send_remote_response()
```

The 2h, 4h and 8h buttons all report (`:684`, `:691`, `:698`).

**Effect:** a 1-hour timer set from the remote is invisible to the app. Also note
1 hour is not one of the four codes the BLE protocol defines (`0`, `2`, `4`, `8`),
so if it were reported the value `1` would not be a valid timer code.

**Fix:** add `send_remote_response(TIMER, HOUR_1);` and define `HOUR_1` in the
protocol, or drop the 1-hour option.

---

## 11. `heartbeat()` mode chain is missing the Smart branch — Severity C

**Where:** `heartbeat()` `:1186-1199`, compare `get_mc_state()` `:1273-1289`.

`get_mc_state()` tests four modes:

```c
if (direction) ... else if (NatureFlage) ... else if (smart_mode) ... else if (OldTargetSpeed == 7) ...
```

`heartbeat()` copies the same chain but drops `smart_mode`:

```c
if (direction) ... else if (NatureFlage) ... else if (OldTargetSpeed == 7) ...
```

**Effect:** none today, because this block only runs once per power-up
(`heartbeat_flag`) and the app polls `get_mc_state()` instead. It is a
copy-paste divergence that will report the wrong mode if the heartbeat path is
ever re-enabled.

**Fix:** factor the chain into one function used by both.

---

## What we would most like fixed

In order of value to the app:

1. **Bug 1** — one line. Without it Smart cannot be switched off from the app.
2. **Bug 2** — a few lines. Gives a real sleep-timer countdown and removes the
   app's need to run its own.
3. **Bug 3** — one line. Removes the app's local Reverse tracking and the ban on
   retrying BLE writes.
4. **Bug 5** — makes 2-byte replies checksum the same way as 1-byte replies, and
   makes the vendor-documented Motor State frame work.

Bugs 1, 2 and 3 together account for all three reported faults: Reverse, Smart
and Nature.
