# Changelog

All notable changes to the Terraton Fan BLE Controller are documented here.

---

## [Unreleased] — Review Pass 10

### Fixed
- **`_showOptions()` bottom sheet missing `SafeArea`** (`fan_card.dart`) — the long-press options sheet (Rename / Delete) rendered its `Column` directly without a `SafeArea` wrapper. On Android gesture-navigation devices the bottom list item could be occluded by the system navigation bar. Wrapped the `Column` in `SafeArea`, matching the identical pattern already used in `router.dart`'s `goToOnboarding()` bottom sheet.

---

## [Unreleased] — Review Pass 9

### Fixed
- **Removed unused `riverpod_generator` dev dependency** (`pubspec.yaml`) — `@riverpod` code generation was removed in Pass 1 (which removed `riverpod_annotation` from runtime dependencies), but `riverpod_generator` was never cleaned from `dev_dependencies`. Removed the orphaned entry and ran `flutter pub get` to update the lock file.

### Added
- **Unit tests for `ActiveFanStateNotifier`** (`test/unit/active_fan_state_notifier_test.dart`) — 14 tests covering all 8 update methods in `providers.dart`. Previously the notifier was the only business-logic class with zero direct unit coverage. Tests specifically exercise the non-trivial paths: `updateMode('boost')` → `isBoost=true` + `activeMode=null`; `updateMode(null)` → both cleared; `updateTimer(0)` → `activeTimerCode=null`; `clearWatts`/`clearRpm` → explicit null via getter-pattern `copyWith`. A minimal `_FakeRepo` provides in-memory storage to avoid the ObjectBox native library in unit tests.

---

## [Unreleased] — Review Pass 8

### Fixed
- **Subscription leak after `await _sub?.cancel()` in `_startScan()`** (`ble_scan_screen.dart`) — `await _sub?.cancel()` is a yield point; if `dispose()` fires between the cancel and the `_sub = ble.scanResultsStream.listen(...)` assignment, `dispose()` has already run and the new subscription is never cancelled. Added `if (!mounted) return;` immediately after the cancel await to prevent the leak.

### Added
- **`Semantics(selected:)` on BOOST button** (`control_screen.dart`) — Pass 7 added `Semantics(selected: isActive)` to mode and timer buttons, but the `_BoostButton` was missed. When boost is active, the button's background changes to `kBoostColor` — a color-only indicator invisible to TalkBack. Now wrapped in `Semantics(selected: isBoost)` for consistency with the rest of the control panel.

---

## [Unreleased] — Review Pass 7

### Fixed
- **`BleResponseParser.parseSpeed()` out-of-range byte** (`ble_response_parser.dart`) — raw `r.data[0]` from hardware was returned without bounds checking. `CircularSpeedDial` indexes `kSpeedColors[currentSpeed - 1]`; a byte outside 1–6 (e.g., firmware bug or unknown response) would panic with a `RangeError`. Added explicit range guard: returns `null` for any byte not in 1–6, which the dial renders as "no speed selected" instead of crashing. Two new unit tests cover the 0x00 and 0x07 out-of-range cases.

### Added
- **`Semantics(selected:)` on mode buttons** (`mode_control_widget.dart`) — each mode button (`NATURE`, `SMART`, `REVERSE`) is now wrapped in `Semantics(selected: isActive)` so TalkBack announces "selected" when a mode is active, rather than relying on the background-color change alone.
- **`Semantics(selected:)` on timer buttons** (`timer_control_widget.dart`) — same pattern applied to the `2H`, `4H`, `8H`, `OFF` timer buttons; active timer is now announced as "selected" by screen readers.

---

## [Unreleased] — Review Pass 6

### Added
- **`_BoostButton` widget class** (`control_screen.dart`) — extracted inline `ElevatedButton` BOOST into a private `StatelessWidget`; owns its haptic feedback call and `ElevatedButton.styleFrom` logic; matches the `_PowerButton` extraction pattern already used for the power button.
- **`RepaintBoundary` around `CircularSpeedDial`** (`control_screen.dart`) — isolates the custom-painted speed arc from the surrounding `Column` rebuild cycle; prevents the arc from repainting when unrelated state (e.g., watts/RPM text) changes.

### Changed
- **`ConnectionBanner` retry text** (`connection_banner.dart`) — wrapped the "Tap to retry" `GestureDetector` in `Semantics(button: true, label: 'Tap to reconnect')` so TalkBack announces the interactive element correctly.

