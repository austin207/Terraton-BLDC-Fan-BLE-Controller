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
  Future<void> startScan({String? targetMac, int timeoutSeconds = 10});
  Future<void> stopScan();
  Future<String> connect();
  Future<void> disconnect();
  Future<void> writeFrame(List<int> frame);
  Future<void> dispose();
  Stream<List<int>>               get notifyStream;
  Stream<app.BleConnectionState>  get connectionStateStream;
  app.BleConnectionState          get currentState;
  Stream<List<DiscoveredFan>>     get scanResultsStream;
  /// Human-readable diagnostic: whether the write characteristic was found
  /// after the last service discovery, and what ATT properties it has.
  String get writeCharStatus;
  /// Human-readable diagnostic: last connection attempt outcome — useful
  /// for surfacing why connect() is failing (timeouts, GATT errors, etc.).
  String get connectStatus;
}

class BleServiceImpl implements BleService {
  BluetoothDevice?           _device;
  BluetoothCharacteristic?   _writeChar;
  BluetoothCharacteristic?   _notifyChar;
  String?                    _targetMac;
  int                        _retryCount = 0;
  static const int           _maxRetries        = 2;
  static const Duration      _retryDelay        = Duration(seconds: 2);
  // autoConnect=true does its own waiting for the peripheral to advertise,
  // so the timeout has to be generous — Amp'ed RF / random-address modules
  // can take 20–30s to be picked up on the first cold connect.
  static const Duration      _connectTimeout    = Duration(seconds: 30);
  static const Duration      _connectHardCap    = Duration(seconds: 33); // dart-side safety net
  static const Duration      _disconnectTimeout = Duration(seconds: 3);  // disconnect can hang on Android

  bool   _disposed        = false;
  Timer? _retryTimer;
  String _writeCharStatus = 'pending';
  String _connectStatus   = 'idle';

  // Cached Guid objects — avoids re-parsing constant UUID strings on every scan/discovery.
  static final _advServiceGuid = Guid(kAdvServiceUUID); // what the module advertises
  static final _serviceGuid    = Guid(kServiceUUID);    // GATT service after connect
  static final _writeGuid      = Guid(kWriteCharUUID);
  static final _notifyGuid     = Guid(kNotifyCharUUID);

  // Stored so they can be cancelled before re-subscribing and on dispose.
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>?             _isScanSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>?        _notifyValueSub;

  final _notifyController      = StreamController<List<int>>.broadcast();
  final _stateController       = StreamController<app.BleConnectionState>.broadcast();
  final _scanResultsController = StreamController<List<DiscoveredFan>>.broadcast();
  final Map<String, DiscoveredFan> _discovered = {};

  app.BleConnectionState _currentState = app.BleConnectionState.disconnected;

  @override
  Stream<List<int>>               get notifyStream        => _notifyController.stream;
  @override
  Stream<app.BleConnectionState>  get connectionStateStream => _stateController.stream;
  @override
  Stream<List<DiscoveredFan>>     get scanResultsStream   => _scanResultsController.stream;
  @override
  app.BleConnectionState          get currentState        => _currentState;
  @override
  String                          get writeCharStatus     => _writeCharStatus;
  @override
  String                          get connectStatus       => _connectStatus;

  void _setState(app.BleConnectionState s) {
    if (_disposed) return;
    _currentState = s;
    _stateController.add(s);
  }

