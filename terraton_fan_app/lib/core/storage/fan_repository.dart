// lib/core/storage/fan_repository.dart
import 'dart:convert';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/objectbox.g.dart';

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

  // ── Field-scoped persistence ────────────────────────────────────────────
  // Each method writes ONLY its own field group, mutating the stored row —
  // a telemetry write can physically never touch the operating state, a
  // timer write never touches lighting, and so on. This is what makes the
  // control screen's connect-time display blank structurally unable to leak
  // into the DB: the old whole-row saveState funnel let ANY write that
  // followed resetOnConnect() (a watts or runtime frame from the connect
  // burst) overwrite the persisted operating state — the vector through
  // which six consecutive reconnect fixes died in the field.

  /// Power / boost / speed / active mode — the operating state.
  Future<void> saveOperatingState(
    String deviceId, {
    required bool isPowered,
    required bool isBoost,
    required int speed,
    required String? activeMode,
  });

  /// Sleep-timer code + app-side countdown start. The fan never reports
  /// remaining time (vendor protocol doc lists no timer field at all), so
  /// this pair is the countdown's only source of truth across reconnects.
  Future<void> saveTimerState(
    String deviceId, {
    required int? activeTimerCode,
    required DateTime? timerActivatedAt,
  });

  /// Watts / RPM / cumulative runtime.
  Future<void> saveTelemetry(
    String deviceId, {
    required int? lastWatts,
    required int? lastRpm,
    required int? lastRuntimeSecs,
  });

  /// Lighting panel UI state.
  Future<void> saveLighting(
    String deviceId, {
    required String colorType,
    required double brightness,
    required bool isOn,
  });

  /// Persists the "open" usage-log segment for Last Known State Continuation —
  /// independent of [saveState] so frequent telemetry-driven writes don't
  /// touch the live Riverpod fan state.
  Future<void> saveOpenSegment(
    String deviceId, {
    required DateTime start,
    required int gear,
    String? mode,
    int? smartBaselineGear,
    required int wattsSum,
    required int wattsCount,
    required int rpmSum,
    required int rpmCount,
  });

  String exportToJson();
  Future<int> importFromJson(String json);
}

class FanRepositoryImpl implements FanRepository {
  final Store _store;
  FanRepositoryImpl(this._store);

  Box<FanDevice> get _fanBox => _store.box<FanDevice>();
  Box<FanState>  get _stateBox => _store.box<FanState>();

  static R _useQuery<T, R>(Query<T> q, R Function(Query<T>) fn) {
    try { return fn(q); } finally { q.close(); }
  }

  @override
  List<FanDevice> getAllFans() => _useQuery(
      _fanBox.query().order(FanDevice_.addedAt, flags: Order.descending).build(),
      (q) => q.find());

  @override
  FanDevice? getFanByDeviceId(String deviceId) => _useQuery(
      _fanBox.query(FanDevice_.deviceId.equals(deviceId)).build(),
      (q) => q.findFirst());

  @override
  FanDevice? getFanByMac(String macAddress) {
    if (macAddress.isEmpty) return null;
    return _useQuery(
        _fanBox.query(FanDevice_.macAddress.equals(macAddress)).build(),
        (q) => q.findFirst());
  }

  @override
  Future<void> saveFan(FanDevice fan) {
    _fanBox.put(fan);
    return Future<void>.value();
  }

  @override
  Future<void> updateMac(String deviceId, String macAddress) {
    final fan = getFanByDeviceId(deviceId);
    if (fan != null) {
      fan.macAddress = macAddress;
      fan.lastConnectedAt = DateTime.now();
      _fanBox.put(fan);
    }
    return Future<void>.value();
  }

  @override
  Future<void> deleteFan(String deviceId) {
    final fan = getFanByDeviceId(deviceId);
    if (fan != null) _fanBox.remove(fan.id);
    final st = _useQuery(
        _stateBox.query(FanState_.deviceId.equals(deviceId)).build(),
        (q) => q.findFirst());
    if (st != null) _stateBox.remove(st.id);
    return Future<void>.value();
  }

  @override
  Future<void> renameFan(String deviceId, String newNickname) {
    final fan = getFanByDeviceId(deviceId);
    if (fan != null) {
      fan.nickname = newNickname;
      _fanBox.put(fan);
    }
    return Future<void>.value();
  }

  @override
  FanState getState(String deviceId) {
    return _useQuery(
        _stateBox.query(FanState_.deviceId.equals(deviceId)).build(),
        (q) => q.findFirst())
        ?? (FanState()..deviceId = deviceId);
  }

