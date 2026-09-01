# Terraton fan firmware — bug report

Source originally reviewed: `IRScan.c` (1658 lines), received 2026-08-21.
Line numbers below are from that original review unless a status note gives a
newer one. **Status column added 2026-08-24** — several items have since been
fixed and reflashed; two new bugs were found and one is fixed, the other is a
known, accepted limitation. The `FIRM/` folder in this repo is a working
reference copy, synced only after a flash (not after every discussion), so its
line numbers can drift from what's below — verify against it before citing an
exact line if it matters.

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

| # | Severity | Area | One line | Status (2026-08-24) |
|---|---|---|---|---|
| 1 | A | Smart mode | BLE speed command does not clear `smart_mode`; IR remote does | Root cause still present in `case SPEED`; **worked around app-side** (app sends power-ON before a speed frame to exit Smart) |
| 2 | A | Sleep timer | `get_mc_state()` reads a flag that is wiped one tick after it is set | **Fixed** — reads the persistent flag; timer frame further widened to report exact remaining time (was 2-min ticks, now raw 10s-unit precision) |
| 3 | A | Reverse | Reverse echo always says `03`, whichever direction results | Open, unchanged |
| 4 | A | Nature | Nature cannot be exited by any BLE mode command | **Fixed** — BLE `REVERSE_MODE` and remote `IRReverse` both now clear `NatureFlage`/`NatureWinFlag` |
| 5 | B | Checksum | `calculate_crc()` omits the header and length byte | Open, unchanged — app already tolerates it (see `BleResponseParser._checksumOk`) |
| 6 | B | UART parser | A `0x55` data byte resets the receive state machine | Open, unchanged |
| 7 | B | Smart mode | Setting a sleep timer silently turns Smart off | **Confirmed intentional** — no longer treated as a bug; app relies on this to detect the change |
| 8 | C | Smart mode | `SmartMode()` is dead code — Smart never steps its speed down | Open, unchanged |
| 9 | C | Motor state | `get_mc_state()` emits a duplicate trailing frame | Open, unchanged — now duplicates the wider timer frame too (harmless either way) |
| 10 | C | IR remote | 1-hour timer button sends no response | Open, unchanged |
| 11 | C | Heartbeat | `heartbeat()` mode chain is missing the Smart branch | Open, unchanged |
| 12 | A | Sleep timer | Remote Timer-OFF (`IRTimerOFF`) caused a real, unintended auto-shutoff a few seconds later | **Fixed** — 2026-08-22 |
| 13 | B | Nature/Reverse | Exiting Reverse after a Nature detour resets speed to `1` instead of the pre-Nature speed | **Open — known, accepted.** No firmware fix planned; app-side exit already sidesteps this (see item 13 below) |

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

**Fix (not applied):** add `smart_mode = 0;` to `case SPEED`, matching `:592`,
`:605`, `:614`, `:627`, `:644`, `:657`.

**Status (2026-08-24):** root cause untouched in firmware. Instead, the app
works around it: exiting Smart via a speed-dial tap now sends `powerOn()` — the
only frame that's confirmed to clear `smart_mode` (`case POWER`'s on-branch,
which does not stop the fan) — immediately before the speed frame. This closes
the user-visible gap without a firmware change, but the root cause (`case
SPEED` still not clearing `smart_mode`) remains exactly as described above, so
this bug should stay open until the one-line fix lands.

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

**Status (2026-08-24): FIXED, then extended twice.**

Stage 1 — `get_mc_state()`'s timer branch now tests the persistent
`AutoPowerState.FlagAutoPower` instead of the one-tick-consumed
`IRControl.FlagAutoPower`, so the app can finally tell "armed" from "not armed."

Stage 2 — the frame was widened from 1 data byte to 2, adding a remaining-time
byte in 2-minute ticks: `response_frame[4] = 0x02;
response_frame[6] = (ShutDowntime - CurrentTime) / 12;`.

Stage 3 (current) — widened again to 3 data bytes, dropping the 2-minute
rounding entirely in favour of the firmware's own raw ~10s tick:

```c
response_frame[4] = 0x03;
if (AutoPowerState.FlagAutoPower) {
    uint16 remaining = AutoPowerState.ShutDowntime - AutoPowerState.CurrentTime;
    response_frame[5] = AutoPowerState.ShutDowntime / 360;   // code 2/4/8
    response_frame[6] = (remaining >> 8) & 0xFF;             // remaining, high byte
    response_frame[7] = remaining & 0xFF;                    // remaining, low byte
}
```

