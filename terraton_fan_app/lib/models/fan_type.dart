// lib/models/fan_type.dart
//
// Compatibility shim. The canonical type is ApplianceType (appliance.dart),
// loaded from assets/appliances.yaml via ApplianceLoader.
//
// This file exists so that any import of `fan_type.dart` keeps compiling
// without changes. Migrate to ApplianceType / ApplianceLoader in new code.

import 'package:terraton_fan_app/models/appliance.dart';

/// Legacy alias — prefer [ApplianceType] in new code.
typedef FanType = ApplianceType;
