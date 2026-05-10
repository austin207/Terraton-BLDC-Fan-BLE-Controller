// lib/features/onboarding/qr_scan_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';

const _kDark       = Color(0xFF0D1423);
const _kCardDark   = Color(0xFF1A2436);
const _kBracket    = Color(0xFF3B82F6);

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled     = false;
  bool _cameraReady = false;
  bool _torchOn     = false;

  late final AnimationController _scanAnim;
  late final Animation<double> _scanPos;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanPos = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnim, curve: Curves.easeInOut),
    );
    unawaited(_checkCamera());
  }

  Future<void> _checkCamera() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      if (mounted) setState(() => _cameraReady = true);
      return;
    }
    final result = await Permission.camera.request();
    if (!mounted) return;
    if (result.isGranted) {
      setState(() => _cameraReady = true);
    } else {
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text('Camera access is needed to scan QR codes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    try {
      final json       = jsonDecode(raw) as Map<String, dynamic>;
      final deviceId   = json['device_id']  as String?;
      final model      = json['model']      as String?;
      final fwVersion  = json['fw_version'] as String?;

      if (deviceId == null || model == null || fwVersion == null) {
        _showInvalidSnack();
        return;
      }

      _handled = true;
      final fan = FanDevice()
        ..deviceId  = deviceId
        ..model     = model
        ..fwVersion = fwVersion
        ..nickname  = model
        ..addedAt   = DateTime.now();

      if (mounted) context.push(AppRoutes.nameFan, extra: fan);
    } on FormatException {
      _showInvalidSnack();
    }
  }

  void _showInvalidSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invalid QR code. Please scan the code on your Terraton fan packaging.'),
      ),
    );
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const frameSize = 260.0;

    return Scaffold(
      backgroundColor: _kDark,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _kCardDark,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                  const Text(
                    'Scan Fan QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Camera frame ─────────────────────────────────────────────────
            SizedBox(
              width: frameSize,
              height: frameSize,
              child: Stack(
                children: [
                  // Live camera (or black placeholder while requesting permission)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cameraReady
                        ? MobileScanner(
                            controller: _ctrl,
                            onDetect: _onDetect,
                          )
                        : Container(color: Colors.black),
                  ),

                  // Corner brackets
                  const CustomPaint(
                    size: Size(frameSize, frameSize),
                    painter: _CornerBracketPainter(),
                  ),

                  // Animated scan line
                  AnimatedBuilder(
                    animation: _scanPos,
                    builder: (_, __) => Positioned(
                      top: 20 + _scanPos.value * (frameSize - 40),
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              _kBracket,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Instructions ─────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 44),
              child: Text(
                'Position the QR code found on your fan packaging within the frame to automatically connect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB0BCC9),
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ),

            const SizedBox(height: 36),

            // ── Torch toggle ─────────────────────────────────────────────────
            GestureDetector(
              onTap: () {
                setState(() => _torchOn = !_torchOn);
                _ctrl.toggleTorch();
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _torchOn ? _kBracket.withAlpha(40) : _kCardDark,
                  shape: BoxShape.circle,
                  border: _torchOn
                      ? Border.all(color: _kBracket.withAlpha(160), width: 1.5)
                      : null,
                ),
                child: Icon(
                  _torchOn ? Icons.flashlight_on_rounded : Icons.bolt_rounded,
                  color: _torchOn ? _kBracket : Colors.white70,
                  size: 24,
                ),
              ),
            ),

            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBracket
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const arm   = 28.0; // length of each bracket arm
    const corner = 10.0; // corner radius

    // ── top-left ─────────────────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(0, corner + arm)
        ..lineTo(0, corner)
        ..arcToPoint(const Offset(corner, 0),
            radius: const Radius.circular(corner), clockwise: true)
        ..lineTo(corner + arm, 0),
      paint,
    );

    // ── top-right ────────────────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(size.width - corner - arm, 0)
        ..lineTo(size.width - corner, 0)
        ..arcToPoint(Offset(size.width, corner),
            radius: const Radius.circular(corner), clockwise: true)
        ..lineTo(size.width, corner + arm),
      paint,
    );

    // ── bottom-left ──────────────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - corner - arm)
        ..lineTo(0, size.height - corner)
        ..arcToPoint(Offset(corner, size.height),
            radius: const Radius.circular(corner), clockwise: false)
        ..lineTo(corner + arm, size.height),
      paint,
    );

    // ── bottom-right ─────────────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(size.width - corner - arm, size.height)
        ..lineTo(size.width - corner, size.height)
        ..arcToPoint(Offset(size.width, size.height - corner),
            radius: const Radius.circular(corner), clockwise: false)
        ..lineTo(size.width, size.height - corner - arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter _) => false;
}


