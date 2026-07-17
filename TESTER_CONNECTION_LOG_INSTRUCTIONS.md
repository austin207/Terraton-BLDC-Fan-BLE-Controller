# Terraton Fan App — Connection Log Capture (Reconnect Bug)

**What we're chasing:** after the app disconnects and reconnects, **Smart Mode** and the
**Sleep Timer** sometimes reset to blank even though the fan is still running in that state.
The app has a built-in **Connection Log** that records every message exchanged with the fan.
One capture of a *failing* reconnect tells us exactly what the fan sent, so we can confirm the fix.

Please follow these steps **exactly** and send back the shared log.

---

## Before you start

- Use the **current app build** (the one where the bug still happens).
- Make sure the fan is connected to **mains power** and working via the remote.
- Do this near the fan, with phone Bluetooth ON.

---

## Steps

**1. Set up the fan state**
1. Open the app and connect to the fan (`lab`).
2. Set the fan to **Gear 6**.
3. Turn on **Smart Mode**.
4. Set the **Sleep Timer to 4 Hours**.
5. Confirm the screen shows: dial around Gear 6, **Smart** highlighted, and a **countdown**
   like `3h 59m … REMAINING`.

**2. Clear the log (so it only captures this test)**
6. Go to **Settings** (bottom-right tab) → scroll down → tap **Connection Log**.
7. Tap **Clear** (empty the log), then go **back** to the fan control screen.

**3. Reproduce the disconnect + reconnect**
8. Press the phone's **Home button** to background the app (this disconnects the fan). Wait **~5 seconds**.
   - *(Alternative if you prefer: fully close/swipe-away the app, wait ~5 s, then reopen it.)*
9. **Reopen the app** and go back to the fan control screen so it reconnects.
10. **Watch the screen** and note what happens to **Smart** and the **timer**:
    - Did Smart stay highlighted, or go blank?
    - Did the timer keep counting down, or disappear / reset?

**4. Capture the log**
11. Go to **Settings → Connection Log** again.
12. Tap **Share** and send the log to me (WhatsApp / email — whatever's easiest).

---

## Please also tell me (one line each)

- **App version** (Settings → bottom of screen, or the version shown on the About/Splash screen).
- **What broke:** e.g. "Smart went blank AND timer disappeared" / "only the timer disappeared" / "both survived this time".
- **Roughly how long** the app was backgrounded before reopening (5 s? 30 s? a minute?).
- Whether the **fan itself kept running** in Smart the whole time (it should have).

---

## Tips for a clean capture

- If the bug **doesn't** happen on the first try, **repeat steps 8–10 two or three times** in the
  same session (don't clear the log again) — the fault is timing-dependent, so a few reconnects
  make it more likely to show up, and the log will hold all of them.
- Don't clear the log between those repeats — we want every reconnect in one capture.
- The log is just text (timestamps + short hex codes); it contains **no personal data**.

Thank you — this single capture is what lets us confirm the exact frame the fan sends on reconnect.
