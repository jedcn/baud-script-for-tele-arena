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

## Archive tele-arena.tumblr.com

Download all content from https://tele-arena.tumblr.com/, convert it to Markdown, and save it in a `docs/` directory. The game is over 30 years old and this material could disappear at any time.

Credit the source at the top of each file. The archive should cover at minimum:
- Experience tables per class
- Items available for purchase (shops, prices)
- Spells available (by class, cost, effect)
- Any other reference material (races, stats, maps, commands)

This gives us an offline reference we can query when building out XP tables, spell costs, and other game mechanics — and preserves the history.

### Progress

The conversion approach is documented in [`docs/shrine/conversion-plan.md`](docs/shrine/conversion-plan.md). The index of all known shrine pages (with links to both the live Tumblr URLs and local files where converted) lives in [`docs/shrine/README.md`](docs/shrine/README.md).

Pages converted so far:
- `MAX_STATS.md` — max rerollable stats per class and race (8 classes × 6 races)
- `WEAPONS_ARMOR.md` — best armor and weapon by level for each class/promoted class
- `MAGIC_ITEMS.md` — all items with descriptions and prices
- `SPELLS.md` — full spell lists for Necrolyte, Acolyte, Sorceror, and Druid
- `PROMOTIONS.md` — stat gains at promotion for all 8 classes
- `PROMOTED_EXP_CHART.md` — full 105-level post-promotion XP table

## Scrape In-Game Help

Automate walking through the game's help system:
1. Send `help` — capture the list of keywords from the response
2. For each keyword, send `help <keyword>` — capture and save the output

Store the results in `docs/help/` as one Markdown file per topic. This gives us authoritative in-game documentation that complements the Tumblr archive, covering anything the devs documented directly in the game itself.

## Unified Report

Once the Tumblr archive and in-game help scrape exist, import them into the database and expand `just report` into a single self-contained HTML page that brings everything together:

- Live session data (combat stats, loot, XP, rooms visited, spell heals)
- Reference data from the archive (XP tables, items, spells) cross-linked with what we've actually seen in-game
- In-game help content alongside our own observed data — e.g. the help page for a spell next to how many times we've cast it and what it actually healed

The goal is one page you can open after a session and use both as a debrief and as a reference guide.

## Two-Character Party Script

A separate script for running a two-character party where a human controls the leader and a script controls the supporter.

**Setup:** Leader is a Warrior (human-controlled), supporter is an Acolyte (script-controlled, running its own baud instance).

### Following

This has been implemented:

```
ta.follow <target>
```

### Combat assist

When the supporter sees that the leader has engaged a monster, it:

### Retreat

If the leader flees the fight, or says `retreat` in the room, the supporter:

1. Stops attacking
2. Waits for the leader to leave the room
3. Follows them out

### Out-of-combat heal commands

The leader can say things in the room that the supporter acts on:

- `heal me` → supporter casts heal on the leader
- `heal yourself` → supporter casts heal on itself

### Things to figure out

- How to detect the leader leaving vs. being in the same room during a chase
- Mana management — what does the supporter do if it runs out of mana mid-fight?
- Whether the two baud instances need any coordination beyond watching room text, or if they can operate independently

### Group-status-driven healing

✅ Implemented. The hardcoded `healAllies` list and the "monster attacked an
ally" trigger are gone. Instead an Acolyte sends `group`, reads the listing,
and heals the **most-injured** member (lowest HE%) below 90% (`cast motu
<name>`), parsing lines like:

```
Your group currently consists of:
  Johnsonite                         [HE:100% ST:Ready]
  Tojolias                       (L) [HE: 55% ST:Resting]
  Teekywiki                          [HE: 95% ST:Ready]
```

A scan is triggered two ways: automatically on attack (physical) exhaustion
mid-fight, and on demand via `confer heal.allies` from the leader (works out
of combat too). The listing has no terminator, so the scan waits for the
header then reads member rows until the first non-member line ends it —
combat spam before the listing can't cut it short.

Decisions made: 90% threshold (not "below 100%"); most-injured member wins;
the auto path is gated on Acolyte + active fight (so it works from a manual
`kill`), the confer path on Acolyte + following.

Still open:
- Tie-breaking when two members share the same lowest HE% (currently the first
  one listed wins).
- Whether `ST:Resting`/exhaustion on a member should affect the choice.
- Self-heal when a monster attacks the supporter (`The <monster> attacked you
  ...`).

### Leader-issued commands via group chat

✅ Implemented (allowlist). While following, a line
`From <leader> (to group): <command>` from the current follow leader runs
the command, but only for recognized entries:

- `kill <monster>` → starts the kill loop on that monster
- `heal.allies` → an Acolyte scans the group and heals the most-injured member
  (see Group-status-driven healing above)

The speaker must match `followTarget`, so a follower's own conferred lines and
other members' messages are ignored, as is anything off the allowlist.

Still open:
- Growing the allowlist as we find more commands worth broadcasting.
- Whether the leader should be able to target a specific member rather than
  the whole group.
- Overlap with the auto-join-the-fight triggers: `confer kill <monster>` plus
  the leader's own attack line both fire, but the second is a no-op once a
  kill is already active.
