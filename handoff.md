# Terraton BLDC Fan BLE Controller — Project Handoff

**App version:** 3.0.19+49  
**Branch:** `main`  
**Last commit:** `9be06f0` — fix: Smart/Boost mutual exclusivity + atomic Machine-State restore on reconnect  
**Platform:** Android only (minSdk 21)  
**Flutter SDK:** >=3.8.0 <4.0.0  

---

## Product Overview

Android Flutter app that controls a Terraton BLDC ceiling fan over BLE v5.2 via an Amp'ed RF BLE60 module. Fan control is fully offline over BLE — no network required. HTTP calls are non-essential: an anonymous launch ping, an opt-in once-per-day usage upload (Wi-Fi only), and the OTA update check — all to a Cloudflare Worker.

```
Flutter App --BLE v5.2--> BLE60 Module --UART1--> Fan MCU --> BLDC Motor
```

The app writes framed packets to the Write Characteristic; the fan responds on the Notify Characteristic. The BLE60 is a transparent UART bridge that only flushes to the MCU when it receives `\r\n` (0x0D 0x0A), which `writeFrame()` appends automatically.

---

## Repository Layout

```
terraton_fan_app/
  lib/
    main.dart                          — startup sequence
    app.dart                           — TerratorApp widget (theme, router)
    core/
      ble/
        ble_constants.dart             — ALL BLE UUIDs (single source of truth)
        ble_service.dart               — BleService abstract + BleServiceImpl
        ble_connection_state.dart      — BleConnectionState enum
        ble_frame_builder.dart         — typed facade over CommandLoader
        ble_response_parser.dart       — frame parser → typed fields
      commands/
        command_loader.dart            — loads assets/commands.yaml; static singleton
      appliances/
        appliance_loader.dart          — loads assets/appliances.yaml
      config/
        app_feature_config.dart        — runtime feature flags from app_config.yaml
      storage/
        objectbox_store.dart           — initObjectBox() / global `store`
        fan_repository.dart            — FanDevice + FanState persistence
        usage_log_repository.dart      — UsageLog persistence
        daily_runtime_repository.dart  — DailyRuntime persistence (NEW)
        app_settings.dart              — userName + tariff (JSON file)
      providers.dart                   — all Riverpod providers
      background/
        ble_foreground_service.dart    — Android foreground notification
      upload/
        device_ping_service.dart       — anonymous Cloudflare ping
        data_upload_service.dart       — opt-in daily usage upload
        usage_summary_builder.dart     — builds upload payload
      update/
        app_update_service.dart        — OTA check (tester variant only)
      diagnostics/
        crash_log_service.dart         — persists Flutter/async errors to disk
    features/
      splash/       — SplashScreen (permission check + 2 s delay)
      home/         — HomeScreen (IndexedStack shell), FansListScreen, ApplianceTypesScreen
      control/      — ControlScreen, _FanControlsPanel, CircularSpeedDial, ModeControlWidget,
                      TimerControlWidget, LightingControlWidget, ConnectionBanner
      analytics/    — AnalyticsScreen + AnalyticsCalculations
      onboarding/   — ProfileSetupScreen, BleScanScreen, QrScanScreen, NameFanScreen
      permission/   — BlePermissionScreen
      settings/     — SettingsScreen, UserManualScreen, ServiceQrModal
      legal/        — PrivacyPolicyScreen, TermsScreen, LegalScreen
      coming_soon/  — ComingSoonScreen
      update/       — UpdateDialog
    models/
      fan_device.dart      — ObjectBox entity
      fan_state.dart       — ObjectBox entity
      usage_log.dart       — ObjectBox entity
      daily_runtime.dart   — ObjectBox entity (NEW)
      appliance.dart
      usage_summary.dart
    shared/
      theme.dart           — all design tokens (kYellow, kBg, kCard, etc.)
      app_routes.dart      — AppRoutes constants + kDemoDeviceId
      app_config.dart      — kIsClientVariant compile-time flag
      router.dart          — GoRouter config + goToOnboarding()
      brand_mark.dart      — Terraton logo crop widget
  assets/
    commands.yaml          — ALL BLE command bytes (single source of truth)
    appliances.yaml        — appliance config (tester variant)
    appliances_client.yaml — appliance config (client variant, fans only)
    app_config.yaml        — feature flags
  test/
    unit/    — pure Dart tests (no Flutter, no ObjectBox native)
    widget/  — widget tests (mocktail mocks for BLE + repos)
```

