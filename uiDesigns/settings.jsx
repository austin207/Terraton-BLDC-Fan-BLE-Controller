// settings.jsx — Settings (matches reference) + Splash (logo-only)

function SettingsScreen({ state, set, onBack, onOpenManual, initialRename = false, initialServiceQr = false }) {
  const userName = state?.userName || 'Austin';
  const [renaming, setRenaming] = React.useState(initialRename);
  const [draft, setDraft] = React.useState(userName);
  const [serviceQr, setServiceQr] = React.useState(initialServiceQr);

  const openRename = () => { setDraft(userName); setRenaming(true); };
  const closeRename = () => setRenaming(false);
  const saveRename = () => {
    const v = (draft || '').trim();
    if (v && set) set({ userName: v });
    setRenaming(false);
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflowY: 'auto', paddingBottom: 28, position: 'relative' }}>
      <ScreenHeader title="Settings" onBack={onBack}/>

      {/* Name handle */}
      <div style={{ padding: '0 20px 20px' }}>
        <div style={{
          background: 'linear-gradient(135deg, rgba(255,236,0,0.08), rgba(255,236,0,0.01))',
          border: '1px solid rgba(255,236,0,0.22)',
          borderRadius: 18, padding: 18,
          display: 'flex', alignItems: 'center', gap: 14,
        }}>
          <div style={{
            width: 48, height: 48, borderRadius: 16,
            background: T.yellow, color: '#000',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: T.font, fontSize: 20, fontWeight: 700,
            boxShadow: `0 0 18px ${T.yellowGlow}`,
          }}>{(userName[0] || 'A').toUpperCase()}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.font, fontSize: 17, fontWeight: 700, color: T.text }}>{userName}</div>
          </div>
          <button onClick={openRename} style={{
            padding: '8px 14px', borderRadius: 10,
            background: 'transparent', border: `1px solid ${T.hairlineStrong}`,
            color: T.text, fontFamily: T.font, fontSize: 11, fontWeight: 600, cursor: 'pointer',
            letterSpacing: '0.06em',
          }}>EDIT</button>
        </div>
      </div>

      {/* DATA MANAGEMENT */}
      <SectionLabel title="DATA MANAGEMENT"/>
      <SettingsGroup>
        <SettingRow icon={SettIcon.upload} iconBg="rgba(80,130,255,0.15)" iconColor="#7AA7FF"
          label="Export Fans Data" divider/>
        <SettingRow icon={SettIcon.download} iconBg="rgba(122,229,130,0.12)" iconColor="#7AE582"
          label="Import Fans Data"/>
      </SettingsGroup>

      {/* ABOUT */}
      <SectionLabel title="ABOUT"/>
      <SettingsGroup>
        <SettingRow icon={SettIcon.info} iconBg={T.cardHi} iconColor={T.text}
          label="App Version" trailingText="v1.1.0 (1)" divider/>
        <SettingRow icon={SettIcon.dev} iconBg={T.cardHi} iconColor={T.text}
          label="Firmware Support" trailingPill={{ label: '✓ Up to Date', color: T.green }} divider/>
        <SettingRow icon={SettIcon.ble} iconBg="rgba(80,130,255,0.12)" iconColor="#7AA7FF"
          label="BLE Protocol" trailingPill={{ label: 'BLE 5.2', color: '#7AA7FF', outlined: true }}/>
      </SettingsGroup>

      {/* SUPPORT */}
      <SectionLabel title="SUPPORT"/>
      <SettingsGroup>
        <SettingRow icon={SettIcon.book} iconBg="rgba(255,180,0,0.15)" iconColor={T.yellow}
          label="User Manual" trailingChev onClick={onOpenManual} divider/>
        <SettingRow icon={SettIcon.qr} iconBg="rgba(255,236,0,0.15)" iconColor={T.yellow}
          label="Service QR" trailingChev onClick={() => setServiceQr(true)}/>
      </SettingsGroup>

      {/* Rename modal */}
      <RenameModal open={renaming} value={draft} onChange={setDraft}
        onClose={closeRename} onSave={saveRename}/>

      {/* Service QR modal */}
      <ServiceQrModal open={serviceQr} fanName={state?.activeFan?.name}
        onClose={() => setServiceQr(false)}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Rename user modal — premium black & yellow modal
