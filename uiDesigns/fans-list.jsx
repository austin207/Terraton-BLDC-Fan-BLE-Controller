// fans-list.jsx — Vertical list of fan cards + long-press action sheet

function FansListScreen({ state, set, onBack, onOpenFan }) {
  const { fans } = state;
  const [actionFor, setActionFor] = React.useState(null); // fan id
  const [renamingFor, setRenamingFor] = React.useState(null);
  const [pairOpen, setPairOpen] = React.useState(false);
  const pressTimer = React.useRef(null);
  const pressed = React.useRef(false);

  const startPress = (id) => {
    pressed.current = false;
    pressTimer.current = setTimeout(() => {
      pressed.current = true;
      if (navigator.vibrate) try { navigator.vibrate(35); } catch(e) {}
      setActionFor(id);
    }, 480);
  };
  const cancelPress = () => {
    if (pressTimer.current) clearTimeout(pressTimer.current);
  };
  const handleClick = (id) => {
    if (pressed.current) { pressed.current = false; return; }
    onOpenFan && onOpenFan(id);
  };

  const activeFan = fans.find(f => f.id === actionFor);

  const renameFan = (id, newName) => {
    set({ fans: fans.map(f => f.id === id ? { ...f, name: newName } : f) });
  };
  const removeFan = (id) => {
    set({ fans: fans.filter(f => f.id !== id) });
    setActionFor(null);
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative' }}>
      <ScreenHeader title="Fans" onBack={onBack}/>

      <div style={{
        padding: '0 20px 8px',
        fontFamily: T.fontMono, fontSize: 10, fontWeight: 700,
        color: T.textMut, letterSpacing: '0.22em',
      }}>{fans.length} PAIRED · LONG-PRESS FOR OPTIONS</div>

      <div style={{
        flex: 1, overflowY: 'auto',
        padding: '12px 20px 110px',
        display: 'flex', flexDirection: 'column', gap: 12,
      }}>
        {fans.map(f => (
          <FanRow key={f.id}
            fan={f}
            onPointerDown={() => startPress(f.id)}
            onPointerUp={cancelPress}
            onPointerLeave={cancelPress}
            onPointerCancel={cancelPress}
            onClick={() => handleClick(f.id)}
          />
        ))}
        {fans.length === 0 && (
          <div style={{
            textAlign: 'center', padding: 60, color: T.textMut,
            fontFamily: T.font, fontSize: 14,
          }}>
            No fans paired yet.<br/>Tap + to add one.
          </div>
        )}
      </div>

      <FanActionSheet
        fan={activeFan}
        open={!!actionFor && !renamingFor}
        onClose={() => setActionFor(null)}
        onRename={() => { setRenamingFor(actionFor); }}
        onRemove={() => removeFan(actionFor)}
      />

      <RenameSheet
        fan={fans.find(f => f.id === renamingFor)}
        open={!!renamingFor}
        onClose={() => { setRenamingFor(null); setActionFor(null); }}
        onConfirm={(name) => { renameFan(renamingFor, name); setRenamingFor(null); setActionFor(null); }}
      />

      <PairSheet open={pairOpen} onClose={() => setPairOpen(false)}/>

      {/* FAB — bottom-right add fan */}
      <button onClick={() => setPairOpen(true)}
        aria-label="Add fan"
        style={{
          position: 'absolute', right: 22, bottom: 26,
          width: 60, height: 60, borderRadius: 22,
          background: T.yellow, border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 14px 32px ${T.yellowGlow}, 0 0 0 1px rgba(255,236,0,0.55)`,
          zIndex: 10,
          transition: 'all 180ms cubic-bezier(.2,.7,.2,1)',
        }}
        onMouseEnter={(e) => { e.currentTarget.style.transform = 'translateY(-2px)'; }}
        onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}>
        <Icon.plus s={26} c="#000"/>
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
function FanRow({ fan, onClick, ...press }) {
  const statusColor = fan.conn === 'connected' ? T.yellow : fan.conn === 'connecting' ? T.yellowSoft : T.textDim;
  const statusLabel = fan.conn === 'connected' ? 'Connected' : fan.conn === 'connecting' ? 'Connecting…' : 'Disconnected';
  // Spin only when the fan is actually connected (and on). Disconnected fans never spin.
  const live = fan.on && fan.conn === 'connected';
  return (
    <div {...press} onClick={onClick} style={{
      background: T.card,
      border: `1px solid ${live ? 'rgba(255,236,0,0.20)' : T.hairline}`,
      borderRadius: 20, padding: '16px 16px',
      display: 'flex', alignItems: 'center', gap: 14,
      cursor: 'pointer', userSelect: 'none', touchAction: 'manipulation',
      transition: 'all 240ms',
    }}>
      <div style={{
        width: 52, height: 52, borderRadius: 14,
        background: live ? 'rgba(255,236,0,0.12)' : T.cardHi,
        border: live ? '1px solid rgba(255,236,0,0.28)' : 'none',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <FanIcon active={live} speed={fan.speed} size={26}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: T.font, fontSize: 15, fontWeight: 700, color: T.text, letterSpacing: '-0.01em' }}>{fan.name}</div>
        <div style={{ fontFamily: T.fontMono, fontSize: 10, fontWeight: 600, color: T.textMut, letterSpacing: '0.1em', marginTop: 4 }}>
          {fan.model}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 8 }}>
          <span style={{
            width: 7, height: 7, borderRadius: '50%', background: statusColor,
            boxShadow: fan.conn === 'connected' ? `0 0 8px ${T.yellowGlow}` : 'none',
            animation: fan.conn === 'connecting' ? 'tn-pulse 1.2s infinite' : 'none',
          }}/>
          <span style={{
            fontFamily: T.font, fontSize: 11, fontWeight: 600,
            color: fan.conn === 'connected' ? T.yellow : T.textMut,
          }}>{statusLabel}</span>
        </div>
      </div>
      {/* Right-facing arrow — navigates to Fan Control (handled by row's onClick). */}
      <div style={{ flexShrink: 0, padding: 4 }}>
        <Icon.chev s={22} c={fan.conn === 'disconnected' ? T.textDim : T.yellow}/>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Bottom action sheet (long-press)
// ─────────────────────────────────────────────────────────────
function FanActionSheet({ fan, open, onClose, onRename, onRemove }) {
  if (!open || !fan) return null;
  return (
    <Sheet onClose={onClose}>
      <div style={{ padding: '4px 20px 12px' }}>
        <div style={{ fontFamily: T.font, fontSize: 16, fontWeight: 700, color: T.text }}>{fan.name}</div>
        <div style={{ fontFamily: T.fontMono, fontSize: 10, fontWeight: 600, color: T.textMut, letterSpacing: '0.12em', marginTop: 4 }}>
          {fan.model.toUpperCase()}
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: '8px 20px 0' }}>
        <ActionRow icon={Icon.pencil} label="Rename Fan" onClick={onRename}/>
        <ActionRow icon={Icon.trash} label="Remove Device" danger onClick={onRemove}/>
      </div>
      <div style={{ padding: '16px 20px 32px' }}>
        <button onClick={onClose} style={{
          width: '100%', height: 52, borderRadius: 16,
          background: T.cardHi, color: T.text, border: 'none',
          fontFamily: T.font, fontSize: 14, fontWeight: 600, cursor: 'pointer',
          letterSpacing: '0.02em',
        }}>Cancel</button>
      </div>
    </Sheet>
  );
}

function ActionRow({ icon: Ic, label, danger, onClick }) {
  const c = danger ? T.red : T.text;
  return (
    <button onClick={onClick} style={{
      width: '100%', height: 60, borderRadius: 16,
      background: T.card, border: `1px solid ${T.hairline}`,
      display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px',
      color: c, fontFamily: T.font, fontSize: 15, fontWeight: 600,
      cursor: 'pointer', textAlign: 'left',
      transition: 'all 180ms',
    }}
      onMouseEnter={(e) => { e.currentTarget.style.background = T.cardElev; }}
      onMouseLeave={(e) => { e.currentTarget.style.background = T.card; }}>
      <div style={{
        width: 36, height: 36, borderRadius: 10,
        background: danger ? 'rgba(255,107,107,0.12)' : 'rgba(255,236,0,0.12)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ic s={18} c={c}/>
      </div>
      <span style={{ flex: 1 }}>{label}</span>
      <Icon.chev c={T.textDim}/>
    </button>
  );
}

// Rename sheet
function RenameSheet({ fan, open, onClose, onConfirm }) {
  const [value, setValue] = React.useState('');
  React.useEffect(() => { if (open && fan) setValue(fan.name); }, [open, fan]);
  if (!open || !fan) return null;
  return (
    <Sheet onClose={onClose}>
      <div style={{ padding: '4px 20px 16px' }}>
        <div style={{ fontFamily: T.font, fontSize: 20, fontWeight: 700, color: T.text }}>Rename fan</div>
        <div style={{ fontFamily: T.font, fontSize: 13, color: T.textMut, marginTop: 4 }}>
          Give this fan a friendlier name.
        </div>
      </div>
      <div style={{ padding: '0 20px 8px' }}>
        <input value={value} onChange={e => setValue(e.target.value)}
          autoFocus
          style={{
            width: '100%', boxSizing: 'border-box',
            background: T.card, color: T.text,
            border: `1px solid rgba(255,236,0,0.30)`,
            borderRadius: 14, padding: '14px 16px',
            fontFamily: T.font, fontSize: 15, fontWeight: 600,
            outline: 'none',
            boxShadow: `0 0 18px ${T.yellowGlow}`,
          }}/>
      </div>
      <div style={{ padding: '16px 20px 32px', display: 'flex', gap: 10 }}>
        <button onClick={onClose} style={{
          flex: 1, height: 52, borderRadius: 16, background: T.cardHi, color: T.text, border: 'none',
          fontFamily: T.font, fontSize: 14, fontWeight: 600, cursor: 'pointer',
        }}>Cancel</button>
        <button onClick={() => onConfirm(value.trim() || fan.name)} disabled={!value.trim()}
          style={{
            flex: 1, height: 52, borderRadius: 16,
            background: value.trim() ? T.yellow : T.cardHi,
            color: value.trim() ? '#000' : T.textDim,
            border: 'none', cursor: value.trim() ? 'pointer' : 'not-allowed',
            fontFamily: T.font, fontSize: 14, fontWeight: 700,
            boxShadow: value.trim() ? `0 0 18px ${T.yellowGlow}` : 'none',
          }}>Save</button>
      </div>
    </Sheet>
  );
}

// Pair sheet (BLE / QR)
function PairSheet({ open, onClose }) {
  if (!open) return null;
  return (
    <Sheet onClose={onClose}>
      <div style={{ padding: '4px 20px 16px' }}>
        <div style={{ fontFamily: T.font, fontSize: 20, fontWeight: 700, color: T.text }}>Pair a new fan</div>
        <div style={{ fontFamily: T.font, fontSize: 13, color: T.textMut, marginTop: 4 }}>
          Choose how you'd like to connect.
        </div>
      </div>
      <div style={{ padding: '8px 20px 0', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <ActionRow icon={Icon.bluetooth} label="Bluetooth pairing" onClick={onClose}/>
        <ActionRow icon={Icon.qr} label="QR code pairing" onClick={onClose}/>
      </div>
      <div style={{ padding: '16px 20px 32px' }}>
        <button onClick={onClose} style={{
          width: '100%', height: 52, borderRadius: 16, background: T.cardHi, color: T.text, border: 'none',
          fontFamily: T.font, fontSize: 14, fontWeight: 600, cursor: 'pointer',
        }}>Cancel</button>
      </div>
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────
// Sheet primitive
// ─────────────────────────────────────────────────────────────
function Sheet({ children, onClose }) {
  return (
    <div onClick={onClose} style={{
      position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.55)',
      backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
      zIndex: 30, display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
      animation: 'tn-fade 220ms',
    }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: '100%', background: T.surface,
        border: `1px solid ${T.hairlineStrong}`,
        borderRadius: '28px 28px 0 0', padding: '12px 0 0',
        animation: 'tn-slideup 320ms cubic-bezier(.2,.7,.2,1)',
        boxShadow: '0 -20px 60px rgba(0,0,0,0.5)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 14 }}>
          <div style={{ width: 36, height: 4, borderRadius: 2, background: '#333' }}/>
        </div>
        {children}
      </div>
    </div>
  );
}

Object.assign(window, { FansListScreen, FanRow, FanActionSheet, RenameSheet, PairSheet, Sheet, ActionRow });
