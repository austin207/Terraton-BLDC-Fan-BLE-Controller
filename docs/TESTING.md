# Testing & Development

All commands run from `terraton_fan_app/`.

```powershell
flutter analyze --no-fatal-infos                 # static analysis
flutter test                                     # all tests
flutter test test/unit/ble_frame_builder_test.dart
flutter test test/widget/control_screen_test.dart
dart run build_runner build --delete-conflicting-outputs   # after model/provider edits
```

> Run `analyze` and `test` in **separate** invocations — chaining them in one
> command has caused out-of-memory restarts on the build machine.

The analyzer is configured strictly in `analysis_options.yaml`: `strict-casts`,
`strict-inference`, `strict-raw-types`, plus `unawaited_futures`,
`cancel_subscriptions`, `close_sinks`, `discarded_futures`, `avoid_print`, and
more. Committed code must analyze clean.

---

## Testing notes

- **Unit tests** use an in-memory `_FakeRepo` to avoid the ObjectBox native library.
- **Widget tests** mock `BleService` and `FanRepository` with mocktail;
  `CommandLoader.load()` must run in `setUpAll`.
- `StreamProvider` in widget tests needs **4 pump cycles** to deliver a connection
  state change: `pump()` ×2, add the stream event, `pump()` ×2.
- `CircularSpeedDial` stacks six `GestureDetector`s at one centre — `tester.tap()`
  is intercepted by the overlaid Column; call `dial.onSpeedSelected(n)` directly.
- Widgets below the 600 px test viewport (lighting, boost button) are obtained via
  `tester.widget<…>(find.byType(…))` and their callbacks invoked directly.
- Power-gate: `controlsEnabled = enabled && fanState.isPowered` — emit a power-on
  response frame before asserting dial/boost state.

---

## Unit tests

| File | Covers |
| --- | --- |
| `command_loader_test.dart` | YAML parsing; `buildFrame()` checksum; `statusPoll()`; null handling |
| `ble_frame_builder_test.dart` | All facades map to correct command bytes |
| `ble_response_parser_test.dart` | Frame validation; all `parse*` helpers |
| `active_fan_state_notifier_test.dart` | Power/speed/mode/boost/timer transitions; Nature blocks boost |
| `fan_repository_test.dart` | ObjectBox CRUD; `importFromJson` validation |
| `fan_device_test.dart` | Default field values |
| `fan_state_test.dart` | `copyWith` round-trip; equality/hashCode |
| `app_settings_test.dart` | JSON file I/O; name + first-launch persistence |
| `usage_log_test.dart` | kWh calculation |
| `usage_log_repository_test.dart` | add / get / date-range query / delete |

## Widget tests

| File | Covers |
| --- | --- |
| `control_screen_test.dart` | BLE lifecycle; demo mode; dial/mode/boost; telemetry dispatch |
| `analytics_screen_test.dart` | Day/Week/Month switching; month-range dropdown; kWh/cost display |
| `ble_permission_screen_test.dart` | Permission flow; settings branch; demo fallback |
| `home_screen_test.dart` | IndexedStack nav shell; tab switching |
| `fans_list_screen_test.dart` | Fan list; live status badge; rename/delete |
| `ble_scan_screen_test.dart` | Scan list; already-paired badge; timeout |
| `qr_scan_screen_test.dart` | Scanner overlay render; torch toggle |
| `name_fan_screen_test.dart` | Nickname validation; submit routing |
| `profile_setup_screen_test.dart` | First-launch name input/routing |
| `settings_screen_test.dart` | Profile edit; export/import; OTA; service QR |
| `user_manual_screen_test.dart` | Section expand/collapse |
| `mode_control_widget_test.dart` | Mode button enabled/active states |
| `timer_control_widget_test.dart` | OFF/2H/4H/8H selector |
| `connection_banner_test.dart` | ConnectionLostCard render + retry |
