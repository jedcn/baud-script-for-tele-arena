# Glossary

Shared vocabulary for talking about the map. The two sources that already have
opinions about these words are the code (`main.lua`, `ta_db.lua`, `ta_nav.lua`,
`map.ts`) and the shrine drawings (`map/shrine/*.txt`), and they don't always
agree with each other — where they differ, this file picks one and says so.

This is a first pass: thirteen terms, chosen because a conversation actually
turned on each of them. Deliberately left for later: everything about combat,
arenas, items and spells.

## Place

**Room**:
One location the game can put you in, identified by an integer id. Its `slug`
(`stonework-corridor-175`) is the human-typable handle used by every `map-*`
command; the suffix is a **global** counter, not per-area, so there is no
`stonework-corridor-0` just because this area starts at 175.
_Avoid_: node, square, cell, tile

**Area**:
A named group of rooms we chose to draw and verify as a unit — `third-town`,
`sewers-level-2`. An area is a bookkeeping decision, not something the game
knows about: rooms carry an `area_id` because we put them there, and moving one
between areas changes no topology.
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
Fingerprint — which is what a route's `{ seam = ... }` step checks and what
`map-here` is for at the start of a crossing.
_Avoid_: border, boundary, transition. Note that a **seam** is also the
boundary between two Lua chunks, crossing through `taPackage` — unrelated to
the map.

**Crossing**:
The reciprocal pair of Exits joining two Areas — the edge a Seam sits on either
end of. Seams and crossings divide the labour: a crossing is what gets walked,
linked, or left as a Stub, and a Seam is where you stand while doing it.
_Avoid_: seam (a crossing is not a room), doorway, border

Every crossing has **two** seams, one per side, so name the side you mean: "the
third-town side of the stoneworks seam". A seam is an ordinary room in every
other respect — most of its exits stay inside its own area.

## Movement

**Exit**:
A one-way edge out of a Room in one of ten directions (`n s e w ne nw se sw u
d`). Exits are stored one-way and are expected to come in reciprocal pairs, so
`A --se--> B` obliges `B --nw--> A`; a one-directional exit is a defect, not a
one-way passage.
_Avoid_: edge, link, connection, and especially **door** — a Door is a property
*of* an exit, not a synonym for one

**Move**:
One step of travel in a compass direction, which the game answers with a Brief.
This is the only event that advances dead reckoning, which is why a Brief for
the room you are *already* in must not be counted as one.
_Avoid_: walk (a whole journey), step (an element of a Route, which may be a
command or a kill rather than a move)

**Teleport**:
A change of location with no Exit to account for it — `push stone`, the
great-lake ferry. The honest result of one is that position becomes **lost**,
because the map has no edge to follow; a teleport recorded as an ordinary exit
is the specific corruption `just verify-area` hunts by looking for impossible
changes of depth.
_Avoid_: warp, jump, portal

## Identity

**Brief**:
The short block the game prints on arrival: the room line (`You're in a
stonework chamber.`), then occupants, then the floor. It is how we learn a
Room's name, and it is *not* the Description — that comes from `look`, opens
with "You are …", and is stored on the room.
_Avoid_: description, look, room text

**Description**:
The prose a Room gives to `look`. It names every exit it has in words ("The
corridor runs to the north and southeast"), which makes it the highest-entropy
identifier we get for free and the best available cross-check on the exits we
recorded.
_Avoid_: brief, long description

**Fingerprint**:
A Room's name plus its exact exit-set — the identity check used before walking a
Route and when deciding whether a room is one we have already seen. It is
*weak* here and must be treated as such: 176 rooms are called "stonework
corridor", and thirteen of this level's chambers share both name and exit-set.
_Avoid_: signature, identity, hash

**Stub**:
An Exit we know exists but have never walked — stored with a NULL destination,
usually seeded from an `ex` listing. The **frontier** is the set of all stubs in
an Area, i.e. the live edge of exploration; a stub is one room's share of it.
_Avoid_: dangling exit, NULL exit, unexplored edge (a stub is not broken — it is
a to-do)

## Obstacles and devices

**Door**:
A locked gate on a single Exit, recorded as the door's material and the key that
opens it. There is no key→door rule to infer: ten different keys each open some
"stone door", so the pairing belongs to the specific edge and nowhere else.
_Avoid_: lock, gate, barrier, exit

**Device**:
Something you operate in one room that changes the world somewhere else — the
two kinds are a **lever** (`pull lever`) and a **stone** (`push stone`). A
device's *effect* is a map fact worth recording; its *state* is only ever a fact
about today, because the world resets daily.
_Avoid_: mechanism, switch, toggle, trigger (a trigger is a baud pattern-match
on server output — unrelated)

**Trap**:
A hazard that fires on a Room rather than on an Exit. The shrine drawings
distinguish the two kinds that matter to routing: one a Device can disarm
(`T1` with its `L1` lever) and one that cannot be turned off at all.
_Avoid_: hazard, damage room
