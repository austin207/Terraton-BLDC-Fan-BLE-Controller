// lib/core/background/ble_foreground_service.dart
import 'package:flutter/services.dart';

abstract final class BleForegroundService {
  static const _ch = MethodChannel('com.terraton/bg_service');

  /// Start (or update) the foreground service notification.
  ///
  /// [endsAt] arms the notification's countdown: Android renders and ticks it
  /// itself from that timestamp, so the sleep-timer countdown keeps running
  /// while the app is backgrounded without anything on this side staying
  /// awake. Pass null when no sleep timer is armed.
  static Future<void> start(String label, {DateTime? endsAt}) async {
    try {
      await _ch.invokeMethod<void>('start', {
        'label': label,
        'endAt': endsAt?.millisecondsSinceEpoch ?? 0,
      });
    } on PlatformException catch (_) {}
  }

  /// Update the notification text while the service is already running.
  static Future<void> update(String label, {DateTime? endsAt}) async {
    try {
      await _ch.invokeMethod<void>('update', {
        'label': label,
        'endAt': endsAt?.millisecondsSinceEpoch ?? 0,
      });
    } on PlatformException catch (_) {}
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
    } on PlatformException catch (_) {}
  }
}
