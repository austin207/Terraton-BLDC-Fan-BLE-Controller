// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/storage/objectbox_store.dart';
import 'package:terraton_fan_app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = FlutterError.presentError;
  WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
    FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
    return true;
  };
  ErrorWidget.builder = (details) => const Material(
    color: Color(0xFF000000), // kBg — dark theme
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Something went wrong.\nPlease restart the app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
        ),
      ),
    ),
  );

  await CommandLoader.load();
  await initObjectBox();
  // Permissions are requested contextually by BlePermissionScreen after the
  // splash screen checks status. Requesting here (before any UI) shows the
  // system dialog over a blank screen, violating Android UX guidelines.
  await _ensureBluetoothOn();

  runApp(const ProviderScope(child: TerratorApp()));
}

Future<void> _ensureBluetoothOn() async {
  if (!Platform.isAndroid) return;
  try {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;
    await FlutterBluePlus.turnOn();
  } on Object catch (_) {
    // Permissions not yet granted — the BlePermissionScreen handles the retry.
  }
}
