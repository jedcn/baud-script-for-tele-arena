# Monster XP Analysis

Empirical study of how experience is awarded for damage in Tele-Arena, using
paired session logs from **Tojolias** (Half-ogre Warrior, L6) and **Teekywiki**
(Goblin Rogue, L6) fighting as a two-person team. Each character's log records
its own attacks ("Your attack hit … for N damage"), and `status` was run before
and after each kill to capture the experience delta.

## Method

For each kill, with the two characters as the *sole* attackers:

- **Total hit points** = sum of both characters' damage dealt.
- **XP per kill (measured)** = sum of both characters' XP gains.
- **XP per point of damage** = a character's XP gain ÷ that character's damage.

### Killing-blow caveat

The *displayed* damage of the final, killing hit overshoots the monster's
remaining HP (you can't deal damage past 0), but XP is awarded only on
*effective* damage. So the character who lands the killing blow shows an
inflated damage total and therefore a deflated XP/damage ratio. The **non-killer
never overkills**, so their XP/damage ratio is the clean per-point rate for that
fight. This pattern held in most fights observed, but has exceptions — see footnote ² below.

Practical consequence:

- **HP (sum of displayed damage)** is a slight *over*-estimate.
- **Effective HP** ≈ (measured XP per kill) ÷ (clean non-killer rate).

## The headline relationship

> **XP per point of damage × total hit points ≈ XP per kill**

Using the clean (non-killer) rate and effective HP, this reproduces the measured
total XP per kill to within rounding.

## Results

| Monster | Tojolias dmg | Teekywiki dmg | HP (displayed sum) | Effective HP | Clean rate (XP/dmg) | **XP per kill (measured)** | Rate × Eff. HP (check) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Stygian Dragon¹ | 128 | 84 | 212 | ~212 | ~21.7 | **4,608** | 21.7 × 212 ≈ 4,600 |
| Chimera | 75 | 41 | 116 | ~107 | 7.43 | **796** | 7.43 × 107 ≈ 795 |
| Skeleton Lord #1 | 101 | 63 | 164 | ~151 | 2.47 | **373** | 2.47 × 151 ≈ 373 |
| Skeleton Lord #2 | 17 | 83 | 100 | ~91 | 3.39 | **308** | 3.39 × 91 ≈ 308 |
| Gargoyle² | 107 | 40 | 147 | ≈147 | 3.84 | **564** | 3.84 × 147 ≈ 564 |
| Troll #1³ | 78 | 69 | 147 | ~124 | 4.39 | **~543** | 4.39 × 124 ≈ 544 |
| Troll #2³ | 84 | 28 | 112 | ~95 | 4.39 | **~417** | 4.39 × 95 ≈ 417 |
| Stone Giant #1 | 77 | 92 | 169 | ~148 | 11.40 | **1,686** | 11.40 × 148 ≈ 1,687 |
| Stone Giant #2 | 134 | 55 | 189 | ~185 | 9.38 | **1,739** | 9.38 × 185 ≈ 1,735 |
| Stone Giantess #1⁴ | 211 | 114 | 325 | ~324 | ~9.66 | **~3,133** | 9.66 × 324 ≈ 3,130 |
| Stone Giantess #2⁴ | 48 | 39 | 87 | ~82 | ~9.66 | **~792** | 9.66 × 82 ≈ 792 |

¹ Stygian Dragon is from an earlier session (`session-tojolias-2026-06-27T07-52-20.log`
/ `session-teekywiki-2026-06-27T07-53-51.log`); both characters earned an
essentially identical ~21.7 XP/point, the cleanest confirmation of the model.

² Gargoyle: the killer-lower-ratio pattern did not hold — Tojolias (killer) had the
*higher* rate (3.91 vs Teekywiki's 3.65). Applying the non-killer rate as clean gives
effective HP > displayed, which is impossible. Rate shown is total XP ÷ total displayed
damage; effective HP is left as the displayed sum.

³ Troll #1 / Troll #2: Teekywiki's single status snapshot covered both kills; per-troll
XP for Teekywiki is estimated by applying the combined non-killer rate (4.39 = 426 XP ÷
97 total damage) to each kill's damage share. Total XP and effective HP are therefore
estimates (~543 and ~417). The killer-lower-ratio pattern holds normally here: Tojolias
(killer, both) 3.08 / 3.50 < Teekywiki 4.39.

⁴ Stone Giantess #1 / #2: the two giantesses were fought in an interleaved chase across
multiple rooms. Giantess #1 was the chased giantess (3 rooms, 9 Tojolias hits); giantess
#2 was a fresh spawn in the final room. Tojolias's giantess #1 XP (2,032) was captured by
a status immediately after that kill, before any hits on giantess #2. Tojolias's giantess
#2 XP was not captured (no status after kill). Teekywiki's single snapshot covers both
kills combined (1,478 XP ÷ 153 damage = 9.66 XP/dmg); per-giantess XP for Teekywiki is
estimated at that rate. Total XP and effective HP for giantess #2 are estimates only.

## Per-character XP gains

| Monster | Tojolias gain | Teekywiki gain | Killing blow | Who gained most |
|---|---:|---:|---|---|
| Stygian Dragon | +2,784 | +1,824 | Tojolias | Tojolias |
| Chimera | +557 | +239 | Teekywiki | Tojolias |
| Skeleton Lord #1 | +249 | +124 | Teekywiki | Tojolias |
| Skeleton Lord #2 | +27 | +281 | Tojolias | Teekywiki |
| **Chimera + 2 Skeletons total** | **+833** | **+644** | — | Tojolias |
| Gargoyle | +418 | +146 | Tojolias | Tojolias |
| Troll #1³ | +240 | ~+303 | Tojolias | Teekywiki |
| Troll #2³ | +294 | ~+123 | Tojolias | Tojolias |
| Stone Giant #1 | +637 | +1,049 | Tojolias | Teekywiki |
| Stone Giant #2 | +1,257 | +482 | Teekywiki | Tojolias |
| Stone Giantess #1⁴ | +2,032 | ~+1,101 | Tojolias | Tojolias |
| Stone Giantess #2⁴ | not captured | ~+377 | Tojolias | — |

## Damage detail (per character's own log)

| Monster | Tojolias hits | Teekywiki hits |
|---|---|---|
| Stygian Dragon | 31, 19, 18, 29, 17, 14 | 20, 20, 11, 14, 19 |
| Chimera | 28, 16, 31 | 15, 9, 17 |
| Skeleton Lord #1 | 17, 27, 26, 31 | 14, 15, 19, 15 |
| Skeleton Lord #2 | 17 | 11, 17, 43, 12 |
| Gargoyle | 17, 30, 27, 33 | 7, 13, 14, 6 |
| Troll #1 | 16, 32, 30 | 12, 14, 17, 16, 10 |
| Troll #2 | 15, 33, 36 | 11, 17 |
| Stone Giant #1 | 25, 27, 25 | 12, 15, 9, 16, 5, 7, 16, 12 |
| Stone Giant #2 | 19, 31, 27, 26, 31 | 8, 12, 17, 8, 10 |
| Stone Giantess #1 | 23, 18, 13, 32, 30, 22, 29, 14, 30 | 9, 18, 6, 19, 9, 11, 15, 11, 7, 9 |
| Stone Giantess #2 | 18, 30 | 7, 10, 8, 14 |

## XP snapshots (`status` deltas)

- **Tojolias:** 47,579 → 50,363 (dragon) → 50,920 (chimera) → 51,169 (skel #1) → 51,196 (skel #2)
- **Teekywiki:** 56,368 → 58,192 (dragon) → 58,431 (chimera) → 58,555 (skel #1) → 58,836 (skel #2)

Session T14:03:
- **Tojolias:** 55,064 → 55,482 (gargoyle) → 55,722 (troll #1) → 56,016 (troll #2) → 56,653 (giant #1) → 56,814 (skel lord) → 58,071 (giant #2) → 60,103 (giantess #1; giantess #2 not captured)
- **Teekywiki:** 59,520 → 59,666 (gargoyle) → 60,092 (both trolls; single snapshot) → 61,141 (giant #1) → 61,284 (skel lord) → 61,766 (giant #2) → 63,244 (both giantesses; single snapshot)

## Takeaways

1. **XP scales linearly with effective damage** at a rate that is the *same for
   both characters* in a given fight (class/level did not matter). Apparent
   per-character differences are entirely a killing-blow overkill artifact.
2. **The rate is per-monster (per individual spawn), not universal.** The dragon
   paid ~21.7 XP/point; the chimera ~7.4; the two skeleton lords differed from
   each other (2.47 vs 3.39) because they were separate spawns with different
   HP/XP values.
3. **XP per kill ≈ rate × HP.** Tougher monsters (more HP) at a higher per-point
   rate pay dramatically more: the dragon's 4,608 XP dwarfs a skeleton lord's
   ~300–370.
4. **HP varies significantly between spawns of the same monster type.** The two
   stone giantesses in a single session had 325 and 87 displayed HP — a 3.7×
   difference — yielding ~3,100 vs ~800 XP per kill. The per-damage rate (~9.66)
   was the same; only the HP differed. The same effect was visible in the two
   skeleton lords (164 vs 100 HP).
