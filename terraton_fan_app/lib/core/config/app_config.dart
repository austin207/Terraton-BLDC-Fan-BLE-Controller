// lib/core/config/app_config.dart

enum OnboardingMode {
  qrScan,
  bleScan,
}

class AppConfig {
  // Controlled at build time via --dart-define=BLE_SCAN=true.
  // Default (no flag) → qrScan.  Pass the flag → bleScan.
  // No code changes needed to produce both variants.
  static const OnboardingMode onboardingMode =
      bool.fromEnvironment('BLE_SCAN')
          ? OnboardingMode.bleScan
          : OnboardingMode.qrScan;
}
