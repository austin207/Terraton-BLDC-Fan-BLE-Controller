// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/commands/command_loader.dart';
import 'core/storage/objectbox_store.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CommandLoader.load();
  await initObjectBox();
  await _requestPermissions();

  runApp(const ProviderScope(child: TerratorApp()));
}

Future<void> _requestPermissions() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}