  @override
  Future<void> startScan({String? targetMac, int timeoutSeconds = 10}) async {
    _targetMac = targetMac;

    // Clears previous results so the list doesn't grow unboundedly across
    // multiple scans. Side-effect: scan results briefly empty on Refresh.
    _discovered.clear();
    _setState(app.BleConnectionState.scanning);

    // Cancel previous scan subscriptions before re-subscribing.
    // Without this, every Refresh tap stacks a new listener.
    await _scanResultsSub?.cancel();
    await _isScanSub?.cancel();

    // Stop any previous scan only during open discovery.
    // Skipped for targeted connection (targetMac != null) because the scan
    // screen has already sent a stopScan on dispose; a second stop+start on
    // some Android BLE drivers stalls the radio and delays connect().
    if (targetMac == null) {
      try { await FlutterBluePlus.stopScan(); } on Object catch (_) {}
    }

    // Filter on BOTH the advertised UUID (BLE Mesh Proxy — what the BLE60
    // actually puts in its advertisement packet) and the proprietary GATT
    // UUID (what ESP32 prototypes are flashed with). withServices is an OR
    // match, so this finds both real hardware and dev test peripherals.
    await FlutterBluePlus.startScan(
      withServices: [_advServiceGuid, _serviceGuid],
      timeout: Duration(seconds: timeoutSeconds),
    );

    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mac  = r.device.remoteId.str;
        // Prefer advertisement name; fall back to cached platform name then MAC.
        final advName = r.advertisementData.advName;
        final name = advName.isNotEmpty
            ? advName
            : r.device.platformName.isNotEmpty
                ? r.device.platformName
                : mac;
        _discovered[mac] = DiscoveredFan(macAddress: mac, name: name, rssi: r.rssi);
      }
      _scanResultsController.add(_discovered.values.toList());
    });

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _currentState == app.BleConnectionState.scanning) {
        _setState(app.BleConnectionState.disconnected);
      }
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<String> connect() async {
    _retryCount = 0;
    return _doConnect();
  }

  Future<String> _doConnect() async {
    if (_disposed) throw StateError('BleService disposed');
    _setState(app.BleConnectionState.connecting);

    BluetoothDevice? target;

    if (_targetMac != null) {
      target = BluetoothDevice.fromId(_targetMac!);
    } else {
      final completer = Completer<BluetoothDevice>();
      StreamSubscription<List<ScanResult>>? sub;
      sub = FlutterBluePlus.scanResults.listen((results) {
        if (results.isNotEmpty && !completer.isCompleted) {
          completer.complete(results.first.device);
        }
      });
      await startScan(timeoutSeconds: 10);
      try {
        target = await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {
          throw TimeoutException('No fan found during scan.');
        });
      } finally {
        await sub.cancel();
        sub = null;
      }
    }

    _connectStatus = 'attempt ${_retryCount + 1}/${_maxRetries + 1} (autoConnect)';
    try {
      // autoConnect: true is the canonical Android fix for peripherals that
      // BluetoothGatt.connect() can't pick up directly — Amp'ed RF modules,
      // Nordic devices, anything using random / resolvable private addresses.
      // Android queues the connection until the peripheral's next advertisement
      // is seen, then initiates the GATT link. Much more reliable than the
      // direct-connect path (autoConnect: false) for modules that work fine
      // with nRF Connect / generic BLE apps but hang in flutter_blue_plus.
      //
      // Trade-off: initial connection is slower (Android uses its background
      // scan interval, ~5–10s typical, up to 30s). Future.timeout() caps it.
      await target
          .connect(
            license: License.free,
            timeout: _connectTimeout,
            autoConnect: true,
          )
          .timeout(_connectHardCap);
    } on Object catch (e) {
      _connectStatus = 'attempt ${_retryCount + 1} failed: ${e.toString().split('\n').first}';
      // Disconnect the partial connection before retrying to avoid "already
      // connected" errors. Wrap in timeout — disconnect() can also hang for
      // 30+ seconds on Android when the peer never ACKs the disconnect.
      try {
        await target.disconnect().timeout(_disconnectTimeout);
      } on Object catch (_) {}
      if (_retryCount < _maxRetries) {
        _retryCount++;
        // Cancel stale connection-state subscription so a previous listener
        // cannot trigger a concurrent retry chain on the same device.
        await _connStateSub?.cancel();
        _connStateSub = null;
        await Future<void>.delayed(_retryDelay);
        return _doConnect();
      }
      _setState(app.BleConnectionState.disconnected);
      rethrow;
    }
    _connectStatus = 'connected, discovering services...';

    _device = target;

    final services = await target.discoverServices();
    // Search ALL services for the write/notify chars by UUID. The BLE60
    // module exposes its data characteristics inside the proprietary
    // service (kServiceUUID), but ESP32 test peripherals and some firmware
    // variants put them under the Mesh Proxy service. Matching by char UUID
    // directly is robust to either layout.
    for (final svc in services) {
      for (final c in svc.characteristics) {
        if (c.characteristicUuid == _writeGuid)  _writeChar  ??= c;
        if (c.characteristicUuid == _notifyGuid) _notifyChar ??= c;
      }
    }

    // Log result for the debug card.
    if (_writeChar != null) {
      final p = _writeChar!.properties;
      final modes = <String>[
        if (p.writeWithoutResponse) 'NoResp',
        if (p.write)                'WithResp',
      ];
      _writeCharStatus =
          'found | props: ${modes.isEmpty ? "NONE" : modes.join("+")}';
    } else {
      final discovered =
          services.map((s) => s.serviceUuid.toString().substring(0, 8)).join(', ');
      _writeCharStatus =
          'NOT FOUND | services: [$discovered]';
    }

    if (_notifyChar != null) {
      await _notifyChar!.setNotifyValue(true);
      await _notifyValueSub?.cancel();
      _notifyValueSub = _notifyChar!.onValueReceived.listen((bytes) {
        _notifyController.add(bytes);
      });
    }

    // Cancel any previous listener before attaching a new one.
    // Without this, each reconnect adds a duplicate callback.
    await _connStateSub?.cancel();
    _connStateSub = target.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _setState(app.BleConnectionState.disconnected);
        if (_retryCount < _maxRetries) {
          _retryCount++;
          _retryTimer?.cancel();
          _retryTimer = Timer(_retryDelay, () => unawaited(_doConnect()));
        }
      }
    });

    _retryCount = 0;
    _connectStatus = 'connected';
    _setState(app.BleConnectionState.connected);
    return target.remoteId.str;
  }

  @override
  Future<void> disconnect() async {
    _retryCount = _maxRetries; // Prevent auto-reconnect on intentional disconnect
    _retryTimer?.cancel();
    _retryTimer = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    try {
      await _device?.disconnect().timeout(_disconnectTimeout);
    } on Object catch (_) {}
    _writeChar        = null;
    _notifyChar       = null;
    _device           = null;
    _writeCharStatus  = 'disconnected';
    _connectStatus    = 'idle';
    _setState(app.BleConnectionState.disconnected);
  }

  @override
  Future<void> writeFrame(List<int> frame) async {
    final char = _writeChar;
    if (char == null) throw StateError('writeChar null ($_writeCharStatus)');
    // Respect the characteristic's declared write type.
    // WithResp (PROPERTY_WRITE) = ATT Write Request; the peripheral sends an ACK.
    // NoResp (PROPERTY_WRITE_NO_RESPONSE) = ATT Write Command; fire-and-forget.
    await char.write(
      Uint8List.fromList(frame),
      withoutResponse: char.properties.writeWithoutResponse,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    try { await FlutterBluePlus.stopScan(); } on Object catch (_) {}
    await _scanResultsSub?.cancel();
    await _isScanSub?.cancel();
    await _connStateSub?.cancel();
    await _notifyValueSub?.cancel();
    await _notifyController.close();
    await _stateController.close();
    await _scanResultsController.close();
  }
}