---

## [Unreleased] — Review Pass 5

### Fixed
- **`_SegmentPainter.paint()` TextPainter leak** (`circular_speed_dial.dart`) — `TextPainter` created inside `paint()` was never disposed; added `tp.dispose()` immediately after `tp.paint()` to release the underlying `Paragraph` native object on every repaint.
- **Per-item DB queries in BLE scan list** (`ble_scan_screen.dart`) — `repo.getFanByMac(mac)` (a full ObjectBox query) was called for every list item inside `ListView.builder`, producing N queries per build. Replaced with a `Set<String>` derived from `ref.watch(savedFansProvider)` before the builder; the "already added" check is now an O(1) set lookup with zero extra queries.
- **`unawaited()` missing in `initState`** (`ble_scan_screen.dart`) — `_startScan()` was called without `unawaited()` in `initState`, inconsistent with the codebase convention established in Passes 1–3. Wrapped with `unawaited(_startScan())`.

### Added
- **Accessibility semantics on speed arc segments** (`circular_speed_dial.dart`) — each `GestureDetector` arc segment is now wrapped in `Semantics(button: true, label: 'Speed N')` so TalkBack/screen-readers can identify and activate individual speed steps.

---

## [Unreleased] — PRD Audit & AC-06-4 Telemetry Timeout

### Added
- **`clearWatts()` / `clearRpm()`** in `ActiveFanStateNotifier` (`providers.dart`) — explicit methods to reset telemetry values to null, used by the 5-second stale-data timeout.

### Changed
- **`FanStateCopyWith` extension** (`fan_state.dart`) — `lastWatts` and `lastRpm` parameters changed from `int?` to `int? Function()?` (getter pattern), matching the existing pattern for `activeMode` and `activeTimerCode`. Enables explicit null assignment via `copyWith(lastWatts: () => null)`.
- **`updateWatts(int)` / `updateRpm(int)`** in `ActiveFanStateNotifier` (`providers.dart`) — updated call sites from `copyWith(lastWatts: watts)` to `copyWith(lastWatts: () => watts)` to match new getter-pattern signature.

### Fixed
- **AC-06-4: Telemetry 5-second timeout** (`control_screen.dart`) — `_lastWattsAt` and `_lastRpmAt` `DateTime?` fields now track when each telemetry value was last received. Each 3-second telemetry timer tick checks whether either timestamp is older than 5 seconds; if so, calls `notifier.clearWatts()` / `notifier.clearRpm()` and resets the timestamp to null. This ensures the dial centre shows `--` for any value that has not been refreshed within 5 seconds, satisfying PRD AC-06-4.

---

## [Unreleased] — Review Pass 4

### Changed (Pass 4)
- **`fan_card.dart` `onTap`** — `context.push('/control', ...)` → `context.push(AppRoutes.control, ...)` + added `import app_routes.dart`; this was the one route call site missed in Pass 3.
- **`fan_card.dart` `.then()` callbacks** — both `_showRenameDialog` and `_confirmDelete` callbacks are now `async`; `renameFan`/`deleteFan` are `await`ed before `ref.invalidate(savedFansProvider)`, eliminating the race condition where the list could refresh before the ObjectBox write completed; added a second `context.mounted` guard after each `await`.
- **`timer_control_widget.dart` `_codeToLabel`** — replaced old-style multi-`return` `switch` statement with a Dart 3 switch expression for conciseness and exhaustiveness.
- **`connection_banner.dart` `build()`** — replaced mutable `Color bg; String label; bool showRetry = false;` locals + imperative `switch` with a single destructuring `final (bg, label, showRetry) = switch (state) { ... }` using a Dart 3 switch expression and record pattern; eliminates mutable state in `build()` and makes the exhaustive enum match visible to the compiler.

---

## [Unreleased] — Review Pass 3

