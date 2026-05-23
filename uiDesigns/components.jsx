// components.jsx — Terraton shared primitives (dark phone shell, brand mark, icons, primitives)

const T = {
  bg: '#000000',
  surface: '#0E0E0E',
  card: '#141414',
  cardElev: '#1A1A1A',
  cardHi: '#222222',
  hairline: 'rgba(255,255,255,0.06)',
  hairlineStrong: 'rgba(255,255,255,0.10)',
  text: '#F4F4F2',
  textMut: '#9A9A95',
  textDim: '#5C5C58',
  yellow: '#FFEC00',
  yellowSoft: '#FFF066',
  yellowDim: '#332C00',
  yellowGlow: 'rgba(255,236,0,0.35)',
  green: '#7AE582',
  red: '#FF6B6B',
  font: '"Manrope", system-ui, -apple-system, "Segoe UI", sans-serif',
  fontMono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
};

// ─────────────────────────────────────────────────────────────
// Phone shell — dark, no chrome interference, 412×892 viewport
// ─────────────────────────────────────────────────────────────
function PhoneShell({ children, width = 412, height = 892, time = '9:30', label }) {
  return (
    <div data-screen-label={label} style={{
      width, height, borderRadius: 44, overflow: 'hidden',
      background: T.bg,
      border: '7px solid #1c1c1c',
      boxShadow: '0 30px 80px rgba(0,0,0,0.45), inset 0 0 0 1px rgba(255,255,255,0.04)',
      display: 'flex', flexDirection: 'column', boxSizing: 'border-box',
      fontFamily: T.font,
      position: 'relative',
      color: T.text,
    }}>
      <StatusBar time={time} />
      <div style={{ flex: 1, overflow: 'hidden', position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      <HomeIndicator />
    </div>
  );
}

function StatusBar({ time = '9:30' }) {
  return (
    <div style={{
      height: 44, padding: '12px 28px 0',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      position: 'relative', flexShrink: 0,
      fontFamily: T.font,
    }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: T.text, letterSpacing: 0.2 }}>{time}</div>
      <div style={{
        position: 'absolute', left: '50%', top: 14, transform: 'translateX(-50%)',
        width: 96, height: 28, borderRadius: 100, background: '#000',
      }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: T.text }}>
        {/* bluetooth */}
        <svg width="12" height="14" viewBox="0 0 12 14" fill="none"><path d="M3 1l6 4.5L6 8l3 2.5L3 13V8m0 0V1l6 4.5L3 8z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round"/></svg>
        {/* signal */}
        <svg width="16" height="11" viewBox="0 0 16 11" fill="currentColor"><rect x="0" y="8" width="3" height="3" rx="0.5"/><rect x="4" y="6" width="3" height="5" rx="0.5"/><rect x="8" y="3" width="3" height="8" rx="0.5"/><rect x="12" y="0" width="3" height="11" rx="0.5"/></svg>
        {/* battery */}
        <div style={{ width: 24, height: 12, borderRadius: 3, border: `1.2px solid ${T.text}`, padding: 1.5, position: 'relative' }}>
          <div style={{ width: '78%', height: '100%', background: T.text, borderRadius: 1 }} />
          <div style={{ position: 'absolute', right: -3, top: 3, width: 2, height: 4, background: T.text, borderRadius: 1 }} />
        </div>
      </div>
    </div>
  );
}

