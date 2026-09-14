-- Stoneworks level 2, walked in three sessions on 2026-09-13, from the stairs
-- down to the last room of the level.
--
-- This is the fixture for what the level 1 walks could not pin down:
--
--   * a Seam crossed while mapping. `map-here` the last room of level 1, walk
--     `d`, then `map-area stoneworks-level-2` -- which re-files the room you
--     landed on and, since 8399ddb, KEEPS the anchor instead of re-resolving it
--     by name. Re-resolving is a coin toss where names repeat -- 85 rooms are
--     called "stonework corridor" and levels 3 to 6 will add more -- and the
--     losing outcome is level 2's exits written onto a level 1 room.
--   * a loop closure CONFIRMED. Every earlier fixture only shows one refused;
--     deferred confirmation had never been pinned doing the other half. This
--     walk closes the middle column and the merge folds TWO provisionals -- the
--     room the closure was held on, and the room minted after it while the
--     closure was still open -- into rooms walked two sessions earlier.
--   * a trap sprung, and recorded, by walking into it (shrine [T2]).
--   * a Seal that shows in the prose. Shrine [@]: `ex` lists `n`, the move is
--     refused, and the description says "The visible exit is southwest" -- so
--     this room's Description tracks Device State, unlike level 1's [D1], which
--     reads identically either way.
--
-- The assertions are what map/shrine/stoneworks-2.txt says, which is also what
-- `just coverage stoneworks-level-2` compares against: 40 rooms, and the only
-- unwalked exit left is the staircase down to level 3.

local replay = dofile("test/log_replay.lua")

local LOGS = {
    "logs/session-tojolias-2026-09-13T19-34-24.log",  -- down the stairs, into [T2]
    "logs/session-tojolias-2026-09-13T19-46-09.log",  -- out to [L2], pull lever
    "logs/session-tojolias-2026-09-13T19-57-35.log",  -- the loop, `say arok`, [v]
}

