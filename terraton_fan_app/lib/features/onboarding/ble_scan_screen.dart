// lib/features/onboarding/ble_scan_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class BleScanScreen extends ConsumerStatefulWidget {
  const BleScanScreen({super.key});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen> {
  List<DiscoveredFan> _results = [];
  bool _scanning = false;
  bool _timedOut = false;
  bool? _permissionGranted;
  StreamSubscription<List<DiscoveredFan>>? _sub;
  Timer? _timeout;
  late BleService _ble;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(bleServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissionAndScan());
  }

  Future<void> _checkPermissionAndScan() async {
    final scanStatus    = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    if (!mounted) return;

    final granted = (scanStatus.isGranted    || scanStatus.isLimited) &&
                    (connectStatus.isGranted || connectStatus.isLimited);

    setState(() => _permissionGranted = granted);
    if (granted) await _startScan();
  }

  Future<void> _startScan() async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth is off. Please enable Bluetooth to scan for fans.'),
        ));
      }
      if (Platform.isAndroid) unawaited(FlutterBluePlus.turnOn());
      return;
    }

    setState(() { _scanning = true; _timedOut = false; _results = []; });

    await _sub?.cancel();
    if (!mounted) return;
    _sub = _ble.scanResultsStream.listen((fans) {
      if (mounted) setState(() => _results = fans);
    });

    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() { _scanning = false; _timedOut = _results.isEmpty; });
    });

    try {
      await _ble.startScan(timeoutSeconds: 15);
    } on Object catch (_) {
      _timeout?.cancel();
      if (mounted) setState(() { _scanning = false; _timedOut = true; });
      return;
    }
    if (!mounted) return;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _timeout?.cancel();
    unawaited(_ble.stopScan());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedMacs = {
      for (final f in ref.watch(savedFansProvider).value ?? const <FanDevice>[])
        if (f.macAddress.isNotEmpty) f.macAddress,
    };

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Select Your Fan',
            style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
        centerTitle: true,
        actions: [
          if (_permissionGranted == true)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: kYellow),
              tooltip: 'Refresh scan',
              onPressed: () => unawaited(_startScan()),
            ),
        ],
      ),
      body: Builder(builder: (_) {
        if (_permissionGranted == null) return const SizedBox.shrink();

        if (_permissionGranted == false) return _buildPermissionDenied();

        if (_scanning && _results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(color: kYellow, strokeWidth: 2),
                ),
                const SizedBox(height: 20),
                Text('Scanning for fans…',
                    style: GoogleFonts.manrope(fontSize: 15, color: kTextMut)),
                const SizedBox(height: 6),
                Text('Make sure your fan is powered on',
                    style: GoogleFonts.manrope(fontSize: 12, color: kTextDim)),
              ],
            ),
          );
        }

        if (_timedOut) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: kCard, borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: kHairline),
                    ),
                    child: const Icon(Icons.wifi_off_rounded, size: 36, color: kTextDim),
                  ),
                  const SizedBox(height: 20),
                  Text('No fans found.',
                      style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
                  const SizedBox(height: 6),
                  Text('Make sure your fan is powered on and within range.',
                      style: GoogleFonts.manrope(fontSize: 13, color: kTextMut),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('Refresh',
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      onPressed: () => unawaited(_startScan()),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Results list
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Text('${_results.length} FOUND',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: kTextMut, letterSpacing: 2.2,
                      )),
                  const SizedBox(width: 8),
                  if (_scanning)
                    const SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: kYellow),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final fan = _results[i];
                  final alreadyAdded = savedMacs.contains(fan.macAddress);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FanResultRow(
                      fan: fan,
                      alreadyAdded: alreadyAdded,
                      onTap: alreadyAdded ? null : () {
                        final device = FanDevice()
                          ..deviceId   = fan.macAddress
                          ..macAddress = fan.macAddress
                          ..nickname   = ''
                          ..addedAt    = DateTime.now();
                        unawaited(context.push(AppRoutes.nameFan, extra: device));
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildPermissionDenied() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: kYellow.withAlpha(25), borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kYellow.withAlpha(60)),
            ),
            child: const Icon(Icons.bluetooth_disabled_rounded, size: 36, color: kYellow),
          ),
          const SizedBox(height: 24),
          Text('Bluetooth Permission Required',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 12),
          Text(
            'Terraton Fan Controller needs Bluetooth Scan and Connect '
            'permissions to search for nearby fans.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: kTextMut),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () => unawaited(openAppSettings()),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text('Open App Settings',
                  style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton.icon(
              onPressed: _checkPermissionAndScan,
              style: OutlinedButton.styleFrom(
                foregroundColor: kText,
                side: const BorderSide(color: kHairlineStrong),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Try Again',
                  style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fan result row ─────────────────────────────────────────────────────────────

class _FanResultRow extends StatelessWidget {
  final DiscoveredFan fan;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  const _FanResultRow({
    required this.fan,
    required this.alreadyAdded,
    required this.onTap,
  });

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return kGreen;
    if (rssi >= -80) return const Color(0xFFF97316);
    return kRed;
  }

  String _rssiLabel(int rssi) {
    if (rssi >= -60) return 'Strong';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: alreadyAdded ? 0.5 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: kCardHi, borderRadius: BorderRadius.circular(14),
                ),
                child: const TerratonFanIcon(size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fan.name,
                        style: GoogleFonts.manrope(
                          fontSize: 15, fontWeight: FontWeight.w700, color: kText,
                        )),
                    const SizedBox(height: 3),
                    Text(fan.macAddress,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: kTextMut, letterSpacing: 0.6,
                        )),
                  ],
                ),
              ),
              if (alreadyAdded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: kCardHi, borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Added',
                      style: GoogleFonts.manrope(
                        fontSize: 11, fontWeight: FontWeight.w600, color: kTextMut,
                      )),
                )
              else
                Semantics(
                  label: 'Signal: ${_rssiLabel(fan.rssi)}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.signal_cellular_alt_rounded,
                          size: 16, color: _rssiColor(fan.rssi)),
                      const SizedBox(width: 4),
                      Text('${fan.rssi} dBm',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: kTextMut,
                          )),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
