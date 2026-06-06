// lib/core/ble/ble_service.dart
//
// MULTI-DEVICE CONNECTION NOTES:
// Root cause: BLE60 stops advertising while a GATT connection is active
//   (standard GAP behavior for single-connection BLE-UART bridge modules).
//   Scan results are empty when another phone is connected — this strongly
//   indicates the hardware stops advertising on first GATT connection.
// BLE60 advertising while connected: likely no (hardware/firmware constraint)
// Maximum simultaneous GATT connections supported: 1 (observed)
// Implemented behavior: Option A — second phone takes over the connection.
//   GATT error 133 (GATT_CONN_FAIL_ESTABLISH) surfaces a user-readable
//   'in use by another device' status rather than a raw exception string.
// Remaining limitation: Phone 2 cannot discover the fan via BLE scan while
//   Phone 1 is connected. For already-paired fans, connection by saved MAC
//   (BluetoothDevice.fromId) works without requiring re-discovery.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:terraton_fan_app/core/ble/ble_constants.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart' as app;

class DiscoveredFan {
  final String macAddress;
  final String name;
  final int rssi;
  const DiscoveredFan({required this.macAddress, required this.name, required this.rssi});
}

abstract class BleService {
  /// Open discovery scan — populates scanResultsStream.
  Future<void> startScan({int timeoutSeconds = 10});
  Future<void> stopScan();

  /// Connect to a specific device by MAC. Uses the live BluetoothDevice from
  /// the most recent scan when available (preserves BLE address type).
  Future<String> connect(String mac);
  Future<void> disconnect();
  Future<void> writeFrame(List<int> frame);
  Future<void> dispose();

  Stream<List<int>>              get notifyStream;
  Stream<app.BleConnectionState> get connectionStateStream;
  app.BleConnectionState         get currentState;
  Stream<List<DiscoveredFan>>    get scanResultsStream;
  String                         get writeCharStatus;
  String                         get connectStatus;
  /// MAC address of the currently connected device, or null when disconnected.
  String?                        get connectedMacAddress;
}

class BleServiceImpl implements BleService {
  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _writeChar;
  BluetoothCharacteristic?  _notifyChar;
  bool                      _disposed = false;

  String _writeCharStatus = 'pending';
  String _connectStatus   = 'idle';

  // Scan cache: live BluetoothDevice objects keyed by MAC.
  // These carry the BLE address type (public vs random) which is lost when
  // constructing a device from a MAC string alone via BluetoothDevice.fromId().
  final Map<String, BluetoothDevice> _scanCache  = {};
  final Map<String, DiscoveredFan>   _discovered = {};

  StreamSubscription<List<ScanResult>>?         _scanResultsSub;
  StreamSubscription<bool>?                     _scanStateSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>?                _notifyValueSub;

  final _notifyCtrl = StreamController<List<int>>.broadcast();
  final _stateCtrl  = StreamController<app.BleConnectionState>.broadcast();
  final _scanCtrl   = StreamController<List<DiscoveredFan>>.broadcast();

  app.BleConnectionState _currentState = app.BleConnectionState.disconnected;

  // Cached Guids — parse once, reuse on every scan/discovery.
  static final _advServiceGuid  = Guid(kAdvServiceUUID);
  static final _serviceGuid     = Guid(kServiceUUID);
  static final _meshProxyIn     = Guid(kMeshProxyDataInUUID);
  static final _meshProxyOut    = Guid(kMeshProxyDataOutUUID);
  static final _writeGuid       = Guid(kWriteCharUUID);
  static final _notifyGuid      = Guid(kNotifyCharUUID);
  static final _writeGuid2      = Guid(kWriteCharUUID2);
  static final _notifyGuid2     = Guid(kNotifyCharUUID2);
  static final _cc254xWrite     = Guid(kCC254xCharUUID);
  static final _nusWrite        = Guid(kNusWriteCharUUID);
  static final _nusNotify       = Guid(kNusNotifyCharUUID);
  static final _microchipWrite  = Guid(kMicrochipWriteCharUUID);
  static final _microchipNotify = Guid(kMicrochipNotifyCharUUID);

