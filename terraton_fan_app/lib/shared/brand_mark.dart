// lib/shared/brand_mark.dart
//
// Terraton brand assets.
//
// full=true  (headers):  PNG crop of terraton-full.png — power-T mark + wordmark
// full=false (splash):   terraton-mark.png — standalone power-T mark, no wordmark text
//
// The crop approach (full=true) is a direct port of the JSX BrandMark:
//   canvas W=537 H=464, logo at x=123 y=204 w=299 h=69
//   scale image so crop height == desired display height, offset to (0,0).
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double height;
  final bool full;

  const BrandMark({
    super.key,
    this.height = 22,
    this.full = true,
  });

  // Canvas constants matching LOGO_CROP in components.jsx
  static const double _cW = 537, _cH = 464;
  static const double _x = 123, _y = 204, _w = 299, _h = 69;

  @override
  Widget build(BuildContext context) {
    // Splash / mark-only path — standalone power-T mark (no wordmark text)
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

    // Full wordmark — crop terraton-full.png using the JSX math:
    //   scale = height / h          (so crop-height fills display height)
    //   dispW = w * scale           (display width from crop aspect ratio)
    //   imgW  = cW * scale          (full image rendered at this width)
    //   imgH  = cH * scale          (full image rendered at this height)
    //   offX  = -(x * scale)        (shift image left so crop x=0 on screen)
    //   offY  = -(y * scale)        (shift image up so crop y=0 on screen)
    final scale = height / _h;
    final dispW = (_w * scale).roundToDouble();
    final imgW  = _cW * scale;
    final imgH  = _cH * scale;
    final offX  = -(_x * scale);
    final offY  = -(_y * scale);

    return Semantics(
      label: 'Terraton',
      child: SizedBox(
        width: dispW,
        height: height,
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(offX, offY),
            child: Image.asset(
              'assets/logos/terraton-full.png',
              width: imgW,
              height: imgH,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
