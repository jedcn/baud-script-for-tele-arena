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
