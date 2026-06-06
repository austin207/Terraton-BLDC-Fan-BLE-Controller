# Project Structure

```text
terraton_fan_app/
├── assets/
│   ├── commands.yaml             # Single source of truth for all BLE command bytes
│   ├── appliances.yaml           # Tester variant: all appliance categories
│   ├── appliances_client.yaml    # Client variant: fans only
│   ├── icon/  icons/  logos/  fonts/
├── lib/
│   ├── app.dart                  # TerratorApp root; re-prompts BT enable mid-session
│   ├── main.dart                 # Entry point: error handlers, loaders, ObjectBox, runApp
│   ├── core/
│   │   ├── appliances/appliance_loader.dart   # Loads appliances*.yaml per variant
│   │   ├── background/ble_foreground_service.dart
│   │   ├── ble/
│   │   │   ├── ble_constants.dart             # All UUID constants (only location)
│   │   │   ├── ble_connection_state.dart
│   │   │   ├── ble_frame_builder.dart         # Typed facade — null for pending commands
│   │   │   ├── ble_response_parser.dart       # Validates frames; parseAll() multi-frame
│   │   │   └── ble_service.dart               # scan / connect / disconnect / write
│   │   ├── commands/command_loader.dart       # YAML singleton; buildFrame(); statusPoll()
│   │   ├── providers.dart                     # All Riverpod providers + ActiveFanStateNotifier
│   │   ├── storage/                           # app_settings, fan_repository, objectbox_store, usage_log_repository
│   │   ├── update/app_update_service.dart     # OTA check + download + installer handoff
│   │   └── upload/                            # data_upload_service, device_ping_service, usage_summary_builder
│   ├── features/
│   │   ├── analytics/                         # kWh / cost / efficiency; Day/Week/Month (+1–6mo range)
│   │   ├── coming_soon/                       # Placeholder for non-fan appliance types
│   │   ├── control/                           # control_screen + dial, modes, timer, lighting, registry
│   │   ├── home/                              # home_screen, fans_list, appliance/fan type screens
│   │   ├── legal/                             # privacy_policy, terms, shared legal_screen
│   │   ├── onboarding/                        # ble_scan, qr_scan, name_fan, profile_setup
│   │   ├── permission/ble_permission_screen.dart
│   │   ├── settings/                          # settings_screen, service_qr_modal, user_manual
│   │   ├── splash/splash_screen.dart
│   │   └── update/update_dialog.dart
│   ├── models/                                # fan_device, fan_state, usage_log, usage_summary, appliance, fan_type
│   └── shared/                                # app_config, app_routes, router, theme, brand_mark, icons
├── android/app/src/main/kotlin/.../           # MainActivity + TerraBgService (foreground service)
├── test/unit/   test/widget/                  # see TESTING.md
└── objectbox.g.dart                           # Generated — run build_runner to regenerate
```

---

## Hard constraints

| Constraint | Rule |
| --- | --- |
| UUID constants | Live **only** in `ble_constants.dart` — never duplicated |
| Command bytes | Live **only** in `assets/commands.yaml` — never hardcoded in Dart |
| BLE writes | Always go through `BleFrameBuilder` → `CommandLoader` → `BleServiceImpl.writeFrame()` |
| Storage | ObjectBox only — no Hive, Isar, or SharedPreferences for fan data |
| Platform | Android only — no iOS build target |
| Connections | One fan at a time — single active BLE connection |
| Design tokens | Colours come from `lib/shared/theme.dart` (`kYellow`, `kBg`, …) — no hardcoded hex in widget files |
| Offline | Never gate fan operation on network — BLE control is fully offline |
| API key | `UPLOAD_API_KEY` injected via `--dart-define` at build time from a gitignored `secrets.env` — never committed |

---

## Dependencies

| Package | Purpose |
| --- | --- |
| `flutter_blue_plus` | BLE scan, connect, GATT write/notify |
| `mobile_scanner` | QR code scanning |
| `objectbox` / `objectbox_flutter_libs` | Local database |
| `flutter_riverpod` | State management |
| `go_router` | Declarative routing |
| `yaml` | `commands.yaml` / `appliances.yaml` parsing |
| `share_plus` / `file_picker` | JSON export / import |
| `permission_handler` | Runtime BT + camera permissions |
| `package_info_plus` | App version + OTA check |
| `path_provider` / `path` | Temp dir for APK download and export |
| `google_fonts` | Manrope + JetBrains Mono |
| `qr_flutter` | Service-access QR generation |
| `http` | Cloudflare upload + OTA check + APK download |
| `crypto` | SHA-256 dedup hash; device-ID anonymisation |
| `connectivity_plus` | Wi-Fi check before upload |
| `open_file` | Opens downloaded APK in the system installer |
