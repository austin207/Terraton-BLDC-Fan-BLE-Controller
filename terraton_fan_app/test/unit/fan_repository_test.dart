// test/unit/fan_repository_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/storage/fan_repository.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

// In-memory implementation — avoids ObjectBox native dependency in unit tests.
class _FakeRepo implements FanRepository {
  final List<FanDevice> _fans   = [];
  final List<FanState>  _states = [];

  @override
  List<FanDevice> getAllFans() => List.from(_fans);

  @override
  FanDevice? getFanByDeviceId(String deviceId) {
    try {
      return _fans.firstWhere((f) => f.deviceId == deviceId);
    } on StateError catch (_) {
      return null;
    }
  }

  @override
  FanDevice? getFanByMac(String macAddress) {
    if (macAddress.isEmpty) return null;
    try {
      return _fans.firstWhere((f) => f.macAddress == macAddress);
    } on StateError catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveFan(FanDevice fan) async {
    _fans.removeWhere((f) => f.deviceId == fan.deviceId);
    _fans.add(fan);
  }

  @override
  Future<void> updateMac(String deviceId, String macAddress) async {
    final fan = getFanByDeviceId(deviceId);
    if (fan == null) return;
    fan.macAddress      = macAddress;
    fan.lastConnectedAt = DateTime.now();
  }

  @override
  Future<void> deleteFan(String deviceId) async {
    _fans.removeWhere((f) => f.deviceId == deviceId);
    _states.removeWhere((s) => s.deviceId == deviceId);
  }

  @override
  Future<void> renameFan(String deviceId, String newNickname) async {
    final fan = getFanByDeviceId(deviceId);
    if (fan == null) return;
    fan.nickname = newNickname;
  }

  @override
  FanState getState(String deviceId) {
    try {
      return _states.firstWhere((s) => s.deviceId == deviceId);
    } on StateError catch (_) {
      return FanState()..deviceId = deviceId;
    }
  }

  @override
  Future<void> saveState(FanState fanState) async {
    _states.removeWhere((s) => s.deviceId == fanState.deviceId);
    _states.add(fanState);
  }

  @override
  String exportToJson() {
    final fans = getAllFans();
    final map = {
      'version':     1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'fans': fans.map((f) => {
        'device_id':   f.deviceId,
        'mac_address': f.macAddress,
        'model':       f.model,
        'nickname':    f.nickname,
        'fw_version':  f.fwVersion,
        'added_at':    f.addedAt.toUtc().toIso8601String(),
      }).toList(),
    };
    return jsonEncode(map);
  }

  @override
  Future<int> importFromJson(String json) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    if (map['version'] != 1) throw const FormatException('Unsupported export version.');
    final fans = (map['fans'] as List).cast<Map<String, dynamic>>();
    int imported = 0;
    for (final f in fans) {
      final deviceId   = f['device_id']   as String? ?? '';
      final macAddress = f['mac_address'] as String? ?? '';
      final nickname   = f['nickname']    as String? ?? '';
      if (deviceId.isEmpty || nickname.isEmpty) continue;
      if (getFanByDeviceId(deviceId) != null) continue;
      final fan = FanDevice()
        ..deviceId   = deviceId
        ..macAddress = macAddress
        ..model      = f['model']      as String? ?? ''
        ..nickname   = nickname
        ..fwVersion  = f['fw_version'] as String? ?? ''
        ..addedAt    = DateTime.tryParse(f['added_at'] as String? ?? '') ?? DateTime.now();
      await saveFan(fan);
      imported++;
    }
    return imported;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

FanDevice _makeFan({
  String id      = 'TT-001',
  String mac     = '',
  String name    = 'Bedroom Fan',
  String model   = 'Terraton X1',
  String version = '1.0',
}) {
  return FanDevice()
    ..deviceId   = id
    ..macAddress = mac
    ..nickname   = name
    ..model      = model
    ..fwVersion  = version
    ..addedAt    = DateTime(2026, 1, 1);
}

String _validJson({
  String id   = 'TT-001',
  String mac  = 'AA:BB:CC:DD:EE:FF',
  String name = 'Bedroom Fan',
}) =>
    jsonEncode({
      'version': 1,
      'fans': [
        {
          'device_id':   id,
          'mac_address': mac,
          'model':       'Terraton X1',
          'nickname':    name,
          'fw_version':  '1.0',
          'added_at':    '2026-01-01T00:00:00.000Z',
        }
      ],
    });

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeRepo repo;

  setUp(() => repo = _FakeRepo());

  // ── saveFan / getAllFans ──────────────────────────────────────────────────

  group('saveFan / getAllFans', () {
    test('saved fan appears in getAllFans', () async {
      await repo.saveFan(_makeFan());
      expect(repo.getAllFans(), hasLength(1));
      expect(repo.getAllFans().first.deviceId, 'TT-001');
    });

    test('saving same deviceId replaces existing entry', () async {
      await repo.saveFan(_makeFan(name: 'Old'));
      await repo.saveFan(_makeFan(name: 'New'));
      expect(repo.getAllFans(), hasLength(1));
      expect(repo.getAllFans().first.nickname, 'New');
    });

    test('multiple distinct fans are all returned', () async {
      await repo.saveFan(_makeFan(id: 'TT-001'));
      await repo.saveFan(_makeFan(id: 'TT-002'));
      expect(repo.getAllFans(), hasLength(2));
    });
  });

  // ── getFanByDeviceId ──────────────────────────────────────────────────────

  group('getFanByDeviceId', () {
    test('returns fan when found', () async {
      await repo.saveFan(_makeFan());
      expect(repo.getFanByDeviceId('TT-001'), isNotNull);
    });

    test('returns null when not found', () {
      expect(repo.getFanByDeviceId('MISSING'), isNull);
    });
  });

  // ── getFanByMac ───────────────────────────────────────────────────────────

  group('getFanByMac', () {
    test('returns fan for matching MAC', () async {
      await repo.saveFan(_makeFan(mac: 'AA:BB:CC:DD:EE:FF'));
      expect(repo.getFanByMac('AA:BB:CC:DD:EE:FF'), isNotNull);
    });

    test('returns null for empty MAC argument', () async {
      await repo.saveFan(_makeFan(mac: 'AA:BB:CC:DD:EE:FF'));
      expect(repo.getFanByMac(''), isNull);
    });

    test('returns null when no MAC matches', () async {
      await repo.saveFan(_makeFan(mac: 'AA:BB:CC:DD:EE:FF'));
      expect(repo.getFanByMac('00:11:22:33:44:55'), isNull);
    });
  });

  // ── updateMac ─────────────────────────────────────────────────────────────

  group('updateMac', () {
    test('sets macAddress and lastConnectedAt', () async {
      await repo.saveFan(_makeFan());
      await repo.updateMac('TT-001', 'AA:BB:CC:DD:EE:FF');
      final fan = repo.getFanByDeviceId('TT-001')!;
      expect(fan.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(fan.lastConnectedAt, isNotNull);
    });

    test('no-op when deviceId not found', () async {
      await repo.updateMac('MISSING', 'AA:BB');
      // should not throw
    });
  });

  // ── deleteFan ─────────────────────────────────────────────────────────────

  group('deleteFan', () {
    test('removes fan from list', () async {
      await repo.saveFan(_makeFan());
      await repo.deleteFan('TT-001');
      expect(repo.getAllFans(), isEmpty);
    });

    test('removes associated FanState', () async {
      await repo.saveFan(_makeFan());
      await repo.saveState(FanState()
        ..deviceId = 'TT-001'
        ..speed    = 3);
      await repo.deleteFan('TT-001');
      final st = repo.getState('TT-001');
      expect(st.speed, 0);  // default state returned
    });

    test('no-op for missing fan', () async {
      await repo.deleteFan('MISSING');
    });
  });

  // ── renameFan ─────────────────────────────────────────────────────────────

  group('renameFan', () {
    test('updates nickname', () async {
      await repo.saveFan(_makeFan(name: 'Old'));
      await repo.renameFan('TT-001', 'New Name');
      expect(repo.getFanByDeviceId('TT-001')!.nickname, 'New Name');
    });

    test('no-op for missing fan', () async {
      await repo.renameFan('MISSING', 'New Name');
    });
  });

  // ── getState / saveState ──────────────────────────────────────────────────

  group('getState / saveState', () {
    test('returns default FanState when none saved', () {
      final st = repo.getState('TT-999');
      expect(st.deviceId, 'TT-999');
      expect(st.speed, 0);
      expect(st.isPowered, false);
    });

    test('returns previously saved state', () async {
      final st = FanState()
        ..deviceId  = 'TT-001'
        ..speed     = 3
        ..isPowered = true;
      await repo.saveState(st);
      final loaded = repo.getState('TT-001');
      expect(loaded.speed, 3);
      expect(loaded.isPowered, true);
    });

    test('saving state for same deviceId replaces existing', () async {
      await repo.saveState(FanState()..deviceId = 'TT-001'..speed = 1);
      await repo.saveState(FanState()..deviceId = 'TT-001'..speed = 5);
      expect(repo.getState('TT-001').speed, 5);
    });
  });

  // ── exportToJson ──────────────────────────────────────────────────────────

  group('exportToJson', () {
    test('version field is 1', () async {
      final map = jsonDecode(repo.exportToJson()) as Map<String, dynamic>;
      expect(map['version'], 1);
    });

    test('empty repo produces empty fans array', () {
      final map = jsonDecode(repo.exportToJson()) as Map<String, dynamic>;
      expect((map['fans'] as List), isEmpty);
    });

    test('fan fields appear with correct values', () async {
      await repo.saveFan(_makeFan(
        id:   'TT-FAN-00123',
        mac:  'A4:C1:38:2F:1B:9E',
        name: 'Bedroom Fan',
      ));
      final map  = jsonDecode(repo.exportToJson()) as Map<String, dynamic>;
      final fans = (map['fans'] as List).cast<Map<String, dynamic>>();
      expect(fans, hasLength(1));
      expect(fans[0]['device_id'],   'TT-FAN-00123');
      expect(fans[0]['mac_address'], 'A4:C1:38:2F:1B:9E');
      expect(fans[0]['nickname'],    'Bedroom Fan');
      expect(fans[0]['model'],       'Terraton X1');
      expect(fans[0]['fw_version'],  '1.0');
    });

    test('exported JSON contains added_at in ISO-8601 format', () async {
      await repo.saveFan(_makeFan());
      final map  = jsonDecode(repo.exportToJson()) as Map<String, dynamic>;
      final fans = (map['fans'] as List).cast<Map<String, dynamic>>();
      expect(() => DateTime.parse(fans[0]['added_at'] as String), returnsNormally);
    });
  });

  // ── importFromJson ────────────────────────────────────────────────────────

  group('importFromJson', () {
    test('returns 1 for a single valid fan', () async {
      expect(await repo.importFromJson(_validJson()), 1);
    });

    test('imported fan is queryable by deviceId', () async {
      await repo.importFromJson(_validJson(id: 'TT-FAN-00123'));
      expect(repo.getFanByDeviceId('TT-FAN-00123'), isNotNull);
    });

    test('imported fan has correct MAC and nickname', () async {
      await repo.importFromJson(_validJson(mac: 'A4:C1:38:2F:1B:9E', name: 'Living Room'));
      final fan = repo.getFanByDeviceId('TT-001')!;
      expect(fan.macAddress, 'A4:C1:38:2F:1B:9E');
      expect(fan.nickname,   'Living Room');
    });

    test('throws FormatException for unsupported version', () {
      final bad = jsonEncode({'version': 2, 'fans': <Map<String, dynamic>>[]});
      expect(repo.importFromJson(bad), throwsA(isA<FormatException>()));
    });

    test('skips fan with empty device_id', () async {
      final json = jsonEncode({
        'version': 1,
        'fans': [
          {
            'device_id':   '',
            'mac_address': 'AA:BB',
            'nickname':    'Fan',
            'model':       '',
            'fw_version':  '',
            'added_at':    '2026-01-01T00:00:00Z',
          }
        ],
      });
      expect(await repo.importFromJson(json), 0);
      expect(repo.getAllFans(), isEmpty);
    });

    test('skips fan with empty nickname', () async {
      final json = jsonEncode({
        'version': 1,
        'fans': [
          {
            'device_id':   'TT-001',
            'mac_address': 'AA:BB',
            'nickname':    '',
            'model':       '',
            'fw_version':  '',
            'added_at':    '2026-01-01T00:00:00Z',
          }
        ],
      });
      expect(await repo.importFromJson(json), 0);
    });

    test('skips duplicate device_id', () async {
      await repo.saveFan(_makeFan(id: 'TT-001'));
      expect(await repo.importFromJson(_validJson(id: 'TT-001')), 0);
      expect(repo.getAllFans(), hasLength(1));
    });

    test('imports only new fans when list has both duplicates and new', () async {
      await repo.saveFan(_makeFan(id: 'TT-001'));
      final json = jsonEncode({
        'version': 1,
        'fans': [
          {
            'device_id':   'TT-001',
            'mac_address': 'AA:BB',
            'nickname':    'Old',
            'model':       '',
            'fw_version':  '',
            'added_at':    '2026-01-01T00:00:00Z',
          },
          {
            'device_id':   'TT-002',
            'mac_address': 'CC:DD',
            'nickname':    'New',
            'model':       '',
            'fw_version':  '',
            'added_at':    '2026-01-01T00:00:00Z',
          },
        ],
      });
      expect(await repo.importFromJson(json), 1);
      expect(repo.getAllFans(), hasLength(2));
    });

    test('export → import round-trip preserves fan data', () async {
      await repo.saveFan(_makeFan(
        id:   'TT-001',
        mac:  'AA:BB:CC:DD:EE:FF',
        name: 'Main Fan',
      ));
      final exported = repo.exportToJson();

      final repo2 = _FakeRepo();
      await repo2.importFromJson(exported);

      expect(repo2.getAllFans(), hasLength(1));
      final fan = repo2.getFanByDeviceId('TT-001')!;
      expect(fan.nickname,   'Main Fan');
      expect(fan.macAddress, 'AA:BB:CC:DD:EE:FF');
    });
  });
}
