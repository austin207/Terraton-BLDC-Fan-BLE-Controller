// lib/features/home/fan_types_screen.dart
//
// Legacy compatibility shim. Canonical screen is ApplianceTypesScreen.
// Kept so any import of fan_types_screen.dart continues to compile unchanged.

import 'package:terraton_fan_app/features/home/appliance_types_screen.dart';
export 'package:terraton_fan_app/features/home/appliance_types_screen.dart';

/// Legacy alias — prefer [ApplianceTypesScreen] in new code.
@Deprecated('Use ApplianceTypesScreen from appliance_types_screen.dart')
typedef FanTypesScreen = ApplianceTypesScreen;

/// Legacy alias — prefer [ApplianceTypeCard] in new code.
@Deprecated('Use ApplianceTypeCard from appliance_types_screen.dart')
typedef FanTypeCard = ApplianceTypeCard;
