// fan-control.jsx — Fan Control: power above dial, BT icon top-right,
// Boost moved into Operating Modes, thinner dial w/ 7 speed buttons
// (7th = lightning), Color Temperature section, light intensity slider,
// sleep timer, disconnect alert.

const ARC_START = 135;
const ARC_END = 405;

function polar(cx, cy, r, angDeg) {
  const a = (angDeg - 90) * Math.PI / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}
function arcPath(cx, cy, r, startDeg, endDeg) {
  const [x1, y1] = polar(cx, cy, r, startDeg);
  const [x2, y2] = polar(cx, cy, r, endDeg);
  const large = (endDeg - startDeg) <= 180 ? 0 : 1;
  return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2}`;
}

// ─────────────────────────────────────────────────────────────
// Dial — thin ring with a circular indicator dot sitting ON the ring
// at each of 7 evenly-spaced positions (1..6 + Boost). The dot is the
// selectable control; the numeric/lightning label outside the ring is
// static text. Tapping the dot at index N illuminates dots 1..N plus
// the arc segment between them. Boost lights every dot and closes the
// ring into a full glowing circle.
// Position 1 sits at 12 o'clock; 2..6 sweep clockwise; the Boost
// lightning is the last step, just left of 12 o'clock.
// ─────────────────────────────────────────────────────────────
function RadialDial({ speed, power, boost, onChange, onBoostToggle }) {
  const SIZE = 344;
  const cx = SIZE / 2;
  const cy = SIZE / 2;
  const r = 116;             // ring radius (bumped so RPM/WATTS sit inside)
  const POS = 7;             // 7 indicators (1..6 + lightning)
  const STEP = 360 / POS;    // ≈ 51.43° per step
  const ringRef = React.useRef(null);

  const angAt = (i) => i * STEP;

  const rpm = power && speed > 0 ? speed * 220 + 80 + (boost ? 200 : 0) : 0;
  const watts = power && speed > 0 ? Math.round(6 + speed * 8.2 + (boost ? 12 : 0)) : 0;

  const tap = (i) => {
    if (!power) return;
    if (i === 6) {
      onBoostToggle && onBoostToggle();
    } else {
      onChange && onChange(i + 1);
    }
  };

  // Geometry for ticks, indicators (on-ring) and labels (outside)
  const TICK_OUT = r - 10;    // stop short of the indicator dot so the
                              // tick never bleeds into the dot's interior
  const TICK_IN  = r - 18;
  const DOT_D    = 14;       // visible indicator dot diameter (on the ring)
  const HIT_D    = 34;       // invisible touch target around each dot
  const LABEL_R  = r + 30;   // static numeric/lightning labels — outside the ring
  const LABEL_D  = 30;       // label box size

  // An indicator's visual state:
  //   'selected' — the currently-tapped dot (bright yellow + glow)
  //   'progress' — lit because it's between dot 1 and the selected one
  //                (slightly dull yellow, no glow, matches the arc)
  //   'off'      — inactive grey
  // Boost lights every dot as 'selected' (full-glow ring) per spec.
  const stateOf = (i) => {
    if (!power) return 'off';
    if (boost) return 'selected';
    if (speed <= 0) return 'off';
    if (i === speed - 1) return 'selected';
    if (i < speed - 1) return 'progress';
    return 'off';
  };
  const isLit = (i) => stateOf(i) !== 'off';

  return (
    <div ref={ringRef}
      style={{
        width: SIZE, height: SIZE, margin: '0 auto', position: 'relative',
        userSelect: 'none', touchAction: 'none',
      }}>

      <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`} style={{ overflow: 'visible' }}>
        <defs>
          <radialGradient id="dialCore" cx="50%" cy="40%" r="60%">
            <stop offset="0%" stopColor="#1f1f1f"/>
            <stop offset="100%" stopColor="#0a0a0a"/>
          </radialGradient>
        </defs>

        {/* Core face — inset from the thin ring */}
        <circle cx={cx} cy={cy} r={r - 16} fill="url(#dialCore)" stroke="rgba(255,255,255,0.04)" strokeWidth="1"/>

        {/* Thin full-circle track */}
        {!boost && (
          <circle cx={cx} cy={cy} r={r}
            fill="none" stroke="rgba(255,255,255,0.10)" strokeWidth="1.5"/>
        )}

        {/* Boost — full closed thin ring */}
        {power && boost && (
          <circle cx={cx} cy={cy} r={r}
            fill="none" stroke={T.yellow} strokeWidth="2"
            opacity="0.95"
            style={{
              filter: `drop-shadow(0 0 6px ${T.yellowGlow})`,
              transition: 'all 380ms cubic-bezier(.32,.72,.24,1.05)',
            }}/>
        )}

        {/* Active arc — from indicator 1 (0°) clockwise to the selected one.
            Opaque dull yellow so the progress dots and the arc read as one
            continuous element. */}
        {power && !boost && speed > 1 && (
          <path d={arcPath(cx, cy, r, 0, angAt(speed - 1))}
            fill="none" stroke="#C2B100" strokeWidth="2"
            strokeLinecap="round"
            style={{
              transition: 'all 480ms cubic-bezier(.32,.72,.24,1.05)',
            }}/>
        )}

        {/* Tick markers — short radial line on the inner edge of the ring at
            each indicator position. Light up in sequence with the arc; the
            selected one stays slightly stronger. */}
        {Array.from({ length: POS }, (_, i) => {
          const a = angAt(i);
          const [x1, y1] = polar(cx, cy, TICK_IN, a);
          const [x2, y2] = polar(cx, cy, TICK_OUT, a);
          const st = stateOf(i);
          const stroke =
            st === 'selected' ? T.yellow
          : st === 'progress' ? '#C2B100'
          : 'rgba(255,255,255,0.22)';
          return (
            <line key={`t${i}`} x1={x1} y1={y1} x2={x2} y2={y2}
              stroke={stroke}
              strokeWidth={st === 'selected' ? 2 : 1.5}
              strokeLinecap="round"
              style={{ transition: 'stroke 280ms' }}/>
          );
        })}

        {/* Indicator dots — sit ON the ring at each position. These are the
            visual selectable controls. Numeric/lightning labels just
            outside are static text. States:
              • selected — bright yellow, strong bloom (focal point)
              • progress — opaque dull yellow matching the arc, no glow
              • off      — dark grey + faint stroke */}
        {Array.from({ length: POS }, (_, i) => {
          const [dx, dy] = polar(cx, cy, r, angAt(i));
          const st = stateOf(i);
          const fill =
            st === 'selected' ? T.yellow
          : st === 'progress' ? '#C2B100'
          : '#1A1A1A';
          const stroke =
            st === 'selected' ? T.yellow
          : st === 'progress' ? '#C2B100'
          : 'rgba(255,255,255,0.22)';
          const filter =
            st === 'selected'
              ? `drop-shadow(0 0 8px ${T.yellowGlow}) drop-shadow(0 0 18px ${T.yellowGlow}) drop-shadow(0 0 32px ${T.yellowGlow})`
              : st === 'off' ? 'drop-shadow(0 0 3px rgba(0,0,0,0.6))' : 'none';
          return (
            <circle key={`d${i}`} cx={dx} cy={dy} r={DOT_D / 2}
              fill={fill}
              stroke={stroke}
              strokeWidth="1.25"
              style={{
                filter,
                transition: 'fill 280ms, stroke 280ms, filter 280ms',
              }}/>
          );
        })}
      </svg>

      {/* Clickable hit areas over each indicator dot — invisible but large
          enough to be tap-friendly. The dots themselves are SVG (drawn above)
          so they don't interfere with hover or pointer events. */}
      {Array.from({ length: POS }, (_, i) => {
        const [hx, hy] = polar(cx, cy, r, angAt(i));
        return (
          <button key={`h${i}`} onClick={() => tap(i)}
            disabled={!power}
            aria-label={i === 6 ? 'Boost' : `Speed ${i + 1}`}
            style={{
              position: 'absolute',
              left: hx - HIT_D / 2, top: hy - HIT_D / 2,
              width: HIT_D, height: HIT_D, borderRadius: '50%',
              padding: 0, border: 'none', background: 'transparent',
              cursor: power ? 'pointer' : 'not-allowed',
            }}/>
        );
      })}

      {/* Static labels — numbers 1..6 and the lightning icon. Positioned
          outside the ring; purely informational, NOT interactive. */}
      {Array.from({ length: POS }, (_, i) => {
        const [bx, by] = polar(cx, cy, LABEL_R, angAt(i));
        const isBoost = i === 6;
        const lit = isLit(i);
        return (
          <div key={`l${i}`}
            style={{
              position: 'absolute',
              left: bx - LABEL_D / 2, top: by - LABEL_D / 2,
              width: LABEL_D, height: LABEL_D,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: T.fontMono, fontSize: 15, fontWeight: 700,
              color: lit ? T.text : (power ? T.textMut : T.textDim),
              pointerEvents: 'none',
              transition: 'color 240ms',
            }}>
            {isBoost
              ? <Icon.bolt s={16} c={lit ? T.text : (power ? T.textMut : T.textDim)}/>
              : i + 1}
          </div>
        );
      })}

      {/* Center readouts */}
      <div style={{
        position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', pointerEvents: 'none',
      }}>
        {boost ? (
          <React.Fragment>
            <div style={{
              fontFamily: T.fontMono, fontSize: 11, fontWeight: 700,
              color: T.textMut, letterSpacing: '0.28em',
            }}>BOOST</div>
            <div style={{ marginTop: 8, filter: `drop-shadow(0 0 18px ${T.yellowGlow})` }}>
              <Icon.bolt s={64} c={T.yellow}/>
            </div>
            <div style={{ display: 'flex', gap: 18, marginTop: 14 }}>
              <Stat label="RPM" value={power ? rpm : '—'}/>
              <div style={{ width: 1, background: T.hairline }}/>
              <Stat label="WATTS" value={power ? watts : '—'}/>
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <div style={{
              fontFamily: T.fontMono, fontSize: 11, fontWeight: 700,
              color: T.textMut, letterSpacing: '0.22em',
            }}>GEAR</div>
            <div style={{
              fontFamily: T.fontMono, fontSize: 84, fontWeight: 600,
              color: power ? T.text : T.textDim,
              lineHeight: 1, marginTop: 2, letterSpacing: '-0.04em',
              transition: 'color 240ms',
            }}>{power ? speed : '—'}</div>
            <div style={{ display: 'flex', gap: 18, marginTop: 14 }}>
              <Stat label="RPM" value={power ? rpm : '—'}/>
              <div style={{ width: 1, background: T.hairline }}/>
              <Stat label="WATTS" value={power ? watts : '—'}/>
            </div>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ fontFamily: T.fontMono, fontSize: 18, fontWeight: 600, color: T.text, lineHeight: 1 }}>{value}</div>
      <div style={{ fontFamily: T.fontMono, fontSize: 9, fontWeight: 600, color: T.textDim, letterSpacing: '0.18em', marginTop: 4 }}>{label}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Color temperatures