### Added (Pass 3)
- **`AppRoutes` abstract final class** in `lib/shared/app_routes.dart` — single source of truth for all route path strings (`home`, `scanQr`, `scanBle`, `nameFan`, `control`, `settings`); eliminates magic string literals scattered across 6 files.
- **`==` / `hashCode` overrides** on `FanState` — Riverpod's `StateNotifier` now suppresses rebuilds when a `copyWith` produces an equal state; previously every call to `update()` caused a rebuild regardless of content.
- **`const kBoostColor = Colors.deepOrange`** in `theme.dart` — replaces the inline `Colors.deepOrange` literal in `control_screen.dart` and centralises the boost highlight colour with the rest of the design tokens.
- **`parseModeString` test group** in `ble_response_parser_test.dart` — 6 new tests covering byte `0x01`–`0x04` → `'boost'`/`'nature'`/`'reverse'`/`'smart'`, an unknown byte → `null`, and a wrong command byte → `null`.

### Changed (Pass 3)
- **`_connect()` in `control_screen.dart`** — removed redundant `final ble = ref.read(bleServiceProvider)` local variable; all BLE calls now go through the cached `_ble` field set in `initState()`. Added `return;` after the `if (!mounted) return;` guard inside the catch block — previously execution fell through to `_startTelemetry()` / `_subscribeNotify()` after a failed connection attempt.
- **`_subscribeNotify()` in `control_screen.dart`** — replaced `ref.read(bleServiceProvider)` with cached `_ble`.
- **`_send()` in `control_screen.dart`** — replaced `ref.read(bleServiceProvider).writeFrame(frame)` with `_ble.writeFrame(frame)`.
- **`update()` in `providers.dart`** — `_repo.saveState(s)` wrapped with `unawaited()` (and `import 'dart:async'` added) — makes the fire-and-forget intent explicit and surfaces any exceptions through the platform error handler instead of silently swallowing them.
- **Route strings in `router.dart`** — `initialLocation` and all `GoRoute(path:)` arguments now use `AppRoutes.*` constants; `context.push('/scan/ble')` and `context.push('/scan/qr')` in `goToOnboarding` updated likewise.
- **`context.push('/settings')`** in `home_screen.dart` → `AppRoutes.settings`; added import for `app_routes.dart`.
- **`context.push('/name-fan', ...)`** in `ble_scan_screen.dart` → `AppRoutes.nameFan`; added import for `app_routes.dart`.
- **`context.push('/name-fan', ...)`** in `qr_scan_screen.dart` → `AppRoutes.nameFan`; added import for `app_routes.dart`.
- **`context.go('/control', ...)`** in `name_fan_screen.dart` → `AppRoutes.control`; added import for `app_routes.dart`.
- **`setSpeed(1–6)` tests** in `ble_frame_builder_test.dart` — upgraded from `isNotNull` to exact byte-array assertions (`[0x55, 0xAA, 0x06, 0x04, 0x01, N, checksum]`); validates the full frame for each speed step.
- **`kBoostColor`** replaces inline `Colors.deepOrange` in `_PowerButton` style in `control_screen.dart`.

### Fixed (Pass 3)
- **`_showInvalidSnack()` in `qr_scan_screen.dart`** — added `if (!mounted) return;` guard before `ScaffoldMessenger.of(context)` to prevent operating on a detached widget context when the screen is dismissed while a scan is in progress.

---

## [Unreleased] — Review Pass 2

### Added (Pass 2)
- **`FanStateCopyWith` extension** on `FanState` — getter-based `copyWith` for nullable fields (`activeMode`, `activeTimerCode`); eliminates the 8-field manual cascade in every notifier update method.
- **`FanRepositoryImpl._useQuery<T,R>`** — private static helper that closes every ObjectBox `Query` object in a `try/finally`, preventing native resource leaks across all 6 query sites.
- **`WidgetsBinding.instance.platformDispatcher.onError`** in `main.dart` — catches uncaught async errors outside Flutter's widget zone (e.g., errors from unawaited futures in `BleServiceImpl`).
- **`_notifyValueSub`** in `BleServiceImpl` — stored `StreamSubscription` for the notify characteristic value listener; cancelled before resubscribing on each reconnect and in `dispose()`, preventing duplicate command dispatches after reconnect.
- **`tooltip`** on Settings `IconButton`, Add Fan `FloatingActionButton`, and Refresh `IconButton` in BLE scan screen — required for TalkBack/screen-reader support.
- **`ValueKey(fan.deviceId)`** on `FanCard` in `_FanList.itemBuilder` — preserves widget state across list reorders.