---

## Key Design Tokens (`lib/shared/theme.dart`)

Never hardcode hex colours in widget files. Always use tokens:

| Token | Value | Purpose |
|---|---|---|
| `kBg` | `0xFF000000` | Screen background |
| `kSurface` | `0xFF0E0E0E` | Modal/sheet background |
| `kCard` | `0xFF141414` | Card background |
| `kYellow` | `0xFFFFEC00` | Primary accent |
| `kText` | `0xFFF4F4F2` | Primary text |
| `kTextMut` | `0xFF9A9A95` | Muted text |
| `kGreen` | `0xFF7AE582` | Status/connected |
| `kRed` | `0xFFFF6B6B` | Error/disconnected |

---

## BLE Protocol

### Frame format

**Request:** `[0x55, 0xAA, 0x06, <cmd>, <len>, ...data, <checksum>]`  
**Response:** same but byte[2] = `0x07`  
**Checksum:** `(0x55 + 0xAA + packetId + cmd + dataLen + Σdata) & 0xFF`  
**Flush terminator:** BLE60 flushes to MCU only on `\r\n` — `writeFrame()` appends automatically.

### Special fixed frames (non-standard — do NOT pass through `buildFrame()`)

| Frame | Hex | Notes |
|---|---|---|
| Status poll | `55 AA 00 00 01 00 00` | Every 3 s; returns 0x23 watts + 0x24 RPM |
| Get Motor State | `55 AA 00 01 01 00 01` | Sent on connect; returns 3 frames (power, speed/mode, timer) |
| Query Runtime | `55 AA 00 08 01 00 08` | Sent on connect + every 90 s; response: `55 AA 07 08 02 HH LL CRC`; `runtime = (HH<<8\|LL) * 5` seconds |

### Verified command frames

| Operation | Frame (hex) |
|---|---|
| Power ON | `55 AA 06 02 01 01 09` |
| Power OFF | `55 AA 06 02 01 00 08` |
| Speed 1–6 | `55 AA 06 04 01 0N checksum` |
| Boost | `55 AA 06 21 01 01 28` |
| Nature | `55 AA 06 21 01 02 29` |
| Reverse | `55 AA 06 21 01 03 2A` (hardware toggle) |
| Smart | `55 AA 06 21 01 04 2B` |
| Timer OFF/2H/4H/8H | `55 AA 06 22 01 00/02/04/08 28/2A/2C/30` |
| Query Power (watts) | `55 AA 06 23 01 00 29` |
| Query Speed (RPM) | `55 AA 06 24 01 00 2A` |

### Response command bytes

| Byte | Meaning |
|---|---|
| `0x02` | Power on/off (`data[0] == 0x01` = on) |
| `0x04` | Speed 1–6 |
| `0x21` | Mode (`0x01`=boost, `0x02`=nature, `0x03`=reverse, `0x04`=smart) |
| `0x22` | Timer code |
| `0x23` | Watts (`data[0]`) |
| `0x24` | RPM (`(data[0]<<8) | data[1]`; checksum quirk: accept correct±1) |
| `0x08` | Runtime (`(data[0]<<8 | data[1]) * 5` seconds) |

### BLE UUIDs (`lib/core/ble/ble_constants.dart` — single source of truth)

