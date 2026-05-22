// lib/features/analytics/analytics_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _range = 'Week';
  double _tariff = 5.4; // ₹ per unit — editable
  late final TextEditingController _tariffCtrl;

  @override
  void initState() {
    super.initState();
    _tariffCtrl = TextEditingController(text: _tariff.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _tariffCtrl.dispose();
    super.dispose();
  }

  // ── Current-period consumption data ─────────────────────────────────────────
  //
  // Day   — 12:00 AM to current time (each bucket = portion of the day)
  // Week  — completed days Mon → (today−1)
  // Month — completed days 1st → (today−1)

  static const _usageData = {
    'Day': [
      ('12AM', 0.4), ('4AM', 0.3), ('8AM', 0.6),
      ('12PM', 0.8), ('4PM', 1.2), ('8PM', 1.4), ('Now', 1.0),
    ],
    'Week': [
      ('Mon', 4.2), ('Tue', 3.8), ('Wed', 5.1),
      ('Thu', 4.6), ('Fri', 6.0), ('Sat', 5.4), ('Sun', 4.9),
    ],
    'Month': [
      ('W1', 28.0), ('W2', 32.0), ('W3', 30.0), ('W4', 34.0),
    ],
  };

  // ── Previous-period data (same window length) ────────────────────────────────
  //
  // Day   — yesterday 12:00 AM → same time as today
  // Week  — same completed days of previous week
  // Month — 1st → (today−1) of previous month

  static const _prevUsageData = {
    'Day': [
      ('12AM', 0.5), ('4AM', 0.4), ('8AM', 0.7),
      ('12PM', 0.9), ('4PM', 1.3), ('8PM', 1.6), ('Now', 1.2),
    ],
    'Week': [
      ('Mon', 4.9), ('Tue', 4.4), ('Wed', 5.7),
      ('Thu', 5.1), ('Fri', 6.6), ('Sat', 6.0), ('Sun', 5.4),
    ],
    'Month': [
      ('W1', 31.0), ('W2', 35.5), ('W3', 33.0), ('W4', 37.5),
    ],
  };

  // ── Per-fan day consumption (12:00 AM → now) ─────────────────────────────────

  static const _fanKwh = [
    ('Living Room Fan',    12.4),
    ('Master Bedroom Fan',  9.1),
    ('Study Room Fan',      6.3),
    ('Kitchen Fan',         4.0),
  ];

  // ── Smart Mode efficiency data ───────────────────────────────────────────────
  //
  // (gear wattage W, hours run) pairs — Smart mode selected different gears.
  // Traditional baseline: a standard 85 W ceiling fan for the same total duration.

  static const _smartGearData = [
    (15.0, 2.0),  // Gear 1
    (20.0, 2.0),  // Gear 2
    (28.0, 2.0),  // Gear 3
    (35.0, 1.0),  // Gear 4
    (42.0, 0.5),  // Gear 5
  ];
  static const _traditionalWatts = 85.0;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  double _total(String range) =>
      _usageData[range]!.fold(0.0, (s, d) => s + d.$2);

  double _prevTotal(String range) =>
      _prevUsageData[range]!.fold(0.0, (s, d) => s + d.$2);

  // Returns arrow glyph, percentage magnitude, and display colour.
  // Green ↓  = lower consumption this period (good).
  // Red   ↑  = higher consumption this period.
  ({String arrow, double pct, Color color}) _comparison(String range) {
    final curr = _total(range);
    final prev = _prevTotal(range);
    if (prev == 0) return (arrow: '—', pct: 0, color: kTextMut);
    final change = (curr - prev) / prev * 100;
    final lower  = change < 0;
    return (
      arrow: lower ? '↓' : '↑',
      pct:   change.abs(),
      color: lower ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
    );
  }

  String _comparisonLabel(String range) => switch (range) {
    'Day'   => 'vs yesterday',
    'Week'  => 'vs last week',
    'Month' => 'vs last month',
    _       => '',
  };

  // Efficiency = (traditional Wh − smart Wh) / traditional Wh × 100
  int get _efficiency {
    final totalH = _smartGearData.fold(0.0, (s, g) => s + g.$2);
    final smartWh = _smartGearData.fold(0.0, (s, g) => s + g.$1 * g.$2);
    final tradWh  = _traditionalWatts * totalH;
    if (tradWh == 0) return 0;
    return ((tradWh - smartWh) / tradWh * 100).round();
  }

  String _efficiencyLabel(int pct) {
    if (pct >= 80) return 'Excellent Efficiency';
    if (pct >= 60) return 'Optimal Range';
    if (pct >= 40) return 'Moderate Efficiency';
    return 'Low Efficiency';
  }

  @override
  Widget build(BuildContext context) {
    final data    = _usageData[_range]!;
    final total   = _total(_range);
    final savings = total * 0.32 * _tariff;
    final cmp     = _comparison(_range);
    final eff     = _efficiency;

    // Bar fractions scale relative to the highest-consuming fan.
    final maxKwh = _fanKwh.map((f) => f.$2).reduce(math.max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Header
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: BrandMark(height: 22),
        ),
        Text(
          'Energy & savings',
          style: GoogleFonts.manrope(
            fontSize: 24, fontWeight: FontWeight.w700,
            color: kText, letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tracking ${_fanKwh.length} fans across your home.',
          style: GoogleFonts.manrope(fontSize: 13, color: kTextMut),
        ),

        const SizedBox(height: 16),

        // Range tabs
        Row(
          children: ['Day', 'Week', 'Month'].map((r) {
            final on = r == _range;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _range = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 36,
                    decoration: BoxDecoration(
                      color: on ? kYellow : kCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: on ? kYellow : kHairline),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      r,
                      style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: on ? Colors.black : kTextMut,
                        letterSpacing: 0.04,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // ── Consumption card ─────────────────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: kWh total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CONSUMED',
                          style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.0)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(total.toStringAsFixed(1),
                              style: kMonoStyle(size: 36, weight: FontWeight.w600, letterSpacing: -0.5)),
                          const SizedBox(width: 6),
                          Text('kWh', style: kMonoStyle(size: 14, color: kTextMut)),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Right: period comparison badge (green ↓ / red ↑)
                  Text(
                    '${cmp.arrow} ${cmp.pct.toStringAsFixed(0)}% ${_comparisonLabel(_range)}',
                    style: kMonoStyle(
                      size: 10, color: cmp.color,
                      letterSpacing: 1.6, weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _LineChart(data: data),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: data.map((d) => Text(d.$1,
                    style: kMonoStyle(size: 9, color: kTextDim, letterSpacing: 0.6))).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Two-column stat cards ────────────────────────────────────────────
        Row(
          children: [
            // SAVED card with editable tariff
            Expanded(
              flex: 6,
              child: _DarkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIconLabel(icon: Icons.eco_outlined, label: 'SAVED', iconColor: kYellow),
                    const SizedBox(height: 10),
                    Text('₹${savings.toStringAsFixed(0)}',
                        style: kMonoStyle(size: 24, color: kYellow, weight: FontWeight.w600, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('vs standard ceiling fan',
                        style: GoogleFonts.manrope(fontSize: 11, color: kTextMut)),
                    const SizedBox(height: 12),
                    // Editable tariff
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFEC00),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x2EFFEC00)),
                      ),
                      child: Row(
                        children: [
                          Text('TARIFF',
                              style: kMonoStyle(size: 9, color: kTextMut, letterSpacing: 1.8,
                                  weight: FontWeight.w700)),
                          const Spacer(),
                          Text('₹', style: kMonoStyle(size: 12, color: kTextMut)),
                          const SizedBox(width: 2),
                          SizedBox(
                            width: 44,
                            child: TextField(
                              controller: _tariffCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              textAlign: TextAlign.right,
                              style: kMonoStyle(size: 13, weight: FontWeight.w700),
                              cursorColor: kYellow,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v);
                                if (parsed != null && parsed >= 0) {
                                  setState(() => _tariff = parsed);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('/UNIT', style: kMonoStyle(size: 10, color: kTextMut)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // AVG WATT card
            Expanded(
              flex: 5,
              child: _DarkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIconLabel(icon: Icons.bolt_outlined, label: 'AVG WATT', iconColor: kYellow),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('28', style: kMonoStyle(size: 22, weight: FontWeight.w600, letterSpacing: -0.5)),
                        const SizedBox(width: 4),
                        Text('W', style: kMonoStyle(size: 12, color: kTextMut)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('65% lower than 85W fan',
                        style: GoogleFonts.manrope(fontSize: 11, color: kTextMut)),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Smart Mode efficiency ring ────────────────────────────────────────
        //
        // Efficiency = (traditional Wh − smart Wh) / traditional Wh × 100
        // Ring glow brightens with efficiency; label and description are dynamic.
        _DarkCard(
          child: Row(
            children: [
              _RingChart(pct: eff),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EFFICIENCY',
                        style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.0)),
                    const SizedBox(height: 6),
                    Text(_efficiencyLabel(eff),
                        style: GoogleFonts.manrope(
                          fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
                    const SizedBox(height: 4),
                    Text(
                      'Your fans are running $eff% more efficiently than a typical ceiling fan at the same airflow.',
                      style: GoogleFonts.manrope(fontSize: 12, color: kTextMut, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── By Fan — day consumption (12:00 AM → now) ────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('BY FAN',
                style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.2, weight: FontWeight.w700)),
            GestureDetector(
              onTap: () {},
              child: Text('DETAILS',
                  style: kMonoStyle(size: 10, color: kYellow, letterSpacing: 2.0, weight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._fanKwh.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _FanBar(name: f.$1, kwh: f.$2, barFraction: f.$2 / maxKwh),
        )),
      ],
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _DarkCard extends StatelessWidget {
  final Widget child;
  const _DarkCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kHairline),
    ),
    child: child,
  );
}

class _SmallIconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  const _SmallIconLabel({required this.icon, required this.label, required this.iconColor});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
      const SizedBox(width: 8),
      Text(label, style: kMonoStyle(size: 9, color: kTextMut, letterSpacing: 1.8, weight: FontWeight.w700)),
    ],
  );
}

// ── Line chart ────────────────────────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  final List<(String, double)> data;
  const _LineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: 100,
        child: CustomPaint(
          size: Size(constraints.maxWidth, 100),
          painter: _LineChartPainter(data: data),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<(String, double)> data;
  const _LineChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final W = size.width;
    final H = size.height;
    const P = 6.0;

    final maxVal = data.map((d) => d.$2).reduce(math.max) * 1.15;
    final xs = List.generate(data.length, (i) => P + i * (W - P * 2) / (data.length - 1));
    final ys = data.map((d) => H - P - (d.$2 / maxVal) * (H - P * 2)).toList();

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1;
    for (final g in [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(P, H * g), Offset(W - P, H * g), gridPaint);
    }

    // Smooth path
    final path = Path()..moveTo(xs[0], ys[0]);
    for (int i = 1; i < xs.length; i++) {
      final cx = (xs[i - 1] + xs[i]) / 2;
      path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
    }

    // Fill area under curve
    final areaPath = Path.from(path)
      ..lineTo(xs.last, H)
      ..lineTo(xs.first, H)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kYellow.withAlpha(70), kYellow.withAlpha(0)],
        ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );

    // Line
    canvas.drawPath(path,
      Paint()
        ..color = kYellow
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots
    for (int i = 0; i < xs.length; i++) {
      final isLast = i == xs.length - 1;
      canvas.drawCircle(
        Offset(xs[i], ys[i]),
        isLast ? 4.5 : 2.5,
        Paint()..color = isLast ? kYellow : Colors.black,
      );
      if (!isLast) {
        canvas.drawCircle(
          Offset(xs[i], ys[i]), 2.5,
          Paint()
            ..color = kYellow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.data != data;
}

// ── Efficiency ring ───────────────────────────────────────────────────────────

class _RingChart extends StatelessWidget {
  final int pct;
  const _RingChart({required this.pct});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92, height: 92,
    child: CustomPaint(painter: _RingPainter(pct: pct)),
  );
}

class _RingPainter extends CustomPainter {
  final int pct;
  const _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const r  = 38.0;
    const sw = 7.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Track ring
    canvas.drawArc(rect, 0, 2 * math.pi, false,
      Paint()
        ..color = const Color(0x0FFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );

    final sweep = 2 * math.pi * pct / 100;

    // Glow — scales with efficiency (brighter at higher %)
    final glowAlpha = (pct * 1.5).round().clamp(20, 160);
    canvas.drawArc(rect, -math.pi / 2, sweep, false,
      Paint()
        ..color = kYellow.withAlpha(glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw + 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Main filled arc
    canvas.drawArc(rect, -math.pi / 2, sweep, false,
      Paint()
        ..color = kYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    // Percentage label
    final painter = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: '$pct', style: kMonoStyle(size: 18, weight: FontWeight.w600)),
        TextSpan(text: '%',    style: kMonoStyle(size: 10, color: kTextMut)),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(cx - painter.width / 2, cy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ── Fan bar ───────────────────────────────────────────────────────────────────

class _FanBar extends StatelessWidget {
  final String name;
  final double kwh;
  final double barFraction; // 0.0–1.0 relative to highest-consuming fan
  const _FanBar({required this.name, required this.kwh, required this.barFraction});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kHairline),
    ),
    child: Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: kCardHi, borderRadius: BorderRadius.circular(8)),
          child: const TerratonFanIcon(size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name,
                      style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                  Text('$kwh kWh', style: kMonoStyle(size: 11, weight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: barFraction,
                  minHeight: 4,
                  backgroundColor: const Color(0x0FFFFFFF),
                  valueColor: const AlwaysStoppedAnimation<Color>(kYellow),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
