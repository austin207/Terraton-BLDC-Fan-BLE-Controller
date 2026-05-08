# Changelog

All notable changes to the Terraton Fan BLE Controller are documented here.

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
