-- ta_map.lua -- the mapper: where we are, and the room graph we build by walking
--
-- Loaded by main.lua with dofile, at the spot this code used to sit, so its
-- triggers are registered in the same order relative to main.lua's as before.
--
-- Like ta_nav.lua it is a separate chunk and cannot see main.lua's locals; the
-- seam runs through taPackage:
--
--   in    taPackage.db (ta_db.lua); taPackage.monsterDb.state (main.lua's look
--         capture -- a room brief that arrives mid-look is the look talking,
--         not an arrival)
--   out   taPackage.stopMapping (for stop-all-scripts), and the position and
--         mapping state ta_nav.lua reads: taPackage.here, hereState, setHere,
--         trackMove, mapping
--
-- =========================================================================
-- Position tracking
-- =========================================================================
--
-- Knowing where you are and writing the map are different jobs, and until now
-- they were the same code path: `player_location` was only stamped inside the
-- Exits handler, behind the mapping gate, so walking anywhere with mapping off
-- left the recorded position silently stale. It is also why
-- `map-print-room-slug` answers with twelve candidates one step after a room it
-- named exactly -- it compares appearances instead of following the exit you
-- just walked.
--
-- This tracker is READ-ONLY. It never discovers, links or merges; it only
-- follows edges the map already has. A bug here cannot corrupt the graph.
--
-- Three states, because "somewhere off the edge of the map" is a real answer
-- and pretending otherwise is how rooms get invented:
--
--   known    we are in `here`, having walked a mapped exit to reach it
--   off-map  we stepped through an unwalked stub; we know where we left and
--            which way, but not where we are
--   lost     no idea -- login, recall, a teleport, or a contradiction
--
-- It never guesses. Contradicted, it goes `lost` rather than picking a
-- plausible room, which is exactly the failure that cost the desert twice.
taPackage.here = nil
taPackage.hereState = "lost"
taPackage.offMap = nil
-- While lost, the rooms we might be in. Narrowed by each move rather than
-- guessed from appearance: two rooms are called "tavern", but only one of them
-- has an `sw` into a room called "north plaza", so one step settles it. This is
-- the same principle the reconciler uses -- identity comes from the route.
taPackage.hereCandidates = nil

-- Moves we have sent and not yet seen an arrival for.
--
-- This was a single `pendingDirection` slot, which is wrong the moment anyone
-- types ahead: send `n` then `e` before `n`'s brief comes back and the second
-- overwrites the first, so the arrival is matched against the wrong direction.
-- The tracker reported a false disagreement that way, and worse, the MAPPER
-- uses the same field to link edges and dead-reckon coordinates -- so typing
-- ahead while mapping writes wrong edges into the graph.
--
-- Moves and arrivals pair up in order, so a queue is the honest shape.
taPackage.pendingDirs = {}