This required widening `response_frame` itself from `[8]` to `[9]` (a 3-byte
payload needs a 9th byte for the checksum), and adding a `dataLen==3` branch to
both `calculate_crc()` and `send_response()`. The app side
(`BleResponseParser.parseTimerRemainingSeconds`) reads whichever shape it gets
— 1/2/3-byte — and reconciles its own countdown anchor against it, tightening
its no-op threshold from 3 minutes (matched to the old 2-minute rounding) down
to 30 seconds (matched to the new ~10s rounding).

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

**Status (2026-08-24):** open, unchanged.

---

## 4. Nature cannot be exited by a mode command — Severity A

**Where:** `case BOOST` `:1373-1413` (BLE); `case IRReverse` (remote, IR handler
switch).

`IRControl.NatureFlage` is set at `:1390` and was cleared only inside
`SetSpeed()` (`:187`) and in `case POWER` (`:1335`, `:1346`).

Sending Boost, Reverse or Smart while Nature is running:

- Boost calls `SetSpeed(7)` → clears Nature. Works by accident.
- Smart calls `SetSpeed(6)` → clears Nature. Works by accident.
- **Reverse called neither** → `NatureFlage` stayed 1. The fan kept modulating its
  speed while also running in reverse, and `get_mc_state()` reported `21 01 03`
  because `direction` is tested first (`:1273`).

**Effect:** Nature + Reverse could both be active at once, and the reply only
mentioned one of them.

**Status (2026-08-24): FIXED, both paths.** `IRControl.NatureFlage = 0;
NatureWinFlag = 0;` was added right after the existing `smart_mode = 0;` line in
**both**:

- the BLE `REVERSE_MODE` branch inside `case BOOST` (`Process_Response()`)
- the remote's own `case IRReverse` handler — a separate switch-case from the
  BLE one, so it needed the identical fix applied independently; the BLE-only
  fix was applied first and initially left the remote path with the exact same
  symptom until this was caught and fixed too.

Confirmed working on both the app-initiated and remote-initiated Nature →
Reverse → exit sequences.

**New, related, and explicitly NOT fixed — see item 13 below:** fixing this
exposed a second, previously-masked issue — exiting Reverse now correctly stops
Nature, but the *speed* it lands on is wrong (resets to `1`, not the pre-Nature
speed), because nothing in either Reverse handler ever restores
`mcFRState.OldTargetSpeed`. Root-caused, fix specified, **declined by request**
— current behavior is accepted as-is.

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
| 3 bytes | `0x55 + 0xAA + 3 = 0x102` | off by exactly 2 |

**Evidence,** same capture, one of each (1- and 2-byte cases):

```
55 AA 07 23 01 18 42       1 byte:  0x07+0x23+0x18       = 0x42  agrees
55 AA 07 24 02 01 68 94    2 bytes: 0x07+0x24+0x01+0x68  = 0x94  off by one
```

**Effect:** any host that checksums the whole frame — the natural reading of the
protocol document — accepts 1-byte replies and rejects 2-byte (and now 3-byte)
ones as-is. That was RPM (`0x24`) and runtime (`0x08`); the widened sleep-timer
frame (item 2) is now a third case of this same pattern.

**Fix:** include `[0]`, `[1]` and `[4]` in both `calculate_crc()` and
`check_crc()`, so the checksum covers the whole frame and every payload size
behaves the same.

**Related:** because `check_crc()` uses this formula, the vendor-documented
"Get Motor State" frame `55 AA 00 01 01 00 02` is **rejected** by the fan —
`0x00 + 0x01 + 0x00 = 0x01`, not `0x02`. Only `55 AA 00 01 01 00 01` is accepted.

**Status (2026-08-24):** open, unchanged in firmware. The app now tolerates all
three payload sizes explicitly (`BleResponseParser._checksumOk`, keyed on
`dataLen`) rather than fixing the root cause — each new payload width needs its
own tolerance branch added on the app side, which is exactly what happened when
the timer frame grew a third byte.

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

**Status (2026-08-24):** open, unchanged.

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

**Effect:** a user arming a sleep timer silently leaves Smart. Two features that
should compose cancel each other.

**Status (2026-08-24): confirmed intentional, no longer treated as a bug.**
Unchanged in firmware, and no fix requested. The app now relies on this
behavior as its *only* signal that Smart was cancelled by a timer arm — since
`get_mc_state()` never reports Smart's state directly either way, the app clears
its own Smart chip locally at the moment it sends a nonzero timer code,
trusting that the firmware is about to do the same thing internally.

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

**Status (2026-08-24):** open, unchanged.

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

**Status (2026-08-24):** open, unchanged. Now duplicates the sleep-timer
frame's current (3-byte) shape instead of the original 1-byte one — same
harmless waste, just a couple more bytes of it per poll.

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

**Status (2026-08-24):** open, unchanged.

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

**Status (2026-08-24):** open, unchanged.

---

