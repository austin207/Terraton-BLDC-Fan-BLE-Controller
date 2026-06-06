// lib/features/control/air_purification_control.dart
//
// Control widget for Air Purification appliances (AQM Monitor, Air Purifier).
// Registered under the 'air_quality' control type in ControlRegistry.
// All sections are pending until Terraton provides BLE command bytes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/features/control/appliance_pending_widgets.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Builder registered as 'air_quality' in ControlRegistry.
Widget buildAirPurificationControl(ControlBuildParams p) =>
    _AirPurificationControl(params: p);

class _AirPurificationControl extends StatelessWidget {
  final ControlBuildParams params;
  const _AirPurificationControl({required this.params});

  void _pending(BuildContext ctx) =>
      showPendingSnackBar(ctx, 'Air purification');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Fan speed ─────────────────────────────────────────────────────────
        const ApplianceSectionHeader('FAN SPEED'),
        PendingToggleRow(
          options: const ['Low', 'Med', 'High'],
          onTap: () => _pending(context),
        ),
        const SizedBox(height: 16),

        // ── Operating mode ────────────────────────────────────────────────────
        const ApplianceSectionHeader('OPERATING MODE'),
        PendingToggleRow(
          options: const ['Auto', 'Sleep', 'Turbo'],
          onTap: () => _pending(context),
        ),
        const SizedBox(height: 20),

        // ── Air quality readings ──────────────────────────────────────────────
        const ApplianceSectionHeader('AIR QUALITY'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.air_outlined,
              label: 'AQI',
            ),
            PendingMetricRow(
              icon: Icons.grain_outlined,
              label: 'PM2.5',
              unit: 'μg/m³',
            ),
            PendingMetricRow(
              icon: Icons.co2_outlined,
              label: 'CO₂',
              unit: 'ppm',
            ),
            PendingMetricRow(
              icon: Icons.thermostat_outlined,
              label: 'Temperature',
              unit: '°C',
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
              label: 'HEPA Filter Life',
              unit: '%',
            ),
            PendingMetricRow(
              icon: Icons.calendar_today_outlined,
              label: 'Days to Replace',
              unit: 'days',
            ),
          ],
        ),
        const SizedBox(height: 12),

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