### Changed (Pass 2)
- **`activeFanStateProvider`** changed from `StateNotifierProvider.family` to `StateNotifierProvider.autoDispose.family` — notifier is released when no widget is watching it, preventing accumulation across multi-fan sessions.
- **All `ActiveFanStateNotifier.update*` methods** rewritten to use `state.copyWith(...)` — each method is now a single expression; adding a new `FanState` field no longer requires touching all 6 methods.
- **`_startTelemetry()`** now uses the cached `_ble` field instead of `ref.read(bleServiceProvider)` inside the `Timer.periodic` callback — eliminates the TOCTOU race between the `mounted` check and the `ref.read` call.
- **`dispose()`** in `_ControlScreenState` — `_ble.disconnect()` wrapped with `unawaited()` to explicitly mark the fire-and-forget intent and satisfy the `unawaited_futures` lint.
- **`_PowerButton`** in `control_screen.dart` — hardcoded `Color(0xFF1A56A0)` replaced with `kPrimary` from `theme.dart`.
- **`ble_scan_screen.dart`** icon changed from `Color(0xFF1A56A0)` to `kPrimary`.
- **`ble_scan_screen.dart`** `ref.read(fanRepositoryProvider)` in `build()` changed to `ref.watch(fanRepositoryProvider)` — idiomatic Riverpod.
- **`CommandLoader.speed()`** guard changed from `assert(step >= 1 && step <= 6)` to `if (step < 1 || step > 6) return null` — asserts are stripped in release builds.
- **`ErrorWidget.builder`** in `main.dart` — `TextStyle` made `const` with `Color(0xFFD32F2F)` literal (equivalent to `Colors.red.shade700`); entire builder lambda is now `const`.

### Fixed (Pass 2)
- **`context.mounted` guards** added to both `.then()` callbacks in `fan_card.dart` (`_showRenameDialog` and `_confirmDelete`) — prevents `ref.read` on a detached widget ref when the card is removed while a dialog is open.
- **`importFromJson`** in `fan_repository.dart` now wraps the entire parse in `try/on FormatException/on Object` — cast errors (`TypeError` from malformed JSON structure) are re-thrown as `FormatException` instead of crashing with an unhandled exception.

### Added (Pass 1)
- **Dual onboarding modes at runtime** — both QR scan and BLE scan are available in a single APK via a bottom-sheet picker on the home screen. The previous compile-time `--dart-define=BLE_SCAN` toggle has been removed.
- **`BleResponseParser.parseModeString()`** — converts the raw mode byte (`0x01`–`0x04`) to a string name (`'boost'`, `'nature'`, `'reverse'`, `'smart'`), moving protocol knowledge out of the providers layer.
- **`BleService.dispose()`** — closes all `StreamController`s and cancels all `StreamSubscription`s on provider teardown (wired via `ref.onDispose` in `bleServiceProvider`).
- **`_RenameDialog` as `StatefulWidget`** — owns and disposes its `TextEditingController` correctly instead of relying on `StatefulBuilder`.
- **`_EmptyState` and `_FanList` as proper widget classes** in `home_screen.dart` — extracted from private helper methods to enable element reuse and const propagation.
- **RSSI accessibility semantics** in `ble_scan_screen.dart` — `Semantics(label: 'Signal strength: strong/fair/weak')` wraps the signal icon row.
- **Power button accessibility** in `control_screen.dart` — `Semantics(button: true, label: 'Power', value: 'on'/'off')`.
- **`FlutterError.onError`** and custom `ErrorWidget.builder` in `main.dart` for user-friendly error presentation.
- **`static final _nameRegex`** in `name_fan_screen.dart` — compiled once at class level instead of per-keystroke.
- **Temp-file cleanup** in `settings_screen.dart` — timestamped temp file deleted in `try/finally` after `Share.shareXFiles`.
- **`analysis_options.yaml` strict mode** — `strict-casts`, `strict-inference`, `strict-raw-types`, plus `avoid_print`, `prefer_const_constructors`, `prefer_final_locals`, `always_declare_return_types`, `unawaited_futures`, `avoid_catches_without_on_clauses`, `always_use_package_imports`.
- **CLAUDE.md** — codebase guidance file based on PRD v7 covering product context, hardware chain, BLE protocol, Phase 2 roadmap, and hard constraints.
- **builds/ folder cleanup** in `build.ps1` — old APKs are deleted before each build run to prevent folder bloat.

