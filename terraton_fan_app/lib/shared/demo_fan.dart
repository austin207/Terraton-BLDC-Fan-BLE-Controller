// lib/shared/demo_fan.dart
//
// The demo fan — a throwaway FanDevice (never persisted to FanRepository) used
// to walk the control screen without hardware. Only surfaced in the tester
// variant (see kIsClientVariant). `_isDemo` in control_screen keys on
// deviceId == kDemoDeviceId and routes every write through _applyDemoFrame.

import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

/// The three ceiling-fan remotes the demo switcher offers, in order.
const kDemoRemoteModels = <String>['TN-CF-01', 'TN-CF-02', 'TN-CF-03'];

/// Builds a fresh in-memory demo [FanDevice]. Not saved anywhere; a new one is
/// made each time the demo is opened. [model] selects the starting remote.
FanDevice demoFanDevice({String model = 'TN-CF-01'}) => FanDevice()
  ..deviceId   = kDemoDeviceId
  ..macAddress = ''
  ..model      = model
  ..nickname   = 'Demo Fan'
  ..fwVersion  = 'demo'
  ..addedAt    = DateTime.now();
