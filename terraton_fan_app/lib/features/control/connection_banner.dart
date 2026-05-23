// lib/features/control/connection_banner.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ConnectionLostCard extends StatelessWidget {
  final VoidCallback onRetry;
  final String? connectStatus;
  const ConnectionLostCard({super.key, required this.onRetry, this.connectStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kHairlineStrong),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(153), blurRadius: 40, offset: const Offset(0, -8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: kYellow.withAlpha(30),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kYellow.withAlpha(71)),
            ),
            child: const Icon(Icons.bluetooth_disabled_rounded, color: kYellow, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Fan is disconnected',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: kText),
          ),
          const SizedBox(height: 8),
          Text(
            'Is the fan powered on and within range?',
            style: GoogleFonts.manrope(fontSize: 13, color: kTextMut, height: 1.5),
            textAlign: TextAlign.center,
          ),

          // Connect status diagnostic
          if (connectStatus != null && connectStatus!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kHairline),
              ),
              child: Text(
                connectStatus!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: connectStatus!.contains('failed') ? kRed : kTextMut,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Retry button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: kYellow,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text('Reconnect',
                  style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
