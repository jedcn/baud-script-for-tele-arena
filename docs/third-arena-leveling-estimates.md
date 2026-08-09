# Third Arena — Leveling Estimates to Level 25

Ballpark projection for tojolias, kerhak, and pelayo, extrapolated from one measured
21-minute team session in the third arena on 2026-08-09 (08:45–09:06 EDT).

Source logs:

| Character | Approach leg | The fight | Post-drop tail |
|---|---|---|---|
| kerhak | `logs/session-kerhak-2026-08-09T08-26-56.log` | `logs/session-kerhak-2026-08-09T08-45-04.log` | — (never dropped) |
| pelayo | `logs/session-pelayo-2026-08-09T08-26-58.log` | `logs/session-pelayo-2026-08-09T08-45-03.log` | `logs/session-pelayo-2026-08-09T09-07-02.log` |
| tojolias | `logs/session-tojolias-2026-08-09T08-26-59.log` | `logs/session-tojolias-2026-08-09T08-44-59.log` | `logs/session-tojolias-2026-08-09T09-06-39.log` |

## The measured session

~19 gong summons in 21 minutes — 9 flame giantesses, 7 apollyon dragons, 3 flame giants.

| | XP at start | Peak in-arena | Final kept | Net gained | Heal gold | Loot found |
|---|---:|---:|---:|---:|---:|---:|
| tojolias | 4,955,145 | 5,047,351 | 5,042,624 | **+87,479** | 17 | 70 |
| kerhak | 1,039,038 | 1,120,411 | 1,120,411 | **+81,373** | 129 | 31 |
| pelayo | 3,940,780 | 4,001,793 | 3,993,463 | **+52,683** | 52 | 28 |
| party | | | | **+221,535** | 198 | 129 |

At `09:05:48` both pelayo and tojolias were dropped mid-fight (see
`session-kerhak-2026-08-09T08-45-04.log:3297-3301`). Their XP rolled back to the last
save on reconnect — pelayo lost 8,330, tojolias lost 6,171. The party earned +236,036
but banked only +221,535.

Kerhak's 129 heal gold is 107 in-arena (9 trips) plus one 22-crown heal on the walk home;
the rates below use the in-arena figure.

## Time to level 25

Thresholds from the `xpThresholds` table in `main.lua` (sourced from `help Exp1`/`Exp2`).
Rates are banked XP per minute from the session above.

| | Class | Now | XP needed | XP/min | **Time** | 21-min sessions |
|---|---|---|---:|---:|---:|---:|
| tojolias | Warrior, L20 | 5,042,624 | 6,552,076 → 11,594,700 | 4,226 | **~26 h** | ~74 |
| kerhak | Hunter, L14 | 1,120,411 | 10,474,289 → 11,594,700 | 3,875 | **~45 h** | ~129 |
| pelayo | Acolyte, L18 | 3,993,463 | 9,854,537 → 13,848,000 | 2,582 | **~64 h** | ~182 |

Using the pre-disconnect (no-rollback) rates instead gives ~25 h / ~45 h / ~55 h, so the
honest band is **25–65 hours of arena time**.

Class drives most of the spread. Warrior and Hunter share an identical table (11,594,700
at 25); Acolyte's is ~19% steeper (13,848,000). Pelayo therefore needs the most XP *and*
earns it slowest, since it spends turns healing rather than swinging.

## Gold

Training is a flat **5 gold × new level** — confirmed across the logs at L3=15, L4=20,
L14=70, L17=85, L18=90.

| | Training to 25 | Healing | Corpse loot | **Net gold** |
|---|---:|---:|---:|---:|
| kerhak | 1,100 | ~13,800 | ~4,000 | **~10,900** |
| pelayo | 770 | ~9,700 | ~5,200 | **~5,300** |
| tojolias | 575 | ~1,300 | ~5,200 | **~ −3,400** (profit) |

Gold is effectively a non-issue. Tojolias funds itself and comes out ahead — it rarely
buys healing (pelayo heals it) and loots the most corpses. Kerhak is the only one needing
real money, ~11k crowns over ~129 sessions, and already carries 1,723. Passing gold
between characters makes the party self-sustaining.

## Caveats

- **Healing scales with HP healed**, and max vitality grows every level. Kerhak more than
  doubles its HP pool going 14 → 25, so its per-heal bill rises. Treat ~11k as a floor;
  ~20k is the safer budget.
- **One 21-minute sample.** A single disconnect cost pelayo 8,330 XP (~3 minutes of
  grinding). Across ~182 sessions that matters if it's routine rather than a one-off.
- **The XP rate itself should hold.** Flame giants, flame giantesses, and apollyon dragons
  award fixed XP per kill, so the rate doesn't decay with level as long as the party keeps
  ringing the gong in the third arena.
