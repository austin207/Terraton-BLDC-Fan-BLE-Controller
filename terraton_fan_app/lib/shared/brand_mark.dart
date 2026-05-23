// lib/shared/brand_mark.dart
//
// full=true  (screen headers): terraton-full.png — client trademark wordmark.
//   PNG canvas: 537×464 px.  Visible logo content: x=123..421, y=203..272
//   (measured via pixel scan).  We render the image scaled so the content
//   height equals `height`, crop all transparent padding, and position the
//   cropped logo using `alignment`.
//
// full=false (splash screen): terraton-mark.png — standalone power-T icon.
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double height;
  final bool full;
  /// Where the cropped wordmark sits in its parent.
  /// Alignment.centerLeft for screen headers (default);
  /// Alignment.center for footer / settings contexts.
  final Alignment alignment;

  const BrandMark({
    super.key,
    this.height = 40,
    this.full = true,
    this.alignment = Alignment.centerLeft,
  });

  // Pixel boundaries of the visible logo content inside terraton-full.png
  // (537 × 464 px canvas).  Measured empirically — do not change without
  // re-running the pixel scan.
  static const double _imgW = 537;
  static const double _imgH = 464;
  static const double _cx1  = 123;   // content left edge
  static const double _cx2  = 421;   // content right edge
  static const double _cy1  = 203;   // content top edge
  static const double _cy2  = 272;   // content bottom edge

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

    // Scale so the content band (cy2−cy1 px tall) maps to `height` dp.
    final double scale    = height / (_cy2 - _cy1);
    final double renderW  = _imgW * scale;
    final double renderH  = _imgH * scale;
    final double offsetX  = _cx1 * scale;          // transparent left pad in dp
    final double offsetY  = _cy1 * scale;          // transparent top pad in dp
    final double contentW = (_cx2 - _cx1) * scale; // visible logo width in dp

    // OverflowBox renders the full (large) image inside the content-sized
    // SizedBox.  Transform.translate shifts the image so the content pixel
    // at (_cx1, _cy1) lands at (0, 0) of the SizedBox.  ClipRect removes
    // anything that paints outside the Align's bounds.
    // ClipRect must wrap SizedBox (content width), NOT Align (full parent width).
    // Wrapping Align would let the overflowed image paint beyond contentW.
    return Semantics(
      label: 'Terraton',
      child: Align(
        alignment: alignment,
        child: ClipRect(
          child: SizedBox(
            width: contentW,
            height: height,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: renderW,
              maxHeight: renderH,
              child: Transform.translate(
                offset: Offset(-offsetX, -offsetY),
                child: Image.asset(
                  'assets/logos/terraton-full.png',
                  width: renderW,
                  height: renderH,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
