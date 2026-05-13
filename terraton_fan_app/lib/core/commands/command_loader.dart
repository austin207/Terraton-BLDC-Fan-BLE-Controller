// lib/core/commands/command_loader.dart
// Phase 1: loads from bundled asset only.
// Phase 2 will add remote fetch + local cache (approved, not yet implemented).

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class CommandLoader {
  static YamlMap? _config;

  /// Call once in main.dart before runApp.
  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/commands.yaml');
    _config = loadYaml(raw) as YamlMap;
  }

  static YamlMap get config {
    if (_config == null) {
      throw StateError('CommandLoader.load() must be called before use.');
    }
    return _config!;
  }

  static String get loadedVersion =>
      (config['version'] as Object?)?.toString() ?? '0.0';

  /// Builds a BLE request frame. Returns null if command or data is null (pending).
  static List<int>? buildFrame(int? commandByte, List<int>? data) {
    if (commandByte == null || data == null) return null;
    const reqId = 0x06;
    final len = data.length;
    int sum = reqId + commandByte + len;
    for (final b in data) { sum += b; }
    return [0x55, 0xAA, reqId, commandByte, len, ...data, sum & 0xFF];
  }

  static List<int> statusPoll() =>
      List<int>.from(((config['status_poll'] as YamlMap)['frame']) as YamlList);

  static List<int>? power(String action) {
    final cmd = _safeGet(['commands', 'power']);
    if (cmd == null) return null;
    return buildFrame(
      cmd['command'] as int?,
      _toIntList((cmd['actions'] as YamlMap)[action]),
    );
  }

  static List<int>? speed(int step) {
    if (step < 1 || step > 6) return null;
    final cmd = _safeGet(['commands', 'speed']);
    if (cmd == null) return null;
    return buildFrame(
      cmd['command'] as int?,
      _toIntList((cmd['steps'] as YamlMap)[step]),
    );
  }

  static List<int>? mode(String action) {
    final cmd = _safeGet(['commands', 'modes']);
    if (cmd == null) return null;
    return buildFrame(
      cmd['command'] as int?,
      _toIntList((cmd['actions'] as YamlMap)[action]),
    );
  }

  static List<int>? timer(String action) {
    final cmd = _safeGet(['commands', 'timers']);
    if (cmd == null) return null;
    return buildFrame(
      cmd['command'] as int?,
      _toIntList((cmd['actions'] as YamlMap)[action]),
    );
  }

  static List<int>? queryPower() {
    final q = _safeGet(['commands', 'queries', 'power_consumption']);
    if (q == null) return null;
    return buildFrame(q['command'] as int?, _toIntList(q['data']));
  }

  static List<int>? querySpeed() {
    final q = _safeGet(['commands', 'queries', 'running_speed']);
    if (q == null) return null;
    return buildFrame(q['command'] as int?, _toIntList(q['data']));
  }

  static List<int>? lightOn() {
    final l = _safeGet(['commands', 'lighting', 'on']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, _toIntList(l['data']));
  }

  static List<int>? lightOff() {
    final l = _safeGet(['commands', 'lighting', 'off']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, _toIntList(l['data']));
  }

  static List<int>? lightColorTemp(int value) {
    final l = _safeGet(['commands', 'lighting', 'color_temp']);
    if (l == null) return null;
    return buildFrame(l['command'] as int?, [value]);
  }

  /// Generic accessor for any new command section added to commands.yaml.
  /// Returns null gracefully if key path does not exist.
  static List<int>? custom(List<String> path, List<int>? data) {
    final node = _safeGet(path);
    if (node == null) return null;
    final cmd = node['command'] as int?;
    return buildFrame(cmd, data);
  }

  static YamlMap? _safeGet(List<String> path) {
    if (path.isEmpty) return null;
    Object? node = config;
    for (final key in path) {
      if (node is! YamlMap || !node.containsKey(key)) return null;
      node = node[key] as Object?;
    }
    return node is YamlMap ? node : null;
  }

  static List<int>? _toIntList(Object? yaml) {
    if (yaml == null) return null;
    return List<int>.from((yaml as YamlList).map((e) => e as int));
  }
}
