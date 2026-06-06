// lib/features/control/energy_storage_control.dart
//
// Control widget for Energy / Storage appliances (Solar, Battery, Power Conversion).
// Registered under the 'energy_metrics' control type in ControlRegistry.
// All sections are pending until Terraton provides BLE command bytes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/features/control/appliance_pending_widgets.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Builder registered as 'energy_metrics' in ControlRegistry.
Widget buildEnergyStorageControl(ControlBuildParams p) =>
    _EnergyStorageControl(params: p);

class _EnergyStorageControl extends StatelessWidget {
  final ControlBuildParams params;
  const _EnergyStorageControl({required this.params});

  void _pending(BuildContext ctx) =>
      showPendingSnackBar(ctx, 'Energy / Storage');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Power output / generation ─────────────────────────────────────────
        const ApplianceSectionHeader('POWER OUTPUT'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.bolt_outlined,
              label: 'Current Output',
              unit: 'W',
            ),
            PendingMetricRow(
              icon: Icons.electric_bolt_outlined,
              label: 'Voltage',
              unit: 'V',
            ),
            PendingMetricRow(
              icon: Icons.electrical_services_outlined,
              label: 'Current',
              unit: 'A',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Storage status ────────────────────────────────────────────────────
        const ApplianceSectionHeader('STORAGE'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.battery_charging_full_outlined,
              label: 'State of Charge',
              unit: '%',
            ),
            PendingMetricRow(
              icon: Icons.speed_outlined,
              label: 'Charge Rate',
              unit: 'W',
            ),
            PendingMetricRow(
              icon: Icons.timelapse_outlined,
              label: 'Time to Full',
              unit: 'h',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Grid / system status ──────────────────────────────────────────────
        const ApplianceSectionHeader('SYSTEM STATUS'),
        const PendingMetricCard(
          rows: [
            PendingMetricRow(
              icon: Icons.grid_on_outlined,
              label: 'Grid Connection',
            ),
            PendingMetricRow(
              icon: Icons.analytics_outlined,
              label: 'System Efficiency',
              unit: '%',
            ),
            PendingMetricRow(
              icon: Icons.thermostat_outlined,
              label: 'Temperature',
              unit: '°C',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Operating mode ────────────────────────────────────────────────────
        const ApplianceSectionHeader('OPERATING MODE'),
        PendingToggleRow(
          options: const ['Normal', 'Eco', 'Backup'],
          onTap: () => _pending(context),
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