function HomeIndicator() {
  return (
    <div style={{ height: 28, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingBottom: 8, flexShrink: 0 }}>
      <div style={{ width: 134, height: 5, borderRadius: 3, background: '#3a3a3a' }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Brand mark — Terraton logo PNG, original (trademarked) colours.
// Do NOT recolour. The source files have lots of transparent
// padding so we render them via background-image with a manual
// crop window keyed to each source.
//   terraton-mark.png : 1684×2528, logo at ~(505,683) size 673×708
//   terraton-full.png : 2220×1920, logo at ~(533,710) size 1354×403
// `full=true` → icon + wordmark.  `full=false` → icon only.
// ─────────────────────────────────────────────────────────────
const LOGO_CROP = {
  mark: { src: 'assets/terraton-mark.png', W: 408, H: 612, x: 120, y: 207, w: 168, h: 187 },
  full: { src: 'assets/terraton-full.png', W: 537, H: 464, x: 123, y: 204, w: 299, h: 69 },
};

function BrandMark({ height = 22, full = true, glow = false }) {
  const c = full ? LOGO_CROP.full : LOGO_CROP.mark;
  const ratio = c.w / c.h;
  const dispH = height;
  const dispW = Math.round(dispH * ratio);
  const bgW = (dispW / c.w) * c.W;
  const bgH = (dispH / c.h) * c.H;
  const bgX = -(dispW / c.w) * c.x;
  const bgY = -(dispH / c.h) * c.y;
  return (
    <div role="img" aria-label="Terraton" style={{
      width: dispW, height: dispH, flexShrink: 0,
      backgroundImage: `url("${c.src}")`,
      backgroundSize: `${bgW}px ${bgH}px`,
      backgroundPosition: `${bgX}px ${bgY}px`,
      backgroundRepeat: 'no-repeat',
      filter: glow
        ? 'drop-shadow(0 0 14px rgba(255,230,0,0.55)) drop-shadow(0 0 30px rgba(255,230,0,0.30))'
        : 'drop-shadow(0 1px 6px rgba(255,236,0,0.18)) saturate(1.15)',
    }}/>
  );
}
// Back-compat alias — `BrandMarkColored` is the same as `BrandMark`.
const BrandMarkColored = BrandMark;

// Simple top-header used on push screens (back arrow + centered title)
function ScreenHeader({ title, onBack, trailing }) {
  return (
    <div style={{
      padding: '6px 20px 16px',
      display: 'flex', alignItems: 'center', gap: 12,
      position: 'relative',
    }}>
      {onBack ? (
        <button onClick={onBack} style={{
          ...iconBtnLite, background: 'transparent', border: 'none',
        }}>
          <Icon.back/>
        </button>
      ) : <div style={{ width: 40 }}/>}
      <div style={{
        position: 'absolute', left: 0, right: 0, textAlign: 'center',
        fontFamily: T.font, fontSize: 22, fontWeight: 700, color: T.text,
        pointerEvents: 'none', letterSpacing: '-0.01em',
      }}>{title}</div>
      <div style={{ flex: 1 }}/>
      <div style={{ display: 'flex', gap: 8 }}>{trailing}</div>
    </div>
  );
}

const iconBtnLite = {
  width: 40, height: 40, borderRadius: 12,
  background: 'transparent', border: 'none', color: T.text,
  display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
};

// ─────────────────────────────────────────────────────────────
// Bottom nav — Analytics / Home / Settings
// ─────────────────────────────────────────────────────────────
function BottomNav({ active, onChange }) {
  const items = [
    { id: 'analytics', label: 'Analytics', icon: NavIcon.analytics },
    { id: 'home', label: 'Home', icon: NavIcon.home },
    { id: 'settings', label: 'Settings', icon: NavIcon.settings },
  ];
  return (
    <div style={{
      position: 'absolute', left: 16, right: 16, bottom: 16,
      background: 'rgba(20,20,20,0.85)',
      backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
      border: `1px solid ${T.hairlineStrong}`,
      borderRadius: 28,
      padding: 6,
      display: 'flex', gap: 4,
      boxShadow: '0 16px 40px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.04)',
      zIndex: 10,
    }}>
      {items.map(it => {
        const on = active === it.id;
        return (
          <button key={it.id}
            onClick={() => onChange && onChange(it.id)}
            style={{
              flex: 1, height: 52, border: 'none', cursor: 'pointer',
              background: on ? T.yellow : 'transparent',
              color: on ? '#000' : T.textMut,
              borderRadius: 22,
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              fontFamily: T.font, fontSize: 13, fontWeight: 600,
              transition: 'all 280ms cubic-bezier(.2,.7,.2,1)',
              boxShadow: on ? `0 0 28px ${T.yellowGlow}` : 'none',
            }}>
            <it.icon active={on} />
            {on && <span>{it.label}</span>}
          </button>
        );
      })}
    </div>
  );
}

const NavIcon = {
  analytics: ({ active }) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
      <path d="M4 20V10M10 20V4M16 20V14M22 20H2" stroke={active ? '#000' : 'currentColor'} strokeWidth="1.8" strokeLinecap="round"/>
    </svg>
  ),
  home: ({ active }) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
      <path d="M3 11l9-8 9 8v9a2 2 0 0 1-2 2h-4v-7h-6v7H5a2 2 0 0 1-2-2z" stroke={active ? '#000' : 'currentColor'} strokeWidth="1.7" strokeLinejoin="round"/>
    </svg>
  ),
  settings: ({ active }) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="3" stroke={active ? '#000' : 'currentColor'} strokeWidth="1.7"/>
      <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-1.11-1.56 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 1 1 0-4h.09a1.7 1.7 0 0 0 1.56-1.11 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34h.08a1.7 1.7 0 0 0 1.03-1.56V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1.03 1.56 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87v.08a1.7 1.7 0 0 0 1.56 1.03H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1.03z" stroke={active ? '#000' : 'currentColor'} strokeWidth="1.7" strokeLinejoin="round"/>
    </svg>
  ),
};

