// lib/features/control/appliance_pending_widgets.dart
//
// Shared UI primitives for pending (not-yet-active) appliance control screens.
// All non-fan categories use these until Terraton provides BLE command bytes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Shows a "commands pending from Terraton" snackbar.
void showPendingSnackBar(BuildContext context, String category) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$category commands pending from Terraton'),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Section header matching the style of _SectionHeader in control_screen.dart.
class ApplianceSectionHeader extends StatelessWidget {
  final String title;
  const ApplianceSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(
          title,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: kTextMut, letterSpacing: 1.8,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: kHairline, thickness: 1, height: 1)),
      ],
    ),
  );
}

/// Card containing a list of [PendingMetricRow]s.
class PendingMetricCard extends StatelessWidget {
  final List<PendingMetricRow> rows;
  const PendingMetricCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kHairline),
    ),
    child: Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: rows[i],
          ),
          if (i < rows.length - 1)
            const Divider(color: kHairline, height: 1, thickness: 0.5),
        ],
      ],
    ),
  );
}

/// One metric row: icon + label on the left, '--' value + PENDING badge on the right.
class PendingMetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? unit;

  const PendingMetricRow({
    super.key,
    required this.icon,
    required this.label,
    this.unit,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: kCardElev,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: kTextMut),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14, fontWeight: FontWeight.w600, color: kText,
          ),
        ),
      ),
      Text(
        unit != null ? '-- $unit' : '--',
        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: kTextDim),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: kCardElev,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kHairline),
        ),
        child: Text(
          'PENDING',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 8, fontWeight: FontWeight.w700,
            color: kTextDim, letterSpacing: 1.2,
          ),
        ),
      ),
    ],
  );
}

/// Row of toggle buttons where all options are pending.
/// Renders the shape of what the real control will look like.
class PendingToggleRow extends StatelessWidget {
  final List<String> options;
  final VoidCallback onTap;

  const PendingToggleRow({
    super.key,
    required this.options,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: options.map((opt) {
      final isFirst = opt == options.first;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: isFirst ? 0 : 6),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kHairline),
              ),
              alignment: Alignment.center,
              child: Text(
                opt,
                style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kTextMut,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}
