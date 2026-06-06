// test/widget/appliance_control_scaffolds_test.dart
//
// Smoke tests for the pending appliance control scaffolds:
//   AirPurificationControl, WaterFiltrationControl, EnergyStorageControl.
//
// All three are "coming soon" placeholders — these tests verify they render
// their section headers and pending notices without crash. No BLE interaction
// is tested (commands are not yet assigned).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/features/control/air_purification_control.dart';
import 'package:terraton_fan_app/features/control/appliance_pending_widgets.dart';
import 'package:terraton_fan_app/features/control/control_registry.dart';
import 'package:terraton_fan_app/features/control/energy_storage_control.dart';
import 'package:terraton_fan_app/features/control/water_filtration_control.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';

FanDevice _device() => FanDevice()
  ..deviceId = 'test'
  ..macAddress = ''
  ..nickname = 'Test'
  ..model = 'TN-CF-01'
  ..addedAt = DateTime(2026, 1, 1);

// Builds the widget inside a Consumer so we have a real WidgetRef.
Widget _build(Widget Function(ControlBuildParams) builder) =>
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (ctx, ref, _) => builder(
                ControlBuildParams(
                  device: _device(),
                  fanState: FanState(),
                  enabled: true,
                  ref: ref,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  group('AirPurificationControl', () {
    testWidgets('renders FAN SPEED section header', (tester) async {
      await tester.pumpWidget(_build(buildAirPurificationControl));
      await tester.pump();
      expect(find.text('FAN SPEED'), findsOneWidget);
    });

    testWidgets('renders OPERATING MODE section header', (tester) async {
      await tester.pumpWidget(_build(buildAirPurificationControl));
      await tester.pump();
      expect(find.text('OPERATING MODE'), findsOneWidget);
    });

    testWidgets('renders AIR QUALITY section header', (tester) async {
      await tester.pumpWidget(_build(buildAirPurificationControl));
      await tester.pump();
      expect(find.text('AIR QUALITY'), findsOneWidget);
    });

    testWidgets('shows pending notice text', (tester) async {
      await tester.pumpWidget(_build(buildAirPurificationControl));
      await tester.pump();
      expect(
        find.textContaining('command bytes'),
        findsOneWidget,
      );
    });
  });

  group('WaterFiltrationControl', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(_build(buildWaterFiltrationControl));
      await tester.pump();
      expect(find.byType(ApplianceSectionHeader), findsAtLeastNWidgets(1));
    });
  });

  group('EnergyStorageControl', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(_build(buildEnergyStorageControl));
      await tester.pump();
      expect(find.byType(ApplianceSectionHeader), findsAtLeastNWidgets(1));
    });
  });

  group('ApplianceSectionHeader', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ApplianceSectionHeader('MY SECTION'),
          ),
        ),
      );
      expect(find.text('MY SECTION'), findsOneWidget);
    });
  });

  group('PendingMetricCard', () {
    testWidgets('renders metric row labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendingMetricCard(
              rows: [
                PendingMetricRow(icon: Icons.water_drop_outlined, label: 'TDS'),
                PendingMetricRow(
                    icon: Icons.thermostat_outlined, label: 'Temp', unit: '°C'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('TDS'), findsOneWidget);
      expect(find.text('Temp'), findsOneWidget);
    });
  });
}
