// lib/shared/brand_mark.dart
//
// full=true  (screen headers): terraton-full.png — client trademark wordmark.
//   The PNG canvas is 537×464 px; the actual logo content sits in the centre
//   ~32% of the image height, surrounded by transparent whitespace.
//   We render the image tall enough so the logo content equals `height`, then
//   crop the transparent padding with ClipRect + Align(heightFactor).
//   Alignment.centerLeft pins the wordmark to the left edge of its parent.
//
// full=false (splash screen): terraton-mark.png — standalone power-T icon.
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double height;
  final bool full;

  const BrandMark({
    super.key,
    this.height = 34,
    this.full = true,
  });

  // Fraction of the PNG canvas occupied by the logo content (vertically).
  // Logo runs from ~32 % to ~65 % of the 464 px canvas → ~33 % band.
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

    // Render image tall enough so logo content == `height` dp,
    // crop whitespace, and pin to left edge of parent.
    final double renderH = height / _cropFactor;
    return Semantics(
      label: 'Terraton',
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
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
