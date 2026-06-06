# Architecture

Fan control is fully offline over BLE — no network is required to operate a fan.
The only HTTP calls are non-essential: an anonymous launch ping, an opt-in
once-per-day usage upload (Wi-Fi only), and the OTA update check — all to a
Cloudflare Worker.

---

## Data flow

```text
assets/commands.yaml
        │
        ▼
  CommandLoader            ← loaded once at startup; static singleton
        │
        ▼
  BleFrameBuilder          ← typed facade; returns null for pending/unknown commands
        │
        ▼
  BleService / BleServiceImpl   (flutter_blue_plus)
        │  connect(mac) ────► GATT connect → service discovery → char setup
        │  writeFrame()  ──► fan hardware  (+0D 0A BLE60 flush terminator)
        │  notifyStream  ◄── fan hardware
        ▼
  BleResponseParser → ActiveFanStateNotifier (Riverpod)
        │
        ▼
  FanRepository (ObjectBox)      ← persists FanDevice + FanState
  UsageLogRepository (ObjectBox) ← persists per-session energy segments
        │
        ▼
  UsageSummaryBuilder            ← aggregates daily logs into a feature vector
        │
        ▼
  DataUploadService              ← async upload to Cloudflare Worker (opt-in)
```

See [BLE_PROTOCOL.md](BLE_PROTOCOL.md) for the wire format.

---

## Startup sequence (`main.dart`)

1. Global error handlers — `FlutterError.onError`, `platformDispatcher.onError`,
   and a dark-theme `ErrorWidget.builder`.
2. `CommandLoader.load()` + `ApplianceLoader.load()` — load YAML config.
3. Register non-fan control widgets — **tester variant only** (see
   [BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md#variants)).
4. `initObjectBox()` — open the store; prune usage logs older than a year.
5. `_ensureBluetoothOn()` — Android-only; turns the adapter on if off (permission
   errors are swallowed — `BlePermissionScreen` handles retry).
6. Fire-and-forget `DevicePingService.ping()` and `DataUploadService.tryUpload()`.
7. `runApp(ProviderScope(TerratorApp()))` — permission check runs inside
   `SplashScreen` after a 2 s hold, then routes to `/profile-setup` or `/home`.

---

## State management

- **Riverpod 2.x** — `NotifierProvider.autoDispose.family<…, String>` keyed by
  `deviceId` for per-fan live state; `FutureProvider` for the saved fan list;
  `AsyncNotifierProvider` for the user name. Mutate state only through the named
  `update*` / `set*` methods on `ActiveFanStateNotifier`.
- **Navigation** — GoRouter with typed constants in `AppRoutes`. The `nameFan` and
  `control` routes require a `FanDevice` via `extra` and guard `null` with a
  `redirect:` (never a fallback widget in `builder`).
- **Storage** — ObjectBox only: `FanDevice` (identity/metadata), `FanState`
  (last-known control state), `UsageLog` (energy segments), `UsageSummary` (daily
  upload vector). `objectbox.g.dart` is generated — run `build_runner` after model
  changes.

> **Riverpod constraint:** `ref.read()` is forbidden inside `dispose()`. Cache any
> needed service in a field during `initState()`.

---

## Nature mode state machine

```text
Idle ──────────────── tap Nature ──────────► Nature active
                      saves _preNatureSpeed    speed dial locked
                                               all modes inactive

Nature active ─── tap Smart/Reverse ──────► mode active
                   mode frame FIRST           speed restored (min 3 for Smart)
                   then speed frame

Nature active ─── tap Boost ──────────────► Boost active
                                             speed NOT restored
                                             Nature cleared silently
```

The BLE mode frame is **always** sent before the speed frame when exiting Nature —
the hardware ignores speed commands while Nature is active.

---

## Connection lifecycle

The BLE60 allows only **one** GATT connection at a time and stops advertising while
connected. `ControlScreen` is a `WidgetsBindingObserver`:

- **`paused`** (screen off / backgrounded): cancel telemetry, stop the foreground
  service, and `disconnect()` — freeing the fan for another phone.
- **`resumed`**: reconnect unless already connected. `connect()` fails gracefully
  with an `in use by another device` status (GATT 133) when another phone holds the
  fan, so resume never steals an active connection.

Demo mode (`deviceId == '__demo__'`) bypasses all BLE calls and applies frames
locally.

---

## Telemetry & analytics

- Live watts/RPM polled every 3 s; stale values cleared after 5 s. See the
  [status-poll section](BLE_PROTOCOL.md#status-poll-2-frame-vs-4-frame-response)
  for the 2-frame vs 4-frame behaviour.
- Usage segments are flushed on every mode/speed change and on app pause/close,
  using a running average of poll responses (not a point-in-time sample).
- The Analytics screen shows kWh / cost / efficiency with Day / Week / Month views.
  The **Month** view has a 1–6 month range selector that uses calendar-month
  boundaries (1st of the start month → yesterday) with true daily graph points and
  an equal-length previous-period comparison.

---

For the full file-by-file layout, see [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).
