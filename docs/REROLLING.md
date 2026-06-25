# Re-rolling for Good Stats

The `re-roll-for-good-stats` alias automates character creation rerolling. Type it to
start, `re-roll-stop` when you're happy with the result.

## How the algorithm works

The Vitality trigger fires after each `reroll` response once all six stats have been
read. It computes a **deficit** — the sum of how far each stat falls below its target
(zero if at or above). When the deficit is at or below the threshold the script stops
and prints the stat summary; otherwise it schedules another `reroll` after 500ms.

Targets and threshold live in `main.lua` around the Vitality trigger. Adjust them
before starting a session.

---

## Half-Ogre Warrior

**Alias:** `re-roll-half-ogre-warrior` (stop with `re-roll-stop`)

**Max stats:** Int=14 Kno=14 Phy=30 Sta=30 Agi=17 Cha=12

**Approach:** Simple hard floors — reroll until Physique >= 29 AND Stamina >= 29
AND Agility >= 15. No deficit math; Int, Kno, and Cha are ignored entirely.
(Agility maxes at 17 for this build, and 15 keeps it in the 15-29 attack tier.)

**Commit:** `dfeddae`

---

## Dwarf Acolyte

**Max stats:** Int=20 Kno=21 Phy=20 Sta=22 Agi=17 Cha=17

**Approach:** Deficit-based — all six stats targeted at their maximums. Stop when
the combined shortfall across all stats is <= threshold. The threshold was tuned
upward several times during play (2 → 3 → 5 → 6) as exact-max proved too rare.

**Final targets:** Int=20 Kno=21 Phy=20 Sta=22 Agi=17 Cha=17, threshold=6

This means a roll within 6 total points of all-maxes was accepted — e.g. one stat
one point shy and another two points shy.

**Commit:** `5b5c048` (targets), `ff7eb40` (final threshold)

---

## Goblin Rogue

**Max stats:** Int=16 Kno=18 Phy=21 Sta=22 Agi=30 Cha=13

**Approach:** Exact match on three stats only. Phy=21, Sta=22, and Agi=30 must all
be at their maximums. Int, Kno, and Cha are ignored (targets=0). Threshold=0 means
no slack on the three that matter.

Roughly 1 in 2,100 rolls satisfies all three simultaneously (~9% each,
independent).

**Final targets:** Phy=21 Sta=22 Agi=30 (Int=0 Kno=0 Cha=0), threshold=0

**Commit:** `9cfa44c`

**Result:** Found after 1,624 rolls — Int=6 Kno=17 Phy=21 Sta=22 Agi=30 Cha=13

---

## Elf Sorceror

**Max stats:** Int=22 Kno=25 Phy=15 Sta=15 Agi=19 Cha=21

**Approach:** Mixed — hard floors on Int=22, Kno=25, and Sta=15 (all must be at max),
plus a combined deficit threshold of 5 for Phy and Cha. Agi is ignored. Vit is excluded
from matching because it is fully determined by Sta.

**Final targets:** Int=22 Kno=25 Sta=15 (exact), Phy+Cha combined deficit <= 5, Agi ignored

**Commit:** `9a25de2`
