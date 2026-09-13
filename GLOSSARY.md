# Glossary

Shared vocabulary for talking about the map. The two sources that already have
opinions about these words are the code (`main.lua`, `ta_db.lua`, `ta_nav.lua`,
`map.ts`) and the shrine drawings (`map/shrine/*.txt`), and they don't always
agree with each other — where they differ, this file picks one and says so.

A **Capitalised** word inside a definition is another term defined here, so the
entries read as a linked set. Words in an `_Avoid_` line stay lowercase: those
are the rejected spellings, not references.

This is a first pass: twenty-six terms, chosen because a conversation actually
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
A change of location that no compass Exit accounts for — `push stone`, or the
great-lake ferry (`buy passage`, 100 gold, and the crossing will sometimes cost
you food or a robbery). Position becomes **lost** the first time, because nothing
in the map says where it went. It need not stay that way: the destination is fixed,
so it is knowable.
_Avoid_: warp, jump, portal

A Device can cause one — the stoneworks' `S2` and `S3` stones, and the labyrinth
Riddle. It is the only Device effect that lands on the person rather than the
world, which is why it is neither Latching nor Toggling and why a Reset does not
touch it.

A Teleport Device's destination is **fixed**: the same Device always lands you in
the same Room. What varies is which Device you reach. The shrine's "If on way out
Push Stone to go to !" on `S3` says when you will be standing there, not that the
stone behaves differently — `[S2]` always goes to `[S3]`, and `[S3]` always goes
to `[!]`.

So a Teleport Device **has a destination Room**, and once that is known the
crossing can be recorded. Not as a compass direction — that would invent a grid
delta and a reverse which do not exist — but under a direction name of its own. The
ferry is the worked example: `docks --passage--> docks-1` and back, where `passage`
is its own reverse (`verify.ts:16`) and carries no delta, so it joins two Rooms
that share a name without distorting either town's coordinates. What the stone
Teleports still need is exactly this treatment.

Most Teleports are **one-way**: `[S2]` reaches `[S3]` and nothing comes back. The
ferry is the exception, and only because there is a Device at each end — you `buy
passage` from whichever dock you are standing on, so the pair is two Devices, not
one that runs both ways.

Not every Teleport comes from a Device. `use heartstone` is a carried item, so it
works from any Room, and its destination is fixed like any other: the temple in the
first town. That makes it the escape from a Room whose only way on is behind a Seal
whose Device is on the far side — the situation a Reset creates for anyone who was
past it when the BBS went down.

Those two stones are the only way through Stoneworks level 1 in either direction —
`[S2]` to go deeper toward the third town, `[S3]` to climb out toward the desert.
So the way in and the way out are different paths, which is part of why a Route is
a one-directional step list and not something you can reverse.

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
thing we get for free about a Room and the best available cross-check on the
Exits we recorded.
_Avoid_: brief, long description, and **identifier** — see below: it is not one

A Description **changes with Device State**, so it is not stable and not an
identity. The riddle chamber, before and after `say komi`:

- shut: "…south and east through stone archways **fitted with massive iron doors**."
- open: "…south and east through stone archways **which stand open to bare stone
  corridors**."

Same Room, same `ex`, different prose. `[D1]` is the same story told the other
way: "The northern portion of this chamber is obscured by a strange mist. The
only visible exit is east" — the mist *is* the Seal, written into the
Description, and "only visible" is the game being careful where we were not.

Two consequences. What we store is whatever state the Room was in when we last
looked, not a fact about the Room — 1087's stored text is the post-komi variant.
And a Description that differs from one we hold is **not** evidence of a
different Room: it may be the same Room with a Device thrown. The reverse still
holds, though, which is what the cross-check rests on — prose naming an Exit the
graph lacks, or lacking one the graph has, is worth investigating either way.

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
Something blocking access, which can be cleared and comes back at the next Reset.
Usually it blocks an Exit: a Door cleared with a key, a wall or a mist cleared by
operating a Device elsewhere, a raised drawbridge over a chasm. It can also block a
**Device** — the tapestry in Hewn Granite hangs over a lever, and until it is moved
aside the lever cannot be pulled.
_Avoid_: wall, mist, barrier, blockage — each of those is one kind of Seal, not
the category

