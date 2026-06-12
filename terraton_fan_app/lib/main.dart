// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/config/app_feature_config.dart';
import 'package:terraton_fan_app/core/diagnostics/crash_log_service.dart';
import 'package:terraton_fan_app/core/storage/objectbox_store.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/core/upload/data_upload_service.dart';
import 'package:terraton_fan_app/core/upload/device_ping_service.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/features/control/water_filtration_control.dart';
import 'package:terraton_fan_app/features/control/air_purification_control.dart';
import 'package:terraton_fan_app/features/control/energy_storage_control.dart';
import 'package:terraton_fan_app/shared/app_config.dart';
import 'package:terraton_fan_app/shared/theme.dart';
import 'package:terraton_fan_app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // Persist for field diagnostics — release builds have no console, so this
    // local log (surfaced in Settings) is the only crash visibility we have.
    unawaited(CrashLogService.record(
        details.exception, details.stack, source: 'flutter'));
  };
  WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
    FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
    unawaited(CrashLogService.record(error, stack, source: 'async'));
    return true;
  };
  ErrorWidget.builder = (details) => const Material(
    color: kBg,
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Something went wrong.\nPlease restart the app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kRed, fontSize: 14),
        ),
      ),
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await CommandLoader.load();
  await ApplianceLoader.load();
  await AppFeatureConfig.load();

  // Register non-fan appliance control widgets (tester variant only).
  // Skipped for client variant — those categories are not in appliances_client.yaml.
  if (!kIsClientVariant) {
    ControlRegistry.register('water_quality',  buildWaterFiltrationControl);
    ControlRegistry.register('air_quality',    buildAirPurificationControl);
    ControlRegistry.register('energy_metrics', buildEnergyStorageControl);
  }

  await initObjectBox();
  // Permissions are requested contextually by BlePermissionScreen after the
  // splash screen checks status. Requesting here (before any UI) shows the
  // system dialog over a blank screen, violating Android UX guidelines.
  await _ensureBluetoothOn();

  // Bound ObjectBox growth: drop usage logs older than a year. A full year
  // covers every analytics window (Day/Week/Month) and the rolling-30-day kWh
  // estimate, while uploads happen next-day so nothing un-uploaded is lost.
  final usageLogRepo = UsageLogRepositoryImpl(store);
  try {
    usageLogRepo.pruneBefore(DateTime.now().subtract(const Duration(days: 365)));
  } on Object catch (_) {
    // Prune is best-effort housekeeping; never block startup on it.
  }

  // Fire-and-forget — anonymous heartbeat; tells Cloudflare this device is active.
  unawaited(DevicePingService.ping());
  // Fire-and-forget — uploads previous days' summaries if user opted in + Wi-Fi.
  unawaited(DataUploadService.tryUpload(usageLogRepo));

  runApp(const ProviderScope(child: TerratorApp()));
}

Future<void> _ensureBluetoothOn() async {
  if (!Platform.isAndroid) return;
  try {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;
    await FlutterBluePlus.turnOn();
  } on Exception catch (_) {
    // Permissions not yet granted — the BlePermissionScreen handles the retry.
  }
}
