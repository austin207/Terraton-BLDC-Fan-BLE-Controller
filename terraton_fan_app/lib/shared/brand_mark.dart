// lib/shared/brand_mark.dart
//
// Terraton brand mark widget.
//
// full=true  (screen headers): terraton-mark.png icon + "Terraton" text in a Row.
//            The previous ClipRect/Transform crop approach produced invisible output;
//            this direct approach is reliable at all sizes.
// full=false (splash screen):  terraton-mark.png only — standalone power-T mark.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BrandMark extends StatelessWidget {
  final double height;
  final bool full;

  const BrandMark({
    super.key,
    this.height = 22,
    this.full = true,
  });

  @override
  Widget build(BuildContext context) {
    // Mark-only path: splash screen, stand-alone icon contexts.
    if (!full) {
      return Semantics(
        label: 'Terraton',
        child: Image.asset(
          'assets/logos/terraton-mark.png',
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    // Full wordmark: power-T mark + "Terraton" text side by side.
    // Proportions kept consistent regardless of height.
    return Semantics(
      label: 'Terraton',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/logos/terraton-mark.png',
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          SizedBox(width: height * 0.36),
          Text(
            'Terraton',
            style: GoogleFonts.manrope(
              fontSize: height * 0.80,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFAAAAAA),
              letterSpacing: -0.2,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