A Seal does not remove the Exit it sits on. `[D1]` answered `Exits: n,e.` and
then refused `n` in the same breath, and a hobgoblin bounced off it twice while
we watched. So `ex` reports topology, and passage is Device State.

It does show in the **Description**, though, which is the one place the game
admits it: a mist over the archway, or doors that are "fitted with massive iron"
rather than standing open. So `look` tells you whether a Seal is shut right now
and `ex` never does — and that is also why a Description is not an identity.

**Door**:
A property of a single Exit: that it stays shut until opened with a particular
key, recorded as the Door's material plus that key. The Seal whose key is an
object you carry. There is no key→Door rule to infer: ten different keys each
open some "stone door", so the pairing belongs to the specific Exit and nowhere
else.
_Avoid_: lock, gate, barrier, exit

**Device**:
Something you operate in one Room that changes the world, usually somewhere else.
Each Device names its own command, and the list is open: so far a **lever**
(`pull lever`), a **stone** (`push stone`), a Riddle (`say <answer>`) and a
**tapestry** (`move tapestry`). A Device's *effect* is a map fact worth recording;
what it has currently done is Device State, which the next Reset throws away.
_Avoid_: mechanism, switch, trigger (a trigger is a baud pattern-match on server
output — unrelated)

A Room holds zero or more Devices, and a Device belongs to the Room you *operate*
it in, never the Room it affects — those are usually different, which is why the
coupling lives in a room note rather than as a column. Where a Room holds two they
can be **ordered**: in Hewn Granite the lever is behind the tapestry, so
`move tapestry` ("You pull the tapestry aside...") must come before `pull lever`
("You pulled the lever."), and the drawing marks that Room `[M]` for both.

Operating one can be refused outright — "Sorry, you can't do that now." with a
monster still up, "You must rest a moment before proceeding!" while winded. So a
Device is not a command that always takes, which matters for a Route step that
advances on a pause rather than on an answer.

A Device is a **fixture of a Room**: you must be standing there. Something you
carry that has the same sort of effect is not a Device, however alike they look —
a key clears a Seal and a heartstone causes a Teleport, and neither belongs to a
Room.

And Device State is **shared by everyone on the BBS**, not held per character. One
player's pull opens the Seal for all of them. That is what makes the level-3 lever
protocol necessary — one character pulls, the rest walk `no-pull-lever` — and it is
also the way out when a Reset leaves someone on the wrong side of a Seal whose
Device is on the other: another player can work it for them.

**Device effect**:
What a Device changes — either **the world** or **the person**, and the split
governs everything else about it. A world effect is a Seal opened or shut, a Trap
disarmed or armed, or Light on or off across a collection of Rooms. A person
effect is always a Teleport.
_Avoid_: outcome, result, action

Only world effects leave Device State behind, so only they are Latching or
Toggling. That is not a footnote about Teleports being odd, it is the reason: a
Reset rebuilds the world, and the person is not part of the world.

So a person effect asks nothing of you. A Teleport Device works every time it is
worked, there is no "has it been thrown today" to find out, and a Reset has
nothing to put back — it rebuilds the world and the stone still teleports. A world
effect is the exact opposite, which is the whole reason a Toggling Device is
dangerous to touch.

Seals and Traps are the common pair, eleven of the sixteen Devices the shrine
drawings document.

Two things the split does not do. It does not follow the verb: `push stone`
teleports in one Room and has a world effect in another — "you feel the floor
vibrate faintly" (`docs/hidden-stone-teleport.md`) — so a Device is classified by
what it does and never by how it is worked. And it does not own Teleports: the
great-lake ferry is bought, not operated, so not every Teleport is a Device
effect.

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
