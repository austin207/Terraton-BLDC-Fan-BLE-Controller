// lib/features/analytics/analytics_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _range = 'Week';

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

  static const _fanBreakdown = [
    ('Living Room', 12.4, 0.84),
    ('Master Bedroom', 9.1, 0.62),
    ('Study', 6.3, 0.43),
    ('Kitchen', 4.0, 0.27),
  ];

  @override
  Widget build(BuildContext context) {
    final data = _usageData[_range]!;
    final total = data.fold(0.0, (s, d) => s + d.$2);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Header
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(children: [FanIcon(size: 26), SizedBox(width: 10)]),
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
          'Tracking ${_fanBreakdown.length} fans across your home.',
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

        // Consumption card with chart
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('↓ 18% vs last ${_range.toLowerCase()}',
                          style: kMonoStyle(size: 10, color: kYellow, letterSpacing: 1.6, weight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('₹${(total * 5.4).toStringAsFixed(0)} est.',
                          style: kMonoStyle(size: 13, color: kTextMut)),
                    ],
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

        // Two-column stat cards
        Row(
          children: [
            Expanded(
              flex: 6,
              child: _DarkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIconLabel(icon: Icons.eco_outlined, label: 'SAVED', iconColor: kYellow),
                    const SizedBox(height: 10),
                    Text('₹${(total * 0.32 * 5.4).toStringAsFixed(0)}',
                        style: kMonoStyle(size: 24, color: kYellow, weight: FontWeight.w600, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('vs standard ceiling fan',
                        style: GoogleFonts.manrope(fontSize: 11, color: kTextMut)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
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
                        Text('32', style: kMonoStyle(size: 22, weight: FontWeight.w600, letterSpacing: -0.5)),
                        const SizedBox(width: 4),
                        Text('W', style: kMonoStyle(size: 12, color: kTextMut)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('56% lower than typical',
                        style: GoogleFonts.manrope(fontSize: 11, color: kTextMut)),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Efficiency ring
        _DarkCard(
          child: Row(
            children: [
              const _RingChart(pct: 68),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EFFICIENCY',
                        style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.0)),
                    const SizedBox(height: 6),
                    Text('Optimal range',
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
                    const SizedBox(height: 4),
                    Text('Running 32% more efficient than typical BLDC at the same airflow.',
                        style: GoogleFonts.manrope(fontSize: 12, color: kTextMut, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Per-fan breakdown
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('BY FAN',
                style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.2, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        ..._fanBreakdown.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _FanBar(name: f.$1, kwh: f.$2, pct: f.$3),
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

class _LineChart extends StatelessWidget {
  final List<(String, double)> data;
  const _LineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: CustomPaint(painter: _LineChartPainter(data: data)),
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

    // Build smooth path
    final path = Path()..moveTo(xs[0], ys[0]);
    for (int i = 1; i < xs.length; i++) {
      final cx = (xs[i - 1] + xs[i]) / 2;
      path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
    }

    // Fill area
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
    canvas.drawPath(
      path,
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
          Offset(xs[i], ys[i]),
          2.5,
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

class _RingChart extends StatelessWidget {
  final int pct;
  const _RingChart({required this.pct});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: CustomPaint(painter: _RingPainter(pct: pct)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int pct;
  const _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const r = 38.0;
    const sw = 7.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    canvas.drawArc(
      rect, 0, 2 * math.pi, false,
      Paint()
        ..color = const Color(0x0FFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );

    final sweep = 2 * math.pi * pct / 100;
    canvas.drawArc(
      rect, -math.pi / 2, sweep, false,
      Paint()
        ..color = kYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    final pctPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$pct',
            style: kMonoStyle(size: 18, weight: FontWeight.w600),
          ),
          TextSpan(
            text: '%',
            style: kMonoStyle(size: 10, color: kTextMut),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pctPainter.paint(
      canvas,
      Offset(cx - pctPainter.width / 2, cy - pctPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

class _FanBar extends StatelessWidget {
  final String name;
  final double kwh;
  final double pct;
  const _FanBar({required this.name, required this.kwh, required this.pct});

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
          child: const Icon(Icons.air_rounded, size: 16, color: kYellow),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                  Text('$kwh kWh', style: kMonoStyle(size: 11, weight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct,
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
