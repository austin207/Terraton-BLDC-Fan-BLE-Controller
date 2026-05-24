// lib/features/settings/service_qr_modal.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/theme.dart';

// Step 1: fan picker (if multiple fans paired).
// Step 2: real QR code + 3-hour countdown.
// The QR encodes JSON that QrScanScreen recognises as a service_access token.

class ServiceQrModal extends StatefulWidget {
  final List<FanDevice> fans;
  const ServiceQrModal({super.key, required this.fans});

  @override
  State<ServiceQrModal> createState() => _ServiceQrModalState();
}

class _ServiceQrModalState extends State<ServiceQrModal> {
  static const _accessDuration = Duration(hours: 3);
  static const _ttlSecs        = 3 * 60 * 60;

  FanDevice? _selectedFan;
  DateTime?  _expiresAt;
  int        _remaining = _ttlSecs;
  String     _qrData    = '';
  Timer?     _timer;

  @override
  void initState() {
    super.initState();
    if (widget.fans.length == 1) _selectFan(widget.fans[0]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectFan(FanDevice fan) {
    _expiresAt = DateTime.now().add(_accessDuration);
    setState(() {
      _selectedFan = fan;
      _remaining   = _ttlSecs;
      _qrData      = _computeQrData(fan, _expiresAt!);
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = math.max(0, _remaining - 1);
      setState(() => _remaining = next);
      if (next == 0) _timer?.cancel();
    });
  }

  void _regenerate() {
    final newExpiry = DateTime.now().add(_accessDuration);
    setState(() {
      _expiresAt = newExpiry;
      _remaining = _ttlSecs;
      _qrData    = _computeQrData(_selectedFan!, newExpiry);
    });
    _startTimer();
  }

  String get _hh => (_remaining ~/ 3600).toString().padLeft(2, '0');
  String get _mm => ((_remaining % 3600) ~/ 60).toString().padLeft(2, '0');
  String get _ss => (_remaining % 60).toString().padLeft(2, '0');

  static String _computeQrData(FanDevice fan, DateTime expiresAt) => jsonEncode({
    'type':         'service_access',
    'version':      1,
    'fan_mac':      fan.macAddress,
    'fan_nickname': fan.nickname,
    'model':        fan.model,
    'expires_at':   expiresAt.millisecondsSinceEpoch ~/ 1000,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(22),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [kCardElev, kSurface],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: kHairlineStrong),
                boxShadow: const [BoxShadow(color: kModalShadow, blurRadius: 80)],
              ),
              child: _selectedFan == null
                  ? _buildFanPicker()
                  : _buildQrView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFanPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox(width: 32, height: 32,
                child: Icon(Icons.close_rounded, color: kTextMut, size: 16)),
          ),
        ),
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: kYellowFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kYellowBorderHi),
            boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 24)],
          ),
          child: const Icon(Icons.build_circle_outlined, color: kYellow, size: 22),
        ),
        const SizedBox(height: 18),
        Text('Service QR',
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700,
                color: kText, letterSpacing: -0.2)),
        const SizedBox(height: 6),
        Text('Select the fan the technician will service.',
            style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.45)),
        const SizedBox(height: 20),
        if (widget.fans.isEmpty)
          Text('No fans paired yet. Add a fan first.',
              style: GoogleFonts.manrope(fontSize: 13, color: kTextDim))
        else
          ...widget.fans.map((fan) {
            final noMac = fan.macAddress.isEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: noMac ? null : () => _selectFan(fan),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: noMac ? kCard.withAlpha(128) : kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kHairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fan.nickname,
                                style: GoogleFonts.manrope(fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: noMac ? kTextDim : kText)),
                            if (fan.model.isNotEmpty)
                              Text(fan.model,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 10,
                                      color: kTextMut)),
                            if (noMac)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Connect to this fan once before sharing',
                                    style: GoogleFonts.manrope(fontSize: 11, color: kRed)),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: noMac ? kTextDim : kTextMut, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 50,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              backgroundColor: kCardHi,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Cancel',
                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
          ),
        ),
      ],
    );
  }

  Widget _buildQrView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox(width: 32, height: 32,
                child: Icon(Icons.close_rounded, color: kTextMut, size: 16)),
          ),
        ),
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: kYellowFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kYellowBorderHi),
            boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 24)],
          ),
          child: const Icon(Icons.qr_code_rounded, color: kYellow, size: 22),
        ),
        const SizedBox(height: 18),
        Text('Service QR',
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700,
                color: kText, letterSpacing: -0.2)),
        const SizedBox(height: 6),
        Text(
          'Let a Terraton technician scan this with their copy of the app. '
          'Access expires in 3 hours.',
          style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.45),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kYellowBorder),
            boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 22)],
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: QrImageView(
                  data: _qrData,
                  size: 184,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _selectedFan!.nickname.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: kText, letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: kYellow,
                  boxShadow: [BoxShadow(color: kYellowGlow, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EXPIRES IN',
                        style: GoogleFonts.jetBrainsMono(fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kTextMut, letterSpacing: 1.8)),
                    const SizedBox(height: 2),
                    Text('$_hh:$_mm:$_ss',
                        style: GoogleFonts.jetBrainsMono(fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kText, letterSpacing: 0.4)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _regenerate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kHairlineStrong),
                  ),
                  child: Text('REGENERATE',
                      style: GoogleFonts.manrope(fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kText, letterSpacing: 0.6)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity, height: 50,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              backgroundColor: kCardHi,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Done',
                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
          ),
        ),
      ],
    );
  }
}