// ─────────────────────────────────────────────────────────────
function RenameModal({ open, value, onChange, onClose, onSave }) {
  const inputRef = React.useRef(null);
  React.useEffect(() => {
    if (open && inputRef.current) {
      // tiny delay so the animation can take effect before focus
      const t = setTimeout(() => inputRef.current && inputRef.current.focus(), 80);
      return () => clearTimeout(t);
    }
  }, [open]);

  if (!open) return null;
  return (
    <div onClick={onClose} style={{
      position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.66)',
      backdropFilter: 'blur(14px)', WebkitBackdropFilter: 'blur(14px)',
      zIndex: 60, display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 22, animation: 'tn-fade 220ms ease-out',
    }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: '100%', maxWidth: 340,
        background: `linear-gradient(180deg, ${T.cardElev} 0%, ${T.surface} 100%)`,
        border: `1px solid ${T.hairlineStrong}`,
        borderRadius: 26, padding: 24,
        animation: 'tn-slideup 320ms cubic-bezier(.2,.7,.2,1)',
        boxShadow: '0 30px 80px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,236,0,0.05), inset 0 1px 0 rgba(255,255,255,0.04)',
        position: 'relative',
      }}>
        {/* Close × */}
        <button onClick={onClose} style={{
          position: 'absolute', top: 16, right: 16,
          width: 32, height: 32, borderRadius: 10,
          background: 'transparent', border: 'none', color: T.textMut,
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}>
          <Icon.x s={16} c="currentColor"/>
        </button>

        {/* Yellow pencil chip */}
        <div style={{
          width: 52, height: 52, borderRadius: 16,
          background: 'rgba(255,236,0,0.10)',
          border: '1px solid rgba(255,236,0,0.28)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 24px ${T.yellowGlow}`,
        }}>
          <Icon.pencil s={20} c={T.yellow}/>
        </div>

        <div style={{
          fontFamily: T.font, fontSize: 20, fontWeight: 700, color: T.text,
          marginTop: 18, letterSpacing: '-0.01em',
        }}>Edit your name</div>
        <div style={{
          fontFamily: T.font, fontSize: 13, color: T.textMut,
          marginTop: 6, lineHeight: 1.45,
        }}>This is the name shown on your profile and across the app.</div>

        {/* Floating-label input */}
        <div style={{ marginTop: 20 }}>
          <div style={{
            fontFamily: T.fontMono, fontSize: 9, fontWeight: 700,
            color: T.yellow, letterSpacing: '0.24em', marginBottom: 8,
          }}>YOUR NAME</div>
          <div style={{
            background: T.bg,
            border: `1px solid rgba(255,236,0,0.32)`,
            borderRadius: 14,
            padding: '4px 4px 4px 16px',
            display: 'flex', alignItems: 'center', gap: 10,
            boxShadow: `0 0 0 4px rgba(255,236,0,0.06), 0 0 22px ${T.yellowGlow}`,
          }}>
            <input ref={inputRef}
              value={value || ''}
              onChange={(e) => onChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') onSave();
                else if (e.key === 'Escape') onClose();
              }}
              maxLength={32}
              style={{
                flex: 1, minWidth: 0,
                background: 'transparent', color: T.text, border: 'none',
                fontFamily: T.font, fontSize: 16, fontWeight: 600,
                outline: 'none', padding: '14px 0',
                caretColor: T.yellow,
              }}/>
            {value && value.length > 0 && (
              <button onClick={() => onChange('')} style={{
                width: 36, height: 36, borderRadius: 10,
                background: T.cardHi, border: 'none', color: T.textMut,
                display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
                marginRight: 4,
              }}>
                <Icon.x s={14} c="currentColor"/>
              </button>
            )}
          </div>
          <div style={{
            display: 'flex', justifyContent: 'space-between',
            fontFamily: T.fontMono, fontSize: 10, color: T.textDim,
            marginTop: 8, letterSpacing: '0.08em',
          }}>
            <span>2–32 characters</span>
            <span>{(value || '').length}/32</span>
          </div>
        </div>

        {/* Actions */}
        <div style={{ marginTop: 22, display: 'flex', gap: 10 }}>
          <button onClick={onClose} style={{
            flex: 1, height: 50, borderRadius: 14,
            background: T.cardHi, color: T.text, border: 'none',
            fontFamily: T.font, fontSize: 14, fontWeight: 600,
            cursor: 'pointer', letterSpacing: '0.02em',
          }}>Cancel</button>
          <button onClick={onSave}
            disabled={!value || value.trim().length < 2}
            style={{
              flex: 1, height: 50, borderRadius: 14,
              background: T.yellow, color: '#000', border: 'none',
              fontFamily: T.font, fontSize: 14, fontWeight: 700,
              cursor: (!value || value.trim().length < 2) ? 'not-allowed' : 'pointer',
              opacity: (!value || value.trim().length < 2) ? 0.45 : 1,
              boxShadow: `0 0 22px ${T.yellowGlow}`,
              letterSpacing: '0.02em',
            }}>Save</button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Service QR modal — generates a temporary QR for a technician
