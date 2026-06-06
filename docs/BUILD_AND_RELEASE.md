# Build & Release

## Requirements

- Flutter 3.29+ with Dart 3.8+
- Android device (API 21+) or emulator with BLE support
- Android SDK

---

## Run locally

All Flutter commands run from `terraton_fan_app/`.

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # regenerate ObjectBox/Riverpod
flutter run                    # auto-selects the connected device/emulator
flutter run -d emulator-5554   # target a specific emulator by ID
```

### Emulator

Two AVDs are configured: **S24_Ultra** and **Medium_Phone_API_36.0**.

```powershell
# From repo root
.\launch-emulator.ps1            # launch S24 Ultra
.\launch-emulator.ps1 -Run       # launch, then run the app once boot finishes
.\launch-emulator.ps1 -RunOnly   # emulator already up — just start the app
```

List/start manually:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd S24_Ultra
```

---

## Variants

The app ships in two compile-time variants, selected via
`--dart-define=APP_VARIANT=<tester|client>` (see
[`lib/shared/app_config.dart`](../terraton_fan_app/lib/shared/app_config.dart)).

| Variant | Appliances | OTA updates | Audience |
| --- | --- | --- | --- |
| **tester** *(default)* | All (fans, water filtration, air purification, energy storage) | ✅ Yes | Client testing |
| **client** | Fans only (`assets/appliances_client.yaml`) | ❌ Compiled out | End users |

In the **client** variant the update code path is removed at compile time —
`AppUpdateService` is never called, the Settings update tile is hidden, and the
client APK is not published to GitHub Releases. There is no way for a client build
to receive an OTA update.

---

## Release build

```powershell
# From repo root
.\build.ps1
```

`build.ps1` is interactive:

1. **Version bump** — **P**atch / mi**N**or / ma**J**or / **S**kip; increments
   `pubspec.yaml`.
2. **Variant** — **T**ester / **C**lient / **B**oth (default).
3. Cleans caches, regenerates code, runs the full test suite (aborts on failure),
   then builds split-per-ABI APKs.

Output:

- **Tester** APKs are saved to `builds/` and published to **GitHub Releases**
  (this is the OTA source).
- **Client** APKs are saved to `builds/` only (`terraton-client-arm64-*.apk`) —
  share them directly with end users. They are never uploaded.

> **API key:** the Cloudflare upload key is read from a gitignored `secrets.env`
> at build time via `--dart-define=UPLOAD_API_KEY=<secret>`. Debug builds skip the
> upload silently. The key must never appear in committed source.

---

## OTA update flow (tester only)

1. On launch (and from Settings → Check for Updates) the app fetches
   `version.json` from the `latest` GitHub release.
2. If `build_number` is newer, an update dialog offers a download.
3. The arm64 APK streams to a temp file with a live progress bar, then hands off to
   the Android system installer (requires the "Install Unknown Apps" permission).
