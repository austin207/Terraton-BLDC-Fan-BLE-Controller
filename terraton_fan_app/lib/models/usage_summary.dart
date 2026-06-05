// lib/models/usage_summary.dart
// Preprocessed daily feature vector — one record per device per day.
// This is what gets uploaded to Cloudflare R2 for model training.
class UsageSummary {
  final String period;           // "2026-05-24"
  final String deviceHash;       // first 16 chars of sha256(deviceId) — anonymous
  final List<double> gearDist;   // 6 values, fraction of runtime at each speed
  final Map<String, double> modeDist; // fraction of runtime per mode
  final List<int> hourlyUsage;   // 24 booleans (0/1) — used in that hour?
  final double avgSessionMins;
  final int sessions;
  final double totalKwh;
  final double avgWatts;
  final double avgRpm;

  // Weather for the day (Open-Meteo, central Kerala coords).
  // -1.0 when the fetch failed — model training pipeline treats as missing.
  final double tempMaxC;
  final double tempMinC;
  final double humidityPct;

  // Tariff context
  final double tariffPerKwh;  // ₹/kWh — user-set in Settings
  final int    ksebSlab;      // KSEB LT domestic slab 1–8 (from fan's 30-day kWh)
  final double monthlyKwhEst; // fan's rolling 30-day kWh total

  UsageSummary({
    required this.period,
    required this.deviceHash,
    required List<double> gearDist,
    required Map<String, double> modeDist,
    required List<int> hourlyUsage,
    required this.avgSessionMins,
    required this.sessions,
    required this.totalKwh,
    required this.avgWatts,
    required this.avgRpm,
    required this.tempMaxC,
    required this.tempMinC,
    required this.humidityPct,
    required this.tariffPerKwh,
    required this.ksebSlab,
    required this.monthlyKwhEst,
  })  : gearDist    = List.unmodifiable(gearDist),
        modeDist    = Map.unmodifiable(modeDist),
        hourlyUsage = List.unmodifiable(hourlyUsage);

  Map<String, dynamic> toJson() => {
    'period':           period,
    'device_hash':      deviceHash,
    'gear_dist':        gearDist,
    'mode_dist':        modeDist,
    'hourly_usage':     hourlyUsage,
    'avg_session_mins': avgSessionMins,
    'sessions':         sessions,
    'total_kwh':        totalKwh,
    'avg_watts':        avgWatts,
    'avg_rpm':          avgRpm,
    'temp_max_c':       tempMaxC,
    'temp_min_c':       tempMinC,
    'humidity_pct':     humidityPct,
    'tariff_per_kwh':   tariffPerKwh,
    'kseb_slab':        ksebSlab,
    'monthly_kwh_est':  monthlyKwhEst,
  };
}
