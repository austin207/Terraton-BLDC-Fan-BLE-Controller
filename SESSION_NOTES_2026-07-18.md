# Session Notes — 2026-07-18: MachineStateSync rewrite (attempt #7)

**Branch:** `rewrite/machine-state-sync` (branched from `wip/reconnect-state-restore` @ `7f3a11e`)
**Main commit:** `abbd7b9` — `rewrite: replace confirm-before-demote with MachineStateSync agreement engine`
**Version shipped for testing:** 3.0.27+57
**Status:** architecture verified by tests; **field verification pending the tester's Connection Log**. `main` stays untouched until the tester confirms.

---

## The bug

Field report (repeated across 6 releases, 3.0.19 → 3.0.26): tester sets Gear 4/5 + **Smart mode** + **2h Sleep Timer**, disconnects BLE, reconnects → the timer shows OFF and Smart resets. Six consecutive fixes to the "confirm-before-demote" guard failed, including 3.0.26+56 (`418110c`).

## Why the old design kept failing (architecture-level diagnosis)

1. **Every trust decision read an ObjectBox baseline** (`_isStateDemotion`) that any stray write could poison — a poisoned row silently *disabled* the guard. This is how fixes #1–#5 died; #6 closed one funnel into the baseline, not the dependence itself.
2. **The 3 s demotion-fallback timeout applied the very unconfirmed stale reply it was holding** — "no confirmation arrived" was converted into "apply the demotion". This is the most plausible cause of the 3.0.26 field failure.
3. **The 300 ms same-burst window was a heuristic** — a second stale OFF from the BLE60's backlog arriving later than 300 ms was treated as a confirmation.

Root physical cause throughout: the BLE60 buffers the MCU's UART output while no phone is connected and **flushes that stale backlog into every fresh connection**, with valid checksums, chunked at arbitrary byte boundaries.

## What was decided (user directives)

- **Stop patching; rewrite on a new branch** (`rewrite/machine-state-sync`).
- **Display philosophy: on reconnect, poll Machine State and render only what the fan returns.** Firmware is display truth; the UI stays blank until retrieval succeeds. Verified against Terraton's vendor PDFs + PRD before implementation.
- Coding delegated to Sonnet subagents with frozen-semantics specs; Fable acted as manager/reviewer.

## What was built (all in `abbd7b9`)

### 1. `MachineStateSync` engine — `lib/core/ble/machine_state_sync.dart`
Pure Dart (no Flutter/Riverpod/ObjectBox imports), fully unit-tested under a fake clock. Replaces the entire confirm-before-demote mechanism (~15 fields + 11 methods deleted from `control_screen.dart`).

**The agreement rule:** during a connect/wake session, a state applies **only** when two consecutively assembled replies agree on `(power, frame[2])` — timer compared only when both replies carry one — **and** the confirming reply's `querySeq` is strictly greater than the candidate's. A BLE60 backlog burst arrives stamped with one `querySeq`, so it can **never confirm itself**. No decision reads the DB baseline — the entire "poisoned baseline disables the guard" failure class is structurally gone.

**Unconfirmed is NEVER applied:** a session that hits its poll cap (6 polls, ~1.5 s apart) or hard timeout (12 s) with no agreement applies *nothing* — blank UI, 90 s poll retries later. Never reintroduce a timeout fallback that applies a held reply.

**Dual-checksum polling:** session polls alternate the lab-verified Get Motor State frame (`55 AA 00 01 01 00 01`) with the vendor-formula variant (`…00 02`, `get_motor_state_vendor` in `commands.yaml`) because the vendor doc computes a different checksum and newer field firmware could silently drop one variant. Assembly is shape-tolerant (`0x22` timer frame optional), matching the vendor doc's Status Check reply which carries no timer field.

### 2. Field-scoped persistence — `fan_repository.dart` + `providers.dart`
`FanRepository` gained `saveOperatingState` / `saveTimerState` / `saveTelemetry` / `saveLighting`; each notifier mutator persists only its own field group. A telemetry/runtime write is now structurally **unable** to touch `isPowered`/`activeMode` (kills the 2026-07-17 baseline-poisoning class). `resetOnConnect()` is pure in-memory display blanking — no persist call exists in its path. Deleted: `_restorePending`, `_toPersist`, `markRestored`, whole-row `update()` persist.

### 3. Transport ordering — `ble_service.dart`
Notify subscription cancelled on `disconnect()`; on `connect()` the old subscription is cancelled and the new listener attached **before** `setNotifyValue(true)` — the backlog flush can no longer land on a stale listener or race the assembler reset.

### 4. Parser tightening — `ble_response_parser.dart`
Checksum ±1 tolerance scoped to RPM (`0x24`) frames only; `parseTimer` accepts only `{0x00, 0x02, 0x04, 0x08}`.

### 5. Tests — 658 passing, analyze clean
- `test/unit/machine_state_sync_test.dart` — 12 engine tests under `fake_async` (backlog can't self-confirm, timeout applies nothing, poll alternation, split-reply debounce, user cancel, …).
- **`test/helpers/connection_log_replay.dart`** — replays a tester's Connection Log capture (`RX`/`TX` hex lines) byte-for-byte through the production pipeline (assembler → frame classification → engine) under a fake clock. `test/unit/connection_log_replay_test.dart` proves it with 3 synthetic captures (stale backlog OFF superseded; lone unconfirmed reply applies nothing; mid-frame split reassembles).
- Reworked `active_fan_state_notifier_test.dart`, `fan_repository_test.dart`, `control_screen_test.dart` to the new semantics.

### 6. Docs
- `CLAUDE.md` — confirm-before-demote sections replaced with the MachineStateSync design; six failed fixes kept as past-tense history.
- `TESTER_CONNECTION_LOG_INSTRUCTIONS.md` — new `MS` log-line explanation; note that a blank screen can now last up to ~12 s if the fan never confirms (and blank-screen-with-fan-still-spinning is itself diagnostic signal).

## Trade-off accepted deliberately

Every connect costs one extra poll round-trip (~200–300 ms) before state renders, versus applying the first reply optimistically. Firmware is display truth; the UI stays blank rather than showing a value that might be wrong.

## Next steps

1. Build 3.0.27+57 via `.\build.ps1` (tester variant) and ship to the tester.
2. Tester re-runs the repro (Smart + 2h timer → disconnect → reconnect, 2–3 times without clearing the log) and shares the Connection Log.
3. **Paste the capture into a test via `replayConnectionLog()`** — it becomes a permanent byte-for-byte regression test of that firmware's exact stream.
4. Merge to `main` only after the tester confirms. If the capture shows the firmware never reports Smart in frame [2] at all, that is a protocol gap for Terraton, not another app fix.
