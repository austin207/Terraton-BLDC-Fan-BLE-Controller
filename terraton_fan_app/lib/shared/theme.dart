// lib/shared/theme.dart
import 'package:flutter/material.dart';

const kPrimary    = Color(0xFF1A56A0);
const kBackground = Color(0xFFF5F7FA);
const kBoostColor = Colors.deepOrange;

// Speed segment colours per AC-05-3
const List<Color> kSpeedColors = [
  Color(0xFF1E8449), // Speed 1 — Green
  Color(0xFF1A56A0), // Speed 2 — Blue
  Color(0xFF7D3C98), // Speed 3 — Violet
  Color(0xFFD4AC0D), // Speed 4 — Yellow
  Color(0xFFD35400), // Speed 5 — Orange
  Color(0xFFC0392B), // Speed 6 — Red
];

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      surface: kBackground,
    ),
    scaffoldBackgroundColor: kBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
