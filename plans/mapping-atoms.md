# Mapping atoms: what a room or exit can *be*

**Goal.** Find the atomic game elements a mapper must capture, by surveying the
shrine's hand-drawn maps for the whole world before building anything. The
question is not "what features should we add" but "what is the vocabulary of
things a room or an exit can be". Feature ideas are parked separately in
`add-display-panel-api-to-baud.md`; this file is the vocabulary.

**The test for an atom.** It changes what you can do or where you can go, and
the exit graph alone cannot express it. A room being north of another is
topology. A room containing a lever that disarms a trap twenty rooms away is an
atom.

## Why this matters more than it first looks

The world's non-topological mechanics are currently encoded as **imperative
route steps in `ta_nav.lua`**, not as facts in the database. The routes hard-code
`pull lever` (9), `push stone` (5), `say arok` (2), `say komi` (1),
`killAll untilFound "<key>"` (10), `door` probes (4), `seam` (3) and `dark`.

Meanwhile `room_notes` — the table CLAUDE.md describes as existing for exactly
this, "remote couplings the graph can't express" — holds **0 rows**.

So every route is a hand-copied walk that works, and none of what it knows is
queryable. Two characters cannot share it, the renderer cannot draw it, and a
re-walk cannot verify it. Getting the atoms right is what would let routes be
*derived* rather than transcribed.

## Inventory so far

From towns 1-2 and dungeon levels 1-3, plus what navigation already needed.

### Room-scoped

| atom | evidence | captured today |
|---|---|---|
| **Trap** — type, damage, remedy item | shrine `[t]`/`[p]`/`[f]`, "(bring rope)", "(bring verbenas)", "does up to 180 damage" | `rooms.trap`, a bare name |
| **Guardian** — fixed monster, count, what it drops | shrine `[c]` "Stone Giantess(2)", "Cyclops (Silver Key)" | nothing; `monsters` is encounter stats with no room link |
| **Item in place** — e.g. the White Rune | shrine `[*]` | nothing; `item_drops` is monster-scoped |
| **Device** — lever, protruding stone, spoken word | `ta_nav.lua` route steps; `docs/hidden-stone-teleport.md` | nothing in the DB; hard-coded in routes |
| **Spawn point** | town 1 `*` = "new players start here" | nothing |
| **Darkness** | labyrinth level 2 is intentionally dark; light does not help | `dark = true` on a nav route only |

### Exit-scoped

| atom | evidence | captured today |
|---|---|---|
| **Locked door** — material, key, and whether it re-locks per player | shrine `#`; unlock lines; descriptions | `lock_door`/`lock_key`, demonstrably unreliable; no shared/personal flag |
| **Hidden exit** — the room's description denies it | `enormous-natural-cavern`: "the only exit is to the west", but it has a north door | nothing |
| **Teleport edge** — `push stone` moves you to an otherwise unreachable room | `docs/hidden-stone-teleport.md`, stonework-corridor-28 | nothing; a documented mapper blind spot |

### Remote couplings — the hard class

| atom | evidence | captured today |
|---|---|---|
| **Device acts elsewhere** | "you feel the floor vibrate faintly"; a lever that arms or disarms a distant trap; `say komi` opens a door in another room | nothing; `room_notes` exists for it and is empty |
| **Device state vs map fact** | the whole world resets daily — levers, stones and doors all revert; within a day one character's action serves everyone | nothing |

The last two are the reason this survey is worth doing before building. A
coupling is an edge between two rooms that is not an exit, and nothing in the
schema can hold one.

### The daily reset splits the data in two

The user confirmed on 2026-09-07 that **everything resets daily and nothing is
permanent**. That is not a detail about levers; it is a line through the whole
model:

- **Map facts** — there is a lever in this room; this exit has a door that a
  silver key opens; this room holds a falling-stone trap. Durable, worth
  checking in, worth exporting.
