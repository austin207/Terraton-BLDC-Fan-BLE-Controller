// lib/shared/app_config.dart
//
// Compile-time variant flag — injected at build time via:
//   --dart-define=APP_VARIANT=client   →  client variant (fans only, no OTA)
//   --dart-define=APP_VARIANT=tester   →  tester variant (all features)
//
// Default is 'tester' so a plain `flutter run` / debug build gets everything.
const kAppVariant = String.fromEnvironment('APP_VARIANT', defaultValue: 'tester');

/// True when building the client-facing variant.
///
/// In the client variant:
///  - Only the Fans category is visible (water filtration / air purification /
///    energy storage are excluded at compile time).
///  - The in-app OTA update feature is disabled (auto-check + manual check tile).
const kIsClientVariant = kAppVariant == 'client';
