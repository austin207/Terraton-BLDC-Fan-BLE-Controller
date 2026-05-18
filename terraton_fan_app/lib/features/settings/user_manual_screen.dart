// lib/features/settings/user_manual_screen.dart
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        title: const Text('User Manual', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: const [
          _ManualSection(
            icon: Icons.power_settings_new_rounded,
            iconColor: Color(0xFF3B82F6),
            iconBg: Color(0xFFEFF6FF),
            title: 'Getting Started',
            steps: [
              'Power on your Terraton fan at the wall switch.',
              'Open the app and tap the + button on the home screen.',
              'Choose "Search via Bluetooth" to scan for nearby fans, or "Scan QR Code" if you have the fan packaging.',
              'Select your fan from the list.',
              'Give your fan a nickname (e.g. "Living Room Fan") and tap Save.',
              'Your fan is now paired and ready to control.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.speed_rounded,
            iconColor: Color(0xFF8B5CF6),
            iconBg: Color(0xFFF5F3FF),
            title: 'Controlling Fan Speed',
            steps: [
              'Tap the Power button at the top of the control screen to turn the fan on or off.',
              'Select a speed from 1 (lowest) to 6 (highest) using the speed buttons.',
              'The arc above the buttons shows your current speed — green for low, red for high.',
              'The centre of the arc displays live watts and RPM when connected.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.bolt_rounded,
            iconColor: Color(0xFFFF6600),
            iconBg: Color(0xFFFFF7ED),
            title: 'Boost Mode',
            steps: [
              'Tap "⚡ BOOST MODE" for maximum airflow beyond the standard speed range.',
              'The arc turns orange and the button glows while Boost is active.',
              'Tap "⚡ BOOST MODE" again to return to normal speed control.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.air_rounded,
            iconColor: Color(0xFF06B6D4),
            iconBg: Color(0xFFECFEFF),
            title: 'Operating Modes',
            steps: [
              'Nature — simulates a natural breeze with gentle, variable speed cycles.',
              'Smart — automatically adjusts speed based on ambient temperature for optimal comfort.',
              'Reverse — reverses blade rotation, ideal in winter to push warm air down from the ceiling.',
              'Tap the active mode button again or select another mode to deactivate.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.timer_rounded,
            iconColor: Color(0xFF22C55E),
            iconBg: Color(0xFFF0FDF4),
            title: 'Sleep Timer',
            steps: [
              'Set the fan to turn off automatically after a fixed period.',
              'Choose OFF, 2H (2 hours), 4H (4 hours), or 8H (8 hours).',
              'The active timer duration is highlighted in blue.',
              'Tap OFF at any time to cancel the active timer.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.light_mode_rounded,
            iconColor: Color(0xFFD97706),
            iconBg: Color(0xFFFFFBEB),
            title: 'Mood Lighting',
            steps: [
              'Tap ON to turn the fan\'s built-in light on, or OFF to turn it off.',
              'Drag the WARM ← → COOL slider to adjust the colour temperature.',
              'Warm (orange) suits evening relaxation; Cool (blue) suits daytime task lighting.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.devices_rounded,
            iconColor: Color(0xFF64748B),
            iconBg: Color(0xFFF8FAFC),
            title: 'Managing Your Fans',
            steps: [
              'Tap a fan card on the home screen to open its control panel.',
              'Long-press a fan card to rename it or remove it from the app.',
              'Tap + to pair another fan.',
              'Use Settings > Export / Import to back up and restore your fan list.',
            ],
          ),
          SizedBox(height: 8),
          _ManualSection(
            icon: Icons.help_outline_rounded,
            iconColor: Color(0xFFEF4444),
            iconBg: Color(0xFFFEF2F2),
            title: 'Troubleshooting',
            steps: [
              'Fan not found — make sure the fan is powered on and within range. Tap Refresh to scan again.',
              'Connection lost — tap "Retry Connection" on the control screen. Move closer to the fan if the problem persists.',
              'Bluetooth permissions denied — open your phone Settings, find Terraton Fan Controller, and grant Bluetooth access.',
              'Controls not responding — check the fan is still powered on at the wall switch, then reconnect.',
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final List<String> steps;

  const _ManualSection({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Column(
              children: [
                for (int i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            steps[i],
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