## 12. Remote Timer-OFF caused a real, unintended auto-shutoff — Severity A

**Where:** `case IRTimerOFF` (remote handler) vs. BLE `case TIMER` code-0 branch.

Found 2026-08-22, not in the original review. The BLE path clears
`AutoPowerState.FlagAutoPower = 0` directly when cancelling a timer. The remote
path only cleared `IRControl.FlagAutoPower` and `AutoPowerState.ShutDowntime` —
**never** `AutoPowerState.FlagAutoPower`.

Since `AutoPowerControl()` (runs every tick) keeps incrementing the countdown as
long as `AutoPowerState.FlagAutoPower` stays `1`, and `ShutDowntime` had just
been zeroed by the same button press, the very next comparison
(`CurrentTime >= ShutDowntime`) was immediately true — triggering a real power-off
a few seconds after pressing Timer-OFF, not a genuine cancellation.

**Effect:** cancelling a sleep timer from the remote appeared to do nothing, then
the fan powered itself off shortly after — the opposite of what the button
should do.

**Status: FIXED, 2026-08-22, confirmed working.**
```c
case IRTimerOFF:
{
    IRControl.FlagAutoPower = 0;
    AutoPowerState.ShutDowntime = 0;
    AutoPowerState.FlagAutoPower = 0;   // added — mirrors the BLE path
    send_remote_response(TIMER, TIMEROFF);
    break;
}
```

---

## 13. Exiting Reverse after Nature resets speed to 1, not the prior speed — Severity B

**Where:** Nature's own entry (`case BOOST`'s `NATURE` branch, and remote
`case IRNatureWind`) both call `SetSpeed(1)`; both Reverse handlers (`REVERSE_MODE`
in `case BOOST`, and remote `case IRReverse`) never call `SetSpeed()` at all.

Found 2026-08-24, immediately after item 4 was fixed — this bug was already
present but masked by item 4's symptom (the display looked wrong for a
different, more obviously-broken reason).

`SetSpeed()` overwrites `mcFRState.OldTargetSpeed` — the value `get_mc_state()`
reports as "current speed" — not just the live `TargetSpeed`. So the moment
Nature is engaged, whatever speed was running before is gone from firmware's
memory permanently; nothing preserved it anywhere. Neither Reverse handler
calls `SetSpeed()` on either the "enter" or "exit" (toggle-back) press, so
neither can restore anything even if the old value still existed.

**Effect:** Nature → Reverse → exit Reverse (via the physical remote) lands on
speed `1` instead of whatever speed was active before Nature started.

**Why the app side looks fine:** the app never relies on firmware's memory for
this — its own `_exitReverse` sends its *locally cached* pre-Nature speed
explicitly in the exit frame, because the app's cached speed field is never
overwritten while a mode is active (no `0x04` frame ever arrives during Nature).
The remote has no equivalent — a physical button press can't supply "the old
speed," only firmware can, and firmware discarded it.

**Fix identified, NOT applied — explicitly declined, current behavior
accepted as-is:**
1. New global `uint8 preNatureSpeed = 3;`
2. At both Nature-entry points, before their `SetSpeed(1)` call:
   `preNatureSpeed = (mcFRState.OldTargetSpeed >= 1 && mcFRState.OldTargetSpeed <= 6) ? mcFRState.OldTargetSpeed : 3;`
3. In both Reverse handlers, capture `NatureFlage` before clearing it, and
   restore on the toggle-back-to-forward transition only:
   ```c
   uint8 wasNature = IRControl.NatureFlage;
   direction ^= 0x01;
   if (direction) {
       MoveReverse();
   } else {
       MoveForward();
       if (wasNature) SetSpeed(preNatureSpeed);
   }
   ```

Leaving this open on record in case priorities change later.

---

## What we would most like fixed

In order of value to the app, as of 2026-08-24:

1. **Bug 3** — one line. Removes the app's local Reverse tracking and the ban on
   retrying BLE writes.
2. **Bug 1** — one line. `case SPEED` still doesn't clear `smart_mode`; the app's
   power-ON workaround is solid but a real fix removes the extra frame entirely.
3. **Bug 5** — makes every payload size checksum the same way, and makes the
   vendor-documented Motor State frame work. Matters more now that the timer
   frame is 3 bytes, not less.
4. **Bug 13** — quality-of-life for remote-only users; explicitly deprioritized
   for now.

Bugs 2, 4, and 12 (sleep timer, Nature exit, remote Timer-OFF false shutoff) are
now fixed. Of the three originally reported field faults — Reverse, Smart, and
Nature — Nature is now fully fixed at the firmware level, Smart is fixed via an
app-side workaround pending the one-line firmware fix, and Reverse still
depends on the app's local tracking (bug 3) since firmware still can't report
which direction it landed on.
