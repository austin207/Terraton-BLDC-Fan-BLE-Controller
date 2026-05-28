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
import 'package:terraton_fan_app/core/storage/objectbox_store.dart';
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
import 'package:terraton_fan_app/core/upload/data_upload_service.dart';
import 'package:terraton_fan_app/core/upload/device_ping_service.dart';
import 'package:terraton_fan_app/shared/theme.dart';
import 'package:terraton_fan_app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  FlutterError.onError = FlutterError.presentError;
  WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
    FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
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
  await initObjectBox();
  // Permissions are requested contextually by BlePermissionScreen after the
  // splash screen checks status. Requesting here (before any UI) shows the
  // system dialog over a blank screen, violating Android UX guidelines.
  await _ensureBluetoothOn();

  // Fire-and-forget — anonymous heartbeat; tells Cloudflare this device is active.
  unawaited(DevicePingService.ping());
  // Fire-and-forget — uploads previous days' summaries if user opted in + Wi-Fi.
  unawaited(DataUploadService.tryUpload(UsageLogRepositoryImpl(store)));

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