// ─────────────────────────────────────────────────────────────
// Generic icons
// ─────────────────────────────────────────────────────────────
const Icon = {
  bolt: ({ s = 18, c = T.yellow }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill={c}><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8z"/></svg>
  ),
  power: ({ s = 22, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none">
      <path d="M12 2v10" stroke={c} strokeWidth="2" strokeLinecap="round"/>
      <path d="M18.4 6.6a9 9 0 1 1-12.8 0" stroke={c} strokeWidth="2" strokeLinecap="round"/>
    </svg>
  ),
  bluetooth: ({ s = 14, c = T.yellow }) => (
    <svg width={s} height={s} viewBox="0 0 14 16" fill="none"><path d="M3 1l6 4.5L6 8l3 2.5L3 13V8m0 0V1l6 4.5L3 8z" stroke={c} strokeWidth="1.4" strokeLinejoin="round"/></svg>
  ),
  qr: ({ s = 18, c = T.yellow }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.6">
      <rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>
      <path d="M14 14h3v3M20 14v3M14 20h3M17 17h4M21 21v-1"/>
    </svg>
  ),
  plus: ({ s = 22, c = '#000' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke={c} strokeWidth="2.4" strokeLinecap="round"/></svg>
  ),
  chev: ({ s = 16, c = T.textMut, dir = 'right' }) => {
    const rot = { right: 0, left: 180, down: 90, up: -90 }[dir];
    return <svg width={s} height={s} viewBox="0 0 24 24" fill="none" style={{ transform: `rotate(${rot}deg)` }}><path d="M9 6l6 6-6 6" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>;
  },
  back: ({ s = 22, c = T.text }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M15 6l-6 6 6 6" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  gear: ({ s = 22, c = T.text }) => NavIcon.settings({ active: false }),
  fan: ({ s = 24, c = T.yellow }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="2" fill={c}/>
      <path d="M12 10c-3-1-6-3-6-5 0-1.5 1.5-3 3-3 2 0 3.5 2 3 5M14 12c1-3 3-6 5-6 1.5 0 3 1.5 3 3 0 2-2 3.5-5 3M12 14c3 1 6 3 6 5 0 1.5-1.5 3-3 3-2 0-3.5-2-3-5M10 12c-1 3-3 6-5 6-1.5 0-3-1.5-3-3 0-2 2-3.5 5-3"
        stroke={c} strokeWidth="1.4" strokeLinejoin="round" fill="rgba(255,236,0,0.08)"/>
    </svg>
  ),
  leaf: ({ s = 16, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M20 4S10 4 6 8s-4 12 0 12 8-4 8-4M6 18s2-8 14-14" stroke={c} strokeWidth="1.5" strokeLinecap="round"/></svg>
  ),
  spark: ({ s = 16, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z" stroke={c} strokeWidth="1.4" strokeLinejoin="round"/></svg>
  ),
  reverse: ({ s = 16, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M3 12a9 9 0 0 1 15.5-6.3M21 4v5h-5M21 12a9 9 0 0 1-15.5 6.3M3 20v-5h5" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  moon: ({ s = 16, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M21 13A9 9 0 1 1 11 3a7 7 0 0 0 10 10z" stroke={c} strokeWidth="1.5" strokeLinejoin="round"/></svg>
  ),
  bulb: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M9 18h6m-5 3h4M12 3a6 6 0 0 0-4 10.5c.7.6 1 1.5 1 2.5h6c0-1 .3-1.9 1-2.5A6 6 0 0 0 12 3z" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  pencil: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M14 4l6 6L9 21H3v-6L14 4z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/></svg>
  ),
  trash: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M4 7h16M9 7V4h6v3m-7 0v13a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2V7" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  x: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M6 6l12 12M18 6L6 18" stroke={c} strokeWidth="2" strokeLinecap="round"/></svg>
  ),
  check: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M5 12l5 5L20 7" stroke={c} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  alert: ({ s = 18, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3l10 18H2L12 3z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/><path d="M12 10v5M12 18v.5" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>
  ),

  flame: ({ s = 16, c = 'currentColor' }) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 22c4 0 7-3 7-7 0-3-2-5-3-7-1 2-2 3-4 3 0-3-1-5-3-7-1 4-5 6-5 11 0 4 3 7 8 7z" stroke={c} strokeWidth="1.5" strokeLinejoin="round"/></svg>
  ),
  signal: ({ s = 14, c = T.yellow, bars = 3 }) => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      {[0,1,2,3].map(i => (
        <rect key={i} x={1 + i*3} y={10 - i*2.5} width="2" height={2 + i*2.5} rx="0.5"
          fill={i < bars ? c : 'rgba(255,255,255,0.15)'}/>
      ))}
    </svg>
  ),
  battery: ({ s = 16, c = T.textMut, pct = 70 }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      <div style={{ width: 22, height: 11, borderRadius: 2.5, border: `1.1px solid ${c}`, padding: 1.2, position: 'relative' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: pct > 25 ? c : T.red, borderRadius: 1 }} />
        <div style={{ position: 'absolute', right: -3, top: 3, width: 2, height: 3, background: c, borderRadius: 1 }} />
      </div>
    </div>
  ),
};

// ─────────────────────────────────────────────────────────────
// Reusable card
// ─────────────────────────────────────────────────────────────
function Card({ children, style, onClick, active }) {
  return (
    <div onClick={onClick} style={{
      background: active ? 'rgba(255,236,0,0.06)' : T.card,
      border: `1px solid ${active ? 'rgba(255,236,0,0.4)' : T.hairline}`,
      borderRadius: 20,
      padding: 18,
      cursor: onClick ? 'pointer' : 'default',
      transition: 'all 240ms cubic-bezier(.2,.7,.2,1)',
      ...style,
    }}>{children}</div>
  );
}

// Connection dot with idle pulse
function ConnDot({ state = 'connected' }) {
  // states: connected | connecting | offline
  const color = state === 'connected' ? T.yellow : state === 'connecting' ? T.yellow : '#555';
  return (
    <span style={{
      width: 8, height: 8, borderRadius: '50%',
      background: color,
      boxShadow: state === 'connected' ? `0 0 10px ${T.yellowGlow}` : 'none',
      animation: state === 'connecting' ? 'tn-pulse 1.2s infinite' : 'none',
      display: 'inline-block', flexShrink: 0,
    }} />
  );
}

Object.assign(window, {
  T, PhoneShell, StatusBar, HomeIndicator,
  BrandMark, BrandMarkColored, LOGO_CROP, ScreenHeader, iconBtnLite,
  BottomNav, NavIcon, Icon, Card, ConnDot,
});
