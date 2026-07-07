# Baud Script for Tele-Arena

Learn more about Tele-Arena here: https://www.mbbsemu.com/Module/TSGARN

# Mapping

The script can build a live map of the world as you walk it. While mapping is
on, every room you enter is recorded — its name, description, exits, and an
`(x, y, z)` coordinate dead-reckoned from your moves (north is +y, east is +x,
up is +z). Identical rooms (every cave is named "cave") are told apart by that
coordinate, so loops close correctly instead of collapsing into one room. Traps
and locked doors are captured as you hit them. The map is stored in
`tele-arena.db` and rendered by `just report`.

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
