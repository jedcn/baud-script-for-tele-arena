# Tutorial

## Quick-Start Overview

1. Choose a Race
2. Choose a Class
3. Reroll for better stats
4. Equip your character
   - Weapons & Armor
   - General items
   - Magic items
   - Spells
5. Head to the Arena

## Introduction

Tele-Arena functions as "a hack & slash fantasy role-playing game" where players explore worlds, defeat monsters, solve puzzles, and gain power. The game distinguishes itself through several key features:

- It operates as a module for MajorBBS bulletin board systems rather than standalone servers, allowing continuous play since the early 1990s across locally-operated systems
- Combat requires deliberate player actions each round without auto-attack functionality, creating more dynamic encounters
- Experience accrues through damage dealt per hit rather than monster kills alone

Players benefit from strategic planning. When starting, you select a race (Elf, Dwarf, Gnome, Human, Goblin, Half-ogre), but should first consider desired class characteristics. "In Tele-Arena, the race you select only determines the minimum and maximum statistics achievable when you roll your new character. There are no other racial bonuses."

## Class Descriptions

**Warriors** rely on physical strength and access the broadest equipment options excluding projectile weapons.

**Sorcerors** cast powerful offensive and utility spells but restrict themselves to robes and staves.

**Acolytes** balance physical combat with curative magic, wielding only bludgeoning weapons.

**Rogues** excel at combat with moderate restrictions and possess special abilities including theft, trap avoidance, wall scaling, and lock-picking.

**Hunters** match warrior combat abilities but with armor restrictions and specialized tracking, hunting, and animal-taming skills.

**Druids** combine melee capability with elemental offense and light healing, restricted to robes or leather armor and blunt weapons.

**Archers** achieve warrior-level combat prowess using projectile weapons exclusively with armor limitations.

**Necrolytes** practice dark magic, matching sorcerer equipment restrictions while gaining power rapidly with limited melee skill.

## Further Class Details

### Spellcasting Considerations

Review the spells list to evaluate each spellcasting class. Early limitations disappear as characters progress and unlock area-of-effect spells.

### Melee Class Abilities

Specialized combat classes possess unique abilities detailed separately. Warriors lack special abilities but access superior equipment.

### Experience Requirements

Different classes demand varying experience amounts for leveling. "Rogues need the least experience, followed by Warriors, Hunters, and Archers. Acolytes and Necrolytes are next, and Sorcerors and Druids require the most."

## Player Attributes/Statistics

**Intellect (INT)** - Determines offensive spell potency and spell resistance.

**Knowledge (KNO)** - Affects spell strength, spell resistance, and rogue-specific abilities like lock-picking, trap detection, wall-climbing, and player theft.

**Physique (PHY)** - Influences melee damage and carrying capacity.

**Stamina (STA)** - Determines starting hit points and leveling vitality gains, providing a STA/5 bonus.

**Agility (AGI)** - Controls running speed before tripping, dodge frequency, and attack frequency per round. Achieving 30 Agility enables a sixth attack.

**Charisma (CHA)** - Adjusts shop prices; low charisma increases costs while high charisma decreases them.

**Vitality** - Hit points representing survivable damage; reaching zero results in character death.

**Mana** - Spellcaster resource for casting spells; different spells require different amounts. "Prior to promotion, Sorcerors and Necrolytes get 2 mana per level, and Acolytes and Druids get 1 mana per level. After promotion, these are doubled."

**Health** - Displays current status effects including hunger, thirst, poison, and overheating.

**Encumberance** - Current weight carried versus maximum capacity; calculated as Physique × 50.

## Recommendations for Races/Classes

**Sorceror & Necrolyte:** Select Elf, Dwarf, Gnome, Human, or Goblin. Prioritize Intellect and Knowledge; Agility helps with defense. Sorcerors access magical attack items beginning at level 3.

**Acolyte:** Choose Dwarf, Gnome, Human, or Goblin. High Agility improves accuracy and defense. Platemail equipment demands significant Physique due to weight (600 encumbrance). Half-ogres are viable with sufficient Physique development.

**Druid:** Select Dwarf, Gnome, Human, or Goblin. Balanced stats work best across Intellect/Knowledge for spells, Physique and Agility for combat, and Stamina for survivability.

**Rogue:** Choose Goblin and attempt rolling 30 Agility for a sixth attack at level 8. Pure melee with skillful attacks resembling critical hits; damage increases with level. Knowledge-based trap avoidance, pit climbing, and lock-picking available. Other races might achieve sixth attacks post-promotion if Agility reaches 25 through leveling.

