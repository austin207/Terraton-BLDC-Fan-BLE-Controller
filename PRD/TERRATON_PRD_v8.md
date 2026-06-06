# Terraton Fan Controller — Product Reference Document v8

> **Type:** Living architecture reference — reflects actual codebase as of 2026-06-05
> **Branch:** `feature/config-driven-appliances` (pending hardware test → merge to `main`)
> **App version:** 3.0.0+30
> **Platform:** Android only
> **Flutter SDK:** ≥3.41.0 · Dart SDK: ≥3.8.0 <4.0.0

---

## 1. Product Overview

### 1.1 What it is

An Android Flutter app that controls Terraton home appliances over BLE v5.2 via the Amp'ed RF BLE60 module. Currently active category: BLDC ceiling fans. Water filtration, air purification, and energy/storage categories are scaffolded — pending BLE command bytes from Terraton.

```
Flutter App --BLE v5.2--> BLE60 Module --UART1--> Appliance MCU --> Load
```

Fully offline. No user accounts, no cloud sync, no HTTP in Phase 1. Anonymous usage analytics are uploaded once per day over Wi-Fi if the user opts in (see §10).

### 1.2 BLE60 Bridge Notes

- Transparent UART bridge: the BLE60 buffers incoming BLE writes and flushes to the MCU only when it receives `\r\n` (0x0D 0x0A). `BleService.writeFrame()` appends these bytes automatically.
- Allows only **one GATT connection at a time**. A second `connect()` attempt returns GATT error 133 ("in use by another device"). The app uses this as its "is someone else connected?" check — no separate probe.
- The BLE60 uses a **random BLE address**. `BluetoothDevice.fromId(mac)` guesses public type; this is fine for reconnects after Android caches the address type. First connection **must** use the live device from the scan cache (never `fromId`).

---

## 2. App Identity

| Field | Value |
|---|---|
| Package name | `com.terraton.terraton_fan_app` |
| Version | `3.0.0+30` |
| Min SDK | 23 |
| Compile SDK | 36 |
| Target SDK | Flutter default (35/36) |
| Dart constraint | `>=3.8.0 <4.0.0` |

---

## 3. Architecture

### 3.1 Data Flow

```
assets/commands.yaml ──► CommandLoader (singleton, loaded in main.dart)
assets/appliances.yaml ─► ApplianceLoader (singleton, loaded in main.dart)
                                │
                                ▼
                          BleFrameBuilder ◄── typed facade; returns null for null commands
                                │
                                ▼
                       BleService (abstract)
                       BleServiceImpl (flutter_blue_plus)
                          connect(mac) ──► GATT → service discovery → char setup
                          writeFrame() ──► appliance hardware (+0D 0A flush terminator)
                          notifyStream ◄── appliance hardware
                                │
                                ▼
                       BleResponseParser → ActiveFanStateNotifier (Riverpod)
                                │
                                ▼
                       FanRepository (ObjectBox) — FanDevice + FanState
                       UsageLogRepository (ObjectBox) — energy segments (analytics)
```

### 3.2 Startup Sequence (`lib/main.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `GoogleFonts.config.allowRuntimeFetching = false` — offline fonts only
3. Global error handlers: `FlutterError.onError`, `platformDispatcher.onError`; `ErrorWidget.builder` overridden with dark-theme error screen
4. `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])` — portrait lock
5. `CommandLoader.load()` — parses `assets/commands.yaml` into static singleton
6. `ApplianceLoader.load()` — parses `assets/appliances.yaml` into static `List<ApplianceCategory>`
7. `ControlRegistry.register(...)` — three registrations: `'water_quality'`, `'air_quality'`, `'energy_metrics'`
8. `initObjectBox()` — opens ObjectBox store at `<documents>/terraton-ob/`
9. `_ensureBluetoothOn()` — Android only; `FlutterBluePlus.turnOn()` if adapter is off; errors silently swallowed
10. `unawaited(DevicePingService.ping())` — anonymous heartbeat; fire-and-forget
11. `unawaited(DataUploadService.tryUpload(...))` — daily usage upload if opted in
12. `runApp(ProviderScope(child: TerratorApp()))` — Riverpod root; permissions checked inside `SplashScreen`

### 3.3 Folder Structure (`lib/`)