// to pair / control the fan briefly. Same dark/yellow modal language
// as the rename popup.
// ─────────────────────────────────────────────────────────────
function ServiceQrModal({ open, onClose, fanName }) {
  // simple ticker for the visible 15-minute expiry
  const TTL = 15 * 60; // seconds
  const [remaining, setRemaining] = React.useState(TTL);
  React.useEffect(() => {
    if (!open) { setRemaining(TTL); return; }
    setRemaining(TTL);
    const id = setInterval(() => setRemaining(r => Math.max(0, r - 1)), 1000);
    return () => clearInterval(id);
  }, [open]);

  if (!open) return null;
  const mins = String(Math.floor(remaining / 60)).padStart(2, '0');
  const secs = String(remaining % 60).padStart(2, '0');

  return (
    <div onClick={onClose} style={{
      position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.66)',
      backdropFilter: 'blur(14px)', WebkitBackdropFilter: 'blur(14px)',
      zIndex: 60, display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 22, animation: 'tn-fade 220ms ease-out',
    }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: '100%', maxWidth: 340,
        background: `linear-gradient(180deg, ${T.cardElev} 0%, ${T.surface} 100%)`,
        border: `1px solid ${T.hairlineStrong}`,
        borderRadius: 26, padding: 24,
        animation: 'tn-slideup 320ms cubic-bezier(.2,.7,.2,1)',
        boxShadow: '0 30px 80px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,236,0,0.05), inset 0 1px 0 rgba(255,255,255,0.04)',
        position: 'relative',
      }}>
        {/* Close × */}
        <button onClick={onClose} style={{
          position: 'absolute', top: 16, right: 16,
          width: 32, height: 32, borderRadius: 10,
          background: 'transparent', border: 'none', color: T.textMut,
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}>
          <Icon.x s={16} c="currentColor"/>
        </button>

        {/* Header chip */}
        <div style={{
          width: 52, height: 52, borderRadius: 16,
          background: 'rgba(255,236,0,0.10)',
          border: '1px solid rgba(255,236,0,0.28)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 24px ${T.yellowGlow}`,
        }}>
          <Icon.qr s={22} c={T.yellow}/>
        </div>

        <div style={{
          fontFamily: T.font, fontSize: 20, fontWeight: 700, color: T.text,
          marginTop: 18, letterSpacing: '-0.01em',
        }}>Service QR</div>
        <div style={{
          fontFamily: T.font, fontSize: 13, color: T.textMut,
          marginTop: 6, lineHeight: 1.45,
        }}>Let a Terraton technician temporarily access and control your fans by scanning the code below.</div>

        {/* QR card */}
        <div style={{
          marginTop: 18, padding: 18, borderRadius: 18,
          background: T.bg,
          border: `1px solid rgba(255,236,0,0.22)`,
          boxShadow: `0 0 22px ${T.yellowGlow}`,
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
        }}>
          <FakeQR size={184}/>
          <div style={{
            fontFamily: T.fontMono, fontSize: 11, fontWeight: 700,
            color: T.text, letterSpacing: '0.16em',
          }}>SVC-9F3A·BLDC52</div>
        </div>

        {/* Expiry + meta */}
        <div style={{
          marginTop: 14,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '12px 14px', borderRadius: 12,
          background: T.card, border: `1px solid ${T.hairline}`,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{
              width: 8, height: 8, borderRadius: '50%', background: T.yellow,
              boxShadow: `0 0 8px ${T.yellowGlow}`,
              animation: 'tn-pulse 1.6s ease-in-out infinite',
            }}/>
            <div>
              <div style={{ fontFamily: T.fontMono, fontSize: 9, fontWeight: 700, color: T.textMut, letterSpacing: '0.18em' }}>EXPIRES IN</div>
              <div style={{ fontFamily: T.fontMono, fontSize: 16, fontWeight: 700, color: T.text, letterSpacing: '0.04em', marginTop: 2 }}>{mins}:{secs}</div>
            </div>
          </div>
          <button style={{
            padding: '8px 12px', borderRadius: 10,
            background: 'transparent', border: `1px solid ${T.hairlineStrong}`,
            color: T.text, fontFamily: T.font, fontSize: 11, fontWeight: 600, cursor: 'pointer',
            letterSpacing: '0.06em',
          }}>REGENERATE</button>
        </div>

        {/* Actions */}
        <div style={{ marginTop: 18, display: 'flex', gap: 10 }}>
          <button onClick={onClose} style={{
            flex: 1, height: 50, borderRadius: 14,
            background: T.cardHi, color: T.text, border: 'none',
            fontFamily: T.font, fontSize: 14, fontWeight: 600,
            cursor: 'pointer', letterSpacing: '0.02em',
          }}>Cancel</button>
          <button onClick={onClose} style={{
            flex: 1, height: 50, borderRadius: 14,
            background: T.yellow, color: '#000', border: 'none',
            fontFamily: T.font, fontSize: 14, fontWeight: 700,
            cursor: 'pointer', letterSpacing: '0.02em',
            boxShadow: `0 0 22px ${T.yellowGlow}`,
          }}>Share</button>
        </div>
      </div>
    </div>
  );
}

