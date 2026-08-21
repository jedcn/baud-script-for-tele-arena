--
-- Navigation: `navigate-to <area>/<room>` and everything it needs.
--
-- Loaded by main.lua with dofile, and in its own file for a concrete reason:
-- Lua allows at most 200 local variables active at once in a single function,
-- and a file IS a function -- so every top-level `local` in main.lua drew from
-- one budget that was down to two free slots. A separate chunk gets its own
-- 200. This section was the natural first cut: the widest block in the file
-- with the narrowest seam.
--
-- The seam runs through taPackage, the shared state table, because locals are
-- not visible across chunks:
--
--   in    taPackage.nowMillis, taPackage.trimLine, taPackage.stopKill,
--         taPackage.killAllScan  (all defined in main.lua)
--   out   taPackage.stopNavigate, taPackage.navOnSweepDone,
--         taPackage.navOnRoomBrief, taPackage.navWanted, taPackage.navItemPhrase
--
-- Add to that list rather than reaching for a main.lua local: it won't be
-- there. A field costs no local slot, unlike a declaration.
--
-- =========================================================================
-- Navigate to a destination
-- =========================================================================
--
-- `navigate-to <area>/<room>` walks a hand-written route from one known room to
-- somewhere far away. We deliberately don't path-find over the mapped graph:
-- it's full of unwalked stubs and locked doors the graph can't reason about,
-- and its two edges into third-town are visibly mis-mapped. Every route here is
-- a step list copied from a walk that actually worked.
--
-- Each route names the single room it starts from. Before moving we identify
-- the room we're standing in by name + exit-set -- the same fingerprint
-- `map-print-room-slug` uses, because names alone are hopeless here (194 rooms
-- are called "cave", 176 "stonework corridor", 170 "town sewers") -- and refuse
-- to walk unless it is that room. The two rooms named "north plaza" make the
-- point: they differ only by exit-set, so a name-only check would happily walk
-- the sewers route from the wrong town.
--
-- A route's KEY IS A LABEL, not a room reference: `town-3/get-ruby-key` names
-- an errand, and the errand ends where it began. Where a route does end
-- somewhere nameable, `to` gives the room so arrival can be checked.
--
-- A route's steps are not all movement. Getting to third-town means levers to
-- pull, stones to push, and rooms to clear for a key, so a step is one of:
--
--     "se"                  -- a direction; the arrival brief advances the walk
--     { cmd = "pull lever" } -- any command; the walk advances after a pause
--     { killAll = true }     -- clear this room; the sweep advances the walk
--
-- Each leg is deliberately short and run by hand. Chaining them is a later
-- decision; for now every one is a thing you ask for and watch.
--
-- `door` is an optional final probe: a direction out of the destination that is
-- known to be gated by a locked door. We walk the route, then try it, and
-- report whether we could pass. Fetching the key is a separate errand.
--
-- THE MAP IS READ-ONLY HERE. Navigating asks the map where it is and never
-- tells it anything: no room is discovered, no visit counted, no exit linked,
-- no coordinate stamped, no player location moved. Two things enforce that.
-- First, every DB call in this section is a SELECT. Second, a walk suspends
-- mapping mode for its duration (navStart), because with mapping ON the plain
-- arrival briefs we generate would otherwise flow into handleRoomEntry and be
-- recorded. Mapping stays off afterwards: sixteen scripted rooms leave the
-- mapper's anchor far behind, and silently resuming would mis-link every
-- manual move that followed. The user is told to re-anchor with `map-here`.
-- `killAll` clears the destination of monsters on arrival, which is how we get
-- at a key: the game auto-searches each corpse, and a key turns up in one of
-- them ("While searching the area, you notice a ruby key...").
local NAV_ROUTES = {
    -- The other eight legs in one, from the junction all the way to third town.
    -- With after-doors before it the whole journey is two commands.
    --
    -- Where after-doors had to decide things, this one only has to walk. Every
    -- key it needs is fetched by a leg inside the run -- the hydra's sweep drops
    -- the pearl key that opens both of the entrance leg's pearl doors -- so
    -- there is nothing here to branch on, and it is a concatenation.
    --
    -- Two things it does need in the pack before it sets off, and they strand
    -- you in different places: the rope in the hydra's pit, the verbena potion
    -- out in the desert with the poison already working.
    --
    -- Its first step is the onyx door (63 --s--> 117), which after-doors leaves
    -- open behind it. Left as a plain move rather than a gate: run the two back
    -- to back and it cannot be shut, and if you have paused across the 3am
    -- relock the refusal already names the onyx key.
    --
    -- The seams are the part worth keeping. Run by hand each leg checks its own
    -- starting room first, and for the six stoneworks legs that is the only
    -- check there is -- nothing down there is mapped. Joining them would have
    -- thrown six of those away, so navRouteSteps puts one back at every join.
    --
    -- 364 steps: 359 across the eight, less the temple leg's last two, plus the
    -- seven seams. Half an hour or so with the hydra fight and the sweep.
    ["town-3/after-doors-to-town-3"] = {
        from     = "sewers/town-sewers-63",
        to       = "third-town/town-square",
        requires = { "coil of rope", "verbena potion" },
        onPoison = "drink verbena",
        legs     = { "town-3/hydra",
                     "town-3/stoneworks-entrance",
                     "town-3/stone-lvl-2",
                     "town-3/stone-lvl-3",
                     "town-3/stone-lvl-4",
                     "town-3/stone-lvl-5",
                     "town-3/stone-lvl-6",
                     -- Stop in the town square. The temple leg's last two steps,
                     -- `ne` then `e`, carry on past it into the underground
                     -- plaza and then the temple; the square is where town-2
                     -- starts, so stopping there closes the round trip.
                     { route = "town-3/temple", drop = 2 } },
        -- An alternative ending for when the chasm is passable.
        --
        -- The temple leg's two levers drop walls that clear the walk across the
        -- chasm, and like every lever and stone on the way to third town they
        -- stay dropped -- the same thing that makes the way home 201 steps
        -- against the outward chain's 438. So on a later run there is nothing
        -- to go and pull: the walls are already down, and this takes the short
        -- way across instead of the long way round to two levers it doesn't
        -- need.
        --
        -- Where the chasm sits in the ordinary ending: the closing run of seven
        -- `w`, steps 95-101 of the temple leg's 103. With the walls up it
        -- refuses -- the walk of 2026-08-03 was stopped on step 96,
        --
        --     [nav|t] 20:56:07 +1503ms  send step 96/103 w
        --     The wide chasm prevents your exit in that direction.
        --
        -- "A very wide natural chasm blocks the passage to the west," said the
        -- room. That walk got across by retrying, which is what the ordinary
        -- ending still does.
        --
        -- The steps live on town-3/temple, whose ending this is; naming the leg
        -- and nothing else borrows them. That way stopping at the temple seam
        -- and running `navigate-to town-3/temple chasm-is-clear` by hand walks
        -- the same 47 steps as the chain does -- which is what you want when a
        -- 310-step walk dies on floor four.
        -- No longer just an ending. It began as one -- the temple's two levers
        -- and the chasm they clear -- but the same permanence holds all the way
        -- down: every lever and stone on the way to third town stays thrown, so
        -- on a later run each level has a shorter way through it, and this is
        -- the name for "they are all already thrown".
        --
        -- `fromLegs` therefore, rather than a leg and an ending: each leg that
        -- has a chasm-is-clear of its own uses it, and the ones that don't are
        -- walked as usual. The temple's is unchanged by the switch -- it is the
        -- last leg, so replacing it and carrying on IS ending there.
        --
        -- Read it as a claim about the LEVERS, not about the chasm. Pulling
        -- them disarms the traps along each level as well as dropping the
        -- walls, and both stay done -- so asking for `chasm-is-clear` says
        -- "every lever on the way has been pulled at some point". On a
        -- character who has never made the outward walk it takes the short way
        -- past traps that are still armed. The chasm is just the obstacle you
        -- can see from the ordinary route; the traps are the ones you can't.
        variants = {
            ["chasm-is-clear"] = { fromLegs = true },
        },
    },
    -- The first four legs in one, from second town's north plaza to the junction
    -- the three doors open off. They were always run in this order and always
    -- for the same reason -- get through the ruby, platinum and onyx doors so
    -- the hydra leg can be walked -- and three of the four are errands you only
    -- need SOMETIMES. The doors relock around 3am but a key once fetched is
    -- kept, so on any given day some of those errands are wasted work and some
    -- are essential, and nothing tells you which from the north plaza.
    --
    -- Hence the gates. Each door is walked at, and the game's answer is the
    -- decision: through it means the key isn't needed, refused means fetch it
    -- (see the locked-door trigger, which splices the errand in and tries the
    -- door again). 22 steps with all three already open; about 78 with none.
    --
    -- The doors, as the map records them:
    --
    --     town-sewers-18 --s--> 62    ruby      (and 62 --d--> 63)
    --     town-sewers-63 --e--> 106   platinum
    --     town-sewers-63 --s--> 117   onyx
    --
    -- The platinum and onyx doors both hang off 63, and -- this is the part
    -- worth knowing -- neither is walked by the errand that fetches its own key.
    -- get-platinum-key never goes near the platinum door, and get-onyx-key opens
    -- BY going through it. So each door is tried here and stepped back from,
    -- rather than left for its errand to discover. Two moves apiece, and it is
    -- what makes the three checks read the same way.
    --
    -- Ends where get-onyx-key ends, at the junction, which is where the hydra
    -- leg begins.
    ["town-3/after-doors"] = {
        from  = "second-town/north-plaza",
        to    = "sewers/town-sewers-63",
        steps = { -- town-3/ruby-door's sixteen steps, down to town-sewers-18.
                  "sw", "d", "se", "sw", "s", "se", "se", "sw",
                  "se", "se", "ne", "ne", "se", "se", "se", "e",
                  { door = "s", key = "ruby", detour = "town-3/get-ruby-key" },
                  "d",   -- 62 down to 63, the junction
                  { door = "e", key = "platinum", detour = "town-3/get-platinum-key-from-63" },
                  "w",   -- back from 106 to the junction
                  { door = "s", key = "onyx", detour = "town-3/get-onyx-key" },
                  "n" }, -- back from 117 to the junction
    },
    -- Second town down into the sewers, ending nose-to-nose with the ruby door.
    -- The door probe reports whether it's locked, which is what tells you
    -- whether you need the get-ruby-key errand: the door relocks around 3am.
    ["town-3/ruby-door"] = {
        from  = "second-town/north-plaza",
        to    = "sewers/town-sewers-18",
        steps = { "sw", "d", "se", "sw", "s", "se", "se", "sw",
                  "se", "se", "ne", "ne", "se", "se", "se", "e" },
        door  = { dir = "s", key = "ruby" },
    },
    -- Out to the room the ruby key drops in, clear it, and come back to the
    -- door. The return leg is the forward leg reversed direction by direction,
    -- checked against the mapped graph -- it lands back on town-sewers-18.
    ["town-3/get-ruby-key"] = {
        from  = "sewers/town-sewers-18",
        to    = "sewers/town-sewers-18",
        steps = { "e", "ne", "n", "ne", "ne", "nw", "nw", "n", "ne", "se", "se", "se",
                  { killAll = true, untilFound = "ruby key" },
                  "nw", "nw", "nw", "sw", "s", "se", "se", "sw", "sw", "s", "sw", "w" },
    },
    -- Through the ruby door and out to the platinum key's room, then back as
    -- far as town-sewers-63 -- the junction the platinum and onyx doors open
    -- off, which is where you want to be standing with the key in hand, not
    -- back up at the ruby door.
    --
    -- Three `ne` up the corridor, not four -- the graph caught the extra one,
    -- and its mirror in the return leg. Every step of both halves now walks
    -- through the mapped graph: out to town-sewers-101 and back to -63.
    ["town-3/get-platinum-key"] = {
        from  = "sewers/town-sewers-18",
        to    = "sewers/town-sewers-63",
        steps = { "s", "d", "n", "nw", "nw", "n", "e", "ne", "ne", "ne", "n",
                  { killAll = true, untilFound = "platinum key" },
                  "s", "sw", "sw", "sw", "w", "s", "se", "se", "s" },
    },
    -- The same errand from the other end. town-sewers-63 is where the three
    -- doors meet and where the legs on either side of this one begin and end, so
    -- standing there without the platinum key is the common case -- and walking
    -- back up to the ruby door to start get-platinum-key would be two steps out
    -- and two steps back for nothing.
    --
    -- These ARE get-platinum-key's steps 3 to 21: its first two, `s` and `d`,
    -- are the walk from the ruby door down to the junction, and its return leg
    -- already stops here. Nothing new was walked to record this. The two are
    -- held in agreement by a test rather than by sharing a table, because they
    -- are transcripts of a walk before they are code, and a correction to one
    -- should be made deliberately to the other.
    ["town-3/get-platinum-key-from-63"] = {
        from  = "sewers/town-sewers-63",
        to    = "sewers/town-sewers-63",
        steps = { "n", "nw", "nw", "n", "e", "ne", "ne", "ne", "n",
                  { killAll = true, untilFound = "platinum key" },
                  "s", "sw", "sw", "sw", "w", "s", "se", "se", "s" },
    },
    -- Picks up where the platinum errand leaves off, at town-sewers-63, and
    -- opens by going east through the platinum door -- so it wants that key in
    -- hand. Out to town-sewers-113 and back to the junction; both halves walk
    -- through the mapped graph.
    ["town-3/get-onyx-key"] = {
        from  = "sewers/town-sewers-63",
        to    = "sewers/town-sewers-63",
        steps = { "e", "se", "se", "s", "e", "se", "ne", "e",
                  { killAll = true, untilFound = "onyx key" },
                  "w", "sw", "nw", "w", "n", "nw", "nw", "w" },
    },
    -- On through the onyx door and a long way north to the hydra's room, which
    -- gets cleared. One way -- no return leg was given.
    --
    -- Step 6 is the odd one: `u` climbs out of a pit. Walking east into
    -- town-sewers-148 (step 5) drops us through a trap door, and the pit's
    -- walls can't be climbed unaided, which is what `requires` is guarding.
    -- Without the rope the errand ends at the bottom of it.
    ["town-3/hydra"] = {
        from     = "sewers/town-sewers-63",
        to       = "sewers/town-sewers-165",
        requires = "coil of rope",
        steps    = { "s", "d", "ne", "ne", "e", "u", "se", "se", "e", "ne", "n", "nw",
                     "ne", "ne", "n", "nw", "w", "n", "ne", "nw", "nw", "nw", "n",
                     { killAll = true, untilFound = "pearl key" } },
    },
    -- Out of the sewers and across the desert. TWO of these steps are pearl-keyed
    -- stone doors, not one: step 2 (town-sewers-168 --w--> 169) and step 6, the
    -- crude stone building's east door out into the sandy passages. One key opens
    -- both, and it's the one the hydra drops -- so this wants that as well as the
    -- potion.
    --
    -- The cure is NOT a step. The walk that produced these directions typed
    -- `drink verbena` after the second `w`, but the poisoning is a maybe -- see
    -- onPoison above, which drinks if and when the game says we've been
    -- poisoned, and doesn't waste a potion when it hasn't.
    --
    -- Three `u` out of the sewers, not four: town-sewers-169 -> town sewer ->
    -- town sewer-1 -> the desert's crude stone building, which has exits d, e
    -- and w and no `u` to take. With that dropped the route runs cleanly for
    -- nineteen steps, out through the building's east door and down the sandy
    -- passages into the desert.
    --
    -- The map's word is worth nothing past that point, and the walk of
    -- 2026-08-03 proved it: it called step 19's `e` impossible (desert-7 having
    -- exits nw and se) and the `e` went through. Those desert rooms carry one
    -- or two visits each against the four or five behind every correction the
    -- map has earned in the sewers, and here it was simply incomplete. Nothing
    -- from step 19 on is verifiable; these directions are the walk itself.
    --
    -- That walk also settled the tail. Step 35 was `se` and there is no `se`:
    -- the room is desert-20, exits e, sw and nw, and the way into the
    -- stoneworks is `sw se s`.
    --
    -- Step 1 springs a trap -- "Several crossbow bolts fire from holes in the
    -- walls, striking you!" -- for about 44 vitality. Nothing to be done about
    -- it, but don't walk this on a sliver of health.
    ["town-3/stoneworks-entrance"] = {
        from     = "sewers/town-sewers-165",
        requires = "verbena potion",
        onPoison = "drink verbena",
        steps    = { "w", "w", "u", "u", "u", "e", "e", "s", "s", "s",
                     "w", "w", "w", "s", "sw", "sw", "sw", "sw", "se", "e",
                     "se", "e", "s", "se", "sw", "se", "s", "se", "s", "s",
                     "se", "sw", "sw", "se", "sw", "se", "s" },
    },
    -- Down into the stoneworks from the chamber the entrance route ends in.
    -- The way in is a riddle: `say komi` is the answer, and saying it is what
    -- opens the door.
    --
    -- The riddle's door is the east one, and the map is the evidence: the
    -- chamber's `e` exit is listed and has never been walked through, which is
    -- exactly the shape of a door nobody could open. Everything past it is
    -- unmapped, so there is nothing in the graph to check these directions
    -- against. Recorded as walked, and trusted as walked.
    -- The start is given as a fingerprint, not a map reference, because the map
    -- cannot pick this room out: thirteen of the twenty-four mapped stonework
    -- chambers share a name, an exit-set and a description with another, and
    -- the record for the one desert-22 leads into contradicts itself -- its
    -- description says "the only visible exits are east and west" while its
    -- edges say e, n, s and w, and standing in it `ex` answers n,e,s.
    ["town-3/stone-lvl-2"] = {
        from  = { room = "stonework chamber", exits = "n,e,s" },
        steps = { { cmd = "say komi" },
                  "e", "se", "se", "se", "sw", "sw", "se", "e", "ne",
                  { cmd = "pull lever" },
                  -- Two `n` here, not three: the walk of 2026-08-03 ran out of
                  -- corridor on the third, in a room offering only ne and s --
                  -- and `ne` is the step that follows.
                  "se", "se", "e", "n", "n", "ne", "se",
                  { cmd = "push stone" },
                  "nw", "sw", "s", "s", "w", "sw", "sw", "s", "sw", "sw", "s",
                  -- The tail, as the manual recovery of 2026-08-03 found it:
                  -- `se e se` to the dead-end corridor (exits: nw, and nothing
                  -- else) where the second stone is, and the stone opens the
                  -- `e` that leads out of it.
                  "e", "e", "e", "e", "s", "se", "e", "se",
                  { cmd = "push stone" },
                  "e", "e", "e", "d" },
        -- The short way through this level, for a run where the lever and the
        -- first stone are already thrown. Like every lever and stone on the way
        -- to third town they stay thrown, so on a later run the two detours
        -- that go and work them are 22 steps spent on nothing.
        --
        -- 29 steps against 43. It keeps the first eight -- the riddle, the door,
        -- and the six that follow -- then takes eight of its own where the
        -- ordinary route takes twenty-two, and REJOINS it exactly: these eight
        -- land where step 30 lands, and everything from there (`e e e e s se e
        -- se`, the second stone, `e e e d`) is the ordinary route's steps 31-43
        -- direction for direction. Worth saying because it is the check on the
        -- transcription: two walks agreeing on their last thirteen steps is not
        -- a coincidence.
        --
        -- The second stone is NOT skipped. It is in the shared tail, in the
        -- dead-end corridor that has no `e` until it is pushed.
        variants = {
            ["chasm-is-clear"] = {
                keep  = 8,
                steps = { "sw", "se", "e", "se", "s", "sw", "sw", "s",
                          "e", "e", "e", "e", "s", "se", "e", "se",
                          { cmd = "push stone" },
                          "e", "e", "e", "d" },
            },
        },
    },
    -- Named, but not yet walked. Each needs a starting room and a step list
    -- taken from a walk that actually worked; `pending` is what makes
    -- navigate-to say that rather than pretend the name is unknown.
    -- Level two down to level three, from the chamber stone-lvl-2 drops into.
    -- The way down is another riddle: `say arok`, three steps from the end.
    --
    -- The start is a fingerprint rather than a map reference: `w` is step 1 and
    -- `u` is the way back up to level two, and only two of the map's stonework
    -- chambers carry that pair -- neither of them this one, which isn't mapped
    -- at all.
    --
    -- Nothing here is checkable against the map, which stops at the riddle
    -- door two levels up. Six runs of a doubled direction -- s s, sw sw, ne ne,
    -- n n, ne ne, n n -- and a miscounted repeat is what went wrong three times
    -- on the level-2 leg, so those are where to look first if a step is refused.
    ["town-3/stone-lvl-3"] = {
        from  = { room = "stonework chamber", exits = "w,u" },
        steps = { "w", "sw", "w", "sw", "w", "s", "s", "e", "ne", "e", "se",
                  "sw", "sw", "se", "sw", "w", "nw", "sw", "s",
                  { cmd = "pull lever" },
                  "n", "ne", "se", "e", "ne", "nw", "ne", "ne", "nw", "w",
                  "sw", "w", "n", "n", "e", "ne", "nw", "n", "nw", "ne", "ne",
                  "e", "ne",
                  { cmd = "say arok" },
                  "n", "n", "d" },
        -- The short way through this level, for a run where its lever is
        -- already pulled. 14 steps against 47, and not a step of it is new:
        -- it is the ordinary route's first three, then its last eleven. The
        -- thirty-three it drops (steps 4-36) are one long loop out to the
        -- lever and back, and the room the third `w` lands in is the room step
        -- 36 lands in -- which is why the join needs nothing of its own.
        --
        -- What that lever does is the reason the variant is named for a
        -- condition rather than for the walls: pulling these levers DISARMS
        -- THE TRAPS along the level, and the traps stay disarmed the same way
        -- the walls stay down. So `chasm-is-clear` means "every lever on the
        -- way has been pulled at some point", not merely "the chasm is
        -- passable" -- and walking this list on a level whose lever has never
        -- been pulled walks it into live traps, not just a shut wall.
        --
        -- `say arok` stays. It is the riddle that opens the way down to level
        -- four, and a riddle door does not stay open the way a lever stays
        -- pulled -- the same reason the level-two variant still says komi.
        variants = {
            ["chasm-is-clear"] = {
                keep  = 3,
                steps = { "nw", "n", "nw", "ne", "ne", "e", "ne",
                          { cmd = "say arok" },
                          "n", "n", "d" },
            },
        },
    },
    -- Level three down to level four. No riddle on this one, just a lever
    -- two-thirds of the way along, and an unguarded `d` at the end.
    --
    -- Its start fingerprint is the same as stone-lvl-3's -- "stonework
    -- chamber", exits w and u -- so the check can't tell the two floors' start
    -- chambers apart, and running the wrong one of the legs would pass it.
    -- Left as is deliberately: these twelve are headed for three or four longer
    -- routes that carry their own state, and the collision goes away then.
    --
    -- It is a coincidence of two floors rather than a rule, though. This leg
    -- lands in a chamber with exits se and u, so stone-lvl-5 starts from
    -- something the check can tell apart.
    --
    -- Nine runs of a doubled direction: w w, sw sw, se se, s s, n n, nw nw,
    -- ne ne, n n, nw nw. A repeat counted once too often is the commonest
    -- mistake in these lists, and nothing here can be checked against the map.
    ["town-3/stone-lvl-4"] = {
        from  = { room = "stonework chamber", exits = "w,u" },
        steps = { "w", "sw", "s", "w", "w", "sw", "nw", "w", "s", "se", "sw",
                  "sw", "se", "se", "ne", "se", "e", "se", "sw", "w", "s", "s",
                  { cmd = "pull lever" },
                  "n", "n", "e", "ne", "nw", "w", "nw", "sw", "nw", "nw", "ne",
                  "ne", "nw", "n", "n", "nw", "nw", "n", "d" },
        -- The short way through this level, for a run where its lever is
        -- already pulled. 14 steps against 42, and like level three's it is
        -- made entirely of the ordinary route's own steps: its first eight,
        -- then its last six. The twenty-eight it drops (steps 9-36) are one
        -- long loop out to the lever and back, and step 37 is where the
        -- retrace lands -- so the join needs nothing of its own.
        --
        -- Nothing but directions in it, which makes it the one variant here
        -- with no command at all: this level has no riddle, and the `d` at the
        -- end is unguarded.
        --
        -- Same caution as level three, and it bites harder here because the
        -- dropped run is longer: the lever disarms this level's traps as well
        -- as dropping its walls, so this is only walkable once it has been
        -- pulled. See the chain's variants block for what the name claims.
        variants = {
            ["chasm-is-clear"] = {
                keep  = 8,
                steps = { "n", "n", "nw", "nw", "n", "d" },
            },
        },
    },
    -- Level four down to level five. One lever, no riddle, and the descent at
    -- the end is unguarded.
    --
    -- The first start check down here that can't be confused with another
    -- floor's: exits se and u, where levels three and four both start from a
    -- chamber with w and u.
    --
    -- Six runs of a doubled direction: se se, s s, ne ne, sw sw, sw sw, se se.
    ["town-3/stone-lvl-5"] = {
        from  = { room = "stonework chamber", exits = "se,u" },
        steps = { "se", "s", "se", "se", "e", "s", "s", "se", "ne", "ne", "n",
                  "ne", "nw", "ne", "n",
                  { cmd = "pull lever" },
                  "s", "sw", "se", "sw", "s", "sw", "sw", "nw", "sw", "sw",
                  "nw", "n", "nw", "sw", "w", "s", "se", "se", "s", "d" },
    },
    -- Level five down to level six. One lever, no riddle, unguarded descent --
    -- the same shape as the two floors above it, and the shortest of them.
    --
    -- Starts from a chamber with exits ne and u, which no other leg down here
    -- begins from (levels three and four start on w,u, level five on se,u).
    --
    -- Six runs of a doubled direction: ne ne, ne ne, sw sw, ne ne, nw nw, n n.
    ["town-3/stone-lvl-6"] = {
        from  = { room = "stonework chamber", exits = "ne,u" },
        steps = { "ne", "ne", "e", "ne", "ne", "se", "ne", "e", "se", "s",
                  "sw", "sw", "se", "s",
                  { cmd = "pull lever" },
                  "n", "nw", "ne", "ne", "n", "nw", "ne", "nw", "nw", "n",
                  "n", "d" },
    },
    -- Level six to the temple, and the end of the chain. No riddle at the door;
    -- two levers, each at the far end of a dead-end run that is then walked
    -- back. Those runs balance -- six n out, lever, six s back; eight s out,
    -- lever, eight n back -- which is the only self-check anything down here
    -- has, and both halves agree.
    --
    -- Much the longest leg, and much the riskiest to transcribe: twenty-three
    -- runs of a repeated direction, including 8 s, 8 n, 7 w and 6 e twice. A
    -- repeat counted once too often is what went wrong four times on
    -- stone-lvl-2, and none of this can be checked against the map.
    ["town-3/temple"] = {
        from  = { room = "stonework chamber", exits = "e,u" },
        steps = { "e", "e", "e", "e", "e", "e", "s", "e", "e", "e",
                  "s", "s", "s", "s", "w", "w", "s", "s", "s",
                  "w", "w", "w", "w", "s", "s", "w", "w", "w", "w",
                  "n", "n", "n", "n", "n", "n",
                  { cmd = "pull lever" },
                  "s", "s", "s", "s", "s", "s", "e", "e", "e", "s", "s",
                  "e", "e", "e", "e", "e", "e", "n", "n", "n", "e", "n", "n",
                  "e", "e", "e", "s", "s", "s", "s", "s", "s", "s", "s",
                  { cmd = "pull lever" },
                  "n", "n", "n", "n", "n", "n", "n", "n", "w", "w", "w",
                  "s", "s", "w", "s", "s", "s", "s", "s", "s", "w", "s", "s",
                  "w", "w", "w", "w", "w", "w", "w", "ne", "e" },
        -- The other way to finish, for when the chasm is passable.
        --
        -- The two levers above drop walls that clear the walk across it, and
        -- like every lever and stone on the way to third town they stay
        -- dropped -- the same permanence that makes the way home 201 steps
        -- against the outward chain's 438. So on a later run there is nothing
        -- to go and pull, and this takes the short way across instead of the
        -- long way round to two levers it doesn't need.
        --
        -- The chasm is in the ordinary ending's closing run of seven `w`,
        -- steps 95-101. With the walls up it refuses -- the walk of 2026-08-03
        -- was stopped on step 96,
        --
        --     [nav|t] 20:56:07 +1503ms  send step 96/103 w
        --     The wide chasm prevents your exit in that direction.
        --
        -- "A very wide natural chasm blocks the passage to the west," said the
        -- room. That walk got across by retrying, which is what the ordinary
        -- ending still does.
        --
        -- The two endings are the same walk for 26 steps and then part, so only
        -- the difference is recorded. `keep = 26` walks as far as the `w` that
        -- ends `w w w s s w`, then finishes on these twenty-one instead of the
        -- remaining 77. Step 27 is where they separate: `s` here, `w` there.
        -- 47 steps end to end against 103, and neither lever run is in them.
        --
        -- The tail is the same shape as the ordinary ending's, which is worth
        -- knowing: seven `w` on both. This one crosses the chasm rather than
        -- being turned back at it, so a `w` that refuses means the walls are
        -- NOT down -- wrong variant, and the ordinary ending is the one that
        -- works.
        variants = {
            ["chasm-is-clear"] = {
                keep  = 26,
                steps = { "s", "s", "e", "e", "e", "e", "e", "e", "s", "s",
                          "s", "w", "s", "s", "w", "w", "w", "w", "w", "w", "w" },
            },
        },
    },
    -- The way home: third town's town square all the way back to second town's
    -- north plaza, in one leg. Walked by pelayo on 2026-08-07 and taken from
    -- that log (session-pelayo-walk-back-2026-08-07T17-38-34.log), which brackets
    -- the trip with two typed markers -- "LET'S BEGIN THE JOURNEY" at the square
    -- and "WE DID IT!" at the plaza -- so the whole of it is one recorded walk
    -- rather than a derivation. That matters here: `town-1/north-plaza` is a
    -- reversal of `ruined-town` done on paper, and this deliberately is not.
    --
    -- 201 steps against the 438 the outward chain takes, and the difference is
    -- all things you only pay for once. The levers and stones turn traps OFF and
    -- open secret walls, and they stay that way -- so every lever detour the
    -- outward legs walk (six n out, pull, six s back, and its like on levels
    -- three to six) is simply not here. Nor are the key errands: the ruby,
    -- platinum and onyx doors are already open, so this walks straight through
    -- where the outward chain went out and back for a key.
    --
    -- Both ends are checked and both agree with what we already had. The start
    -- fingerprint is third town's mapped town square (id 1011, exits e/ne/nw/
    -- se/sw), and it's stated literally rather than as `third-town/town-square`
    -- so this leg still runs on a host with no map -- the same reason
    -- `ruined-town` states both of its ends. The tail is better than a check: the
    -- last two steps `u`, `ne` are the exact reverse of the first two steps of
    -- `town-3/ruby-door` (`sw`, `d`), the path between the plaza and the sewers.
    -- The three `d` into the sewers mirror that route's three `u` out. Between
    -- those ends nothing is verifiable -- the map stops at the riddle door two
    -- stoneworks levels down -- so these directions are the walk itself.
    --
    -- Two stretches of the log are NOT here, both confirmed by the user as
    -- getting lost rather than route: a wander out to the magic shop and back
    -- before the walk proper began, and `w w` into the storage rooms and `e e`
    -- back out, between the desert and the sewers.
    --
    -- `push stone` is a real step and it TELEPORTS -- it doesn't open a wall you
    -- then walk through. The game glues the arrival onto the push ("You push the
    -- protruding stone into it's recess...You're in a stonework corridor."), and
    -- that line doesn't start with "You're in", so no room-brief trigger fires
    -- for it. A `{ cmd = ... }` step is exactly right: it advances on a pause,
    -- which is the only thing that can advance it.
    --
    -- The rope is not optional. The trap door drops you into the pit going this
    -- way too (the `w` about two-thirds through the sewers prints the room and
    -- then the pit, and the `u` after it is the climb out), and the walls can't
    -- be climbed unaided. Only one item can be required, and this is the one
    -- that strands you.
    --
    -- The keys still matter even though they aren't checked: this comes back out
    -- through the onyx, platinum and ruby doors. They were open on the walk. The
    -- ruby door relocks around 3am -- if it has, the walk ends against it and you
    -- want the ruby key in hand.
    --
    -- Poison is handled the same way the outward leg handles it. On the walk an
    -- acolyte cured the whole group with a spell; a verbena does the same job for
    -- one character, and onPoison drinks it only if the game says we're poisoned.
    ["town-2"] = {
        from     = { room = "town square", exits = "e,ne,nw,se,sw" },
        to       = { room = "north plaza" },
        requires = "coil of rope",
        onPoison = "drink verbena",
        steps    = { "e", "e", "e", "e", "e", "e", "e", "n", "n", "e",
                     "n", "n", "n", "w", "w", "w", "w", "w", "w", "n",
                     "n", "e", "n", "n", "e", "e", "e", "e", "n", "n",
                     "n", "e", "e", "n", "n", "n", "n", "w", "w", "w",
                     "n", "w", "w", "w", "w", "w", "w", "u", "s", "s",
                     "se", "se", "sw", "w", "sw", "nw", "sw", "sw", "w", "sw",
                     "sw", "u", "n", "nw", "nw", "n", "e", "ne", "ne", "ne",
                     "nw", "nw", "n", "nw", "u", "s", "se", "se", "s", "e",
                     "se", "ne", "e", "n", "ne", "e", "u", "s", "s", "sw",
                     "w", "sw", "sw", "se", "s", "se", "e", "ne", "e", "u",
                     "w", "w", "w",
                     { cmd = "push stone" },
                     "sw", "w", "sw", "s", "w", "w", "w", "w", "n", "ne",
                     "ne", "n", "nw", "w", "nw", "w", "w", "n", "ne", "nw",
                     "n", "n", "n", "nw", "ne", "nw", "nw", "nw", "n", "n",
                     "nw", "ne", "e", "ne", "nw", "n", "ne", "nw", "nw", "nw",
                     "ne", "ne", "n", "e", "e", "e", "n", "n", "n", "w",
                     -- Down the three levels into the sewers, and from here on
                     -- the outward chain's ground, walked backwards.
                     "w", "d", "d", "d", "e", "e", "s", "se", "se", "se",
                     "sw", "s", "e", "se", "s", "sw", "sw", "se", "s", "sw",
                     -- The `w` two along is the trap door; the `u` after the two
                     -- `sw` is the climb out of the pit.
                     "w", "nw", "nw", "w", "u", "sw", "sw", "u", "n", "u",
                     "n", "w", "nw", "nw", "nw", "sw", "sw", "nw", "nw", "ne",
                     "nw", "nw", "n", "ne", "nw", "u", "ne" },
    },
    -- Out of the first town and south-west across the wilderness to the ruined
    -- town in the swamp. Nothing to do with the town-3 chain above: this one
    -- starts from the FIRST town's north plaza, which the map can tell apart
    -- from second-town's by exit-set (six exits against five).
    --
    -- Rather more of this is checkable than it first looks, because the whole
    -- wilderness was mapped in one walk -- tojolias, 2026-07-13 -- and these
    -- directions run back over it. Steps 1-24 walk through the mapped graph and
    -- steps 55-61 do too, coming backwards from the plaza; only the
    -- twenty-nine in between are unverifiable, and those leave the map at
    -- step 25, an unwalked `ne` stub out of the clearing at id 915.
    --
    -- Two things that reading fell out of, both worth knowing about:
    --
    -- The map is missing a room at step 3. Between south-plaza and the mountains
    -- stands "outside the town gates" (exits ne, se, sw, nw), which the mapper
    -- failed to name on the way past -- "[map] couldn't read the room name" --
    -- and then anchored past. So the graph carries a south-plaza --sw--> mountains
    -- edge that skips a room, and a forward trace of this route "fails" at step 3
    -- for that reason. The route is right and the map is wrong; don't correct the
    -- route to match it.
    --
    -- Step 11 is the second `w`, and it was missing from the walk as first
    -- written down. Without it step 12's `sw` is being asked of cave-161, whose
    -- exits are e and w and are known from an actual `ex` -- and with it the next
    -- thirteen steps walk cleanly through the forest to the clearing. Which is
    -- the usual failure exactly once inverted: a repeated direction counted one
    -- time too FEW. Nine other runs of a doubled direction to mistrust if a step
    -- is refused, the longest being se se se se (19-22), ne ne ne ne (42-45) and
    -- the n n n n that ends it.
    --
    -- Both ends are stated literally rather than as map references, so this leg
    -- runs on a machine that has no map: the script opens `tele-arena.db`
    -- relative to the working directory, and on a host that has never mapped
    -- anything that call quietly makes an EMPTY database rather than failing --
    -- whereupon every route naming an <area>/<room> reports "there's no area
    -- called 'first-town' (known areas: )" and refuses to move. The two towns'
    -- north plazas are still told apart exactly, by the six exits against five
    -- that the paragraph above turns on. What is given up is only the map's
    -- corroboration of the two ends, and both were checked when this was
    -- recorded -- the plaza is id 966 and its `ex` reads n,ne,e,s,w,nw.
    ["ruined-town"] = {
        from  = { room = "north plaza",  exits = "e,n,ne,nw,s,w" },
        to    = { room = "ruined plaza" },
        steps = { "s", "sw", "sw", "s", "sw", "se", "sw", "sw", "nw", "w",
                  "w", "sw", "s", "s", "sw", "sw", "se", "sw", "se", "se",
                  "se", "se", "sw", "se", "ne", "e", "e", "e", "ne", "n",
                  "ne", "e", "e", "se", "s", "sw", "se", "se", "ne", "ne",
                  "n", "ne", "ne", "ne", "ne", "se", "se", "e", "ne", "ne",
                  "e", "se", "se", "e", "ne", "ne", "ne", "n", "n", "n", "n" },
    },
    -- The way home: ruined-town reversed, direction by direction. Sixty-one
    -- steps back to where the other one starts.
    --
    -- Derived rather than walked, which is a weaker thing than the leg it
    -- mirrors and should be read that way -- it assumes every exit out there has
    -- a reverse, and one that doesn't is a step this list cannot know about.
    -- What can be checked has been. The map confirms both ends of the mirror:
    -- steps 1-7 down the path and the swamp to id 959, and steps 38-59 from the
    -- clearing at 915 back through the forest and the caves to the mountains --
    -- twenty-nine of the sixty-one, each one a real reverse edge in the graph
    -- rather than an assumed one. Steps 8-37 are the stretch the map has never
    -- seen; the walk of 2026-08-05 crossed it forwards, so the rooms are there,
    -- but nothing has been through them the other way.
    --
    -- Step 60 is the one the map actively disagrees with, and the map is wrong.
    -- Tracing back from the north plaza dies at step 60 because the graph is
    -- missing "outside the town gates" and carries a south-plaza --sw-->
    -- mountains edge straight through where it stands. The session log of
    -- 2026-08-05 walked the pair in both directions and settles it: `sw` from
    -- the south plaza reaches the gates (exits ne, se, sw, nw) and `ne` returns.
    -- Two `ne` here, not one.
    ["town-1/north-plaza"] = {
        from  = { room = "ruined plaza", exits = "e,n,ne,nw,s,w" },
        to    = { room = "north plaza" },
        steps = { "s", "s", "s", "s", "sw", "sw", "sw", "w", "nw", "nw",
                  "w", "sw", "sw", "w", "nw", "nw", "sw", "sw", "sw", "sw",
                  "s", "sw", "sw", "nw", "nw", "ne", "n", "nw", "w", "w",
                  "sw", "s", "sw", "w", "w", "w", "sw", "nw", "ne", "nw",
                  "nw", "nw", "nw", "ne", "nw", "ne", "ne", "n", "n", "ne",
                  "e", "e", "se", "ne", "ne", "nw", "ne", "n", "ne", "ne", "n" },
    },
}
-- Second names for the two halves of the third-town journey. `after-doors` and
-- `after-doors-to-town-3` say what each one is, which is what you want when
-- you're editing them; `part-1` and `part-2` say what order to run them in,
-- which is what you want at 2am with the rope in your pack. Both names reach
-- the same table rather than a copy, so a correction to either route is a
-- correction to both names by construction.
NAV_ROUTES["town-3/part-1"] = NAV_ROUTES["town-3/after-doors"]
NAV_ROUTES["town-3/part-2"] = NAV_ROUTES["town-3/after-doors-to-town-3"]
-- part-1 needs neither the rope nor the potion -- twenty-two steps of sewer and
-- three doors -- but it is nearly always the first half of the journey, and it
-- ends at the junction where part-2 begins. Checked only at part-2 the answer
-- comes too late to be any use: you are already down at town-sewers-63, and
-- fetching what you're missing means walking the sewers back up to the plaza
-- and down again. So part-1 asks for part-2's items before it sets off, when
-- you are still standing where they can be bought.
--
-- Assigned from part-2's own list rather than transcribed, so the two can't
-- drift: change what part-2 needs and part-1 checks for the new thing. The
-- refusal says whose requirement it is (requiresFor) -- "this route needs a
-- coil of rope" of a route that doesn't would send you looking for a pit that
-- isn't on it.
--
-- Overridable as everything here is: `navigate-to town-3/part-1 anyway` walks
-- it regardless, which is what you want when part-1 really is all you're
-- walking today.
NAV_ROUTES["town-3/part-1"].requires = NAV_ROUTES["town-3/part-2"].requires
NAV_ROUTES["town-3/part-1"].requiresFor = "town-3/part-2, which carries on from where this ends,"
-- Exposed so tests can register a route without editing the table above.
taPackage.navRoutes = NAV_ROUTES

