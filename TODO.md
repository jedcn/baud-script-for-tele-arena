# TODO

Working list. Checked items stay, with what settled them, so a question does not
get asked twice.

## First town — 13 rooms

- [ ] **Visual check.** `just report`, look at first town, say whether it matches
      the game as you know it.
- [ ] **Sort out `weapon-shop nw`.** It is one-directional and crosses towns:

      weapon-shop (first-town) --nw--> underground-plaza (third-town)

      and `underground-plaza` does not point back — its exits are ne, nw, se, sw,
      all inside third town. You cannot walk from town 1 to town 3, so this edge
      is wrong. `ta_nav.lua` already warns about "two edges into third-town
      visibly mis-mapped"; this is one of them.

      In game: stand in the weapon shop and `ex`.
        - if `nw` IS listed -> the exit is real, the destination is wrong. Set
          `to_id = NULL` so it reads as unwalked, and walk it properly.
        - if `nw` is NOT listed -> the whole row is bogus. Delete it.

- [ ] **Get a description for `docks`.** It is the only first-town room without
      one, and no session log has ever captured it. In game: go to the docks and
      `look`.
- [ ] **Declare first town "no known issues"** once the three above are done and
      `just verify-area first-town` is clean.

## Sewers level 1 — 63 rooms

- [ ] **8 edges whose coordinates contradict the direction walked**, in four
      pairs:

      town-sewers-5  <-> town-sewers-14      town-sewers-18 <-> town-sewers-42
      town-sewers-54 <-> town-sewers-59      town-sewers-60 <-> town-sewers-61

      Topology is fine — every exit is reciprocal and nothing dangles. It is the
      stored x/y that drifted, the same fault that broke the desert. Harmless for
      routing; it would mint duplicate rooms if anyone mapped through there again.

## Counts that differ from the shrine drawings

Neither is understood. Could be us, could be the drawing, could be a version
difference.

- [ ] `first-dungeon-level-1` — we have 51 rooms, the drawing has 50
- [ ] `sewers-level-1` — we have 63, the drawing has 65
- (`sewers-level-3` reads 56 against 53, which is expected: we deliberately file
  the two pits and the two-room desert shaft there)

## Regions with no data

- [ ] **The desert.** Deleted after a corrupted re-walk. The drawing has 103
      rooms; author it from `map/shrine/desert.txt`.
- [ ] **The stoneworks.** Deleted; 199 rooms held against the drawings' 267
      across six levels. Author from `map/shrine/stoneworks-1..6.txt`.
- [ ] **Third town.** 10 rooms, only reachable edges are the two mis-mapped ones
      above. No shrine map scraped for it yet.

## Bigger threads, not started

- [ ] Make the JSON the source of truth rather than an export of SQLite.
- [ ] A router: "I am here, take me there", with keys, runes and levers as
      constraints. Replaces hand-copied `navigate-to` step lists.
- [ ] The static HTML map site.
- [ ] Have the mapper write JSON, so a new region is authored the same way.

## Settled

- [x] **Position tracking works.** `where` in game follows you room by room,
      independently of mapping. Watched working through the first dungeon,
      2026-09-09.
- [x] **Typing ahead corrupted the map.** Two moves sent before the first arrival
      overwrote a single `pendingDirection` slot, so arrivals were matched to the
      wrong direction — and the mapper writes edges from that field. Now a queue.
- [x] **The automatic shrine/database matcher is removed.** One wrong pairing
      silently poisoned every pairing after it. See `plans/map-schema.md`.
