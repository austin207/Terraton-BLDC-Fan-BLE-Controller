// test/unit/service_qr_test.dart
//
// Tests for ServiceQrModal.computeQrPayload — verifies the JSON structure
// that QrScanScreen._handleServiceAccess expects on the scanning side.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/settings/service_qr_modal.dart';
import 'package:terraton_fan_app/models/fan_device.dart';

FanDevice _fan({
  String mac      = 'AA:BB:CC:DD:EE:FF',
  String nickname = 'Living Room Fan',
  String model    = 'TN-CF-01',
}) =>
    FanDevice()
      ..deviceId   = 'dev1'
      ..macAddress = mac
      ..nickname   = nickname
      ..model      = model
      ..addedAt    = DateTime(2026, 1, 1);

void main() {
  group('ServiceQrModal.computeQrPayload — JSON structure', () {
    test('encodes all required fields with correct types', () {
      final fan    = _fan();
      final expiry = DateTime(2026, 6, 6, 15, 0, 0);
      final p = jsonDecode(ServiceQrModal.computeQrPayload(fan, expiry))
          as Map<String, dynamic>;

      expect(p['type'],         'service_access');
      expect(p['version'],      1);
      expect(p['fan_mac'],      'AA:BB:CC:DD:EE:FF');
      expect(p['fan_nickname'], 'Living Room Fan');
      expect(p['model'],        'TN-CF-01');
      expect(p['expires_at'],   isA<int>());
    });

    test('expires_at is Unix seconds (milliseconds ~/ 1000)', () {
      final expiry = DateTime(2026, 6, 6, 15, 0, 0);
      final p = jsonDecode(ServiceQrModal.computeQrPayload(_fan(), expiry))
          as Map<String, dynamic>;

      expect(p['expires_at'], expiry.millisecondsSinceEpoch ~/ 1000);
    });

    test('expires_at round-trips through the scanner decode unchanged', () {
      // Simulates QrScanScreen._handleServiceAccess:
      //   final expSecs = json['expires_at'] as int;
      //   final expiresAt = DateTime.fromMillisecondsSinceEpoch(expSecs * 1000);
      final expiry = DateTime(2026, 6, 6, 15, 0, 0);
      final p = jsonDecode(ServiceQrModal.computeQrPayload(_fan(), expiry))
          as Map<String, dynamic>;

      final decoded = DateTime.fromMillisecondsSinceEpoch(
          (p['expires_at'] as int) * 1000);
      expect(decoded.difference(expiry).abs().inSeconds,
          lessThanOrEqualTo(1));
    });

    test('a 3-hour TTL expires_at is approximately now + 3 h', () {
      final now    = DateTime.now();
      final expiry = now.add(const Duration(hours: 3));
      final p = jsonDecode(ServiceQrModal.computeQrPayload(_fan(), expiry))
          as Map<String, dynamic>;

      final decoded = DateTime.fromMillisecondsSinceEpoch(
          (p['expires_at'] as int) * 1000);
      final diff = decoded.difference(now).inSeconds;
      // Allow ±2 s to cover millisecond truncation and test execution time.
      expect(diff, closeTo(3 * 3600, 2));
    });

    test('a freshly generated QR has not expired yet', () {
      final expiry = DateTime.now().add(const Duration(hours: 3));
      final p = jsonDecode(ServiceQrModal.computeQrPayload(_fan(), expiry))
          as Map<String, dynamic>;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          (p['expires_at'] as int) * 1000);
      expect(DateTime.now().isBefore(expiresAt), isTrue);
    });

    test('a past expiry is correctly detected as expired by scanner logic', () {
      final expiry = DateTime.now().subtract(const Duration(seconds: 1));
      final p = jsonDecode(ServiceQrModal.computeQrPayload(_fan(), expiry))
          as Map<String, dynamic>;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          (p['expires_at'] as int) * 1000);
      expect(DateTime.now().isAfter(expiresAt), isTrue);
    });

    test('fan nickname and model are preserved verbatim', () {
      final fan = _fan(nickname: 'Master Bedroom', model: 'TN-CF-07');
      final expiry = DateTime(2026, 6, 6, 15, 0, 0);
      final p = jsonDecode(ServiceQrModal.computeQrPayload(fan, expiry))
          as Map<String, dynamic>;

      expect(p['fan_nickname'], 'Master Bedroom');
      expect(p['model'],        'TN-CF-07');
    });

    test('empty MAC is encoded as empty string', () {
      // The picker blocks generation without a MAC but we verify the encoding.
      final fan = _fan(mac: '');
      final expiry = DateTime(2026, 6, 6, 15, 0, 0);
      final p = jsonDecode(ServiceQrModal.computeQrPayload(fan, expiry))
          as Map<String, dynamic>;

      expect(p['fan_mac'], '');
    });
  });
}
