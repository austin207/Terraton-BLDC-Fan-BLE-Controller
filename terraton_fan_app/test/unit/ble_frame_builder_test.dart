// test/unit/ble_frame_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/commands/command_loader.dart';
import 'package:terraton_fan_app/core/ble/ble_frame_builder.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CommandLoader.load();
  });

  test('statusPoll', () =>
      expect(BleFrameBuilder.statusPoll(), [0x55, 0xAA, 0x00, 0x00, 0x01, 0x00, 0x01]));

  test('powerOn',  () =>
      expect(BleFrameBuilder.powerOn(),  [0x55, 0xAA, 0x06, 0x02, 0x01, 0x01, 0x0A]));

  test('powerOff', () =>
      expect(BleFrameBuilder.powerOff(), [0x55, 0xAA, 0x06, 0x02, 0x01, 0x00, 0x09]));

  for (int i = 1; i <= 6; i++) {
    final step = i;
    test('setSpeed($step)', () =>
        expect(BleFrameBuilder.setSpeed(step), isNotNull));
  }

  test('setBoost',   () => expect(BleFrameBuilder.setBoost(),   [0x55, 0xAA, 0x06, 0x21, 0x01, 0x01, 0x29]));
  test('setNature',  () => expect(BleFrameBuilder.setNature(),  [0x55, 0xAA, 0x06, 0x21, 0x01, 0x02, 0x2A]));
  test('setReverse', () => expect(BleFrameBuilder.setReverse(), [0x55, 0xAA, 0x06, 0x21, 0x01, 0x03, 0x2B]));
  test('setSmart',   () => expect(BleFrameBuilder.setSmart(),   [0x55, 0xAA, 0x06, 0x21, 0x01, 0x04, 0x2C]));
  test('timerOff',   () => expect(BleFrameBuilder.timerOff(),   [0x55, 0xAA, 0x06, 0x22, 0x01, 0x00, 0x29]));
  test('timer2h',    () => expect(BleFrameBuilder.timer2h(),    [0x55, 0xAA, 0x06, 0x22, 0x01, 0x02, 0x2B]));
  test('timer4h',    () => expect(BleFrameBuilder.timer4h(),    [0x55, 0xAA, 0x06, 0x22, 0x01, 0x04, 0x2D]));
  test('timer8h',    () => expect(BleFrameBuilder.timer8h(),    [0x55, 0xAA, 0x06, 0x22, 0x01, 0x08, 0x31]));
  test('queryPower', () => expect(BleFrameBuilder.queryPower(), [0x55, 0xAA, 0x06, 0x23, 0x01, 0x00, 0x2A]));
  test('querySpeed', () => expect(BleFrameBuilder.querySpeed(), [0x55, 0xAA, 0x06, 0x24, 0x01, 0x00, 0x2B]));
  test('lightOn returns null', () => expect(BleFrameBuilder.lightOn(),  isNull));
  test('lightOff returns null', () => expect(BleFrameBuilder.lightOff(), isNull));
}
