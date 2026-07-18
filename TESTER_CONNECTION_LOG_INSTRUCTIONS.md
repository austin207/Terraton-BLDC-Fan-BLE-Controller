# Terraton Fan App — Connection Log Capture (Reconnect Bug)

**What we're chasing:** after the app disconnects and reconnects, **Smart Mode** and the
**Sleep Timer** reset to blank even though the fan is still running in that state.

**This build contains a fix for a confirmed cause of that bug**, and it also records a lot more
detail in the built-in **Connection Log**. So there are two things to do:

1. Tell us whether the bug still happens.
2. **Send the log either way** — working or not. If it's fixed, the log confirms it's fixed for
   the right reason. If it isn't, the log now shows us exactly which step failed, which the
   previous builds could not.

Please follow these steps **exactly**.

---

## Before you start

- Use the **new build** we just sent (check the version in Settings matches).
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

> Please do step 1 on this build at least once even if everything looks fine — it refreshes the
> app's saved record of the fan, which older builds may have corrupted on your phone.

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

> On reconnect the dial may be blank for **up to ~12 seconds** before Smart and the gear reappear.
> That gap is expected — the app now refuses to trust the fan's very first answer at all. It asks
> twice, and only draws Smart/the timer once the fan gives the **same answer a second time**.
> If the fan never gives a clean second answer, the app deliberately leaves the screen blank
> rather than guess — so a blank screen that never fills in, while the log shows repeated
> "unanswered" polling, is itself useful diagnostic information, not just a failure.
> What matters is the state **after** that gap.

**4. Capture the log**
11. Go to **Settings → Connection Log** again.
12. Tap **Share** and send the log to me (WhatsApp / email — whatever's easiest).

---

## What's in the log now

The lines starting with `MS` are new and are the most important part of this capture. Each one is
the app asking the fan "what state are you in?" and recording the answer. Instead of trusting the
fan's first answer, the app now asks **at least twice** and only shows Smart/the timer once two
answers in a row **agree**. So you'll see, per reconnect: an answer logged as a candidate, then
either a second line saying it **agrees → applied** (the screen updates) or, if the fan never gives
a clean repeat answer in time, a line saying **session expired — nothing applied** (the screen
stays blank on purpose). Both outcomes are useful to us — a repeated "nothing applied" with the fan
still spinning correctly tells us the fan simply isn't answering reliably, which is a different
problem than the app misreading a correct answer.

---

## Please also tell me (one line each)

- **Did the fan itself keep spinning in Smart** the whole time, while the app showed it blank?
  **This is the single most useful answer** — it tells us whether the app misread the fan, or the
  fan genuinely forgot the mode. Please answer it even if you're not sure.
- **What the app showed:** e.g. "Smart went blank AND timer disappeared" / "only the timer
  disappeared" / "both survived this time".
- **App version** (Settings → bottom of screen).
- **Roughly how long** the app was backgrounded before reopening (5 s? 30 s? a minute?).

---

## Tips for a clean capture

- If the bug **doesn't** happen on the first try, **repeat steps 8–10 two or three times** in the
  same session (don't clear the log again) — the fault is timing-dependent, so a few reconnects
  make it more likely to show up, and the log will hold all of them.
- Don't clear the log between those repeats — we want every reconnect in one capture.
- The log is just text (timestamps + short hex codes); it contains **no personal data**.

Thank you — this capture is what lets us confirm the fix against your fan's firmware, which we
cannot reproduce here.