- **Today's state** — that lever is currently thrown; that door is currently
  open; that trap is currently disarmed. True for everyone at once, and gone
  tomorrow.

Three things in this repo already conflated them and were wrong as a result:
`project-town-2-route-home` explained a short return route by levers opening
walls "permanently"; `ta_nav.lua`'s `chasm-is-clear` variant skips a sweep and
walks past a hydra on the same assumption; and this table said "permanent" until
now. All are really claims about *a day on which someone already made the
outward walk*.

Any export — a checked-in database, JSON behind an HTML map — must keep the two
apart, or it ships one afternoon's state as though it were the world.

## From the sewers (level 1 surveyed)

**12. A shaft belongs to no level.** Two rooms named "town sewer" (singular,
against 170 "town sewers") form a vertical drop from the desert into sewer level
three, bypassing levels one and two:

```
crude-stone-building (desert, z=0)
  -> town-sewer-1 (z=-1) -> town-sewer (z=-2) -> town-sewers-169 (z=-3)
```

They are flat-disconnected from every level they pass through, so each shows as
a one-room component at its own depth. "Level" is a property of a horizontally
connected region; some rooms are pure vertical transit and belong to none. The
same shape recurs with pits (`pit`, `pit-1`, `pit-2`) — a room whose only links
are vertical. Filing them by `z` alone is arbitrary and, for the dungeon `pit`,
we already chose to file by *the level you fall from* instead.

**13. A region can have entrances the map's author left out.** The sewers reach
the surface twice — up to second town, and up this shaft to the desert. The
shrine's level 1 draws only the town 2 stair. That is scope, not error, but it
means a room-count difference is not automatically our bug.

**14. A key is a relation, not a property.** Sewer level 2's legend pairs them
by case: `p` is the room where the platinum key is found, `P` is the door it
opens, drawn on the connector. Same for jade and onyx. A key joins a **source**
to one or more **gated exits**.

We hold only the door end. `room_exits.lock_key` says which key opens an exit;
nothing says where that key comes from. `item_drops` knows an anaconda drops a
ruby key but not in which room, and a key sitting in a room rather than on a
monster has nowhere to live at all.

This subsumes two earlier atoms: the guardian (atom 5, "Cyclops (Silver Key)")
and the item in place (atom 8, the White Rune) are both the *source* end of this
relation. It also explains, retroactively, why every shrine map names a door by
its key rather than its material: to the map's author a door is not a thing with
a material, it is the far end of a key relation. Our `lock_door` column is the
part that carries almost no information.

### Confidence: what the survey says is trustworthy

Sewer level 2 is the first complete match — 55 rooms to 55 boxes, identical hub
topology, all three doors with the right keys. Running total on doors:

| map | shrine draws | ours correct before the survey |
|---|---|---|
| dungeon 1 | 4 | 1 of 2 recorded |
| dungeon 2 | 1 | 1 of 3 recorded |
| dungeon 3 | 1 | 1 of 2 recorded |
| sewers 1 | 1 | 1 of 1 |
| sewers 2 | 3 | 3 of 3 |

The dungeon door data is bad; the sewer door data is perfect. Worth knowing why
before trusting either — the sewers were mapped later, and their doors are the
ones `navigate-to` routes actually gate on, so they have been walked and
re-walked while the dungeon's were passed once.

## From sewers level 3

Their 53 boxes against our 52 in the `z=-3` component; they draw neither pit,
marking only the `[t]` that drops you in. The pearl door, the shaft and the
hydra all match: `[^]` "Up to Desert" is `town-sewers-169`, `#` is the pearl
door, and `[c] Hydra (Pearl Key)` is `town-sewers-165` — which `item_drops`
already has dropping a pearl key.

**15. A room can hold more than one hazard, and we can hold only one.** The
shrine marks `town-sewers-168` as a Poison Trap; we have `crossbow trap` on it.
`rooms.trap` is a single TEXT column, so even if both are true only one fits.