```
lib/
├── main.dart
├── app.dart
├── objectbox.g.dart               — generated (build_runner)
├── core/
│   ├── ble/                       — BLE constants, service, frame builder, parser, connection state
│   ├── commands/                  — CommandLoader: YAML command loading singleton
│   ├── appliances/                — ApplianceLoader: appliances.yaml loading singleton
│   ├── storage/                   — ObjectBox store + fan/usage-log repositories + app settings
│   ├── upload/                    — DataUploadService, DevicePingService, UsageSummaryBuilder
│   ├── update/                    — AppUpdateService: OTA APK update from GitHub Releases
│   ├── background/                — BleForegroundService: Android foreground notification
│   └── providers.dart             — all Riverpod providers
├── models/
│   ├── fan_device.dart            — @Entity
│   ├── fan_state.dart             — @Entity
│   ├── usage_log.dart             — @Entity
│   ├── usage_summary.dart         — upload payload DTO
│   └── appliance.dart             — ApplianceCategory, ApplianceType (from YAML)
├── features/
│   ├── splash/                    — SplashScreen (breathing aura animation, version footer)
│   ├── permission/                — BlePermissionScreen
│   ├── onboarding/                — QrScanScreen, BleScanScreen, NameFanScreen, ProfileSetupScreen
│   ├── home/                      — HomeScreen (IndexedStack shell), FansListScreen, ApplianceTypesScreen
│   ├── control/                   — ControlScreen + all sub-widgets; ControlRegistry; appliance control widgets
│   ├── analytics/                 — AnalyticsScreen
│   ├── settings/                  — SettingsScreen, UserManualScreen, ServiceQrModal
│   ├── legal/                     — PrivacyPolicyScreen, TermsScreen, LegalScreen
│   └── update/                    — UpdateDialog
└── shared/
    ├── router.dart                — GoRouter instance + goToOnboarding() helper
    ├── app_routes.dart            — AppRoutes constants + kDemoDeviceId = '__demo__'
    ├── theme.dart                 — design tokens (kBg, kYellow, kCard, kText, etc.)
    └── brand_mark.dart            — BrandMark widget with pixel-accurate crop logic
```

---

## 4. BLE Layer

### 4.1 BLE Constants (`ble_constants.dart`)

**Scan filters (both used):**
- `kAdvServiceUUID  = "00001827-0000-1000-8000-00805f9b34fb"` — BLE Mesh Proxy (primary)
- `kServiceUUID     = "26cc3fc0-6241-f5b4-5347-63a3097f6764"` — Amp'ed RF proprietary (secondary)

**Service discovery — priority order, first match wins:**

| Priority | Write characteristic | Notify characteristic |
|---|---|---|
| 1 | `00002adb-…` (Mesh Proxy Data In) | `00002adc-…` (Mesh Proxy Data Out) |
| 2 | `26cc3fc2-…` (Amp'ed RF unit 1 write) | `26cc3fc1-…` (Amp'ed RF unit 1 notify) |
| 3 | `bf8796f1-…-09bb46d79101` (unit 2 write) | `bf8796f1-…-09bb46d79100` (unit 2 notify) |
| 4–6 | CC254X/HM-10, Nordic NUS, Microchip RN4870 fallbacks | (same services) |

`setNotifyValue(true)` is called on the notify characteristic after discovery.

### 4.2 BleService Public API

```dart
abstract class BleService {
  Future<void>  startScan({int timeoutSeconds = 10});
  Future<void>  stopScan();
  Future<String> connect(String mac);        // 3 retries × 5 s; returns MAC
  Future<void>  disconnect();
  Future<void>  writeFrame(List<int> frame); // appends [0x0D, 0x0A]
  Future<void>  dispose();

  Stream<List<int>>           get notifyStream;
  Stream<BleConnectionState>  get connectionStateStream;
  BleConnectionState          get currentState;
  Stream<List<DiscoveredFan>> get scanResultsStream;
  String?                     get connectedMacAddress;
  String                      get writeCharStatus;   // diagnostic
  String                      get connectStatus;     // diagnostic
}
```

**Important:** never call `startScan()` before `connect()` — it clears `_scanCache`, destroying the live `BluetoothDevice` that holds the correct BLE address type.

### 4.3 BLE Frame Structure

```
[0x55][0xAA][packetId][command][dataLen][...data][checksum]
```

