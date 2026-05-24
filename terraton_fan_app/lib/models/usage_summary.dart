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
  };
}