-- What level 1 hands to this walk. See `opts.seed` in test/log_replay.lua for
-- why it is stated rather than replayed: the level 1 chain is ten logs long and
-- asserts nothing about level 2.
--
-- `stonework-corridor-45` is the room the stairs come down from, with the
-- exit-set the log's first `ex` prints (`w,d`) and no coordinates -- which is why
-- the room below it starts a fresh (0,0,0) rather than continuing level 1's
-- reckoning. Its `d` is a Stub, so the first move of the walk has a frontier to
-- cross; `w` is walked, so the fixture starts reciprocal.
--
-- The other rows exist only to hold slug numbers. Level 1 had 50 rooms called
-- "stonework corridor" (stonework-corridor, -1 .. -49) and 5 called "stonework
-- chamber", so level 2's first mints are -50 and chamber-5 -- the names the
-- later logs' `map-here` lines use. They also make resolution by name genuinely
-- ambiguous, which is the situation the kept anchor exists for.
local function seedLevel1()
    local AREA = "(SELECT id FROM areas WHERE slug = 'stoneworks-level-1')"
    local ROOM = "(SELECT id FROM rooms WHERE slug = '%s')"
    local sql = {
        "INSERT INTO areas (slug, name) VALUES ('stoneworks-level-1',"
            .. " 'The Stoneworks, Level 1')",
    }
    local function room(slug, name)
        sql[#sql + 1] = "INSERT INTO rooms (slug, name, area_id) VALUES ('"
            .. slug .. "', '" .. name .. "', " .. AREA .. ")"
    end
    room("stonework-corridor", "stonework corridor")
    for i = 1, 49 do room("stonework-corridor-" .. i, "stonework corridor") end
    room("stonework-chamber", "stonework chamber")
    for i = 1, 4 do room("stonework-chamber-" .. i, "stonework chamber") end
    -- The Seam room's own exits: a walked `w` (with its reverse, so the fixture
    -- has no one-way edge before the walk begins) and the `d` Stub.
    sql[#sql + 1] = "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
        .. ROOM:format("stonework-corridor-45") .. ", 'w', "
        .. ROOM:format("stonework-corridor-46") .. ")"
    sql[#sql + 1] = "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
        .. ROOM:format("stonework-corridor-46") .. ", 'e', "
        .. ROOM:format("stonework-corridor-45") .. ")"
    sql[#sql + 1] = "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
        .. ROOM:format("stonework-corridor-45") .. ", 'd', NULL)"
    return sql
end

describe("Stoneworks level 2", function()

    local g

    -- Follow `dirs` from a room, so the graph is walked the way the session
    -- walked it. Slugs are deliberately not used past the Seam: they are a
    -- function of mint order, and what the test means is "the room three moves
    -- that way", which survives a renumbering.
    -- Read the graph once. g.rooms() is a query per room against a real sqlite3
    -- process, so calling it inside a walk is what makes a spec take minutes.
    local byId, bySlugIndex
    local function index()
        if not byId then
            byId, bySlugIndex = {}, {}
            for _, r in ipairs(g.rooms()) do
                byId[r.id] = r
                bySlugIndex[r.slug] = r
            end
        end
    end

    local function follow(room, dirs)
        index()
        for dir in dirs:gmatch("%S+") do
            local id = room.exits[dir]
            assert.is_truthy(id, "no walked exit " .. dir .. " from " .. room.slug)
            local nxt = byId[id]
            assert.is_truthy(nxt, dir .. " from " .. room.slug .. " leads to a room that is gone")
            room = nxt
        end
        return room
    end

    local function bySlug(slug)
        index()
        return bySlugIndex[slug]
    end

    -- The room the stairs down from level 1 land on: where every walk below starts.
    local function entryRoom()
        return follow(assert(bySlug("stonework-corridor-45")), "d")
    end

    -- Rooms of level 2 only: the seeded level 1 rows share the database.
    local function level2Count()
        return g.db.one("SELECT COUNT(*) AS n FROM rooms WHERE area_id ="
            .. " (SELECT id FROM areas WHERE slug = 'stoneworks-level-2')").n
    end

    setup(function()
        g = replay.replayChain(LOGS, { seed = seedLevel1() })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the Seam with level 1", function()

        it("fills the stairs Stub and links both ways across it", function()
            local up = assert(bySlug("stonework-corridor-45"))
            local entry = follow(up, "d")
            assert.are.equal("stonework chamber", entry.name)
            assert.are.equal(up.id, entry.exits.u)
        end)

        it("leaves each end of the Seam in its own Area", function()
            -- The room you land on is discovered under level 1's area id -- the
            -- frontier lived on a level 1 room -- and map-area re-files it. Get
            -- this wrong and level 2 is one room short for the rest of time.
            local area = function(slug)
                return g.db.one("SELECT a.slug AS s FROM rooms r JOIN areas a"
                    .. " ON a.id = r.area_id WHERE r.slug = '" .. slug .. "'").s
            end
            assert.are.equal("stoneworks-level-1", area("stonework-corridor-45"))
            assert.are.equal("stoneworks-level-2", area(entryRoom().slug))
        end)

        it("does not write level 2 onto a level 1 room", function()
            -- The cold start map-area used to do resolved by NAME, and with 55
            -- rooms called "stonework corridor"/"stonework chamber" seeded here
            -- its last resort -- the first id that matches -- is a coin toss.
            -- Every seeded room must still be exitless bar the Seam room.
            local touched = {}
            for _, e in ipairs(g.db.rows(
                "SELECT DISTINCT r.slug AS slug FROM room_exits e"
                .. " JOIN rooms r ON r.id = e.from_id"
                .. " JOIN areas a ON a.id = r.area_id"
                .. " WHERE a.slug = 'stoneworks-level-1' ORDER BY r.slug")) do
                touched[#touched + 1] = e.slug
            end
            assert.are.same({ "stonework-corridor-45", "stonework-corridor-46" }, touched)
        end)
    end)

    describe("the level as a whole", function()

        it("holds the drawing's 40 rooms and no more", function()
            -- 40 boxes in map/shrine/stoneworks-2.txt. 41 or 42 would mean the
            -- confirmed closure merged one provisional, or neither.
            assert.are.equal(40, level2Count())
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("records no exit a corridor's own description denies, bar the stairs",
            function()
            -- One exception, and the prose is the thing that is odd, not our
            -- edges: the last room says "The corridor continues to the south."
            -- and then gives the stairs a sentence of their own, "There is a
            -- stone staircase here leading downward." So `d` is never in the list
            -- corridorMismatches() reads -- exactly as in stonework-corridor-45
            -- on level 1, the room these logs come down from. Stated exactly
            -- rather than excluded, so a SECOND mismatch still fails the test.
            local bad = g.corridorMismatches()
            assert.are.equal(1, #bad, table.concat(bad, "; "))
            assert.is_truthy(bad[1]:find("prose says s, edges say d,s", 1, true))
            -- ... and the check really looked at this level, rather than passing
            -- because no description matched its pattern.
            assert.is_true(g.corridorsChecked() >= 30)
        end)

        it("leaves one Stub: the stairs down to level 3", function()
            -- The level's other way out is walked, not a Stub -- the stairs up
            -- were crossed to get here -- so a complete level leaves exactly one
            -- unwalked exit, and it is the one nobody has been down. Anything
            -- else unwalked means a room of this level was never reached.
            local stubs = g.stubs()
            assert.are.equal(1, #stubs, "stubs: " .. table.concat(stubs, ", "))
            assert.are.equal("d", stubs[1]:match("(%S+)$"))
            local last = follow(entryRoom(),
                "w sw w nw n nw ne ne e ne n n")   -- the way the last session went
            assert.are.equal("d,s", g.exitSet(last.id))
            assert.are.equal(tostring(last.id), stubs[1]:match("^(%d+)"))
        end)

        it("leaves no move queued at the end", function()
            assert.are.same({}, g.pendingDirs())
        end)
    end)

    describe("the loop closure", function()

        it("confirms exactly one closure, and refuses none", function()
            -- The echoes are the LAST log's only, which is the session that
            -- closed the loop. The two candidates raised into the trap room in
            -- the earlier sessions were refused there, not here.
            assert.are.equal(1, #g.echoesMatching("loop closure confirmed"))
            assert.are.equal(0, #g.echoesMatching("refused"))
        end)

        it("wires the closed loop into rooms walked two sessions earlier", function()
            -- The closure is held on arrival in the room the middle column joins,
            -- and settled by the NEXT move -- which is why the room minted in
            -- between has to merge too. Walking on from the far side lands in the
            -- trap room, which was walked in the first of the three sessions.
            local joined = follow(entryRoom(), "w sw w")    -- the loop's east end
            assert.are.equal("e,nw,sw", g.exitSet(joined.id))
            local trapRoom = follow(joined, "nw n nw ne")
            assert.are.equal("falling rocks", trapRoom.trap)
        end)

        it("reaches the same room by both ways round", function()
            -- What a loop IS: two paths from one room to another. Before the
            -- merge these ended in two different rooms, which is the bug the
            -- deferred closure exists to avoid.
            local joined = follow(entryRoom(), "w sw w")
            local viaColumn = follow(joined, "sw w s s")
            local viaLevel = follow(joined, "nw n nw nw w sw s sw sw s se ne e se e")
            assert.are.equal(viaColumn.id, viaLevel.id)
            assert.are.equal("e,n,w", g.exitSet(viaColumn.id))
        end)
    end)

    describe("the Devices the walk found", function()

        it("records the trap by springing it", function()
            -- Nothing was typed to record this: walking in printed "Several large
            -- stones fall on you from above!" and handleTrap tagged the room.
            local trapped = g.db.rows("SELECT slug, trap FROM rooms WHERE trap IS NOT NULL")
            assert.are.equal(1, #trapped)
            assert.are.equal("falling rocks", trapped[1].trap)
        end)

        it("keeps the Sealed exit, which `ex` lists even while it is shut", function()
            -- Shrine [@]. The walk was refused `n` twice, said arok, and went
            -- north -- so the edge exists, and the two refusals wrote nothing:
            -- no phantom room (the 40 above) and no edge in a direction the
            -- server would not let us move.
            local seal = follow(entryRoom(), "w sw w nw n nw ne ne e ne")
            assert.are.equal("n,sw", g.exitSet(seal.id))
            assert.is_truthy(seal.exits.n, "the wall was opened and walked through")
        end)

        it("keeps a Description that tracks Device State, not the exit-set", function()
            -- The prose says the exit is southwest, singular, while `ex` says
            -- `n,sw`: the Seal is legible in this room's description, so what is
            -- stored is a fact about the Reset it was read in. This is why
            -- chambers are exempt from corridorMismatches().
            local seal = follow(entryRoom(), "w sw w nw n nw ne ne e ne")
            assert.is_truthy(seal.description:find("The visible exit is southwest", 1, true))
            assert.is_truthy(seal.description:find("guardian of the white rune", 1, true))
        end)
    end)
end)
