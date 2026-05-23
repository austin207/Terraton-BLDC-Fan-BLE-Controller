// analytics.jsx — Analytics dashboard

function AnalyticsScreen({ state, set }) {
  const range = state.analyticsRange || 'Week';
  const setRange = (r) => set({ analyticsRange: r });
  const tariff = state.tariff != null ? state.tariff : 5.4;
  const setTariff = (v) => set({ tariff: v });

  const data = USAGE_DATA[range];
  const total = data.reduce((s, d) => s + d.kwh, 0);
  const cost = total * tariff;
  const savings = total * 0.32 * tariff; // 32% efficiency gain

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflowY: 'auto', paddingBottom: 96 }}>
      {/* Header */}
      <div style={{ padding: '6px 20px 12px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <BrandMark/>
        <div/>
      </div>

      <div style={{ padding: '0 20px 6px' }}>
        <div style={{ fontFamily: T.font, fontSize: 24, fontWeight: 700, color: T.text, letterSpacing: '-0.02em' }}>
          Energy & savings
        </div>
        <div style={{ fontFamily: T.font, fontSize: 13, color: T.textMut, marginTop: 4 }}>
          Tracking 4 fans across your home.
        </div>
      </div>

      {/* Range tabs */}
      <div style={{ padding: '14px 20px 12px', display: 'flex', gap: 6 }}>
        {['Day', 'Week', 'Month'].map(r => (
          <button key={r} onClick={() => setRange(r)} style={{
            flex: 1, height: 36, borderRadius: 12,
            background: r === range ? T.yellow : T.card,
            color: r === range ? '#000' : T.textMut,
            border: `1px solid ${r === range ? T.yellow : T.hairline}`,
            fontFamily: T.font, fontSize: 12, fontWeight: 700, cursor: 'pointer',
            transition: 'all 220ms',
            letterSpacing: '0.04em',
          }}>{r}</button>
        ))}
      </div>

      {/* Big card: consumption */}
      <div style={{ padding: '0 20px 12px' }}>
        <Card style={{ padding: 20 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontFamily: T.fontMono, fontSize: 10, fontWeight: 700, color: T.textMut, letterSpacing: '0.2em' }}>CONSUMED</div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 6 }}>
                <span style={{ fontFamily: T.fontMono, fontSize: 36, fontWeight: 600, color: T.text, letterSpacing: '-0.03em' }}>{total.toFixed(1)}</span>
                <span style={{ fontFamily: T.fontMono, fontSize: 14, color: T.textMut }}>kWh</span>
              </div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{
                fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
                color: T.yellow, letterSpacing: '0.16em',
              }}>↓ 18% vs last {range.toLowerCase()}</div>
              <div style={{ fontFamily: T.fontMono, fontSize: 13, color: T.textMut, marginTop: 6 }}>₹{cost.toFixed(0)} est.</div>
            </div>
          </div>

          {/* Line chart */}
          <div style={{ marginTop: 18 }}>
            <LineChart data={data}/>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, padding: '0 4px' }}>
            {data.map((d, i) => (
              <span key={i} style={{ fontFamily: T.fontMono, fontSize: 9, color: T.textDim, letterSpacing: '0.06em' }}>{d.label}</span>
            ))}
          </div>
        </Card>
      </div>

      {/* Two-column small cards — Saved is wider to fit the tariff input */}
      <div style={{ padding: '0 20px 12px', display: 'grid', gridTemplateColumns: '1.35fr 1fr', gap: 10 }}>
        <Card style={{ padding: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 24, height: 24, borderRadius: 8, background: 'rgba(255,236,0,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon.leaf s={14} c={T.yellow}/>
            </div>
            <div style={{ fontFamily: T.fontMono, fontSize: 9, fontWeight: 700, color: T.textMut, letterSpacing: '0.18em' }}>SAVED</div>
          </div>
          <div style={{ marginTop: 10, fontFamily: T.fontMono, fontSize: 24, fontWeight: 600, color: T.yellow, letterSpacing: '-0.02em' }}>
            ₹{savings.toFixed(0)}
          </div>
          <div style={{ fontFamily: T.font, fontSize: 11, color: T.textMut, marginTop: 2 }}>
            vs standard ceiling fan
          </div>
          {/* Tariff input */}
          <div style={{
            marginTop: 12,
            display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8,
            padding: '8px 10px', borderRadius: 10,
            background: 'rgba(255,236,0,0.05)',
            border: '1px solid rgba(255,236,0,0.18)',
          }}>
            <span style={{
              fontFamily: T.fontMono, fontSize: 9, fontWeight: 700,
              color: T.textMut, letterSpacing: '0.18em',
            }}>TARIFF</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <span style={{ fontFamily: T.fontMono, fontSize: 12, color: T.textMut }}>₹</span>
              <input type="number" step="0.1" min="0"
                value={tariff}
                onChange={(e) => {
                  const v = e.target.value;
                  setTariff(v === '' ? 0 : parseFloat(v));
                }}
                aria-label="Electricity tariff"
                style={{
                  width: 44,
                  background: 'transparent', border: 'none', outline: 'none',
                  fontFamily: T.fontMono, fontSize: 13, fontWeight: 700, color: T.text,
                  padding: 0, textAlign: 'right',
                  appearance: 'textfield',
                  MozAppearance: 'textfield',
                }}/>
              <span style={{ fontFamily: T.fontMono, fontSize: 10, color: T.textMut, marginLeft: 4 }}>/UNIT</span>
            </div>
          </div>
        </Card>
        <Card style={{ padding: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 24, height: 24, borderRadius: 8, background: 'rgba(255,236,0,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon.bolt s={12}/>
            </div>
            <div style={{ fontFamily: T.fontMono, fontSize: 9, fontWeight: 700, color: T.textMut, letterSpacing: '0.18em' }}>AVG WATT</div>
          </div>
          <div style={{ marginTop: 10, fontFamily: T.fontMono, fontSize: 22, fontWeight: 600, color: T.text, letterSpacing: '-0.02em' }}>
            32<span style={{ fontSize: 12, color: T.textMut, marginLeft: 4 }}>W</span>
          </div>
          <div style={{ fontFamily: T.font, fontSize: 11, color: T.textMut, marginTop: 2 }}>
            56% lower than typical
          </div>
        </Card>
      </div>

      {/* Efficiency ring + fan breakdown */}
      <div style={{ padding: '0 20px 12px' }}>
        <Card style={{ padding: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
            <RingChart pct={68}/>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: T.fontMono, fontSize: 10, fontWeight: 700, color: T.textMut, letterSpacing: '0.2em' }}>EFFICIENCY</div>
              <div style={{ fontFamily: T.font, fontSize: 16, fontWeight: 700, color: T.text, marginTop: 6 }}>
                Optimal range
              </div>
              <div style={{ fontFamily: T.font, fontSize: 12, color: T.textMut, marginTop: 4, lineHeight: 1.4 }}>
                Your fans are running 32% more efficient than typical BLDC at the same airflow.
              </div>
            </div>
          </div>
        </Card>
      </div>

      {/* Per-fan breakdown */}
      <div style={{
        padding: '4px 20px 10px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{
          fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
          color: T.textMut, letterSpacing: '0.22em',
        }}>BY FAN</div>
        <button style={{
          background: 'none', border: 'none', cursor: 'pointer',
          fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
          color: T.yellow, letterSpacing: '0.2em',
        }}>DETAILS</button>
      </div>
      <div style={{ padding: '0 20px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        {FAN_BREAKDOWN.map(f => <FanBar key={f.name} fan={f}/>)}
      </div>
    </div>
  );
}

function LineChart({ data }) {
  const W = 332, H = 120, P = 6;
  const max = Math.max(...data.map(d => d.kwh)) * 1.15;
  const xs = data.map((_, i) => P + (i * (W - P*2) / (data.length - 1)));
  const ys = data.map(d => H - P - (d.kwh / max) * (H - P*2));
  // smooth path
  let d = `M ${xs[0]} ${ys[0]}`;
  for (let i = 1; i < xs.length; i++) {
    const cx = (xs[i-1] + xs[i]) / 2;
    d += ` C ${cx} ${ys[i-1]} ${cx} ${ys[i]} ${xs[i]} ${ys[i]}`;
  }
  const area = `${d} L ${xs[xs.length-1]} ${H} L ${xs[0]} ${H} Z`;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} style={{ display: 'block' }}>
      <defs>
        <linearGradient id="aFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#FFEC00" stopOpacity="0.28"/>
          <stop offset="100%" stopColor="#FFEC00" stopOpacity="0"/>
        </linearGradient>
        <filter id="lineGlow"><feGaussianBlur stdDeviation="2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      {/* grid */}
      {[0.25, 0.5, 0.75].map((g, i) => (
        <line key={i} x1={P} x2={W-P} y1={H*g} y2={H*g} stroke="rgba(255,255,255,0.04)" strokeWidth="1"/>
      ))}
      <path d={area} fill="url(#aFill)"/>
      <path d={d} fill="none" stroke={T.yellow} strokeWidth="2" filter="url(#lineGlow)" strokeLinejoin="round" strokeLinecap="round"/>
      {xs.map((x, i) => (
        <g key={i}>
          <circle cx={x} cy={ys[i]} r={i === xs.length - 1 ? 4.5 : 2.2} fill={i === xs.length - 1 ? T.yellow : '#000'} stroke={T.yellow} strokeWidth={i === xs.length - 1 ? 0 : 1.5}/>
        </g>
      ))}
    </svg>
  );
}

function RingChart({ pct }) {
  const R = 38, C = 2 * Math.PI * R;
  const off = C * (1 - pct / 100);
  return (
    <svg width="92" height="92" viewBox="0 0 92 92">
      <defs>
        <filter id="rGlow"><feGaussianBlur stdDeviation="2.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      <circle cx="46" cy="46" r={R} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="7"/>
      <circle cx="46" cy="46" r={R} fill="none" stroke={T.yellow} strokeWidth="7" strokeLinecap="round"
        strokeDasharray={C} strokeDashoffset={off}
        transform="rotate(-90 46 46)"
        filter="url(#rGlow)"/>
      <text x="46" y="48" textAnchor="middle" dominantBaseline="middle"
        fontFamily={T.fontMono} fontSize="18" fontWeight="600" fill={T.text}>{pct}<tspan fontSize="10" fill={T.textMut}>%</tspan></text>
    </svg>
  );
}

function FanBar({ fan }) {
  return (
    <div style={{
      background: T.card, border: `1px solid ${T.hairline}`,
      borderRadius: 14, padding: '12px 14px',
      display: 'flex', alignItems: 'center', gap: 12,
    }}>
      <div style={{ width: 28, height: 28, borderRadius: 8, background: T.cardHi, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon.fan s={16} c={T.yellow}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontFamily: T.font, fontSize: 13, fontWeight: 600, color: T.text }}>{fan.name}</span>
          <span style={{ fontFamily: T.fontMono, fontSize: 11, fontWeight: 600, color: T.text }}>{fan.kwh} kWh</span>
        </div>
        <div style={{
          height: 4, background: 'rgba(255,255,255,0.06)', borderRadius: 2, marginTop: 8, overflow: 'hidden',
        }}>
          <div style={{
            height: '100%', width: `${fan.pct}%`,
            background: T.yellow, borderRadius: 2,
            boxShadow: `0 0 8px ${T.yellowGlow}`,
          }}/>
        </div>
      </div>
    </div>
  );
}

const USAGE_DATA = {
  Day: [
    { label: '12 AM', kwh: 0.4 }, { label: '4 AM', kwh: 0.3 }, { label: '8 AM', kwh: 0.6 },
    { label: '12 PM', kwh: 0.8 }, { label: '4 PM', kwh: 1.2 }, { label: '8 PM', kwh: 1.4 }, { label: 'Now', kwh: 1.0 },
  ],
  Week: [
    { label: 'Mon', kwh: 4.2 }, { label: 'Tue', kwh: 3.8 }, { label: 'Wed', kwh: 5.1 },
    { label: 'Thu', kwh: 4.6 }, { label: 'Fri', kwh: 6.0 }, { label: 'Sat', kwh: 5.4 }, { label: 'Sun', kwh: 4.9 },
  ],
  Month: [
    { label: 'W1', kwh: 28 }, { label: 'W2', kwh: 32 }, { label: 'W3', kwh: 30 }, { label: 'W4', kwh: 34 },
  ],
};
const FAN_BREAKDOWN = [
  { name: 'Living Room', kwh: 12.4, pct: 84 },
  { name: 'Master Bedroom', kwh: 9.1, pct: 62 },
  { name: 'Study', kwh: 6.3, pct: 43 },
  { name: 'Kitchen', kwh: 4.0, pct: 27 },
];

Object.assign(window, { AnalyticsScreen, LineChart, RingChart, FanBar });
