# TODO

Working list. Checked items stay, with what settled them, so a question does not
get asked twice.

## First town — 13 rooms

- [x] ~~**Visual check.**~~ **Done 2026-09-09.** First town matches the game and
      the shrine drawing.

      The report marks defects: a room with a known problem gets a red ring and a
      ⚠, clicking it lists what is wrong, and a bar above the map counts them
      with a button to jump to one. So a fix can be seen to have landed rather
      than taken on trust. It started at

          ⚠ 19 known problems in 19 rooms — 16 coords, 1 no-description, 2 one-way

      and everything outside sewers level 1 has since been cleared.
- [x] ~~**Sort out `weapon-shop nw`.**~~ **Done 2026-09-09.** Confirmed in game:
      the weapon shop has exactly one exit, `w`. The `nw` row was deleted. First
      town now passes reciprocity, and the report's count went 19 -> 18.

      What it was:

      weapon-shop (first-town) --nw--> underground-plaza (third-town)

      and `underground-plaza` does not point back — its exits are ne, nw, se, sw,
      all inside third town. You cannot walk from town 1 to town 3, so this edge
      is wrong. `ta_nav.lua` already warns about "two edges into third-town
      visibly mis-mapped"; this is one of them.

      `nw` was not listed in game, so the whole row was bogus and went.

- [x] ~~**Get a description for `docks`.**~~ **Done 2026-09-09**, captured in game
      and cross-checked: the text says "an ornately carved marble archway exits
      through the town wall to the south into the guild hall", and our map has
      `docks --s--> guild-hall`. The two agree.

      To capture one this way in future: `map-here <slug>` then `look`. The
      description capture needs `currentRoomId`, which is only set while mapping,
      so a bare `look` with mapping off records nothing.

- [x] ~~**Declare first town "no known issues".**~~ **Done 2026-09-09.**
      `just verify-area first-town` passes every check, and `just report` says
      "no known problems" for it. 13 rooms, matching the shrine drawing's 13.

## Third town — 14 rooms

- [x] ~~**`underground-plaza-1 nw -> equipment-shop`**~~ **Done 2026-09-09**, and
      it was not what either of us expected. The exit is REAL; what was wrong was
      where it went. Third town has its own equipment shop, and

          first-town/equipment-shop    exits: se -> north-plaza
          third-town equipment shop    exits: se

      are identical by name and exit-set, so the mapper could not tell them apart
      and linked to first town's. Same fingerprint failure as everywhere else.
      Now `equipment-shop-2`, with its description captured on the walk.

      Neither of the two edges ta_nav.lua warns about survives: one was a
      phantom exit, one was a real exit to a conflated room. No town links to
      another town any more except the docks ferry, which is real.

- [x] ~~**Two armor shops.**~~ **Done 2026-09-10.** There is one, and the shrine
      drawing was right.

      It unravelled from a wrong description. Room 1012, the northwest plaza, was
      carrying the southwest plaza's text byte for byte — "southwest corner",
      "town square to the northeast", archways nw/se/sw. Captured the real text
      in game; it names three ways out, ne/nw/se, and `ex` agreed:
      `Exits: ne,se,nw.` Our graph had a fourth, `sw`, with a room on the end of
      it whose description was in turn a copy of the real armor shop's.

      So an armor shop already recorded off the southwest plaza got recorded a
      second time off the northwest one. The edge was deleted outright rather
      than re-stubbed to NULL — the usual re-stub rule protects a frontier you
      still mean to walk, and there is no southwest exit to walk. The survivor
      took the freed slug, `third-town/armor-shop-2`.

      Worth remembering: the slug suffix is a global counter, not a per-area one.
      `armor-shop-1` is second town's. There is no `third-town/armor-shop-1`.

- [x] ~~**Declare third town "no known issues".**~~ **Done 2026-09-10.** 14 rooms,
      one armor shop, and the drawing matches the shrine's. `just verify-area
      third-town` passes everything except the unwalked exit below, which is a
      hole in the stoneworks rather than in third town.

- [ ] **`stonework-corridor-175 e` is unwalked** — the only remaining hole. It is
      third town's door into the stoneworks, so walking it needs the stoneworks
      re-mapped first, or it will mint rooms into third town.
- [ ] No shrine map scraped for third town; there may not be one.

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
