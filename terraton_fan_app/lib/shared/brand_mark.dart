// lib/shared/brand_mark.dart
//
// Replicates the JSX BrandMark crop math from components.jsx.
//
// Source PNGs have large transparent padding; the actual logo sits in a
// sub-rectangle. We scale the full image so the target crop region exactly
// fills the requested display height, then clip everything outside.
//
// Canvas constants (design-canvas pixel space — see components.jsx LOGO_CROP):
//   terraton-mark.png: canvas 408×612, logo at x=120 y=207 w=168 h=187
//   terraton-full.png: canvas 537×464, logo at x=123 y=204 w=299 h=69
import 'package:flutter/material.dart';

class _Crop {
  final String asset;
  final double cW, cH, x, y, w, h;
  const _Crop({
    required this.asset,
    required this.cW, required this.cH,
    required this.x,  required this.y,
    required this.w,  required this.h,
  });
}

const _kMark = _Crop(
  asset: 'assets/logos/terraton-mark.png',
  cW: 408, cH: 612, x: 120, y: 207, w: 168, h: 187,
);

const _kFull = _Crop(
  asset: 'assets/logos/terraton-full.png',
  cW: 537, cH: 464, x: 123, y: 204, w: 299, h: 69,
);

/// Terraton brand mark widget.
///
/// [full]  = true  → icon + wordmark (terraton-full.png, used in app headers)
/// [full]  = false → icon only       (terraton-mark.png, used on splash)
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
    final c = full ? _kFull : _kMark;

    // JSX math (from components.jsx BrandMark):
    //   ratio = w / h
    //   dispH = height
    //   dispW = round(dispH * ratio)
    //   bgW   = (dispW / w) * cW    — scaled canvas width
    //   bgH   = (dispH / h) * cH    — scaled canvas height
    //   bgX   = -(dispW / w) * x    — negative offset shifts logo to (0,0)
    //   bgY   = -(dispH / h) * y
    final ratio = c.w / c.h;
    final dispH = height;
    final dispW = (dispH * ratio).roundToDouble();
    final bgW   = (dispW / c.w) * c.cW;
    final bgH   = (dispH / c.h) * c.cH;
    final bgX   = -(dispW / c.w) * c.x;
    final bgY   = -(dispH / c.h) * c.y;

    // cacheWidth/cacheHeight: decode at display size (×2 for hdpi) to
    // avoid allocating full-PNG memory for a 22 dp widget.
    final cacheW = (dispW * 2).round();
    final cacheH = (dispH * 2).round();

    // The crop: SizedBox clips to dispW×dispH; OverflowBox lets the image
    // render at bgW×bgH; Transform.translate positions the image so the
    // logo region lands at (0,0).
    return Semantics(
      label: 'Terraton',
      child: SizedBox(
        width: dispW,
        height: dispH,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: bgW,
            maxHeight: bgH,
            child: Transform.translate(
              offset: Offset(bgX, bgY),
              child: Image.asset(
                c.asset,
                width: bgW,
                height: bgH,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                cacheWidth: cacheW,
                cacheHeight: cacheH,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