- **Request** packet ID: `0x06`
- **Response** packet ID: `0x07`
- **Checksum:** `(0x55 + 0xAA + packetId + command + dataLen + Σdata) & 0xFF`
  — the full header bytes `0x55` and `0xAA` are included in the sum.

### 4.4 Verified Fan Command Frames

| Operation | Frame (hex) | Checksum derivation |
|---|---|---|
| Status Poll | `55 AA 00 00 01 00 00` | Fixed non-standard frame |
| Power ON | `55 AA 06 02 01 01 09` | 55+AA+06+02+01+01=0x109→09 |
| Power OFF | `55 AA 06 02 01 00 08` | 55+AA+06+02+01+00=0x108→08 |
| Speed 1 | `55 AA 06 04 01 01 0B` | 55+AA+06+04+01+01=0x10B→0B |
| Speed 2 | `55 AA 06 04 01 02 0C` | …→0C |
| Speed 3 | `55 AA 06 04 01 03 0D` | …→0D |
| Speed 4 | `55 AA 06 04 01 04 0E` | …→0E |
| Speed 5 | `55 AA 06 04 01 05 0F` | …→0F |
| Speed 6 | `55 AA 06 04 01 06 10` | …→10 |
| Boost | `55 AA 06 21 01 01 28` | 55+AA+06+21+01+01=0x128→28 |
| Nature | `55 AA 06 21 01 02 29` | …→29 |
| Reverse | `55 AA 06 21 01 03 2A` | …→2A |
| Smart | `55 AA 06 21 01 04 2B` | …→2B |
| Timer OFF | `55 AA 06 22 01 00 28` | 55+AA+06+22+01+00=0x128→28 |
| Timer 2H | `55 AA 06 22 01 02 2A` | …→2A |
| Timer 4H | `55 AA 06 22 01 04 2C` | …→2C |
| Timer 8H | `55 AA 06 22 01 08 30` | …→30 |
| Query Power (W) | `55 AA 06 23 01 00 29` | 55+AA+06+23+01+00=0x129→29 |
| Query Speed (RPM) | `55 AA 06 24 01 00 2A` | …→2A |

### 4.5 Status Poll Response Frames (hardware-verified)

The status poll is a **non-standard fixed frame** (`55 AA 00 00 01 00 00`). It always produces **exactly 2 response frames**:

| Response | Frame bytes | Notes |
|---|---|---|
| Watts (fan OFF) | `55 AA 07 23 01 00 2A` | `data[0] = 0x00` → 0 W |
| Watts (fan ON, speed 6) | `55 AA 07 23 01 05 2F` | `data[0] = 0x05` → 5 W |
| RPM (fan OFF) | `55 AA 07 24 02 00 00 2B` | 2-byte big-endian, 0 RPM |
| RPM (fan ON, speed 6) | `55 AA 07 24 02 01 7E AA` | `(0x01<<8)|0x7E` = 382 RPM; checksum is `correct-1` (known quirk) |

**Firmware limitation:** power state (`0x02`) and speed gear (`0x04`) are **not** included in poll responses. Firmware developer has been notified. Power and speed state are only known from command echo frames after explicit writes.

**RPM checksum quirk:** `_checksumOk()` in `BleResponseParser` accepts both `computed` and `computed-1` for cmd `0x24`.

### 4.6 Response Byte Dispatch

`BleResponseParser.parseAll()` scans the full byte array for all complete response frames (hardware sometimes concatenates multiple). The control screen dispatches on command byte:

| Byte | Parser method | Notifier method |
|---|---|---|
| `0x02` | `parsePowerState()` | `updatePower(bool)` |
| `0x04` | `parseSpeed()` | `updateSpeed(int)` |
| `0x21` | `parseModeString()` | `setActiveMode(String?)` |
| `0x22` | `parseTimer()` | `updateTimer(int)` |
| `0x23` | `parsePowerWatts()` | `updateWatts(int)` |
| `0x24` | `parseRpm()` | `updateRpm(int)` |

**Reverse mode toggle:** if a `0x21` response arrives with mode `'reverse'` and the current fan state is already `activeMode == 'reverse'`, the control screen calls `setActiveMode(null)` instead — hardware uses toggle semantics.

---

## 5. Command & Config System

### 5.1 `assets/commands.yaml` Structure

