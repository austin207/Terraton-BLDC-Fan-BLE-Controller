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
  // Match nRF Connect's defaults: autoConnect=false, 15s per attempt.
  static const Duration      _connectTimeout    = Duration(seconds: 15);
  static const Duration      _connectHardCap    = Duration(seconds: 18); // dart-side safety net
  static const Duration      _disconnectTimeout = Duration(seconds: 3);  // disconnect can hang on Android

  bool   _disposed        = false;
  Timer? _retryTimer;
  String _writeCharStatus = 'pending';
  String _connectStatus   = 'idle';

  // Cached Guid objects — avoids re-parsing constant UUID strings on every scan/discovery.
  static final _advServiceGuid  = Guid(kAdvServiceUUID);
  static final _serviceGuid     = Guid(kServiceUUID);
  static final _writeGuid       = Guid(kWriteCharUUID);
  // Fallback UART profiles — same order Serial Bluetooth Terminal uses.
  static final _cc254xWrite     = Guid(kCC254xCharUUID);
  static final _nusWrite        = Guid(kNusWriteCharUUID);
  static final _nusNotify       = Guid(kNusNotifyCharUUID);
  static final _microchipWrite  = Guid(kMicrochipWriteCharUUID);
  static final _microchipNotify = Guid(kMicrochipNotifyCharUUID);
  static final _notifyGuid     = Guid(kNotifyCharUUID);

  // Stored so they can be cancelled before re-subscribing and on dispose.
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>?             _isScanSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>?        _notifyValueSub;

  final _notifyController      = StreamController<List<int>>.broadcast();
  final _stateController       = StreamController<app.BleConnectionState>.broadcast();
  final _scanResultsController = StreamController<List<DiscoveredFan>>.broadcast();
  final Map<String, DiscoveredFan>      _discovered        = {};
  // Live BluetoothDevice instances from scan results, keyed by MAC. These
  // carry the address type that BluetoothDevice.fromId(mac) loses, which
  // is required for connecting to random-address peripherals like Amp'ed RF.
  final Map<String, BluetoothDevice>    _discoveredDevices = {};

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
    _discoveredDevices.clear();
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
        _discovered[mac]        = DiscoveredFan(macAddress: mac, name: name, rssi: r.rssi);
        _discoveredDevices[mac] = r.device; // keep the live device for connect()
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

  /// Scans without a service UUID filter to find a specific MAC address.
  /// Returns the live BluetoothDevice (which carries the correct address type)
  /// or null if the device is not seen within [timeout].
  Future<BluetoothDevice?> _scanForDevice(String mac, {Duration timeout = const Duration(seconds: 8)}) async {
    final completer = Completer<BluetoothDevice>();
    StreamSubscription<List<ScanResult>>? sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.str == mac && !completer.isCompleted) {
          _discoveredDevices[mac] = r.device;
          completer.complete(r.device);
          break;
        }
      }
    });
    // Scan with no service filter so we find the device regardless of what
    // it is currently advertising. We know the exact MAC so filtering is
    // unnecessary and risks missing a device that duty-cycles its UUID.
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } on Object catch (_) {}
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      await sub.cancel();
      try { await FlutterBluePlus.stopScan(); } on Object catch (_) {}
    }
  }

  Future<String> _doConnect() async {
    if (_disposed) throw StateError('BleService disposed');
    _setState(app.BleConnectionState.connecting);

    BluetoothDevice? target;

    if (_targetMac != null) {
      // Prefer the live scan-result device — it carries the correct BLE address
      // type (public vs random). BluetoothDevice.fromId() always assumes public,
      // which fails silently on phones that have never seen this peripheral.
      // _discoveredDevices is populated by the BLE scan screen; for home-screen
      // reconnections where no scan has run this session we do a brief targeted
      // scan first, then fall back to fromId() as a last resort.
      target = _discoveredDevices[_targetMac];
      if (target == null) {
        _connectStatus = 'scanning for device...';
        target = await _scanForDevice(_targetMac!, timeout: const Duration(seconds: 8));
        target ??= BluetoothDevice.fromId(_targetMac!);
      }
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

    _connectStatus = 'attempt ${_retryCount + 1}/${_maxRetries + 1}';
    try {
      // autoConnect: false matches nRF Connect / Serial Bluetooth Terminal —
      // direct GATT connect with explicit TRANSPORT_LE. autoConnect: true was
      // making things worse for the BLE60 (Android keeps it pending until the
      // peripheral re-advertises, which Amp'ed RF modules duty-cycle).
      // Future.timeout(_connectHardCap) is the dart-side safety net in case
      // BluetoothGatt.connect() itself hangs past the requested timeout.
      // mtu: 512 triggers BluetoothGatt.requestMtu(512) right after
      // STATE_CONNECTED, matching Serial Bluetooth Terminal's sequence.
      // Without an explicit MTU request, some peripherals (including Amp'ed RF
      // modules) use the default 23-byte ATT_MTU, which can cause issues on
      // first GATT discovery.
      await target
          .connect(
            license: License.free,
            timeout: _connectTimeout,
            autoConnect: false,
            mtu: 512,
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
    _connectStatus = 'discovering services...';

    _device = target;

    final services = await target.discoverServices()
        .timeout(const Duration(seconds: 15), onTimeout: () {
      throw TimeoutException('discoverServices() timed out after 15s');
    });
    // Search ALL services for the write/notify chars by UUID. The BLE60
    // Search for write/notify chars using the same priority order as Serial
    // Bluetooth Terminal, which is confirmed to work with the BLE60 module.
    //
    // Priority:
    //   1. Firmware-team proprietary UUIDs (26cc3fc2 / 26cc3fc1)
    //   2. HM-10 / CC254X profile (0000ffe1) — most common for Amp'ed RF
    //   3. Nordic UART Service (6e400002 write / 6e400003 notify)
    //   4. Microchip RN4870 profile
    //
    // All services are searched so the char can live inside any service UUID.
    for (final svc in services) {
      for (final c in svc.characteristics) {
        // Priority 1 — proprietary
        if (c.characteristicUuid == _writeGuid)    _writeChar  ??= c;
        if (c.characteristicUuid == _notifyGuid)   _notifyChar ??= c;
        // Priority 2 — HM-10 / CC254X (RW char doubles as write+notify)
        if (c.characteristicUuid == _cc254xWrite)  { _writeChar ??= c; _notifyChar ??= c; }
        // Priority 3 — Nordic UART Service
        if (c.characteristicUuid == _nusWrite)     _writeChar  ??= c;
        if (c.characteristicUuid == _nusNotify)    _notifyChar ??= c;
        // Priority 4 — Microchip
        if (c.characteristicUuid == _microchipWrite)  _writeChar  ??= c;
        if (c.characteristicUuid == _microchipNotify) _notifyChar ??= c;
      }
    }

    // Log result so debug card shows exactly which char was picked and
    // all discovered services, making it trivial to spot a UUID mismatch.
    final svcList = services.map((s) => s.serviceUuid.toString().substring(0, 8)).join(', ');
    if (_writeChar != null) {
      final p = _writeChar!.properties;
      final modes = <String>[
        if (p.writeWithoutResponse) 'NoResp',
        if (p.write)                'WithResp',
      ];
      _writeCharStatus = 'found ${_writeChar!.characteristicUuid.toString().substring(0, 8)}'
          ' | props: ${modes.isEmpty ? "NONE" : modes.join("+")} | svcs: [$svcList]';
    } else {
      _writeCharStatus = 'NOT FOUND | svcs: [$svcList]';
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
    // The Amp'ed RF BLE60 module is a BLE-to-UART bridge. It buffers incoming
    // BLE data and only flushes it to the MCU's UART when it receives \r\n
    // (0x0D 0x0A). Without the newline, frames sit in the module's buffer and
    // never reach the MCU — confirmed by Serial Bluetooth Terminal's log which
    // shows 0D 0A appended to every sent frame and the fan responding.
    final payload = Uint8List.fromList([...frame, 0x0D, 0x0A]);
    await char.write(
      payload,
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
