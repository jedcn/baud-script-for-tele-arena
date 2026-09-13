# Baud Script for Tele-Arena

Learn more about Tele-Arena here: https://www.mbbsemu.com/Module/TSGARN

# Mapping

The script can build a live map of the world as you walk it. While mapping is
on, every room you enter is recorded — its name, description, exits, and an
`(x, y, z)` coordinate dead-reckoned from your moves (north is +y, east is +x,
up is +z). Identical rooms (every cave is named "cave") are told apart by that
coordinate, so loops close correctly instead of collapsing into one room. Traps
and locked doors are captured as you hit them, and you can attach freeform
[room notes](#room-notes) for mechanics the graph can't express. The map is
stored in `tele-arena.db` and rendered by `just report`.

Move with the normal direction aliases — `n s e w ne nw se sw u d`. While
mapping, each move both walks you in-game and advances your position on the map.

## Starting / resuming

Mapping is turned on by one of two commands, depending on the situation — there
is no separate "mapping on":

- **`map-area <slug> [display name]`** — start mapping a **fresh** area from the
  room you're standing in, e.g. `map-area mountains` or
  `map-area mountains The Misty Mountains`. It tags the area (new rooms inherit
  it) and begins mapping here, cold-starting by the room's name. Use this for a
  never-before-mapped area or when your current room has a unique name. It also
  **re-files the room you're standing in** into the new area — see
  [Connecting a new area across a seam](#connecting-a-new-area-across-a-seam).

- **`map-here <slug>`** — resume mapping in an **already-mapped** area by
  anchoring at a known room, e.g. `map-here filthy-cavern`. Use this when the
  room name is ambiguous (every `cave` is "cave", so a name lookup can't tell
  them apart). It sets your position exactly from the room's stored record, so
  your next move dead-reckons from the right place.

- **`map-off`** — stop mapping. The map is left untouched during normal play.

## Connecting a new area across a seam

When a new area is reached through an exit of an area you've already mapped —
e.g. a `down` from a town room leads into the sewers — that doorway (the
**seam**) needs to belong to *both* areas: the exit stays on the old area's
room, and the room on the far side belongs to the new area.

Walk it in this order:

1. **`map-here <room>`** — anchor on the old-area room that holds the exit into
   the new area (use its unique slug; seam rooms often share an ambiguous name).
   This gives you a connected session so the crossing gets linked.
2. **Walk through the exit** and stop on the first room of the new area. The
   crossing is recorded automatically (the exit and its reverse are linked), but
   that first room is still filed under the **old** area for now — the exit that
   discovered it lived on an old-area room.
3. **`map-area <slug> [display name]`** — register the new area, make it current
   for everything you map from here on, **and move the room you're standing in
   into it**. That last part is what splits the seam cleanly: the exit stays on
   the old area's room, and its destination now lives in the new area.

Then keep walking to map the rest.

Because `map-area` re-files whatever room you're anchored in, run it **only once
you've actually stepped into the new area** — if you run it while still standing
on a room that belongs to the old area, it will move that room too.

## Finding out where you are

- **`map-print-room-slug`** — read-only: identifies the room you're standing in
  by its name + exits and prints the matching slug (or every candidate, with
  coordinates, when several rooms match). Use it to decide what to pass to
  `map-here`. Prints a hint if it looks like a brand-new room.

## Managing areas

- **`map-list-areas`** — print every mapped area's slug.

- **`map-reset-area <slug>`** — wipe one area's rooms and exits so you can
  re-walk it from scratch (e.g. after a messy first pass), e.g.
  `map-reset-area first-dungeon`. Leaves every other area intact. Follow it with
  `map-area <slug>` to begin re-mapping.

## Devices

A **Device** is something you operate to change the world: a lever, a stone, a
spoken riddle answer, a tapestry to move aside. They are the mechanics the exit
graph cannot express on its own, because a Device is almost never in the room it
affects — a lever here disarms a trap twenty rooms away.

Recorded structurally, not as prose, so the map can be reasoned about. The
vocabulary is `GLOSSARY.md`'s and the columns follow it.

A Device belongs to the room you **operate** it in. Its `effect` is one of four:

| effect | what it acts on |
|---|---|
| `seal` | opens (or toggles) a **Seal** — a shut door, a wall, a mist |
| `teleport` | moves whoever worked it, always to the same room |
| `trap` | disarms (or re-arms) the trap in some room |
| `light` | lights a whole **area**, never a single room |

- **`map-add-device <effect> <command>`** — record one in the room you're
  standing in, e.g. `map-add-device seal pull lever`,
  `map-add-device teleport push stone`, `map-add-device seal say komi`. The
  effect comes first so the command can contain spaces. Prints the new id.

- **`map-device-repeats <id> once|toggle`** — whether working it again does
  anything more *this Reset*. `once` and the Seal stays open however many times
  you pull; `toggle` and the second pull shuts it. Refused for a teleport, which
  is neither — it fires every time and leaves no state behind.

- **`map-device-dest <id> <room-slug>`** — where a teleport lands you.
- **`map-device-trap <id> <room-slug>`** — the room whose trap it disarms.
- **`map-device-light <id> <area-slug>`** — the area it lights. One argument
  names both area and level, since the level lives in the slug
  (`labyrinth-level-2`).
- **`map-device-behind <id> <other-id>`** — this Device can't be worked until
  that one has been. The Hewn Granite case: the lever is behind the tapestry, so
  `move tapestry` comes first.
- **`map-device-note <id> <text>`** — free text, attached to the Device it's
  about rather than scattered on a room.
- **`map-devices`** / **`map-devices <room-slug>`** / **`map-devices all`** — list.
- **`map-del-device <id>`** — remove it, un-pointing anything that named it.

### Seals

A Seal is recorded on the **exit it blocks**, naming the Device that opens it —
the same place and shape as `lock_key`/`lock_door`, which is the Seal a carried
key clears.

- **`map-seal <dir> <device-id>`** — the exit `dir` out of the room you're in is
  sealed, and that Device opens it.
- **`map-seal <room-slug> <dir> <device-id>`** — for an exit elsewhere, which is
  the usual case: the Device and the Seal are normally rooms apart.
- **`map-unseal <room-slug> <dir>`** — it turned out not to be sealed.

Recording it this way round is what lets **one Device open several Seals** —
`say komi` opens two doors, which a single target column on the Device could not
express.

Two things this deliberately does not do. A Seal does **not** remove the exit it
sits on: `[D1]` answered `Exits: n,e.` and refused `n` in the same breath, so
`ex` reports topology and passage is a separate question. And nothing records
whether a Device has been worked **today** — that's Device State, a fact about
this Reset rather than about the map, and it would be wrong by 4am.

Devices surface on **room entry** as `[device] …` while mapping, so a lever
reaches you before you walk past it, and in the `just report` room panel.

## Viewing the map

- **`just report`** — regenerate and open `report.html`. The World Map is an
  interactive, pannable/zoomable graph; click a room (or a locked-door line) for
  details. Multiple floors (reached by `u`/`d`) get their own tabs. Colors:
  - **area color** — normal rooms, one hue per area
  - **red** — a room with a trap (the trap is named in the detail panel)
  - **orange line + 🔒** — a locked door (click it for the door, the rooms it
    joins, and the key)
  - **yellow** — "you are here" (a character's last known room while mapping)
  - **dashed octagon** — a known but unexplored exit (a frontier to walk)

  Any [room notes](#room-notes) you've added show in the clicked room's detail
  panel under **Notes**.