```
version: "1.0"
protocol                    ← shared header/packet-ID constants
status_poll                 ← fixed non-standard frame (fan only)

# ── 1. FAN / COOLING (active, hardware-verified) ──────────────────────────
commands                    ← power, speed, modes, timers, queries, lighting
response_commands           ← 0x02…0x24 byte mappings

# ── 2–8. Pending appliances (null templates) ──────────────────────────────
water_ro                    ← RO Filter
water_uf_uv                 ← UF/UV Filter
air_aqm                     ← AQM Monitor
air_purifier                ← Air Purifier
energy_solar                ← Solar
energy_battery              ← Battery Storage
energy_power_conversion     ← Power Conversion
```

Fan commands are at the root `commands:` key. Pending sections use their own root keys (e.g. `water_ro:`, `air_aqm:`). Access via `CommandLoader.custom(['water_ro', 'commands', 'power'], data)`.

**Currently null** (pending from Terraton): all lighting bytes (`commands.lighting.*`), all 7 non-fan appliance sections entirely.

### 5.2 `CommandLoader` Public API

| Method | Description |
|---|---|
| `load()` | Async; call once in `main.dart` before `runApp` |
| `buildFrame(int? cmd, List<int>? data)` | Builds framed request; returns null if either arg is null |
| `statusPoll()` | Returns fixed `[0x55,0xAA,0x00,0x00,0x01,0x00,0x00]` |
| `power(String action)` | 'on' / 'off' |
| `speed(int step)` | 1–6 |
| `mode(String action)` | 'boost' / 'nature' / 'reverse' / 'smart' |
| `timer(String action)` | 'off' / '2h' / '4h' / '8h' |
| `queryPower()` / `querySpeed()` | Query frames (cmd 0x23 / 0x24) |
| `lightOn()` / `lightOff()` / `lightColorTemp(int)` | Returns null (pending) |
| `custom(List<String> path, List<int>? data)` | Generic accessor for any YAML path |
| `responseCommand(String key)` | Looks up response byte by name |

`_safeGet()` returns null gracefully for missing paths — no crash for pending commands.

### 5.3 `assets/appliances.yaml` — Categories & Types

| Category | ID | Types | Controls |
|---|---|---|---|
| Fans | `fans` | ceiling_fan (CF×21), table_fan (TF×21), pedestal_fan (PF×21), wall_fan (WF×21), exhaust_fan (EF×21) | speed, mode, timer, lighting (ceiling only); speed, mode, timer (others); speed, timer (exhaust) |
| Water Filtration | `water_filtration` | ro_filter (RO×10), uf_uv_filter (UV×10) | `water_quality` |
| Air Purification | `air_purification` | aqm_monitor (AQ×10), air_purifier (AP×10) | `air_quality` |
| Energy / Storage | `energy_storage` | solar (SL×10), battery_storage (BA×10), power_conversion (PC×10) | `energy_metrics` |

Model IDs auto-generated as `TN-<PREFIX>-01` through `TN-<PREFIX>-N`. Icon PNGs for non-fan categories are pending — `errorBuilder` fallbacks use Material icons (water_drop / air / bolt).

### 5.4 `ControlRegistry`

Maps control-type strings to widget builder functions. Built-in types (`speed`, `mode`, `timer`, `lighting`, `power`) are rendered natively by `_FanControlsPanel`. All others are looked up here.

```dart
typedef ControlWidgetBuilder = Widget Function(ControlBuildParams params);

// ControlBuildParams fields: device, fanState, enabled, ref, config
ControlRegistry.register('water_quality', buildWaterFiltrationControl);
ControlRegistry.register('air_quality',   buildAirPurificationControl);
ControlRegistry.register('energy_metrics', buildEnergyStorageControl);
```

---

## 6. Data Models

### 6.1 `FanDevice` (ObjectBox `@Entity`)

| Field | Type | Notes |
|---|---|---|
| `id` | `int` | `@Id()` |
| `deviceId` | `String` | `@Unique()` — stable primary key |
| `macAddress` | `String` | Empty until first BLE connection; filled by `updateMac()` |
| `model` | `String` | From QR payload; empty for BLE-scan-onboarded fans |
| `nickname` | `String` | User-defined |
| `fwVersion` | `String` | From QR payload |
| `addedAt` | `DateTime` | Default `DateTime.now()` — **not** `late` |
| `lastConnectedAt` | `DateTime?` | Set by `updateMac()` on each connection |
| `isServiceAccess` | `bool` | Field-technician QR bypass; default false |
| `serviceExpiresAt` | `DateTime?` | Used when `isServiceAccess == true` |