// Render a deterministic-looking QR mock — finder boxes + a stable
// pseudo-random module pattern. Not a real QR, just decorative.
function FakeQR({ size = 180 }) {
  const N = 25;
  const cell = size / N;
  // pseudo-random pattern, seeded so every render is identical
  const rng = (i, j) => {
    const v = Math.sin(i * 12.9898 + j * 78.233) * 43758.5453;
    return (v - Math.floor(v)) > 0.5;
  };
  const inFinder = (i, j) => {
    const f = (oi, oj) => i >= oi && i < oi + 7 && j >= oj && j < oj + 7;
    return f(0,0) || f(0, N-7) || f(N-7, 0);
  };
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}
      style={{ background: '#fff', borderRadius: 10 }}>
      {/* modules */}
      {Array.from({ length: N }, (_, i) => (
        Array.from({ length: N }, (_, j) => {
          if (inFinder(i, j)) return null;
          if (!rng(i, j)) return null;
          return <rect key={`${i}-${j}`} x={j * cell} y={i * cell} width={cell} height={cell} fill="#000"/>;
        })
      ))}
      {/* finder patterns */}
      {[[0,0], [0,N-7], [N-7,0]].map(([oi, oj], k) => (
        <g key={k}>
          <rect x={oj * cell} y={oi * cell} width={7*cell} height={7*cell} fill="#000"/>
          <rect x={(oj+1) * cell} y={(oi+1) * cell} width={5*cell} height={5*cell} fill="#fff"/>
          <rect x={(oj+2) * cell} y={(oi+2) * cell} width={3*cell} height={3*cell} fill="#000"/>
        </g>
      ))}
    </svg>
  );
}

function SectionLabel({ title }) {
  return (
    <div style={{
      padding: '8px 24px 8px',
      fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
      color: T.textMut, letterSpacing: '0.22em',
    }}>{title}</div>
  );
}

function SettingsGroup({ children }) {
  return (
    <div style={{ padding: '0 20px 18px' }}>
      <div style={{
        background: T.card, border: `1px solid ${T.hairline}`,
        borderRadius: 18, overflow: 'hidden',
      }}>{children}</div>
    </div>
  );
}

