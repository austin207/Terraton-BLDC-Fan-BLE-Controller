// test/unit/fan_device_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/models/fan_device.dart';

void main() {
  group('FanDevice defaults', () {
    test('id defaults to 0', () {
      expect(FanDevice().id, 0);
    });

    test('deviceId defaults to empty string', () {
      expect(FanDevice().deviceId, '');
    });

    test('macAddress defaults to empty string', () {
      expect(FanDevice().macAddress, '');
    });

    test('model defaults to empty string', () {
      expect(FanDevice().model, '');
    });

    test('nickname defaults to empty string', () {
      expect(FanDevice().nickname, '');
    });

    test('fwVersion defaults to empty string', () {
      expect(FanDevice().fwVersion, '');
    });

    test('lastConnectedAt defaults to null', () {
      expect(FanDevice().lastConnectedAt, isNull);
    });

    test('isServiceAccess defaults to false', () {
      expect(FanDevice().isServiceAccess, isFalse);
    });

    test('serviceExpiresAt defaults to null', () {
      expect(FanDevice().serviceExpiresAt, isNull);
    });
  });

  group('FanDevice field mutation', () {
    test('fields can be set and read back', () {
      final fan = FanDevice()
        ..deviceId = 'TT-001'
        ..macAddress = 'AA:BB:CC:DD:EE:FF'
        ..nickname = 'Bedroom'
        ..model = 'Terraton X1'
        ..fwVersion = '1.0'
        ..addedAt = DateTime(2026, 1, 1);

      expect(fan.deviceId, 'TT-001');
      expect(fan.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(fan.nickname, 'Bedroom');
      expect(fan.model, 'Terraton X1');
      expect(fan.fwVersion, '1.0');
    });

    test('isServiceAccess and serviceExpiresAt can be set together', () {
      final expiry = DateTime(2026, 6, 1, 12, 0);
      final fan = FanDevice()
        ..isServiceAccess = true
        ..serviceExpiresAt = expiry;

      expect(fan.isServiceAccess, isTrue);
      expect(fan.serviceExpiresAt, expiry);
    });

    test('lastConnectedAt can be set', () {
      final ts = DateTime(2026, 5, 20);
      final fan = FanDevice()..lastConnectedAt = ts;
      expect(fan.lastConnectedAt, ts);
    });
  });
}