### 6.2 `FanState` (ObjectBox `@Entity`)

| Field | Type | Notes |
|---|---|---|
| `id` | `int` | `@Id()` |
| `deviceId` | `String` | `@Unique()` |
| `speed` | `int` | 0 = unknown; 1–6 = step |
| `isBoost` | `bool` | |
| `activeMode` | `String?` | `'nature'` \| `'smart'` \| `'reverse'` \| null |
| `activeTimerCode` | `int?` | `0x02` \| `0x04` \| `0x08` \| null |
| `isPowered` | `bool` | |
| `lastWatts` | `int?` | Cleared after 5 s without poll response |
| `lastRpm` | `int?` | Cleared after 5 s without poll response |
| `lastLightColorType` | `String` | `'warm'` \| `'neutral'` \| `'cool'`; default `'warm'` |
| `lastLightBrightness` | `double` | 0.0–1.0; default 0.7 |
| `lastLightIsOn` | `bool` | default false |

Has `==`, `hashCode`, and a full `FanStateCopyWith` extension.

### 6.3 `UsageLog` (ObjectBox `@Entity`)

| Field | Type | Notes |
|---|---|---|
| `id` | `int` | `@Id()` |
| `deviceId` | `String` | |
| `startTime` | `DateTime` | |
| `durationSecs` | `int` | |
| `gear` | `int` | 1–6; 0 = off |
| `watts` | `int` | 0 = no reading |
| `mode` | `String?` | |

Computed: `double get kwh` = `watts * durationSecs / 3_600_000` (0 if watts=0 or gear=0).

---

## 7. Riverpod Providers (`lib/core/providers.dart`)

| Provider | Type | What it provides |
|---|---|---|
| `packageInfoProvider` | `FutureProvider<PackageInfo>` | App version / build number |
| `userNameProvider` | `AsyncNotifierProvider<UserNameNotifier, String>` | User name, persisted to `app_settings.json` |
| `bluetoothAdapterStateProvider` | `StreamProvider<BluetoothAdapterState>` | Live BT adapter state |
| `bleServiceProvider` | `Provider<BleService>` | Singleton `BleServiceImpl` |
| `bleConnectionStateProvider` | `StreamProvider<BleConnectionState>` | From `bleServiceProvider.connectionStateStream` |
| `fanRepositoryProvider` | `Provider<FanRepository>` | Singleton `FanRepositoryImpl(store)` |
| `usageLogRepositoryProvider` | `Provider<UsageLogRepository>` | Singleton `UsageLogRepositoryImpl(store)` |
| `savedFansProvider` | `FutureProvider<List<FanDevice>>` | `getAllFans()`; invalidate after every write |
| `activeFanStateProvider` | `NotifierProvider.autoDispose.family<…, FanState, String>` | FanState keyed by `deviceId`; autoDispose |

**`ActiveFanStateNotifier` named methods:**
`update`, `updatePower`, `updateSpeed`, `updateMode`, `updateTimer`, `updateWatts`, `updateRpm`, `clearWatts`, `clearRpm`, `setBoostActive`, `setActiveMode`, `updateLighting({colorType, brightness, isOn})`

**Riverpod 2.x constraint:** `ref.read()` is forbidden inside `dispose()`. Cache services in `initState()`.

---

## 8. Screens & Routes

### 8.1 Route Map

| Route | Screen | Extra |
|---|---|---|
| `/splash` | SplashScreen | — |
| `/permission-required` | BlePermissionScreen | — |
| `/profile-setup` | ProfileSetupScreen | — |
| `/` | HomeScreen (IndexedStack shell) | — |
| `/appliance-types` | ApplianceTypesScreen | `ApplianceCategory` |
| `/fans` | FansListScreen | `ApplianceType?` |
| `/scan/ble` | BleScanScreen | — |
| `/scan/qr` | QrScanScreen | — |
| `/name-fan` | NameFanScreen | `FanDevice` (redirect to `/` if null) |
| `/control` | ControlScreen | `FanDevice` (redirect to `/` if null) |

Routes `/name-fan` and `/control` always use `redirect:` when `extra` is null — never a fallback widget in `builder`.

