// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/features/analytics/analytics_screen.dart';
import 'package:terraton_fan_app/features/home/fans_list_screen.dart';
import 'package:terraton_fan_app/features/settings/settings_screen.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 1; // 0=analytics, 1=home, 2=settings

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: const [
              AnalyticsScreen(),
              _HomeTab(),
              SettingsScreen(),
            ],
          ),
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: _BottomNav(
              active: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home tab ──────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fansAsync = ref.watch(savedFansProvider);
    final fanCount  = fansAsync.when(data: (f) => f.length, loading: () => 0, error: (_, __) => 0);

    final hour   = DateTime.now().hour;
    final greet  = hour < 5 ? 'Sleep well' : hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // Tiny brand mark row
        const SizedBox(height: 8),
        // Brand wordmark header — matches home.jsx BrandMark height=22
        const BrandMark(height: 22),

        // Greeting
        const SizedBox(height: 20),
        Text(
          '$greet,',
          style: GoogleFonts.manrope(
            fontSize: 28, fontWeight: FontWeight.w600,
            color: kText, letterSpacing: -0.5, height: 1.15,
          ),
        ),
        Text(
          'there.',
          style: GoogleFonts.manrope(
            fontSize: 28, fontWeight: FontWeight.w600,
            color: kTextMut, letterSpacing: -0.5, height: 1.15,
          ),
        ),

        const SizedBox(height: 24),

        // Fans tile
        _DeviceTile(
          icon: Icons.air_rounded,
          title: 'Fans',
          subtitle: '$fanCount paired · 0 running',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FansListScreen()),
          ),
        ),

        const SizedBox(height: 14),

        // Usage card (mock)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0x1AFFEC00),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x38FFEC00)),
                ),
                child: const Icon(Icons.bolt_rounded, color: kYellow, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("TODAY'S USAGE",
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: kTextMut, letterSpacing: 2.0,
                        )),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('2.4',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 26, fontWeight: FontWeight.w600,
                              color: kText, letterSpacing: -0.5,
                            )),
                        const SizedBox(width: 6),
                        Text('kWh · ₹13.0',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12, color: kTextMut, letterSpacing: 0.6,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFEC00),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x38FFEC00)),
                ),
                child: Text('↓ 18%',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: kYellow, letterSpacing: 1.2,
                    )),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Device category tile ──────────────────────────────────────────────────────

class _DeviceTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kYellow.withAlpha(_pressed ? 40 : 25),
              kYellow.withAlpha(_pressed ? 10 : 5),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kYellow.withAlpha(76)),
          boxShadow: [
            BoxShadow(
              color: kYellow.withAlpha(_pressed ? 20 : 40),
              blurRadius: 30,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: kYellow.withAlpha(38),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kYellow.withAlpha(76)),
              ),
              child: Icon(widget.icon, size: 28, color: kYellow),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: GoogleFonts.manrope(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: kText, letterSpacing: -0.2,
                      )),
                  const SizedBox(height: 4),
                  Text(widget.subtitle,
                      style: GoogleFonts.manrope(fontSize: 12, color: kTextMut)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kYellow, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Bottom navigation ─────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int active;
  final void Function(int) onChanged;

  const _BottomNav({required this.active, required this.onChanged});

  static const _items = [
    (Icons.bar_chart_rounded, 'Analytics'),
    (Icons.home_rounded, 'Home'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xD9141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kHairlineStrong),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(128), blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: List.generate(_items.length, (i) {
          final on = i == active;
          final (icon, label) = _items[i];
          return Expanded(
            child: Semantics(
              button: true,
              label: label,
              selected: on,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: on ? kYellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: on
                        ? [BoxShadow(color: kYellow.withAlpha(89), blurRadius: 28, spreadRadius: -4)]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 20, color: on ? Colors.black : kTextMut),
                      if (on) ...[
                        const SizedBox(width: 8),
                        Text(label,
                            style: GoogleFonts.manrope(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: Colors.black,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
