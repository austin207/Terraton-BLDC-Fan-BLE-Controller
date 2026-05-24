// lib/features/settings/user_manual_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/theme.dart';

// ── Section data ──────────────────────────────────────────────────────────────

class _SectionData {
  final String id;
  final String label;
  final IconData icon;
  final Color accent;
  final List<String> body;
  const _SectionData({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
    required this.body,
  });
}

const _sections = [
  _SectionData(
    id: 'getting-started',
    label: 'Getting Started',
    icon: Icons.power_settings_new_rounded,
    accent: Color(0xFF7AA7FF),
    body: [
      'Power on your Terraton fan from the wall switch — the indicator LED will pulse yellow.',
      'On first launch, open the Terraton app and tap the Fans tile on the Home screen.',
      'Tap + to pair a new fan via Bluetooth or QR code.',
      'Once paired, your fan appears in the list and is ready to control.',
    ],
  ),
  _SectionData(
    id: 'speed',
    label: 'Controlling Fan Speed',
    icon: Icons.speed_rounded,
    accent: Color(0xFFB68BFF),
    body: [
      'Open any fan from the list to view its control screen.',
      'Tap a dot on the radial ring to set speed from 1 to 6.',
      'The active speed glows yellow; RPM and watt draw update in real time at the center.',
      'Tap the lightning bolt to engage Boost for maximum airflow.',
    ],
  ),
  _SectionData(
    id: 'boost',
    label: 'Boost Mode',
    icon: Icons.bolt_rounded,
    accent: Color(0xFFFFB400),
    body: [
      'Tap BOOST to instantly push the fan to its maximum airflow.',
      'The dial visualizes Boost with an intensified glow ring.',
      'Boost ends when you toggle it off, set a different speed, or power the fan off.',
      'Use Boost briefly — sustained max speed increases power draw and wear.',
    ],
  ),
  _SectionData(
    id: 'modes',
    label: 'Operating Modes',
    icon: Icons.air_rounded,
    accent: Color(0xFF7AE582),
    body: [
      'Nature: gently varies speed to mimic natural breeze patterns.',
      'Smart: learns your usage and adjusts speed based on time-of-day.',
      'Reverse: spins the blades in the opposite direction for winter circulation.',
      'Only one mode can be active at a time. Tap the active mode again to turn it off.',
    ],
  ),
  _SectionData(
    id: 'timer',
    label: 'Sleep Timer',
    icon: Icons.timer_rounded,
    accent: Color(0xFF7AE582),
    body: [
      'Set a 2H, 4H, or 8H timer to automatically power the fan off.',
      'The remaining time appears beside the SLEEP TIMER label.',
      'Tap OFF to clear the timer at any time.',
      'Timer settings persist per-fan, so each fan can have its own schedule.',
    ],
  ),
  _SectionData(
    id: 'lighting',
    label: 'Mood Lighting',
    icon: Icons.light_mode_rounded,
    accent: Color(0xFFFFEC00),
    body: [
      'Toggle the light ON/OFF using the switch in the MOOD LIGHTING section.',
      'Choose Warm, Neutral, or Cool colour temperature to match your mood.',
      'Drag the intensity slider to dim or brighten the integrated downlight.',
      'Set intensity to 0 to fully turn the downlight off without affecting fan speed.',
    ],
  ),
  _SectionData(
    id: 'managing',
    label: 'Managing Your Fans',
    icon: Icons.devices_rounded,
    accent: Color(0xFF9A9A95),
    body: [
      'Long-press any fan card to open the action sheet.',
      'Tap Rename Fan to give it a friendlier name (e.g. "Bedroom Fan").',
      'Tap Remove Device to unpair the fan from your account.',
      'Use Export Fans Data in Settings to back up your setup.',
    ],
  ),
  _SectionData(
    id: 'ai-training',
    label: 'AI Training & Data Sharing',
    icon: Icons.auto_graph_rounded,
    accent: Color(0xFFFFEC00),
    body: [
      'The app collects anonymous usage patterns to train an on-device AI model that suggests energy-saving settings tailored to your habits.',
      'Data collected includes: speed used, mode selected, hours of operation, and estimated watt draw — never your name, location, or device ID.',
      'Your device ID is converted into a one-way hash before any data leaves the app, making it impossible to trace back to you.',
      'Uploads happen automatically on Wi-Fi only, once per day, covering the previous day\'s completed sessions.',
      'The trained model will be embedded in a future update to provide personalised efficiency recommendations directly in the Analytics screen.',
      'You can opt out at any time in Settings → AI Training. Turning it off stops all future uploads; no data already sent can be recalled.',
    ],
  ),
  _SectionData(
    id: 'troubleshooting',
    label: 'Troubleshooting',
    icon: Icons.help_outline_rounded,
    accent: Color(0xFFFF6B6B),
    body: [
      'Fan not responding? Make sure Bluetooth is enabled and you\'re within ~10 m.',
      'If a fan shows Disconnected, tap Reconnect in the popup, or cycle the wall switch.',
      'Bluetooth permissions denied? Open your phone Settings and grant Bluetooth access.',
      'Still stuck? Reach out through the contact options in your device packaging.',
    ],
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class UserManualScreen extends ConsumerStatefulWidget {
  const UserManualScreen({super.key});

  @override
  ConsumerState<UserManualScreen> createState() => _UserManualScreenState();
}

class _UserManualScreenState extends ConsumerState<UserManualScreen> {
  String? _openId;

  void _toggle(String id) => setState(() => _openId = _openId == id ? null : id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('User Manual',
            style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: BrandMark(height: 40),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                ..._sections.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ManualSection(
              section: s,
              open: _openId == s.id,
              onToggle: () => _toggle(s.id),
            ),
          )),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Center(
                    child: Text(
                        'END OF MANUAL · v${ref.watch(packageInfoProvider).valueOrNull?.version ?? '—'}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: kTextDim, letterSpacing: 2.0,
                        )),
                  ),
                ),
              ],          // closes ListView children
            ),            // closes ListView
          ),              // closes Expanded
        ],                // closes Column children
      ),                  // closes Column (body)
    );
  }
}

// ── Accordion section ─────────────────────────────────────────────────────────

class _ManualSection extends StatefulWidget {
  final _SectionData section;
  final bool open;
  final VoidCallback onToggle;

  const _ManualSection({
    required this.section,
    required this.open,
    required this.onToggle,
  });

  @override
  State<_ManualSection> createState() => _ManualSectionState();
}

class _ManualSectionState extends State<_ManualSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.open ? 1.0 : 0.0,
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(_ManualSection old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) {
      widget.open ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.open ? kYellow.withAlpha(56) : kHairline,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: s.accent.withAlpha(34),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(s.icon, size: 20, color: s.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(s.label,
                        style: GoogleFonts.manrope(
                          fontSize: 15, fontWeight: FontWeight.w700, color: kText,
                        )),
                  ),
                  AnimatedRotation(
                    turns: widget.open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: widget.open ? kYellow : kTextMut,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable body
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(70, 0, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: s.body.map((line) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 8, right: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.accent,
                        ),
                      ),
                      Expanded(
                        child: Text(line,
                            style: GoogleFonts.manrope(
                              fontSize: 13, color: kTextMut, height: 1.6,
                            )),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