`goToOnboarding(context)` shows a bottom sheet with two options: **Bluetooth pairing** → `/scan/ble`; **QR code pairing** → `/scan/qr`. Both paths are always available (no compile-time toggle).

### 8.2 Home Screen Architecture

`HomeScreen` is an `IndexedStack` with three tabs and a floating `_BottomNav` (sliding yellow pill):
- **Tab 0 — Analytics:** `AnalyticsScreen` — kWh/cost/efficiency/per-fan breakdown from `UsageLogRepository`
- **Tab 1 — Home:** Greeting, `_ApplianceCategoryTile` grid (YAML-driven), `_UsageCard` (mock, Phase 2)
- **Tab 2 — Settings:** `SettingsScreen`

`FansListScreen` (`/fans`) is pushed from Home; receives `ApplianceType?` and filters `savedFansProvider` results accordingly.

### 8.3 Onboarding Flows

**QR Pairing (`/scan/qr`):**
- `MobileScanner` full-screen with animated scan line and torch toggle
- Normal payload: requires `device_id`, `model`, `fw_version` → navigate to `/name-fan`
- Service access payload (`type == 'service_access'`): creates `FanDevice` with `isServiceAccess=true` and `macAddress` pre-filled → navigate directly to `/control`
- Invalid QR: SnackBar, scanner stays open

**BLE Pairing (`/scan/ble`):**
- `BleService.startScan()` with 15 s timeout; streams `scanResultsStream`
- Already-paired MACs show "Reconnect" badge → navigate directly to `/control`
- New device → navigate to `/name-fan`

---

## 9. Control Screen

### 9.1 Widget Tree

```
Scaffold (kBg)
  AppBar — nickname + _ConnStatusLabel + _BluetoothIndicator
  body: Stack
    SingleChildScrollView
      Column
        [isServiceAccess] _ServiceAccessBanner (HH:MM countdown)
        _PowerButton (56dp circle; green/red/grey + glow)
        IgnorePointer/AnimatedOpacity (0.45 opacity when !controlsEnabled)
          _FanControlsPanel (ConsumerStatefulWidget)
            CircularSpeedDial     (if 'speed' in controls)
            ModeControlWidget     (if 'mode')
            BoostButton           (if 'mode')
            TimerControlWidget    (if 'timer')
            LightingControlWidget (if 'lighting')
            ControlRegistry.*     (for custom control types)
    [disconnected] ConnectionLostCard (bottom overlay)
    [_showDisconnectAlert] _DisconnectAlertOverlay
```

`controlsEnabled = enabled && fanState.isPowered` — controls are dimmed and blocked when fan is off.

### 9.2 Telemetry

- Polls every **3 seconds** via `Timer.periodic`
- Sends the non-standard `statusPoll()` fixed frame — NOT `queryPower()` + `querySpeed()` separately
- Response: always 2 frames (`0x23` watts + `0x24` RPM)
- Power state and speed are NOT in poll responses (firmware limitation; developer notified)
- Stale clearing: no `0x23` response in 5 s → `clearWatts()`; same for `0x24` → `clearRpm()`

### 9.3 App Lifecycle: Disconnect / Reconnect

`_ControlScreenState` implements `WidgetsBindingObserver`:

| State | Action |
|---|---|
| `paused` | Cancel telemetry timer → `BleForegroundService.stop()` → `_ble.disconnect()` |
| `resumed` | If `currentState != connected`: call `_connect()` |
| `inactive / hidden / detached` | No-op |

`connect()` fails gracefully with "in use by another device" if another phone holds the fan — this IS the "is someone else using it?" check. No separate probe.

### 9.4 Nature Mode State Machine

State: `_preNatureSpeed: int` on `_FanControlsPanelState`. Seeded in `initState()` from ObjectBox.

**BLE frame order is critical — mode frame must precede speed frame:**

| Exit path | Frames sent | Notes |
|---|---|---|
| Nature → Smart | `setSmart()` then `setSpeed(max(3, _preNatureSpeed))` | Min 3 for Smart |
| Nature → Reverse | `setReverse()` then `setSpeed(_preNatureSpeed)` | No optimistic mode update; BLE echo drives toggle detection |
| Nature → Boost | `setBoost()` only | Skip speed restore |
| Toggle off (tap Nature again) | `setSpeed(current)` only | No mode frame |

### 9.5 Demo Mode

