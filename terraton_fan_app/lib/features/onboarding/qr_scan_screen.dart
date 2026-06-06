// lib/features/onboarding/qr_scan_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen>
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
    unawaited(showDialog<void>(
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
                unawaited(openAppSettings());
              },
              child: const Text('Open Settings')),
        ],
      ),
    ));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    try {
      // Untrusted external input — validate the decoded TYPE before casting.
      // Valid-but-non-object JSON (e.g. "[1,2]", "5", "\"x\"") decodes without a
      // FormatException, so `as Map` would throw an uncaught TypeError.
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _showInvalidSnack();
        return;
      }
      final json = decoded;

      // ── Service access token ──────────────────────────────────────────────
      if (json['type'] == 'service_access') {
        unawaited(_handleServiceAccess(json));
        return;
      }

      // ── Normal fan pairing QR ─────────────────────────────────────────────
      final deviceId  = json['device_id']  as String?;
      final model     = json['model']      as String?;
      final fwVersion = json['fw_version'] as String?;

      if (deviceId == null || model == null || fwVersion == null) {
        _showInvalidSnack();
        return;
      }
      if (deviceId.isEmpty || deviceId == kDemoDeviceId ||
          deviceId.length > 64 || model.length > 64 || fwVersion.length > 32) {
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

      if (mounted) {
        unawaited(
          context.push(AppRoutes.nameFan, extra: fan).then((_) {
            if (mounted) setState(() => _handled = false);
          }),
        );
      }
    } on FormatException {
      _showInvalidSnack();
    }
  }

  Future<void> _handleServiceAccess(Map<String, dynamic> json) async {
    final mac      = json['fan_mac']      as String? ?? '';
    final nickname = json['fan_nickname'] as String? ?? 'Service Fan';
    final model    = json['model']        as String? ?? '';
    final expSecs  = json['expires_at']   as int?    ?? 0;

    if (mac.isEmpty) { _showInvalidSnack(); return; }
    if (expSecs <= 0) { _showInvalidSnack(); return; }

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expSecs * 1000);
    if (DateTime.now().isAfter(expiresAt)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This service QR has expired. Ask the customer to generate a new one.')),
      );
      return;
    }

    _handled = true;
    final fan = FanDevice()
      ..deviceId         = 'svc_${mac}_${DateTime.now().millisecondsSinceEpoch}'
      ..macAddress       = mac
      ..nickname         = nickname
      ..model            = model
      ..isServiceAccess  = true
      ..serviceExpiresAt = expiresAt
      ..addedAt          = DateTime.now();

    await ref.read(fanRepositoryProvider).saveFan(fan);
    if (!mounted) return;
    ref.invalidate(savedFansProvider);
    unawaited(context.push(AppRoutes.control, extra: fan).then((_) {
      if (mounted) setState(() => _handled = false);
    }));
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
    unawaited(_ctrl.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the granular selectors so this only rebuilds on size/padding changes,
    // not on every MediaQuery change (text scale, brightness, etc.).
    final screenSize  = MediaQuery.sizeOf(context);
    final padding     = MediaQuery.paddingOf(context);
    final topPad      = padding.top;
    final bottomPad   = padding.bottom;

    // Frame sits centered in the space between the top bar and the bottom panel.
    const topBarH      = 64.0;
    const bottomPanelH = 148.0;
    const frameSize    = 272.0;
    final availH   = screenSize.height - topPad - topBarH - bottomPanelH - bottomPad;
    final frameTop = topPad + topBarH + (availH - frameSize).clamp(0.0, double.infinity) / 2;
    final frameLeft = (screenSize.width - frameSize) / 2;
    final cutout = Rect.fromLTWH(frameLeft, frameTop, frameSize, frameSize);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Camera feed ────────────────────────────────────────────────────
          if (_cameraReady)
            MobileScanner(
              controller: _ctrl,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            )
          else
            const ColoredBox(color: Color(0xFF0A0A0A)),

          // ── Semi-transparent overlay with cutout ───────────────────────────
          CustomPaint(
            size: screenSize,
            painter: _OverlayCutoutPainter(cutout: cutout),
          ),

          // ── Corner bracket markers ─────────────────────────────────────────
          Positioned(
            left: cutout.left - 3,
            top:  cutout.top  - 3,
            width:  cutout.width  + 6,
            height: cutout.height + 6,
            child: const CustomPaint(painter: _CornerBracketPainter()),
          ),

          // ── Scan line ──────────────────────────────────────────────────────
          if (_cameraReady)
            AnimatedBuilder(
              animation: _scanPos,
              builder: (_, __) => Positioned(
                left:   cutout.left   + 16,
                top:    cutout.top    + 12 + _scanPos.value * (cutout.height - 24),
                width:  cutout.width  - 32,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        kYellow.withAlpha(140),
                        kYellow,
                        kYellow.withAlpha(140),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),

          // ── Top bar: close + torch ─────────────────────────────────────────
          Positioned(
            top:   topPad,
            left:  0,
            right: 0,
            height: topBarH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _OverlayIconBtn(
                    icon: Icons.close_rounded,
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  _OverlayIconBtn(
                    icon: _torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    active: _torchOn,
                    onTap: !_cameraReady ? null : () {
                      setState(() => _torchOn = !_torchOn);
                      unawaited(_ctrl.toggleTorch());
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom panel ───────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left:   0,
            right:  0,
            child: Container(
              padding: EdgeInsets.fromLTRB(28, 20, 28, 20 + bottomPad),
              decoration: const BoxDecoration(
                color: Color(0xEE111111),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: kCardHi,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Scan Fan QR Code',
                    style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Point the camera at the QR sticker on your Terraton fan packaging.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 13, color: kTextMut, height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── No-permission placeholder ──────────────────────────────────────
          if (!_cameraReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt_outlined, color: kTextDim, size: 48),
                  const SizedBox(height: 16),
                  Text('Camera access required',
                      style: GoogleFonts.manrope(
                          fontSize: 15, fontWeight: FontWeight.w600, color: kTextMut)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Overlay with transparent cutout ──────────────────────────────────────────

class _OverlayCutoutPainter extends CustomPainter {
  final Rect cutout;
  const _OverlayCutoutPainter({required this.cutout});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xC0000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutout, const Radius.circular(18)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverlayCutoutPainter old) => old.cutout != cutout;
}

// ── Corner bracket markers ────────────────────────────────────────────────────

class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kYellow
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const arm    = 32.0;
    const radius = 18.0;

    // top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, radius + arm)
        ..lineTo(0, radius)
        ..arcToPoint(const Offset(radius, 0),
            radius: const Radius.circular(radius), clockwise: true)
        ..lineTo(radius + arm, 0),
      paint,
    );
    // top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - radius - arm, 0)
        ..lineTo(size.width - radius, 0)
        ..arcToPoint(Offset(size.width, radius),
            radius: const Radius.circular(radius), clockwise: true)
        ..lineTo(size.width, radius + arm),
      paint,
    );
    // bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - radius - arm)
        ..lineTo(0, size.height - radius)
        ..arcToPoint(Offset(radius, size.height),
            radius: const Radius.circular(radius), clockwise: false)
        ..lineTo(radius + arm, size.height),
      paint,
    );
    // bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - radius - arm, size.height)
        ..lineTo(size.width - radius, size.height)
        ..arcToPoint(Offset(size.width, size.height - radius),
            radius: const Radius.circular(radius), clockwise: false)
        ..lineTo(size.width, size.height - radius - arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter _) => false;
}

// ── Icon button for the overlay controls ──────────────────────────────────────

class _OverlayIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  const _OverlayIconBtn({required this.icon, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: active ? kYellowFill : const Color(0x55000000),
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? kYellowBorder : const Color(0x44FFFFFF),
          width: 1.2,
        ),
      ),
      child: Icon(
        icon,
        color: active ? kYellow : Colors.white,
        size: 20,
      ),
    ),
  );
}