### Changed
- **`savedFansProvider`** changed from `Provider<List<FanDevice>>` to `FutureProvider<List<FanDevice>>` — ObjectBox queries run off the build thread; `HomeScreen` uses `.when(data:, loading:, error:)`.
- **`activeFanStateProvider`** changed to `StateNotifierProvider.family<..., String>` (keyed by `deviceId`) — eliminates the notifier teardown race condition when unrelated providers change.
- **`ActiveFanStateNotifier.updateMode`** signature changed from `updateMode(int modeCode)` to `updateMode(String? modeName)` — receives the parsed string from `BleResponseParser.parseModeString()`.
- **`app.dart`** changed from `ConsumerWidget` to `StatelessWidget` — was reading no providers.
- **`fan_device.dart`** `addedAt` field changed from `late DateTime` to `DateTime addedAt = DateTime.now()` — prevents `LateInitializationError` when ObjectBox creates entities without explicit initialisation.
- **`CommandLoader`** and **`ObjectBoxStore`** guards changed from `assert(...)` to `if (...) throw StateError(...)` — asserts are stripped in release builds.
- **`go_router` route for `/control`** — extra cast changed from `state.extra as FanDevice` to `state.extra as FanDevice?` with null redirect to `HomeScreen`, preventing crash on missing route extra.
- **BLE scan subscription management** — `_scanResultsSub` and `_isScanSub` are cancelled before resubscribing in `startScan()`, preventing listener stacking on each Refresh tap.
- **`_connStateSub`** cancelled before attaching a new listener in `_doConnect()`, preventing duplicate callbacks across reconnects.
- **Bottom sheet context** in `fan_card.dart` and `router.dart` — `Navigator.of(sheetCtx).pop()` used instead of `Navigator.pop(context)` to avoid operating on the wrong context.
- **`showDialog<String>` / `showDialog<bool>`** in `fan_card.dart` — dialogs return their values; no captured `BuildContext` used in callbacks.
- **`kPrimary`** token used in `fan_card.dart`, `mode_control_widget.dart`, `timer_control_widget.dart`, and `ble_scan_screen.dart` instead of hardcoded `Color(0xFF1A56A0)`.
- All `lib/` imports converted to `package:terraton_fan_app/...` — `always_use_package_imports` lint enforced project-wide.
- **`riverpod_annotation`** removed from `pubspec.yaml` dependencies (was unused).

### Removed
- **`activeFanProvider`** (`StateNotifierProvider<ActiveFanNotifier, FanDevice?>`) — `ControlScreen` receives `FanDevice` via GoRouter `extra`; the provider served no purpose.
- **`app_config.dart`** and compile-time `BLE_SCAN` constant — replaced by runtime picker.

### Fixed
- **`mounted` checks** after every `await` in `_ControlScreenState._connect()`, timer callback, and notify subscription callback — prevents `setState` on disposed widget.
- **`StreamSubscription`** type annotations made explicit (`StreamSubscription<List<ScanResult>>`, `StreamSubscription<List<int>>`, `StreamSubscription<List<DiscoveredFan>>`) — satisfies `strict-inference`.
- **`catch` clauses** updated to `on Object catch (_)` / `on StateError catch (_)` throughout — satisfies `avoid_catches_without_on_clauses`.
- **`Future.delayed` type inference** fixed to `Future<void>.delayed(...)` in `ble_service.dart` and `control_screen.dart`.
- **`unawaited(Future<void>.delayed(...))` ** in `BleServiceImpl` reconnect listener — explicitly marks the fire-and-forget retry as intentional.
- **`await _sub?.cancel()`** in `ble_scan_screen.dart` — was unawaited.
- **`showDialog<void>`** type parameter added in `qr_scan_screen.dart`.
- **`const FormatException(...)`** in `fan_repository.dart` and `fan_repository_test.dart`.
- **Empty list type annotation** `<Map<String, dynamic>>[]` in `fan_repository_test.dart` — satisfies `inference_failure_on_collection_literal`.
- **`_FakeRepo` catch clauses** in `fan_repository_test.dart` changed to `on StateError catch (_)` — `firstWhere` throws `StateError`, not `Exception`.
- **Camera permission race** in `qr_scan_screen.dart` — `MobileScanner` is only mounted after camera is granted (`_cameraReady` flag).
- **`build.ps1` APK path** updated for split-per-ABI output (`app-arm64-v8a-release.apk`).