`_isDemo = (fan.deviceId == kDemoDeviceId)` where `kDemoDeviceId = '__demo__'` (`app_routes.dart`).
When true: `_connect()` skipped; `_send()` calls `_applyDemoFrame(frame)` which parses the outgoing request frame and dispatches to notifier methods — simulating hardware echo. All lifecycle BLE callbacks skipped.

### 9.6 Foreground Service

`BleForegroundService` (MethodChannel `'com.terraton/bg_service'`):
- `start(label)` — called on power-on echo (shows speed label)
- `update(label)` — called on watts response
- `stop()` — called on power-off echo, on `paused` lifecycle, and in `dispose()`

---

## 10. Analytics & Cloud Upload

### 10.1 Analytics Screen

Reads `UsageLogRepository`. Usage segments flushed by `_FanControlsPanelState._flushSegment()` on every mode/speed change.

Displays: kWh, ₹ cost (editable tariff, persisted), avg watts vs 85 W traditional baseline, efficiency ring chart, per-fan bar chart. Range selector: Day / Week / Month.

Efficiency baseline: `_traditionalWatts = 85.0 W` (hardcoded constant — not yet config-driven).

### 10.2 Cloudflare Worker (`cloudflare/worker.js`)

Deployed as `terraton-ingest` with R2 bucket `terraton-usage-data` and two KV namespaces.

**`POST /ping`** — anonymous heartbeat, no auth, no opt-in:
- Payload: `{ device_hash: sha256(installId).substring(0,16), app_version }`
- Fired once per app launch; failure silently swallowed

**`POST /upload`** — daily usage summary, requires `Authorization: Bearer <UPLOAD_API_KEY>`:
- Gating: key non-empty AND user opt-in AND Wi-Fi only AND only past completed days
- IP rate-limited: 20/hour via `RATE_LIMIT_KV`; body size guard: 10 KB
- Stores to R2: `uploads/<period>/<hash>_<timestamp>.json`

**`UPLOAD_API_KEY` security:** never committed. Injected at build time via `--dart-define=UPLOAD_API_KEY=<secret>` in `build.ps1`, which reads from gitignored `secrets.env`.

`UsageSummary` fields: period, deviceHash, gearDist, modeDist, hourlyUsage, avgSessionMins, sessions, totalKwh, avgWatts, tempMaxC/Min, humidityPct (from Open-Meteo, Kerala coordinates 10.5°N/76.27°E), tariffPerKwh, ksebSlab, monthlyKwhEst.

---

## 11. Build System

### 11.1 `build.ps1` Steps (run from repo root)

1. Load `secrets.env` → extract `UPLOAD_API_KEY`
2. Version bump: prompt [P]atch / [N]inor / [M]ajor / [S]kip; bumps `pubspec.yaml`, increments build number
3. Clear `builds/*.apk`
4. Kill stale `dart`, `java`, `flutter`, `adb` processes; pause OneDrive
5. `flutter clean`
6. Delete `android/.gradle/`
7. `flutter pub get`
8. `dart run build_runner build --delete-conflicting-outputs`
9. **`flutter test --no-pub`** — **build aborts if any test fails**
10. `flutter build apk --release --split-per-abi --dart-define="UPLOAD_API_KEY=$key"` → arm64-v8a, armeabi-v7a, x86_64
11. Copy APKs to `builds/` (timestamped + fixed-name)
12. Write `builds/version.json` (UTF-8 no-BOM)
13. Delete existing `latest` GitHub Release; create new with fixed-name APKs + `version.json`
14. If version bumped: commit `pubspec.yaml` + `pubspec.lock`; push
15. Restart OneDrive

### 11.2 OTA Updates

`AppUpdateService.checkForUpdate()` fetches `version.json` from the `latest` GitHub Release, compares with current `PackageInfo` build number, and shows `UpdateDialog` if newer. Fixed APK URL pattern: `terraton-fan-<arch>.apk`.

---

## 12. Tests

### 12.1 Unit Tests (`test/unit/`)

