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
import 'package:terraton_fan_app/core/storage/usage_log_repository.dart';
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

  // Cached query results and derived aggregations — reloaded on initState
  // and range change only, not on every build(). Avoids both ObjectBox queries
  // and O(n) aggregation loops running on every IndexedStack parent rebuild.
  List<UsageLog>          _curLogs     = const [];
  List<UsageLog>          _prevLogs    = const [];
  List<double>            _chartPoints = const [];        // one value per bucket
  List<(double, String)>  _chartLabels = const [];        // (xFraction 0..1, label)
  double                  _totalKwh    = 0.0;
  double                  _prevKwh     = 0.0;
  int                     _avgWattsV   = 0;
  int                     _avgRpmV     = 0;
  int                     _effPct      = 0;
  Map<String, double>     _fanMap      = const {};
  int                     _monthRangeN = 1; // 1–6 months; Month tab only

  @override
  void initState() {
    super.initState();
    _tariffCtrl = TextEditingController(text: _tariff.toStringAsFixed(1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadData();
      unawaited(_loadTariff());
    });
  }

  Future<void> _loadTariff() async {
    final saved = await AppSettings.loadTariff(fallback: _tariff);
    if (!mounted) return;
    setState(() {
      _tariff = saved;
      _tariffCtrl.text = saved.toStringAsFixed(1);
    });
  }

  void _reloadData() {
    if (!mounted) return;
    final repo = ref.read(usageLogRepositoryProvider);
    final (curFrom, curEndExcl) = _currentWindow(_range);
    final (preFrom, preEndExcl) = _prevWindow(_range);
    setState(() {
      _curLogs     = _queryHalfOpen(repo, curFrom, curEndExcl);
      _prevLogs    = _queryHalfOpen(repo, preFrom, preEndExcl);
      _chartPoints = _chartData(_curLogs, _range);
      _chartLabels = _axisLabels(_range);
      _totalKwh    = _sumKwh(_curLogs);
      _prevKwh     = _sumKwh(_prevLogs);
      _avgWattsV   = _avgWatts(_curLogs);
      _avgRpmV     = _avgRpm(_curLogs);
      _effPct      = _efficiency(_curLogs);
      final map    = <String, double>{};
      for (final l in _curLogs) {
        map[l.deviceId] = (map[l.deviceId] ?? 0) + l.kwh;
      }
      _fanMap = map;
    });
  }

  // Half-open range query: timestamp >= from && timestamp < endExclusive.
  // getLogsInRange is inclusive on both ends, so we subtract 1ms from the
  // exclusive bound — exact for millisecond-precision timestamps. This prevents
  // a log at exactly the boundary (e.g. midnight on the 1st) being counted in
  // both the current and previous period.
  List<UsageLog> _queryHalfOpen(
          UsageLogRepository repo, DateTime from, DateTime endExclusive) =>
      repo.getLogsInRange(
          from, endExclusive.subtract(const Duration(milliseconds: 1)));

  Future<void> _onRefresh() async {
    ref.invalidate(savedFansProvider);
    _reloadData();
    await _loadTariff();
  }

  @override
  void dispose() {
    _tariffCtrl.dispose();
    super.dispose();
  }

  static const double _traditionalWatts = 85.0;

  static const _monthNames = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];
  static String _monthAbbrev(int month) => _monthNames[month - 1];

  // ── Time-window helpers ───────────────────────────────────────────────────
  // All windows are half-open [from, endExclusive). For Month, the range runs
  // from the 1st of the start month up to (not including) today at 00:00, so
  // today's partial usage is excluded — the period ends yesterday.

  (DateTime, DateTime) _currentWindow(String range) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // today at 00:00
    if (range == 'Month') {
      // Start = 1st of the month that is (_monthRangeN - 1) months ago.
      // Dart normalises DateTime(y, 0, 1) → Dec of prior year, so negative
      // month offsets work correctly for January boundaries.
      final start = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
      return (start, today);
    }
    return switch (range) {
      'Day'  => (today, now),
      'Week' => (now.subtract(const Duration(days: 7)), now),
      _      => (today, now),
    };
  }

  (DateTime, DateTime) _prevWindow(String range) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (range == 'Month') {
      // Previous period = the current month-to-date window shifted back N months.
      //   current:  [1st of (month-(N-1)), today)
      //   previous: [1st of (month-(2N-1)), today shifted back N months)
      // e.g. N=2, today=6 Jun → current 1 May–5 Jun, previous 1 Mar–5 Apr.
      final n         = _monthRangeN;
      final prevStart = DateTime(now.year, now.month - (2 * n - 1), 1);
      final prevEnd   = DateTime(now.year, now.month - n, now.day);
      return (prevStart, prevEnd);
    }
    return switch (range) {
      'Day'  => (today.subtract(const Duration(days: 1)),
                 now.subtract(const Duration(days: 1))),
      'Week' => (now.subtract(const Duration(days: 14)),
                 now.subtract(const Duration(days: 7))),
      _      => (today, now),
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

  int _avgRpm(List<UsageLog> logs) {
    final active = logs.where((l) => l.rpm > 0 && l.gear > 0).toList();
    if (active.isEmpty) return 0;
    final totalSecs = active.fold(0, (s, l) => s + l.durationSecs);
    if (totalSecs == 0) return 0;
    return (active.fold(0.0, (s, l) => s + l.rpm * l.durationSecs) / totalSecs)
        .round();
  }

  String _efficiencyLabel(int pct) {
    if (pct >= 80) return 'Excellent Efficiency';
    if (pct >= 60) return 'Optimal Range';
    if (pct >= 40) return 'Moderate Efficiency';
    if (pct > 0)   return 'Low Efficiency';
    return 'No Data Yet';
  }

  // ── Chart data ────────────────────────────────────────────────────────────
  // Returns one kWh value per bucket. Buckets must use the SAME window as the
  // CONSUMED total so the chart reconciles exactly with it. Day = six 4-hour
  // buckets, Week = seven days, Month = one bucket PER DAY across the whole
  // selected range (true daily granularity, up to ~184 points for 6 months).

  List<double> _chartData(List<UsageLog> logs, String range) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (range == 'Day') {
      return List.generate(6, (i) {
        final from = today.add(Duration(hours: i * 4));
        final to   = today.add(Duration(hours: (i + 1) * 4));
        return _sumKwh(logs.where((l) =>
            !l.startTime.isBefore(from) && l.startTime.isBefore(to)).toList());
      });
    }

    if (range == 'Week') {
      return List.generate(7, (i) {
        final day = today.subtract(Duration(days: 6 - i));
        final to  = day.add(const Duration(days: 1));
        return _sumKwh(logs.where((l) =>
            !l.startTime.isBefore(day) && l.startTime.isBefore(to)).toList());
      });
    }

    // Month — one value per calendar day from start (1st of start month) up to
    // but not including today. DateTime(y, m, d + i) gives calendar-correct day
    // boundaries (immune to month-length differences).
    final start   = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
    final nDays   = today.difference(start).inDays;
    return List.generate(nDays, (i) {
      final dayStart = DateTime(start.year, start.month, start.day + i);
      final dayEnd   = DateTime(start.year, start.month, start.day + i + 1);
      return _sumKwh(logs.where((l) =>
          !l.startTime.isBefore(dayStart) && l.startTime.isBefore(dayEnd)).toList());
    });
  }

  // ── Sparse X-axis labels ──────────────────────────────────────────────────
  // Returns (xFraction 0..1, label). Daily Month charts have far too many points
  // to label individually, so labels are thinned: month abbreviations at each
  // calendar-month boundary for multi-month ranges, ~5 evenly spaced day numbers
  // for a single month. Day/Week keep one label per bucket.

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

    // Month — sparse labels over the daily range.
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month - (_monthRangeN - 1), 1);
    final n     = today.difference(start).inDays;
    if (n <= 1) return n == 1 ? [(0.0, '${start.day}')] : const [];

    if (_monthRangeN >= 2) {
      // One label per calendar month, at the first-of-month data point.
      final out = <(double, String)>[];
      for (var i = 0; i < n; i++) {
        final d = DateTime(start.year, start.month, start.day + i);
        if (d.day == 1) out.add((i / (n - 1), _monthAbbrev(d.month)));
      }
      return out;
    }

    // Single month — ~5 evenly spaced day-of-month labels.
    const count = 5;
    return List.generate(count, (k) {
      final i = (k * (n - 1) / (count - 1)).round();
      final d = DateTime(start.year, start.month, start.day + i);
      return (i / (n - 1), '${d.day}');
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
      color: lower ? kCompareGood : kCompareBad,
    );
  }

  String _comparisonLabel(String range) {
    if (range == 'Month') {
      return _monthRangeN == 1
          ? 'vs last month'
          : 'vs previous $_monthRangeN months';
    }
    return switch (range) {
      'Day'  => 'vs yesterday',
      'Week' => 'vs last week',
      _      => '',
    };
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
    final fansAsync = ref.watch(savedFansProvider);

    // All O(n) aggregation is cached in _reloadData(); build() only does O(1) arithmetic.
    final cost = _totalKwh * _tariff;
    final cmp  = _comparison(_totalKwh, _prevKwh);

    // Fan-name lookup comes from the async provider — must stay in build().
    final fanNames = fansAsync.valueOrNull
        ?.asMap()
        .map((_, f) => MapEntry(f.deviceId, f.nickname.isNotEmpty ? f.nickname : f.model)) ??
        {};
    final fanKwh = _fanMap.entries
        .map((e) => (fanNames[e.key] ?? e.key, e.value))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final maxFanKwh =
        fanKwh.isEmpty ? 1.0 : fanKwh.map((f) => f.$2).reduce(math.max);

    return RefreshIndicator(
      onRefresh: _onRefresh,
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

        // ── Range tabs — sliding yellow pill, same pattern as bottom nav ──
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
                          onTap: () {
                            setState(() => _range = tabs[i]);
                            _reloadData();
                          },
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
                          style: kMonoStyle(size: 10, color: kTextMut, letterSpacing: 2.0)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_totalKwh.toStringAsFixed(1),
                              style: kMonoStyle(size: 36, weight: FontWeight.w600,
                                  letterSpacing: -0.5)),
                          const SizedBox(width: 6),
                          Text('kWh', style: kMonoStyle(size: 14, color: kTextMut)),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_range == 'Month')
                        _MonthRangeDropdown(
                          value: _monthRangeN,
                          onChanged: (v) {
                            _monthRangeN = v;
                            _reloadData();
                          },
                        ),
                      if (_prevKwh > 0)
                        Text(
                          '${cmp.arrow} ${cmp.pct.toStringAsFixed(0)}% ${_comparisonLabel(_range)}',
                          style: kMonoStyle(size: 10, color: cmp.color,
                              letterSpacing: 1.6, weight: FontWeight.w700),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _LineChart(data: _chartPoints),
              const SizedBox(height: 8),
              _AxisLabels(labels: _chartLabels),
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
                      value: '${_totalKwh.toStringAsFixed(1)} U',
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
                  icon: Icons.bolt_outlined, label: 'AVG WATT', iconColor: kYellow),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_avgWattsV > 0 ? '$_avgWattsV' : '--',
                      style: kMonoStyle(size: 36, weight: FontWeight.w600,
                          letterSpacing: -0.5)),
                  const SizedBox(width: 6),
                  Text('W', style: kMonoStyle(size: 16, color: kTextMut)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _avgWattsV > 0
                    ? '${((_traditionalWatts - _avgWattsV) / _traditionalWatts * 100).round()}% lower than a typical ${_traditionalWatts.round()}W fan'
                    : 'No usage data yet',
                style: GoogleFonts.manrope(fontSize: 12, color: kTextMut),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── RPM / performance ──────────────────────────────────────────────
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
                        Text(_avgRpmV > 0 ? '$_avgRpmV' : '--',
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
                        // Headline efficiency KPI: ratio of the two aggregates
                        // (avg RPM ÷ avg W), NOT a time-weighted average of
                        // per-segment RPM/W. Intentional — it reads as "airflow
                        // delivered per watt drawn" over the whole period.
                        Text(
                          (_avgRpmV > 0 && _avgWattsV > 0)
                              ? (_avgRpmV / _avgWattsV).toStringAsFixed(1)
                              : '--',
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
              _RingChart(pct: _effPct),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EFFICIENCY',
                        style: kMonoStyle(size: 10, color: kTextMut,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 6),
                    Text(_efficiencyLabel(_effPct),
                        style: GoogleFonts.manrope(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: kText)),
                    const SizedBox(height: 4),
                    Text(
                      _effPct > 0
                          ? 'Your fans are running $_effPct% more efficiently than a typical ceiling fan at the same airflow.'
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
    // Guard against a single-point range (e.g. 1 Month on the 2nd of the month):
    // division by (length - 1) would be zero, so collapse to the left edge.
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

    // Fill — shader rect depends on canvas size so assigned here, not in constructor.
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

    // Line — uses pre-computed _linePaint (color set in constructor).
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
            // Alignment x maps fraction 0..1 → -1..1; edge labels stay flush
            // and interior labels are kept inside the bounds automatically.
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

  // The visible compact pill. Sits centred inside a 48px-tall tap region so the
  // touch target meets the accessibility minimum while the chip stays small.
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
      height: 48, // kMinInteractiveDimension — full-height invisible tap target
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: false,
          alignment: Alignment.centerRight,
          dropdownColor: kCard,
          borderRadius: BorderRadius.circular(12),
          // Arrow lives inside the pill, so hide the built-in trailing icon.
          icon: const SizedBox.shrink(),
          // Closed state shows the compact pill; the 48px box stays tappable.
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
                  backgroundColor: kHairline,
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