  @override Stream<List<int>>              get notifyStream          => _notifyCtrl.stream;
  @override Stream<app.BleConnectionState> get connectionStateStream  => _stateCtrl.stream;
  @override Stream<List<DiscoveredFan>>    get scanResultsStream      => _scanCtrl.stream;
  @override app.BleConnectionState         get currentState           => _currentState;
  @override String                         get writeCharStatus        => _writeCharStatus;
  @override String                         get connectStatus          => _connectStatus;
  @override String?                        get connectedMacAddress    => _device?.remoteId.str;

  void _setState(app.BleConnectionState s) {
    if (_disposed) return;
    _currentState = s;
    _stateCtrl.add(s);
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  @override
  Future<void> startScan({int timeoutSeconds = 10}) async {
    _discovered.clear();
    _scanCache.clear();
    _setState(app.BleConnectionState.scanning);

    await _scanResultsSub?.cancel();
    await _scanStateSub?.cancel();
    try { await FlutterBluePlus.stopScan(); } on Object catch (_) {}

    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mac     = r.device.remoteId.str;
        final advName = r.advertisementData.advName;
        final name    = advName.isNotEmpty
            ? advName
            : r.device.platformName.isNotEmpty
                ? r.device.platformName
                : mac;
        _scanCache[mac]  = r.device;
        _discovered[mac] = DiscoveredFan(macAddress: mac, name: name, rssi: r.rssi);
      }
      _scanCtrl.add(_discovered.values.toList());
    });

    _scanStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _currentState == app.BleConnectionState.scanning) {
        _setState(app.BleConnectionState.disconnected);
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [_advServiceGuid, _serviceGuid],
        timeout: Duration(seconds: timeoutSeconds),
      );
    } on Object catch (_) {
      // startScan() threw before emitting isScanning:false — reset manually
      // so callers don't see a permanently-stale scanning state.
      _setState(app.BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Connect ───────────────────────────────────────────────────────────────

  static const int      _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);

  @override
  Future<String> connect(String mac) async {
    if (_disposed) throw StateError('BleService disposed');

    // Already connected to the exact same device — skip full GATT setup.
    if (_currentState == app.BleConnectionState.connected &&
        _device?.remoteId.str == mac) {
      return mac;
    }

    // Switching to a different device — clean up the existing connection first
    // so we don't leave a dangling GATT handle or a stale _connStateSub.
    if (_device != null) {
      await _connStateSub?.cancel();
      _connStateSub = null;
      await _notifyValueSub?.cancel();
      _notifyValueSub = null;
      try { await _device!.disconnect(); } on Object catch (_) {}
      _writeChar  = null;
      _notifyChar = null;
      _device     = null;
      _setState(app.BleConnectionState.disconnected);
    }

    // Use the live scan-result device when available — it carries the correct
    // BLE address type. fromId() works on reconnects once Android has cached
    // the address type from a prior successful connection.
    final device = _scanCache[mac] ?? BluetoothDevice.fromId(mac);

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      _setState(app.BleConnectionState.connecting);
      _connectStatus = 'attempt $attempt/$_maxRetries';
      _writeCharStatus = 'pending';

      try {
        await device.connect(
          license: License.free,
          autoConnect: false,
          timeout: const Duration(seconds: 15),
        );

        _connectStatus = 'discovering services...';
        final services = await device.discoverServices();

        _writeChar  = null;
        _notifyChar = null;
        for (final svc in services) {
          for (final c in svc.characteristics) {
            // Priority — first match wins (??= never overwrites):
            // 1. BLE Mesh Proxy Data In/Out  (confirmed working with BLE60 fan)
            // 2. Firmware-team proprietary   (26cc3fc2 / 26cc3fc1) — fan unit 1
            // 3. Firmware-team proprietary   (bf8796f1-..00 / ..01) — fan unit 2
            // 4. HM-10 / CC254X              (0000ffe1 — common on Amp'ed RF)
            // 5. Nordic UART Service
            // 6. Microchip RN4870
            if (c.characteristicUuid == _meshProxyIn)     _writeChar  ??= c;
            if (c.characteristicUuid == _meshProxyOut)    _notifyChar ??= c;
            if (c.characteristicUuid == _writeGuid)       _writeChar  ??= c;
            if (c.characteristicUuid == _notifyGuid)      _notifyChar ??= c;
            if (c.characteristicUuid == _writeGuid2)      _writeChar  ??= c;
            if (c.characteristicUuid == _notifyGuid2)     _notifyChar ??= c;
            if (c.characteristicUuid == _cc254xWrite)     { _writeChar ??= c; _notifyChar ??= c; }
            if (c.characteristicUuid == _nusWrite)        _writeChar  ??= c;
            if (c.characteristicUuid == _nusNotify)       _notifyChar ??= c;
            if (c.characteristicUuid == _microchipWrite)  _writeChar  ??= c;
            if (c.characteristicUuid == _microchipNotify) _notifyChar ??= c;
          }
        }

        String shortId(Guid g) { final s = g.toString(); return s.length > 8 ? s.substring(0, 8) : s; }
        final svcList = services.map((s) => shortId(s.serviceUuid)).join(', ');
        if (_writeChar != null) {
          final p     = _writeChar!.properties;
          final modes = [
            if (p.writeWithoutResponse) 'NoResp',
            if (p.write)                'WithResp',
          ];
          _writeCharStatus =
              'found ${shortId(_writeChar!.characteristicUuid)}'
              ' | ${modes.isEmpty ? "NONE" : modes.join("+")} | svcs:[$svcList]';
        } else {
          _writeCharStatus = 'NOT FOUND | svcs:[$svcList]';
        }

        if (_notifyChar != null) {
          await _notifyChar!.setNotifyValue(true);
          await _notifyValueSub?.cancel();
          _notifyValueSub = _notifyChar!.onValueReceived.listen(_notifyCtrl.add);
        }

        _device = device;
        _scanCache[mac] = device;

        await _connStateSub?.cancel();
        _connStateSub = device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected && !_disposed) {
            _writeChar  = null;
            _notifyChar = null;
            _device     = null;
            _setState(app.BleConnectionState.disconnected);
          }
        });

        _connectStatus = 'connected';
        _setState(app.BleConnectionState.connected);
        return mac;

      } on Object catch (e) {
        final msg = e.toString();
        // GATT error 133 (GATT_CONN_FAIL_ESTABLISH) means the peripheral
        // refused the connection — most likely it is already connected to
        // another device. Surface a human-readable status instead of the
        // raw exception so ConnectionLostCard can show a helpful hint.
        final isInUse = msg.contains('133');
        _connectStatus = isInUse
            ? 'in use by another device (attempt $attempt/$_maxRetries)'
            : 'attempt $attempt failed: ${msg.split('\n').first}';

        // Disconnect the partial GATT before retrying — avoids "already
        // connected" errors on the next attempt. Timeout so we don't hang
        // if the peripheral never ACKs the disconnect.
        try {
          await device.disconnect().timeout(const Duration(seconds: 3));
        } on Object catch (_) {}

        await _connStateSub?.cancel();
        _connStateSub = null;

        if (attempt == _maxRetries) {
          _writeChar  = null;
          _notifyChar = null;
          _device     = null;
          _setState(app.BleConnectionState.disconnected);
          rethrow;
        }
        await Future<void>.delayed(_retryDelay);
      }
    }

    // unreachable — loop always returns or rethrows
    throw StateError('connect() loop exited without result');
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    await _connStateSub?.cancel();
    _connStateSub = null;
    try { await _device?.disconnect(); } on Object catch (_) {}
    _writeChar       = null;
    _notifyChar      = null;
    _device          = null;
    _writeCharStatus = 'disconnected';
    _connectStatus   = 'idle';
    _setState(app.BleConnectionState.disconnected);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  @override
  Future<void> writeFrame(List<int> frame) async {
    final char = _writeChar;
    if (char == null) throw StateError('writeChar null ($_writeCharStatus)');
    // BLE60 is a BLE-to-UART bridge: buffers incoming BLE data and only
    // flushes to the MCU UART when it receives \r\n (0x0D 0x0A).
    final payload = Uint8List.fromList([...frame, 0x0D, 0x0A]);
    await char.write(payload, withoutResponse: char.properties.writeWithoutResponse);
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _disposed = true;
    try { await FlutterBluePlus.stopScan(); } on Object catch (_) {}
    await _scanResultsSub?.cancel();
    await _scanStateSub?.cancel();
    await _connStateSub?.cancel();
    await _notifyValueSub?.cancel();
    await _notifyCtrl.close();
    await _stateCtrl.close();
    await _scanCtrl.close();
  }
}
