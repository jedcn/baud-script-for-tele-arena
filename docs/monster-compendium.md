# Monster Compendium

Per-monster field notes, built from party session logs. Each entry records what
the game actually printed: the monster's own text, what it hit for, what it
dropped, and how much damage the party had to put through it to kill it.

This is the qualitative companion to [monster-xp-analysis.md](monster-xp-analysis.md),
which tracks HP / XP-per-damage / XP-per-kill across many monsters in one table.

## How the numbers are derived

Each `logs/session-<name>-*.log` is one character's point of view and prints a
damage number only for **that character's own** hits — everyone else's attacks
appear as `X just attacked the <monster> with ...` with no number. So a monster's
HP is only knowable when every attacker's log is in hand: sum each character's
own `Your attack hit ...` lines across all of them.

Two caveats apply to every HP figure here:

- **The killing blow overshoots.** Displayed damage on the fatal hit exceeds the
  monster's remaining HP, so a summed total is a slight over-estimate and the
  killer's own total is the inflated part.
- **"Dodged" is counted from the attacker's own log.** `The <monster> dodged your
  attack!` in your log is the same event as `The <monster> barely dodged X's
  <weapon>!` in everyone else's — don't count both.

---

## Arch demoness

**Found:** a complex of natural caverns, alongside a demon king (the two share a
room and are pulled together unless split deliberately).

**Description:** not captured — nobody looked at her before she died.

**Hit points:** **~942** (over-estimate; Kerhak's 63-damage killing blow carries
the overkill).

**Offense:** none observed. She died in four rounds and never landed an attack on
anyone in the party.

**Drop:** 52 gold crowns, searched up by the character who landed the kill.

### Damage breakdown — 2026-09-20, four-character party

| Character | Weapon | Damage | Share | Hits / swings | Per-hit avg |
|---|---|---:|---:|---:|---:|
| Teekywiki | Twin Katanas | 321 | 34.1% | 4 / 4 | 80.3 |
| Tojolias | Wyrmslayer | 279 | 29.6% | 3 / 5 | 93.0 |
| Kerhak | Ecliptic Glaive | 198 | 21.0% | 3 / 4 | 66.0 |
| Pelayo | Hallowed Stick | 144 | 15.3% | 4 / 4 | 36.0 |
| **Total** | | **942** | | **14 / 17** | |

Kerhak landed the killing blow (63).

**XP:** measurable only for Tojolias, the one character who ran `status` on both
sides of the kill — **7,040 XP** for 279 points of damage, i.e. **~25.2 XP per
point**. If that rate is uniform across the party, the demoness is worth roughly
**24,000 XP** split four ways; that is an extrapolation from one sample, not a
measurement.

---

## Demon king

**Found:** a complex of natural caverns, alongside an arch demoness.

**Description:**

> The demon king emanates incredible power and horrific malevolence. He has
> dull black skin and stands over thirty feet tall. He wields a huge glowing
> sabre nearly fifteen feet long and wears a dull grey crown engraved with
> runes.

**Hit points:** **~1,935** (over-estimate; Kerhak's 81-damage killing blow carries
the overkill). Roughly twice the demoness, and nine times a Stygian Dragon.

**Offense:** two attacks, both of which can one-round a mid-level character.

- *Glowing sabre* — melee, hit Kerhak for **184**.
- *Devastating beam of dark energy* — hit Tojolias for **211**. Announced to the
  whole room as `The demon king just discharged a devastating beam of dark energy
  at <target>!`

He needs a dedicated healer: Pelayo spent the fight intoning 385- and 386-point
heals on Kerhak and Tojolias rather than attacking, and still only put in 10.6%
of the damage.

**Drop:** 342 gold crowns, plus a **rod of power** — which nobody could pick up
(`you notice a rod of power, but you can't carry it`), so the kill needs someone
with encumbrance headroom if the rod is the point.

### Damage breakdown — 2026-09-20, four-character party

| Character | Weapon | Damage | Share | Hits / swings | Per-hit avg |
|---|---|---:|---:|---:|---:|
| Kerhak | Ecliptic Glaive | 729 | 37.7% | 11 / 14 | 66.3 |
| Teekywiki | Twin Katanas | 718 | 37.1% | 13 / 14 | 55.2 |
| Tojolias | Wyrmslayer | 283 | 14.6% | 4 / 5 | 70.8 |
| Pelayo | Hallowed Stick | 205 | 10.6% | 9 / 11 | 22.8 |
| **Total** | | **1,935** | | **37 / 44** | |

Kerhak landed the killing blow (81).

Tojolias's 14.6% is not representative: he took the 211-point beam four swings in
and was then locked out for the rest of the fight by `You are still physically
exhausted from your previous activities!`, so he spent it handing out gold. Read
his share as "what one character contributes before being knocked out of the
rotation", not as his damage output.

**XP:** again measurable only for Tojolias — **9,620 XP** for 283 points of
damage, i.e. **~34.0 XP per point**. Note this is a *higher* rate than the
demoness's ~25.2, so XP per point is a property of the monster, not a global
constant. Extrapolated across the party that puts the demon king near **66,000
XP**, with the same single-sample caveat.
