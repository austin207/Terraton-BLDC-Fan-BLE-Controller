// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Background layers ─────────────────────────────────────────────────────────
const kBg       = Color(0xFF000000);
const kSurface  = Color(0xFF0E0E0E);
const kCard     = Color(0xFF141414);
const kCardElev = Color(0xFF1A1A1A);
const kCardHi   = Color(0xFF222222);

// ── Borders ───────────────────────────────────────────────────────────────────
const kHairline       = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
const kHairlineStrong = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)

// ── Text ──────────────────────────────────────────────────────────────────────
const kText    = Color(0xFFF4F4F2);
const kTextMut = Color(0xFF9A9A95);
const kTextDim = Color(0xFF5C5C58);

// ── Accent ────────────────────────────────────────────────────────────────────
const kYellow       = Color(0xFFFFEC00);
const kYellowSoft   = Color(0xFFFFF066);
const kYellowGlow   = Color(0x59FFEC00); // rgba(255,236,0,0.35)
const kYellowFill   = Color(0x1AFFEC00); // 10 % yellow — icon badge fill
const kYellowBorder = Color(0x38FFEC00); // 22 % yellow — icon badge border

// ── Status ────────────────────────────────────────────────────────────────────
const kGreen = Color(0xFF7AE582);
const kRed   = Color(0xFFFF6B6B);

// ── Power button states ───────────────────────────────────────────────────────
const kPowerOn  = Color(0xFF3FD37A); // connected + powered on
const kPowerOff = Color(0xFFE5484D); // connected + powered off

// ── Legacy aliases (kept so unchanged imports compile) ────────────────────────
const kPrimary    = kYellow;
const kBackground = kBg;

// Speed dot colours — kept for any remaining arc references
const List<Color> kSpeedColors = [
  Color(0xFF22C55E), // 1 — Green
  Color(0xFF06B6D4), // 2 — Cyan
  Color(0xFF3B82F6), // 3 — Blue
  Color(0xFF8B5CF6), // 4 — Violet
  Color(0xFFF97316), // 5 — Orange
  Color(0xFFEF4444), // 6 — Red
];

// ── Mono text style helper ────────────────────────────────────────────────────
TextStyle kMonoStyle({
  double size = 12,
  FontWeight weight = FontWeight.w600,
  Color color = kText,
  double letterSpacing = 0,
}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );

// ── App theme ─────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: kYellow,
      onPrimary: Colors.black,
      surface: kSurface,
      onSurface: kText,
      surfaceContainerHighest: kCardHi,
    ),
    scaffoldBackgroundColor: kBg,
  );

  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: kText,
      displayColor: kText,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: kText),
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kYellow,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: kCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kHairline),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      modalBackgroundColor: kSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kCardElev,
      contentTextStyle: GoogleFonts.manrope(color: kText, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: kHairline, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: kText,
      iconColor: kTextMut,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      hintStyle: const TextStyle(color: kTextDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kYellow, width: 1.5),
      ),
    ),
  );
}
