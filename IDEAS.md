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

## Room Mapping — next phase

The mapper (rooms/exits/areas in `ta_db.lua`, `just report` graph) now has
mapping mode (`map-on`/`map-off`), auto-`ex` on each move, and loop closure:
when you arrive via an unwalked edge into an already-known room, it fingerprints
the room by **name + exit-set** and folds the provisional duplicate into the
existing one. Its design is adapted from Mudlet's bundled `generic_mapper`
(`~/src/Mudlet/src/mudlet-lua/lua/generic-mapper/`), whose `check_room` /
`find_link` / `find_me` we studied. Three of its ideas are deferred:

### Manual "I'm in room N" assert — BUILT (`map-here <slug>`)

`map-here <slug>` force-anchors at a known room: it turns mapping on and sets
currentRoomId / currentRoom / currentAreaId / coord from the room's stored row,
with no reprint or name resolution, so the next move dead-reckons from the right
place. This is the escape hatch for resuming in an **ambiguous** room (every
`cave` shares a name, so `map-on`'s name lookup can't pick the right one) and it
also guarantees the correct area is inherited (vs. a null area on a cold start
with no `map-area`). Unknown slug is a no-op with a message.

**Deferred enhancement — verify before anchoring.** Today `map-here` trusts the
slug blindly; asserting the wrong room silently corrupts the map. Make it check
the *live* room against the record before committing: on `map-here filthy-cavern`
send `look`/`ex`, and when the room brief + `Exits:` return, compare the **name +
exit-set** to what's stored for that slug. On match, commit the anchor; on
mismatch, bail with `Cannot begin mapping! This location doesn't match what's on
record for <slug>` and stay un-anchored. Key on name + exit-set (both exact and
stable — `ex` lists a locked-door direction regardless of lock state, so no false
alarms); treat the stored description as a soft signal only (wrapping / partial-
capture noise), maybe surfaced in the mismatch report but not gating. Cost: this
makes `map-here` async — the confirm/reject prints a beat later when `ex`
returns, instead of instantly. (User's idea, 2026-07-05; deferred, not urgent.)

### Relocate when lost (`find_me`)

On cold start / after a recall or teleport, `resolveColdStart` picks by unique
name and otherwise takes the first same-named room — a guess when the name is
ambiguous. Mudlet's `find_me` instead does a global fingerprint search: use the
exit-set (from the auto-`ex`) to pick the *right* existing room rather than
guessing, and flag when it still can't tell.

### Retag the current room's area

`retag-area <slug>` to set the area of the room you're standing in. `map-area`
only stamps an area on rooms at *discovery* time, so you must switch areas
*before* stepping across a boundary — impractical when you don't know you're
entering, say, the mountains until you've arrived. A retag-in-place command
fixes the boundary room after the fact (area is otherwise only set at discovery
and never revisited).

**Related bug (observed 2026-07-09, desert).** Running `map-area desert The
Desert` mid-walk did *not* propagate to rooms discovered *afterward* — the
expectation is that once you set the area, every newly-discovered room inherits
it and you only hand-fix the ones visited before the command. Instead only the
first room (crude-stone-building, id 538) ended up desert while everything
discovered later (539–549) stayed sewers, so `map-area` isn't reliably setting
the "current area" that discovery reads from. Worth confirming whether
`map-area` updates `currentAreaId` (used at discovery) at all, or only writes
the areas row / one room. Low priority; the whole desert region was retagged by
hand for now.

### Systemic desync guard — validate a move against the room's known exit-set

Every "stop everything, delete corruption" incident so far (pit-trap fall,
`You at ...` broken brief, `look <dir>`, rest-rejection) has been the SAME
failure: the mapper's `pendingDirection`/position drifts from reality and it
mints a phantom room. We've fixed each *trigger* one at a time. A single
systemic guard would catch the whole class at the source: when about to mint a
new room by walking `dir` from room X, first check that `dir` is in X's recorded
exit-set (from its `ex`). If it isn't — e.g. `215 se→` when 215's exits are only
`e,w` — the move is a provable desync: refuse to mint, and re-resolve by
name/coord (or clear pendingDirection and treat as a re-scan) instead of
inventing a room through an exit that doesn't exist. Caveat: only applies when
X's exit-set is known (ex captured); skip the guard otherwise. Reach for this if
incidents keep happening after the per-trigger fixes — decide once we've mapped
~2 new regions cleanly (if they're clean, the per-trigger fixes sufficed).

### Cosmetic: de-collide overlapping rooms on the rendered map

Two topologically-distinct rooms can dead-reckon onto the same grid cell, so the
World Map renders them on top of each other. **The underlying data is correct —
this is purely cosmetic**, so there's no rush and nothing to delete/merge.

Known instance: **town-sewers-145 (id 508)** and **town-sewers-167 (id 532)** both
land at `(11,1,-3)`. 145 is 140's NE dead-end (`{sw}` back only); 167 is 160's NW
through-room (`{ne,se}`). They share no edge — only the dead-reckoned coordinate.
Verified in-game that 140 genuinely has a NE exit, and the mapper can't mis-merge
them (identity is by exit-set; coordinate-only matching was removed in `aa16520`).

The fix belongs in the **renderer** (`report.ts`), not the DB: `report.ts` ignores
stored `x/y/z` and re-derives layout from topology + relaxation, so the overlap is
a relaxation artifact. Detect when two rooms resolve to the same layout cell and
nudge one into an adjacent free cell for display only. Do NOT edit stored
coordinates — each room's coordinate is individually-correct dead-reckoning, and
changing one corrupts the cursor future moves reckon from.

## World Map Improvements

Two related upgrades to how the World Map presents rooms.

### De-emphasize filler rooms, emphasize unique ones

Most rooms are the same room repeated over and over — a `cave`, a `cavern`, a
`forest path` — with nothing to distinguish them but their id. They dominate the
World Map visually and drown out the handful of rooms that actually matter (named
landmarks, shops, boss lairs, locked-door junctions). When rendering the map,
either **de-emphasize** the repeated filler (dim/shrink/desaturate rooms whose
name recurs many times) **or** **emphasize** the genuinely unique ones (rooms
with a one-of-a-kind name, or otherwise flagged as significant) so they stand out.

Things to figure out:
- How to classify "filler" vs. "unique" — probably by name-frequency across the
  map (a name that appears N+ times is filler), possibly combined with an
  explicit "significant" flag on rooms we care about.
- Which visual treatment reads best: dimming the common rooms, brightening the
  rare ones, or both.
- Whether to let the threshold be tunable, since a name common in one region may
  be rare overall.

### Associate fixed monsters with rooms and surface them in the side panel

Some monsters wander in randomly, but others **always** occupy a specific room —
e.g. the **Stygian Dragon** is always in the **enormous cavern**. These fixed
spawns often gate progression: the first time the Stygian Dragon is killed each
day it **always** drops the **electrum key**, which is **always required** to
open the door to the north of that room.

Make it possible to associate one or more monsters with a given room, record what
they carry / what it unlocks, and pull that information up in the room side panel
so I can see, when looking at a room, "this room always contains the Stygian
Dragon, which drops the electrum key (first kill of the day) → opens the north
door."

Things to figure out:
- Where fixed monster/room associations live (a new table keyed by room id, or an
  extension of the existing room record).
- What to store per association: monster name, guaranteed drop, drop condition
  (e.g. "first kill of the day"), and what the drop is for (which door/lock it
  opens).
- How the side panel renders it, and whether to cross-link the drop to the room
  whose locked door it opens (we already draw locked-door badges — tie the key to
  the door).
- Whether "first kill of the day" state should be tracked live (have we already
  taken the key today?) or just documented.
