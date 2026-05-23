// user-manual.jsx — Expandable FAQ-style user manual

const ManIcon = {
  power: ({ s = 20, c = '#7AA7FF' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3v9" stroke={c} strokeWidth="1.8" strokeLinecap="round"/><path d="M18.4 7.6a9 9 0 1 1-12.8 0" stroke={c} strokeWidth="1.8" strokeLinecap="round"/></svg>,
  dial: ({ s = 20, c = '#B68BFF' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke={c} strokeWidth="1.6"/><path d="M12 12l5-4" stroke={c} strokeWidth="1.6" strokeLinecap="round"/><circle cx="12" cy="12" r="1.6" fill={c}/></svg>,
  bolt: ({ s = 20, c = '#FFB400' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill={c}><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8z"/></svg>,
  wind: ({ s = 20, c = '#7AE582' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M4 9h11a3 3 0 1 0-3-3M4 15h13a3 3 0 1 1-3 3M4 12h9" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  timer: ({ s = 20, c = '#7AE582' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="13" r="8" stroke={c} strokeWidth="1.6"/><path d="M12 13V9M10 3h4M19 6l-2 2" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  sun: ({ s = 20, c = '#FFEC00' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="4" stroke={c} strokeWidth="1.6"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  devices: ({ s = 20, c = '#9A9A95' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="13" height="11" rx="2" stroke={c} strokeWidth="1.6"/><path d="M8 20h10M13 16v4" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  help: ({ s = 20, c = '#FF6B6B' }) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke={c} strokeWidth="1.6"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.5" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
};

const MANUAL_SECTIONS = [
  {
    id: 'getting-started',
    label: 'Getting Started',
    icon: ManIcon.power,
    accent: '#7AA7FF',
    body: [
      'Power on your Terraton fan from the wall switch — the indicator LED will pulse yellow.',
      'On first launch, open the Terraton app and enter your name on the Profile Setup screen.',
      'Tap the Fans tile on the Home screen, then tap + to pair a new fan via Bluetooth or QR code.',
      'Once paired, your fan appears in the list and is ready to control.',
    ],
  },
  {
    id: 'speed',
    label: 'Controlling Fan Speed',
    icon: ManIcon.dial,
    accent: '#B68BFF',
    body: [
      'Open any fan from the list to view its control screen.',
      'Drag the yellow knob around the radial dial to set speed from 0 to 6.',
      'The active speed glows yellow; RPM and watt draw update in real time at the center.',
      'Tap a numeral on the ring as a shortcut to jump to that speed.',
    ],
  },
  {
    id: 'boost',
    label: 'Boost Mode',
    icon: ManIcon.bolt,
    accent: '#FFB400',
    body: [
      'Tap BOOST to instantly push the fan to its maximum airflow at speed 6.',
      'The dial visualizes Boost with an intensified glow and a rotating outer halo.',
      'Boost ends when you toggle it off, set a different speed, or power the fan off.',
      'Use Boost briefly — sustained max speed increases power draw and wear.',
    ],
  },
  {
    id: 'modes',
    label: 'Operating Modes',
    icon: ManIcon.wind,
    accent: '#7AE582',
    body: [
      'Nature: gently varies speed to mimic natural breeze patterns.',
      'Smart: learns your usage and adjusts speed based on time-of-day and ambient temperature.',
      'Reverse: spins the blades in the opposite direction to circulate warm air in winter.',
      'Only one mode can be active at a time. Tap the active mode again to turn it off.',
    ],
  },
  {
    id: 'timer',
    label: 'Sleep Timer',
    icon: ManIcon.timer,
    accent: '#7AE582',
    body: [
      'Set a 2H, 4H, or 8H timer to automatically power the fan off after the chosen duration.',
      'The remaining time appears beside the SLEEP TIMER label.',
      'Tap OFF to clear the timer at any time.',
      'Timer settings persist per-fan, so each fan can have its own schedule.',
    ],
  },
  {
    id: 'lighting',
    label: 'Mood Lighting',
    icon: ManIcon.sun,
    accent: '#FFEC00',
    body: [
      'Drag the slider in the LIGHT INTENSITY section to dim or brighten the integrated downlight.',
      'Snap to 0, 25, 50, 75 or 100% using the markers below the slider.',
      'The light state is preserved when you power the fan off — it returns when you power it back on.',
      'Set intensity to 0 to fully turn the downlight off without affecting fan speed.',
    ],
  },
  {
    id: 'managing',
    label: 'Managing Your Fans',
    icon: ManIcon.devices,
    accent: '#9A9A95',
    body: [
      'Long-press any fan card to open the action sheet.',
      'Tap Rename Fan to give it a friendlier name (e.g. "Bedroom Fan").',
      'Tap Remove Device to unpair the fan from your account.',
      'Use Export Fans Data in Settings to back up your setup and schedules.',
    ],
  },
  {
    id: 'troubleshooting',
    label: 'Troubleshooting',
    icon: ManIcon.help,
    accent: '#FF6B6B',
    body: [
      'Fan not responding? Make sure Bluetooth is enabled on your phone and you\'re within ~10 m of the fan.',
      'If a fan shows Disconnected, tap Reconnect when the popup appears, or pull the wall switch off/on.',
      'Firmware out of date? Check Settings → Firmware Support for an in-app update.',
      'Still stuck? Reach out through the contact options provided with your device packaging.',
    ],
  },
];

function UserManualScreen({ onBack, initialOpen }) {
  const [openId, setOpenId] = React.useState(initialOpen || null);
  const toggle = (id) => setOpenId(openId === id ? null : id);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <ScreenHeader title="User Manual" onBack={onBack}/>
      <div style={{
        flex: 1, overflowY: 'auto',
        padding: '0 20px 32px',
        display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        {MANUAL_SECTIONS.map(sec => (
          <ManualSection key={sec.id} section={sec}
            open={openId === sec.id}
            onToggle={() => toggle(sec.id)}/>
        ))}
        <div style={{
          marginTop: 16, textAlign: 'center',
          fontFamily: T.fontMono, fontSize: 10, color: T.textDim, letterSpacing: '0.2em',
        }}>END OF MANUAL · v1.1.0</div>
      </div>
    </div>
  );
}

function ManualSection({ section, open, onToggle }) {
  const Ic = section.icon;
  return (
    <div style={{
      background: T.card,
      border: `1px solid ${open ? 'rgba(255,236,0,0.22)' : T.hairline}`,
      borderRadius: 18, overflow: 'hidden',
      transition: 'all 240ms',
    }}>
      <button onClick={onToggle} style={{
        width: '100%', padding: '16px 18px',
        background: 'transparent', border: 'none', cursor: 'pointer',
        display: 'flex', alignItems: 'center', gap: 14,
        color: T.text, fontFamily: T.font, textAlign: 'left',
      }}>
        <div style={{
          width: 38, height: 38, borderRadius: 12,
          background: `${section.accent}22`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <Ic c={section.accent}/>
        </div>
        <div style={{ flex: 1, fontSize: 15, fontWeight: 700 }}>{section.label}</div>
        <div style={{
          transform: open ? 'rotate(180deg)' : 'rotate(0deg)',
          transition: 'transform 280ms cubic-bezier(.2,.7,.2,1)',
          color: open ? T.yellow : T.textMut,
        }}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M6 9l6 6 6-6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </div>
      </button>
      <div style={{
        maxHeight: open ? 600 : 0,
        overflow: 'hidden',
        transition: 'max-height 380ms cubic-bezier(.2,.7,.2,1)',
      }}>
        <div style={{
          padding: '4px 18px 20px 70px',
          fontFamily: T.font, fontSize: 13, color: T.textMut, lineHeight: 1.6,
        }}>
          <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 10 }}>
            {section.body.map((p, i) => (
              <li key={i} style={{ display: 'flex', gap: 10 }}>
                <span style={{
                  flexShrink: 0, marginTop: 8,
                  width: 4, height: 4, borderRadius: '50%',
                  background: section.accent,
                }}/>
                <span>{p}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { UserManualScreen, MANUAL_SECTIONS });
