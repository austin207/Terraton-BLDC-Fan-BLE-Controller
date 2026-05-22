// lib/shared/brand_mark.dart
//
// full=true  (screen headers): terraton-full.png — client trademark wordmark.
//   The PNG canvas is 537×464 px; the actual logo content sits in the centre
//   ~32% of the image height, surrounded by transparent whitespace.
//   We render the image tall enough so the logo content equals `height`, then
//   crop the transparent padding with ClipRect + Align(heightFactor).
//
// full=false (splash screen): terraton-mark.png — standalone power-T icon.
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double height;
  final bool full;

  const BrandMark({
    super.key,
    this.height = 28,
    this.full = true,
  });

  // Fraction of the PNG canvas occupied by the logo content (vertically).
  // Logo runs from ~32 % to ~65 % of the 464 px canvas height → ~33 % band.
  // heightFactor = 0.33 makes Align size itself to exactly `height` dp,
  // and AlignCenter positions the logo band in the visible window.
  static const double _cropFactor = 0.33;

  @override
  Widget build(BuildContext context) {
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

    // Render the image tall enough so the logo content == `height` dp,
    // then clip the transparent whitespace above and below.
    final double renderH = height / _cropFactor;
    return Semantics(
      label: 'Terraton',
      child: ClipRect(
        child: Align(
          alignment: Alignment.center,
          heightFactor: _cropFactor,
          child: Image.asset(
            'assets/logos/terraton-full.png',
            height: renderH,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
