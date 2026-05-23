// home.jsx — Home: greeting, Fans tile, Today's Usage. Bottom nav routes Analytics/Home/Settings.

function HomeScreen({ state, set, onOpenFans }) {
  const { fans, userName } = state;
  const running = fans.filter(f => f.on).length;
  const connected = fans.filter(f => f.conn !== 'disconnected').length;
  const hour = new Date().getHours();
  const greet = hour < 5 ? 'Sleep well' : hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflowY: 'auto', paddingBottom: 96 }}>
      {/* Header — brand only, no settings icon */}
      <div style={{
        padding: '6px 20px 12px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <BrandMark height={22}/>
        <div style={{ width: 24 }}/>
      </div>

      {/* Greeting */}
      <div style={{ padding: '4px 20px 24px' }}>
        <div style={{ fontFamily: T.font, fontSize: 28, fontWeight: 600, color: T.text, letterSpacing: '-0.02em', lineHeight: 1.15 }}>
          {greet},<br/>
          <span style={{ color: T.textMut }}>{userName || 'there'}.</span>
        </div>
      </div>

      {/* Fans tile */}
      <div style={{ padding: '0 20px 14px' }}>
        <DeviceCategoryCard
          icon={Icon.fan}
          title="Fans"
          subtitle={`${fans.length} paired · ${running} running`}
          accent
          onClick={onOpenFans}
        />
      </div>

      {/* Today's Usage card */}
      <div style={{ padding: '0 20px 0' }}>
        <Card style={{ padding: 20, display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{
            width: 48, height: 48, borderRadius: 14,
            background: 'rgba(255,236,0,0.10)',
            border: '1px solid rgba(255,236,0,0.22)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon.bolt s={24}/>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: T.fontMono, fontSize: 10, fontWeight: 700, color: T.textMut, letterSpacing: '0.2em' }}>TODAY'S USAGE</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 6 }}>
              <span style={{ fontFamily: T.fontMono, fontSize: 26, fontWeight: 600, color: T.text, letterSpacing: '-0.02em' }}>2.4</span>
              <span style={{ fontFamily: T.fontMono, fontSize: 12, color: T.textMut, letterSpacing: '0.06em' }}>kWh · ₹13.0</span>
            </div>
          </div>
          <div style={{
            padding: '6px 10px', borderRadius: 8,
            background: 'rgba(255,236,0,0.10)',
            border: '1px solid rgba(255,236,0,0.22)',
            fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
            color: T.yellow, letterSpacing: '0.12em',
          }}>↓ 18%</div>
        </Card>
      </div>
    </div>
  );
}

function DeviceCategoryCard({ icon: Ic, title, subtitle, accent, onClick }) {
  const enabled = !!onClick;
  return (
    <button onClick={onClick} disabled={!enabled} style={{
      display: 'flex', alignItems: 'center', gap: 18,
      width: '100%', padding: 22,
      background: accent
        ? 'linear-gradient(135deg, rgba(255,236,0,0.10), rgba(255,236,0,0.02))'
        : T.card,
      border: `1px solid ${accent ? 'rgba(255,236,0,0.30)' : T.hairline}`,
      borderRadius: 22, cursor: enabled ? 'pointer' : 'default',
      color: T.text, fontFamily: T.font, textAlign: 'left',
      transition: 'all 240ms cubic-bezier(.2,.7,.2,1)',
      boxShadow: accent ? `0 0 30px ${T.yellowGlow}` : 'none',
    }}
      onMouseEnter={e => enabled && (e.currentTarget.style.transform = 'translateY(-1px)')}
      onMouseLeave={e => enabled && (e.currentTarget.style.transform = 'translateY(0)')}>
      <div style={{
        width: 56, height: 56, borderRadius: 16,
        background: accent ? 'rgba(255,236,0,0.15)' : T.cardHi,
        border: accent ? '1px solid rgba(255,236,0,0.3)' : 'none',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ic s={28} c={accent ? T.yellow : T.textMut}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: '-0.01em' }}>{title}</div>
        <div style={{ fontSize: 12, color: T.textMut, marginTop: 4 }}>{subtitle}</div>
      </div>
      {enabled && <Icon.chev s={22} c={accent ? T.yellow : T.textMut}/>}
    </button>
  );
}

function FanIcon({ active, speed, size = 22 }) {
  const spin = (typeof window !== 'undefined') ? (window.__terratonFanAnim !== false) : true;
  return (
    <div style={{
      animation: (active && spin) ? `tn-spin ${Math.max(0.7, 2.5 - speed*0.3)}s linear infinite` : 'none',
      display: 'flex',
    }}>
      <Icon.fan s={size} c={active ? T.yellow : T.textMut}/>
    </div>
  );
}

Object.assign(window, { HomeScreen, FanIcon, DeviceCategoryCard });
