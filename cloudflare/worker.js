/**
 * Terraton Usage Data Ingest Worker
 *
 * Receives daily fan usage summaries from the Terraton app and stores them
 * in Cloudflare R2 for model training. All data is anonymous (device_hash only).
 *
 * Environment bindings — configure in the Cloudflare dashboard or wrangler.toml:
 *   UPLOAD_API_KEY  — Bearer token injected into the APK at build time
 *   R2              — R2 bucket binding (bucket: terraton-usage-data)
 *   RATE_LIMIT_KV   — KV namespace for per-IP rate limiting
 *   DEVICE_KV       — KV namespace tracking active device count (no opt-in required)
 */

const MAX_BODY_BYTES    = 10_000; // 10 KB per payload — generous for the schema
const RATE_LIMIT        = 20;     // max uploads per IP per window
const RATE_WINDOW_SECS  = 3_600;  // 1-hour rolling window

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // ── Route guard ──────────────────────────────────────────────────────────
    if (request.method !== 'POST') return reply(404, 'Not found');

    if (url.pathname === '/ping') return handlePing(request, env);
    if (url.pathname === '/upload') return handleUpload(request, env);
    return reply(404, 'Not found');
  },
};

// ── /ping — anonymous device heartbeat (no auth, no opt-in) ──────────────────
//
// Records that a device has the app installed. Called on every app launch.
// KV key:   device:<hash>
// KV value: { first_seen, last_seen, app_version, ping_count }

async function handlePing(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return reply(400, 'Invalid JSON');
  }

  const hash    = body.device_hash;
  const version = typeof body.app_version === 'string' ? body.app_version : 'unknown';

  if (typeof hash !== 'string' || !/^[0-9a-f]{8,64}$/.test(hash)) {
    return reply(400, 'Invalid device_hash');
  }

  const key = `device:${hash}`;
  const now = new Date().toISOString();

  let record = { first_seen: now, last_seen: now, app_version: version, ping_count: 0 };
  const existing = await env.DEVICE_KV.get(key, { type: 'json' });
  if (existing) {
    record = {
      first_seen:  existing.first_seen ?? now,
      last_seen:   now,
      app_version: version,
      ping_count:  (existing.ping_count ?? 0) + 1,
    };
  }

  await env.DEVICE_KV.put(key, JSON.stringify(record));
  return reply(200, 'OK');
}

// ── /upload — daily usage summary (requires Bearer auth + user opt-in) ────────

async function handleUpload(request, env) {

    // ── Bearer token auth ────────────────────────────────────────────────────
    const auth = request.headers.get('Authorization') ?? '';
    if (!env.UPLOAD_API_KEY || auth !== `Bearer ${env.UPLOAD_API_KEY}`) {
      return reply(401, 'Unauthorized');
    }

    // ── IP-based rate limiting (via Workers KV) ──────────────────────────────
    const ip    = request.headers.get('CF-Connecting-IP') ?? 'unknown';
    const kvKey = `rl:${ip}`;
    const prev  = await env.RATE_LIMIT_KV.get(kvKey);
    const count = prev ? parseInt(prev, 10) : 0;

    if (count >= RATE_LIMIT) {
      return reply(429, 'Too many requests');
    }
    // Increment; TTL enforces the rolling window (KV sets it from now each time)
    await env.RATE_LIMIT_KV.put(kvKey, String(count + 1), {
      expirationTtl: RATE_WINDOW_SECS,
    });

    // ── Payload size guard ───────────────────────────────────────────────────
    // Check Content-Length first (fast path) then re-verify on actual body
    const declared = parseInt(request.headers.get('Content-Length') ?? '0', 10);
    if (declared > MAX_BODY_BYTES) return reply(413, 'Payload too large');

    let text;
    try {
      text = await request.text();
    } catch {
      return reply(400, 'Failed to read body');
    }
    if (text.length > MAX_BODY_BYTES) return reply(413, 'Payload too large');

    // ── JSON parse ───────────────────────────────────────────────────────────
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return reply(400, 'Invalid JSON');
    }

    // ── Field validation ─────────────────────────────────────────────────────
    if (!isValid(body)) return reply(400, 'Invalid payload');

    // ── Store in R2 ──────────────────────────────────────────────────────────
    // Key: uploads/<date>/<hash>_<ts>.json — deduplication by timestamp suffix
    const key = `uploads/${body.period}/${body.device_hash}_${Date.now()}.json`;
    try {
      await env.R2.put(key, text, {
        httpMetadata: { contentType: 'application/json' },
      });
    } catch {
      return reply(500, 'Storage error');
    }

    return reply(200, 'OK');
}

/**
 * Validates the UsageSummary payload shape produced by the Flutter app.
 * Checks required fields only — extra fields are ignored and harmless.
 */
function isValid(b) {
  if (typeof b !== 'object' || b === null) return false;

  // Date string YYYY-MM-DD
  if (typeof b.period !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(b.period)) return false;

  // Anonymous device hash — hex string, 8–64 chars (matches SHA-256 truncated to 16)
  if (typeof b.device_hash !== 'string' || !/^[0-9a-f]{8,64}$/.test(b.device_hash)) return false;

  // Gear distribution — exactly 6 finite non-negative numbers
  if (!Array.isArray(b.gear_dist) || b.gear_dist.length !== 6) return false;
  if (!b.gear_dist.every(v => Number.isFinite(v) && v >= 0)) return false;

  // Must have at least one session (finite positive integer)
  if (!Number.isFinite(b.sessions) || b.sessions < 1) return false;

  // kWh must be a finite non-negative number (NaN/Infinity would corrupt training data)
  if (!Number.isFinite(b.total_kwh) || b.total_kwh < 0) return false;

  return true;
}

/** All responses share the same security headers. */
function reply(status, body) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type':              'text/plain',
      'X-Content-Type-Options':    'nosniff',
      'X-Frame-Options':           'DENY',
      'Referrer-Policy':           'no-referrer',
      'Cache-Control':             'no-store',
      'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    },
  });
}