**16. Poison is a hazard we never record at all.** `You're poisoned!` appears
**345 times** in the logs — the most common hazard message in the game — and
`main.lua` has no trigger for it. The trap triggers cover spiked trap, crossbow,
falling rocks, falling block, scything blade, flame trap and trap door; poison
is simply absent. This is the largest known gap between what the world does and
what we write down.

**17. A hazard's outcome depends on who walks into it.** "Your rogue abilities
allowed you to detect and avoid a trap!" appears 26 times. A trap is not a fact
about a room alone.

**18. Traps are disarmed remotely, and the game says so only in passing.** Other
players falling through a trap door are announced in the destination room ("X
has just fallen into the room through a trap door in the ceiling!", 282+ lines),
which is a *remote observation* of a hazard somewhere else.

## Blocking bug: the one attempt to record a coupling was thrown away

The logs contain the user trying to write down exactly the coupling this
inventory is about:

```
> map-note Pull lever here so you aren't hurt by the trap on this level
Sorry, that is not an appropriate command.
```

There is no `map-note` alias — it is `map-add-note` — so the text went to the
BBS, which rejected it, and nothing was saved. It was attempted twice, and a
third line reads "HEY CLAUDE I THINK A TRAP SHOULD'VE BEEN HERE AND WOULD'VE
BEEN HERE IF I DIDN'T PULL THAT LEVER".

**That is why `room_notes` has 0 rows.** The table was not unused; the alias
name did not match what a person types, and an unmatched `map-*` command is
indistinguishable from a typo because it silently becomes game input. Any
capture work is worth little until this is fixed, since it is the failure mode
that loses observations a human already made.

## From the desert

The desert map is topology only — no doors, traps or creatures marked. An area
can be pure terrain, which no earlier map showed.

**19. `z` is not trustworthy everywhere.** In the dungeon and sewers, flooding
across non-vertical edges produced components each sitting at a single `z`. In
the desert **one flat component of 197 rooms spans `z = 0, -2 and -3`** —
dead reckoning drifted, almost certainly because the area was mapped from
several anchors across sessions. So the dungeon-style "split by `z`, confirm by
topology" recipe does **not** generalise. Where `z` and topology disagree,
topology wins, and here `z` has to be discarded rather than confirmed.

**20. A region boundary can be a single ordinary exit.** The desert meets the
stoneworks at exactly one horizontal edge:

```
desert-22 --s--> stonework-chamber
stonework-chamber --n--> desert-22
```

which is the shrine's `[S] Stoneworks` box. Same shape as first-town/mountains.
The split is ready whenever we want it: 47 desert-proper rooms (desert 36,
sandy passage 8, storage room 2, crude stone building 1) against 199 stoneworks
rooms (corridor 175, chamber 24), currently all filed under `desert`.

### The shrine maps are a completeness check

The most useful thing the desert comparison gives us is not an atom. **Their
map has 103 boxes; we have 47 desert-proper rooms.** We have walked roughly half
the desert. It also has 28 unwalked exits, more than every other area combined
(mountains 13, third-town 4, cellars 4), seven of them in desert rooms proper:
`desert-9 w`, `-10 sw`, `-13 sw`, `-19 n`, `-24 se`, `-31 ne`, `-35 ne`.

So a box count per area tells us where mapping is incomplete, and the drawing
tells us roughly what shape the missing part is. That is worth doing for every
area before trusting any export.

**A warning for the stoneworks.** Our 199 stoneworks rooms fall into three flat
components, not six, and 21 of the area's frontiers are in them. The user says
the stoneworks has six levels. So that region is materially incomplete too, and
`z` cannot be used to split it.

## Done: the sewers split

`sewers` became `sewers-level-1` (63), `sewers-level-2` (55), `sewers-level-3`
(56); the emptied `sewers` area was dropped. Cross-area edges came out exactly
as the shrine draws them:

```
[level 1]  u  town-sewers      -> path-4               [second-town]
[level 1]  d  town-sewers-62   -> town-sewers-63       [level 2]
[level 2]  d  town-sewers-117  -> town-sewers-118      [level 3]
[level 3]  u  town-sewer-1     -> crude-stone-building [desert]
```

Two judgement calls, both following the first dungeon's precedent that a room
of pure vertical transit is filed with the level it serves rather than by `z`:

- `pit-1` and `pit-2` go to level 3, the level you fall from.
- The two-room desert shaft (`town-sewer-1`, `town-sewer`) goes to level 3 as
  well, even though those rooms dead-reckon to `z=-1` and `z=-2`. It touches no
  level horizontally and lands on level 3, which is exactly how the shrine draws
  it — as level 3's "Up to Desert" exit, absent from the level 1 and 2 maps.

So level 3 holds four rooms whose `z` disagrees with their area. That is the
intended meaning: `z` is physical depth, the area is which level you explore it
from.

**Naming settled: numerals.** The first dungeon's areas were renamed from
`first-dungeon-level-one/two/three` to `-1/-2/-3` to match. Numerals win because
room slugs already use them (`cave-61`, `town-sewers-117`, `desert-22`), so
words for areas would have moved the inconsistency rather than removed it; the
game and the shrine both say "Down to Level 2"; and `one/two/three` sorts as
one, three, two, which is why the dungeon areas listed in the wrong order all
through this survey.

## From stoneworks level 1 — every hard atom, drawn

55 boxes. Our 199 stoneworks rooms are still filed under `desert` in three flat
components (197 mixed with the desert itself, 29, 20), none of which is 55, so
there is nothing to compare counts against yet. What this map gives instead is
the notation for everything the inventory has been circling:

```
L1 = Pull Lever to disarm stone trap (T1)    S2 = Push Stone to go to S3
S1 = Push Stone to open door at D1           S3 = If on way out Push Stone to go to !
 @ = "say komi" to enter the Stoneworks       v = Stairs Down to Level 2
```

`[@]` is identifiable: our `stonework-chamber`, exits `n,e,s`, which is exactly
the room `ta_nav.lua`'s `town-3/stone-lvl-2` route starts from with a first step
of `{ cmd = "say komi" }`.

**21. A device disarms a hazard elsewhere.** `L1` -> `T1`. This is precisely the
coupling the user tried to write down and lost to the `map-note` bug.

**22. A device opens a door elsewhere.** `S1` -> `D1`. Note the door at `D1` has
no key and no material; it is opened by an action in another room.

**23. Teleport edges are not rare.** `S2` -> `S3`, and `S3` -> `!`. Two on this
level alone. `docs/hidden-stone-teleport.md` records the one at
`stonework-corridor-28` and says "Only one instance seen so far — may be the
only teleport in the game. If more turn up, fix the mapper." More have turned up.

**24. A device's effect can depend on the direction of travel.** "If on way out
Push Stone to go to `!`" — the same stone is useful only outbound. So an effect
is not always a pure function of the room.

**25. A gate can be a spoken word rather than a key.** `say komi` to enter the
stoneworks; `say arok` appears twice more in the routes. No door, no material,
no key — an utterance, in a specific room.

**26. Couplings need named endpoints, and that is the schema answer.** The
shrine invented `L1`, `T1`, `S1`, `D1`, `S2`, `S3`, `!` for one reason: a
coupling has two ends and both must be nameable. We already have stable room
ids, so we have the endpoints. What has nowhere to live is the **relation**.

That is the shape the survey has been driving at: a table of room-to-room
relations that are not exits, carrying a verb (`pull lever`, `push stone`,
`say <word>`), a source room, a target room or exit, an effect (disarms,
opens, teleports), and a condition (direction of travel). `room_notes` is the
prose version of this and cannot be queried, joined or drawn.

## Done: the stoneworks split off from the desert

`desert` 246 -> **`desert` 47** + **`stoneworks` 199**. The `stoneworks` area
already existed holding zero rooms; it now holds them.

The partition was made by flooding the graph from `crude-stone-building` (the
desert map's `[v]`, down to the sewers) with the one seam edge cut, rather than
by filtering on room name. It came out split exactly along name lines anyway —
desert 36, sandy passage 8, storage room 2, crude stone building 1 on one side;
stonework corridor 175, stonework chamber 24 on the other, with no mixing. That
agreement is the evidence the seam really is the only connection.

The seam is the room both shrine maps draw: the desert map's `[S] Stoneworks`
box is the stoneworks level 1 map's `[@]`, the room you `say komi` in.

```
desert-22          --s--> stonework-chamber
stonework-chamber  --n--> desert-22
```

Only `rooms.area_id` changed: 760 rooms and 1607 exits before and after, no NULL
areas, the four pre-existing non-reciprocal edges unchanged. Afterwards the two
regions have exactly two cross-area edge pairs between them and the rest of the
world — the seam, and the desert's shaft down to `sewers-level-3`.

Frontiers now attribute where they belong instead of hiding inside one count:
**stoneworks 21, desert 7.**

Still open, and not attempted: carving the stoneworks into its six levels. `z`
is unreliable in this region, its 199 rooms form three flat components rather
than six, and 21 unwalked exits sit inside it. Survey levels 2-6 first, so we
know what six levels should look like before trying to find them.

## From stoneworks level 2

40 boxes. The level 1 pattern repeats exactly: one lever that disarms that
level's own stone trap (`L2` -> `T2`, as `L1` -> `T1`), and one spoken gate —
`say arok` here where level 1 had `say komi`.

**27. Devices are systematic, one set per level.** Not scattered oddities. That
is what makes them worth modelling rather than noting in prose.

**28. Devices are already sitting in `rooms.description`, in rigid templates,
and have never been extracted.** Description coverage is 759 of 760 rooms, so
this is close to a complete source:

```
A small lever is partially concealed in a niche in the <dir> wall.        x 7
A stone in the <dir> wall appears to protrude from the wall slightly
  more than the others.                                                   x 2
```

Seven lever rooms against a one-lever-per-level pattern across six levels says
we have walked past most of them. This is the same discovery as doors, one level
up: the *device* is in the description, though its *effect* — which trap it
disarms, which door it opens, where it teleports you — never is. Descriptions
give the source end of a coupling for free; only the target end needs observing.

## Resolved: the levels come from the nav routes, not from `z`

`z` is unusable in the stoneworks, and not merely offset. The largest flat
component — 150 rooms with **no vertical edges inside it**, so every room in it
was reached without going up or down — holds three different `z` values
(0 x45, -2 x101, -3 x4). It was walked across several sessions that each
anchored `z=0` where they began, so `z` is internally contradictory here. Level
6's body sits at `z=-1` and level 5's at `z=-3`: `z` is anti-correlated with
depth, not just noisy.

The ground truth was already in the repo. `ta_nav.lua`'s `stone-lvl-2..6` are
hand-copied walks that worked, and replaying their step lists against the room
graph recovers the structure. Each route's `from` fingerprint can match several
rooms, so the start is disambiguated by walking every candidate and keeping the
one whose directions keep working:

| route | start | result |
|---|---|---|
| `stone-lvl-3` | `stonework-chamber-4` | **45/45**, ends in `stonework-chamber-9` |
| `stone-lvl-4` | `stonework-chamber-9` | 17/41, breaks on an unwalked stub |
| `stone-lvl-5` | `stonework-chamber-12` | 24/35, breaks in `stonework-corridor-68` |
| `stone-lvl-6` | `stonework-chamber-15` | **26/26**, ends in `stonework-chamber-17` |
| `stone-lvl-2` | unresolved | 2/39 at best from any candidate |

`stone-lvl-3` ends exactly where `stone-lvl-4` starts, and every level's arrival
chamber is one of our five `d` targets, each leg ending by descending to the
next:

```
corridor-28  -d-> chamber-4  [lvl 3, 30 rooms]  -> corridor-52
corridor-52  -d-> chamber-9  [lvl 4, 18+ rooms] -> corridor-78
corridor-78  -d-> chamber-12 [lvl 5, 17+ rooms] -> corridor-93
corridor-93  -d-> chamber-15 [lvl 6, 21 rooms]  -> corridor-111
corridor-111 -d-> chamber-17 (below level 6, toward town 3)
```

**29. A recorded walk is better evidence than a coordinate.** The routes were
hand-copied precisely because the graph could not be trusted, and they turn out
to be the only thing that can carve the region. Worth remembering when the
export question comes back: a route is data, not just a script.

### What blocks finishing the carve

Specific exits the routes use that the graph does not have. These are a short
in-game errand, not a modelling problem:

| room | direction | seen by |
|---|---|---|
| `stonework-corridor-68` | `se` | `stone-lvl-4` step 18 (unwalked stub) |
| `stonework-corridor-68` | `sw` | `stone-lvl-5` step 26 (no such exit) |
| `stonework-corridor-30` | `s` | `stone-lvl-4` from chamber-4 |
| `stonework-corridor-4` | `se` | `stone-lvl-2` candidate |
| `stonework-corridor-58` | `se` | `stone-lvl-2` candidate |

`stone-lvl-2` is the odd one. Its `from` fingerprint is a stonework chamber with
exits `n,e,s`, and the stoneworks entry chamber — the desert seam, the `say
komi` room, the shrine's `[@]` — has `n,e,s,w`. One exit too many. Either the
`w` is spurious in our graph or the route's fingerprint predates it, and until
that is settled level 2 cannot be anchored.

## Superseded: we could not say where level 1's stairs go

We hold five vertical edges in the stoneworks and **two** descents from `z=0`:

```
stonework-corridor-28  (z=0)   d-> stonework-chamber-4   (z=-1)
stonework-corridor-93  (z=0)   d-> stonework-chamber-15  (z=-1)
stonework-corridor-52  (z=-1)  d-> stonework-chamber-9   (z=-2)
stonework-corridor-111 (z=-1)  d-> stonework-chamber-17  (z=-2)
stonework-corridor-78  (z=-2)  d-> stonework-chamber-12  (z=-3)
```

The shrine draws one `[v]` on level 1, so at most one of the two z=0 descents is
it. Neither candidate's description mentions a protruding stone, so neither is
an obviously mis-recorded teleport. The real problem is that `z` is not
trustworthy in this region (one flat component already spans z=0, -2 and -3), so
"z=0" is not a synonym for "level 1" here and the question cannot be settled by
counting depth.

What would settle it: the six levels have six known landmarks between them — two
spoken gates, six levers, at least three push-stones. Anchoring our rooms to the
shrine's levels by matching those, rather than by `z`, is the way in. Survey
levels 3-6 first so the full landmark set is known.

## Survey queue

- [x] First town, second town
- [x] First dungeon, levels 1-3
- [x] Sewers levels 1-3
- [x] The desert
- [x] Stoneworks levels 1-2
- [ ] Stoneworks levels 3-6  (the `stoneworks` area holds 0 rooms; its 199 rooms are filed under `desert`, in 3 flat components not 6, with 21 unwalked exits)
- [ ] Third town
- [ ] Anything else with levers, stones or spoken words

## Method

For each map: count rooms against ours; diff the glyph vocabulary; check every
door and trap against `rooms.description` and the logs; and record any mechanic
that is neither a room nor an exit. Note new atoms here, not new features.

Two rules learned the hard way, both from being wrong first:

- **Never retract a door on description silence.** A generic exit list
  ("The exits are to the north and south.") carries no information; only a
  description that positively names something else in that direction does.
- **Shrine labels name a door by its KEY, the game names it by its MATERIAL.**
  They are not in conflict; they are different columns.