| File | Coverage |
|---|---|
| `command_loader_test.dart` | All 19 frame byte values; checksum includes 0x55+0xAA; null for pending |
| `ble_frame_builder_test.dart` | All BleFrameBuilder methods |
| `ble_response_parser_test.dart` | All parse methods; RPM checksum quirk (accepts `correct-1`) |
| `fan_repository_test.dart` | All CRUD + importFromJson validation |
| `fan_state_test.dart` | Equality, hashCode, copyWith |
| `fan_device_test.dart` | Field defaults, service access fields |
| `usage_log_test.dart` | `kwh` computed property |
| `usage_log_repository_test.dart` | CRUD, range queries, `pruneBefore` |
| `app_settings_test.dart` | Read/write persistence |
| `active_fan_state_notifier_test.dart` | All notifier methods, Nature/Boost interaction |

### 12.2 Widget Tests (`test/widget/`)

`control_screen_test.dart`, `fans_list_screen_test.dart`, `home_screen_test.dart`, `ble_scan_screen_test.dart`, `qr_scan_screen_test.dart`, `analytics_screen_test.dart`, `settings_screen_test.dart`, `mode_control_widget_test.dart`, `timer_control_widget_test.dart`, `connection_banner_test.dart`, `ble_permission_screen_test.dart`, `user_manual_screen_test.dart`, `profile_setup_screen_test.dart`, `name_fan_screen_test.dart`, `generate_icon_test.dart`

### 12.3 Test Infrastructure Notes

- `_FakeRepo` — in-memory `FanRepository` (avoids ObjectBox native lib in unit tests)
- `CommandLoader.load()` must be called in `setUpAll` for any test touching BLE frames
- `StreamProvider` requires **4 pump cycles** for connection-state delivery: `pump()×2` → emit event → `pump()×2`
- `CircularSpeedDial` stacks 6 `GestureDetector`s at same centre — call `dial.onSpeedSelected(n)` directly
- `_BoostButton` found via `ValueKey('boost_button')` on outer `GestureDetector`
- Boost/lighting sit below 600 px test viewport — obtain via `tester.widget<T>(find.byType(T))`
- Power gate: emit power-on BLE response frame before testing dial or boost state

---

## 13. Hard Constraints

- UUID constants live only in `ble_constants.dart` — never duplicated
- Command bytes live only in `assets/commands.yaml` — never hardcoded in Dart
- All BLE writes go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()`
- ObjectBox only for fan data — no Hive, no Isar, no SharedPreferences for fan data
- Android only — no iOS build
- Single active BLE connection — one fan at a time
- `UPLOAD_API_KEY` must never appear in committed source files — injected via `--dart-define` at build time only
- Design tokens only from `lib/shared/theme.dart` — no hardcoded hex colours in widget files
- Do not modify `gradle.properties` or Android build infrastructure without explicit user instruction
- **Merge to `main` is blocked until hardware testing passes**

---

## 14. Pending Items

| Priority | Item | Blocker |
|---|---|---|
| HIGH | Firmware: add `0x02` power state and `0x04` speed to status poll responses | Firmware developer (notified) |
| HIGH | Firmware: fix timer display bug | Firmware developer (sent fix instructions) |
| MEDIUM | Icon PNG assets for non-fan appliance categories (10 files) | Terraton design team |
| LOW | BLE command bytes for water/air/energy appliances (7 sections in `commands.yaml`) | Terraton hardware team |
| LOW | Lighting command bytes (`commands.lighting.*`) | Terraton |
| LOW | Home screen "Today's Usage" card — wire `_UsageCard` to real `UsageLogRepository` data | Internal |
| LOW | Open-Meteo weather coordinates hardcoded for Kerala — parameterise for other regions | Internal |

---

## 15. Phase 2 Plans

### 15.1 Remote Command Loading (approved, not yet built)

Fetch `commands.yaml` from a hosted URL on app launch, compare `version` field, write local cache, fall back to bundled asset on failure. Enables BLE command updates without an app release. Planned URL: `https://raw.githubusercontent.com/terraton/fan-app-config/main/commands.yaml` or equivalent. `CommandLoader` is designed for this — Phase 1 uses only `rootBundle`.

### 15.2 Today's Usage Card

`_UsageCard` in `home_screen.dart` currently shows `'—'` placeholder values. `UsageLogRepository` is fully functional — this is a UI wiring task only.

---

## 16. Non-Goals (current scope)

- iOS build
- Voice commands (hardware VC10 chip feature — not an app concern)
- Cloud sync or user accounts
- Wi-Fi control
- Fan firmware OTA from this app
- Smart home integration (Alexa, Google Home)
- Scheduling / automation
- Push notifications
- Multi-user collaboration