function SettingRow({ icon: Ic, iconBg, iconColor, label, trailingText, trailingPill, trailingChev, divider, onClick }) {
  return (
    <button onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 14,
      width: '100%', padding: '16px 16px',
      background: 'transparent', border: 'none', cursor: onClick ? 'pointer' : 'default',
      borderBottom: divider ? `1px solid ${T.hairline}` : 'none',
      textAlign: 'left', color: T.text, fontFamily: T.font,
    }}>
      <div style={{
        width: 40, height: 40, borderRadius: 11, background: iconBg || T.cardHi,
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        <Ic s={18} c={iconColor || T.yellow}/>
      </div>
      <div style={{ flex: 1, fontSize: 15, fontWeight: 600 }}>{label}</div>
      {trailingText && (
        <div style={{ fontFamily: T.fontMono, fontSize: 12, color: T.textMut }}>{trailingText}</div>
      )}
      {trailingPill && (
        <div style={{
          padding: '5px 10px', borderRadius: 100,
          background: trailingPill.outlined ? 'transparent' : `${trailingPill.color}22`,
          border: trailingPill.outlined ? `1px solid ${trailingPill.color}66` : 'none',
          color: trailingPill.color,
          fontFamily: T.font, fontSize: 11, fontWeight: 700, letterSpacing: '0.02em',
        }}>{trailingPill.label}</div>
      )}
      {trailingChev && <Icon.chev c={T.textMut}/>}
    </button>
  );
}

const SettIcon = {
  upload:   ({ s = 18, c = T.yellow }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 4v12m0-12l-4 4m4-4l4 4M4 20h16" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>,
  download: ({ s = 18, c = T.yellow }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 16V4m0 12l-4-4m4 4l4-4M4 20h16" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>,
  info:     ({ s = 18, c = T.text }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke={c} strokeWidth="1.6"/><path d="M12 11v6M12 7v.5" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  dev:      ({ s = 18, c = T.text }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><rect x="4" y="5" width="13" height="11" rx="2" stroke={c} strokeWidth="1.6"/><path d="M9 20h10M14 16v4" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  ble:      ({ s = 18, c = '#7AA7FF' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M7 7l10 10-5 4V3l5 4L7 17" stroke={c} strokeWidth="1.7" strokeLinejoin="round" strokeLinecap="round"/></svg>,
  book:     ({ s = 18, c = T.yellow }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M4 5a2 2 0 0 1 2-2h12v18H6a2 2 0 0 1-2-2zm0 0v14M8 8h6M8 12h6" stroke={c} strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round"/></svg>,
  qr:       ({ s = 18, c = T.yellow }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.6"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3M20 14v3M14 20h3M17 17h4M21 21v-1"/></svg>,
};

// ─────────────────────────────────────────────────────────────
// SPLASH — Terraton logo (icon only), no extra "T" shape
// ─────────────────────────────────────────────────────────────
function SplashScreen() {
  return (
    <div style={{
      flex: 1, position: 'relative', display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
    }}>
      {/* Aura rings — soft glow only, no T overlay */}
      <div style={{
        position: 'absolute', width: 460, height: 460, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(255,236,0,0.20) 0%, rgba(255,236,0,0.04) 38%, transparent 72%)',
        animation: 'tn-breathe 3.4s ease-in-out infinite',
        pointerEvents: 'none',
      }}/>
      <div style={{
        position: 'absolute', width: 240, height: 240, borderRadius: '50%',
        border: '1px solid rgba(255,236,0,0.18)',
        animation: 'tn-breathe 3.4s ease-in-out infinite',
        pointerEvents: 'none',
      }}/>
      <div style={{
        position: 'absolute', width: 340, height: 340, borderRadius: '50%',
        border: '1px solid rgba(255,236,0,0.10)',
        animation: 'tn-breathe 4.2s ease-in-out infinite',
        pointerEvents: 'none',
      }}/>

      {/* Just the icon — original trademarked colours */}
      <div style={{
        position: 'relative',
        animation: 'tn-breathe 2.8s ease-in-out infinite',
      }}>
        <BrandMark height={148} full={false} glow/>
      </div>

      {/* Loading dots */}
      <div style={{ position: 'absolute', bottom: 64, display: 'flex', gap: 8 }}>
        {[0,1,2].map(i => (
          <div key={i} style={{
            width: 6, height: 6, borderRadius: '50%', background: T.yellow,
            animation: `tn-dot 1.2s ease-in-out infinite`,
            animationDelay: `${i * 0.15}s`, opacity: 0.4,
          }}/>
        ))}
      </div>

      <div style={{
        position: 'absolute', bottom: 36, fontFamily: T.fontMono, fontSize: 10,
        color: T.textDim, letterSpacing: '0.24em',
      }}>v1.1.0 · BUILD 2407</div>
    </div>
  );
}

Object.assign(window, { SettingsScreen, SplashScreen, SettingRow, SettIcon, SectionLabel, SettingsGroup, RenameModal, ServiceQrModal, FakeQR });
