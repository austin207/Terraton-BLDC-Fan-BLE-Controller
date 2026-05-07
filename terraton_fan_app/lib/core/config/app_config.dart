// lib/core/config/app_config.dart

enum OnboardingMode {
  qrScan,
  bleScan,
}

class AppConfig {
  /// Toggle this constant to switch onboarding mode.
  /// qrScan  : User scans QR code on fan packaging.
  /// bleScan : User selects fan from a BLE scan list.
  /// No other code changes are needed when toggling this.
  static const OnboardingMode onboardingMode = OnboardingMode.bleScan;
}
