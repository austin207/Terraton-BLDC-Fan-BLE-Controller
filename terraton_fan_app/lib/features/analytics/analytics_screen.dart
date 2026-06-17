// lib/features/analytics/analytics_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/models/fan_state.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
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
  int _monthRangeN = 1;

  // Power profile per gear step (index = gear, 0 unused).
  static const _kGearWatts    = [0, 4, 7, 10, 15, 21, 28];
  static const _kBoostWatts   = 33;
  static const _kTraditionalW = 85;

  @override
  void initState() {
    super.initState();
    _tariffCtrl = TextEditingController(text: _tariff.toStringAsFixed(1));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_loadTariff()),
    );
  }

  Future<void> _loadTariff() async {
    final saved = await AppSettings.loadTariff(fallback: _tariff);
    if (!mounted) return;
    setState(() {
      _tariff = saved;
      _tariffCtrl.text = saved.toStringAsFixed(1);
    });
  }

  @override
  void dispose() {
    _tariffCtrl.dispose();
    super.dispose();
  }

  static const _monthNames = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];
  static String _monthAbbrev(int month) => _monthNames[month - 1];

  // ── Runtime-based helpers ──────────────────────────────────────────────────

  // Returns the deviceId of the most recently connected fan, or null.
  static String? _mostRecentFanId(List<FanDevice> fans) {
    if (fans.isEmpty) return null;
    final sorted = [...fans]..sort((a, b) {
      final at = a.lastConnectedAt;
      final bt = b.lastConnectedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return sorted.first.deviceId;
  }

  static int _gearWatts(FanState? s) {
    if (s == null) return 0;
    if (s.isBoost) return _kBoostWatts;
    final g = s.speed.clamp(0, 6);
    return g == 0 ? 0 : _kGearWatts[g];
  }

  double _dailyKwhFrom(FanState? s, FanDevice? device) {
    final gw         = _gearWatts(s);
    final runtimeSec = s?.lastRuntimeSecs ?? 0;
    if (gw == 0 || runtimeSec == 0) return 0.0;
    final daysSince = device != null
        ? math.max(1, DateTime.now().difference(device.addedAt).inDays)
        : 1;
    return gw * (runtimeSec / daysSince) / 3_600_000;
  }

  // Returns null when no runtime data or fan is off (gear 0 / no speed).
  static int? _effPct(FanState? s) {
    if (s?.lastRuntimeSecs == null) return null;
    final gw = _gearWatts(s);
    if (gw == 0) return null; // fan stopped — efficiency undefined
    return ((_kTraditionalW - gw) / _kTraditionalW * 100).round().clamp(0, 100);
  }

  static String _effLabel(int? pct) {
    if (pct == null) return 'No Runtime Data';
    if (pct < 70)   return 'Moderate Efficiency';
    if (pct < 88)   return 'High Efficiency';
    return 'Excellent Efficiency';
  }

  double _totalKwh(double dailyKwh) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_range == 'Day')  return dailyKwh;
    if (_range == 'Week') return dailyKwh * 7;
    final start = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
    return dailyKwh * today.difference(start).inDays;
  }

  // One chart point per bucket: Day=6 (4-hour buckets), Week=7 days, Month=nDays.
  List<double> _chartPoints(double dailyKwh) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_range == 'Day')  return List.generate(6, (_) => dailyKwh / 6);
    if (_range == 'Week') return List.generate(7, (_) => dailyKwh);
    final start = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
    final nDays = today.difference(start).inDays;
    if (nDays <= 0) return const [];
    return List.generate(nDays, (_) => dailyKwh);
  }

  // ── Sparse X-axis labels ──────────────────────────────────────────────────

  List<(double, String)> _axisLabels(String range) {
    if (range == 'Day') {
      const labels = ['12AM', '4AM', '8AM', '12PM', '4PM', '8PM'];
      return [for (var i = 0; i < 6; i++) (i / 5, labels[i])];
    }

    if (range == 'Week') {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return [
        for (var i = 0; i < 7; i++)
          (i / 6, names[today.subtract(Duration(days: 6 - i)).weekday - 1]),
      ];
    }

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
    final n     = today.difference(start).inDays;
    if (n <= 1) return n == 1 ? [(0.0, '${start.day}')] : const [];

    if (_monthRangeN >= 2) {
      final out = <(double, String)>[];
      for (var i = 0; i < n; i++) {
        final d = DateTime(start.year, start.month, start.day + i);
        if (d.day == 1) out.add((i / (n - 1), _monthAbbrev(d.month)));
      }
      return out;
    }

    const count = 5;
    return List.generate(count, (k) {
      final i = (k * (n - 1) / (count - 1)).round();
      final d = DateTime(start.year, start.month, start.day + i);
      return (i / (n - 1), '${d.day}');
    });
  }

  String _periodLabel(String range) {
    if (range == 'Month') {
      return _monthRangeN == 1 ? 'this month' : 'last $_monthRangeN months';
    }
    return switch (range) {
      'Day'  => 'today',
      'Week' => 'this week',
      _      => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final userName    = ref.watch(userNameProvider).valueOrNull ?? '';
    final connectedId = ref.watch(connectedFanDeviceIdProvider);
    final allFans     = ref.watch(savedFansProvider).valueOrNull ?? <FanDevice>[];

    final targetId  = connectedId ?? _mostRecentFanId(allFans);
    final fanState  = targetId != null
        ? ref.watch(activeFanStateProvider(targetId)) : null;
    final activeFan = targetId != null
        ? allFans.cast<FanDevice?>().firstWhere(
            (f) => f?.deviceId == targetId, orElse: () => null)
        : null;

    final gearWatts  = _gearWatts(fanState);
    final lastRpm    = fanState?.lastRpm ?? 0;
    final dailyKwh   = _dailyKwhFrom(fanState, activeFan);
    final kwh        = _totalKwh(dailyKwh);
    final cost       = kwh * _tariff;
    final chartPts   = _chartPoints(dailyKwh);
    final effPct     = _effPct(fanState);   // null = no runtime data or fan off
    final axisLabels = _axisLabels(_range);

    final wattDisplay  = gearWatts > 0 ? '$gearWatts' : '—';
    final rpmDisplay   = lastRpm  > 0  ? '$lastRpm'   : '—';
    final perfDisplay  = lastRpm  > 0 && gearWatts > 0
        ? (lastRpm / gearWatts).toStringAsFixed(1) : '—';
    final wattSavePct  = gearWatts > 0
        ? ((_kTraditionalW - gearWatts) / _kTraditionalW * 100).round() : 0;

    return RefreshIndicator(
      onRefresh: _loadTariff,
      color: kYellow,
      backgroundColor: kCard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
        // Header
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: BrandMark(height: 40),
        ),
        Text(
          userName.isNotEmpty ? "$userName's Energy Usage" : "Your Energy Usage",
          style: GoogleFonts.manrope(
            fontSize: 24, fontWeight: FontWeight.w700,
            color: kText, letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ⓘ Energy figures use firmware-reported cumulative runtime and the '
          'active gear\'s power profile. Readings may not reflect activity '
          'while the app was disconnected.',
          style: GoogleFonts.manrope(fontSize: 11, color: kTextMut, height: 1.4),
        ),

        const SizedBox(height: 16),

        // ── Range tabs — sliding yellow pill ──────────────────────────────
        Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kHairline),
          ),
          child: LayoutBuilder(
            builder: (_, constraints) {
              const tabs      = ['Day', 'Week', 'Month'];
              final tabW      = constraints.maxWidth / tabs.length;
              final activeIdx = tabs.indexOf(_range);
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    left: activeIdx * tabW,
                    top: 0, bottom: 0,
                    width: tabW,
                    child: Container(
                      decoration: BoxDecoration(
                        color: kYellow,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: kYellow.withAlpha(89),
                            blurRadius: 16,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(tabs.length, (i) {
                      final on = i == activeIdx;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _range = tabs[i]),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Text(tabs[i],
                                style: GoogleFonts.manrope(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: on ? Colors.black : kTextMut,
                                )),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
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
                          style: kMonoStyle(size: 10, color: kTextMut,
                              letterSpacing: 2.0)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(kwh.toStringAsFixed(3),
                              style: kMonoStyle(size: 36,
                                  weight: FontWeight.w600,
                                  letterSpacing: -0.5)),
                          const SizedBox(width: 6),
                          Text('kWh',
                              style: kMonoStyle(size: 14, color: kTextMut)),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_range == 'Month')
                    _MonthRangeDropdown(
                      value: _monthRangeN,
                      onChanged: (v) => setState(() => _monthRangeN = v),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _LineChart(data: chartPts),
              const SizedBox(height: 8),
              _AxisLabels(labels: axisLabels),
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
                      value: '₹${cost.toStringAsFixed(2)}',
                      valueColor: kYellow,
                      sub: _periodLabel(_range),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStatCard(
                      icon: Icons.bolt_outlined,
                      label: 'UNITS USED',
                      value: '${kwh.toStringAsFixed(3)} U',
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
                  color: kYellowFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kYellowBorder),
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
                              RegExp(r'^\d*\.?\d*$')),
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
                          if (p != null && p >= 0 && p <= 999) {
                            setState(() => _tariff = p);
                            unawaited(AppSettings.saveTariff(p));
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

        const SizedBox(height: 12),

        // ── AVG WATT ──────────────────────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SmallIconLabel(
                  icon: Icons.bolt_outlined, label: 'AVG WATT',
                  iconColor: kYellow),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(wattDisplay,
                      style: kMonoStyle(size: 36, weight: FontWeight.w600,
                          letterSpacing: -0.5)),
                  const SizedBox(width: 6),
                  Text('W', style: kMonoStyle(size: 16, color: kTextMut)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                gearWatts > 0
                    ? '$wattSavePct% lower than a typical ${_kTraditionalW}W fan'
                    : 'Connect to your fan to see power draw',
                style: GoogleFonts.manrope(fontSize: 12, color: kTextMut),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── AVG RPM / Performance ──────────────────────────────────────────
        _DarkCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIconLabel(
                        icon: Icons.rotate_right_outlined,
                        label: 'AVG RPM',
                        iconColor: kYellow),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(rpmDisplay,
                            style: kMonoStyle(size: 36,
                                weight: FontWeight.w600,
                                letterSpacing: -0.5)),
                        const SizedBox(width: 6),
                        Text('RPM',
                            style: kMonoStyle(size: 12, color: kTextMut)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 56, color: kHairline),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIconLabel(
                        icon: Icons.auto_graph_outlined,
                        label: 'PERFORMANCE',
                        iconColor: kYellow),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          perfDisplay,
                          style: kMonoStyle(size: 36,
                              weight: FontWeight.w600,
                              letterSpacing: -0.5),
                        ),
                        const SizedBox(width: 6),
                        Text('RPM/W',
                            style: kMonoStyle(size: 10, color: kTextMut)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Efficiency ring ───────────────────────────────────────────────
        _DarkCard(
          child: Row(
            children: [
              _RingChart(pct: effPct ?? 0),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EFFICIENCY',
                        style: kMonoStyle(size: 10, color: kTextMut,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 6),
                    Text(_effLabel(effPct),
                        style: GoogleFonts.manrope(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: kText)),
                    const SizedBox(height: 4),
                    Text(
                      effPct != null
                          ? 'Your fan consumes $gearWatts W at the current '
                            'gear — $effPct% less energy than a traditional '
                            '${_kTraditionalW}W ceiling fan.'
                          : 'Connect to your fan to see real-time efficiency '
                            'based on firmware-reported runtime.',
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
        ],
      ),
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
  final List<double> data;
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
  final List<double> data;

  // Above this many points, per-point dots become visual noise (daily Month
  // charts have 28–184 points) — draw only the line + the final dot.
  static const _maxDottedPoints = 14;

  // Pre-computed so paint() does not allocate new objects on every frame.
  final bool   _allZero;
  final Paint  _linePaint;
  final Paint  _dotStrokePaint;
  final Paint  _fillPaint;  // shader assigned inside paint() — size unknown here

  _LineChartPainter({required this.data})
      : _allZero = data.every((v) => v == 0),
        _linePaint = Paint()
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        _dotStrokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
        _fillPaint = Paint() {
    final lineColor = data.every((v) => v == 0)
        ? kYellow.withAlpha(60) : kYellow;
    _linePaint.color      = lineColor;
    _dotStrokePaint.color = lineColor;
  }

  // Static paints for values that never change across instances.
  static final _gridPaint = Paint()
    ..color = kGridLine
    ..strokeWidth = 1;
  static final _dotInnerPaint  = Paint()..color = Colors.black;
  static final _lastDotPaint   = Paint()..color = kYellow;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final W = size.width;
    final H = size.height;
    const P = 6.0;

    final maxVal = _allZero ? 1.0 : data.reduce(math.max) * 1.15;
    // Guard against a single-point range: division by (length - 1) would be
    // zero, so collapse to the left edge.
    final denom = data.length > 1 ? data.length - 1 : 1;
    final xs = List.generate(
        data.length, (i) => P + i * (W - P * 2) / denom);
    final ys = data
        .map((v) => H - P - (v / maxVal) * (H - P * 2))
        .toList();

    for (final g in [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(P, H * g), Offset(W - P, H * g), _gridPaint);
    }

    final path = Path()..moveTo(xs[0], ys[0]);
    for (int i = 1; i < xs.length; i++) {
      final cx = (xs[i - 1] + xs[i]) / 2;
      path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
    }

    // Fill — shader rect depends on canvas size so assigned here.
    final areaPath = Path.from(path)
      ..lineTo(xs.last, H)
      ..lineTo(xs.first, H)
      ..close();
    _fillPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [kYellow.withAlpha(_allZero ? 20 : 70), kYellow.withAlpha(0)],
    ).createShader(Rect.fromLTWH(0, 0, W, H));
    canvas.drawPath(areaPath, _fillPaint);

    canvas.drawPath(path, _linePaint);

    // Dots — per-point only for small series; always mark the final point.
    if (data.length <= _maxDottedPoints) {
      for (int i = 0; i < xs.length - 1; i++) {
        canvas.drawCircle(Offset(xs[i], ys[i]), 2.5, _dotInnerPaint);
        canvas.drawCircle(Offset(xs[i], ys[i]), 2.5, _dotStrokePaint);
      }
    }
    canvas.drawCircle(Offset(xs.last, ys.last), 4.5, _lastDotPaint);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => !listEquals(old.data, data);
}

// ── Sparse axis labels ────────────────────────────────────────────────────────

class _AxisLabels extends StatelessWidget {
  // (xFraction 0..1, label) — positioned across the chart width.
  final List<(double, String)> labels;
  const _AxisLabels({required this.labels});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox(height: 12);
    return SizedBox(
      height: 12,
      child: Stack(
        children: [
          for (final (frac, text) in labels)
            Align(
              alignment: Alignment(frac * 2 - 1, 0),
              child: Text(text,
                  style: kMonoStyle(size: 9, color: kTextDim, letterSpacing: 0.6)),
            ),
        ],
      ),
    );
  }
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

  // Pre-laid-out TextPainter and glow paint so neither is allocated in paint().
  final TextPainter _textPainter;
  final Paint        _glowPaint;

  _RingPainter({required this.pct})
      : _textPainter = TextPainter(
          text: TextSpan(children: [
            TextSpan(
                text: pct > 0 ? '$pct' : '--',
                style: kMonoStyle(size: 18, weight: FontWeight.w600)),
            if (pct > 0)
              TextSpan(text: '%', style: kMonoStyle(size: 10, color: kTextMut)),
          ]),
          textDirection: TextDirection.ltr,
        )..layout(),
        _glowPaint = Paint()
          ..color = kYellow.withAlpha((pct * 1.5).round().clamp(20, 160))
          ..style = PaintingStyle.stroke
          ..strokeWidth = _sw + 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

  static const _r  = 38.0;
  static const _sw = 7.0;

  static final _trackPaint = Paint()
    ..color = kHairline
    ..style = PaintingStyle.stroke
    ..strokeWidth = _sw;

  static final _arcPaint = Paint()
    ..color = kYellow
    ..style = PaintingStyle.stroke
    ..strokeWidth = _sw
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final cx   = size.width / 2;
    final cy   = size.height / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: _r);

    canvas.drawArc(rect, 0, 2 * math.pi, false, _trackPaint);

    final sweep = 2 * math.pi * pct / 100;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, _glowPaint);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, _arcPaint);

    _textPainter.paint(canvas,
        Offset(cx - _textPainter.width / 2, cy - _textPainter.height / 2));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ── Month-range dropdown (Month tab only) ────────────────────────────────────

class _MonthRangeDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _MonthRangeDropdown({required this.value, required this.onChanged});

  static String _label(int n) => n == 1 ? '1 Month' : '$n Months';

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: kYellowFill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kYellowBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            style: kMonoStyle(size: 10, color: kYellow, weight: FontWeight.w700)),
        const SizedBox(width: 2),
        const Icon(Icons.expand_more_rounded, size: 14, color: kYellow),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: false,
          alignment: Alignment.centerRight,
          dropdownColor: kCard,
          borderRadius: BorderRadius.circular(12),
          icon: const SizedBox.shrink(),
          selectedItemBuilder: (_) => List.generate(
            6,
            (i) => Align(
              alignment: Alignment.centerRight,
              child: _pill(_label(i + 1)),
            ),
          ),
          items: List.generate(6, (i) => DropdownMenuItem(
            value: i + 1,
            child: Text(_label(i + 1),
                style: kMonoStyle(size: 12, color: kText, weight: FontWeight.w600)),
          )),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}
