// lib/core/background/ble_foreground_service.dart
import 'package:flutter/services.dart';

abstract final class BleForegroundService {
  static const _ch = MethodChannel('com.terraton/bg_service');

  /// Start (or update) the foreground service notification.
  static Future<void> start(String label) async {
    try {
      await _ch.invokeMethod<void>('start', {'label': label});
    } on PlatformException catch (_) {}
  }

  /// Update the notification text while the service is already running.
  static Future<void> update(String label) async {
    try {
      await _ch.invokeMethod<void>('update', {'label': label});
    } on PlatformException catch (_) {}
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
    } on PlatformException catch (_) {}
  }
}
