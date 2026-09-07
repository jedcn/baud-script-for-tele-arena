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
| **Persistence and reset** | levers and pushed stones are permanent; doors re-lock daily, server-wide; one character's lever pull serves everyone | nothing |

The last two are the reason this survey is worth doing before building. A
coupling is an edge between two rooms that is not an exit, and nothing in the
schema can hold one.

## Survey queue

- [x] First town, second town
- [x] First dungeon, levels 1-3
- [ ] Sewers beneath town 2
- [ ] Stoneworks, levels 1-6
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
