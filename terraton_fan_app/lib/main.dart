// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
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
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Something went wrong.\nPlease restart the app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD32F2F)),
        ),
      ),
    ),
  );

  await CommandLoader.load();
  await initObjectBox();
  await _requestPermissions();
  await _ensureBluetoothOn();

  runApp(const ProviderScope(child: TerratorApp()));
}

Future<void> _requestPermissions() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}

Future<void> _ensureBluetoothOn() async {
  if (!Platform.isAndroid) return;
  if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;
  await FlutterBluePlus.turnOn();
}
