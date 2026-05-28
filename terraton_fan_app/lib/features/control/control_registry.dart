// lib/features/control/control_registry.dart
//
// Extensibility hook for non-built-in control widgets.
//
// Built-in control types (handled natively in _FanControlsPanel):
//   speed    → CircularSpeedDial
//   mode     → ModeControlWidget + boost button
//   timer    → TimerControlWidget
//   lighting → LightingControlWidget
//   power    → reserved power toggle
//
// To add a completely new control type (e.g. 'brightness' for a smart light):
//   1. Create a StatelessWidget or ConsumerWidget for the control UI.
//   2. In main.dart (after ApplianceLoader.load()), call:
//        ControlRegistry.register('brightness', (p) => BrightnessControl(p));
//   3. Add the control type string to the relevant type in appliances.yaml.
//      No other code changes are needed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

/// All context a custom control widget might need.
class ControlBuildParams {
  final FanDevice device;
  final FanState fanState;
  final bool enabled;
  final WidgetRef ref;

  /// Per-control configuration map from appliances.yaml (empty if not present).
  final Map<String, dynamic> config;

  const ControlBuildParams({
    required this.device,
    required this.fanState,
    required this.enabled,
    required this.ref,
    this.config = const {},
  });
}

typedef ControlWidgetBuilder = Widget Function(ControlBuildParams params);

/// Registry that maps control-type strings to widget builders for custom controls.
///
/// Only non-built-in controls need registration. Built-in controls (speed, mode,
/// timer, lighting, power) are rendered directly by _FanControlsPanel.
abstract final class ControlRegistry {
  static final Map<String, ControlWidgetBuilder> _builders = {};

  /// Register a [builder] for [controlType].
  /// Safe to call multiple times — later calls overwrite earlier ones.
  static void register(String controlType, ControlWidgetBuilder builder) {
    _builders[controlType] = builder;
  }

  /// Returns the registered builder for [controlType], or null if not registered.
  static ControlWidgetBuilder? get(String controlType) => _builders[controlType];

  /// Returns true if [controlType] is a native built-in (does not need registration).
  static bool isBuiltIn(String controlType) => _builtIn.contains(controlType);

  static const Set<String> _builtIn = {
    'speed',
    'mode',
    'timer',
    'lighting',
    'power',
  };
}
