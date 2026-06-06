# Features & Roadmap

## Features

| Category | Details |
| --- | --- |
| **Onboarding** | BLE scan or full-screen immersive QR scanner; profile setup on first launch |
| **Fan control** | Power, 6 speed steps, Boost / Nature / Reverse / Smart modes, 2 / 4 / 8 h sleep timer |
| **Nature mode** | Locks the speed dial and disables other modes; restores pre-nature speed on switch to Smart/Reverse |
| **Mood lighting** | ON/OFF + warm↔cool colour-temperature slider *(bytes pending from Terraton)* |
| **Telemetry** | Live watts and RPM polled every 3 s; stale values auto-clear after 5 s |
| **Analytics** | kWh, estimated cost, avg wattage, efficiency vs. a traditional fan; Day / Week / Month views with per-fan breakdown. Month view has a 1–6 month range selector with daily graph points |
| **Background tracking** | Usage segments flushed on app pause/close; Android foreground service shows a persistent "Fan running" notification while connected |
| **Connection lifecycle** | Disconnects on background / screen sleep (frees the fan for another phone) and reconnects on resume; never steals a connection held by another phone |
| **Data upload** | Opt-in anonymised daily usage summaries to a Cloudflare Worker (Wi-Fi only, once per day); API key injected at build time |
| **Multi-fan** | Manage multiple fans; live connection status badge; rename / remove / long-press actions |
| **Storage** | Fan metadata + last-known state in ObjectBox; usage logs for analytics |
| **Backup** | Export / import fan list as JSON |
| **OTA updates** | *(tester variant)* on-launch + manual check; downloads arm64 APK from GitHub Releases with a progress bar; hands off to the system installer |
| **Service QR** | Time-limited QR (3-hour countdown) for a technician to scan with their own copy of the app; regenerate resets the clock |
| **Permissions** | Guided BT permission screen with retry, settings deep-link, and demo-mode fallback |
| **Demo mode** | Full UI walkthrough without a physical fan |
| **User manual** | In-app manual — 8 expandable sections |
| **Legal** | Privacy Policy and Terms of Service screens |

See [BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md#variants) for which features ship in
the tester vs client variant.

---

## Roadmap

| Phase | Feature | Status |
| --- | --- | --- |
| 1 | BLE connectivity | ✅ Complete |
| 1 | Full fan control — power, speed, modes, timers | ✅ Complete |
| 1 | Live telemetry — watts and RPM | ✅ Complete |
| 1 | Multi-fan management and persistence | ✅ Complete |
| 1 | QR + BLE scan onboarding; full-screen QR scanner | ✅ Complete |
| 1 | Live connection status in fan list | ✅ Complete |
| 1 | Permissions screen, splash, demo mode | ✅ Complete |
| 1 | Profile setup + user-name personalisation | ✅ Complete |
| 1 | Analytics — energy, cost, efficiency | ✅ Complete |
| 1 | Monthly analytics 1–6 month rolling range | ✅ Complete |
| 1 | In-app user manual | ✅ Complete |
| 1 | Background usage tracking + foreground service | ✅ Complete |
| 1 | Service QR for technician access | ✅ Complete |
| 1 | Privacy Policy + Terms of Service | ✅ Complete |
| 2 | OTA self-update from GitHub Releases | ✅ Complete |
| 2 | Tester / client build variants | ✅ Complete |
| 2 | Config-driven appliance categories (YAML) | ✅ Complete |
| 2 | AI training data upload (Cloudflare Worker + R2) | ✅ Complete |
| 2 | Lighting control | ⏳ UI complete — awaiting command bytes from Terraton |
| 2 | Non-fan appliances (water / air / energy) | ⏳ UI scaffolded — awaiting hardware command bytes |
| 2 | Remote command updates (fetch `commands.yaml` from URL) | 📋 Planned |
