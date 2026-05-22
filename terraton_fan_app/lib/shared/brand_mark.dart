// lib/shared/brand_mark.dart
//
// full=true  (screen headers): terraton-full.png — the complete client-supplied wordmark image.
// full=false (splash screen):  terraton-mark.png — standalone power-T icon only.
import 'package:flutter/material.dart';

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
    return Semantics(
      label: 'Terraton',
      child: Image.asset(
        full ? 'assets/logos/terraton-full.png' : 'assets/logos/terraton-mark.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
