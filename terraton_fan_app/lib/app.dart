// lib/app.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class TerratorApp extends ConsumerWidget {
  const TerratorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-prompt the system Bluetooth enable dialog whenever the adapter is
    // turned off mid-session (Android only — iOS does not allow this).
    ref.listen<AsyncValue<BluetoothAdapterState>>(
      bluetoothAdapterStateProvider,
      (prev, next) {
        if (prev?.hasValue != true) return; // skip initial emission to avoid double-prompt
        if (next.valueOrNull == BluetoothAdapterState.off && Platform.isAndroid) {
          unawaited(FlutterBluePlus.turnOn().onError((_, __) {}));
        }
      },
    );

    return MaterialApp.router(
      title: 'Terraton Fan',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
