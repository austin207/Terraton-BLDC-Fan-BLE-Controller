// lib/core/storage/fan_repository.dart
import 'dart:convert';
import '../../models/fan_device.dart';
import '../../models/fan_state.dart';
import '../../objectbox.g.dart';
import 'objectbox_store.dart';

abstract class FanRepository {
  List<FanDevice> getAllFans();
  FanDevice? getFanByDeviceId(String deviceId);
  FanDevice? getFanByMac(String macAddress);
  Future<void> saveFan(FanDevice fan);
  Future<void> updateMac(String deviceId, String macAddress);
  Future<void> deleteFan(String deviceId);
  Future<void> renameFan(String deviceId, String newNickname);
  FanState getState(String deviceId);
  Future<void> saveState(FanState fanState);
  String exportToJson();
  Future<int> importFromJson(String json);
}

class FanRepositoryImpl implements FanRepository {
  Box<FanDevice> get _fanBox => store.box<FanDevice>();
  Box<FanState>  get _stateBox => store.box<FanState>();

  @override
  List<FanDevice> getAllFans() =>
      _fanBox.query().order(FanDevice_.addedAt, flags: Order.descending).build().find();

  @override
  FanDevice? getFanByDeviceId(String deviceId) =>
      _fanBox.query(FanDevice_.deviceId.equals(deviceId)).build().findFirst();

  @override
  FanDevice? getFanByMac(String macAddress) {
    if (macAddress.isEmpty) return null;
    return _fanBox.query(FanDevice_.macAddress.equals(macAddress)).build().findFirst();
  }

  @override
  Future<void> saveFan(FanDevice fan) async {
    _fanBox.put(fan);
  }

  @override
  Future<void> updateMac(String deviceId, String macAddress) async {
    final fan = getFanByDeviceId(deviceId);
    if (fan == null) return;
    fan.macAddress = macAddress;
    fan.lastConnectedAt = DateTime.now();
    _fanBox.put(fan);
  }

  @override
  Future<void> deleteFan(String deviceId) async {
    final fan = getFanByDeviceId(deviceId);
    if (fan != null) _fanBox.remove(fan.id);
    final st = _stateBox.query(FanState_.deviceId.equals(deviceId)).build().findFirst();
    if (st != null) _stateBox.remove(st.id);
  }

  @override
  Future<void> renameFan(String deviceId, String newNickname) async {
    final fan = getFanByDeviceId(deviceId);
    if (fan == null) return;
    fan.nickname = newNickname;
    _fanBox.put(fan);
  }

  @override
  FanState getState(String deviceId) {
    return _stateBox.query(FanState_.deviceId.equals(deviceId)).build().findFirst()
        ?? (FanState()..deviceId = deviceId);
  }

  @override
  Future<void> saveState(FanState fanState) async {
    final existing = _stateBox.query(FanState_.deviceId.equals(fanState.deviceId)).build().findFirst();
    if (existing != null) fanState.id = existing.id;
    _stateBox.put(fanState);
  }

  @override
  String exportToJson() {
    final fans = getAllFans();
    final map = {
      'version': 1,
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
    if (map['version'] != 1) throw FormatException('Unsupported export version.');
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
      _fanBox.put(fan);
      imported++;
    }
    return imported;
  }
}
