# Observed Promotion: Dwarven Acolyte L25 → High Priest L1

A live `st` / `buy promotion` / `st` capture. Confirms the numbers in
[shrine/PROMOTIONS.md](shrine/PROMOTIONS.md) and shows how temporary stat
potions distort the "before" reading.

## Raw comparison

| Field | Acolyte L25 | High Priest L1 | Δ |
|-------|------------|----------------|---|
| Level | 25 | 1 | reset |
| Experience | 13,900,978 | 0 | reset |
| Intellect | 21 | 24 | **+3** |
| Knowledge | 22 | 25 | **+3** |
| Physique | 26 | 22 | −4 (see below) |
| Stamina | 20 | 22 | **+2** |
| Agility | 38 | 21 | −17 (see below) |
| Charisma | 17 | 17 | — |
| Mana | 25 | 52 | **+27** (×2, +2) |
| Vitality | 603 | 798 | **+195** (+32.3%) |
| Armor Rating | 0 | 0 | — |
| Weapon | Celestial Maul | Celestial Maul | — |
| Armor | Cloak | Cloak | — |
| Encumberance max | 1000 | 1100 | +100 |
| Encumberance carried | 425 | 225 | −200 |

## The Physique/Agility "losses" are potions wearing off

The pre-promotion `st` was taken with potion boosts active. Promotion applies
its gains to the **base** stat, so the after-picture is base + gain, and the
temporary boost is simply gone.

Reconstructing the base stats:

| Stat | Shown before | Boost | Real base | Shrine gain | Predicted | Actual |
|------|-------------|-------|-----------|-------------|-----------|--------|
| Intellect | 21 | — | 21 | +3 | 24 | **24** ✓ |
| Knowledge | 22 | — | 22 | +3 | 25 | **25** ✓ |
| Physique | 26 | +6 (Rowan) | 20 | +2 | 22 | **22** ✓ |
| Stamina | 20 | — | 20 | +2 | 22 | **22** ✓ |
| Agility | 38 | +20 (Hyssop) | 18 | +3 | 21 | **21** ✓ |

Every stat lands exactly on the shrine's published Acolyte → High Priest row
(`+3 / +3 / +2 / +2 / +3`) once the potions are backed out.

**Independent confirmation from encumbrance.** Max encumbrance is
Physique × 50 ([shrine/TUTORIAL.md](shrine/TUTORIAL.md)):

- Before: 1000 / 50 = Physique **20** — the *base*, not the displayed 26.
- After: 1100 / 50 = Physique **22** — matches the displayed value.

So the encumbrance cap already ignored the Rowan boost before promotion. The
potion inflates the `st` line but buys no carrying capacity.

Rowan Potion is a strength boost of 5–20 for 600s and Hyssop Potion an agility
boost of 5–20 for 600s ([shrine/MAGIC_ITEMS.md](shrine/MAGIC_ITEMS.md)), so
+6 Physique and +20 Agility are both in range — Agility at the cap.

## Mana

The shrine says a spellcaster's mana pool doubles on promotion, and that a High
Priest gains 2 MP per level. 25 × 2 = 50, +2 for the level = **52**. Matches.

## Vitality

+195 HP (603 → 798). The shrine describes this as a class-average top-up that
ignores your stats, to bring a character with poor per-level HP rolls back up
to par — so this figure is not necessarily reproducible for another Acolyte.

## Carried weight

Carried encumbrance dropped 200 (425 → 225) with weapon and armor unchanged.
The most likely explanation is the gold paid for the promotion leaving the
inventory, since coins have weight. Not confirmed here.

## Note for this repo

The training hall refuses a potion-tainted character (see
[shrine/PROMOTIONS.md](shrine/PROMOTIONS.md) workflow notes and the
`buy restoring` handling in the script), but `buy promotion` clearly went
through with both a Rowan and a Hyssop boost active. **Promotion does not
appear to be gated on potion taint the way training is** — it just quietly
computes from base stats, so the boosts are wasted rather than blocking.

## Caveats

- Single observation, one race/class pair (Dwarven Acolyte).
- The boost sizes are inferred from the arithmetic, not from a potion-quaff
  line in the log. Base Agility 18 sits 1 above the Dwarf Acolyte reroll max of
  17 in [shrine/MAX_STATS.md](shrine/MAX_STATS.md), so something else may have
  contributed a permanent point.
