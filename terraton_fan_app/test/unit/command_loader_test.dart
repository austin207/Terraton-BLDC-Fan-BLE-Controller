// test/unit/command_loader_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  group('CommandLoader - frame verification', () {
    test('statusPoll fixed frame', () {
      expect(CommandLoader.statusPoll(), [0x55, 0xAA, 0x00, 0x00, 0x01, 0x00, 0x01]);
    });

    test('power on  = 55 AA 06 02 01 01 0A', () {
      expect(CommandLoader.power('on'),  [0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x0A]);
    });

    test('power off = 55 AA 06 02 01 00 09', () {
      expect(CommandLoader.power('off'), [0x55, 0xAA, 0x06, 0x02, 0x01, 0x00, 0x09]);
    });

    test('speed 1 = 55 AA 06 04 01 01 0C', () {
      expect(CommandLoader.speed(1), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x01, 0x0C]);
    });

    test('speed 2 = 55 AA 06 04 01 02 0D', () {
      expect(CommandLoader.speed(2), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x02, 0x0D]);
    });

    test('speed 3 = 55 AA 06 04 01 03 0E', () {
      expect(CommandLoader.speed(3), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x03, 0x0E]);
    });

    test('speed 4 = 55 AA 06 04 01 04 0F', () {
      expect(CommandLoader.speed(4), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x04, 0x0F]);
    });

    test('speed 5 = 55 AA 06 04 01 05 10', () {
      expect(CommandLoader.speed(5), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x05, 0x10]);
    });

    test('speed 6 = 55 AA 06 04 01 06 11', () {
      expect(CommandLoader.speed(6), [0x55, 0xAA, 0x06, 0x04, 0x01, 0x06, 0x11]);
    });

    test('boost   = 55 AA 06 21 01 01 29', () {
      expect(CommandLoader.mode('boost'),   [0x55, 0xAA, 0x06, 0x21, 0x01, 0x01, 0x29]);
    });

    test('nature  = 55 AA 06 21 01 02 2A', () {
      expect(CommandLoader.mode('nature'),  [0x55, 0xAA, 0x06, 0x21, 0x01, 0x02, 0x2A]);
    });

    test('reverse = 55 AA 06 21 01 03 2B', () {
      expect(CommandLoader.mode('reverse'), [0x55, 0xAA, 0x06, 0x21, 0x01, 0x03, 0x2B]);
    });

    test('smart   = 55 AA 06 21 01 04 2C', () {
      expect(CommandLoader.mode('smart'),   [0x55, 0xAA, 0x06, 0x21, 0x01, 0x04, 0x2C]);
    });

    test('timer off = 55 AA 06 22 01 00 29', () {
      expect(CommandLoader.timer('off'), [0x55, 0xAA, 0x06, 0x22, 0x01, 0x00, 0x29]);
    });

    test('timer 2h  = 55 AA 06 22 01 02 2B', () {
      expect(CommandLoader.timer('2h'),  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x02, 0x2B]);
    });

    test('timer 4h  = 55 AA 06 22 01 04 2D', () {
      expect(CommandLoader.timer('4h'),  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x04, 0x2D]);
    });

    test('timer 8h  = 55 AA 06 22 01 08 31', () {
      expect(CommandLoader.timer('8h'),  [0x55, 0xAA, 0x06, 0x22, 0x01, 0x08, 0x31]);
    });

    test('queryPower = 55 AA 06 23 01 00 2A', () {
      expect(CommandLoader.queryPower(), [0x55, 0xAA, 0x06, 0x23, 0x01, 0x00, 0x2A]);
    });

    test('querySpeed = 55 AA 06 24 01 00 2B', () {
      expect(CommandLoader.querySpeed(), [0x55, 0xAA, 0x06, 0x24, 0x01, 0x00, 0x2B]);
    });

    test('lightOn returns null (pending in YAML)', () {
      expect(CommandLoader.lightOn(), isNull);
    });

    test('lightOff returns null (pending in YAML)', () {
      expect(CommandLoader.lightOff(), isNull);
    });

    test('custom returns null gracefully for missing key', () {
      expect(CommandLoader.custom(['commands', 'nonexistent', 'action'], [0x01]), isNull);
    });

    test('version is 1.0', () {
      expect(CommandLoader.loadedVersion, '1.0');
    });
  });
}
