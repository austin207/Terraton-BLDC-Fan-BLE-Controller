// profile.jsx — Profile Setup screen (post-splash onboarding)

function ProfileScreen({ onContinue }) {
  const [name, setName] = React.useState('');
  const inputRef = React.useRef(null);
  const valid = name.trim().length >= 2;

  React.useEffect(() => {
    // Soft focus after mount
    setTimeout(() => inputRef.current && inputRef.current.focus(), 200);
  }, []);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* Top brand */}
      <div style={{ padding: '20px 20px 0', display: 'flex', justifyContent: 'center' }}>
        <BrandMark height={22}/>
      </div>

      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center',
        padding: '0 28px',
      }}>
        {/* Iconographic header */}
        <div style={{
          width: 76, height: 76, borderRadius: 24,
          background: 'rgba(255,236,0,0.10)',
          border: '1px solid rgba(255,236,0,0.25)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          marginBottom: 28,
          boxShadow: `0 0 40px ${T.yellowGlow}`,
        }}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="8" r="4" stroke={T.yellow} strokeWidth="1.8"/>
            <path d="M4 21a8 8 0 0 1 16 0" stroke={T.yellow} strokeWidth="1.8" strokeLinecap="round"/>
          </svg>
        </div>

        <div style={{
          fontFamily: T.font, fontSize: 32, fontWeight: 700, color: T.text,
          letterSpacing: '-0.02em', lineHeight: 1.1,
        }}>
          What should<br/>we call you?
        </div>
        <div style={{
          fontFamily: T.font, fontSize: 14, color: T.textMut, marginTop: 12, lineHeight: 1.5,
        }}>
          We'll personalize your home, devices and<br/>schedules around your name.
        </div>

        {/* Input */}
        <div style={{ marginTop: 36, position: 'relative' }}>
          <div style={{
            fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
            color: T.textMut, letterSpacing: '0.22em', marginBottom: 10,
          }}>YOUR NAME</div>
          <input ref={inputRef}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Austin"
            style={{
              width: '100%', boxSizing: 'border-box',
              background: T.card, color: T.text,
              border: `1px solid ${name ? 'rgba(255,236,0,0.35)' : T.hairlineStrong}`,
              borderRadius: 16, padding: '18px 18px',
              fontFamily: T.font, fontSize: 18, fontWeight: 600,
              outline: 'none',
              transition: 'all 220ms',
              boxShadow: name ? `0 0 24px ${T.yellowGlow}` : 'none',
            }}/>
        </div>
      </div>

      {/* Footer CTA */}
      <div style={{ padding: '20px 24px 28px' }}>
        <button
          onClick={() => valid && onContinue && onContinue(name.trim())}
          disabled={!valid}
          style={{
            width: '100%', height: 56, borderRadius: 18,
            background: valid ? T.yellow : T.card,
            color: valid ? '#000' : T.textDim,
            border: 'none',
            fontFamily: T.font, fontSize: 15, fontWeight: 700,
            cursor: valid ? 'pointer' : 'not-allowed',
            letterSpacing: '0.04em',
            boxShadow: valid ? `0 0 28px ${T.yellowGlow}` : 'none',
            transition: 'all 220ms',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          }}>
          Continue
          <Icon.chev s={18} c={valid ? '#000' : T.textDim}/>
        </button>
        <div style={{
          marginTop: 14, textAlign: 'center',
          fontFamily: T.fontMono, fontSize: 10, color: T.textDim, letterSpacing: '0.18em',
        }}>
          STEP 1 OF 1 · SETUP
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ProfileScreen });
