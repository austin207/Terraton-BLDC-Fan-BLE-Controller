// lib/features/control/water_filtration_control.dart
//
// Control widget for Water Filtration appliances (RO Filter, UF/UV Filter).
// Registered under the 'water_quality' control type in ControlRegistry.
// All sections are pending until Terraton provides BLE command bytes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/features/control/appliance_pending_widgets.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Builder registered as 'water_quality' in ControlRegistry.
Widget buildWaterFiltrationControl(ControlBuildParams p) =>
    _WaterFiltrationControl(params: p);

class _WaterFiltrationControl extends StatelessWidget {
  final ControlBuildParams params;
  const _WaterFiltrationControl({required this.params});

  void _pending(BuildContext ctx) =>
      showPendingSnackBar(ctx, 'Water filtration');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Purification mode ─────────────────────────────────────────────────
        const ApplianceSectionHeader('PURIFICATION MODE'),
        PendingToggleRow(
          options: const ['Standard', 'Fast', 'Eco'],
          onTap: () => _pending(context),
        ),
        const SizedBox(height: 20),

        // ── Water quality readings ────────────────────────────────────────────
        const ApplianceSectionHeader('WATER QUALITY'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.opacity_outlined,
              label: 'TDS',
              unit: 'ppm',
            ),
            PendingMetricRow(
              icon: Icons.water_outlined,
              label: 'Flow Rate',
              unit: 'L/h',
            ),
            PendingMetricRow(
              icon: Icons.science_outlined,
              label: 'Purity Level',
              unit: '%',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Filter status ─────────────────────────────────────────────────────
        const ApplianceSectionHeader('FILTER STATUS'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.filter_alt_outlined,
              label: 'Filter Life',
              unit: '%',
            ),
            PendingMetricRow(
              icon: Icons.calendar_today_outlined,
              label: 'Days to Change',
              unit: 'days',
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Notice
        _PendingNotice(onTap: () => _pending(context)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PendingNotice extends StatelessWidget {
  final VoidCallback onTap;
  const _PendingNotice({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kYellowFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kYellowBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 16, color: kYellow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Full controls available once Terraton provides command bytes.',
              style: GoogleFonts.manrope(fontSize: 12, color: kTextMut),
            ),
          ),
        ],
      ),
    ),
  );
}
