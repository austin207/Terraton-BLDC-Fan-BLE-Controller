// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/storage/objectbox_store.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/objectbox.g.dart';
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
  _seedDemoFan();
  await _requestPermissions();

  runApp(const ProviderScope(child: TerratorApp()));
}

void _seedDemoFan() {
  const demoId = 'demo-fan-001';
  final box = store.box<FanDevice>();
  final q = box.query(FanDevice_.deviceId.equals(demoId)).build();
  final alreadyExists = q.count() > 0;
  q.close();
  if (alreadyExists) return;

  final demo = FanDevice()
    ..deviceId = demoId
    ..macAddress = ''
    ..model = 'Terraton AC-05-3'
    ..nickname = 'Living Room Fan'
    ..fwVersion = '1.0.0'
    ..addedAt = DateTime.now()
    ..lastConnectedAt = DateTime.now().subtract(const Duration(hours: 2));
  box.put(demo);
}

Future<void> _requestPermissions() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}