-- The steps a route will actually walk, as a fresh array, plus a reason if the
-- route can't be flattened.
--
-- Most routes give their steps directly. One built by joining others gives
-- `legs` instead -- the route names to walk in order -- and this is where that
-- becomes a step list: each leg's steps in turn, with a seam check inserted
-- before every leg but the first (the first leg's start is the joined route's
-- own, already checked before the walk sets off). `drop` takes that many steps
-- off the end of a leg, which is how the third-town chain stops in the town
-- square instead of walking the temple leg's last two steps on past it.
--
-- Naming the legs rather than copying their steps is the point: 359 directions
-- transcribed a second time would be 359 chances for the two copies to disagree,
-- and each leg stays runnable on its own, which is what you want when a walk
-- this long dies on floor four.
--
-- Always a copy, never NAV_ROUTES' own table: a locked gate splices its key
-- errand into the walk's list, and splicing into the route would weld it there
-- for the rest of the session.
--
-- `variant` names one of the route's `variants`: an alternative ENDING, asked
-- for as a trailing word (`navigate-to town-3/part-2 chasm-is-clear`). A
-- variant is not a second copy of the route. It says where to leave the usual
-- one and what to walk instead:
--
--     leg   = "town-3/temple"   -- the leg it diverges inside (omit for a
--                                  route that gives `steps` directly)
--     keep  = 94                -- walk that many of the leg's steps first
--     steps = { "sw", ... }     -- then these, instead of the leg's tail
--
-- Keeping the shared prefix shared is the point, and it's the same reason
-- `legs` names its legs rather than copying their directions: the two endings
-- of the chain agree on everything up to the divergence, and directions
-- transcribed twice are chances for the two copies to disagree.
--
-- A variant's steps are the END of the route. The named leg's tail is dropped
-- and so is every leg after it -- those are how the ORDINARY walk finishes --
-- and the leg entry's own `drop` doesn't apply either, since the variant is
-- already choosing where to stop. `keep = 0` diverges at the leg's first step,
-- which still leaves the leg's seam check in front of it: worth having, since
-- below the riddle door that fingerprint is the only check there is.
--
-- That covers a variant that ends a route. A variant can also be a shorter way
-- through the MIDDLE of one, and then it is not an ending at all: the leg is
-- replaced and the walk carries on through the legs after it.
--
--     fromLegs = true
--
-- says so. It takes no steps of its own; it means "every leg that has a variant
-- of this name uses it, and the rest are walked as usual". The steps then live
-- on the legs, one transcription each, which is the same reason `legs` names
-- its legs rather than copying their directions -- and it is what makes
-- `navigate-to town-3/stone-lvl-2 chasm-is-clear` walk that one segment's short
-- way on its own, which is how you check a new one without the 300 steps in
-- front of it.
--
-- The ending falls out of this rather than being a special case: a per-leg
-- variant on the LAST leg has nothing after it to carry on to.
function taPackage.navRouteSteps(route, variant)
    local steps = {}
    local v
    if variant then
        v = route.variants and route.variants[variant]
        if not v then
            return nil, "there's no '" .. tostring(variant) .. "' variant of it"
        end
        -- A leg named with no steps of its own is a borrowing: the ending is
        -- recorded on the leg it belongs to, and the joined route just says
        -- which leg to take it from. One transcription, reachable both ways --
        -- `navigate-to town-3/temple chasm-is-clear` for the leg alone, and
        -- the whole chain for the journey.
        if v.fromLegs then
            if not route.legs then
                return nil, "its '" .. variant .. "' variant is taken from the legs' own"
                    .. " variants, and this route isn't built from legs"
            end
        elseif v.leg and not v.steps and not v.pending then
            local owner = NAV_ROUTES[v.leg]
            local sub = owner and owner.variants and owner.variants[variant]
            if not sub then
                return nil, "its '" .. variant .. "' variant borrows from leg '"
                    .. v.leg .. "', which has no such variant of its own"
            end
            v = { leg = v.leg, keep = sub.keep, steps = sub.steps, pending = sub.pending }
        end
        if v.pending then
            return nil, "its '" .. variant .. "' variant has no steps recorded yet"
        end
    end
    if not route.legs then
        if v and v.leg then
            return nil, "its '" .. variant .. "' variant diverges inside leg '"
                .. v.leg .. "', and this route isn't built from legs"
        end
        local base = route.steps or {}
        for i = 1, (v and math.min(v.keep or 0, #base) or #base) do steps[i] = base[i] end
        if v then
            for _, step in ipairs(v.steps) do steps[#steps + 1] = step end
        end
        return steps
    end
    local diverged = false
    for n, entry in ipairs(route.legs) do
        local name = (type(entry) == "table") and entry.route or entry
        local drop = ((type(entry) == "table") and entry.drop) or 0
        local leg = NAV_ROUTES[name]
        if not leg then
            return nil, "leg " .. n .. " is '" .. tostring(name) .. "', and there's no such route"
        end
        if not leg.steps then
            return nil, "leg " .. n .. " (" .. name .. ") is itself built from legs,"
                .. " and I don't join those"
        end
        if n > 1 then steps[#steps + 1] = { seam = name } end
        local last = #leg.steps - drop
        -- The leg's own variant of this name, where the joined route asked for
        -- the legs' variants rather than an ending of its own. It replaces the
        -- leg's tail exactly as an ending does -- and `drop` goes with the tail,
        -- since the variant is already saying where the leg finishes.
        local legTail
        if v and v.fromLegs then
            local lv = leg.variants and leg.variants[variant]
            if lv then
                if not lv.steps then
                    return nil, "its '" .. variant .. "' variant takes leg " .. n .. " ("
                        .. name .. ") from that leg's own variant, which has no steps recorded yet"
                end
                last, legTail, diverged = math.min(lv.keep or 0, #leg.steps), lv.steps, true
            end
        end
        if v and v.leg == name then last, diverged = math.min(v.keep or 0, #leg.steps), true end
        for i = 1, last do steps[#steps + 1] = leg.steps[i] end
        if legTail then
            for _, step in ipairs(legTail) do steps[#steps + 1] = step end
        end
        -- An ENDING, so it ends the route: the legs after this one are the way
        -- the ordinary walk finishes, and the variant is the other way. Walking
        -- the variant's steps and then carrying on through the rest of the legs
        -- would be neither.
        if v and v.leg == name then
            for _, step in ipairs(v.steps) do steps[#steps + 1] = step end
            break
        end
    end
    -- A variant naming a leg this route doesn't walk would otherwise flatten to
    -- the ordinary route and walk it in silence, which is the one outcome worse
    -- than refusing: you asked for the other ending and got this one anyway.
    if v and v.leg and not diverged then
        return nil, "its '" .. variant .. "' variant diverges inside leg '"
            .. v.leg .. "', and no leg of this route is called that"
    end
    -- The same trap one level up: a variant taken from the legs, where no leg
    -- has one. Silence there would walk the ordinary 364 steps having been asked
    -- for the short way.
    if v and v.fromLegs and not diverged then
        return nil, "its '" .. variant .. "' variant is taken from the legs' own variants,"
            .. " and no leg of this route has one called '" .. variant .. "'"
    end
    return steps
end

-- Pace between steps or the character trips and falls (see the trip trigger
-- below). Measured across four walks at 1000ms: 4 trips in 60 moves, 6.7%,
-- against a 1.13% baseline over the 72,354 hand-typed moves in the archived
-- logs -- so a 1s cadence really does provoke them (p ~ 0.005). Neither 1200ms
-- nor 1300ms was enough: 1200 tripped on one of two traced walks, and 1300 kept
-- tripping on the longer sewers errands. 1500ms then carried the hydra errand
-- -- 23 moves and a sweep, the longest route here -- without a single trip.
-- Don't shave it back without a reason: the trips so far have
-- landed on steps 8, 8, 10, 11 and 14, which looks like a flat per-move risk
-- rather than fatigue setting in after some number of steps -- meaning a longer
-- route is likelier to trip somewhere simply because it takes more moves, and
-- the pace has to be low enough per move to make that rare. navDebug below is
-- there to replace the guessing with measurements.
local NAV_STEP_DELAY_MS = 1500
local NAV_TRIP_RETRY_MS = 2000
-- How long to leave a monster alone before trying the blocked move again. A
-- combat round lasts seconds, so hammering it only fills the screen.
local NAV_COMBAT_RETRY_MS = 2000
-- And how long to wait out being winded after a fight. Shorter, because
-- nothing is happening to us while we get our breath back -- the sooner we
-- find out we can move, the sooner the walk goes on.
local NAV_REST_RETRY_MS = 1500
-- Exposed so tests fire the walk's timers by name rather than by a literal
-- interval, which silently stops matching the moment the pacing is retuned.
taPackage.navStepDelayMs = NAV_STEP_DELAY_MS
taPackage.navTripRetryMs = NAV_TRIP_RETRY_MS
taPackage.navCombatRetryMs = NAV_COMBAT_RETRY_MS
taPackage.navRestRetryMs = NAV_REST_RETRY_MS
-- How long to wait for the room probe (bare return + `ex`) before giving up.
-- Without this a swallowed reply leaves navigate-to armed and silent, with
-- nothing on screen to explain why nothing happened.
local NAV_PROBE_TIMEOUT_MS = 5000

local function navEcho(msg) echo("[nav] " .. msg) end

local navNowMs = taPackage.nowMillis

-- Timing trace for the paced walk, off unless `navigate-to <dest> debug` was
-- used. Every line carries the wall clock and, more usefully, the gap since
-- the previous traced event -- the question being asked here is what interval
-- the game will accept without tripping us, and that is a question about gaps.
local function navDebug(label)
    local j = taPackage.navigate
    if not (j and j.debug) then return end
    local now = navNowMs()
    local since = j.debugLast and (now - j.debugLast) or 0
    j.debugLast = now
    echo(string.format("[nav|t] %s +%dms  %s", os.date("%H:%M:%S"), since, label))
end

-- End a walk, however it ended -- arrival, locked door, error, or a manual
-- stop. Every exit path funnels through here so the mapping notice below can't
-- be forgotten on one of them. Bumping the generation invalidates any step or
-- retry timer still in flight so a stale one can't resume a walk we've
-- abandoned. Returns whether anything was actually running. Shared by
-- stop-navigating and stop-all-scripts.
local function stopNavigate()
    local j = taPackage.navigate
    local running = j ~= nil
    -- Only drop the probe if it's ours: map-print-room-slug may have one armed.
    if taPackage.slugProbe and taPackage.slugProbe.nav then
        taPackage.slugProbe = nil
        running = true
    end
    -- Headline numbers for a traced walk, so the pacing question can be
    -- answered without reading back through every step.
    if j and j.debug then
        local seconds = (navNowMs() - (j.startedAt or navNowMs())) / 1000
        -- Trips, being winded and being held in combat are three different
        -- things with three different causes, and lumping them together is how
        -- the pace got blamed for a dozen stalls it had nothing to do with.
        local extra = ""
        if (j.rests or 0) > 0 then extra = extra .. ", winded " .. j.rests .. "x" end
        if (j.combatBlocks or 0) > 0 then extra = extra .. ", held in combat " .. j.combatBlocks .. "x" end
        if (j.cures or 0) > 0 then extra = extra .. ", poisoned " .. j.cures .. "x" end
        echo(string.format("[nav|t] walk ended: %d/%d steps, %d trip(s), %.1fs total, pace %dms%s",
            j.index or 0, #(j.steps or {}), j.trips or 0, seconds, NAV_STEP_DELAY_MS, extra))
    end
    taPackage.navigate = nil
    taPackage.navPickup = nil
    taPackage.navGen = (taPackage.navGen or 0) + 1
    -- A sweep is part of the walk now, so stopping the walk stops the fighting
    -- too -- otherwise "stopped" would leave the character still swinging.
    if taPackage.navSweep then
        taPackage.navSweep = nil
        if taPackage.killAllActive then taPackage.stopKill() end
        running = true
    end
    -- Mapping was on when we set off and we turned it off. Leave it off: we may
    -- be many rooms from where the mapper last knew we were (and, if the walk
    -- was cut short, somewhere neither of us can name), so resuming would link
    -- the next manual move from the wrong room and mint duplicates.
    if j and j.mappingWasOn then
        navEcho("Mapping is still off — the walk moved us well past the mapper's"
            .. " anchor. Re-anchor with map-here <slug> before mapping again.")
    end
    return running
end
taPackage.stopNavigate = stopNavigate

-- A set of exits reduced to one comparable string, from either a list (as the
-- `ex` reply gives us) or a comma-separated spec (as a route writes one).
-- Sorted, so "n,e,s" and the game's "e,n,s" are the same fingerprint.
local function navExitKey(exits)
    local out = {}
    if type(exits) == "table" then
        for _, d in ipairs(exits) do out[#out + 1] = d end
    else
        for d in tostring(exits):gmatch("[^,%s]+") do out[#out + 1] = d end
    end
    table.sort(out)
    return table.concat(out, ",")
end

-- Split "<area>/<room>" and resolve it to exactly one room. Returns the room
-- row, or nil plus a reason -- a malformed reference, an unknown area, an
-- unknown room, or an ambiguous one. Every failure is reported rather than
-- guessed past: picking one of three rooms named "underground plaza" and
-- walking off would be worse than refusing.
--
-- A third return says the failure was "there is no map here" rather than "this
-- reference is wrong", and the difference decides what the caller does. The
-- user also plays from a VPS with no tele-arena.db, and dbOpen makes an empty
-- one silently rather than failing -- so on that machine EVERY reference fails,
-- and refusing to walk is refusing over a check we were never going to be able
-- to make. A reference that fails against a map that DOES exist is a broken
-- route table and still gets refused.
--
-- Told apart by the areas table: no areas at all is an empty database, and one
-- unknown area among others is a typo. Nothing else can be both.
local function navResolveRef(ref)
    local areaSlug, roomRef = ref:match("^([^/]+)/(.+)$")
    if not areaSlug then
        return nil, "'" .. ref .. "' isn't an <area>/<room> reference (try e.g. third-town/arena)"
    end
    local matches = taPackage.db.roomsInAreaMatching(areaSlug, roomRef)
    if matches == nil then
        local names = {}
        for _, a in ipairs(taPackage.db.listAreas()) do names[#names + 1] = a.slug end
        if #names == 0 then
            return nil, "there's no map on this machine — tele-arena.db has no areas in it", true
        end
        return nil, "there's no area called '" .. areaSlug .. "' (known areas: "
            .. table.concat(names, ", ") .. ")"
    end
    if #matches == 0 then
        return nil, "there's no room '" .. roomRef .. "' in " .. areaSlug
    end
    if #matches > 1 then
        local slugs = {}
        for _, m in ipairs(matches) do slugs[#slugs + 1] = areaSlug .. "/" .. m.slug end
        return nil, "'" .. ref .. "' is ambiguous — did you mean " .. table.concat(slugs, ", ") .. "?"
    end
    return matches[1]
end

-- Does the room we're standing in match a route's `from`? Asked in two places
-- now -- before a walk sets off, and at each seam of a route built from other
-- routes -- and they are the same question about the same field, so they share
-- an answer rather than drifting apart.
--
-- Returns ok, here, expect, weak, err, unmapped:
--   here      how to name where we are, exits and all
--   expect    how to name what the route wanted
--   weak      matched on the room name alone, the `from` having named no exits
--   err       the `from` is a map reference that doesn't resolve
--   unmapped  ...and it doesn't resolve because there is no map here at all,
--             which is a check we can't make rather than one we've failed
--
-- The two branches word themselves differently on purpose. A fingerprint knows
-- nothing but the room in front of it; a map reference can say which room the
-- map thinks this is, which is the more useful sentence when it's the wrong one.
function taPackage.navFromMatches(from, name, dirs)
    local sorted = navExitKey(dirs)
    if type(from) == "table" then
        local want = from.exits and navExitKey(from.exits) or nil
        local expect = "a room called '" .. from.room .. "'"
            .. (want and (" with exits " .. want) or "")
        local ok = (name == from.room) and (not want or sorted == want)
        return ok, "'" .. name .. "' with exits " .. sorted, expect, ok and not want
    end
    local room, err, unmapped = navResolveRef(from)
    if not room then
        -- With no map there is still something worth saying: where we are. It
        -- is all the caller has to go on once it decides to walk anyway.
        return false, "'" .. name .. "' with exits " .. navExitKey(dirs), from, false,
            err, unmapped
    end
    local here = "'" .. name .. "' with exits " .. table.concat(dirs, ",")
    local candidates = taPackage.db.roomsMatchingFingerprint(name, dirs)
    if #candidates == 1 and candidates[1].id == room.id then
        return true, here, from, false
    end
    local which
    if #candidates == 1 then
        which = taPackage.db.roomRef(candidates[1].id) or candidates[1].slug
    elseif #candidates == 0 then
        which = "no room I have mapped"
    else
        local refs = {}
        for _, c in ipairs(candidates) do
            refs[#refs + 1] = taPackage.db.roomRef(c.id) or c.slug
        end
        which = "one of " .. table.concat(refs, ", ") .. " — too ambiguous to act on"
    end
    return false, here .. ", which is " .. which, from, false
end

-- Walk one step. Unlike the manual n/s/e/w aliases this deliberately leaves no
-- trail for the mapper: `pendingDirection` is CLEARED, not set. Setting it would
-- be an instruction to record an edge, and a stale one left behind at the end of
-- a walk would dead-reckon the user's next manual move from a room sixteen steps
-- away. Clearing `suppressRoomEntry` is unrelated bookkeeping -- it stops a
-- leftover `look <dir>` flag from swallowing our first arrival brief.
local function navSend(dir)
    taPackage.suppressRoomEntry = nil
    taPackage.pendingDirection = nil
    send(dir)
end

-- What kind of thing a step is, or nil if the route table is malformed. What
-- makes the distinction matter is how each one finishes: a move is answered by
-- an arrival brief, a command by nothing in particular, and a sweep by the room
-- falling quiet -- so each advances the walk from somewhere different.
-- A `gate` is a move through a door that may or may not be shut, naming the key
-- that opens it and the errand that fetches that key. Its point is that the move
-- IS the question: the game answers a door direction with an arrival brief if it
-- is open, "your <key> key unlocks..." if we already hold the key, or the locked
-- refusal if we don't -- and the first two both mean the errand can be skipped.
-- A `seam` moves nowhere at all. It is the join between two legs of a route
-- built from other routes, and it asks the room we have arrived in whether it is
-- where the next leg begins -- the check that leg would have made for itself had
-- it been run by hand.
local function navStepKind(step)
    if type(step) == "string" then return "move" end
    if type(step) ~= "table" then return nil end
    if step.killAll then return "killAll" end
    if type(step.cmd) == "string" then return "cmd" end
    if type(step.door) == "string" then return "gate" end
    if type(step.seam) == "string" then return "seam" end
    return nil
end

-- Reject a malformed route standing still rather than halfway along it. A gate's
-- detour is another route named by string, so it is checked too: a typo there
-- would otherwise lie undisturbed until the day a door happened to be locked.
-- `seen` stops a detour that leads back to its own route from recursing forever.
local function navBadStep(steps, seen)
    seen = seen or {}
    for i, step in ipairs(steps or {}) do
        local kind = navStepKind(step)
        if not kind then
            return i, "isn't a direction, a { cmd = ... }, a { killAll = true },"
                .. " a { door = ... } or a { seam = ... }"
        end
        if kind == "seam" and not NAV_ROUTES[step.seam] then
            return i, "checks we've reached '" .. step.seam .. "', and there's no such route"
        end
        if kind == "gate" and step.detour then
            local sub = NAV_ROUTES[step.detour]
            if not sub then
                return i, "sends us to '" .. step.detour .. "' for the key, and there's no such route"
            end
            if not seen[step.detour] then
                seen[step.detour] = true
                local badSub, why = navBadStep(sub.steps, seen)
                if badSub then
                    return i, "sends us to " .. step.detour .. ", whose step " .. badSub .. " " .. why
                end
            end
        end
    end
    return nil
end

local function navStepLabel(step)
    local kind = navStepKind(step)
    if kind == "move" then return step end
    if kind == "cmd" then return "'" .. step.cmd .. "'" end
    if kind == "gate" then return step.door .. " (" .. (step.key or "locked") .. " door)" end
    if kind == "seam" then return "seam check (" .. step.seam .. ")" end
    return "kill-all"
end

-- All three are defined below: they need navStep, which needs them.
local navAdvance, navStartSweep, navStartSeam

-- Send the next queued step. index counts steps already started, so bumping it
-- first and indexing gives the one we haven't done yet.
local function navStep()
    local j = taPackage.navigate
    if not j then return end
    j.index = j.index + 1
    local step = j.steps[j.index]
    if step == nil then return end
    local kind = navStepKind(step)
    -- Remembered because the room-brief handler has to know whether a brief is
    -- this step's answer or just noise from a command or a sweep.
    j.stepKind = kind
    navDebug("send step " .. j.index .. "/" .. #j.steps .. " " .. navStepLabel(step))
    if kind == "move" then
        navSend(step)
    elseif kind == "gate" then
        -- Cleared so the key that opened the LAST door can't be reported for
        -- this one: the line only arrives when a key is actually used.
        j.doorOpenedByKey = nil
        navSend(step.door)
    elseif kind == "cmd" then
        navSend(step.cmd)
        -- Nothing reliably answers an arbitrary command, so the pause is the
        -- only signal we have that it has had its chance.
        navAdvance()
    elseif kind == "seam" then
        navStartSeam(step.seam)
    else
        navStartSweep()
    end
end

-- Re-send the current step without advancing, to recover from a move the game
-- refused (a trip, or "rest a while first"): the step at j.index went out but
-- never landed us anywhere new.
local function navResendStep()
    local j = taPackage.navigate
    if not j then return end
    j.blocked = nil
    -- Only a move can be refused this way, and only a move is safe to repeat:
    -- re-sending a lever pull would work it twice. A gate is a move -- walking
    -- at a door twice costs nothing -- and has to be named explicitly here or a
    -- trip on one would leave the walk waiting for a step it never re-sent.
    local step = j.steps[j.index]
    local dir = (type(step) == "string" and step)
        or (navStepKind(step) == "gate" and step.door)
        or nil
    if dir then
        navDebug("re-send step " .. j.index .. " " .. dir)
        navSend(dir)
    end
end

local function navScheduleStep()
    local gen = taPackage.navGen or 0
    createTimer(NAV_STEP_DELAY_MS, function()
        if taPackage.navigate and (taPackage.navGen or 0) == gen then navStep() end
    end, { repeating = false })
end

-- Try the route's final locked-door direction. Whether we get through is
-- decided by the game's reply: the "locked ... prevents your exit" refusal, the
-- "your <key> key unlocks" success, or -- if the door is simply open -- an
-- ordinary arrival brief. All three are handled below.
local function navScheduleDoor()
    local gen = taPackage.navGen or 0
    createTimer(NAV_STEP_DELAY_MS, function()
        local j = taPackage.navigate
        if not j or (taPackage.navGen or 0) ~= gen then return end
        j.phase = "door"
        navEcho("Trying the " .. j.door.dir .. " door out of " .. j.destination .. ".")
        navSend(j.door.dir)
    end, { repeating = false })
end

-- =========================================================================
-- What's on the floor, and what a fall shook loose
-- =========================================================================
--
-- Tripping sometimes knocks an item out of the pack onto the floor. The game
-- says nothing when it happens -- the line after "you trip and fall!" is just
-- our next command -- so the only way to notice is to look at the floor and
-- compare it with what was there before. Walking on without looking loses the
-- item for good.
--
-- Hence: remember every room's floor as we enter it, and after a trip take a
-- fresh reading. Anything that appeared is ours. Comparing against the room's
-- own floor (rather than against our inventory) is what stops us pocketing
-- somebody else's litter -- the sewers genuinely have a rue potion lying in
-- one room, and it is not ours to take.
--
-- The wording, from the logs:
--     There is nothing on the floor.
--     There is a waterskin lying on the floor.
--     There is a bronze key, and an electrum key lying on the floor.
--     There is a bronze key, a waterskin, and a bronze key lying on the floor.
-- Always "There is", even for a list; an Oxford comma before "and"; and the
-- same item can appear twice. That last point makes this a MULTISET compare --
-- with a set, dropping a second bronze key next to one already lying there
-- would look like nothing had changed.

-- "a bronze key" / "and an electrum key" -> "bronze key" / "electrum key".
-- The article test requires trailing whitespace so "anemone potion" survives.
local function navStripArticle(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^and%s+", ""):gsub("^an?%s+", ""))
end

local function navParseFloorItems(phrase)
    local items = {}
    for part in (phrase .. ","):gmatch("([^,]+),") do
        local item = navStripArticle(part)
        if item ~= "" then items[#items + 1] = item end
    end
    return items
end

local function navFloorCounts(items)
    local counts = {}
    for _, item in ipairs(items or {}) do counts[item] = (counts[item] or 0) + 1 end
    return counts
end

-- Items present in `after` beyond what `before` held, repeated by how many
-- extra copies appeared. This is the list of things the fall shook loose.
local function navNewFloorItems(before, after)
    local had, now = navFloorCounts(before), navFloorCounts(after)
    local out = {}
    for item, n in pairs(now) do
        for _ = 1, n - (had[item] or 0) do out[#out + 1] = item end
    end
    table.sort(out)
    return out
end

-- =========================================================================
-- Picking a dropped item back up
-- =========================================================================
--
-- `get` matches a SINGLE word and ignores the rest of the argument, and which
-- word answers is not predictable from the display name. From the logs:
--
--     a coil of rope      `get rope` works (9x); `get coil` does not (3x)
--     a ration of food    `get ration` works, and so does `get rat`
--     a wand of lightning `get wand` works
--     a yarrow potion     `get yarrow` works, and so does `get potion`
--
-- So "coil of rope" answers to its LAST word while "ration of food" answers to
-- its FIRST -- and passing the whole name is no help, because `get coil of
-- rope` is read as `get coil` and fails just the same. That is exactly what
-- went wrong on the 2026-08-01 walk: a rope shaken loose in the sewers was
-- correctly spotted and then not recovered.
--
-- Rather than guess, try the words in turn -- first, then last, then any in
-- between -- and let the game's refusal drive the next attempt. Refusals come
-- back at once, so the ladder resolves well inside the pacing pause before the
-- walk resumes.
local function navPickupHandles(item)
    local words = {}
    for word in item:gmatch("%S+") do
        -- "of" is never the handle; it only ever joins the two halves.
        if word ~= "of" then words[#words + 1] = word end
    end
    if #words <= 1 then return { item } end
    local handles = { words[1], words[#words] }
    for i = 2, #words - 1 do handles[#handles + 1] = words[i] end
    return handles
end

local navPickupSendCurrent

-- Move to the next item we owe a pick-up for, or finish.
local function navPickupNextItem()
    local p = taPackage.navPickup
    if not p then return end
    p.queueIndex = p.queueIndex + 1
    local item = p.queue[p.queueIndex]
    if not item then
        taPackage.navPickup = nil
        return
    end
    p.item, p.handles, p.index = item, navPickupHandles(item), 1
    navPickupSendCurrent()
end

navPickupSendCurrent = function()
    local p = taPackage.navPickup
    if p then send("get " .. p.handles[p.index]) end
end

local function navPickupStart(items)
    taPackage.navPickup = { queue = items, queueIndex = 0 }
    navPickupNextItem()
end

-- The game did not recognise the word we tried. Step down the ladder; when it
-- runs out, say the item is being left behind rather than failing silently.
createTrigger("^Sorry, but no such item is here\\.$", function()
    local p = taPackage.navPickup
    if not p then return end
    p.index = p.index + 1
    if p.handles[p.index] then
        navPickupSendCurrent()
        return
    end
    navEcho("Couldn't work out how to pick the " .. p.item .. " back up — it's on the floor here.")
    navPickupNextItem()
end, { type = "regex" })

createTrigger("^Ok, you got (.+)\\.$", function(matches)
    local p = taPackage.navPickup
    if not p then return end
    navEcho("Picked the " .. navStripArticle(matches[2]) .. " back up.")
    navPickupNextItem()
end, { type = "regex" })

-- Re-send the step we tripped on, after the usual pacing pause.
local function navScheduleResend(delayMs)
    local gen = taPackage.navGen or 0
    createTimer(delayMs or NAV_STEP_DELAY_MS, function()
        if taPackage.navigate and (taPackage.navGen or 0) == gen then navResendStep() end
    end, { repeating = false })
end

-- Handle a floor line. Which reading it is depends on why we asked:
--   * during the opening room probe -- stash it, so the very first step is
--     already covered if it trips (without this the starting room's floor is
--     unknown and anything lying there would look like ours);
--   * on arrival     -- record it as this room's "before";
--   * after a trip   -- diff it and pick up whatever we shook loose.
local function navOnFloorLine(items)
    local probe = taPackage.slugProbe
    if probe and probe.nav then
        probe.floor = items
        return
    end
    local j = taPackage.navigate
    if not j then return end

    if j.floorPhase ~= "tripcheck" then
        j.floor = items
        j.floorPhase = nil
        return
    end
    j.floorPhase = nil

    local dropped = navNewFloorItems(j.floor, items)
    if #dropped == 0 then
        -- Nothing of ours. Adopt the reading anyway: someone else may have
        -- dropped or taken something while we stood here, and that is the
        -- baseline a second trip in this room must compare against.
        j.floor = items
        navEcho("Nothing dropped in the fall.")
    else
        navEcho("The fall shook loose the " .. table.concat(dropped, ", the ")
            .. " — picking it back up.")
        navPickupStart(dropped)
        -- Picking them up puts the floor back as it was, so j.floor stands.
    end

    j.phase = "walking"
    navScheduleResend()
end

createTrigger("^There is nothing on the floor\\.$", function()
    navOnFloorLine({})
end, { type = "regex" })

createTrigger("^There is (.+) lying on the floor\\.$", function(matches)
    navOnFloorLine(navParseFloorItems(matches[2]))
end, { type = "regex" })

-- Picking a dropped item back up can fail, and encumbrance is the likely
-- reason. Say so plainly: the walk goes on, but something of ours is now lying
-- in a sewer and only this line will tell you.
createTrigger("^You can't carry anything else\\.$", function()
    if not taPackage.navigate then return end
    navEcho("Couldn't pick it up — pack is full. Item left on the floor here.")
end, { type = "regex" })

createTrigger("^Sorry, you can't carry that much more weight!$", function()
    if not taPackage.navigate then return end
    navEcho("Couldn't pick it up — too heavy. Item left on the floor here.")
end, { type = "regex" })

-- A move the game refused outright. No room change happens and, as the live
-- walk on 2026-08-01 showed, no room line follows either -- so nothing would
-- prompt us to look around. Wait out the stumble, then take a fresh reading of
-- the floor (the bare return below) before walking on, because the fall may
-- have cost us an item. `blocked` guards the case where the game DOES reprint
-- the room, so that reprint isn't miscounted as an arrival.
local function navRecoverAfterRefusedMove()
    local j = taPackage.navigate
    if not j then return end
    -- The measurement that matters: how long after the previous move the game
    -- refused this one, and how far into the walk we were.
    j.trips = (j.trips or 0) + 1
    navDebug("TRIPPED on step " .. j.index .. "/" .. #j.steps
        .. " (trip " .. j.trips .. " this walk, pace " .. NAV_STEP_DELAY_MS .. "ms)")
    j.blocked = true
    local gen = taPackage.navGen or 0
    createTimer(NAV_TRIP_RETRY_MS, function()
        local walk = taPackage.navigate
        if not walk or (taPackage.navGen or 0) ~= gen then return end
        walk.blocked = nil
        if walk.floor == nil then
            -- We never saw this room's floor, so we can't tell our dropped item
            -- from what was already lying here. Taking a guess risks pocketing
            -- someone else's; walk on and say why.
            navEcho("Tripped, but I never saw this room's floor — not risking a"
                .. " pick-up that might not be mine.")
            navScheduleResend()
            return
        end
        walk.phase = "tripcheck"
        walk.floorPhase = "tripcheck"
        send("")
    end, { repeating = false })
end

-- The end of the route. `room` is the arrival brief's room name when a move
-- finished the walk, and nil when the last step was a command or a sweep --
-- neither of which moves us, so neither has a fresh name to check.
local function navArrive(room)
    local j = taPackage.navigate
    if not j then return end
    -- Confirm we're where the route said we'd be: a name mismatch means a step
    -- went astray, and the door probe below would then be tried from the wrong
    -- room.
    if room and j.arriveName and room ~= j.arriveName then
        local want = j.arriveName
        stopNavigate()
        navEcho("Walked the whole route but ended up in '" .. room .. "', not '"
            .. want .. "' — stopping rather than guessing. The route may be wrong.")
        return
    end
    if j.door then
        navEcho("Arrived at " .. j.destination .. ".")
        navScheduleDoor()
        return
    end
    local dest = j.destination
    stopNavigate()
    navEcho("Arrived at " .. dest .. ".")
end

-- One step done. Either pace the next one or finish.
navAdvance = function()
    local j = taPackage.navigate
    if not j then return end
    if j.index >= #j.steps then navArrive() else navScheduleStep() end
end

-- A `{ seam = "<route>" }` step: the join between two legs of a joined route.
-- Ask the room where we are and check it against the leg about to start.
--
-- Run by hand, each leg checks its own starting room before it moves, and for
-- the six stoneworks legs that check is the ONLY thing standing between a
-- miscounted repeat and a character walking into walls a hundred steps from the
-- cause -- there is no map down there to catch a wrong turn. Joining the legs
-- would have thrown those checks away, so the seams keep them.
--
-- Nothing new is needed to ask: this is the same bare return plus `ex` the start
-- check uses, answered through the same slugProbe (see the Exits trigger, which
-- hands the room name and its exits to onResolve).
navStartSeam = function(legName)
    local j = taPackage.navigate
    if not j then return end
    local leg = NAV_ROUTES[legName]
    -- navBadStep refuses an unknown leg before the walk sets off, so this can
    -- only be a route deleted mid-walk. Say so rather than walking on blind.
    if not leg then
        stopNavigate()
        navEcho("The seam check names " .. legName .. ", which I no longer know — stopping.")
        return
    end
    local gen = taPackage.navGen or 0
    j.phase = "seam"
    taPackage.slugProbe = {
        name = nil,
        nav  = true,
        onResolve = function(name, dirs)
            local walk = taPackage.navigate
            if not walk or (taPackage.navGen or 0) ~= gen then return end
            walk.phase = "walking"
            if not name then
                stopNavigate()
                navEcho("Couldn't read the room I'm in at the " .. legName .. " seam — stopping.")
                return
            end
            local ok, here, expect, weak, err, unmapped =
                taPackage.navFromMatches(leg.from, name, dirs)
            -- No map, so this seam names a room nothing here can identify. The
            -- walk is no worse off than it is between any two steps -- and the
            -- seams that fingerprint their room still check, which on the way to
            -- third town is six of the seven.
            if unmapped then
                navEcho("No map here, so the " .. legName .. " seam can't be checked — I'm in "
                    .. here .. ", carrying on.")
                navAdvance()
                return
            end
            if err then
                stopNavigate()
                navEcho("The " .. legName .. " seam can't be checked: " .. err .. " — stopping.")
                return
            end
            if ok then
                navEcho("At the " .. legName .. " seam: " .. here .. " — as expected"
                    .. (weak and ", though only the name was checked." or ", carrying on."))
                navAdvance()
                return
            end
            stopNavigate()
            navEcho("At the " .. legName .. " seam I expected " .. tostring(expect)
                .. " but I'm in " .. here .. " — stopping.")
            -- The leg is the resume point: it is what you would run by hand from
            -- wherever this actually is, once you have worked out where that is.
            navEcho("  Get to where " .. legName .. " starts and run it on its own"
                .. ", or stop-navigating and walk it by hand.")
        end,
    }
    send("")
    send("ex")
    createTimer(NAV_PROBE_TIMEOUT_MS, function()
        if (taPackage.navGen or 0) ~= gen then return end
        if not (taPackage.slugProbe and taPackage.slugProbe.nav) then return end
        taPackage.slugProbe = nil
        stopNavigate()
        navEcho("The game never told me what room I'm in at the " .. legName
            .. " seam — stopping rather than walking on unsure.")
    end, { repeating = false })
end

-- A `{ killAll = true }` step: clear this room before walking on. Getting a
-- key is the usual reason -- the game auto-searches each corpse and a key turns
-- up in one of them ("While searching the area, you notice a ruby key...").
navStartSweep = function()
    local j = taPackage.navigate
    if not j then return end
    if taPackage.arenaState then
        local dest = j.destination
        stopNavigate()
        navEcho("An arena session is active — stopping " .. dest .. " rather than starting kill-all.")
        return
    end
    -- `untilFound` is what the errand actually came for. With it, the sweep is
    -- over the moment that thing turns up; without it, the room gets cleared.
    local step = j.steps[j.index]
    local want = step.untilFound
    -- Each errand sweep gets its own chase budget. A sweep spliced in BY a
    -- chase carries the budget on instead, which is what caps how far one
    -- runaway can drag us (see navChaseAfterSweep).
    if not step.chase then j.chases = 0 end
    navEcho(want and ("Clearing the room until I get "
                      .. (want:match("^[aeiou]") and "an " or "a ") .. want .. ".")
                  or "Clearing the room with kill-all.")
    -- Marks this sweep as a route's, which is what scopes the full-pack
    -- handling below: a kill-all run by hand is nobody's business but yours.
    taPackage.navSweep = { destination = j.destination, uncarried = {}, untilFound = want }
    taPackage.killAllActive = true
    taPackage.killAllScan()
end

-- We have what the errand came for, so there is no reason to go on killing.
-- Stop swinging and walk on; if something is still on us, the move is refused
-- and retried until it breaks off, which is no worse than fighting it out and
-- usually a great deal quicker.
local function navSweepGotWhatItCameFor(item)
    local sweep = taPackage.navSweep
    taPackage.navSweep = nil
    if taPackage.stopKill then taPackage.stopKill() end
    navEcho("Got the " .. item .. " — that's what this was for, leaving the rest of the room.")
    if sweep and #sweep.uncarried > 0 then
        navEcho("  Note: the " .. table.concat(sweep.uncarried, ", the ")
            .. " is still on the floor here.")
    end
    navAdvance()
end

-- How many rooms a runaway may drag us off the route. A second chase can only
-- ever be a nested one -- the room we started from has finished its sweep by
-- the time the first chase walks back, so nothing there can start another --
-- which is why counting chases per errand is the same thing as capping the
-- depth, and needs no index arithmetic to unwind.
local NAV_CHASE_MAX = 2

-- The room is clear and the errand's item never turned up, but something walked
-- out mid-fight and never came back: it is carrying what we came for. Follow
-- it, clear that room for the same thing, and come home.
--
-- The chase is three ORDINARY steps spliced in after this one, exactly as a
-- locked gate splices its key errand (see the locked-door trigger below):
--
--     "ne", { killAll = true, untilFound = "platinum key", chase = true }, "sw"
--
-- so nothing new has to understand arrival briefs, winded retries, trips,
-- combat blocks or a full pack -- every handler already services these shapes,
-- and they all read #j.steps afresh. Splicing after rather than before is what
-- leaves the errand's own next step to follow once we are back.
--
-- Two things it deliberately does not do. It doesn't second-guess an exit the
-- monster used and we can't: the no-exit handler ends the walk with a clear
-- message, which is the right answer. And a chase that finds nothing just
-- walks home and lets the errand finish, so the door probe reports the locked
-- door as it always did -- no new way for a run to stop.
local function navChaseAfterSweep(sweep)
    local j = taPackage.navigate
    if not j then return false end
    -- The most recent departure nobody has seen come back. In the live log that
    -- is the northeast one, not the south one the mage returned from.
    local hunt = sweep.gone and sweep.gone[#sweep.gone]
    if not hunt then return false end
    local n = (j.chases or 0) + 1
    if n > NAV_CHASE_MAX then
        navEcho("The " .. hunt.monster .. " went " .. hunt.out .. " with the "
            .. sweep.untilFound .. ", but that's " .. NAV_CHASE_MAX
            .. " rooms off the route already — letting it go.")
        return false
    end
    j.chases = n
    local chase = { hunt.out,
                    { killAll = true, untilFound = sweep.untilFound, chase = true },
                    hunt.back }
    for k = #chase, 1, -1 do table.insert(j.steps, j.index + 1, chase[k]) end
    navEcho("Room cleared, but no " .. sweep.untilFound .. " — the " .. hunt.monster
        .. " left " .. hunt.out .. " before it died, so it has what we came for."
        .. " Following it and coming back " .. hunt.back .. ".")
    navAdvance()
    return true
end

-- The room is clear, so the sweep step is done. Report what it yielded and walk
-- on -- unless something had to be left behind, which is the one outcome a run
-- should not carry on from: whatever we came for may be lying on that floor.
local function navOnSweepDone()
    local sweep = taPackage.navSweep
    if not sweep then return end
    taPackage.navSweep = nil
    if #sweep.uncarried > 0 then
        local dest = sweep.destination
        stopNavigate()
        navEcho("Room cleared, but the pack was full: the "
            .. table.concat(sweep.uncarried, ", the ") .. " is still on the floor here.")
        navEcho("  Stopped " .. dest .. ". Drop or stow something, pick it up, then carry on.")
        return
    end
    -- Cleared without what we came for is not the end of the errand if the
    -- thing walked out on legs.
    if sweep.untilFound and navChaseAfterSweep(sweep) then return end
    navEcho("Room cleared.")
    navAdvance()
end
taPackage.navOnSweepDone = navOnSweepDone

-- Advance the walk one room at a time. Called for every arrival brief while a
-- walk is active (hooked into handleRoomEntry, which owns all the phrasings).
local function navOnRoomBrief(room)
    local j = taPackage.navigate
    if not j then return end

    -- The reprint after a refused move is not an arrival; swallow exactly one.
    if j.blocked then
        j.blocked = nil
        return
    end

    -- The brief our own post-trip bare return produced. We never left the room,
    -- so this is not an arrival -- it's here to carry the floor line behind it.
    if j.phase == "tripcheck" then
        navDebug("floor check reply")
        return
    end

    -- Likewise the bare return a seam check sends to identify the room. It is a
    -- question about where we already are, not a move.
    if j.phase == "seam" then
        navDebug("seam check reply")
        return
    end

    if j.phase == "door" then
        navDebug("through the door (" .. room .. ")")
        local key, dir = j.doorOpenedByKey, j.door.dir
        -- We are through the door, which means we are one room PAST the route's
        -- stated destination. Name where that is from the map -- "town sewers"
        -- is shared by 170 rooms and tells the user nothing about where they
        -- have been left standing.
        local beyond = j.destRoomId and taPackage.db.exitDestination(j.destRoomId, dir)
        local where = (type(beyond) == "number" and taPackage.db.roomRef(beyond)) or room
        stopNavigate()
        if key then
            navEcho("My " .. key .. " key opened the door — it's already ours, so this leg"
                .. " needs no detour.")
        else
            navEcho("The " .. dir .. " door was already open — walked through it.")
        end
        navEcho("  Now one room past " .. j.destination .. ", standing in " .. where .. ".")
        return
    end

    -- A gate that produced a brief is a door we got through, and which of the
    -- two ways we got through it is worth saying: "the walk carried on" reads
    -- identically for both, and only one of them means the key is ours to keep.
    if j.stepKind == "gate" then
        local gate = j.steps[j.index]
        if j.doorOpenedByKey then
            navEcho("My " .. j.doorOpenedByKey .. " key opened the " .. gate.door
                .. " door — no errand needed.")
        else
            navEcho("The " .. gate.door .. " door was already open — no errand needed.")
        end
        j.doorOpenedByKey = nil
    -- Only a movement step is answered by an arrival brief. A command's reply
    -- and the briefs a kill-all sweep's own scans print are not arrivals, and
    -- counting them would run the walk ahead of where the character is.
    elseif j.stepKind ~= "move" then
        return
    end

    navDebug("arrived after step " .. j.index .. " (" .. room .. ")")

    if j.index >= #j.steps then
        navArrive(room)
        return
    end

    navScheduleStep()
end
taPackage.navOnRoomBrief = navOnRoomBrief

-- =========================================================================
-- Setting off only if we're carrying what the errand needs
-- =========================================================================
--
-- Some routes can't be walked without a particular item. The hydra route drops
-- through a trap door into a pit whose walls "rise some ten feet above your
-- head... you could [not] climb them unaided" -- so a rope-less character walks
-- in and stays there. Far better to find that out standing in the sewers than
-- at the bottom of the pit.
--
-- `i` answers with one sentence that wraps at the terminal width, so an item
-- can straddle two lines:
--
--     You are carrying 559 gold crowns, a glowstone, a coil of rope, a
--     ration of food, and a waterskin(3).
--
-- Hence: gather lines until one ends the sentence, join them back into a
-- single string, and look for the item in that. Matching a wrapped line on its
-- own would miss a "coil of rope" split across the break.
-- A route may need more than one thing. after-doors-to-town-3 needs the rope for
-- the hydra's pit AND the verbena potion for the poison out in the desert, and
-- setting off with one of the two is how you find out about the other from the
-- bottom of a pit. `requires` therefore takes a string, as it always has, or a
-- list. On taPackage rather than a local: main.lua is two names short of Lua's
-- 200-local ceiling on a chunk.
function taPackage.navWanted(requires)
    if type(requires) == "table" then return requires end
    return { requires }
end

-- "a coil of rope", "a coil of rope and a verbena potion", "a, b and c".
function taPackage.navItemPhrase(items)
    local out = {}
    for _, item in ipairs(items) do out[#out + 1] = "a " .. item end
    if #out < 2 then return out[1] or "" end
    return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
end

local function navInventoryFinish()
    local inv = taPackage.navInventory
    if not inv then return end
    taPackage.navInventory = nil
    if (taPackage.navGen or 0) ~= inv.gen then return end
    -- Which ones are missing, not just that something is: told "this route needs
    -- a verbena potion" while holding one, you go looking for the wrong problem.
    local text, missing = inv.text:lower(), {}
    for _, item in ipairs(inv.wants) do
        if not text:find(item:lower(), 1, true) then missing[#missing + 1] = item end
    end
    if #missing == 0 then
        inv.onOk()
        return
    end
    navEcho((inv.subject or "This route") .. " needs " .. taPackage.navItemPhrase(missing)
        .. " and I'm not carrying " .. (#missing > 1 and "them" or "one") .. " — not setting off.")
    navEcho("  Carrying: " .. inv.text)
end

createTrigger("^(.+)$", function(matches)
    local inv = taPackage.navInventory
    if not inv then return end
    local line = taPackage.trimLine(matches[2])
    if inv.text == nil then
        -- Everything before the listing (our own echoed `i`, a passing shout)
        -- is not ours to read.
        local rest = line:match("^You are carrying (.+)$")
        if not rest then return end
        inv.text = rest
    else
        inv.text = inv.text .. " " .. line
    end
    -- The sentence ends with a full stop; anything else is a wrapped line.
    if inv.text:sub(-1) == "." then navInventoryFinish() end
end, { type = "regex" })

-- `subject` names who wants the items, for a route that checks on another's
-- behalf: part-1 carries part-2's list because the junction it ends at is the
-- wrong side of the sewers to discover the potion is missing from. Defaults to
-- "This route", which is the truth for every route that needs its own.
local function navCheckInventory(requires, gen, onOk, subject)
    local wants = taPackage.navWanted(requires)
    taPackage.navInventory = { wants = wants, gen = gen, onOk = onOk, subject = subject }
    send("i")
    createTimer(NAV_PROBE_TIMEOUT_MS, function()
        local inv = taPackage.navInventory
        if not inv or inv.gen ~= gen then return end
        taPackage.navInventory = nil
        navEcho("The game never listed what I'm carrying, so I can't tell whether I have "
            .. taPackage.navItemPhrase(wants) .. " — nothing sent. Try again.")
    end, { repeating = false })
end

-- `startFloor` is what was lying in the starting room, captured by the opening
-- probe. Without it a trip on the very first step would have nothing to compare
-- against, and anything already on the floor there would look like ours.
--
-- `resumeAt` picks the walk up in the middle: the first step sent is step N of
-- the flattened list rather than step 1. N is read off the trace,
--
--     [nav|t] 18:36:24 +1504ms  send step 56/310 se
--
-- and it means the step that WAS SENT -- the trace line is printed as it goes
-- out, not when the game answers it. So after a hangup: resume at 56 if that
-- `se` never landed (no arrival brief for it in the log, which is the usual
-- case -- the connection is why the walk stopped), and at 57 if it did.
local function navStart(destination, route, arriveName, startFloor, destRoomId, debug, variant,
                        resumeAt)
    taPackage.navGen = (taPackage.navGen or 0) + 1
    -- Suspend mapping so the walk can't write to the map. Our arrival briefs are
    -- ordinary room lines; with mapping on handleRoomEntry would happily record
    -- visits, mint rooms and link edges from them. Remembered so the teardown
    -- can say mapping is still off (see stopNavigate for why we don't restore).
    local mappingWasOn = taPackage.mapping == true
    if mappingWasOn then
        taPackage.mapping = false
        navEcho("Mapping was on — suspended it, the map won't be written to.")
    end
    -- Flattened afresh (see navRouteSteps): a copy the walk owns, because a
    -- locked gate splices its key errand into it.
    local steps, gated = taPackage.navRouteSteps(route, variant), false
    for _, step in ipairs(steps) do
        if navStepKind(step) == "gate" then gated = true end
    end
    taPackage.navigate = {
        destination  = destination,
        steps        = steps,
        -- index counts steps already started, so the step sent next is
        -- index + 1: one less than where we're resuming.
        index        = resumeAt and (resumeAt - 1) or 0,
        door         = route.door,
        onPoison     = route.onPoison,
        arriveName   = arriveName,
        destRoomId   = destRoomId,
        phase        = "walking",
        mappingWasOn = mappingWasOn,
        floor        = startFloor,
        debug        = debug,
        startedAt    = navNowMs(),
    }
    -- With a gate in it the count is a floor, not a total: every door that turns
    -- out to be locked adds its key errand to the walk.
    navEcho((resumeAt
            and ("Walking to " .. destination .. " from step " .. resumeAt .. " — "
                 .. (#steps - resumeAt + 1) .. " of its " .. #steps .. " steps left")
            or ("Walking to " .. destination .. " — " .. #steps .. " steps"))
        .. (gated and ", plus a key errand for any door that's locked." or "."))
    if debug then
        -- Record encumbrance alongside the pace. "In your haste" reads like a
        -- speed check, but a loaded character is the other obvious candidate,
        -- and if trips track the pack rather than the cadence then pacing is a
        -- workaround for the wrong thing. nil until an `st` has been seen.
        local load = getEncumberancePercent()
        echo(string.format("[nav|t] trace on: pace %dms, encumbrance %s",
            NAV_STEP_DELAY_MS, load and (load .. "%") or "unknown (run st)"))
    end
    navStep()
end

createAlias("^navigate-to (.+)$", function(matches)
    local arg = matches[2]:match("^%s*(.-)%s*$")
    -- Trailing words, peeled off in any order and any number. A destination
    -- never contains a space, so anything after one is a flag.
    --
    --   quiet   the timing trace is ON by default while we are still tuning the
    --           pace -- the whole reason it exists is to catch a trip when it
    --           happens, and a trip we have to reproduce deliberately is one we
    --           mostly miss. This turns it off. `debug` is accepted too, so
    --           asking for the trace explicitly still works.
    --   anyway  set off without the pre-flight inventory check.
    --   from-step N   pick a walk up in the middle: don't check the starting
    --           room, and send step N first. This is the BBS hanging up on a
    --           310-step walk, which is otherwise 56 steps to be re-walked by
    --           hand. See navStart for what N means.
    local destination, debug, anyway, resumeAt = arg, true, false, nil
    while true do
        -- Two words where the others are one, so it is peeled first: `56` on
        -- its own is not a flag, and the loop would stop on it and leave
        -- "town-3/part-2 from-step" as the destination.
        local rest, n = destination:match("^(.-)%s+from%-step%s+(%d+)$")
        if rest then
            destination, resumeAt = rest, tonumber(n)
        else
            local head, word = destination:match("^(.-)%s+(%S+)$")
            if word == "quiet" then
                destination, debug = head, false
            elseif word == "debug" then
                destination = head
            elseif word == "anyway" then
                destination, anyway = head, true
            else
                break
            end
        end
    end
    -- A variant: a trailing word naming an alternative ending the route itself
    -- records (`navigate-to town-3/part-2 chasm-is-clear`). Peeled only when
    -- what's left really is a route and that route really has that variant, so
    -- a mistyped destination is still reported whole rather than quietly split
    -- into a route we don't know and a variant we don't know either.
    local variant
    if not NAV_ROUTES[destination] then
        local head, word = destination:match("^(.-)%s+(%S+)$")
        local base = head and NAV_ROUTES[head]
        if base and base.variants then
            if base.variants[word] then
                destination, variant = head, word
            else
                local names = {}
                for name in pairs(base.variants) do names[#names + 1] = name end
                table.sort(names)
                navEcho("I don't know a '" .. word .. "' variant of " .. head
                    .. ". I know: " .. table.concat(names, ", ") .. ".")
                return
            end
        end
    end
    local route = NAV_ROUTES[destination]
    if not route then
        local known = {}
        for name in pairs(NAV_ROUTES) do known[#known + 1] = name end
        table.sort(known)
        navEcho("I don't know a route to '" .. destination .. "'."
            .. (#known > 0 and (" I know: " .. table.concat(known, ", ") .. ".")
                            or " No routes are recorded yet."))
        return
    end
    -- A name we've agreed on but haven't been given the way to yet. Saying so
    -- is the whole reason these are in the table: "I don't know that name" and
    -- "I know that name but not the way" are different problems.
    if route.pending then
        navEcho("I know the name " .. destination .. ", but nobody has told me the way there yet.")
        navEcho("  Walk it by hand, then give me the starting room and the steps"
            .. " (directions, plus any lever pulls or rooms to clear) and I'll record it.")
        return
    end
    -- The same distinction one level down: we've agreed there's another way to
    -- end this walk, and nobody has walked it for us yet.
    if variant and route.variants[variant].pending then
        navEcho("I know the " .. variant .. " variant of " .. destination
            .. ", but nobody has told me how it differs yet.")
        navEcho("  Walk it by hand, then tell me where it leaves the usual route"
            .. " and what to walk instead of the ending, and I'll record it.")
        return
    end
    if taPackage.navigate then
        navEcho("Already walking to " .. taPackage.navigate.destination
            .. " — run stop-navigating first.")
        return
    end
    -- From here on the variant is part of what we're walking to, so it belongs
    -- in everything we say about it -- including "try X again", which has to
    -- stay a command you can retype.
    if variant then destination = destination .. " " .. variant end
    -- Flatten first, so a joined route naming a leg that isn't there is refused
    -- standing still rather than three hundred steps in.
    local flat, flatErr = taPackage.navRouteSteps(route, variant)
    if not flat then
        navEcho("The route to " .. destination .. " is joined from other routes and "
            .. flatErr .. " — fix the route table.")
        return
    end
    local bad, why = navBadStep(flat)
    if bad then
        navEcho("Step " .. bad .. " of the route to " .. destination .. " " .. why
            .. " — fix the route table.")
        return
    end
    if resumeAt then
        if resumeAt < 1 or resumeAt > #flat then
            navEcho("The route to " .. destination .. " is " .. #flat
                .. " steps, so there's no step " .. resumeAt .. " to resume at.")
            return
        end
        -- The numbers in the trace are indices into the list the walk was
        -- holding, and a gate that turned out to be locked splices its key
        -- errand into that list -- so past the first locked door the trace's
        -- numbering and this one no longer agree. The denominator is the tell:
        -- the trace says `step N/T`, and if T isn't this many steps then a key
        -- errand had already gone in and N means nothing here.
        for _, step in ipairs(flat) do
            if navStepKind(step) == "gate" then
                navEcho("Careful: this route has doors that splice a key errand into the walk"
                    .. " when they're locked, and that renumbers every step after them."
                    .. " Step " .. resumeAt .. " means what you think it means only if the"
                    .. " trace said '/" .. #flat .. "'.")
                break
            end
        end
    end

    -- Resolve both ends before sending anything, so a typo in the route table is
    -- reported standing still rather than halfway down a sewer. A route need not
    -- name where it ends -- an errand ends back where it started -- but when it
    -- does, that room is what arrival is checked against.
    --
    -- Either end may be stated literally instead of as a map reference, and both
    -- ends of a route can need it for the same reason the stoneworks legs do:
    -- the map may not be able to answer. `{ room = "ruined plaza" }` asks it
    -- nothing and checks the arrival brief's name directly. All that is lost is
    -- `destRoomId`, which only the door probe wants, so a literal `to` and a
    -- `door` don't go together.
    --
    -- On a machine with no map neither end resolves, and neither refuses: see
    -- navResolveRef. What is lost is named out loud below rather than left for
    -- the user to notice from a walk that checked nothing.
    local arriveName, destRoomId, noMap
    if type(route.to) == "table" then
        arriveName = route.to.room
    elseif route.to then
        local destRoom, destErr, destUnmapped = navResolveRef(route.to)
        if not destRoom and not destUnmapped then
            navEcho("Route destination " .. destErr)
            return
        end
        noMap = noMap or destUnmapped
        if destRoom then arriveName, destRoomId = destRoom.name, destRoom.id end
    end
    -- A route names its start either as a map reference or, where the map can't
    -- tell one room from another, as a literal fingerprint (see navExitKey).
    local fromRoom, fromErr, fromFp
    if type(route.from) == "table" then
        -- Exits are optional. Naming a room we've only ever stood in once, and
        -- never run `ex` in, is worth more than nothing -- but say out loud
        -- that it is a weak check, because "stonework chamber" is twenty-four
        -- rooms and the walk would set off from any of them.
        fromFp = { room = route.from.room,
                   exits = route.from.exits and navExitKey(route.from.exits) or nil }
    else
        local fromUnmapped
        fromRoom, fromErr, fromUnmapped = navResolveRef(route.from)
        if not fromRoom and not fromUnmapped then
            navEcho("Route start " .. fromErr)
            return
        end
        noMap = noMap or fromUnmapped
    end
    -- Say once, before anything is sent, which of this route's checks won't be
    -- made -- and which still will. The fingerprint seams are the point: below
    -- the riddle door nothing is mapped, so those legs already identify their
    -- own starting room without asking the map, and on the way to third town
    -- that is six of the seven seams.
    if noMap then
        local mapped, literal = 0, 0
        for _, step in ipairs(flat) do
            if navStepKind(step) == "seam" then
                local leg = NAV_ROUTES[step.seam]
                if leg and type(leg.from) == "table" then literal = literal + 1
                else mapped = mapped + 1 end
            end
        end
        -- Only what is really unchecked. A route can name one end as a map
        -- reference and the other as a fingerprint, and the fingerprint end is
        -- checked here as well as anywhere.
        local lost = {}
        if not fromFp then lost[#lost + 1] = "where this route starts" end
        if route.to and not arriveName then lost[#lost + 1] = "where it ends" end
        if mapped > 0 then
            lost[#lost + 1] = mapped .. " of its " .. (mapped + literal) .. " seams"
        end
        navEcho("No map on this machine, so I can't check "
            .. (#lost > 1 and (table.concat(lost, ", ", 1, #lost - 1) .. " or " .. lost[#lost])
                           or lost[1])
            .. " — walking on the recorded directions alone.")
        if literal > 0 then
            navEcho("  " .. literal .. " seam" .. (literal > 1 and "s" or "")
                .. " name the room outright rather than by map reference, so"
                .. (literal > 1 and " those are" or " that one is") .. " still checked.")
        end
    end
    local fromLabel = fromFp
        and ("a room called '" .. fromFp.room .. "'"
             .. (fromFp.exits and (" with exits " .. fromFp.exits) or ""))
        or route.from

    -- Identify where we're standing before we move. A route is only valid from
    -- one room; walked from anywhere else it marches the character into walls.
    local gen = (taPackage.navGen or 0) + 1
    taPackage.navGen = gen
    taPackage.suppressRoomEntry = nil
    -- Declared before the table so onResolve can read back what the probe
    -- collected -- notably `floor`, which the bare return's floor line fills in
    -- a moment after this closure is built.
    local probe
    probe = {
        name = nil,
        nav  = true,
        onResolve = function(name, dirs)
            if (taPackage.navGen or 0) ~= gen then return end
            if not name then
                navEcho("Couldn't read the room I'm in — try navigate-to " .. destination .. " again.")
                return
            end
            local function go()
                navStart(destination, route, arriveName, probe.floor, destRoomId, debug,
                    variant, resumeAt)
            end
            -- We're in the right room by the time this is called; the only
            -- remaining question is whether we're equipped for what lies
            -- between here and there. `anyway` skips the asking -- the check is
            -- a courtesy, and there are good reasons to overrule it: the item
            -- is on the floor a room away, or today's hazard is survivable
            -- without it. Say what is being skipped, and get on with it.
            local function checkThenGo()
                if not route.requires then
                    go()
                elseif anyway then
                    navEcho("Setting off without checking for "
                        .. taPackage.navItemPhrase(taPackage.navWanted(route.requires))
                        .. " — you asked for it anyway.")
                    go()
                else
                    navCheckInventory(route.requires, gen, go, route.requiresFor)
                end
            end
            -- Resuming starts in the middle, so the route's starting room is the
            -- one thing we know we are NOT in, and there is nothing here to
            -- check against: the step list says which directions to walk, not
            -- which rooms they pass through. Say where we are and whose word we
            -- are taking for it. What does get checked is the next seam -- a
            -- resume that was a leg or two out is stopped there rather than at
            -- the far end of the walk.
            if resumeAt then
                navEcho("Resuming " .. destination .. " at step " .. resumeAt
                    .. " — I'm in " .. name .. ", and I'm taking your word that that's where"
                    .. " step " .. resumeAt .. " starts. The next seam check will tell us.")
                checkThenGo()
                return
            end
            -- A map reference we couldn't resolve because there is no map. The
            -- probe still ran and still had to answer -- that part is about the
            -- connection being alive, not about the map -- so all that's missing
            -- is the comparison. Say where we are and let the user judge it.
            if noMap and not fromFp then
                navEcho("No map here, so I can't check I'm at " .. tostring(route.from)
                    .. " — I'm in '" .. name .. "' with exits " .. navExitKey(dirs) .. ".")
                checkThenGo()
                return
            end
            local ok, here, _, weak = taPackage.navFromMatches(route.from, name, dirs)
            if ok then
                -- A fingerprint that named no exits matched on the room name
                -- alone, and "stonework chamber" is twenty-four rooms. Walk it,
                -- but say out loud how little was checked.
                if weak then
                    navEcho("Going on the room name alone — I can't tell this"
                        .. " '" .. name .. "' from any other. Check it's the right one."
                        .. " (Its exits are " .. navExitKey(dirs)
                        .. " — tell me and I'll make the check exact.)")
                end
                checkThenGo()
                return
            end
            navEcho("I don't know how to get there from here.")
            navEcho("  I'm in " .. here .. ".")
            navEcho("  The route to " .. destination
                .. (fromFp and " starts from " or " starts at ") .. fromLabel .. ".")
        end,
    }
    taPackage.slugProbe = probe
    send("")
    send("ex")
    createTimer(NAV_PROBE_TIMEOUT_MS, function()
        if (taPackage.navGen or 0) ~= gen then return end
        if not (taPackage.slugProbe and taPackage.slugProbe.nav) then return end
        taPackage.slugProbe = nil
        navEcho("The game never told me what room I'm in — nothing sent. Try again.")
    end, { repeating = false })
end, { type = "regex" })

createAlias("^stop-navigating$", function()
    if stopNavigate() then
        navEcho("Stopped walking.")
    else
        navEcho("Not currently walking anywhere.")
    end
end, { type = "regex" })

-- A locked door we lack the key for. For a route that ends by probing a door
-- this is the answer it went to find out; for a route that walks THROUGH a door
-- mid-way (the platinum errand opens with the ruby door) it's a hard stop, and
-- naming the step is what says which door was shut.
createTrigger("^The locked (.+) door prevents your exit in that direction\\.$", function(matches)
    local j = taPackage.navigate
    if not j then return end
    -- A gate is a door we expected to find shut about half the time -- the sewer
    -- doors relock around 3am and a key once fetched is kept -- so it names the
    -- errand that fetches its key. Run that and try the door again rather than
    -- ending the walk on the one answer the route was written to handle.
    -- Not while probing a final door: that probe is sent after the last step,
    -- so stepKind still names the step before it -- and if that step were itself
    -- a gate we'd fetch a key for the wrong door and re-walk the probe.
    local gate = (j.phase ~= "door" and j.stepKind == "gate") and j.steps[j.index] or nil
    if gate and gate.detour then
        j.gateTried = j.gateTried or {}
        if j.gateTried[gate] then
            stopNavigate()
            navEcho("Walked " .. gate.detour .. " and the " .. gate.door
                .. " door is still locked — stopping rather than fetching the "
                .. (gate.key or "same") .. " key all over again.")
            return
        end
        j.gateTried[gate] = true
        local detour = NAV_ROUTES[gate.detour].steps
        -- Spliced in BEFORE the gate with the index rewound one, so the errand
        -- runs and then this same door is tried again. Nothing else has to know:
        -- the step list is simply longer, which is what the arrival check and
        -- the trip recovery both already work from -- and a gate inside the
        -- errand splices the same way, so nesting needs no extra thought.
        for k = #detour, 1, -1 do table.insert(j.steps, j.index, detour[k]) end
        j.index = j.index - 1
        -- No brief follows a refusal, but the walk is now between steps; leaving
        -- this as "gate" would let a stray line be read as getting through.
        j.stepKind = nil
        navEcho("The " .. gate.door .. " door is locked and I don't have the "
            .. (gate.key or "right") .. " key — fetching it first, by way of "
            .. gate.detour .. " (" .. #detour .. " steps).")
        navScheduleStep()
        return
    end
    -- Which key, if we know: a gate names one, and so does a final door probe.
    local door, dest = matches[2], j.destination
    local want = (gate and gate.key) or (j.door and j.door.key)
    local where = (j.phase == "door") and ("the way on from " .. dest)
        or ("step " .. j.index .. " of " .. dest)
    stopNavigate()
    navEcho("A locked " .. door .. " door blocks " .. where
        .. " and I don't have the key — I need to go get the key"
        .. (want and (" (the " .. want .. " key)") or "") .. ".")
end, { type = "regex" })

-- We already hold the key: the door opens and the arrival brief follows, so the
-- walk carries on by itself. Record which key it was; the brief handler reports
-- it. This is the branch a second run takes to skip the key detour entirely.
createTrigger("^Your (.+) key unlocks the (.+) door and allows you to pass through\\.$", function(matches)
    local j = taPackage.navigate
    if not j then return end
    j.doorOpenedByKey = matches[2]
end, { type = "regex" })

-- A direction the game rejects outright can't be retried into working, and
-- sending the rest of the route from a room it doesn't apply to only digs the
-- hole deeper. Stop and say which step failed.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    local j = taPackage.navigate
    if not j then return end
    local dest = j.destination
    local where = (j.phase == "door")
        and ("the " .. j.door.dir .. " door out of " .. dest)
        or ("step " .. j.index .. " of " .. #j.steps .. " (" .. tostring(j.steps[j.index]) .. ")")
    stopNavigate()
    navEcho("No exit that way at " .. where .. " — stopping."
        .. " Either the route is wrong or I wasn't where I thought I was.")
end, { type = "regex" })

-- =========================================================================
-- Getting poisoned on the way
-- =========================================================================
--
-- A route declares `onPoison = "drink verbena"` and we drink when the game
-- says we've been poisoned.
--
-- Reacting to the announcement, rather than putting the drink at a fixed step,
-- is deliberate: the poison does not arrive on a schedule. Its source is the
-- crossbow trap in the sewers room west of the hydra ("Several crossbow bolts
-- fire from holes in the walls, striking you!") -- it wounds and poisons, and
-- in the logs it takes the whole party at once. But it doesn't always land,
-- and the poison doesn't always declare itself at once: on the 2026-08-03 walk
-- the bolts struck on step 1 and the poison announced itself fifteen steps
-- later, out in the desert. A fixed step would have drunk in the wrong room.
--
-- "You're poisoned!" is NOT one line per poisoning. It is a status line that
-- repeats for as long as the poison is in you, once per tick, arriving two or
-- three lines apart -- the same shape as the "You're thirsty." spam that fills
-- problem.log, and in the archived logs it runs alongside "<name> looks a
-- little under the weather." for every poisoned party member:
--
--     Status:       Poisoned
--     Teekywiki looks a little under the weather.
--     You're poisoned!
--     Teekywiki looks a little under the weather.
--     You're poisoned!
--
-- Reacting to every one of those would empty the pack of potions in seconds.
-- So drink at most once per poisoning: hold off while a drink is unanswered,
-- and then for a cooldown afterwards, long enough that the tail of one
-- poisoning's ticks can't be read as a fresh one. A genuine second poisoning
-- later in a walk still gets treated.
local NAV_CURE_COOLDOWN_MS = 15000

createTrigger("^You're poisoned!$", function()
    local j = taPackage.navigate
    if not (j and j.onPoison) then return end
    -- A drink is already on its way; this is the same poisoning still ticking.
    if j.curePending then return end
    local now = navNowMs()
    if j.lastCureAt and (now - j.lastCureAt) < NAV_CURE_COOLDOWN_MS then
        navDebug("still poisoned on step " .. j.index .. " — already drank, holding off")
        return
    end
    j.cures = (j.cures or 0) + 1
    j.curePending = true
    j.lastCureAt = now
    navDebug("poisoned on step " .. j.index .. " — " .. j.onPoison)
    navEcho("Poisoned — " .. j.onPoison .. ".")
    send(j.onPoison)
end, { type = "regex" })

createTrigger("^You feel somehow different after drinking the potion\\.$", function()
    local j = taPackage.navigate
    if not (j and j.curePending) then return end
    j.curePending = nil
    navEcho("  Drank it.")
end, { type = "regex" })

-- The cure isn't in the pack. The walk carries on, because stopping in a sewer
-- while poisoned is not obviously better than walking out of it -- but only
-- this line will tell you it happened.
createTrigger("^Sorry, but you don't seem to have one\\.$", function()
    local j = taPackage.navigate
    if not (j and j.curePending) then return end
    j.curePending = nil
    navEcho("  Nothing left to drink — still poisoned. Break off if that won't survive the walk.")
end, { type = "regex" })

-- A trap door drops us a floor mid-step. The game prints the room we walked
-- into, THEN the fall, THEN the pit -- two arrival briefs for one move, and
-- counting both would run the step list a move ahead of the character. Swallow
-- the pit's brief; the route's own next step is the climb back out.
--
--     e
--     You're in a cave.
--     There is an ogress here.
--     There is nothing on the floor.
--     You just fell through a trap door in the floor!
--     You're in a pit.
--
-- The pit on the way to the hydra is why `town-3/hydra` insists on a rope: its
-- walls "rise some ten feet above your head" and can't be climbed unaided.
createTrigger("^You just fell through a trap door in the floor!$", function()
    local j = taPackage.navigate
    if not j then return end
    navDebug("fell through a trap door on step " .. j.index)
    j.blocked = true
end, { type = "regex" })

createTrigger("^In your haste, you trip and fall!$", navRecoverAfterRefusedMove, { type = "regex" })

-- Being winded is not tripping, and treating it as one was wrong three ways.
--
-- Every occurrence of it in the runs so far -- twelve of them, across three
-- errands -- landed on the FIRST move after a kill-all, and none on any other
-- step. It is the fight catching up with us, not the pace: the character is out
-- of breath, hasn't dropped anything and hasn't stumbled. So counting it as a
-- trip put "5 trip(s), pace 1500ms" in the closing trace and made the pacing
-- look like the culprit, which it isn't -- slowing the walk down would not
-- avoid a single one of these. Checking the floor afterwards was wasted work
-- too: twelve floor checks, twelve "Nothing dropped in the fall."
--
-- And it was slow. Each retry cost the 2s trip pause plus a bare return, its
-- reply, and a pacing beat -- about 4.3s a go, three to five gos, 13 to 21
-- seconds of it. Retrying straight away, with no floor check, roughly halves
-- that.
createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function()
    local j = taPackage.navigate
    if not j then return end
    j.rests = (j.rests or 0) + 1
    -- "attempt N" is about THIS move, so it counts from the step rather than
    -- from the walk. after-doors clears three rooms and comes out of each of
    -- them winded, and on its first live run the walk total made the third
    -- episode announce itself as "attempt 20" -- which reads as one move
    -- refused twenty times over rather than the fifth refusal of a fresh one.
    -- The walk total is still what the closing trace reports.
    if j.restStep ~= j.index then j.restStep, j.restRun = j.index, 0 end
    j.restRun = j.restRun + 1
    navDebug("winded on step " .. j.index .. " (rest " .. j.restRun
        .. " here, " .. j.rests .. " this walk)")
    if j.restRun == 1 or j.restRun % 5 == 0 then
        navEcho("Winded from the fight — retrying the move (attempt " .. j.restRun .. ").")
    end
    -- navResendStep clears this again; set in case the game reprints the room.
    j.blocked = true
    navScheduleResend(NAV_REST_RETRY_MS)
end, { type = "regex" })

-- Something engaged us mid-route: the game refuses the move and prints no room
-- line. This is the commonest refusal in the logs by a wide margin (11,655 of
-- them), and the stoneworks legs walk through rooms holding kobolds, imps and
-- rats, so a long route meets it constantly.
--
-- Keep trying. Stopping would abandon a forty-step walk to any wandering rat
-- that picks a fight, and it leaves the character standing in the fight
-- regardless -- giving up on the move buys nothing. Monsters break off, or
-- die, and then the step goes through. The arena's walk-outs have retried this
-- same line on a 2s timer for months, which is where the interval comes from.
--
-- Announced on the first block and every fifth after, so a walk pinned down by
-- something it can't get away from is visible rather than silently stuck.
createTrigger("^You cannot leave in the heat of battle!$", function()
    local j = taPackage.navigate
    if not j then return end
    j.combatBlocks = (j.combatBlocks or 0) + 1
    navDebug("held in combat on step " .. j.index .. " (block " .. j.combatBlocks .. ")")
    if j.combatBlocks == 1 or j.combatBlocks % 5 == 0 then
        navEcho("Something has me in combat — can't move yet, still trying (attempt "
            .. j.combatBlocks .. "). kill-all or flee to break it.")
    end
    -- navResendStep clears this again. It's set in case the game reprints the
    -- room, so that reprint isn't miscounted as an arrival.
    j.blocked = true
    navScheduleResend(NAV_COMBAT_RETRY_MS)
end, { type = "regex" })

-- =========================================================================
-- Clearing the destination for a key
-- =========================================================================
--
-- The game auto-searches every corpse and announces what it turns up. That is
-- how a door key is come by -- there is no `search` to send, we just read the
-- replies. The wording wraps at the terminal width, so the "add to your
-- possessions." form arrives whole or split; both are matched.

-- Announce a key during a sweep. Fetching one is the entire reason a route
-- walks to a monster room, and the line is easy to lose in combat spam.
-- The capture carries the article ("a ruby key"), which reads wrong in a
-- sentence and is wrong again in a `get` command, so strip it as on the floor.
local function navNoteKeyFound(item)
    if not (taPackage.killAllActive or taPackage.killActive) then return end
    local name = navStripArticle(item)
    -- A sweep that named what it wanted ends here, whatever it was.
    local sweep = taPackage.navSweep
    if sweep and sweep.untilFound and name:find(sweep.untilFound, 1, true) then
        navSweepGotWhatItCameFor(name)
        return
    end
    if not name:find("key", 1, true) then return end
    navEcho("Got the " .. name .. ".")
end
createTrigger("^While searching the area, you notice (.+), which you add to your possessions\\.$",
    function(matches) navNoteKeyFound(matches[2]) end, { type = "regex" })
createTrigger("^While searching the area, you notice (.+), which you add to your$",
    function(matches) navNoteKeyFound(matches[2]) end, { type = "regex" })

-- The pack was full when the search turned something up, so the item -- quite
-- possibly the key we came for -- is still lying on the floor.
--
-- Note it and FIGHT ON. Breaking off here would stop us attacking without
-- stopping the room attacking us: the destination rooms on both sewers legs
-- held four live monsters on arrival, so downing tools mid-sweep just means
-- standing there being bitten. Clear the room first; navOnSweepDone above then
-- stops the run once nothing is left swinging.
--
-- Scoped to a route's own sweep: a kill-all or a kill you ran by hand is left
-- entirely alone, since a full pack may be irrelevant to what you're doing.
createTrigger("^While searching the area, you notice (.+), but you can't carry it\\.$", function(matches)
    local sweep = taPackage.navSweep
    if not sweep then return end
    local item = navStripArticle(matches[2])
    sweep.uncarried[#sweep.uncarried + 1] = item
    navEcho("Couldn't carry the " .. item .. " — pack is full. Clearing the room first.")
end, { type = "regex" })

-- =========================================================================
-- Monsters that walk out of a sweep
-- =========================================================================
--
-- A monster that thinks it is losing runs, and the key we came for runs with
-- it. On 2026-08-16 the platinum errand cleared its room, found nothing, and
-- walked all the way back to a still-locked door; the ogre mage holding the key
-- had left to the northeast forty lines earlier (logs/session-pelayo-2026-08-
-- 16T09-21-04.log, lines 815-882). The room brief can't show that -- by the
-- time it says "There is nobody here." the monster is a room away -- so the
-- only record of where the key went is the departure line as it goes past.
--
-- Note that a departure is not necessarily a flight: monsters wander. Either
-- way the reasoning is the same, so we don't try to tell them apart.
--
-- The long word the game prints, mapped to the move that follows it and the
-- move that comes back. main.lua's REVERSE_DIR and dirShort would each do half
-- of this, but they are locals in another chunk and invisible here. Vertical
-- departures read "has just gone upward.", never "to the up", which is why
-- those two words sit in the same table as the compass ones.
local NAV_CHASE_DIR = {
    north     = { "n",  "s"  }, south     = { "s",  "n"  },
    east      = { "e",  "w"  }, west      = { "w",  "e"  },
    northeast = { "ne", "sw" }, southwest = { "sw", "ne" },
    northwest = { "nw", "se" }, southeast = { "se", "nw" },
    upward    = { "u",  "d"  }, downward  = { "d",  "u"  },
}

-- Remember which way something left, but only during an errand's own sweep --
-- one that named what it came for. A kill-all you ran by hand is nobody's
-- business but yours, the same rule the full-pack handler above works to, and
-- a sweep with nothing to find has nothing to chase. The list lives on
-- navSweep, which navStartSweep rebuilds per step, so it can never go stale.
--
-- Players trip the same wording ("Tojolias has just gone to the north."), and
-- "^The " does not rule them out on its own -- a player may be called "The
-- Ripper". Monster names are lowercase and player names are not, so one
-- uppercase letter anywhere in the name settles it.
local function navNoteDeparture(name, word)
    local sweep = taPackage.navSweep
    if not (sweep and sweep.untilFound) then return end
    if name:match("%u") then return end
    local dir = NAV_CHASE_DIR[word]
    if not dir then return end
    sweep.gone = sweep.gone or {}
    sweep.gone[#sweep.gone + 1] = { monster = name, out = dir[1], back = dir[2] }
end

-- It came back, so it is in the room again and the sweep will get to it. Drop
-- every departure under that name: the ogre mage in the log left to the south,
-- returned, and was still there to be killed, and chasing south afterwards
-- would have walked away from the room the key was actually in.
local function navNoteArrival(name)
    local sweep = taPackage.navSweep
    if not (sweep and sweep.gone) then return end
    for i = #sweep.gone, 1, -1 do
        if sweep.gone[i].monster == name then table.remove(sweep.gone, i) end
    end
end

-- One trigger per wording rather than an alternation: the test harness turns
-- these regexes into Lua patterns, which have no `|`, so an alternation would
-- match nothing in the tests while working in play.
createTrigger("^The (.+) has just gone to the (.+)\\.$",
    function(matches) navNoteDeparture(matches[2], matches[3]) end, { type = "regex" })
createTrigger("^The (.+) has just gone upward\\.$",
    function(matches) navNoteDeparture(matches[2], "upward") end, { type = "regex" })
createTrigger("^The (.+) has just gone downward\\.$",
    function(matches) navNoteDeparture(matches[2], "downward") end, { type = "regex" })

-- Arrivals name the monster with its article ("An ogre mage has just arrived"),
-- and the vertical pair drops the "the": "from above", "from below".
createTrigger("^An? (.+) has just arrived from the (.+)\\.$",
    function(matches) navNoteArrival(matches[2]) end, { type = "regex" })
createTrigger("^An? (.+) has just arrived from above\\.$",
    function(matches) navNoteArrival(matches[2]) end, { type = "regex" })
createTrigger("^An? (.+) has just arrived from below\\.$",
    function(matches) navNoteArrival(matches[2]) end, { type = "regex" })