**Warrior & Hunter:** Select Goblin or Half-ogre. Goblins should roll 27+ Agility for promotion-achieved sixth attack. Half-ogres benefit from 30 Physique and Stamina maximization. Warriors access superior equipment; Hunters face slight restrictions but comparable abilities.

**Archer:** Difficult class requiring Goblin selection with 27+ Agility targeting. Equipment matches rogues but lacks skillful attacks, reducing overall damage. Ranged advantage disappears in indoor arenas.

## Rerolling

After character creation in the North Plaza, access the status command (st) to review statistics and initiate rerolling for improvements. Consider class-specific stat priorities: spellcasters should maximize Intellect and Knowledge, while melee characters prioritize Physique, Stamina, and Agility. "Be willing to have stats that are a point or two lower than the max. If you are a spellcaster, try to get maximum Intellect and Knowledge, and let the rest be less than perfect."

Restart completely by typing suicide if dissatisfied with race/class selections.

## Equipping Your Character

Navigate to the Armor Shop (south, then west from North Plaza). First-level characters wear robes exclusively. Purchase with (b robes) and equip with (eq robes). Armor Class increases from 0 to 1.

Move to the Weapon Shop (east, east) and purchase appropriate weapons:

| Class | Weapon |
|-------|--------|
| Warrior | Warhammer |
| Hunter | Warhammer |
| Acolyte | Warhammer |
| Druid | Warhammer |
| Rogue | Shortsword |
| Archer | Shortsword, Shortbow |
| Sorceror | Staff |
| Necrolyte | Staff |

Proceed to the Magic Shop (west, south from Weapon Shop). Purchase healing potions (rue or amaranth), stat-boosting potions (rowan, hyssop), and a glowstone for permanent light.

Visit the Equipment Shop (north, north, northwest) and acquire waterskin, rations, rope (unnecessary for rogues), and relevant ranged weaponry.

## Buying Spells

Spellcasting classes proceed north to the Guild Hall. View available spells via (ls a1, ls s1, ls d1, ls n1) for acolyte, sorceror, druid, and necrolyte respectively. Spell level eligibility requires character level equaling twice the mana cost.

First-level spells available:

| Class | Spell |
|-------|-------|
| Sorceror | Komiza |
| Druid | Pakaza and Fadi |
| Necrolyte | Teka |
| Acolyte | Motu |

## Playing the Game

The Arena (east from North Plaza) serves as primary training ground. Summon monsters with (ri g). Attack via (a monsterName) or abbreviations. Spellcasters cast with (c spellname targetName). Monitor vitality continuously to avoid death.

Status commands include:
- (he) - abbreviated health information
- (st) - full statistics
- (gr) - group information showing health percentage and status

Attack readiness cycles every 15 seconds; spell cooldowns extend to 30, 45, or 90 seconds. Healing options include potions (drink potionName), acolyte/druid self-healing spells, or Temple healing (west, west; b healing).

## Experience and Leveling Up

Experience accumulates through attacks and spellcasting. Check progress via (ep) for current level and experience totals. Training eligibility begins when reaching the next level's experience requirement, accessed at the Guild Hall through (b training).

Training cost formula: next level × 5 (level 2 costs 10 gold). Stats must remain unaffected by temporary boosts or drains for training eligibility.

Level-up benefits include vitality increases (class and Stamina/5 bonus), mana gains for spellcasters, and random stat increases (capped at 25).

Experience thresholds for Level 2:

| Class | Experience |
|-------|------------|
| Warrior | 1125 |
| Hunter | 1125 |
| Archer | 1125 |
| Rogue | 1120 |
| Acolyte | 1150 |
| Necrolyte | 1150 |
| Druid | 1180 |
| Sorceror | 1180 |

## Miscellaneous Info/Tips

**Falling:** Rapid room transitions risk tripping based on Agility. Tripping causes 50% chance of dropping inventory items; inspect rooms after tripping via (g itemName) for retrieval.

**Mirror, Mirror:** Visit the Tavern (northeast from North Plaza) and type (gaze mirror) to preview your appearance as other players perceive you, determined by stats and equipment.

**Traps:** Numerous rooms contain armed traps dealing damage upon entry; repeated entries increase damage. Rogues can detect and avoid traps. Avoid logging out in trap rooms to prevent additional damage upon return.

**Getting Lost:** Site maps assist navigation; purchase Heartstones (100 gold, Magic Shop) for teleportation to Temple at 1% experience cost if lost.

**BBS Stuff:** Check online players via (#), see in-game characters with (pl), access global chat via ('), exit game via (x), or log off immediately via (=x). Logging out during combat allows monsters free attacks.

**Runes:** Achievement markers enabling access to later game areas; see Runes page for details.

---

Contact: tele-arena (at) outlook.com