// ─────────────────────────────────────────────────────────────
const COLOR_TEMPS = [
  {
    id: 'warm',    label: 'Warm',    kelvin: '2700K',
    bg: '#E6B85C', glow: '#F2C46D', highlight: '#FFE2A8',
  },
  {
    id: 'neutral', label: 'Neutral', kelvin: '4000K',
    bg: '#CFCFCF', glow: '#B8B8B8', highlight: '#ECECEC',
  },
  {
    id: 'cool',    label: 'Cool',    kelvin: '6500K',
    bg: '#DDEEFF', glow: '#CFE5FF', highlight: '#F8FCFF',
  },
];

// ─────────────────────────────────────────────────────────────
function FanControlScreen({ state, set, onBack }) {
  const { fanName, conn, speed, power, mode, timer, boost, light, colorTemp } = state;
  const [disconnectAlert, setDisconnectAlert] = React.useState(false);

  const isConnected = conn === 'connected';

  const tryPowerToggle = () => {
    if (!power && !isConnected) { setDisconnectAlert(true); return; }
    set({ power: !power });
  };

  const setSpeed = (s) => {
    if (!power) return;
    const patch = { speed: s };
    if (boost) patch.boost = false; // any manual speed change exits boost
    set(patch);
  };
  const toggleBoost = () => {
    if (!power) return;
    set({ boost: !boost, speed: !boost ? 6 : state.speed });
  };
  const toggleMode = (m) => set({ mode: state.mode === m ? null : m });

  const MODES = [
    { id: 'nature', label: 'Nature', icon: Icon.leaf },
    { id: 'smart', label: 'Smart', icon: Icon.spark },
    { id: 'reverse', label: 'Reverse', icon: Icon.reverse },
  ];
  const TIMERS = ['OFF', '2H', '4H', '8H'];

  // Boost in the Operating Modes is "on" when state.boost is true.
  const boostActive = boost;

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflowY: 'auto', paddingBottom: 32, position: 'relative' }}>
      {/* Top bar — back + fan name + connection text + BT icon top-right */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 20px 12px',
      }}>
        <button onClick={onBack} style={{ ...iconBtnLite }}>
          <Icon.back/>
        </button>
        <div style={{ textAlign: 'center', flex: 1 }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: T.text }}>{fanName}</div>
          <div style={{
            marginTop: 3, fontSize: 10, fontWeight: 700,
            color: isConnected ? T.yellow : conn === 'connecting' ? T.yellowSoft : T.textDim,
            letterSpacing: '0.22em',
            display: 'inline-flex', alignItems: 'center', gap: 6,
          }}>
            {isConnected ? 'CONNECTED' : conn === 'connecting' ? 'CONNECTING' : 'DISCONNECTED'}
          </div>
        </div>
        {/* Bluetooth icon top-right */}
        <div style={{
          width: 40, height: 40, borderRadius: 12,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <span style={{
            display: 'inline-flex',
            color: isConnected ? '#409CFF' : T.text,
            animation: isConnected ? 'tn-bt-blink 1.8s ease-in-out infinite' : 'none',
          }}>
            <Icon.bluetooth s={20} c="currentColor"/>
          </span>
        </div>
      </div>

      {/* Power button — circular, between header and dial.
          Visual state communicates both connection AND power:
            \u2022 disconnected \u2192 neutral grey rim (no glow)
            \u2022 connected + off \u2192 subtle red rim + faint red halo
            \u2022 connected + on  \u2192 vibrant green rim + green bloom */}
      <div style={{ display: 'flex', justifyContent: 'center', padding: '4px 0 14px' }}>
        {(() => {
          const status = !isConnected ? 'grey' : (power ? 'on' : 'off');
          const palette = {
            on:   { rim: '#3FD37A', icon: '#3FD37A', bg: 'rgba(63,211,122,0.10)',
                    shadow: '0 0 14px rgba(63,211,122,0.55), 0 0 28px rgba(63,211,122,0.30)' },
            off:  { rim: '#E5484D', icon: '#E5484D', bg: 'rgba(229,72,77,0.08)',
                    shadow: '0 0 10px rgba(229,72,77,0.30), 0 0 22px rgba(229,72,77,0.15)' },
            grey: { rim: 'rgba(255,255,255,0.28)', icon: 'rgba(255,255,255,0.55)', bg: T.card,
                    shadow: '0 0 8px rgba(255,255,255,0.06)' },
          }[status];
          return (
            <button onClick={tryPowerToggle}
              aria-label={power ? 'Power off' : 'Power on'}
              style={{
                width: 56, height: 56, borderRadius: '50%',
                border: `1.5px solid ${palette.rim}`,
                background: palette.bg,
                color: palette.icon,
                cursor: 'pointer', padding: 0,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: palette.shadow,
                transition: 'all 260ms',
              }}>
              <Icon.power s={26} c="currentColor"/>
            </button>
          );
        })()}
      </div>

      {/* Dial */}
      <div style={{ padding: '4px 0 12px' }}>
        <RadialDial speed={speed} power={power} boost={boost}
          onChange={setSpeed} onBoostToggle={toggleBoost}/>
      </div>

      {/* Operating modes — 4 buttons including Boost */}
      <SectionHeader title="OPERATING MODES"/>
      <div style={{ padding: '0 20px 16px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
          {MODES.map(m => {
            const on = mode === m.id;
            return (
              <button key={m.id} onClick={() => toggleMode(m.id)} disabled={!power}
                style={{
                  height: 80, borderRadius: 16,
                  background: on ? T.yellow : T.card,
                  border: `1px solid ${on ? T.yellow : T.hairline}`,
                  color: on ? '#000' : (power ? T.text : T.textDim),
                  display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
                  fontFamily: T.font, fontSize: 12, fontWeight: 600,
                  cursor: power ? 'pointer' : 'not-allowed',
                  opacity: power ? 1 : 0.55,
                  boxShadow: on ? `0 0 18px ${T.yellowGlow}` : 'none',
                  transition: 'all 240ms',
                }}>
                <m.icon s={20} c="currentColor"/>
                {m.label}
              </button>
            );
          })}
          {/* Boost — same shape as the others */}
          <button onClick={toggleBoost} disabled={!power}
            style={{
              height: 80, borderRadius: 16,
              background: boostActive ? T.yellow : T.card,
              border: `1px solid ${boostActive ? T.yellow : T.hairline}`,
              color: boostActive ? '#000' : (power ? T.text : T.textDim),
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
              fontFamily: T.font, fontSize: 12, fontWeight: 600,
              cursor: power ? 'pointer' : 'not-allowed',
              opacity: power ? 1 : 0.55,
              boxShadow: boostActive ? `0 0 18px ${T.yellowGlow}` : 'none',
              transition: 'all 240ms',
            }}>
            <Icon.bolt s={20} c="currentColor"/>
            Boost
          </button>
        </div>
      </div>

      {/* Light intensity slider */}
      <SectionHeader title="LIGHT INTENSITY"
        trailing={
          <span style={{ fontFamily: T.fontMono, fontSize: 10, color: T.yellow, fontWeight: 700, letterSpacing: '0.16em' }}>
            {light}%
          </span>
        }/>
      <div style={{ padding: '0 20px 18px' }}>
        <LightSlider value={light} disabled={!power} onChange={(v) => set({ light: v })}/>
      </div>

      {/* Color Temperature — only usable when light > 0 */}
      <SectionHeader title="COLOUR TEMPERATURE"
        trailing={
          <span style={{ fontFamily: T.fontMono, fontSize: 10, color: light > 0 ? T.yellow : T.textDim, fontWeight: 700, letterSpacing: '0.16em' }}>
            {COLOR_TEMPS.find(c => c.id === colorTemp)?.label?.toUpperCase() || '—'}
          </span>
        }/>
      <div style={{ padding: '0 20px 18px' }}>
        <ColorTempPicker value={colorTemp} disabled={!power || light === 0}
          onChange={(v) => set({ colorTemp: v })}/>
      </div>

      {/* Sleep timer */}
      <SectionHeader title="SLEEP TIMER"
        trailing={timer !== 'OFF' && (
          <span style={{ fontFamily: T.fontMono, fontSize: 10, color: T.yellow, fontWeight: 700, letterSpacing: '0.16em' }}>
            {timer} REMAINING
          </span>
        )}/>
      <div style={{ padding: '0 20px 28px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
          {TIMERS.map(t => {
            const on = timer === t;
            return (
              <button key={t} onClick={() => set({ timer: t })} disabled={!power}
                style={{
                  height: 50, borderRadius: 14,
                  background: on ? T.yellow : T.card,
                  border: `1px solid ${on ? T.yellow : T.hairline}`,
                  color: on ? '#000' : (power ? T.text : T.textDim),
                  fontFamily: T.fontMono, fontSize: 13, fontWeight: 700, cursor: power ? 'pointer' : 'not-allowed',
                  opacity: power ? 1 : 0.55,
                  boxShadow: on ? `0 0 18px ${T.yellowGlow}` : 'none',
                  transition: 'all 240ms', letterSpacing: '0.06em',
                }}>{t}</button>
            );
          })}
        </div>
      </div>

      {/* Disconnect alert */}
      <DisconnectAlert open={disconnectAlert} fanName={fanName}
        onClose={() => setDisconnectAlert(false)}
        onRetry={() => {
          setDisconnectAlert(false);
          set({ conn: 'connecting' });
          setTimeout(() => set({ conn: 'connected' }), 1400);
        }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
function SectionHeader({ title, trailing }) {
  return (
    <div style={{
      padding: '6px 20px 10px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    }}>
      <div style={{
        fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
        color: T.textMut, letterSpacing: '0.22em',
      }}>{title}</div>
      {trailing}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Color Temperature picker — 3 buttons, same shape as sleep-timer pills
// ─────────────────────────────────────────────────────────────
function ColorTempPicker({ value, onChange, disabled }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, opacity: disabled ? 0.4 : 1 }}>
      {COLOR_TEMPS.map(c => {
        const on = value === c.id && !disabled;
        return (
          <button key={c.id} onClick={() => !disabled && onChange(c.id)}
            disabled={disabled}
            style={{
              position: 'relative',
              height: 64, borderRadius: 14,
              background: on ? c.bg : '#1A1A1A',
              border: `1px solid ${on ? c.highlight : '#2A2A2A'}`,
              color: on ? '#1A1A1A' : '#6F6F6F',
              display: 'flex',
              alignItems: 'center', justifyContent: 'center',
              fontFamily: T.font, fontSize: 14, fontWeight: 700,
              cursor: disabled ? 'not-allowed' : 'pointer',
              transition: 'all 260ms cubic-bezier(.2,.7,.2,1)',
              boxShadow: on
                ? `0 0 0 1.5px ${c.highlight}55, 0 0 22px ${c.glow}88, 0 0 44px ${c.bg}66`
                : 'none',
              letterSpacing: '0.02em',
              overflow: 'hidden',
              textAlign: 'center',
            }}>
            {/* Ambient highlight wash on active */}
            {on && (
              <div style={{
                position: 'absolute', inset: 0,
                background: `radial-gradient(circle at 50% 30%, ${c.highlight}aa 0%, ${c.bg} 60%, ${c.bg} 100%)`,
                pointerEvents: 'none',
              }}/>
            )}
            <span style={{ position: 'relative', zIndex: 1 }}>{c.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Light intensity slider — custom drag track
// ─────────────────────────────────────────────────────────────
function LightSlider({ value, onChange, disabled }) {
  const trackRef = React.useRef(null);
  const STOPS = [0, 25, 50, 75, 100];

  const drag = (clientX) => {
    if (!trackRef.current) return;
    const rect = trackRef.current.getBoundingClientRect();
    const t = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const v = Math.round(t * 100);
    onChange(v);
  };

  const ptr = (e) => {
    if (disabled) return;
    e.preventDefault();
    const move = (ev) => drag(ev.clientX);
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    drag(e.clientX);
  };

  return (
    <div style={{
      background: T.card, border: `1px solid ${T.hairline}`,
      borderRadius: 18, padding: '18px 18px 14px',
      opacity: disabled ? 0.5 : 1,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <Icon.bulb s={18} c={value > 0 && !disabled ? T.yellow : T.textMut}/>
        <div ref={trackRef}
          onPointerDown={ptr}
          style={{
            flex: 1, height: 28, position: 'relative',
            cursor: disabled ? 'not-allowed' : 'pointer',
            touchAction: 'none',
          }}>
          {/* track */}
          <div style={{
            position: 'absolute', left: 0, right: 0, top: 12, height: 4,
            background: 'rgba(255,255,255,0.08)', borderRadius: 2,
          }}/>
          {/* fill */}
          <div style={{
            position: 'absolute', left: 0, top: 12, height: 4,
            width: `${value}%`,
            background: T.yellow, borderRadius: 2,
            boxShadow: value > 0 && !disabled ? `0 0 10px ${T.yellowGlow}` : 'none',
            transition: 'width 220ms cubic-bezier(.2,.7,.2,1)',
          }}/>
          {/* knob */}
          <div style={{
            position: 'absolute', top: 0, left: `calc(${value}% - 14px)`,
            width: 28, height: 28, borderRadius: '50%',
            background: T.yellow, border: '3px solid #000',
            boxShadow: !disabled ? `0 0 14px ${T.yellowGlow}` : 'none',
            transition: 'left 220ms cubic-bezier(.2,.7,.2,1)',
          }}/>
        </div>
        <Icon.bulb s={22} c={value > 50 && !disabled ? T.yellow : T.textMut}/>
      </div>
      <div style={{
        marginTop: 12, display: 'flex', justifyContent: 'space-between',
        padding: '0 28px',
      }}>
        {STOPS.map(p => (
          <span key={p} style={{
            fontFamily: T.fontMono, fontSize: 9, fontWeight: 600,
            color: p <= value && !disabled ? T.text : T.textDim, letterSpacing: '0.08em',
          }}>{p}</span>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Disconnect alert
// ─────────────────────────────────────────────────────────────
function DisconnectAlert({ open, fanName, onClose, onRetry }) {
  if (!open) return null;
  return (
    <div onClick={onClose} style={{
      position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.7)',
      backdropFilter: 'blur(10px)', WebkitBackdropFilter: 'blur(10px)',
      zIndex: 50, display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 24, animation: 'tn-fade 200ms',
    }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: '100%', maxWidth: 340,
        background: T.surface,
        border: `1px solid ${T.hairlineStrong}`,
        borderRadius: 24, padding: 28,
        animation: 'tn-slideup 280ms cubic-bezier(.2,.7,.2,1)',
        textAlign: 'center',
        boxShadow: '0 30px 80px rgba(0,0,0,0.6)',
      }}>
        <div style={{
          width: 64, height: 64, borderRadius: 20,
          background: 'rgba(255,236,0,0.12)',
          border: '1px solid rgba(255,236,0,0.28)',
          margin: '0 auto 18px',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icon.bluetooth s={28} c={T.yellow}/>
        </div>
        <div style={{ fontFamily: T.font, fontSize: 20, fontWeight: 700, color: T.text }}>
          Fan is disconnected
        </div>
        <div style={{ fontFamily: T.font, fontSize: 13, color: T.textMut, marginTop: 10, lineHeight: 1.5 }}>
          Please re-establish the Bluetooth connection<br/>to <b style={{ color: T.text }}>{fanName}</b> before powering it on.
        </div>
        <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <button onClick={onRetry} style={{
            width: '100%', height: 50, borderRadius: 14,
            background: T.yellow, color: '#000', border: 'none',
            fontFamily: T.font, fontSize: 14, fontWeight: 700,
            cursor: 'pointer', letterSpacing: '0.04em',
            boxShadow: `0 0 20px ${T.yellowGlow}`,
          }}>Reconnect</button>
          <button onClick={onClose} style={{
            width: '100%', height: 46, borderRadius: 14,
            background: 'transparent', color: T.textMut, border: 'none',
            fontFamily: T.font, fontSize: 13, fontWeight: 600,
            cursor: 'pointer',
          }}>Not now</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FanControlScreen, RadialDial, LightSlider, ColorTempPicker, COLOR_TEMPS, DisconnectAlert, SectionHeader });
