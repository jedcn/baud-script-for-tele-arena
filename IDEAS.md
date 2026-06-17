# Ideas

## Casting Healing while Fighting

When the current character is Pelayo and the arena automation is actively fighting (not fleeing to buy healing), automatically cast `cast motu pelayo` during combat.

After casting, the server may respond with:

```
You are still too mentally exhausted from your last incantation!
```

When that line appears, wait and try again. Keep casting until the fight ends or the arena state transitions to fleeing.

Things to figure out:
- How long to wait between retry attempts
- Whether mana tracking is reliable enough to skip the cast when at 0 mana
- Whether to suppress casting during certain arena states (e.g. mid-flee, tavern queue)

## Timed Experience Checks

On a repeating timer, echo a timestamp to the session log and send `status`. When the XP reading comes back, compare it to the XP from the previous tick and echo the difference — something like:

```
[XP check] 14:32:01 — XP: 4821 (+143 since last check)
```

This gives a running record in the session log of experience gained per interval, making it easy to see how fast XP is accumulating during an arena session.

Things to figure out:
- What interval to use (e.g. every 5 minutes)
- Whether to skip the delta on the very first tick (no prior value to compare against)
- Whether to also record this to the database for longer-term trending

## Per-Class Experience Tables

Capture the character's class from the game output (known so far: Acolyte, Warrior) and store it in `taPackage.character.class`.

There are roughly 6 classes total, and each has its own XP-per-level table. Right now `getXpForNextLevel` presumably uses a single table; it should branch on class so the "XP to next level" value shown in the status bar and timed XP checks is accurate for the active character.

The class appears in the `status` output, e.g.:

```
Race:         Dwarven
Class:        Acolyte
Level:        3
```

So a trigger on `^Class:\s+(\w+)$` would capture it whenever `status` is sent.

Things to figure out:
- Whether to look up all 6 class XP tables from the game docs or derive them empirically from observed level-up events
