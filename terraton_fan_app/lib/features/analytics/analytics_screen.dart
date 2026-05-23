// lib/features/analytics/analytics_screen.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/usage_log.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _range = 'Week';
  double _tariff = 5.4;
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

  static const double _traditionalWatts = 85.0;

  // ── Time-window helpers ───────────────────────────────────────────────────

  (DateTime, DateTime) _currentWindow(String range) {
    final now  = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      'Day'   => (today, now),
      'Week'  => (now.subtract(const Duration(days: 7)), now),
      'Month' => (now.subtract(const Duration(days: 30)), now),
      _       => (today, now),
    };
  }

  (DateTime, DateTime) _prevWindow(String range) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      'Day'   => (today.subtract(const Duration(days: 1)),
                  now.subtract(const Duration(days: 1))),
      'Week'  => (now.subtract(const Duration(days: 14)),
                  now.subtract(const Duration(days: 7))),
      'Month' => (now.subtract(const Duration(days: 60)),
                  now.subtract(const Duration(days: 30))),
      _       => (today, now),
    };
  }

  // ── Aggregation helpers ───────────────────────────────────────────────────

  double _sumKwh(List<UsageLog> logs) =>
      logs.fold(0.0, (s, l) => s + l.kwh);

  int _avgWatts(List<UsageLog> logs) {
    final active = logs.where((l) => l.watts > 0 && l.gear > 0).toList();
    if (active.isEmpty) return 0;
    final totalSecs = active.fold(0, (s, l) => s + l.durationSecs);
    if (totalSecs == 0) return 0;
    return (active.fold(0.0, (s, l) => s + l.watts * l.durationSecs) / totalSecs)
        .round();
  }

  int _efficiency(List<UsageLog> logs) {
    final active = logs.where((l) => l.watts > 0 && l.gear > 0).toList();
    if (active.isEmpty) return 0;
    final totalSecs = active.fold(0, (s, l) => s + l.durationSecs);
    if (totalSecs == 0) return 0;
    final terrWh = active.fold(0.0, (s, l) => s + l.watts * l.durationSecs / 3600.0);
    final tradWh = _traditionalWatts * totalSecs / 3600.0;
    return ((tradWh - terrWh) / tradWh * 100).round().clamp(0, 100);
  }

  String _efficiencyLabel(int pct) {
    if (pct >= 80) return 'Excellent Efficiency';
    if (pct >= 60) return 'Optimal Range';
    if (pct >= 40) return 'Moderate Efficiency';
    if (pct > 0)   return 'Low Efficiency';
    return 'No Data Yet';
  }

  // ── Chart bucket builders ─────────────────────────────────────────────────

  List<(String, double)> _chartData(List<UsageLog> logs, String range) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (range == 'Day') {
      // Six 4-hour buckets for today.
      final labels = ['12AM', '4AM', '8AM', '12PM', '4PM', '8PM'];
      return List.generate(6, (i) {
        final from = today.add(Duration(hours: i * 4));
        final to   = today.add(Duration(hours: (i + 1) * 4));
        final kwh  = _sumKwh(logs.where((l) =>
            !l.startTime.isBefore(from) && l.startTime.isBefore(to)).toList());
        return (labels[i], kwh);
      });
    }

    if (range == 'Week') {
      // Last 7 days, each labelled with short day name.
      return List.generate(7, (i) {
        final day  = today.subtract(Duration(days: 6 - i));
        final from = day;
        final to   = day.add(const Duration(days: 1));
        final kwh  = _sumKwh(logs.where((l) =>
            !l.startTime.isBefore(from) && l.startTime.isBefore(to)).toList());
        final label = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
            [day.weekday - 1];
        return (label, kwh);
      });
    }

    // Month — four 7-day weeks.
    return List.generate(4, (i) {
      final from = today.subtract(Duration(days: 28 - i * 7));
      final to   = today.subtract(Duration(days: 21 - i * 7));
      final kwh  = _sumKwh(logs.where((l) =>
          !l.startTime.isBefore(from) && l.startTime.isBefore(to)).toList());
      return ('W${i + 1}', kwh);
    });
  }

  // ── Comparison badge ──────────────────────────────────────────────────────

  ({String arrow, double pct, Color color}) _comparison(
      double curr, double prev) {
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

  String _periodLabel(String range) => switch (range) {
    'Day'   => 'today',
    'Week'  => 'this week',
    'Month' => 'this month',
    _       => '',
  };

  @override
  Widget build(BuildContext context) {
    final repo     = ref.watch(usageLogRepositoryProvider);
    final fansAsync = ref.watch(savedFansProvider);

    final (curFrom, curTo) = _currentWindow(_range);
    final (preFrom, preTo) = _prevWindow(_range);

    final curLogs  = repo.getLogsInRange(curFrom, curTo);
    final prevLogs = repo.getLogsInRange(preFrom, preTo);

    final chartData  = _chartData(curLogs, _range);
    final total      = _sumKwh(curLogs);
    final prevTotal  = _sumKwh(prevLogs);
    final cmp        = _comparison(total, prevTotal);
    final cost       = total * _tariff;
    final avgW       = _avgWatts(curLogs);
    final eff        = _efficiency(curLogs);

    // By-fan: group logs by deviceId, map deviceId → fan name.
    final fanMap = <String, double>{};
    for (final log in curLogs) {
      fanMap[log.deviceId] = (fanMap[log.deviceId] ?? 0) + log.kwh;
    }
    final fanNames = fansAsync.valueOrNull
        ?.asMap()
        .map((_, f) => MapEntry(f.deviceId, f.nickname.isNotEmpty ? f.nickname : f.model)) ??
        {};
    final fanKwh = fanMap.entries
        .map((e) => (fanNames[e.key] ?? e.key, e.value))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final maxFanKwh =
        fanKwh.isEmpty ? 1.0 : fanKwh.map((f) => f.$2).reduce(math.max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Header
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: BrandMark(height: 40),
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
          fanKwh.isEmpty
              ? 'Start using your fans to see usage data.'
              : 'Tracking ${fanKwh.length} fan${fanKwh.length == 1 ? '' : 's'} across your home.',
          style: GoogleFonts.manrope(fontSize: 13, color: kTextMut),
        ),

        const SizedBox(height: 16),

        // ── Range tabs ────────────────────────────────────────────────────
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
                    child: Text(r,
                        style: GoogleFonts.manrope(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: on ? Colors.black : kTextMut,
                        )),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // ── Consumption card ───────────────────────────────────────────────
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
                              style: kMonoStyle(size: 36, weight: FontWeight.w600,
                                  letterSpacing: -0.5)),
                          const SizedBox(width: 6),
                          Text('kWh', style: kMonoStyle(size: 14, color: kTextMut)),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (prevTotal > 0)
                    Text(
                      '${cmp.arrow} ${cmp.pct.toStringAsFixed(0)}% ${_comparisonLabel(_range)}',
                      style: kMonoStyle(size: 10, color: cmp.color,
                          letterSpacing: 1.6, weight: FontWeight.w700),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _LineChart(data: chartData),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: chartData.map((d) => Text(d.$1,
                    style: kMonoStyle(size: 9, color: kTextDim,
                        letterSpacing: 0.6))).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Energy Cost / Units Used / Tariff ─────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MiniStatCard(
                      icon: Icons.currency_rupee,
                      label: 'ENERGY COST',
                      value: '₹${cost.toStringAsFixed(1)}',
                      valueColor: kYellow,
                      sub: _periodLabel(_range),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStatCard(
                      icon: Icons.bolt_outlined,
                      label: 'UNITS USED',
                      value: '${total.toStringAsFixed(1)} U',
                      valueColor: kText,
                      sub: _periodLabel(_range),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Tariff strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFEC00),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x2EFFEC00)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('TARIFF',
                        style: kMonoStyle(size: 9, color: kTextMut,
                            letterSpacing: 1.8, weight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text('₹', style: kMonoStyle(size: 12, color: kTextMut)),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 44,
                      child: TextField(
                        controller: _tariffCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        textAlign: TextAlign.center,
                        style: kMonoStyle(size: 14, weight: FontWeight.w700),
                        cursorColor: kYellow,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final p = double.tryParse(v);
                          if (p != null && p >= 0) setState(() => _tariff = p);
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

        const SizedBox(height: 12),

        // ── AVG WATT ──────────────────────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SmallIconLabel(
                  icon: Icons.bolt_outlined, label: 'AVG WATT', iconColor: kYellow),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(avgW > 0 ? '$avgW' : '--',
                      style: kMonoStyle(size: 36, weight: FontWeight.w600,
                          letterSpacing: -0.5)),
                  const SizedBox(width: 6),
                  Text('W', style: kMonoStyle(size: 16, color: kTextMut)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                avgW > 0
                    ? '${((_traditionalWatts - avgW) / _traditionalWatts * 100).round()}% lower than a typical ${_traditionalWatts.round()}W fan'
                    : 'No usage data yet',
                style: GoogleFonts.manrope(fontSize: 12, color: kTextMut),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Efficiency ring ───────────────────────────────────────────────
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
                        style: kMonoStyle(size: 10, color: kTextMut,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 6),
                    Text(_efficiencyLabel(eff),
                        style: GoogleFonts.manrope(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: kText)),
                    const SizedBox(height: 4),
                    Text(
                      eff > 0
                          ? 'Your fans are running $eff% more efficiently than a typical ceiling fan at the same airflow.'
                          : 'Run your fans to see efficiency data.',
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: kTextMut, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── By Fan ────────────────────────────────────────────────────────
        if (fanKwh.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('BY FAN',
                  style: kMonoStyle(size: 10, color: kTextMut,
                      letterSpacing: 2.2, weight: FontWeight.w700)),
              Text(_periodLabel(_range).toUpperCase(),
                  style: kMonoStyle(size: 10, color: kYellow,
                      letterSpacing: 2.0, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...fanKwh.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FanBar(
              name: f.$1,
              kwh: f.$2,
              barFraction: maxFanKwh > 0 ? f.$2 / maxFanKwh : 0,
            ),
          )),
        ],
      ],
    );
  }
}

// ── Mini stat card ────────────────────────────────────────────────────────────

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String sub;

  const _MiniStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kCardElev,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kHairlineStrong),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: kYellow.withAlpha(30),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 12, color: kYellow),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: kMonoStyle(size: 8, color: kTextMut,
                      letterSpacing: 1.4, weight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(value,
            style: kMonoStyle(size: 20, color: valueColor,
                weight: FontWeight.w600, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(sub, style: GoogleFonts.manrope(fontSize: 10, color: kTextDim)),
      ],
    ),
  );
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
  const _SmallIconLabel(
      {required this.icon, required this.label, required this.iconColor});

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
      Text(label,
          style: kMonoStyle(
              size: 9, color: kTextMut,
              letterSpacing: 1.8, weight: FontWeight.w700)),
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
    final allZero = data.every((d) => d.$2 == 0);

    final W = size.width;
    final H = size.height;
    const P = 6.0;

    final maxVal = allZero ? 1.0 : data.map((d) => d.$2).reduce(math.max) * 1.15;
    final xs = List.generate(
        data.length, (i) => P + i * (W - P * 2) / (data.length - 1));
    final ys = data
        .map((d) => H - P - (d.$2 / maxVal) * (H - P * 2))
        .toList();

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1;
    for (final g in [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(P, H * g), Offset(W - P, H * g), gridPaint);
    }

    final path = Path()..moveTo(xs[0], ys[0]);
    for (int i = 1; i < xs.length; i++) {
      final cx = (xs[i - 1] + xs[i]) / 2;
      path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
    }

    // Fill
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
          colors: [kYellow.withAlpha(allZero ? 20 : 70), kYellow.withAlpha(0)],
        ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = allZero ? kYellow.withAlpha(60) : kYellow
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots
    for (int i = 0; i < xs.length; i++) {
      final isLast = i == xs.length - 1;
      canvas.drawCircle(Offset(xs[i], ys[i]), isLast ? 4.5 : 2.5,
          Paint()..color = isLast ? kYellow : Colors.black);
      if (!isLast) {
        canvas.drawCircle(
          Offset(xs[i], ys[i]),
          2.5,
          Paint()
            ..color = allZero ? kYellow.withAlpha(60) : kYellow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => !listEquals(old.data, data);
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

    canvas.drawArc(rect, 0, 2 * math.pi, false,
      Paint()
        ..color = const Color(0x0FFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw);

    final sweep = 2 * math.pi * pct / 100;
    final glowAlpha = (pct * 1.5).round().clamp(20, 160);

    canvas.drawArc(rect, -math.pi / 2, sweep, false,
      Paint()
        ..color = kYellow.withAlpha(glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw + 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    canvas.drawArc(rect, -math.pi / 2, sweep, false,
      Paint()
        ..color = kYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round);

    final painter = TextPainter(
      text: TextSpan(children: [
        TextSpan(
            text: pct > 0 ? '$pct' : '--',
            style: kMonoStyle(size: 18, weight: FontWeight.w600)),
        if (pct > 0)
          TextSpan(text: '%', style: kMonoStyle(size: 10, color: kTextMut)),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas,
        Offset(cx - painter.width / 2, cy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ── Fan bar ───────────────────────────────────────────────────────────────────

class _FanBar extends StatelessWidget {
  final String name;
  final double kwh;
  final double barFraction;
  const _FanBar(
      {required this.name, required this.kwh, required this.barFraction});

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
          decoration:
              BoxDecoration(color: kCardHi, borderRadius: BorderRadius.circular(8)),
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
                  Flexible(
                    child: Text(name,
                        style: GoogleFonts.manrope(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: kText)),
                  ),
                  Text('${kwh.toStringAsFixed(2)} U',
                      style: kMonoStyle(size: 11, weight: FontWeight.w600)),
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