function taPackage.pushPendingDir(dir)
    taPackage.pendingDirs[#taPackage.pendingDirs + 1] = dir
end

-- The direction for the arrival now being handled. Refused moves shift the
-- queue too, via the "no exit in that direction" trigger.
function taPackage.shiftPendingDir()
    return table.remove(taPackage.pendingDirs, 1)
end

-- Stamp the position for `just report` and for `where`. Called on every change,
-- mapping or not, which is the whole point.
function taPackage.setHere(roomId)
    taPackage.here = roomId
    taPackage.hereState = "known"
    taPackage.offMap = nil
    taPackage.hereCandidates = nil
    if taPackage.character.getName() then
        taPackage.db.setPlayerLocation(taPackage.character.getName(), roomId)
    end
end

function taPackage.loseHere(why)
    taPackage.here = nil
    taPackage.hereState = "lost"
    taPackage.offMap = nil
    taPackage.hereCandidates = nil
    if why then echo("[where] lost track: " .. why) end
end

-- Work out where we are from the walk, while lost. Each arrival narrows the
-- set: keep only the candidates that actually have an exit this way into a room
-- of this name. When one survives, that is where we are -- and it is a far
-- stronger claim than any appearance match, because 194 rooms are called "cave"
-- but very few of them are reached by this sequence of moves.
--
-- Losing every candidate is not a failure, it just means the walk did not start
-- where we assumed; begin again from the name we can see.
function taPackage.narrowHere(dir, name)
    local kept = {}
    if dir and taPackage.hereCandidates then
        for _, id in ipairs(taPackage.hereCandidates) do
            local dest = taPackage.db.exitDestination(id, dir)
            if type(dest) == "number" and taPackage.db.roomName(dest) == name then
                kept[#kept + 1] = dest
            end
        end
    end
    if #kept == 0 then kept = taPackage.db.roomIdsByName(name) or {} end
    taPackage.hereCandidates = kept
    if #kept == 1 then
        taPackage.setHere(kept[1])
        echo("[where] " .. tostring(taPackage.db.roomRef(kept[1]))
            .. " — worked out from the way you walked.")
    end
end

-- One move, followed against the map. `name` is the arriving room's name, which
-- the brief gives us for free -- so the check costs no extra traffic. It cannot
-- tell two identically-named rooms apart, but it catches every gross error, and
-- the strong check (exit-set) still runs while mapping.
function taPackage.trackMove(dir, name)
    if taPackage.hereState == "off-map" then
        taPackage.offMap.moves = taPackage.offMap.moves + 1
        -- Keep trying to recognise where we are. Walking off the map is not a
        -- one-way door: 28 room names identify exactly one room in the world,
        -- so stepping through "large cavern" should put us straight back on it
        -- rather than counting moves forever.
        --
        -- A narrowed set can be wrong -- a genuinely new room could share a name
        -- with a known one -- but the very next move checks the claim against
        -- the map, so a bad acquire is caught rather than compounded.
        taPackage.narrowHere(dir, name)
        return
    end
    if taPackage.hereState ~= "known" then
        taPackage.narrowHere(dir, name)
        return
    end
    if not dir then return end
    local dest = taPackage.db.exitDestination(taPackage.here, dir)
    if type(dest) ~= "number" then
        -- Past the edge of what we have walked. Remember where we left from:
        -- that is what makes the trip back, or a later re-anchor, possible.
        taPackage.offMap = { from = taPackage.here, dir = dir, moves = 1 }
        taPackage.here = nil
        taPackage.hereState = "off-map"
        return
    end
    local expect = taPackage.db.roomName(dest)
    if expect and name and expect ~= name then
        echo("[where] the map says " .. dir .. " leads to \"" .. expect
            .. "\", but this is \"" .. name .. "\" — lost track.")
        taPackage.loseHere(nil)
        taPackage.narrowHere(nil, name)
        return
    end
    taPackage.setHere(dest)
end

-- World map triggers
-- =========================================================================

-- [mapdbg] tracing. ON by default, which is a reversal: it was off because a
-- mapping run prints one of these per arrival, burying the [map] lines and
-- bloating the log.
--
-- Both of those turned out to be the point. Every mapper bug found this week was
-- diagnosed from these traces and from nothing else -- `discoverRoom` naming the
-- id it minted, `findLoopClosure` naming the room it matched -- and the logs are
-- now test fixtures, so a session walked without them is a session that cannot be
-- replayed or argued about afterwards. The cost is scrollback; the benefit is
-- being able to tell what happened.
--
-- `map-debug off` still quiets it. A field rather than a local -- main.lua's
-- 200-local budget.
taPackage.mapDebug = true
function taPackage.mapdbg(msg)
    if taPackage.mapDebug then echo(msg) end
end

-- Reverse of each movement direction, used to record the back-edge when we
-- discover a room by walking into it.
local REVERSE_DIR = {
    n = "s", s = "n", e = "w", w = "e",
    ne = "sw", sw = "ne", nw = "se", se = "nw",
    u = "d", d = "u",
    -- The great-lake ferry ("buy passage") is a symmetric teleport between the two
    -- towns' docks: crossing back is the same "passage", not a compass reverse.
    passage = "passage",
}

-- Grid displacement of each move, as { dx, dy, dz }: north is +y, east is +x,
-- up is +z. Dead-reckoning these from a room's stored coordinate gives the
-- coordinate of the room we walk into, which distinguishes identically-named
-- rooms by position and closes loops the topology alone misses. Coordinates are
-- area-local — only relative offsets matter, so the per-area origin is wherever
-- mapping first anchored (see handleRoomEntry).
local DIR_DELTA = {
    n = { 0, 1, 0 }, s = { 0, -1, 0 }, e = { 1, 0, 0 }, w = { -1, 0, 0 },
    ne = { 1, 1, 0 }, nw = { -1, 1, 0 }, se = { 1, -1, 0 }, sw = { -1, -1, 0 },
    u = { 0, 0, 1 }, d = { 0, 0, -1 },
}

-- Turn the phrase after "You're in/on/at ..." into a canonical room name by
-- dropping a leading article: "the tavern" -> "tavern", "a cave" -> "cave",
-- "an intersection" -> "intersection", "small cavern" -> "small cavern".
local function normalizeRoomName(phrase)
    return (phrase or ""):gsub("^the%s+", ""):gsub("^an?%s+", "")
end

-- Resolve the room we entered when there's no move to walk from (session start,
-- recall, teleport): stay in the room we already believe we're in, else the
-- unique room with this name, else discover a fresh one. Returns the room id and
-- whether it was newly discovered (provisional, i.e. a merge candidate).
local function resolveColdStart(name)
    -- `map-area <slug>` states which area we are standing in, so the cold start
    -- it asks for must only consider rooms of THAT area. The lookup below is
    -- global, which is fine while every new area is reached across a frontier
    -- from a mapped one -- but walk to a town no mapped area touches, run
    -- `map-area fourth-town`, and a single global name match reads as certainty:
    -- "town square" resolves to the THIRD town's square, and the walk writes the
    -- fourth town's exits onto it. A fresh area has no rooms of its own, so
    -- minting is the only honest answer. One-shot, set by map-area immediately
    -- before it bare-returns, so an ordinary cold start (session start, recall)
    -- is unaffected.
    local scoped = taPackage.coldStartArea
    taPackage.coldStartArea = nil
    if scoped then
        local ids = taPackage.db.roomIdsByName(name, scoped)
        if #ids == 1 then return ids[1], false end
        return taPackage.db.discoverRoom(name, scoped), true
    end
    -- After a Teleport we have definitely left, so the "we never moved" shortcut
    -- below is wrong -- and wrong in the worst way here, because [S2] and [S3]
    -- are both "stonework corridor", so it would conclude we are still standing
    -- on the stone we just pushed.
    --
    -- An ambiguous name must mint rather than pick, for the same reason: with 176
    -- rooms called "stonework corridor", `ids[1]` is a coin toss. Minting leaves a
    -- provisional room, which the Exits handler can still fold into a known one on
    -- the evidence of its exit-set.
    if taPackage.arrivedByTeleport then
        -- A Device that says where this Teleport goes settles it outright.
        if taPackage.teleportDest then return taPackage.teleportDest, false end
        local ids = taPackage.db.roomIdsByName(name)
        if #ids == 1 then return ids[1], false end
        return taPackage.db.discoverRoom(name, taPackage.currentAreaId), true
    end
    if taPackage.currentRoomId and name == taPackage.currentRoom then
        return taPackage.currentRoomId, false
    end
    local ids = taPackage.db.roomIdsByName(name)
    if #ids == 1 then return ids[1], false end
    if #ids == 0 then return taPackage.db.discoverRoom(name, taPackage.currentAreaId), true end
    return ids[1], false
end

-- Topology-based room identity: when we arrive after moving `dir` from a known
-- room, the room is whatever that exit already points to; only when the exit's
-- destination is unknown do we mint a new room id and link both directions.
-- A newly-minted room is flagged provisional: the `Exits:` handler may later
-- fold it into an existing room once we know its exit-set (loop closure).
local function handleRoomEntry(matches)
    -- A `look <dir>` peek prints the neighbor's "You're in ..." brief, identical
    -- to an arrival. Suppress that one line so we don't mint a phantom room for a
    -- room we only glanced at (and don't fire the auto look/ex for it).
    if taPackage.suppressRoomEntry then
        taPackage.suppressRoomEntry = false
        return
    end

    local name = normalizeRoomName(matches[2])

    -- A `map-print-room-slug` probe just wants this brief's room name; capture it
    -- and stop, so the probe's bare return doesn't disturb the map (the paired
    -- `ex` resolves and prints in the Exits handler). Takes priority over mapping.
    if taPackage.slugProbe then
        taPackage.slugProbe.name = name
        return
    end

    -- A paced walk (`navigate-to`) advances one room at a time on these briefs.
    -- It hooks in here rather than owning its own room triggers so it inherits
    -- every phrasing of the arrival line -- "You're in/inside/on/at", the "You
    -- are ..." variants, and the verbless "You at ..." -- along with the two
    -- guards above, which stop a `look <dir>` peek or a `look` reply being
    -- counted as a move. (Miscounting arrivals is exactly how the arena's paced
    -- walk wedged in July 2026; see arenaJourneyOnMovement.) It sits ahead of
    -- the mapping gate below because a walk always runs with mapping off -- it
    -- suspends mapping for its duration precisely so it can't write to the map
    -- (see navStart). The hook is installed by the navigation section below.
    if taPackage.navOnRoomBrief then taPackage.navOnRoomBrief(name) end

    -- One arrival consumes one sent move. Placed after the guards above, so a
    -- `look <dir>` peek or a slug probe -- neither of which is an arrival --
    -- cannot eat somebody else's move.
    -- A Teleport is not a compass move, so it consumes nothing from the queue and
    -- leaves pendingDirection nil -- which is what stops an edge being linked for
    -- it further down. Recording one as a compass edge is the specific corruption
    -- docs/hidden-stone-teleport.md describes: the whole [S3] strip once hung off
    -- [S2] by a phantom `e`.
    if taPackage.arrivedByTeleport then
        taPackage.pendingDirection = nil
    else
        taPackage.pendingDirection = taPackage.shiftPendingDir()
    end

    -- A kill with no gold found before we left records zero loot.
    -- (Loot bookkeeping is independent of mapping mode.)
    if taPackage.pendingLootCheck and taPackage.lastKilledMonster then
        taPackage.db.recordMonsterLoot(taPackage.lastKilledMonster, 0)
        taPackage.pendingLootCheck = nil
        taPackage.lastKilledMonster = nil
    end

    -- Mapping mode gates the whole room *graph*: when off, we don't discover,
    -- visit, link, or track position at all. The room *name* is not part of the
    -- graph, so it's tracked either way -- plain bookkeeping that non-mapping
    -- features read: the tavern mode's "are we standing in a bar?" check,
    -- and the monster-presence keys above. Gating the name too left currentRoom
    -- nil for the whole of any ordinary (non-mapping) session.
    -- It's set here rather than hoisted above this gate because the mapping path
    -- below calls resolveColdStart, which recognizes "we're still in the room we
    -- thought we were" by comparing the new name against the *previous*
    -- currentRoom -- so that value has to survive until then.
    if not taPackage.mapping then
        taPackage.trackMove(taPackage.pendingDirection, name)
        taPackage.pendingDirection = nil
        taPackage.prevRoom = taPackage.currentRoom
        taPackage.currentRoom = name
        return
    end

    -- The room this move left is the room we are in NOW. Arrivals are handled in
    -- the order moves were sent, so whatever the previous arrival settled on is
    -- where this one departed from. The move alias records a prevRoomId too, but
    -- at SEND time -- and a second move typed before the first arrives records the
    -- same room twice. In the labyrinth on 2026-09-24 that looked for a `w` on the
    -- dead end instead of the room `s` had reached, and minted a copy of every
    -- room walked after (labyrinth-94..96).
    if taPackage.pendingDirection and taPackage.currentRoomId then
        taPackage.prevRoomId = taPackage.currentRoomId
    end

    -- The coordinate we expect to arrive at: the room we left plus the move's
    -- grid delta. nil when we have no prior coordinate to walk from (a cold
    -- start, or a prev room that was never anchored).
    local arriveCoord
    if taPackage.pendingDirection and taPackage.prevRoomId then
        local delta = DIR_DELTA[taPackage.pendingDirection]
        local base = taPackage.db.roomCoord(taPackage.prevRoomId)
        if delta and base then
            arriveCoord = { x = base.x + delta[1], y = base.y + delta[2], z = base.z + delta[3] }
        end
    end

    local roomId
    if taPackage.pendingDirection and taPackage.prevRoomId then
        local dir = taPackage.pendingDirection
        local dest = taPackage.db.exitDestination(taPackage.prevRoomId, dir)
        if dest and taPackage.db.roomName(dest) == name then
            roomId = dest                       -- known edge, confirmed by name
            taPackage.currentRoomProvisional = false
        elseif dest then
            -- The edge points at a room with a DIFFERENT name than we arrived in
            -- — a stale edge or a spurious room re-display (the game sometimes
            -- reprints the current room on a move). Don't trust it; re-resolve by
            -- name so we don't overwrite the wrong room.
            roomId, taPackage.currentRoomProvisional = resolveColdStart(name)
        else
            -- Unknown exit: mint a provisional room and link the edge. We do NOT
            -- identify the room by coordinate here -- that was exit-blind, and in
            -- this non-Euclidean world two distinct rooms can dead-reckon to the
            -- same coordinate, so a coordinate-only match glued unrelated rooms
            -- together (a {se,nw} room folded onto a 4-exit one). Identity is
            -- resolved in the Exits handler instead, which checks the exit-set:
            -- findRoomByFingerprint (exact coord + exit-set) closes grid-aligned
            -- loops, findLoopClosure (topology + return door) closes drifted ones,
            -- and a genuinely new room simply stays.
            roomId = taPackage.db.discoverRoom(name, taPackage.currentAreaId)
            taPackage.currentRoomProvisional = true
            taPackage.db.linkExit(taPackage.prevRoomId, dir, roomId)
            local back = REVERSE_DIR[dir]
            if back then taPackage.db.linkExit(roomId, back, taPackage.prevRoomId) end
        end
    else
        roomId, taPackage.currentRoomProvisional = resolveColdStart(name)
    end

    -- Anchor this room's coordinate. Adopt a stored coordinate when the room
    -- already has one (trust the persisted map over dead-reckoning, which drifts
    -- when a move is missed); otherwise stamp the coordinate we computed, or a
    -- fresh origin for a cold anchor with nothing to walk from. taPackage.coord is the
    -- cursor the next move dead-reckons from.
    local stored = taPackage.db.roomCoord(roomId)
    if stored then
        taPackage.coord = stored
        -- A room that already knows where it is re-anchors the chain a Teleport
        -- broke.
        taPackage.coordLost = nil
    elseif taPackage.arrivedByTeleport or taPackage.coordLost then
        -- A Teleport has no grid position relative to where we were: there is no
        -- delta to add and no honest value to stamp, so leave the coordinate NULL
        -- rather than claim the origin. Coordinates are soft anyway, and the
        -- renderer lays out by walking exits -- a teleport destination is simply a
        -- component of its own, the way the dungeon's pit is.
        taPackage.coord = nil
    else
        -- Nothing to reckon from: a new frame, started clear of every other frame
        -- in this area (see TaDb.freshOrigin).
        local c = arriveCoord or taPackage.db.freshOrigin(taPackage.currentAreaId)
        taPackage.db.setRoomCoord(roomId, c.x, c.y, c.z)
        taPackage.coord = c
    end

    -- If we just passed through a locked door (the unlock message stashed the
    -- key/door before this brief arrived), tag the edge we crossed -- and its
    -- reverse, since the door blocks both ways -- so the map knows a key is
    -- needed here. Do this after the edges are linked above.
    if taPackage.pendingLock and taPackage.pendingDirection and taPackage.prevRoomId then
        local dir = taPackage.pendingDirection
        local lk = taPackage.pendingLock
        taPackage.db.setExitLock(taPackage.prevRoomId, dir, lk.key, lk.door)
        local back = REVERSE_DIR[dir]
        if back then taPackage.db.setExitLock(roomId, back, lk.key, lk.door) end
    end
    taPackage.pendingLock = nil

    -- The coordinate is legitimately nil after a Teleport, which has no grid
    -- position. The string is built whether or not tracing is on, so this has to
    -- tolerate that rather than index through it.
    taPackage.mapdbg("[mapdbg] entry '" .. tostring(name) .. "' roomId=" .. tostring(roomId)
        .. " (" .. type(roomId) .. ") provisional=" .. tostring(taPackage.currentRoomProvisional)
        .. " coord=" .. (taPackage.coord
            and ("(" .. taPackage.coord.x .. "," .. taPackage.coord.y
                 .. "," .. taPackage.coord.z .. ")")
            or "none (teleport)"))

    -- Follow the room we entered into its area. If a session starts in one area
    -- (e.g. `map-here path-4` in second-town) and then walks across a frontier
    -- into a known room of another area (down into the sewers), adopt that area
    -- so rooms minted onward are filed where we actually are, not where the
    -- session happened to begin. A room just minted above already carries
    -- currentAreaId, so this is a no-op for it; a legacy row with no area (nil)
    -- leaves the current area untouched.
    local enteredArea = taPackage.db.roomArea(roomId)
    if enteredArea then taPackage.currentAreaId = enteredArea end

    taPackage.db.recordVisit(roomId)
    taPackage.prevRoomId = taPackage.currentRoomId
    taPackage.currentRoomId = roomId
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.currentRoom = name
    -- Remember how we got here for the Exits handler's loop-closure check: it
    -- runs after pendingDirection is cleared, and needs the direction walked to
    -- know which return door a closure candidate must still have open.
    taPackage.currentEntryDir = taPackage.pendingDirection
    taPackage.pendingDirection = nil

    -- Surface the devices you can work here, so a lever reaches us *before* we
    -- walk past it. Only runs while mapping, which is the sole time
    -- currentRoomId is trustworthy.
    for _, d in ipairs(taPackage.db.devicesInRoom(roomId)) do
        echo("[device] #" .. tostring(d.id) .. " " .. d.command
            .. " (" .. d.effect .. (d.repeats and (", " .. d.repeats) or "") .. ")")
    end

    -- While mapping, capture the room: `look` for its description, then `ex`
    -- for its exits. The `ex` reply ("Exits: ...") both ends the look capture
    -- and drives loop closure. Neither reply is a room line, so no re-entry.
    send("look")
    send("ex")
end

-- A room line that arrives while a bare `look` is still being captured is that
-- look's own output, not an arrival. Defined here rather than beside the "You
-- are" triggers below because every preposition now goes through it, and in Lua
-- a local has to exist before the trigger that names it.
local function handleRoomEntryUnlessLooking(matches)
    if taPackage.monsterDb.state == "accumulating_room" then return end
    -- The brief after the smoke is a Teleport, not a move (see the smoke trigger
    -- below). If the room it fired in has a Device saying where it goes, and the
    -- brief names that room, that is where we are; otherwise we are lost, as
    -- after `push stone`, rather than guessing among same-named rooms.
    local smoke = taPackage.pendingSmoke
    if smoke then
        taPackage.pendingSmoke = nil
        local lookup = smoke.lookup or taPackage.db.teleportOnEntry
        local dest = smoke.from and lookup(smoke.from) or nil
        if dest and taPackage.db.roomName(dest) ~= normalizeRoomName(matches[2]) then
            dest = nil
        end
        taPackage.arrivedByTeleport = true
        taPackage.teleportDest = dest
        taPackage.coordLost = true
        if not dest and taPackage.hereState ~= "lost" then
            taPackage.loseHere((smoke.what or "the smoke") .. " moved you somewhere no Device records")
        end
        handleRoomEntry(matches)
        if dest and not taPackage.mapping then taPackage.setHere(dest) end
        taPackage.arrivedByTeleport = nil
        taPackage.teleportDest = nil
        return
    end
    handleRoomEntry(matches)
end

-- One trigger per preposition (mutually exclusive prefixes, so no double-fire).
--
-- "The 'You're' contraction is always a move brief" is what this comment used to
-- say, and the Stone Passages north of the deep forest disproved it on
-- 2026-09-17: that room briefs as "You're in a stone passage." on arrival and
-- answers `look` with "You're in a stone passage leading north and south." -- an
-- arrival brief, contraction and all, and under a LONGER name. Every other room
-- describes itself as "You are standing deep within...", which is why only the
-- "You are" forms were guarded. So the mapper's own probe re-entered here, minted
-- a second room for the same passage, and sent another `look`, which answered the
-- same way: 32 laps before the session was killed by hand.
--
-- These go through the same guard as the "You are" forms now. A bare `look` is
-- outstanding from its echo until the `Exits:` line terminates the description
-- capture, and a room line inside that window is the look talking, not a move.
createTrigger("^You're in (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You're inside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You're on (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You're at (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
-- "outside" is the fifth preposition, and it went missing for a long time
-- because exactly one known room uses it -- "You're outside the town gates.",
-- between the first town's south plaza and the mountains. The cost was paid
-- twice. The mapper walked through it on 2026-07-13, couldn't read the name,
-- and left a south-plaza --sw--> mountains edge that swallows the room whole.
-- And a `navigate-to ruined-town` walk stepped into it on 2026-08-04 and simply
-- stopped: the arrival never registered, so the walk sat waiting for a brief
-- that had already gone past.
createTrigger("^You're outside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
-- And "down in", which the shaft below the mountain road's crooked path uses
-- all the way down: "You're down in a hole." Missed on 2026-09-28, the descent
-- never registered, so the mapper still believed it stood on the crooked path
-- and stopped at the first `ex`. Its `look` answers "You're down in a hole you
-- found by...", which the looking guard keeps from minting a second room.
createTrigger("^You're down in (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
-- One arrival ends with no full stop at all: "You're on a path in the Elven
-- Valley", north-east of the mountain road. Matched exactly rather than by
-- making the "\\.$" optional everywhere, because the first line of a look wraps
-- at 78 columns and would then read as a brief ("You're in a large stone
-- chamber illuminated by brightly glowing orbs suspended").
createTrigger("^You're on (a path in the Elven Valley)$", handleRoomEntryUnlessLooking, { type = "regex" })

-- Some rooms print their move brief with "You are ..." instead of the "You're"
-- contraction (e.g. "You are inside the dungeon entrance.", "You are in a large
-- cavern."). That exact phrasing is ALSO the first line of every look
-- description, so it's ambiguous by wording. The tell: a look line arrives while
-- we're accumulating a description; a move brief arrives when we're idle. Only
-- treat "You are ..." as an arrival when we're not mid-look.
createTrigger("^You are in (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are inside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are on (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are at (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are outside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })

-- A few rooms have a grammatically broken move brief that drops the verb
-- entirely: "You at the bottom of a stairwell." (no "'re"/"are"). It's a real,
-- consistent game quirk, and without a matching trigger the arrival is missed —
-- the mapper stays in the room above, then mis-links everything you map next and
-- mints duplicates when you climb back. Treated like the "You are ..." forms
-- (idle-only, so a look line can't spoof it). Only "at" has been seen so far.
createTrigger("^You at (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })

local moveDirections = { "n", "s", "e", "w", "ne", "nw", "se", "sw", "u", "d" }
-- The same set, for a navigate walk: its moves skip these aliases, and only a
-- step in here is a move the arrival queue should expect an answer to.
taPackage.moveDirs = {}
for _, dir in ipairs(moveDirections) do taPackage.moveDirs[dir] = true end
for _, dir in ipairs(moveDirections) do
    createAlias("^" .. dir .. "$", function()
        -- A real move: this arrival must not be suppressed, even if a prior
        -- `look <dir>` returned no room and left the flag armed, or a bare `look`
        -- never saw the `Exits:` line that ends its capture. Both would otherwise
        -- swallow the brief we are about to walk into.
        taPackage.suppressRoomEntry = nil
        taPackage.abandonRoomDescCapture()
        taPackage.pushPendingDir(dir)
        taPackage.prevRoom = taPackage.currentRoom
        taPackage.prevRoomId = taPackage.currentRoomId
        send(dir)
    end, { type = "regex" })
end

-- Resolve and print what room a `map-print-room-slug` probe is standing in,
-- from the captured name + observed exit-set: the definitive slug when exactly
-- one known room matches, every candidate when several do (with coords to help
-- you pick), or nothing-matches. The output is what you'd pass to `map-here`.
local function printRoomSlugCandidates(name, dirs)
    local exits = table.concat(dirs, ",")
    if not name then
        echo("[map] couldn't read the room name — try map-print-room-slug again")
        return
    end
    local matches = taPackage.db.roomsMatchingFingerprint(name, dirs)
    if #matches == 0 then
        echo("[map] no known room matches '" .. name .. "' with exits " .. exits
            .. " (new room? use map-area to start mapping here)")
    elseif #matches == 1 then
        -- A definitive identification, so the tracker takes it. Printing "this
        -- is north-plaza" while `where` still answered "lost" was absurd.
        taPackage.setHere(matches[1].id)
        -- The `map-here` hint stays: it also turns MAPPING on, which is a
        -- different thing from knowing where you are.
        echo("[map] this is " .. matches[1].slug .. "  (position tracked)"
            .. "  ->  map-here " .. matches[1].slug .. " to map from here")
    else
        -- Ambiguous by appearance, but the walk will narrow it: seed the
        -- candidate set so the next move or two settles it.
        local ids = {}
        for _, m in ipairs(matches) do ids[#ids + 1] = m.id end
        taPackage.hereCandidates = ids
        local parts = {}
        for _, m in ipairs(matches) do
            local coord = (m.x ~= nil) and (" (" .. m.x .. "," .. m.y .. "," .. m.z .. ")") or ""
            parts[#parts + 1] = m.slug .. coord
        end
        echo("[map] " .. #matches .. " candidates for '" .. name .. "' [" .. exits .. "]: "
            .. table.concat(parts, ", "))
        -- The map already stamped where this character was standing when it last
        -- ran, so when that room is one of the candidates it is almost certainly
        -- the answer -- and a tie-break is free. On 2026-09-13 a probe in the
        -- Stoneworks offered four identical corridors while player_location named
        -- the right one, and the walk spent a move narrowing them down by hand.
        -- A hint, not a pick: the location is stamped while MAPPING, so a
        -- character walked around with mapping off has silently moved on.
        local lastSeen = taPackage.character.getName()
            and taPackage.db.playerLocation(taPackage.character.getName())
        if lastSeen then
            for _, m in ipairs(matches) do
                if m.id == lastSeen then
                    echo("[map] the map last saw you in " .. m.slug
                        .. " -- if nothing walked since, that is this room"
                        .. "  ->  map-here " .. m.slug)
                    break
                end
            end
        end
        echo("[map] walk a room or two and they will narrow on their own.")
    end
end

-- Do two rooms' descriptions contradict each other? Only when both have one: a
-- room never looked at is no evidence, the same rule findLoopClosure uses. The
-- fresh room's description is already stored by the time the Exits handler asks,
-- because the look capture ends on that same `Exits:` line and fires first.
function taPackage.closureDescriptionsDiffer(a, b)
    local da, db_ = taPackage.db.roomDescription(a), taPackage.db.roomDescription(b)
    return type(da) == "string" and type(db_) == "string" and da ~= db_
end

-- Has a held closure's chain passed through a room that does not look like the
-- one it started on? Until it has, its agreement is no evidence: in a corridor of
-- identical rooms every room agrees with every other, so the chain would have
-- agreed whichever room it was offered. The Elven Valley's wall path is a ring of
-- rooms that share a name, a description and (bar the corners) exits e,w, and
-- twice a walk west of path-in-the-elven-valley-7 was merged three rooms on into
-- the far end of the walked arm -- a six-room ring of nothing but e moves
-- (2026-10-02, and logs/session-pelayo-2026-10-17T17-15-32.log, line 220).
function taPackage.closureChainDistinguished(pc)
    local function roomLook(id)
        local dirs = {}
        for d in pairs(taPackage.db.roomExitDirections(id)) do dirs[#dirs + 1] = d end
        table.sort(dirs)
        return table.concat(dirs, ","), taPackage.db.roomDescription(id)
    end
    local firstDirs, firstDesc = roomLook(pc.pairs[1].into)
    for i = 2, #pc.pairs do
        local dirs, desc = roomLook(pc.pairs[i].into)
        if dirs ~= firstDirs then return true end
        if type(desc) == "string" and type(firstDesc) == "string" and desc ~= firstDesc then
            return true
        end
    end
    return false
end

-- How many fresh rooms in a row must agree with a held loop closure before it
-- is merged. Three, because the labyrinth's Level 3 has a corridor that mimics a
-- walked one for three rooms and only the third tells them apart.
taPackage.closureConfirmations = 3

-- Merge a held closure: every provisional room of the chain into the room the
-- candidate's graph predicted for it, in order. Moves our position onto the
-- merged room if we were standing on one of the provisionals.
function taPackage.settleClosure(pc)
    local pairs_ = pc.pairs or { { from = pc.from, into = pc.into } }
    for _, p in ipairs(pairs_) do
        taPackage.db.mergeRoomInto(p.from, p.into)
        if taPackage.currentRoomId == p.from then
            taPackage.currentRoomId = p.into
            taPackage.currentRoomProvisional = false
            local snapped = taPackage.db.roomCoord(p.into)
            if snapped then taPackage.coord = snapped end
        end
        if taPackage.prevRoomId == p.from then taPackage.prevRoomId = p.into end
    end
    echo("[map] " .. (pc.seam and "Seam crossing confirmed: #" or "loop closure confirmed: #")
        .. tostring(pairs_[1].from) .. " was #" .. tostring(pairs_[1].into))
    -- A confirmed Seam leaves us standing in the other area, so follow it: rooms
    -- minted from here belong to where we actually are. handleRoomEntry does this
    -- for a KNOWN room, and cannot for one it has just folded in.
    local landedIn = taPackage.db.roomArea(taPackage.currentRoomId)
    if landedIn and landedIn ~= taPackage.currentAreaId then
        taPackage.currentAreaId = landedIn
        echo("[map] now mapping " .. tostring(taPackage.db.areaSlugOf(taPackage.currentRoomId)))
    end
    if taPackage.currentRoomId then taPackage.setHere(taPackage.currentRoomId) end
end

-- `ex` prints the current room's exits ("Exits: n,e,sw."). While mapping, use
-- them for loop closure: if we provisionally minted this room but it's really an
-- already-known one (same name + exit-set), fold the provisional into it. Then
-- seed each exit as a known edge so the map shows it before it's walked.
createTrigger("^Exits: (.+)\\.$", function(matches)
    local dirs = {}
    for dir in matches[2]:gmatch("[^,%s]+") do dirs[#dirs + 1] = dir end

    -- A room probe: identify (don't map), then stop. `map-print-room-slug` just
    -- prints the candidates; a probe that carries an onResolve callback wants
    -- them instead (navigate-to checks them against a route's starting room).
    if taPackage.slugProbe then
        local probe = taPackage.slugProbe
        taPackage.slugProbe = nil
        if probe.onResolve then
            probe.onResolve(probe.name, dirs)
        else
            printRoomSlugCandidates(probe.name, dirs)
        end
        return
    end

    -- Nothing to do (and nothing to debug-log) unless we're actively mapping;
    -- this guard sits before the [mapdbg] echo so a plain `ex` during normal
    -- play stays quiet.
    if not taPackage.mapping or not taPackage.currentRoomId then return end
    taPackage.mapdbg("[mapdbg] Exits trigger: mapping=" .. tostring(taPackage.mapping)
        .. " currentRoomId=" .. tostring(taPackage.currentRoomId)
        .. " (" .. type(taPackage.currentRoomId) .. ")")

    -- Confirm or refute a loop closure deferred from the previous arrival.
    --
    -- findLoopClosure matches on name, exit-set and "the return door is an
    -- unwalked stub", and in this world all three are weak: 85 rooms are called
    -- "stonework corridor", and a corridor's description names only its exits, so
    -- two with the same exit-set read identically. On 2026-09-13 a walk matched a
    -- brand-new corridor to one on the far arm of the level and merged them.
    --
    -- Coordinates cannot settle it. That same log holds a FALSE closure one
    -- diagonal off (reckoned (3,-6) against a candidate at (4,-5)) and a TRUE one
    -- one diagonal off the other way ((1,-6) against (0,-5)). Any tolerance loose
    -- enough for the real closure admits the bad one, and that is structural: a
    -- real closure IS a coordinate disagreement, which is why this fallback exists.
    --
    -- What does settle it is the next move. Believing it stood in the candidate,
    -- that walk stepped `sw` and arrived somewhere answering ne,se,w where the
    -- candidate's `sw` neighbour was recorded as ne,sw. So: hold the closure, walk
    -- one more room, and ask the graph whether it agrees.
    --
    -- One agreeing room is not always enough. In the labyrinth's Level 3 a new
    -- corridor mimics a walked one for THREE rooms -- same name, description and
    -- exits -- and one agreement merged it, after which the walk followed the old
    -- edges until the lost-room guard stopped it (twice, on 2026-09-25). So the
    -- closure is held while fresh rooms keep agreeing, up to closureConfirmations,
    -- and any disagreement in that window refuses it. If the walk turns back or
    -- mapping stops, it merges on the agreement it has, as it always did; if it
    -- reaches a room the candidate cannot predict, or one that sits exactly on a
    -- different mapped room, the chain is dropped.
    local holding = false
    if taPackage.pendingClosure and taPackage.currentRoomProvisional then
        local pc = taPackage.pendingClosure
        pc.pairs = pc.pairs or { { from = pc.from, into = pc.into } }
        local last = pc.pairs[#pc.pairs]
        local onward = taPackage.currentEntryDir
        local expected = onward and taPackage.prevRoomId == last.from
            and taPackage.db.exitDestination(last.into, onward) or nil
        -- A room sitting EXACTLY on a mapped room's square with that room's exits
        -- is a match trusted outright everywhere else (see the reconcile below).
        -- If it names a different room from the one the chain predicts, the chain
        -- is wrong: Level 5 of the labyrinth walked back onto labyrinth-286 while a
        -- chain insisted it was 278, two columns over (2026-09-26).
        -- Exactly means its coordinate was compared and agreed: a lookalike with no
        -- stored coordinate sits on no square and overrules nothing.
        local exact, onSquare
        if taPackage.coord then
            local _
            exact, _, onSquare = taPackage.db.findRoomByFingerprint(
                taPackage.currentRoom, dirs, taPackage.currentRoomId, taPackage.coord,
                taPackage.currentAreaId)
        end
        if type(exact) == "number" and onSquare and exact ~= expected then
            taPackage.pendingClosure = nil
            echo("[map] loop closure into #" .. tostring(pc.into)
                .. " refused -- this room sits exactly on #" .. tostring(exact) .. " instead")
        elseif type(expected) == "number" and taPackage.db.hasEntryTeleport(expected) then
            -- It predicts a room that throws you elsewhere the moment you enter,
            -- and here we stand. Level 5's [G], 2026-09-26.
            taPackage.pendingClosure = nil
            echo("[map] loop closure into #" .. tostring(pc.into)
                .. " refused -- it predicts #" .. tostring(expected)
                .. ", which would have teleported you")
        elseif type(expected) == "number"
            and taPackage.closureDescriptionsDiffer(taPackage.currentRoomId, expected) then
            -- Same name, same exits, and yet the room says it is something else.
            -- Stoneworks Level 6's chasm room mimicked stonework-corridor-171 in
            -- every way the fingerprint checks, and the walk then had to turn back
            -- at the chasm, which settled the chain on two rooms and merged it
            -- (logs/session-teekywiki-2026-09-27T19-13-40.log, line 4659).
            taPackage.pendingClosure = nil
            echo("[map] loop closure into #" .. tostring(pc.into)
                .. " refused -- this room's description is not #" .. tostring(expected) .. "'s")
        elseif type(expected) == "number"
            and taPackage.db.roomLooksLike(expected, taPackage.currentRoom, dirs) then
            pc.pairs[#pc.pairs + 1] = { from = taPackage.currentRoomId, into = expected }
            local agreed = #pc.pairs - 1
            local distinguished = taPackage.closureChainDistinguished(pc)
            if agreed >= taPackage.closureConfirmations and distinguished then
                taPackage.pendingClosure = nil
                taPackage.settleClosure(pc)
            elseif agreed >= taPackage.closureConfirmations then
                holding = true
                echo("[map] " .. (pc.seam and "Seam crossing" or "loop closure")
                    .. " into #" .. tostring(pc.into) .. " agrees so far (" .. agreed
                    .. "), but every room so far looks alike -- keep walking to a room that differs")
            else
                holding = true
                echo("[map] " .. (pc.seam and "Seam crossing" or "loop closure")
                    .. " into #" .. tostring(pc.into) .. " agrees so far (" .. agreed
                    .. " of " .. taPackage.closureConfirmations .. ") -- keep walking to settle it")
            end
        elseif type(expected) ~= "number" and #pc.pairs >= 2 then
            -- The candidate has nothing to say about this room. That is running
            -- out of evidence, not agreement: on Level 5 it merged three real rooms
            -- two columns from where they were. Drop it; a duplicate is mergeable.
            taPackage.pendingClosure = nil
            echo("[map] loop closure into #" .. tostring(pc.into) .. " dropped -- "
                .. (#pc.pairs - 1) .. " of " .. taPackage.closureConfirmations
                .. " rooms agreed, then #" .. tostring(last.into) .. " had nothing to"
                .. " predict this one with")
        else
            -- Refuted, or nothing to check against. Either way the rooms stay
            -- separate: a duplicate is visible and mergeable, where a wrong merge
            -- deletes a room and misattaches everything walked after it.
            taPackage.pendingClosure = nil
            echo("[map] loop closure into #" .. tostring(pc.into)
                .. " refused -- the next room is not what it predicted")
        end
    elseif taPackage.pendingClosure then
        -- The next arrival was not a fresh room -- we turned back, say -- so the
        -- chain cannot go on. Settle on what agreed so far, or drop it if nothing
        -- has yet.
        local pc = taPackage.pendingClosure
        taPackage.pendingClosure = nil
        if pc.pairs and #pc.pairs >= 2 then
            if taPackage.closureChainDistinguished(pc) then
                taPackage.settleClosure(pc)
            else
                echo("[map] loop closure into #" .. tostring(pc.into) .. " dropped -- every"
                    .. " room that agreed looks alike, so the agreement proves nothing")
            end
        end
    end

    -- Are we where we think we are? `ex` lists every exit a room has (sealed ones
    -- and u/d too), so a stored exit it leaves out means this is some OTHER room
    -- -- or the map gave this one an exit it does not have. Either way nothing
    -- below may be written onto it, so stop mapping and say why.
    --
    -- Only for a room we believe we know. A room minted on this move holds just
    -- the back-link the mapper assumed, which a bent passage makes wrong without
    -- anyone being lost.
    --
    -- The Orc Caves, 2026-09-22: a chance Seam match put the walk on July's caves
    -- under the ruined town. Three rooms in, `ex` said ne,s where the room we
    -- "were" in has nw,s, and the mapper added `ne` to it and walked on
    -- (logs/session-teekywiki-2026-09-22T21-20-30.log).
    if not taPackage.currentRoomProvisional then
        local missing = taPackage.exitsMissingFrom(taPackage.currentRoomId, dirs)
        if #missing > 0 then
            local ref = taPackage.db.roomRef(taPackage.currentRoomId)
                or ("#" .. tostring(taPackage.currentRoomId))
            taPackage.mapping = false
            taPackage.loseHere("the map has " .. ref .. " with "
                .. table.concat(missing, ",") .. ", which this room does not")
            cecho("red", "[map] mapping OFF: `ex` says " .. table.concat(dirs, ",")
                .. ", but " .. ref .. " has " .. table.concat(missing, ",")
                .. " too -- so this is not " .. ref .. ", or the map gave it an exit"
                .. " it does not have. Nothing was written.")
            cecho("red", "[map]   `map-print-room-slug` to find where you are, then"
                .. " `map-here <slug>` to carry on.")
            return
        end
    end

    if taPackage.currentRoomProvisional and not holding then
        taPackage.mapdbg("[mapdbg] reconcile: room=" .. tostring(taPackage.currentRoom)
            .. " id=" .. tostring(taPackage.currentRoomId)
            .. " dirs=" .. table.concat(dirs, ","))
        local match, coordVetoed, coordAgreed = taPackage.db.findRoomByFingerprint(
            taPackage.currentRoom, dirs, taPackage.currentRoomId, taPackage.coord,
            taPackage.currentAreaId)
        taPackage.mapdbg("[mapdbg] findRoomByFingerprint -> type=" .. type(match)
            .. " val=" .. tostring(match))
        -- Which matcher found it decides whether we trust it now or hold it for
        -- the next room to confirm. A fingerprint match is only strong when there
        -- was a coordinate to compare: findRoomByFingerprint SKIPS its coordinate
        -- veto when `coord` is nil, so with none it is just name plus exit-set --
        -- the weakest signal we have, and the one that has cost us rooms twice.
        -- After a Teleport there is no coordinate, so those matches get held.
        -- Both SIDES need one: a candidate with no stored coordinate also skips
        -- the veto, and checking only ours merged a new Flagstones corridor into
        -- the one coordless [ne,w] corridor in the area, rooms away
        -- (logs/session-pelayo-2026-10-04T22-15-15.log, line 164).
        local byCoord = type(match) == "number" and coordAgreed
        -- Set when the candidate is in another area: the echo says so, and a
        -- confirmed merge has to follow us into that area.
        local acrossSeam = false
        -- Coordinates drift across this world's non-Euclidean loops, so when the
        -- coordinate match misses, trust the door we walked through instead: the
        -- room we re-entered is the same-name, same-exit-set room whose exit back
        -- the way we came is still unexplored. Topology over 30-year-old grid math.
        if type(match) ~= "number" and taPackage.currentEntryDir then
            local back = REVERSE_DIR[taPackage.currentEntryDir]
            local tooMany
            match, tooMany = taPackage.db.findLoopClosure(
                taPackage.currentRoom, dirs, taPackage.currentRoomId, back,
                taPackage.currentAreaId, taPackage.coord)
            taPackage.mapdbg("[mapdbg] findLoopClosure back=" .. tostring(back)
                .. " -> type=" .. type(match) .. " val=" .. tostring(match))
            -- Several candidates and no way to choose: the room stays minted, which
            -- is right, but SAY so. Giving up quietly is how a duplicate appears
            -- with nothing in the log to notice -- desert-25 was minted as a copy
            -- of desert-7 that way, and only caught because someone was watching
            -- (logs/session-tojolias-2026-09-14T20-21-08.log).
            if tooMany then
                local ids = {}
                for _, id in ipairs(tooMany) do ids[#ids + 1] = "#" .. tostring(id) end
                echo("[map] #" .. tostring(taPackage.currentRoomId) .. " looks like "
                    .. #tooMany .. " rooms already mapped (" .. table.concat(ids, ", ")
                    .. ") and nothing separates them -- minted it as new."
                    .. " If it is one of them, merge it by hand.")
            end
            -- Still nothing, and the exit we walked was a frontier? Then we may
            -- have just crossed a Seam into an area that is already mapped, which
            -- neither matcher above can see: both search the current area. Two
            -- frontiers meeting is the evidence (see findSeamRoom), and the answer
            -- is held for the next move like any other topological match.
            if type(match) ~= "number" then
                local seam = taPackage.db.findSeamRoom(
                    taPackage.currentRoom, dirs, taPackage.currentRoomId, back,
                    taPackage.currentAreaId)
                taPackage.mapdbg("[mapdbg] findSeamRoom back=" .. tostring(back)
                    .. " -> type=" .. type(seam) .. " val=" .. tostring(seam))
                if type(seam) == "number" then
                    match = seam
                    acrossSeam = true
                end
            end
        end
        -- Nothing matched, and we are about to keep a freshly minted room -- but
        -- a room of this name and exit-set IS on the map and was rejected on its
        -- stored coordinate alone. Say so. These rooms never sat on a grid, so
        -- the reckoning drifts, and once it does findRoomByFingerprint is blind
        -- for good while findLoopClosure cannot cover for it (it needs the return
        -- door to be an unwalked stub, and in walked ground it never is). That
        -- combination re-walked the Complex of Natural Caverns into a parallel
        -- copy on 2026-09-19 with nothing in the log to notice until 81 rooms
        -- later. This line is what makes it noticeable on the FIRST one.
        if type(match) ~= "number" and coordVetoed and #coordVetoed > 0 then
            local parts = {}
            for _, v in ipairs(coordVetoed) do
                parts[#parts + 1] = (taPackage.db.roomRef(v.id) or ("#" .. tostring(v.id)))
                    .. string.format(" (%d,%d,%d)", v.coord.x, v.coord.y, v.coord.z)
            end
            -- Red, and still in the session log: baud's cecho used to draw
            -- without logging, which is why everything that matters here was
            -- written in plain echo. It logs now (baud, App.tsx), and this line
            -- has to be BOTH -- it is the one a walker must notice on screen, and
            -- the one whose false-alarm rate gets measured off the log afterwards.
            cecho("red", "[map] minting " .. (taPackage.db.roomRef(taPackage.currentRoomId)
                    or ("#" .. tostring(taPackage.currentRoomId)))
                .. ", but " .. #coordVetoed .. " room"
                .. (#coordVetoed > 1 and "s match" or " matches")
                .. " this name and exit-set and "
                .. (#coordVetoed > 1 and "were" or "was")
                .. " rejected on coordinates alone: " .. table.concat(parts, ", ")
                .. string.format(" vs reckoned (%d,%d,%d)",
                    taPackage.coord.x, taPackage.coord.y, taPackage.coord.z))
            cecho("red", "[map]   If this is that room, stop now and `map-here` it"
                .. " -- every room walked from here will be a duplicate too.")
        end
        -- Guard on a real numeric id: never concatenate/merge a js_null or nil.
        if type(match) == "number" then
            if byCoord then
                -- An exact coordinate match on top of name and exit-set. Nothing
                -- weak about that, so merge now.
                taPackage.db.mergeRoomInto(taPackage.currentRoomId, match)
                taPackage.currentRoomId = match
                -- Re-anchor dead-reckoning to the room we closed onto: its stored
                -- coordinate is consistent with its already-mapped neighbours,
                -- while the drifted provisional's was not. Without this the drift
                -- compounds into another duplicate on the next move.
                local snapped = taPackage.db.roomCoord(match)
                if snapped then taPackage.coord = snapped end
                echo("[map] linked into #" .. tostring(match) .. " (" .. tostring(taPackage.currentRoom) .. ")")
            else
                -- Topological only, so hold it for the next move to confirm. The
                -- room stays minted meanwhile: if the closure is refuted it was
                -- always a separate room, and if confirmed it folds in one move
                -- later at no cost.
                taPackage.pendingClosure = { from = taPackage.currentRoomId, into = match,
                                             seam = acrossSeam or nil }
                -- Name the moves that can settle it. Confirming asks the candidate
                -- what lies through the door we walk next, so only a direction it
                -- has already walked can answer -- and the obvious move, back the
                -- way we came, is often exactly the one it cannot.
                local settle = taPackage.db.walkedExits(match)
                echo("[map] " .. (acrossSeam and "possible Seam crossing into #"
                                  or "possible loop closure into #") .. tostring(match)
                    .. (acrossSeam and (" (" .. tostring(taPackage.db.areaSlugOf(match))
                                        .. ")") or "")
                    .. " -- settle it by walking " ..
                    (#settle > 0 and table.concat(settle, " or ")
                     or "on (that room has no walked exit, so nothing can confirm it yet)"))
            end
        end
        taPackage.currentRoomProvisional = false
    end

    for _, dir in ipairs(dirs) do
        taPackage.db.recordKnownExit(taPackage.currentRoomId, dir)
    end

    -- Guide exploration: flag which listed exits still lead somewhere unmapped.
    -- An exit is "mapped" once it has a walked destination; otherwise it's a stub
    -- we've never stepped through (including the ones we just seeded above, whose
    -- to_id is NULL). This is a [map] line, not [mapdbg] -- it's a real aid.
    local unexplored, mapped = {}, {}
    for _, dir in ipairs(dirs) do
        if taPackage.db.exitDestination(taPackage.currentRoomId, dir) then
            mapped[#mapped + 1] = dir
        else
            unexplored[#unexplored + 1] = dir
        end
    end
    if #unexplored > 0 then
        echo("[map] unexplored exits: " .. table.concat(unexplored, ", ")
            .. (#mapped > 0 and ("  (mapped: " .. table.concat(mapped, ", ") .. ")") or ""))
    else
        echo("[map] all exits mapped: " .. table.concat(mapped, ", "))
    end

    -- Remember where this character is now (settled room id, after any merge),
    -- so `just report` can mark "you are here". Needs the logged-in name.
    -- Mapping already resolved the room, merges included, so the tracker
    -- follows it rather than working it out a second time.
    taPackage.setHere(taPackage.currentRoomId)
end, { type = "regex" })

-- A rejected move: clear the pending direction so the next room line doesn't
-- record a phantom exit from the room we never actually left.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    -- Refused, so no arrival is coming for it. Drop it rather than leaving it
    -- to be matched against the next room we really do enter.
    taPackage.shiftPendingDir()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Passing through a locked door prints this just before the destination brief.
-- Stash the key/door; handleRoomEntry tags the crossed edge (and its reverse)
-- once it has linked them. Both are recorded lowercase to match room/dir slugs.
createTrigger("^Your (.+) key unlocks the (.+) door and allows you to pass through\\.$", function(matches)
    taPackage.pendingLock = { key = matches[2], door = matches[3] }
end, { type = "regex" })

-- A locked door we lack the key for turns us back, like a failed move. Record
-- the exit as a locked door (key unknown) so the map shows it, then clear the
-- pending direction so the reprinted room isn't mistaken for an arrival.
createTrigger("^The locked (.+) door prevents your exit in that direction\\.$", function(matches)
    -- Refused, so no arrival is coming: take the move off the queue and record
    -- the door against the direction it was actually refused in.
    local dir = taPackage.shiftPendingDir()
    if taPackage.mapping and taPackage.currentRoomId and dir then
        taPackage.db.setExitLock(taPackage.currentRoomId, dir, nil, matches[2])
    end
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Everything else that "prevents your exit": the mystical force at a misty
-- archway, the wide chasm. Refused, so take the move off the queue -- the ruined
-- mansion walk left it on, and every arrival after it was paired with the move
-- before (logs/session-teekywiki-2026-09-23T20-17-57.log, line 1692). A locked
-- door says the same thing but has its own trigger above, which already shifts;
-- shifting here as well would drop a move that is still coming.
createTrigger("^(.+) prevents your exit in that direction\\.$", function(matches)
    if matches[2]:match("^The locked ") then return end
    taPackage.shiftPendingDir()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Moving too quickly makes the character trip instead of moving — no room
-- change happens, but the game then reprints the current room. Clear the
-- pending direction so that reprint is treated as a re-scan of the room we're
-- still in, not an arrival through the exit we tried to take.
createTrigger("^In your haste, you trip and fall!$", function()
    taPackage.shiftPendingDir()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Trying to move while still resting is rejected outright — no room change. Like
-- the other rejected moves, clear the pending direction so a stale one can't be
-- dead-reckoned onto the next arrival (which would mint a phantom room in the
-- wrong direction). Separate from the arena-mode retry trigger elsewhere.
createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function()
    taPackage.shiftPendingDir()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Begin mapping from the room you're standing in. Clear any stale anchor so the
-- brief that follows is treated as a fresh arrival (not a walked edge), then a
-- bare return prints that brief, which handleRoomEntry captures (and auto-probes
-- its exits). Shared by map-area; map-here anchors precisely instead.
local function startMappingHere()
    taPackage.mapping = true
    taPackage.pendingClosure = nil
    taPackage.coordLost = nil
    taPackage.pendingDirs = {}
    taPackage.pendingDirection = nil
    taPackage.prevRoomId = nil
    taPackage.currentRoomId = nil
    taPackage.coord = nil
    send("")
end

-- Start mapping a (usually fresh) area from where you stand: `map-area caves`
-- or `map-area caves The Caves`. Ensures the area, tags it current so newly
-- discovered rooms inherit it, and begins mapping here — no separate command to
-- turn mapping on. To resume in an already-mapped area, use `map-here <slug>`
-- (which anchors at a known room); `map-area` cold-starts by name, so it's for
-- fresh areas or a uniquely-named entry room.
createAlias("^map-area (.+)$", function(matches)
    local arg = matches[2]
    local slug, name = arg:match("^(%S+)%s+(.+)$")
    if not slug then slug, name = arg:match("^(%S+)$"), nil end
    local areaId = taPackage.db.ensureArea(slug, name)
    -- If we're already anchored on a room (e.g. we ran `map-here <prev-area
    -- room>`, walked across a frontier into this fresh area, and stopped on the
    -- entry room), that entry room was discovered under the *previous* area's id
    -- — the frontier lived on a room of that area. Re-file the room we're
    -- standing in into the new area so the seam ends up split cleanly between
    -- the two areas. Do this before startMappingHere clears currentRoomId, so we
    -- move the room the session already knows we're in rather than re-resolving
    -- an ambiguous name.
    -- Re-file only a LIVE anchor. With mapping on, `anchored` is the room the
    -- mapper just walked into across the frontier and linked, so moving it is
    -- exactly what splits the Seam. With mapping OFF the anchor is a leftover
    -- from wherever mapping last stopped -- stopMapping does not clear it, and
    -- the character has been walked around by hand since -- so re-filing it
    -- drags a room we are nowhere near into the new area.
    local anchored = taPackage.currentRoomId
    local walkedIn = anchored ~= nil and taPackage.mapping
    if walkedIn then
        taPackage.db.setRoomArea(anchored, areaId)
        echo("[map] moved current room into " .. slug)
    end
    taPackage.currentAreaId = areaId
    echo("[map] mapping " .. slug .. " from here")
    -- An anchor held while MAPPING is live was earned: we walked here and the
    -- mapper linked the edge, so it knows the room id. Cold-starting over it
    -- would throw that away and re-resolve the room by name -- and where the
    -- names repeat, resolveColdStart's last resort is `ids[1]`, i.e. a coin toss
    -- among the 85 rooms called "stonework corridor". Crossing a Seam is exactly
    -- when that happens: walk `d` off Level 1's last corridor, run `map-area
    -- stoneworks-level-2`, and the cold start could anchor the walk on a Level 1
    -- room and write Level 2's exits onto it. So keep the anchor (and its coord,
    -- so dead reckoning carries across the Seam) and only turn mapping on.
    --
    -- With mapping OFF the anchor is stale -- the character has since been walked
    -- around by hand, and the id is whatever the last session left behind -- so
    -- there the bare return and a fresh resolve are the only honest option.
    if walkedIn then
        taPackage.pendingClosure = nil
        taPackage.coordLost = nil
        echo("[map] kept anchor #" .. tostring(anchored) .. " (walked in from "
            .. "the previous area)")
    else
        -- Scope the cold start that startMappingHere is about to trigger to this
        -- area, so a fresh one mints rather than adopting a same-named room in
        -- an area we are not standing in.
        taPackage.coldStartArea = areaId
        startMappingHere()
    end
end, { type = "regex" })

-- Resume mapping at a known room: `map-here cave-11`. Use this in an
-- already-mapped area — especially an ambiguously-named room (every cave is
-- "cave", so map-area's cold-start-by-name can't tell them apart). Turns
-- mapping on and anchors currentRoomId/coord/area from the named room's stored
-- row, without reprinting or re-resolving, so the next move dead-reckons from
-- the right place. Use the unique slug (shown in the report / `map-list-areas`).
createAlias("^map-here (.+)$", function(matches)
    local slug = matches[2]:match("^%s*(.-)%s*$")
    -- Accept the `area/room` form as well as the bare slug, because that is how
    -- the map prints a room everywhere else -- roomRef, the coverage report,
    -- live-navigate, and the duplicate warning, which ends "stop now and
    -- `map-here` it" and then names the room as `complex-caverns/...`. Copying
    -- that name back in answered "no room with slug", so the one command the
    -- warning exists to prompt was the one thing it made impossible. The walker
    -- gave up and ran map-off, and the duplicate is still in the map
    -- (logs/session-pelayo-2026-09-19T15-01-29.log, line 1274).
    slug = slug:match("[^/]+$") or slug
    local room = taPackage.db.roomBySlug(slug)
    if not room then
        echo("[map] no room with slug: " .. slug)
        return
    end
    taPackage.mapping = true
    taPackage.pendingClosure = nil
    taPackage.coordLost = nil
    taPackage.currentAreaId = room.area_id
    taPackage.currentRoomId = room.id
    taPackage.currentRoom = room.name
    taPackage.currentRoomProvisional = false
    taPackage.prevRoomId = nil
    taPackage.prevRoom = nil
    taPackage.pendingDirs = {}
    taPackage.pendingDirection = nil
    if room.x ~= nil then
        taPackage.coord = { x = room.x, y = room.y, z = room.z }
    else
        taPackage.coord = nil
    end
    -- An explicit statement of where we are, so the tracker takes it too.
    taPackage.setHere(room.id)
    -- Stamp location now so the report's "you are here" marker is right the
    -- moment you anchor, not only after the first move (map-here sends no ex).
    if taPackage.character.getName() then
        taPackage.db.setPlayerLocation(taPackage.character.getName(), room.id)
    end
    echo("[map] anchored at " .. slug .. " (#" .. tostring(room.id) .. ")"
        .. (taPackage.coord
            and (" coord=(" .. taPackage.coord.x .. "," .. taPackage.coord.y
                 .. "," .. taPackage.coord.z .. ")")
            or ""))
end, { type = "regex" })

-- Identify the room you're standing in without committing to it: re-reads the
-- room (bare return -> name, `ex` -> exit-set), consults the DB, and prints the
-- matching slug — or all candidates when name+exits are ambiguous — so you know
-- what to pass to `map-here`. Read-only; the capture happens in handleRoomEntry
-- and the Exits handler (both check taPackage.slugProbe).
createAlias("^map-print-room-slug$", function()
    taPackage.slugProbe = { name = nil }
    send("")
    send("ex")
end, { type = "regex" })

-- List every area slug we've mapped, one per line.
createAlias("^map-list-areas$", function()
    local areas = taPackage.db.listAreas()
    if #areas == 0 then
        echo("[map] no areas mapped yet")
        return
    end
    for _, a in ipairs(areas) do
        echo(a.slug)
    end
end, { type = "regex" })

-- Wipe one area so it can be re-walked from scratch (e.g. after a messy first
-- pass): `map-reset-area first-dungeon`. Leaves other areas intact and keeps the
-- area row, then forgets the mapping anchor so a now-deleted room can't be
-- re-linked from stale state — run `map-area <slug>` afterward to start re-mapping.
createAlias("^map-reset-area (.+)$", function(matches)
    local slug = matches[2]:match("^%s*(.-)%s*$")
    local areaId = taPackage.db.areaIdBySlug(slug)
    if not areaId then
        echo("[map] no such area: " .. slug)
        return
    end
    local removed = taPackage.db.resetArea(areaId)
    taPackage.currentRoomId = nil
    taPackage.prevRoomId = nil
    taPackage.pendingDirection = nil
    taPackage.coord = nil
    echo("[map] reset area " .. slug .. " (" .. tostring(removed)
        .. " rooms removed). Run map-area " .. slug .. " to re-map it.")
end, { type = "regex" })

-- Mapping mode. Off by default; while on, room lines are recorded, each arrival
-- auto-probes exits with `ex`, and provisional rooms are merged into known ones
-- by fingerprint. Turning it off leaves the graph untouched during normal play.
-- Mapping is turned ON by map-area (fresh area) or map-here (resume at a known
-- room); map-off stops it.
local function stopMapping()
    taPackage.mapping = false
    -- A held loop closure can only be settled by the next move, so stopping here
    -- leaves a duplicate. Say so plainly and say what resolves it: the cost of
    -- deferring is paid entirely by whoever closes a loop as their last act.
    local held = taPackage.pendingClosure
    if held and held.pairs and #held.pairs >= 2
        and taPackage.closureChainDistinguished(held) then
        -- It has agreed for a room or more; settle on that, as a turn back would.
        taPackage.pendingClosure = nil
        taPackage.settleClosure(held)
    end
    if taPackage.pendingClosure then
        echo("[map] a possible " .. (taPackage.pendingClosure.seam and "Seam crossing"
                                    or "loop closure")
            .. " into #" .. tostring(taPackage.pendingClosure.into)
            .. " is unresolved, so room #" .. tostring(taPackage.pendingClosure.from)
            .. " stays a duplicate. One more move before map-off would have settled it.")
        taPackage.pendingClosure = nil
    end
end
taPackage.stopMapping = stopMapping

-- `map-debug on` / `map-debug off`. Traces every room entry and every
-- fingerprint decision. Useful when a walk mis-links; unbearable otherwise.
-- One capture rather than `(on|off)`: Lua patterns have no alternation, and the
-- test helper converts these regexes to Lua patterns, so an alternation here
-- silently matches nothing under test.
createAlias("^map-debug (.+)$", function(matches)
    local arg = matches[2]
    if arg ~= "on" and arg ~= "off" then
        echo("[map] usage: map-debug on   or   map-debug off")
        return
    end
    taPackage.mapDebug = arg == "on"
    echo("[map] mapdbg tracing " .. (taPackage.mapDebug and "on" or "off"))
end, { type = "regex" })

-- `push stone` teleports (docs/hidden-stone-teleport.md): the game glues the
-- arrival onto the push, so no ordinary arrival brief fires and the tracker
-- would happily keep believing we never left. There is no edge in the map to
-- follow, so the honest result is `lost`.
-- `push stone` is overloaded: at [S2] it teleports, at [S1] it opens a seal four
-- rooms away and you do not move at all (docs/hidden-stone-teleport.md calls the
-- overloading a mechanic, not a one-off).
--
-- So there is nothing to decide when the command goes out, and deciding anyway
-- was wrong: an outbound trigger here used to declare the position lost on the
-- verb alone, which it did on 2026-09-13 while the character had not gone
-- anywhere. The game tells the two apart in its reply, so key off that.
--
-- Only the teleport needs handling. The game glues the arrival onto the tail of
-- the push line, so `^You're in ` never matches it and handleRoomEntry never
-- runs -- position becomes genuinely unknown, with no edge in the map to follow.
-- The remote reply ("As you push ... you feel the floor vibrate faintly") needs
-- no trigger at all: nothing about where we are has changed.
-- The game glues the arrival onto the tail of the push line, so the room trigger
-- anchored at `^You're in ` never matches it and the mapper used to miss the move
-- entirely: currentRoomId stayed on the stone, the following `ex` was
-- misattributed, and the destination got hung off it by a phantom compass edge.
-- Drive the arrival from here instead, flagged as a Teleport.
createTrigger("^You push the protruding stone into it's recess\\.\\.\\.You're in (.+)\\.$",
    function(matches)
        taPackage.arrivedByTeleport = true
        -- And every room walked from here has no grid position either, until one
        -- with a stored coordinate re-anchors us. Stamping (0,0,0) instead put a
        -- second origin inside the area and matched a third-town corridor.
        taPackage.coordLost = true
        -- Position is unknown to the tracker either way: the map holds no edge to
        -- follow, and the link lives on the device (devices.dest_room_id).
        if taPackage.hereState ~= "lost" then
            taPackage.loseHere("`push stone` moves you somewhere the map has no edge for")
        end
        handleRoomEntry(matches)
        taPackage.arrivedByTeleport = nil
    end, { type = "regex" })

-- Walking into the tower's [L] or the labyrinth's [T] prints its arrival brief,
-- then this, then the brief of where you land -- nothing is typed for it. Mark
-- the next brief as a Teleport from the room just entered; the brief handler
-- resolves it. (Anchored, so "X has just appeared in a puff of thick black
-- smoke!" about someone else arriving does not match.)
--
-- The labyrinth's Level 4 tunnel does the same with a flash instead of smoke:
-- walk `s` from the tunnel into "the entrance to a tunnel", and "A sudden flash
-- of light momentarily blinds you!" is followed by the riddle room's brief
-- (logs/session-teekywiki-2026-09-26T22-11-28.log, line 159).
for _, line in ipairs({
    { pattern = "^A cloud of thick black smoke suddenly engulfs you!$", what = "the smoke" },
    { pattern = "^A sudden flash of light momentarily blinds you!$", what = "the flash" },
}) do
    createTrigger(line.pattern, function()
        taPackage.pendingSmoke = {
            from = (taPackage.mapping and taPackage.currentRoomId) or taPackage.here,
            what = line.what,
        }
    end, { type = "regex" })
end

-- The right answer to a riddle can move you, and like `push stone` the game
-- glues the arrival onto the answer line, so `^You're in ` never sees it:
-- "As the answer passes your lips, your surroundings fade...You're in a tunnel."
-- (logs/session-teekywiki-2026-09-26T22-11-28.log, line 137, the labyrinth's
-- Level 4 riddle). Unhandled, the mapper stayed on the riddle room, and the
-- `map-area tunnels` that followed re-filed the riddle room into the new area.
-- It is a Teleport from the room the answer was spoken in; a `teleport` Device
-- there, worked by a command, says where it lands.
createTrigger("^As the answer passes your lips, your surroundings fade\\.\\.\\.You're in (.+)\\.$",
    function(matches)
        taPackage.pendingSmoke = {
            from = (taPackage.mapping and taPackage.currentRoomId) or taPackage.here,
            what = "the riddle's answer",
            lookup = taPackage.db.teleportByCommand,
        }
        handleRoomEntryUnlessLooking(matches)
    end, { type = "regex" })

-- The labyrinth's Level 3 springboards ([A], [B], [C]) throw you up into Level 2
-- the moment you walk in, and Level 2 is dark: what follows is "It's too dark to
-- see.", never a room brief. (One whose landing room is known is handled first.) So there is no arrival to resolve and nothing to map
-- from. Say so, stop mapping, and drop the moves already typed -- in the dark they
-- would wait for a brief that never comes and then be matched against the first
-- lit room reached. Each springboard is also a Device, '(on entry)' teleport with
-- no destination yet, so the `[device]` line warns before it fires.
createTrigger("^A spring loaded pressure plate rapidly lifts you through the ceiling!$", function()
    -- Level 5's springboards land on Level 3, which is lit and mapped. Where the
    -- springboard's Device names its landing room, it is a Teleport like the smoke:
    -- the brief that follows is resolved to that room, and mapping carries on.
    local from = (taPackage.mapping and taPackage.currentRoomId) or taPackage.here
    if from and taPackage.db.teleportOnEntry(from) then
        taPackage.pendingSmoke = { from = from }
        return
    end
    taPackage.pendingDirs = {}
    taPackage.pendingDirection = nil
    taPackage.pendingSmoke = nil
    if taPackage.mapping then
        stopMapping()
        cecho("red", "[map] mapping OFF: a springboard threw you up through the ceiling, into"
            .. " the dark level above. `map-here <slug>` once you can see where you are.")
    end
    if taPackage.hereState ~= "lost" then
        taPackage.loseHere("a springboard threw you up through the ceiling")
    end
end, { type = "regex" })

-- `where` -- what the tracker currently believes, and why. Deliberately says
-- "lost" rather than a best guess: a wrong answer here is worse than none.
createAlias("^where$", function()
    if taPackage.hereState == "known" and taPackage.here then
        local ref = taPackage.db.roomRef(taPackage.here)
        local name = taPackage.db.roomName(taPackage.here)
        echo("[where] " .. tostring(ref) .. "  (" .. tostring(name) .. ")")
    elseif taPackage.hereState == "off-map" and taPackage.offMap then
        local o = taPackage.offMap
        echo("[where] off the map — " .. o.moves .. " move(s) past "
            .. tostring(taPackage.db.roomRef(o.from)) .. " going " .. o.dir)
    else
        echo("[where] lost — no position. `map-print-room-slug` to re-acquire,"
            .. " or `map-here <slug>` if you know where you are.")
    end
end, { type = "regex" })

createAlias("^map-off$", function()
    stopMapping()
    echo("[map] mapping OFF")
end, { type = "regex" })
