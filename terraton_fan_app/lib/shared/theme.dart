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
const kYellowFill     = Color(0x1AFFEC00); // 10 % yellow — icon badge fill
const kYellowBorder   = Color(0x38FFEC00); // 22 % yellow — icon badge border
const kYellowBorderHi = Color(0x47FFEC00); // 28 % yellow — stronger badge border

// ── Lighting temperature ──────────────────────────────────────────────────────
const kLightWarm    = Color(0xFFE6B85C); // amber — warm CCT
const kLightNeutral = Color(0xFFCFCFCF); // white/gray — neutral CCT
const kLightCool    = Color(0xFFDDEEFF); // pale blue — cool CCT

// ── Blue accent (settings, BLE badge, data management icons) ─────────────────
const kBlue     = Color(0xFF7AA7FF);
const kBlueFill = Color(0x207AA7FF); // 12 % blue — icon badge fill

// ── Green fill (data management import icon) ──────────────────────────────────
const kGreenFill = Color(0x207AE582); // 12 % green — icon badge fill

// ── Yellow misc ───────────────────────────────────────────────────────────────
const kYellowFaint = Color(0x03FFEC00); // 1 % yellow — gradient terminal fade
const kYellowDim   = Color(0x0FFFEC00); // 6 % yellow — spread shadow tint

// ── Overlay ───────────────────────────────────────────────────────────────────
const kModalShadow     = Color(0xB3000000); // 70 % black — modal drop shadow
const kModalShadowSoft = Color(0x99000000); // 60 % black — lighter modal drop shadow

// ── Neutral white overlays (chart / dial accents) ─────────────────────────────
const kGridLine = Color(0x0AFFFFFF); //  4 % white — chart gridlines / dial track
const kDialTick = Color(0x38FFFFFF); // 22 % white — unselected dial ticks & dots

// ── Speed dial core gradient ──────────────────────────────────────────────────
const kDialCoreTop = Color(0xFF1F1F1F);
const kDialCoreBot = Color(0xFF0A0A0A);

// ── Disabled control affordances ──────────────────────────────────────────────
const kDisabledRim  = Color(0x47FFFFFF); // 28 % white — disabled power-button rim
const kDisabledIcon = Color(0x8CFFFFFF); // 55 % white — disabled icon glyph

// ── Lighting colour swatch ────────────────────────────────────────────────────
const kLightSwatchOff = Color(0xFF2A2A2A); // inactive lighting colour swatch

// ── Comparison arrows (analytics — lower energy is better) ───────────────────
const kCompareGood = Color(0xFF22C55E); // green — lower vs previous period
const kCompareBad  = Color(0xFFEF4444); // red   — higher vs previous period

// ── Status ────────────────────────────────────────────────────────────────────
const kGreen  = Color(0xFF7AE582);
const kRed    = Color(0xFFFF6B6B);
const kOrange = Color(0xFFF97316); // orange — fair RSSI signal, kSpeedColors[4]
const kPurple = Color(0xFFB68BFF); // soft lavender — user manual accent
const kAmber  = Color(0xFFFFB400); // warm amber    — boost/highlight accent

// ── Power button states ───────────────────────────────────────────────────────
const kPowerOn  = Color(0xFF3FD37A); // connected + powered on
const kPowerOff = Color(0xFFE5484D); // connected + powered off

// Alpha shades of the power-button colours (fill + two glow layers per state).
// Kept as const tokens so the BoxShadow lists stay const.
const kPowerOnFill   = Color(0x1A3FD37A);
const kPowerOnGlow1  = Color(0x8C3FD37A);
const kPowerOnGlow2  = Color(0x4D3FD37A);
const kPowerOffFill  = Color(0x14E5484D);
const kPowerOffGlow1 = Color(0x4DE5484D);
const kPowerOffGlow2 = Color(0x26E5484D);

// ── Bluetooth indicator accent ────────────────────────────────────────────────
// Distinct from kBlue (the settings/UI accent). Faint variant is the blink fade.
const kBluetoothBlue      = Color(0xFF409CFF);
const kBluetoothBlueFaint = Color(0x1A409CFF);

// ── Nature mode green ─────────────────────────────────────────────────────────
// Shares its hue with kCompareGood but is semantically the Nature-mode accent.
const kNatureGreen = Color(0xFF22C55E);

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