  @override
  Future<void> saveState(FanState fanState) async {
    final existing = _useQuery(
        _stateBox.query(FanState_.deviceId.equals(fanState.deviceId)).build(),
        (q) => q.findFirst());
    // Copy before mutating so the live Riverpod state object is never modified
    // outside a Riverpod state transition. The live state never carries open-segment
    // bookkeeping, so preserve whatever is already persisted for those fields.
    final toSave = existing != null
        ? (fanState.copyWith()
          ..id                       = existing.id
          ..openSegmentStart         = existing.openSegmentStart
          ..openSegmentGear          = existing.openSegmentGear
          ..openSegmentMode          = existing.openSegmentMode
          ..openSegmentSmartBaseline = existing.openSegmentSmartBaseline
          ..openSegmentWattsSum      = existing.openSegmentWattsSum
          ..openSegmentWattsCount    = existing.openSegmentWattsCount
          ..openSegmentRpmSum        = existing.openSegmentRpmSum
          ..openSegmentRpmCount      = existing.openSegmentRpmCount)
        : fanState;
    _stateBox.put(toSave);
  }

  // getState returns the live queried entity (with its ObjectBox id) or a
  // fresh row keyed to the deviceId — mutate + put is the same pattern
  // saveOpenSegment established.

  @override
  Future<void> saveOperatingState(
    String deviceId, {
    required bool isPowered,
    required bool isBoost,
    required int speed,
    required String? activeMode,
  }) async {
    final row = getState(deviceId)
      ..isPowered  = isPowered
      ..isBoost    = isBoost
      ..speed      = speed
      ..activeMode = activeMode;
    _stateBox.put(row);
  }

  @override
  Future<void> saveTimerState(
    String deviceId, {
    required int? activeTimerCode,
    required DateTime? timerActivatedAt,
  }) async {
    final row = getState(deviceId)
      ..activeTimerCode  = activeTimerCode
      ..timerActivatedAt = timerActivatedAt;
    _stateBox.put(row);
  }

  @override
  Future<void> saveTelemetry(
    String deviceId, {
    required int? lastWatts,
    required int? lastRpm,
    required int? lastRuntimeSecs,
  }) async {
    final row = getState(deviceId)
      ..lastWatts       = lastWatts
      ..lastRpm         = lastRpm
      ..lastRuntimeSecs = lastRuntimeSecs;
    _stateBox.put(row);
  }

  @override
  Future<void> saveLighting(
    String deviceId, {
    required String colorType,
    required double brightness,
    required bool isOn,
  }) async {
    final row = getState(deviceId)
      ..lastLightColorType  = colorType
      ..lastLightBrightness = brightness
      ..lastLightIsOn       = isOn;
    _stateBox.put(row);
  }

  @override
  Future<void> saveOpenSegment(
    String deviceId, {
    required DateTime start,
    required int gear,
    String? mode,
    int? smartBaselineGear,
    required int wattsSum,
    required int wattsCount,
    required int rpmSum,
    required int rpmCount,
  }) async {
    final existing = _useQuery(
        _stateBox.query(FanState_.deviceId.equals(deviceId)).build(),
        (q) => q.findFirst())
        ?? (FanState()..deviceId = deviceId);
    existing.openSegmentStart         = start;
    existing.openSegmentGear          = gear;
    existing.openSegmentMode          = mode;
    existing.openSegmentSmartBaseline = smartBaselineGear;
    existing.openSegmentWattsSum      = wattsSum;
    existing.openSegmentWattsCount    = wattsCount;
    existing.openSegmentRpmSum        = rpmSum;
    existing.openSegmentRpmCount      = rpmCount;
    _stateBox.put(existing);
  }

  @override
  String exportToJson() {
    // Service access entries are temporary; never included in the customer's backup.
    final fans = getAllFans().where((f) => !f.isServiceAccess).toList();
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
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      if (map['version'] != 1) throw const FormatException('Unsupported export version.');
      final fans = (map['fans'] as List).cast<Map<String, dynamic>>();
      int imported = 0;
      for (final f in fans) {
        final deviceId   = f['device_id']   as String? ?? '';
        final macAddress = f['mac_address'] as String? ?? '';
        final nickname   = f['nickname']    as String? ?? '';
        if (deviceId.isEmpty || nickname.isEmpty) continue;
        if (deviceId.length > 64 || macAddress.length > 17 ||
            nickname.length > 30 || (f['model'] as String? ?? '').length > 64 ||
            (f['fw_version'] as String? ?? '').length > 32) {
          continue;
        }
        if (getFanByDeviceId(deviceId) != null) continue;
        if (macAddress.isNotEmpty && getFanByMac(macAddress) != null) continue;
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
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      throw FormatException('Malformed backup file: $e');
    }
  }
}
