# Terraton Fan App — Handover Guide

Everything a new developer or team needs to take ownership of this project: what to change, where it lives, and how to do it.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Structure](#2-repository-structure)
3. [Secrets and Keys](#3-secrets-and-keys)
4. [Cloudflare Worker](#4-cloudflare-worker)
5. [GitHub Repository](#5-github-repository)
6. [Android App Identity](#6-android-app-identity)
7. [BLE Protocol Constants](#7-ble-protocol-constants)
8. [Fan Types and Models](#8-fan-types-and-models)
9. [Build and Release](#9-build-and-release)
10. [OTA Update System](#10-ota-update-system)
11. [Data Upload (AI Training Pipeline)](#11-data-upload-ai-training-pipeline)
12. [Device Ping / Install Tracking](#12-device-ping--install-tracking)
13. [Phase 2 Items (Not Yet Built)](#13-phase-2-items-not-yet-built)

---

## 1. Prerequisites

Install these before doing anything else.

| Tool | Version | Install |
|------|---------|---------|
| Flutter SDK | ≥ 3.8.0 | https://docs.flutter.dev/get-started/install |
| Android Studio | Latest | For emulator and SDK tools |
| Android SDK | API 36 (compileSdk), min API 23 | Via Android Studio SDK Manager |
| NDK | 27.0.12077973 | Via Android Studio SDK Manager |
| Java (JDK) | 11 | Bundled with Android Studio |
| Git | Any | https://git-scm.com |
| GitHub CLI (`gh`) | Any | https://cli.github.com — run `gh auth login` after install |
| Node.js | LTS | For Wrangler (Cloudflare CLI) |
| Wrangler | Latest | `npm install -g wrangler` then `wrangler login` |
| PowerShell | 5.1+ | Pre-installed on Windows |

**Verify Flutter:**
```powershell
flutter doctor
```
All items should be green except iOS (Android-only project).

---

## 2. Repository Structure

```
repo root/
├── terraton_fan_app/          # Flutter Android app (all app code lives here)
│   ├── lib/                   # Dart source
│   │   ├── core/              # BLE, storage, upload, providers
│   │   ├── features/          # Screens (control, home, onboarding, settings…)
│   │   ├── models/            # Data models (FanDevice, FanState, FanType…)
│   │   └── shared/            # Theme, router, shared widgets
│   ├── assets/
│   │   ├── commands.yaml      # BLE command bytes — single source of truth
│   │   ├── icons/             # Fan type icons (PNG, per FanType enum)
│   │   └── fonts/             # Bundled Manrope TTF files
│   ├── android/               # Android project
│   │   └── app/build.gradle.kts  # App ID, signing config, SDK versions
│   └── pubspec.yaml           # Dependencies and version number
├── cloudflare/
│   ├── worker.js              # Cloudflare Worker (upload + ping endpoints)
│   └── wrangler.toml          # Worker name, R2 bucket, KV namespaces
├── builds/                    # Output APKs and version.json (gitignored except version.json)
├── build.ps1                  # One-command release script
├── secrets.env                # Local secrets file — NEVER commit (gitignored)
├── secrets.env.template       # Template to copy from
├── CLAUDE.md                  # Guidance for Claude Code AI assistant
└── HANDOVER.md                # This file
```

---

## 3. Secrets and Keys

### 3.1 `secrets.env` (local build machine only)

Copy the template and fill in the real value:

```powershell
Copy-Item secrets.env.template secrets.env
```

Then edit `secrets.env`:

```
UPLOAD_API_KEY=<your_actual_key>
```

- This file is gitignored — **never commit it.**
- `build.ps1` reads it automatically and passes the key to the Flutter build via `--dart-define`.
- Debug builds (`flutter run`) get an empty key and skip all uploads silently.

### 3.2 `UPLOAD_API_KEY` — what it is

The key that authenticates the app's data uploads to the Cloudflare Worker `/upload` endpoint.
It is set as a Cloudflare Worker secret (not in `wrangler.toml`):

```bash
wrangler secret put UPLOAD_API_KEY
# (Wrangler prompts for the value interactively — paste the key)
```

To rotate the key:
1. Generate a new secret string (any random hex/UUID will do).
2. Run `wrangler secret put UPLOAD_API_KEY` with the new value.
3. Update `secrets.env` on every developer machine that runs `build.ps1`.
4. Rebuild and redistribute the APK so existing installs start using the new key.

---

## 4. Cloudflare Worker

The worker handles two endpoints:
- `POST /ping` — anonymous install count (no auth)
- `POST /upload` — usage data for AI training (requires `UPLOAD_API_KEY`)

### 4.1 First-time setup on a new Cloudflare account

```bash
cd cloudflare

# 1. Login
wrangler login

# 2. Create the R2 bucket
wrangler r2 bucket create terraton-usage-data

# 3. Create the rate-limit KV namespace
wrangler kv:namespace create RATE_LIMIT_KV
# → copy the returned `id` into wrangler.toml under the RATE_LIMIT_KV binding

# 4. Create the device-ping KV namespace
wrangler kv:namespace create DEVICE_KV
# → copy the returned `id` into wrangler.toml under the DEVICE_KV binding

# 5. Set the upload auth secret
wrangler secret put UPLOAD_API_KEY

# 6. Deploy
wrangler deploy
```

### 4.2 `wrangler.toml` — fields to update

| Field | Where | What to change |
|-------|-------|----------------|
| `name` | line 1 | Worker name — becomes part of the URL: `<name>.<account>.workers.dev` |
| `bucket_name` | `[[r2_buckets]]` | R2 bucket name (must match what you created in step 2) |
| `id` (RATE_LIMIT_KV) | `[[kv_namespaces]]` | KV namespace ID from step 3 |
| `id` (DEVICE_KV) | `[[kv_namespaces]]` | KV namespace ID from step 4 |

### 4.3 Worker URL — update in the app

After deploying, the worker URL changes. Update **two files** in the Flutter app:

**`lib/core/upload/data_upload_service.dart` line 12:**
```dart
static const _endpoint = 'https://<new-worker-name>.<account>.workers.dev/upload';
```

**`lib/core/upload/device_ping_service.dart` line 9:**
```dart
static const _endpoint = 'https://<new-worker-name>.<account>.workers.dev/ping';
```

### 4.4 Updating the worker

```bash
cd cloudflare
wrangler deploy
```

### 4.5 Viewing data

```bash
# List all device pings (install count)
wrangler kv:key list --namespace-id <DEVICE_KV_ID>

# Download uploaded usage data from R2
wrangler r2 object get terraton-usage-data/<filename>
```

---

## 5. GitHub Repository

### 5.1 Transferring the repository

1. On GitHub: **Settings → Danger Zone → Transfer ownership** → enter the new org/username.
2. After transfer, update the `$Repo` variable in `build.ps1` line 6:
   ```powershell
   $Repo = "new-org/new-repo-name"
   ```
3. Update `_repo` in `lib/core/update/app_update_service.dart` line 23:
   ```dart
   static const _repo = 'new-org/new-repo-name';
   ```
4. Run `gh auth login` on the new machine and authenticate with the new account.

### 5.2 GitHub CLI authentication (required for `build.ps1`)

```powershell
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser
```

`build.ps1` uses `gh release create` to publish APKs. Without auth this step fails.

### 5.3 GitHub Actions (optional CI)

The repo currently uses `build.ps1` on a local machine for releases. If you want CI:
- Set these repository secrets in GitHub: `UPLOAD_API_KEY`, `KEYSTORE_PATH`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
- `build.gradle.kts` already reads `KEYSTORE_PATH` etc. from environment variables — no code changes needed.

---

## 6. Android App Identity

### 6.1 Application ID and namespace

Both are set in `terraton_fan_app/android/app/build.gradle.kts`:

```kotlin
namespace     = "com.terraton.terraton_fan_app"   // line 10
applicationId = "com.terraton.terraton_fan_app"   // line 24
```

Change both to the company's reverse-domain ID (e.g. `com.acme.terraton`). They must match.

> **Note:** changing the application ID makes the app a different app on device — existing installs will NOT auto-update via the OTA system.

### 6.2 Release signing keystore

Currently, release builds fall back to the Android debug keystore when `KEYSTORE_PATH` env var is not set. For Play Store or production distribution:

1. Generate a keystore:
   ```powershell
   keytool -genkey -v -keystore terraton-release.jks -alias terraton -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Store it somewhere safe (NOT in the repo).
3. Set environment variables before running `build.ps1`:
   ```powershell
   $env:KEYSTORE_PATH  = "C:\path\to\terraton-release.jks"
   $env:STORE_PASSWORD = "..."
   $env:KEY_ALIAS      = "terraton"
   $env:KEY_PASSWORD   = "..."
   ```
   Or add them to `secrets.env` and load them in `build.ps1`.

### 6.3 App version

Version is managed in `terraton_fan_app/pubspec.yaml`:
```yaml
version: 1.11.2+15   # semver+buildNumber
```

`build.ps1` bumps this interactively on every release. Do not edit it manually unless you need to force a specific version.

### 6.4 App name and icon

- **Name:** `terraton_fan_app/android/app/src/main/AndroidManifest.xml` → `android:label`
- **Icon:** Replace `terraton_fan_app/assets/icon/icon.png` with the new 1024×1024 PNG, then run:
  ```powershell
  cd terraton_fan_app
  dart run flutter_launcher_icons
  ```

---

## 7. BLE Protocol Constants

All BLE UUIDs live in **one file only**: `lib/core/ble/ble_constants.dart`. Never copy them elsewhere.

The primary working profile for the Amp'ed RF BLE60 module is:
- **Scan filter:** `00001827` (BLE Mesh Proxy)
- **Write char:** `00002adb` (Mesh Proxy Data In)
- **Notify char:** `00002adc` (Mesh Proxy Data Out)

If Terraton switches to a different BLE module or firmware:
1. Update the relevant UUID constants in `ble_constants.dart`.
2. Update the service discovery priority order in `lib/core/ble/ble_service.dart` `_findChars()`.
3. No other files need touching — all BLE code reads from `ble_constants.dart`.

### 7.1 Adding new BLE commands

All command bytes live in **one file only**: `terraton_fan_app/assets/commands.yaml`.

To add a new command:
1. Add the bytes under the appropriate section in `commands.yaml`.
2. Add a named method in `lib/core/ble/ble_frame_builder.dart` (calls `CommandLoader.custom([...], [...])`).
3. Call the new method from `control_screen.dart` `_send(...)`.

No checksum calculation needed — `buildFrame()` computes it automatically.

---

## 8. Fan Types and Models

### 8.1 Fan type enum

`lib/models/fan_type.dart` defines the five categories shown in the Fan Types screen:

```dart
enum FanType {
  ceiling('Ceiling Fan', 'CF', 'assets/icons/Ceiling fan.png'),
  table  ('Table Fan',   'TF', 'assets/icons/Table fan.png'),
  ...
}
```

To add a new fan type:
1. Add the PNG icon to `assets/icons/`.
2. Declare the asset in `pubspec.yaml` under `flutter: assets:`.
3. Add a new enum case with `(label, prefix, iconPath)`.

### 8.2 Model numbers

Each `FanType` auto-generates 21 model IDs: `TN-CF-01` … `TN-CF-21`, etc.
To change the count or format, edit `modelNumbers` getter in `fan_type.dart`.

### 8.3 Fan type icons

Icons live in `assets/icons/`. Current files:
```
Ceiling fan.png   → FanType.ceiling
Table fan.png     → FanType.table
Pedestal fan.png  → FanType.pedestal
Wall fan.png      → FanType.wall
Exhaust fan.png   → FanType.exhaust
```

Icons are tinted at runtime with `BlendMode.srcIn`. For correct tinting, supply **white foreground on transparent background** PNGs.

---

## 9. Build and Release

### 9.1 One-command release

```powershell
# From repo root
.\build.ps1
```

The script will:
1. Ask for a version bump type (Patch / Minor / Major / Skip).
2. Regenerate launcher icons and clean all caches.
3. Regenerate ObjectBox / Riverpod generated code.
4. Run the full test suite — **aborts if any test fails.**
5. Build three APK splits (arm64, arm7, x86_64).
6. Save copies to `builds/` with timestamps.
7. Publish to GitHub Releases under the `latest` tag (overwrites previous).
8. Commit and push the version bump.

### 9.2 Prerequisites for `build.ps1`

- `gh` CLI authenticated (`gh auth login`)
- `secrets.env` present with `UPLOAD_API_KEY=...`
- Flutter and Dart in PATH
- Working internet connection (for GitHub upload)

### 9.3 Manual test run

```powershell
cd terraton_fan_app
flutter test --no-pub
```

All 316 tests must pass before releasing.

---

## 10. OTA Update System

The app checks for updates on launch by fetching `version.json` from GitHub Releases.

**How it works:**
1. `build.ps1` writes `builds/version.json` with `{ "version": "x.y.z", "build_number": N }`.
2. This file is uploaded to GitHub Releases under the `latest` tag alongside the APKs.
3. On launch, `AppUpdateService.checkForUpdate()` fetches it and compares `build_number` to the installed build.
4. If the remote build number is higher, an update dialog appears and the user can download + install.

**Download URL pattern** (hard-coded in `lib/core/update/app_update_service.dart`):
```
https://github.com/<repo>/releases/download/latest/terraton-fan-arm64.apk
https://github.com/<repo>/releases/download/latest/version.json
```

If you change the GitHub repo name, update `_repo` in `app_update_service.dart` (line 23).
If you change the APK filename, update `_apkUrl` (line 29) and the matching `$Arm64Release` name in `build.ps1`.

---

## 11. Data Upload (AI Training Pipeline)

Users who opt in share daily usage summaries (power-on duration, speed distribution, watt readings, ambient temperature) with the Cloudflare Worker for AI model training.

**Opt-in:** User toggles "Share Usage Data" in Settings → the preference is stored locally in `app_settings.json`.

**Key file:** `lib/core/upload/data_upload_service.dart`
- `_endpoint` — Worker URL (update if worker is redeployed)
- `_lat` / `_lon` — Weather coordinates for Open-Meteo API (currently hardcoded to central Kerala). Update to match your deployment region or make configurable in Phase 2.
- `_apiKey` — Injected via `--dart-define=UPLOAD_API_KEY=<secret>` at build time. Empty in debug builds (uploads silently skipped).

**Data flow:**
```
App (on Wi-Fi, opted-in) → POST /upload → Cloudflare Worker → R2 bucket (terraton-usage-data)
```

Data is uploaded once per completed day. Uploaded dates are persisted locally to prevent duplicate submissions.

---

## 12. Device Ping / Install Tracking

Every app launch fires an anonymous ping to count unique installs. No opt-in required — the payload contains only a hashed device ID and app version.

**Key file:** `lib/core/upload/device_ping_service.dart`
- `_endpoint` — Worker URL (update if worker is redeployed)

**Data stored in Cloudflare KV (`DEVICE_KV`):**
```json
{
  "first_seen": "2026-01-01T00:00:00.000Z",
  "last_seen":  "2026-05-28T12:00:00.000Z",
  "app_version": "1.11.2+15",
  "ping_count": 42
}
```

Keys are `device:<16-char-sha256-prefix>` — not reversible to real device identity.

To view device count:
```bash
wrangler kv:key list --namespace-id <DEVICE_KV_ID> | grep -c "device:"
```

---

## 13. Phase 2 Items (Not Yet Built)

These are planned features. Code stubs or comments exist in the codebase for most of them.

| Feature | Status | Notes |
|---------|--------|-------|
| Lighting commands | Pending bytes from Terraton | `LightingControlWidget` is built; `commands.yaml` has null placeholders. When Terraton provides the byte values, add them to `commands.yaml` — no other code changes needed. |
| Remote command loading | Planned | Fetch `commands.yaml` from a hosted URL on launch; fall back to bundled asset on failure. Logic stub noted in `CLAUDE.md`. |
| Real energy analytics | Planned | `_UsageCard` on Home screen shows "—" placeholders. Wire to `UsageLogRepository` data. |
| Weather coordinates configurable | Planned | Currently hardcoded to Kerala in `data_upload_service.dart`. |
| iOS build | Not planned (Phase 1 is Android-only) | `pubspec.yaml` has `ios: false` in launcher icons config. |
| Firebase Crashlytics | Not integrated | `FlutterError.onError` is set up but just calls `FlutterError.presentError`. Hook in a Crashlytics reporter here. |

---

## Quick Reference — Files Most Likely to Need Changing

| What | File | Line(s) |
|------|------|---------|
| Worker URL (upload) | `lib/core/upload/data_upload_service.dart` | 12 |
| Worker URL (ping) | `lib/core/upload/device_ping_service.dart` | 9 |
| GitHub repo (OTA + build) | `lib/core/update/app_update_service.dart` | 23 |
| GitHub repo (build script) | `build.ps1` | 6 |
| Application ID | `android/app/build.gradle.kts` | 10, 24 |
| BLE UUIDs | `lib/core/ble/ble_constants.dart` | all |
| BLE command bytes | `assets/commands.yaml` | all |
| Fan types / model prefixes | `lib/models/fan_type.dart` | all |
| Fan type icons | `assets/icons/` | — |
| Upload API key (local) | `secrets.env` | — |
| Upload API key (Cloudflare) | `wrangler secret put UPLOAD_API_KEY` | — |
| Weather coordinates | `lib/core/upload/data_upload_service.dart` | 20–21 |
| KV namespace IDs | `cloudflare/wrangler.toml` | 15, 19 |
