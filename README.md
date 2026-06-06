# Terraton BLDC Fan BLE Controller

Android (Flutter) app that controls a Terraton BLDC ceiling fan over Bluetooth Low
Energy 5.2 via an Amp'ed RF BLE60 module. Fan control is fully offline over BLE.

```text
Flutter App  ──BLE 5.2──►  Amp'ed RF BLE60  ──UART──►  Fan MCU  ──►  BLDC Motor
```

The app writes framed packets to the Write characteristic; the fan responds on the
Notify characteristic. Power, 6 speeds, Boost / Nature / Reverse / Smart modes,
sleep timers, live watts/RPM telemetry, energy analytics, multi-fan management, and
opt-in anonymised usage upload.

---

## Quick start

```powershell
# From terraton_fan_app/
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run

# Release build (from repo root) — prompts for version bump + variant
.\build.ps1
```

Requires Flutter 3.29+ / Dart 3.8+ and an Android device or emulator with BLE.

---

## Documentation

| Doc | What's in it |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Data flow, startup sequence, state management, Nature-mode state machine, connection lifecycle |
| [docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md) | UUIDs, frame format, checksum, BLE60 bridge, **full request/response command table**, 2- vs 4-frame status poll |
| [docs/BUILD_AND_RELEASE.md](docs/BUILD_AND_RELEASE.md) | Local run, emulator, tester/client variants, `build.ps1`, OTA flow |
| [docs/TESTING.md](docs/TESTING.md) | Analyze/test commands, testing notes, full coverage tables |
| [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) | File-by-file layout, hard constraints, dependencies |
| [docs/FEATURES.md](docs/FEATURES.md) | Feature list and roadmap |

Working in this repo with Claude Code? See [CLAUDE.md](CLAUDE.md) for the
authoritative architecture notes and conventions.

---

## Author

Antony Austin — College Project, 2026
