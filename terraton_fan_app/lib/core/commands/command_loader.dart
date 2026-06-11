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
    // Checksum = sum of ALL frame bytes before the checksum (including 0x55 0xAA header).
    int sum = 0x55 + 0xAA + reqId + commandByte + len;
    for (final b in data) { sum += b; }
    return [0x55, 0xAA, reqId, commandByte, len, ...data, sum & 0xFF];
  }

  // ── Protocol byte accessors (read from YAML — no hardcoding in Dart) ────────

  /// The two-byte frame header [0x55, 0xAA].
  static List<int> get frameHeader {
    final p = _safeGet(['protocol']);
    if (p == null) return const [0x55, 0xAA];
    return _toIntList(p['header']) ?? const [0x55, 0xAA];
  }

  /// Packet ID that identifies a response frame (0x07).
  static int get responsePacketId {
    final p = _safeGet(['protocol']);
    return (p?['response_packet_id'] as int?) ?? 0x07;
  }

  /// Command byte for a named response, e.g. 'power_watts', 'running_rpm'.
  /// Returns null if the key is missing from response_commands in the YAML.
  static int? responseCommand(String key) {
    final rc = _safeGet(['response_commands']);
    return rc?[key] as int?;
  }

  // ── Fixed frames ──────────────────────────────────────────────────────────

  static List<int> statusPoll() {
    final node = _safeGet(['status_poll']);
    if (node == null) throw StateError('status_poll missing from commands.yaml');
    return List<int>.from((node['frame'] as YamlList));
  }

  static List<int> getMotorState() {
    final node = _safeGet(['get_motor_state']);
    if (node == null) throw StateError('get_motor_state missing from commands.yaml');
    return List<int>.from((node['frame'] as YamlList));
  }

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
      _toIntList((cmd['steps'] as YamlMap)['$step']),
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