| Purpose | UUID |
|---|---|
| Scan filter (advertisement) | `00001827-0000-1000-8000-00805f9b34fb` (BLE Mesh Proxy) |
| Write characteristic | `00002adb-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data In) |
| Notify characteristic | `00002adc-0000-1000-8000-00805f9b34fb` (Mesh Proxy Data Out) |

Service discovery also searches (first match wins): Amp'ed RF proprietary (26cc3fc2/26cc3fc1 and alt variants), CC254X/HM-10 (0000ffe1), Nordic UART Service, Microchip RN4870.

### BLE service connection rules

- **Do NOT call `startScan()` before `connect()`** — it clears `_scanCache`, destroying the live `BluetoothDevice` needed for BLE address type resolution.
- The BLE60 uses a **random BLE address**. `BluetoothDevice.fromId(mac)` guesses public type. Always use the live device from `_scanCache` on first connection; `fromId()` is fine for reconnects after Android has cached the address type.
- One fan at a time — single active BLE connection.

---

## ObjectBox Entities

### `FanDevice`
- `deviceId` — stable primary key (`@Unique`). QR mode: from QR payload. BLE scan mode: set to macAddress on first save.
- `macAddress` — starts empty; filled by `FanRepository.updateMac()` on first successful BLE connection.
- `nickname`, `model`, `fwVersion`, `addedAt`, `lastConnectedAt`
- `isServiceAccess`, `serviceExpiresAt` — for temporary service-technician access entries (self-delete on expiry)

### `FanState`
- Keyed by `deviceId` (`@Unique`)
- `speed` (0=unknown, 1–6), `isBoost`, `activeMode` (null|"nature"|"smart"|"reverse"), `activeTimerCode`, `timerActivatedAt`, `isPowered`, `lastWatts`, `lastRpm`, `lastRuntimeSecs`
- `lastLightColorType`, `lastLightBrightness`, `lastLightIsOn` — lighting UI state (commands pending from Terraton)
- Open-segment bookkeeping fields (excluded from `==`/`hashCode`): `openSegmentStart`, `openSegmentGear`, `openSegmentMode`, `openSegmentSmartBaseline`, `openSegmentWattsSum/Count`, `openSegmentRpmSum/Count`
- `copyWith()` uses `T? Function()?` pattern for nullable fields (pass `() => null` to explicitly null them)

### `UsageLog`
- One record per mode/speed change. Fields: `deviceId`, `startTime`, `durationSecs`, `gear`, `watts`, `rpm`, `mode`, `smartBaselineGear`
- `kwh` getter: `watts * durationSecs / 3_600_000`
- Pruned to 365 days at startup

### `DailyRuntime` (NEW in commit `95fd838`)
- One record per fan per calendar day
- `deviceId` (`@Index`), `date` (local midnight; `@Property(type: PropertyType.date)`), `runtimeSecs`
- Written on every firmware runtime-poll response (90 s interval) via upsert
- Never treat as zero — missing days are filled with the average of available days

---

## Riverpod Providers (`lib/core/providers.dart`)

| Provider | Type | Notes |
|---|---|---|
| `packageInfoProvider` | `FutureProvider<PackageInfo>` | |
| `userNameProvider` | `AsyncNotifierProvider<UserNameNotifier, String>` | Persisted to `app_settings.json` |
| `bluetoothAdapterStateProvider` | `StreamProvider<BluetoothAdapterState>` | |
| `bleServiceProvider` | `Provider<BleService>` | Singleton `BleServiceImpl`; disposes on scope exit |
| `bleConnectionStateProvider` | `StreamProvider<BleConnectionState>` | |
| `fanRepositoryProvider` | `Provider<FanRepository>` | Singleton backed by ObjectBox `store` |
| `usageLogRepositoryProvider` | `Provider<UsageLogRepository>` | Singleton backed by ObjectBox `store` |
| `dailyRuntimeRepositoryProvider` | `Provider<DailyRuntimeRepository>` | Singleton backed by ObjectBox `store` |
| `savedFansProvider` | `FutureProvider<List<FanDevice>>` | Invalidate with `ref.invalidate(savedFansProvider)` after any write |
| `connectedFanDeviceIdProvider` | `StateProvider<String?>` | Set by `_ControlScreenState` on connect; cleared in `dispose()` |
| `activeFanStateProvider` | `NotifierProvider.autoDispose.family<ActiveFanStateNotifier, FanState, String>` | Keyed by `deviceId`; mutate only via named methods |

**Riverpod 2.x constraint:** `ref.read()` is forbidden inside `dispose()`. Cache needed controllers in `initState()` as fields. Example: `_connectedFanCtrl = ref.read(connectedFanDeviceIdProvider.notifier);`

### `ActiveFanStateNotifier` key methods

| Method | Effect |
|---|---|
| `updatePower(bool)` | Sets `isPowered` |
| `updateSpeed(int)` | Sets `speed` |
| `updateMode(String?)` | Handles boost/nature/smart/reverse coexistence rules |
| `updateTimer(int, {DateTime?})` | Sets timer; `activatedAt` only set by UI taps, not BLE responses |
| `updateWatts(int)` / `clearWatts()` | Watts telemetry |
| `updateRpm(int)` / `clearRpm()` | RPM telemetry |
| `updateRuntime(int)` | Persists `lastRuntimeSecs` |
| `resetOnConnect()` | Clears all volatile fields; Motor State response restores within ~100 ms |
| `applyMotorStatePowerOff()` | Atomically clears all state when Motor State frame [1] = OFF |
| `applyMotorStateTruth(String?)` | Motor State frame [2] exclusive truth: sets one mode, clears all others |
| `setBoostActive(bool)` | Toggle boost; nature blocks activation; activating clears an active Smart (mutually exclusive), preserves Reverse (may coexist) |
| `setActiveMode(String?)` | Set/clear non-boost mode; nature and smart both clear boost, reverse preserves it |

---

## Control Screen (`lib/features/control/control_screen.dart`)

### Startup sequence (post-connect)
1. `resetOnConnect()` — clears stale volatile state (including the persisted timer, so a stale value can't flash)
2. `_startTelemetry()` — 3 s status-poll timer (watts + RPM)
3. `_subscribeNotify()` — listens to `notifyStream`
4. `_startRuntimePoll()` — 90 s runtime-query timer
5. `_scheduleConnectPolls()` — sends getMotorState and retries (every 1.5 s, up to 4 retries) until a real reply lands; NOT a single one-shot `writeFrame` (a rebooted MCU after a mains power-cycle may drop the first query)
6. `writeFrame(BleFrameBuilder.queryRuntime())` — seeds today's daily runtime

### Key guards

**`_recentlyPoweredOn` flag:** set `true` for 1500 ms after any Power ON command. Suppresses incoming `power=false` BLE frames so a stale Motor State response (queued before the powerOn reaches the fan) cannot override the user-initiated optimistic `isPowered=true`.

**Motor State detection (spontaneous remote frames):** A getMotorState response always contains a timer frame (`0x22`). Status-poll responses never contain a timer. `isMotorStateResponse = responses.any((r) => BleResponseParser.parseTimer(r) != null)`. This live-dispatch path (with its frame [2] gate — skip speed/mode when frame [1] said power=OFF) still handles a spontaneous remote frame we didn't request.

**Machine State assembly (replies to polls WE sent):** for the getMotorState reply to `_scheduleConnectPolls`, `_scheduleWakePolls`, or the 90 s mode-poll, frames are instead buffered (`_msPower`/`_msSpeed`/`_msMode`/`_msTimer`) and applied atomically by `_flushMachineState()` once complete or after a 300 ms debounce — because the BLE60/MCU may split or reorder the 3 frames across notifications (most commonly right after a mains power-cycle reboot), which the old same-notification frame-gate would silently drop. A power=ON reply with no speed/mode yet is treated as incomplete and the retry loop keeps polling.

**`controlsEnabled = enabled && fanState.isPowered`** — the outer `IgnorePointer` only blocks taps when disconnected. When connected but powered off, taps still reach `_FanControlsPanel` so `_ensurePoweredOn()` can auto-power the fan.

**`_ensurePoweredOn()`** (called by boost + mode buttons): reads state; if not powered, calls `updatePower(true)` optimistically + sends powerOn frame, then proceeds with the actual action.

### Boost behavior
- Boost is activation-only (no toggle-off from the app; the fan's own toggle doesn't apply to boost).
- Nature mode blocks boost activation (`setBoostActive(bool on)` returns early if `activeMode == 'nature'`).
- Boost and Smart are mutually exclusive — activating either clears the other (enforced in `ActiveFanStateNotifier`, not the UI handlers). Boost and Reverse may coexist.
- `_preNatureSpeed` stored in `_FanControlsPanelState` — seeded from ObjectBox on init; used to restore speed when leaving Nature.

### Nature mode exit paths
1. → Smart or Reverse: send mode frame FIRST, then speed frame (min 3 for Smart)
2. → Boost: skip speed restore; clear Nature, activate Boost
3. Toggle off (tap same mode): send speed frame only, no mode frame

### Reverse mode
Hardware toggle model: first `0x03` enters Reverse, second exits. When `parseModeString` returns `'reverse'` and `activeMode == 'reverse'`, the response is an exit toggle → call `setActiveMode(null)`.

### App lifecycle (disconnect on background)
- `paused`: cancel all timers, `BleForegroundService.stop()`, `_ble.disconnect()`
- `resumed`: if not connected, call `_connect()`
- `inactive`/`hidden`/`detached`: no-op
- Demo mode skips all lifecycle handling

### Runtime poll → daily runtime persistence
```dart
// In _subscribeNotify(), after parseRuntimeSeconds():
notifier.updateRuntime(runtimeSecs);
final now = DateTime.now();
ref.read(dailyRuntimeRepositoryProvider).upsertForDate(
  widget.fan.deviceId,
  DateTime(now.year, now.month, now.day),  // local calendar midnight
  runtimeSecs,
);
```

### Motor State polling (mode-dependent)
`_updateMotorStatePoll()` starts/stops a 90 s `_motorStateTimer` when the fan is ON and in Smart/Nature/Reverse mode. This keeps UI state in sync with hardware as these modes change speed autonomously. Its poll is sent via `_requestMotorState()`, so the reply goes through the same Machine State assembly (buffer + atomic flush) as the connect/wake polls above.

### Service access
`FanDevice.isServiceAccess = true` entries self-delete on `serviceExpiresAt`. The debug `_DebugCard` (raw BLE frame viewer) is only shown to service-access users. Service entries are excluded from backup export.

---

## Analytics System

### `AnalyticsCalculations` (`lib/features/analytics/analytics_calculations.dart`)
Pure static math — no Flutter imports. Key methods:

- `normalizeDailyRuntimes(records, from, to)` — fills missing days with avg of available days; denominator = `records.length` (not total days)
- `rangeKwh(records, from, to, gearWatts)` — total kWh for a date range
- `chartKwh(records, from, to, gearWatts, {splitDay})` — per-point kWh list; `splitDay:true` splits one day into 6 × 4-hour buckets
- `efficiency(logs)` — Smart Mode efficiency vs baseline; returns 0–100 int
- `efficiencyLabel(pct)` — "Excellent Efficiency" ≥80, "Optimal Range" ≥60, "Moderate Efficiency" ≥40, "Low Efficiency" >0, else "No Data Yet"

### Power profile (verified)
```dart
static const _kGearWatts = [0, 4, 7, 10, 15, 21, 28]; // index = gear (0 unused)
static const _kBoostWatts = 33;
static const _kTraditionalW = 85;  // baseline for efficiency comparison
```

### `DailyRuntimeRepository` (`lib/core/storage/daily_runtime_repository.dart`)
- `upsertForDate(deviceId, date, runtimeSecs)` — find-and-update-or-insert (firmware reports cumulative daily runtime; each poll overwrites with the latest value)
- `getRange(deviceId, from, to)` — inclusive date range query
- Uses `_use<T,R>(Query<T>, fn)` pattern to guarantee `q.close()` in finally block
- Date comparison uses `millisecondsSinceEpoch`; `_sameDay()` helper for Dart-side comparison

### Analytics screen (`_rangeFromTo()`)
```dart
// Day  → (today, today)
// Week → (today - 6 days, today)
// Month N → (DateTime(now.year, now.month - (N-1), 1), today)
```
Chart axis labels for Day range: 12AM / 4AM / 8AM / 12PM / 4PM / 8PM (6 buckets).

---

## Commands YAML (`assets/commands.yaml`)

Single source of truth for all BLE command bytes. Adding a new command:
1. Add entry to `commands.yaml`
2. Add named method to `BleFrameBuilder` calling `CommandLoader.*`
3. No other Dart changes needed

Currently `null` (pending from Terraton): all lighting commands.

**Phase 2 (approved, not yet built):** Remote command loading — fetch `commands.yaml` from a hosted URL on launch, compare `version` field, update local cache if newer, fall back to bundled asset on failure.

---

## Startup Sequence (`main.dart`)

1. `FlutterError.onError` + `platformDispatcher.onError` → `CrashLogService.record()`; `ErrorWidget.builder` overridden with dark-theme error screen
2. Lock to portrait orientation
3. `CommandLoader.load()` — loads `assets/commands.yaml`
4. `ApplianceLoader.load()` — loads appliance YAML
5. `AppFeatureConfig.load()` — runtime feature flags
6. Register non-fan appliance control widgets (tester variant only)
7. `initObjectBox()` — opens ObjectBox store
8. `_ensureBluetoothOn()` — Android only; `FlutterBluePlus.turnOn()` if adapter is off
9. Prune usage logs older than 365 days (best-effort)
10. Fire-and-forget: `DevicePingService.ping()`, `DataUploadService.tryUpload()`
11. `runApp(ProviderScope(TerratorApp()))`

---

## App Variants

Controlled by `--dart-define=APP_VARIANT=client|tester` (default: `tester`).

| Feature | tester | client |
|---|---|---|
| Water/Air/Energy appliance categories | ✅ | ❌ |
| OTA update feature | ✅ | ❌ |
| Non-fan YAML sections | ✅ | ❌ |

`kIsClientVariant = kAppVariant == 'client'` — checked in `main.dart` and relevant screens.

---

## Router (`lib/shared/router.dart`)

Initial location: `/splash`. All routes defined in `appRouter` (global `GoRouter`).

| Route constant | Path | Notes |
|---|---|---|
| `AppRoutes.splash` | `/splash` | 2 s delay, permission check |
| `AppRoutes.home` | `/` | `HomeScreen` — IndexedStack shell |
| `AppRoutes.applianceTypes` | `/appliance-types` | Expects `ApplianceCategory` as `extra` |
| `AppRoutes.fans` | `/fans` | Expects optional `ApplianceType` as `extra` |
| `AppRoutes.scanBle` | `/scan/ble` | BLE scan; 15 s timeout |
| `AppRoutes.scanQr` | `/scan/qr` | Reads `device_id`, `model`, `fw_version` from QR JSON |
| `AppRoutes.nameFan` | `/name-fan` | Requires `FanDevice` as `extra`; redirect to `/` if null |
| `AppRoutes.control` | `/control` | Requires `FanDevice` as `extra`; redirect to `/` if null |
| `AppRoutes.settings` | `/settings` | |

**`kDemoDeviceId = '__demo__'`** defined in `app_routes.dart`; imported by `control_screen.dart`, `fan_card.dart`, `qr_scan_screen.dart`.

---

## Home Screen Architecture (`lib/features/home/home_screen.dart`)

`HomeScreen` is an `IndexedStack` shell with a floating bottom nav:
- **Tab 0 — Analytics** (`AnalyticsScreen`)
- **Tab 1 — Home** (`_HomeTab`) — greeting, "Fans" tile → `FansListScreen`
- **Tab 2 — Settings** (`SettingsScreen`)

`FansListScreen` (`/fans`) is a separate route pushed from the Home tab. Status badges wired to `bleConnectionStateProvider` + `connectedFanDeviceIdProvider`.

---

## `CircularSpeedDial` (`lib/features/control/circular_speed_dial.dart`)

- 6 dots + tick marks on a ring (radius 110dp, canvas 320dp square)
- `_DialPainter` (CustomPainter): dark core circle, thin track ring, yellow arc when `speed > 1`, dots with bloom glow for selected state
- `_dotStateOf()` — single source of truth for dot state; used by BOTH painter and hit-area logic
- Hit areas: 48dp `GestureDetector` (meets accessibility minimum) centered on each dot; `HitTestBehavior.opaque`
- `shouldRepaint` uses `setEquals(old.disabledSpeeds, disabledSpeeds)` from `foundation.dart`
- Nature mode: `isNature: true` disables all dots, shows a leaf icon in the centre

---

## Testing

### Test file locations
- `test/unit/` — pure Dart; use `_FakeRepo` (in-memory) to avoid ObjectBox native library
- `test/widget/` — mocktail mocks for `BleService`, `FanRepository`, `UsageLogRepository`, `DailyRuntimeRepository`

### Critical widget test patterns

**`dailyRuntimeRepositoryProvider` must be overridden** in every widget test that touches `AnalyticsScreen` or `HomeScreen` (which includes `AnalyticsScreen` in its `IndexedStack`). Failing to override causes `StateError('Call initObjectBox() before accessing store.')`.

```dart
class _MockDailyRuntimeRepo extends Mock implements DailyRuntimeRepository {}

