---
name: fight-xp-analysis
description: Analyze Tele-Arena party fights from session logs — damage per character, monster HP, XP gained, and XP-per-damage. Use when the user names party members and a monster (or monsters) they fought and asks how much damage/XP each did, how many hit points the monster had, or the XP-per-kill. Reads the per-character session logs in logs/.
---

# Fight XP Analysis

Analyze one or more party fights using the per-character session logs in `logs/`.
The user provides:

- **Party members** (character names) — e.g. "Tojolias, Teekywiki"
- **What they fought** — one or more monsters, in order — e.g. "a chimera, then two skeleton lords"

Each `logs/session-<name>-<timestamp>.log` is one character's point of view and
records *that character's own* attacks. The user creates these logs with the
character name in the filename and runs `status` before/after fights so XP can
be diffed.

## Goal / output

For each monster, report:

1. **Damage each character dealt**, and the per-character hit breakdown.
2. **Monster hit points** = sum of all party members' damage (the party are the
   sole attackers — confirm this assumption with the user if unclear).
3. **XP each character gained** (from `status` before vs. after), and who
   gained the most.
4. **XP per point of damage** for each character.
5. **XP per kill** ≈ clean rate × HP (and cross-checked against the measured
   total XP gained by the party).

A prior worked example lives in `docs/monster-xp-analysis.md` — read it for the
expected output shape and the conclusions it reached.

## Procedure

### 1. Find the logs

Pick the **newest** log per named character:

```bash
cd logs && for n in Name1 Name2; do ls -t session-${n:l}-*.log | head -1; done
```

(Character names in filenames are lowercase.) If a character's fight isn't in
their newest log, check the next newest. Confirm the same fight appears in every
party member's log before trusting the numbers.

### 2. Locate each fight

Logs are raw terminal output with ANSI escapes and binary bytes, so **always use
`grep -a`** (treat as text) or matches are silently skipped. Find fight
boundaries with the monster name and the kill markers:

```bash
grep -an -i "<monster> here\|\[kill\].*Attacking\|falls to the ground lifeless\|<monster> is dead" logs/<file>
```

The user often plants an explicit in-game marker (e.g. a sent message like
`ATTACKING DRAGON` or `FIRST DEAD`) to bracket a fight or separate two same-type
monsters — search for those too. When two monsters of the same type are fought
back-to-back, use the coordination message (and each `... is dead` line) to split
which damage/XP belongs to which kill.

### 3. Read the fight region (strip ANSI safely)

`sed` can choke on binary bytes ("illegal byte sequence"). Strip non-printable
bytes first, then remove ANSI color codes:

```bash
LC_ALL=C sed -n '<start>,<end>p' logs/<file> \
  | LC_ALL=C tr -cd '\11\12\15\40-\176' \
  | sed 's/\x1b\[[0-9;]*m//g'
```

Do this for each party member's log around the same fight.

### 4. Tally damage and XP

- **Damage:** sum each character's own `Your attack hit the <monster> for N
  damage!` lines (use that character's *own* log — it's the source of truth for
  their hits). Ignore "missed", "dodged", and other players' attack lines.
- **XP:** read the `Experience: NNNNN` field from the `status` blocks
  immediately before and after each fight; the difference is that character's
  gain for that fight.

### 5. Compute and present

- Monster HP = Σ damage (displayed).
- XP per kill (measured) = Σ XP gains.
- XP/damage per character = that character's XP gain ÷ their damage.

## The killing-blow overkill caveat (important)

The killing blow's *displayed* damage overshoots the monster's remaining HP, but
XP is awarded only on *effective* damage. So:

- **HP from summed displayed damage is a slight over-estimate.**
- **The character who lands the kill shows a deflated XP/damage ratio** (inflated
  damage denominator). The **non-killer never overkills**, so their XP/damage is
  the clean per-point rate for that fight.

Verify the pattern (it has held in every clean fight observed): the character who
landed the killing blow has the lower raw XP/damage ratio. To report a single
per-point rate and a corrected HP estimate:

```
clean rate      = non-killer's XP gain ÷ non-killer's damage
effective HP    ≈ measured XP per kill ÷ clean rate
XP per kill     ≈ clean rate × effective HP   (cross-check vs. measured Σ XP)
```

## Notes on cleanliness

This works cleanly only when: every party member's log covers the fight, the
party are the sole attackers, and `status` was captured before and after. If any
of those are missing or the logs are messy, say so explicitly and report only
what can be supported, rather than forcing numbers.
