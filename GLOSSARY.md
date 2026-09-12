# Glossary

Shared vocabulary for talking about the map. The two sources that already have
opinions about these words are the code (`main.lua`, `ta_db.lua`, `ta_nav.lua`,
`map.ts`) and the shrine drawings (`map/shrine/*.txt`), and they don't always
agree with each other — where they differ, this file picks one and says so.

A **Capitalised** word inside a definition is another term defined here, so the
entries read as a linked set. Words in an `_Avoid_` line stay lowercase: those
are the rejected spellings, not references.

This is a first pass: seventeen terms, chosen because a conversation actually
turned on each of them. Deliberately left for later: everything about combat,
arenas, items and spells.

## Place

**Room**:
One location the game can put you in, identified by an integer id. Its `slug`
(`stonework-corridor-175`) is the human-typable handle used by every `map-*`
command; the suffix is a **global** counter, not per-Area, so there is no
`stonework-corridor-0` just because this Area starts at 175.
_Avoid_: node, square, cell, tile

**Area**:
A named group of Rooms we chose to draw and verify as a unit — `third-town`,
`sewers-level-2`. An Area is a bookkeeping decision, not something the game
knows about: Rooms carry an `area_id` because we put them there, and moving one
between Areas changes no topology.
_Avoid_: region, zone, map, dungeon

**Level**:
One storey of a multi-storey place, where the game reaches the next one by
stairs. Levels are the reason an Area is usually `<place>-level-<N>`: we split
them so each renders as a tidy grid instead of several overlapping ones.
_Avoid_: floor — in this codebase "the floor" is the ground you read items off
("There is nothing on the floor."), which is a different thing entirely

**Seam**:
A Room you can leave, by one particular Exit, and arrive in a Room of a
different Area. It is a place you stand in, anchor on and identify by
Fingerprint — which is what a Route's `{ seam = ... }` step checks and what
`map-here` is for at the start of a Crossing.
_Avoid_: border, boundary, transition. Note that a **seam** is also the
boundary between two Lua chunks, crossing through `taPackage` — unrelated to
the map.

**Crossing**:
The reciprocal pair of Exits joining two Areas — the edge a Seam sits on either
end of. Seams and Crossings divide the labour: a Crossing is what gets walked,
linked, or left as a Stub, and a Seam is where you stand while doing it.
_Avoid_: seam (a Crossing is not a Room), doorway, border

Every Crossing has **two** Seams, one per side, so name the side you mean: "the
third-town side of the stoneworks seam". A Seam is an ordinary Room in every
other respect — most of its Exits stay inside its own Area.

## Movement

**Exit**:
A one-way edge out of a Room in one of ten directions (`n s e w ne nw se sw u
d`). Exits are stored one-way and are expected to come in reciprocal pairs, so
`A --se--> B` obliges `B --nw--> A`; a one-directional Exit is a defect, not a
one-way passage.
_Avoid_: edge, link, connection, and especially **door** — a Door is a property
*of* an Exit, not a synonym for one

**Move**:
One step of travel in a compass direction, which the game answers with a Brief.
This is the only event that advances Dead reckoning, which is why a Brief for
the Room you are *already* in must not be counted as one.
_Avoid_: walk (a whole journey), step (an element of a Route, which may be a
command or a kill rather than a Move)

**Dead reckoning**:
Working out where you are by accumulating Moves from a known starting Room,
because the game never reports a position. Each Move adds its direction's delta
to the previous Room's coordinate — north `+y`, east `+x`, up `+z`, diagonals
both at once — and that sum is the only source of the `x/y/z` stamped on a Room.
_Avoid_: tracking (position tracking follows the map and survives with no
coordinate at all), positioning, navigation (that is walking a Route)

Two things follow, and both have cost us Rooms. It **drifts**: these Rooms never
sat on a real grid, so a loop need not close geometrically and two distinct
Rooms can legitimately reckon onto the same cell — which is why coordinates are
a hint and topology is the truth. And it needs an **anchor**: a cold start has
no coordinate to reckon from, and `map-here` exists to restore one from a Room's
stored record.

The same phrase turns up for time as well as space — recovering a cooldown by
counting from the last accepted swing rather than waiting to be told. Same idea,
different axis.

**Teleport**:
A change of location with no Exit to account for it — `push stone`, the
great-lake ferry. The honest result of one is that position becomes **lost**,
because the map has no edge to follow; a Teleport recorded as an ordinary Exit
is the specific corruption `just verify-area` hunts by looking for impossible
changes of depth.
_Avoid_: warp, jump, portal

**Route**:
A named, hand-written list of steps from one Room to somewhere far away, walked
by `navigate-to`. Its key is a **label** rather than a destination —
`town-3/get-ruby-key` names an errand that ends where it began — and it names
the single Room it starts from, by slug or by Fingerprint, refusing to walk
unless you are standing there.
_Avoid_: path, journey, directions, walk (a Route is the written plan, not the
act of following it)

Not every **step** is a Move: a step is a direction, a command (`pull lever`), a
Room to clear of monsters, a **gate** (a Move through a Door that may or may not
be shut, naming the key and the errand that fetches it), or a Seam check. A
Route built from **legs** names other Routes to walk in order instead of copying
their steps, with a Seam check inserted before each — so every leg stays
runnable on its own and no direction is transcribed twice.

A Route is never derived from the map: each one is a transcription of a walk that
actually worked, because the graph is full of Stubs and Doors it cannot reason
about. The map is read-only while a Route runs.

## Identity

**Brief**:
The short block the game prints on arrival: the room line (`You're in a
stonework chamber.`), then occupants, then the floor. It is how we learn a
Room's name, and it is *not* the Description — that comes from `look`, opens
with "You are …", and is stored on the Room.
_Avoid_: description, look, room text

**Description**:
The prose a Room gives to `look`. It names every Exit it has in words ("The
corridor runs to the north and southeast"), which makes it the highest-entropy
identifier we get for free and the best available cross-check on the Exits we
recorded.
_Avoid_: brief, long description

**Fingerprint**:
A Room's name plus its exact exit-set — the identity check used before walking a
Route and when deciding whether a Room is one we have already seen. It is
*weak* here and must be treated as such: 176 Rooms are called "stonework
corridor", and thirteen of this Level's chambers share both name and exit-set.
_Avoid_: signature, identity, hash

**Stub**:
An Exit we know exists but have never walked — stored with a NULL destination,
usually seeded from an `ex` listing. The **frontier** is the set of all Stubs in
an Area, i.e. the live edge of exploration; a Stub is one Room's share of it.
_Avoid_: dangling exit, NULL exit, unexplored edge (a Stub is not broken — it is
a to-do)

## Obstacles and devices

**Door**:
A locked gate on a single Exit, recorded as the Door's material and the key that
opens it. There is no key→Door rule to infer: ten different keys each open some
"stone door", so the pairing belongs to the specific Exit and nowhere else.
_Avoid_: lock, gate, barrier, exit

**Device**:
Something you operate in one Room that changes the world somewhere else — the
two kinds are a **lever** (`pull lever`) and a **stone** (`push stone`). A
Device's *effect* is a map fact worth recording; its *state* is only ever a fact
about today, because the world resets daily.
_Avoid_: mechanism, switch, toggle, trigger (a trigger is a baud pattern-match
on server output — unrelated)

**Trap**:
A hazard that fires on a Room rather than on an Exit. The shrine drawings
distinguish the two kinds that matter to routing: one a Device can disarm
(`T1` with its `L1` lever) and one that cannot be turned off at all.
_Avoid_: hazard, damage room
