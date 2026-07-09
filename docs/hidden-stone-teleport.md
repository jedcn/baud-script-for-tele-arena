# Finding: hidden "push stone" teleport (mapper blind spot)

**Status:** documented, code left unchanged (per user, 2026-07-09). Only one
instance seen so far — may be the only teleport in the game. If more turn up,
fix the mapper (see below).

## What happened

In `logs/session-tojolias-2026-07-09T16-26-33.log`, Tojolias reached
`stonework-corridor-28` (#606) — a dead-end whose look reads:

> A stone in the northeast wall appears to protrude from the wall slightly more
> than the others. The corridor continues to the northwest.
> Exits: nw.

Doing `push stone` there **teleported** him to a different, otherwise
unreachable room:

```
> push stone
push stone
You push the protruding stone into it's recess...You're in a stonework corridor.
There is nobody here.
There is nothing on the floor.
> ex
Exits: e.
```

Room #606's only real exit is `nw`; the destination's only exit is `e` — a
different room.

### Not the same as the earlier stone

Earlier in the same session, `push stone` in `stonework-corridor-13` (#589)
produced a *remote* effect, not a teleport:

```
As you push the protruding stone into it's recess, you feel the floor vibrate faintly.
```

So "push stone" is overloaded: sometimes a remote trigger ("floor vibrate
faintly"), sometimes a teleport ("...You're in ...").

## Why the mapper couldn't catch it

The room-entry trigger is anchored to the start of the line:

```lua
main.lua:1177  createTrigger("^You're in (.+)\\.$", handleRoomEntry, { type = "regex" })
```

On a teleport the game glues the arrival onto the tail of the push response —
`You push the protruding stone into it's recess...You're in a stonework corridor.`
— so the line starts with `You push…` and `^You're in ` never matches.
`handleRoomEntry` never runs, `currentRoomId` stays 606, and the following `ex`
(`Exits: e.`) is misattributed to #606, adding a phantom `e→NULL` exit to it.

## Manual repair applied to `tele-arena.db` (2026-07-09)

Snapshot: `db-snapshot 9976108` in `../tele-arena-db`.

1. Deleted the phantom `606 e→NULL` exit (#606 keeps only `nw↔605`).
2. Created `stonework-corridor-29` (#607) as the teleport destination
   (area 12, one unexplored `e→NULL` exit; description NULL — never `look`ed;
   coords NULL — a teleport has no grid position).
3. Added a room note to #606:
   `push stone here to teleport onward (hidden exit -> stonework-corridor-29 #607; not a walkable compass edge)`

The teleport is intentionally **not** modeled as a compass edge — #607 is a
standalone node, and the coupling is captured by the note. If teleports become
common, revisit this (e.g. a dedicated link type, or a mid-line arrival trigger
that fires on the `...You're in` splice).