// In setUpAll:
registerFallbackValue(DailyRuntime(deviceId: '', date: DateTime(0), runtimeSecs: 0));
registerFallbackValue(DateTime.now());

// In ProviderScope overrides:
dailyRuntimeRepositoryProvider.overrideWithValue(dr),
```

**`StreamProvider` needs 4 pump cycles** to deliver a connection state change:
`pump()` ×2, add stream event, `pump()` ×2

**`CircularSpeedDial` hit testing:** `tester.tap()` is intercepted by the overlaid Column. Invoke `dial.onSpeedSelected(n)` directly.

**`LightingControlWidget` and boost button** sit below the 600 px test viewport. Use `tester.widget<...>(find.byType(...))` and call callback directly.

**`_BoostButton`** is a `StatefulWidget` (owns `_shimmerCtrl`); find via `ValueKey('boost_button')` on its outer `GestureDetector`.

**Power-gate:** `controlsEnabled = enabled && fanState.isPowered` — tests that check dial or boost state must emit a power-on BLE response frame first.

**`CommandLoader.load()` must be called in `setUpAll`** for widget tests.

### Run commands (from `terraton_fan_app/`)

```powershell
# Analyze
rtk flutter analyze --no-fatal-infos

# All tests
rtk flutter test

# Single file
rtk flutter test test/unit/analytics_calculations_test.dart

