// lib/core/ble/ble_service.dart
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
  static final _cc254xWrite     = Guid(kCC254xCharUUID);
  static final _nusWrite        = Guid(kNusWriteCharUUID);
  static final _nusNotify       = Guid(kNusNotifyCharUUID);
  static final _microchipWrite  = Guid(kMicrochipWriteCharUUID);
  static final _microchipNotify = Guid(kMicrochipNotifyCharUUID);

  @override Stream<List<int>>              get notifyStream        => _notifyCtrl.stream;
  @override Stream<app.BleConnectionState> get connectionStateStream => _stateCtrl.stream;
  @override Stream<List<DiscoveredFan>>    get scanResultsStream   => _scanCtrl.stream;
  @override app.BleConnectionState         get currentState        => _currentState;
  @override String                         get writeCharStatus     => _writeCharStatus;
  @override String                         get connectStatus       => _connectStatus;

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

    await FlutterBluePlus.startScan(
      withServices: [_advServiceGuid, _serviceGuid],
      timeout: Duration(seconds: timeoutSeconds),
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Connect ───────────────────────────────────────────────────────────────

  @override
  Future<String> connect(String mac) async {
    if (_disposed) throw StateError('BleService disposed');
    _setState(app.BleConnectionState.connecting);
    _connectStatus = 'connecting...';
    _writeCharStatus = 'pending';

    // Use the live scan-result device when available — it carries the correct
    // BLE address type. On reconnects after the first session, Android caches
    // the address type so fromId() also works.
    final device = _scanCache[mac] ?? BluetoothDevice.fromId(mac);

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
          // Priority order — first match wins (??= never overwrites):
          // 1. BLE Mesh Proxy Data In/Out  (confirmed working with BLE60 fan)
          // 2. Firmware-team proprietary   (26cc3fc2 / 26cc3fc1)
          // 3. HM-10 / CC254X              (0000ffe1 — common on Amp'ed RF)
          // 4. Nordic UART Service
          // 5. Microchip RN4870
          if (c.characteristicUuid == _meshProxyIn)     _writeChar  ??= c;
          if (c.characteristicUuid == _meshProxyOut)    _notifyChar ??= c;
          if (c.characteristicUuid == _writeGuid)       _writeChar  ??= c;
          if (c.characteristicUuid == _notifyGuid)      _notifyChar ??= c;
          if (c.characteristicUuid == _cc254xWrite)     { _writeChar ??= c; _notifyChar ??= c; }
          if (c.characteristicUuid == _nusWrite)        _writeChar  ??= c;
          if (c.characteristicUuid == _nusNotify)       _notifyChar ??= c;
          if (c.characteristicUuid == _microchipWrite)  _writeChar  ??= c;
          if (c.characteristicUuid == _microchipNotify) _notifyChar ??= c;
        }
      }

      final svcList = services
          .map((s) => s.serviceUuid.toString().substring(0, 8))
          .join(', ');
      if (_writeChar != null) {
        final p     = _writeChar!.properties;
        final modes = [
          if (p.writeWithoutResponse) 'NoResp',
          if (p.write)                'WithResp',
        ];
        _writeCharStatus =
            'found ${_writeChar!.characteristicUuid.toString().substring(0, 8)}'
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
      _scanCache[mac] = device; // keep for future reconnects in this session

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
      _connectStatus = 'failed: ${e.toString().split('\n').first}';
      try { await device.disconnect(); } on Object catch (_) {}
      _writeChar  = null;
      _notifyChar = null;
      _device     = null;
      _setState(app.BleConnectionState.disconnected);
      rethrow;
    }
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
