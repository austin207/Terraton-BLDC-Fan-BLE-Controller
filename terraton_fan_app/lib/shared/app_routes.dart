// lib/shared/app_routes.dart
const kDemoDeviceId = '__demo__';

abstract final class AppRoutes {
  static const splash             = '/splash';
  static const profileSetup       = '/profile-setup';
  static const home               = '/';
  /// Config-driven appliance-type picker. Expects [ApplianceCategory] as GoRouter extra.
  static const applianceTypes     = '/appliance-types';
  /// Legacy path — redirects to [applianceTypes] for backward compat.
  static const fanTypes           = '/fan-types';
  static const fans               = '/fans';
  /// Placeholder for not-yet-supported appliance types. Expects [ApplianceType] as GoRouter extra.
  static const comingSoon         = '/coming-soon';
  static const permissionRequired = '/permission-required';
  static const scanQr             = '/scan/qr';
  static const scanBle            = '/scan/ble';
  static const nameFan            = '/name-fan';
  static const control            = '/control';
  static const settings           = '/settings';
  static const userManual         = '/settings/user-manual';
  static const privacyPolicy      = '/settings/privacy-policy';
  static const terms              = '/settings/terms';
}
