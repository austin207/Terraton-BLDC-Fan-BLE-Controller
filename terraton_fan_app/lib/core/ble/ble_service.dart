// lib/core/ble/ble_service.dart
import 'dart:async';
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
}

class BleServiceImpl implements BleService {
  BluetoothDevice?           _device;
  BluetoothCharacteristic?   _writeChar;
  BluetoothCharacteristic?   _notifyChar;
  String?                    _targetMac;
  int                        _retryCount = 0;
  static const int           _maxRetries = 3;
  static const Duration      _retryDelay = Duration(seconds: 5);

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

  void _setState(app.BleConnectionState s) {
    _currentState = s;
    _stateController.add(s);
  }

  @override
  Future<void> startScan({String? targetMac, int timeoutSeconds = 10}) async {
    _targetMac = targetMac;
    _discovered.clear();
    _setState(app.BleConnectionState.scanning);

    // Cancel previous scan subscriptions before re-subscribing.
    // Without this, every Refresh tap stacks a new listener.
    await _scanResultsSub?.cancel();
    await _isScanSub?.cancel();

    await FlutterBluePlus.startScan(
      withServices: [Guid(kServiceUUID)],
      timeout: Duration(seconds: timeoutSeconds),
    );

    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mac  = r.device.remoteId.str;
        final name = r.device.platformName.isNotEmpty ? r.device.platformName : mac;
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
          sub?.cancel();
        }
      });
      await startScan(timeoutSeconds: 10);
      target = await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {
        throw TimeoutException('No fan found during scan.');
      });
    }

    try {
      await target.connect(license: License.free, timeout: const Duration(seconds: 15));
    } on Object catch (_) {
      // Disconnect the partial connection before retrying to avoid "already connected" errors.
      try { await target.disconnect(); } on Object catch (_) {}
      if (_retryCount < _maxRetries) {
        _retryCount++;
        await Future<void>.delayed(_retryDelay);
        return _doConnect();
      }
      _setState(app.BleConnectionState.disconnected);
      rethrow;
    }

    _device = target;

    final services = await target.discoverServices();
    for (final svc in services) {
      if (svc.serviceUuid == Guid(kServiceUUID)) {
        for (final c in svc.characteristics) {
          if (c.characteristicUuid == Guid(kWriteCharUUID))  _writeChar  = c;
          if (c.characteristicUuid == Guid(kNotifyCharUUID)) _notifyChar = c;
        }
      }
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
          unawaited(Future<void>.delayed(_retryDelay, _doConnect));
        }
      }
    });

    _retryCount = 0;
    _setState(app.BleConnectionState.connected);
    return target.remoteId.str;
  }

  @override
  Future<void> disconnect() async {
    _retryCount = _maxRetries; // Prevent auto-reconnect on intentional disconnect
    await _connStateSub?.cancel();
    _connStateSub = null;
    await _device?.disconnect();
    _writeChar  = null;
    _notifyChar = null;
    _device     = null;
    _setState(app.BleConnectionState.disconnected);
  }

  @override
  Future<void> writeFrame(List<int> frame) async {
    if (_writeChar == null) return;
    await _writeChar!.write(frame, withoutResponse: false);
  }

  @override
  Future<void> dispose() async {
    await _scanResultsSub?.cancel();
    await _isScanSub?.cancel();
    await _connStateSub?.cancel();
    await _notifyValueSub?.cancel();
    await _notifyController.close();
    await _stateController.close();
    await _scanResultsController.close();
  }
}
