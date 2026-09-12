# Glossary

Shared vocabulary for talking about the map. The two sources that already have
opinions about these words are the code (`main.lua`, `ta_db.lua`, `ta_nav.lua`,
`map.ts`) and the shrine drawings (`map/shrine/*.txt`), and they don't always
agree with each other — where they differ, this file picks one and says so.

A **Capitalised** word inside a definition is another term defined here, so the
entries read as a linked set. Words in an `_Avoid_` line stay lowercase: those
are the rejected spellings, not references.

This is a first pass: twenty-five terms, chosen because a conversation actually
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

An Exit is topology, and topology survives a Reset. Whether it will admit you
right now is Device State, and the two come apart: a Sealed Exit is still an
Exit, still listed by `ex`, and still a walked edge in the map.

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

A Device can cause one — the stoneworks' `S2` and `S3` stones, and the labyrinth
Riddle. It is the one Device effect that is an event rather than a state, so a
Reset has nothing to put back: a Teleport already happened.

**Route**:
A named, hand-written list of steps from one Room to somewhere far away, walked
by `navigate-to`. Its key is a **label** rather than a destination —
`town-3/get-ruby-key` names an errand that ends where it began — and it names
the single Room it starts from, by slug or by Fingerprint, refusing to walk
unless you are standing there.
_Avoid_: path, journey, directions, walk (a Route is the written plan, not the
act of following it)

Not every **step** is a Move: a step is a direction, a command (`pull lever`), a
Room to clear of monsters, a RouteGate, or a Seam check. A Route built from
**legs** names other Routes to walk in order instead of copying their steps, with
a Seam check inserted before each — so every leg stays runnable on its own and no
direction is transcribed twice.

A Route is never derived from the map: each one is a transcription of a walk that
actually worked, because the graph is full of Stubs and Doors it cannot reason
about. The map is read-only while a Route runs.

**RouteGate**:
A Route step that Moves through a Door which may or may not be shut, naming the
key that opens it and the **detour** — the errand Route that fetches that key.
Written `{ door = "s", key = "ruby", detour = "town-3/get-ruby-key" }`, so the
data says "door" where the vocabulary says gate.
_Avoid_: gate on its own (Door's `_Avoid_` already claims that spelling for the
obstruction), door step, lock step

Its point is that the Move *is* the question. The game answers a Door direction
with a Brief if it already stands open, with "your `<key>` key unlocks…" if we
are carrying the key, and with a refusal if we are not — and the first two both
mean the detour can be skipped. Distinct from a Route's own final `door` field,
which is a single direction tried on arrival to report whether it could be
passed, and which fetches nothing.

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

**Seal**:
Something blocking passage along an Exit that can be cleared and comes back at
the next Reset. A Door cleared with a key is one kind; a wall or a mist cleared
by operating a Device elsewhere is another; a raised drawbridge over a chasm is a
third.
_Avoid_: wall, mist, barrier, blockage — each of those is one kind of Seal, not
the category

A Seal does not remove the Exit it sits on. `[D1]` answered `Exits: n,e.` and
then refused `n` in the same breath, and a hobgoblin bounced off it twice while
we watched. So `ex` reports topology, and passage is Device State.

**Door**:
A property of a single Exit: that it stays shut until opened with a particular
key, recorded as the Door's material plus that key. The Seal whose key is an
object you carry. There is no key→Door rule to infer: ten different keys each
open some "stone door", so the pairing belongs to the specific Exit and nowhere
else.
_Avoid_: lock, gate, barrier, exit

**Device**:
Something you operate in one Room that changes the world, usually somewhere else.
Three ways to work one: a **lever** (`pull lever`), a **stone** (`push stone`),
and a Riddle (`say <answer>`). A Device's *effect* is a map fact worth recording;
what it has currently done is Device State, which the next Reset throws away.
_Avoid_: mechanism, switch, trigger (a trigger is a baud pattern-match on server
output — unrelated)

A Device acts on exactly one of four things:

- a **Seal**, opened or shut
- a **Trap**, disarmed or armed
- **Light**, on or off across a whole collection of Rooms
- a **Teleport**, moving whoever worked it

