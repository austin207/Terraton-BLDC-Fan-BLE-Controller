// lib/shared/fan_icon.dart
import 'package:flutter/material.dart';

/// Terraton fan icon — uses the official brand image from assets/icon/icon.png.
class FanIcon extends StatelessWidget {
  final double size;

  const FanIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