# Regenerate ObjectBox + Riverpod code (after changing any model)
rtk dart run build_runner build --delete-conflicting-outputs
```

**Important:** Never chain `flutter analyze` + `flutter test` in a single invocation — it OOMs the machine (past incident causing forced restart). Run them separately.

---

## Hard Constraints

1. UUID constants live **only** in `ble_constants.dart` — never duplicated
2. Command bytes live **only** in `assets/commands.yaml` — never hardcoded in Dart
3. All BLE writes go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()`
4. ObjectBox only for fan data — no Hive, no Isar, no SharedPreferences
5. Android only — no iOS build
6. Single active BLE connection — one fan at a time
7. Fan control is fully offline over BLE — never gate fan operation on network
8. Design tokens from `lib/shared/theme.dart` — no hardcoded hex colours in widget files
9. `ref.read()` is forbidden inside `dispose()` — cache providers in `initState()` as fields
10. Do NOT call `startScan()` before `connect()` — it clears `_scanCache`

---

## Recent Commits (last 10)

```
9be06f0  fix: Smart/Boost mutual exclusivity + atomic Machine-State restore on reconnect
c85807d  feat: robust motor-state polling on wake/connect; unify home nav
e4256fb  chore: bump version to 3.0.19+49
f381b8c  chore: bump version to 3.0.18+48
0aa8c8b  chore: bump version to 3.0.17+47
7395238  chore: bump version to 3.0.16+46
95fd838  feat: replace runtime estimation with per-day firmware runtime tracking
5d0f0b4  fix: clear stale speed/mode on reconnect when fan is OFF
bd7b8c1  feat: boost auto power-on guard, mode buttons activation-only
3f4b6d9  chore: bump version to 3.0.15+45
```

---

## Pending / Open Items

### Phase 2 — Remote command loading (approved, not yet built)
Fetch `commands.yaml` from a hosted URL on launch. Compare `version` field, update local cache if newer, fall back to bundled asset on failure. No Dart command-handling code changes needed.

### Lighting commands (pending from Terraton)
Commands YAML has `lighting.on`, `lighting.off`, `lighting.color_temp` all set to `null`. `LightingControlWidget` shows the UI but the BLE frames return `null` from `CommandLoader`. When Terraton supplies the bytes, add them to `commands.yaml` only — no Dart changes needed.

### Known Issues
All audit findings from 2026-05-23 have been resolved:
- Fan card light-theme hardcoded colours — N/A (file removed, absorbed into `fans_list_screen.dart`)
- Status badge not wired to provider — Fixed 2026-05-24
- Async work in `.then()` callback — Fixed 2026-05-24
- Splash screen hardcoded version string — Fixed (reads `packageInfoProvider`)

---

## Build Script

Run from repo root (not `terraton_fan_app/`):

```powershell
.\build.ps1
```

Saves APK to `builds/` and publishes to GitHub Releases.