Seals and Traps are the common pair — eleven of the sixteen Devices the shrine
drawings document. Latching and Toggling classify the first three, which leave a
state behind. A Teleport leaves none, so it is neither: work it again and it
simply fires again.

**Latching**:
A Device that stays where you put it: the first use opens the Seal, the Seal
stays open for the rest of the Reset, and using it again does nothing further.
The levers on the way to third town are these. Idempotent — but within one Reset
only, so it needs working again tomorrow.
_Avoid_: permanent (it invites the conclusion that you will never have to work it
again, and the next Reset says otherwise), one-shot, sticky, idempotent as the
name — it is the property, not the kind of thing

**Toggling**:
A Device that reverses itself: first use opens the Seal, second shuts it, third
opens it again. The lever at the end of the dark labyrinth's third Level is one,
which is why only the first character through pulls it and everyone after walks
`navigate-to end-of-labrynth-level-3 no-pull-lever`.
_Avoid_: switch, flip-flop, momentary

Both kinds hold state, so this is not a stateful/stateless distinction and a
Latching Device is not "the stateless one" — every Device has Device State. The
only difference is whether working it a second time changes anything.

**Riddle**:
A Device worked by speaking an answer — `say komi` to enter the Stoneworks, `say
arok` to get further down. The answer is knowledge rather than an object, which is
what separates a Riddle from a Door: nothing in your inventory helps, and once you
know it you have it for good.
_Avoid_: password, puzzle, incantation, spell (a spell is cast and this is not
one)

A Riddle can want more than one answer. The labyrinth's `Z` room takes `say
cinders` and then `say ether`, and its effect is a Teleport into the Tunnels. The
two stoneworks Riddles are single-answer, Latching, and open Seals — which is why
a Route re-says them every walk: `say arok` stays in the `no-pull-lever` variant
precisely because saying it again is harmless.

Which kind a Device is belongs to that Device alone and cannot be reasoned out
from another one. The level-3 lever was written down as permanent because the
levers on the way to third town are, and that was wrong — the same error as
calling the level-2 stone a Teleport. The asymmetry is the point: a Latching
Device can be worked without knowing Device State, a Toggling one cannot, and
nothing you can see in the Room tells you which is in front of you.

**Trap**:
A hazard that fires on a Room rather than on an Exit. The shrine drawings
distinguish the two kinds that matter to routing: one a Device can disarm
(`T1` with its `L1` lever) and one that cannot be turned off at all. Disarming
is Device State, so the first kind is armed again after the next Reset — a
Route that walked through it yesterday is not safe today.
_Avoid_: hazard, damage room

**Light**:
Whether a collection of Rooms is lit. Always a group and never a single Room: the
stone on the labyrinth's fifth Level lights its second Level, and one on the
second lights the fourth.
_Avoid_: torch, lamp, visibility — a light source you carry is a different thing
and on the labyrinth's dark Level it does not help

It matters because an unlit Room answers a Move with "It's too dark to see."
instead of a Brief, so a Route through one declares `dark = true` and advances on
that line. A Device that lights those Rooms would therefore turn a dark Route
into an ordinary one.

## The world resets

**Reset**:
The BBS restarting, which restarts Tele-Arena with it — nightly at around 3 or
4am, and again whenever the BBS crashes. A power cycle rather than a game event,
so every Seal anyone had cleared is back: Doors locked, a wall a Device removed
standing again, a lowered drawbridge raised.
_Avoid_: daily reset (a crash resets too, so "daily" is the wrong half of it),
reboot, restart, respawn (nothing is respawning — the world is being rebuilt)

The word does double duty, and both readings are wanted: the *event*, and the
*interval* it opens. "Within a Reset" and "since the Reset" mean that interval,
and it is the lifetime of every piece of Device State — the unit a Seal stays
open for, and the reason nothing a Device does is permanent.

**Device State**:
What is true right now because of the Devices operated since the last Reset. It
is a claim about *today*, never a map fact, and the map must not learn to doubt
its own topology because of it — which is why a Sealed Exit stays a walked edge
rather than degrading to a Stub.
_Avoid_: world state, flags, progress
