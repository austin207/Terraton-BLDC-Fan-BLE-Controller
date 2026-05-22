// lib/shared/brand_mark.dart
//
// Terraton brand mark — drawn entirely on-GPU (no PNG crop).
//
// full=true  (headers):  TerratonFanIcon + "Terraton" wordmark side-by-side
// full=false (splash):   TerratonFanIcon alone at the requested height
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

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
    final icon = TerratonFanIcon(size: height, color: kYellow);

    if (!full) return Semantics(label: 'Terraton', child: icon);

    // Full wordmark: icon + "Terraton" text aligned on the baseline
    return Semantics(
      label: 'Terraton',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 7),
          Text(
            'Terraton',
            style: GoogleFonts.manrope(
              fontSize: height * 0.85,
              fontWeight: FontWeight.w700,
              color: kText,
              letterSpacing: -0.3,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
