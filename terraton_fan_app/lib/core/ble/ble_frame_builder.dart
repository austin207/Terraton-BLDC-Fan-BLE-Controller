// lib/core/ble/ble_frame_builder.dart
// All frames come from CommandLoader (YAML). This class is a typed facade.
// Do not hardcode any bytes here.
// Do not call BleFrameBuilder directly from UI widgets — go through ControlScreenNotifier.

import '../commands/command_loader.dart';

class BleFrameBuilder {
  static List<int>  statusPoll()          => CommandLoader.statusPoll();
  static List<int>? powerOn()             => CommandLoader.power('on');
  static List<int>? powerOff()            => CommandLoader.power('off');
  static List<int>? setSpeed(int step)    => CommandLoader.speed(step);
  static List<int>? setBoost()            => CommandLoader.mode('boost');
  static List<int>? setNature()           => CommandLoader.mode('nature');
  static List<int>? setReverse()          => CommandLoader.mode('reverse');
  static List<int>? setSmart()            => CommandLoader.mode('smart');
  static List<int>? timerOff()            => CommandLoader.timer('off');
  static List<int>? timer2h()             => CommandLoader.timer('2h');
  static List<int>? timer4h()             => CommandLoader.timer('4h');
  static List<int>? timer8h()             => CommandLoader.timer('8h');
  static List<int>? queryPower()          => CommandLoader.queryPower();
  static List<int>? querySpeed()          => CommandLoader.querySpeed();
  static List<int>? lightOn()             => CommandLoader.lightOn();
  static List<int>? lightOff()            => CommandLoader.lightOff();
  static List<int>? lightColorTemp(int v) => CommandLoader.lightColorTemp(v);
}
