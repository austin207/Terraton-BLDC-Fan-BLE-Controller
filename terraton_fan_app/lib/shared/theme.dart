// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPrimary    = Color(0xFF1A56A0);
const kBackground = Color(0xFFF5F7FA);

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
