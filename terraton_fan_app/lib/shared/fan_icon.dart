// lib/shared/fan_icon.dart
import 'package:flutter/material.dart';

/// Terraton fan icon — uses the official brand image from assets/icon/icon.png.
/// Pass [semanticLabel] for non-decorative uses (e.g. splash, permission screens).
/// Omit it (defaults to empty string) for decorative uses where surrounding
/// widgets already provide a meaningful accessible label.
class FanIcon extends StatelessWidget {
  final double size;
  final String semanticLabel;

  const FanIcon({super.key, required this.size, this.semanticLabel = ''});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel.isEmpty ? null : semanticLabel,
    );
  }
}
