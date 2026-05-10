// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPrimary    = Color(0xFF1A56A0);
const kBackground = Color(0xFFF5F7FA);

const List<Color> kSpeedColors = [
  Color(0xFF22C55E), // Speed 1 — Green
  Color(0xFF06B6D4), // Speed 2 — Cyan
  Color(0xFF3B82F6), // Speed 3 — Blue
  Color(0xFF8B5CF6), // Speed 4 — Violet
  Color(0xFFF97316), // Speed 5 — Orange
  Color(0xFFEF4444), // Speed 6 — Red
];

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      surface: kBackground,
    ),
    scaffoldBackgroundColor: kBackground,
  );

  return base.copyWith(
    textTheme: GoogleFonts.nunitoTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withAlpha(20),
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EDF2)),
      ),
    ),
  );
}
