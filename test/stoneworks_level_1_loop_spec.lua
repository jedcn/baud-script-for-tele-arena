-- Stoneworks level 1, session five: a loop, walked deliberately to see what the
-- mapper does with one.
--
-- This is the most valuable fixture in the suite, because it contains BOTH kinds
-- of loop closure in one walk:
--
--   move 7  a FALSE closure. The new corridor's name and exit-set matched
--           stonework-corridor-7, whose return door happened to be an unwalked
--           stub -- so findLoopClosure merged them and destroyed a room.
--   move 10 a TRUE closure, back into the chamber the walk set out from.
--
-- Which is what makes it decisive rather than just another bug report. Every
-- signal that might separate the two says the same thing about both:
--
--   coordinates  the false match was one diagonal off (reckoned (3,-6), candidate
--                at (4,-5)); the true one was one diagonal off the other way
--                (reckoned (1,-6), candidate at (0,-5)). A drift tolerance loose
--                enough to allow the real closure allows the bad one. This is
--                structural: a real closure IS a coordinate disagreement, which
--                is the whole reason the fallback exists.
--   description  both are corridors, and a corridor's prose names only its exits,
--                so two corridors with the same exit-set read word for word alike.
--                The check that caught the 2026-09-11 merge cannot see this one.
--
-- What DOES separate them is the next move. Believing it stood in
-- stonework-corridor-6, the walk arrived somewhere whose `ex` answered ne,se,w
-- where that room was recorded as ne,sw -- a flat contradiction, one move after
-- the merge, which the mapper ignored and papered over by grafting the two new
-- exits on. Hence deferred confirmation: hold a candidate closure, and let the
-- next arrival confirm or refute it.
--
-- The assertions below are what a correct mapper produces, taken from
-- map/shrine/stoneworks-1.txt.

local replay = dofile("test/log_replay.lua")

local LOGS = {
    "logs/focused-session-tojolias-2026-09-11T21-24-54.log",  -- the outer edge
    "logs/session-tojolias-2026-09-12T10-18-42.log",          -- resume, cross a frontier
    "logs/session-tojolias-2026-09-12T10-37-22.log",          -- the shut door
    "logs/session-tojolias-2026-09-13T11-59-10.log",          -- say komi, walk east
    "logs/session-tojolias-2026-09-13T14-52-50.log",          -- this loop
}

-- Only the first log predates baud recording aliases.
local SETUP = { { "map-area stoneworks-level-1 The Stoneworks, Level 1" } }

-- Anchors named by a slug that no longer means the same room: a slug is a
-- function of mint order, and the 2026-09-13 fix made the first session mint two
-- rooms it had been losing.
local ANCHORS = {
    ["map-here stonework-corridor-20"] = "map-here stonework-corridor-21",  -- [S2]
    ["map-here stonework-corridor-24"] = "map-here stonework-corridor-25",  -- [!]
}

-- The loop, and what the drawing says each arrival's exit-set is. Asserted by
-- following the graph rather than by slug, because slugs move when mint order
-- does and these do not.
local LOOP = {
    { dir = "e",  exits = "se,w" },      -- already mapped: the komi session walked it
    { dir = "se", exits = "nw,se" },
    { dir = "se", exits = "nw,se" },
    { dir = "se", exits = "nw,sw" },
    { dir = "sw", exits = "ne,sw" },
    { dir = "sw", exits = "ne,se" },
    { dir = "se", exits = "e,nw,sw" },   -- move 7: the false closure happened here
    { dir = "sw", exits = "ne,se,w" },   -- move 8: and this arrival refutes it
    { dir = "w",  exits = "e,w" },
    { dir = "w",  exits = "e,n,s" },     -- move 10: the true closure
}

local function roomBySlug(g, slug)
    for _, r in ipairs(g.rooms()) do
        if r.slug == slug then return r end
    end
    return nil
end

describe("Stoneworks level 1 — walking a loop", function()

    local g

    setup(function()
        g = replay.replayChain(LOGS, { setup = SETUP, rewrite = ANCHORS })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the log itself", function()

        it("walks ten moves out and back", function()
            -- The log opens with the walk TO the riddle chamber -- a `w`, a kill,
            -- then e,s,s,s,n while working out where it was. The loop is the last
            -- ten moves, after `map-here`.
            local all = replay.movesIn(LOGS[5])
            local tail = {}
            for i = #all - 9, #all do tail[#tail + 1] = all[i] end
            local dirs = {}
            for _, step in ipairs(LOOP) do dirs[#dirs + 1] = step.dir end
            assert.are.same(dirs, tail)
        end)
    end)

    describe("the graph after all five sessions", function()

        it("holds 39 rooms: 30 before, 8 new, and one deliberate duplicate", function()
            -- 38 would be right if the closure at move 10 could be confirmed. It
            -- cannot: confirming needs the NEXT arrival, and the walk stopped
            -- there. So the last room stays minted as a duplicate of the chamber
            -- the loop returns to, which is the cost of deferring -- paid only by
            -- whoever closes a loop as their final move, and recoverable, where a
            -- wrong merge is not.
            assert.are.equal(39, g.roomCount())
        end)

        it("merges nothing on the strength of topology alone", function()
            -- Two candidate closures were raised, the false one at move 7 and the
            -- true one at move 10, and neither is merged on the spot. The first is
            -- refuted by the room after it; the second is never settled because
            -- the walk ends.
            assert.are.equal(0, #g.echoesMatching("linked into"))
            assert.are.equal(2, #g.echoesMatching("possible loop closure"))
        end)

        it("refutes the false closure using the room after it", function()
            local refused = g.echoesMatching("refused")
            assert.are.equal(1, #refused)
            assert.is_truthy(refused[1]:find("not what it predicted", 1, true))
        end)

        it("leaves the second closure unsettled rather than guessing", function()
            -- Two raised, one refuted, none confirmed. The second is never
            -- settled because this session ends without even a map-off -- the walk
            -- simply stops -- so there is no next arrival and nothing to check
            -- against. Silence is the correct outcome: the alternative is to
            -- assume, which is the bug this replaced.
            assert.are.equal(0, #g.echoesMatching("confirmed"))
        end)

        it("records no exit any room's own description denies", function()
            -- The conflation shows up here: the room the walk was wrongly told it
            -- stood in gains exits its prose does not mention.
            assert.are.same({}, g.corridorMismatches())
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)
    end)

    describe("the loop itself", function()

        it("gives every arrival the exit-set the shrine drawing has", function()
            local at = assert(roomBySlug(g, "stonework-chamber"))
            for i, step in ipairs(LOOP) do
                local nextId = at.exits[step.dir]
                assert.is_truthy(nextId,
                    "move " .. i .. " (" .. step.dir .. ") leads nowhere from "
                    .. at.slug)
                local nxt
                for _, r in ipairs(g.rooms()) do if r.id == nextId then nxt = r end end
                assert.is_truthy(nxt, "move " .. i .. " lands on a room that is gone")
                assert.are.equal(step.exits, g.exitSet(nxt.id),
                    "move " .. i .. " (" .. step.dir .. ") into " .. nxt.slug)
                at = nxt
            end
        end)

        it("ends on a room indistinguishable from the one the column reaches",
            function()
            -- Not the SAME room, because the closure was never confirmed. But the
            -- duplicate is recognisable as one: same name, same exit-set, which is
            -- what lets it be merged deliberately later.
            -- Follow the OTHER way round -- down the left column from the riddle
            -- chamber -- and the two paths must meet at the same room.
            local viaLoop = assert(roomBySlug(g, "stonework-chamber"))
            for _, step in ipairs(LOOP) do
                local id = viaLoop.exits[step.dir]
                for _, r in ipairs(g.rooms()) do if r.id == id then viaLoop = r end end
            end
            local viaColumn = assert(roomBySlug(g, "stonework-chamber"))
            for _, dir in ipairs({ "s", "s", "se", "sw", "s" }) do
                local id = viaColumn.exits[dir]
                for _, r in ipairs(g.rooms()) do if r.id == id then viaColumn = r end end
            end
            assert.are.equal(viaColumn.name, viaLoop.name)
            assert.are.equal(g.exitSet(viaColumn.id), g.exitSet(viaLoop.id))
        end)

        it("keeps move 7's room and the room it nearly merged with apart",
            function()
                -- The two are indistinguishable to every check the mapper had:
                -- same name, same exit-set. Both must still exist, which is what
                -- says the merge did not happen. Found by the echo rather than by
                -- slug, since slugs move whenever mint order does.
                local raised = g.echoesMatching("possible loop closure")
                local candidateId = tonumber(raised[1]:match("#(%d+)"))
                local candidate
                for _, r in ipairs(g.rooms()) do
                    if r.id == candidateId then candidate = r end
                end
                assert.is_truthy(candidate, "the refused candidate should still exist")

                -- Walk to move 7's room the way the log did.
                local at = assert(roomBySlug(g, "stonework-chamber"))
                for i = 1, 7 do
                    local id = at.exits[LOOP[i].dir]
                    for _, r in ipairs(g.rooms()) do if r.id == id then at = r end end
                end
                assert.are_not.equal(candidate.id, at.id,
                    "move 7's room must not be the candidate")
                assert.are.equal(candidate.name, at.name)
                assert.are.equal(g.exitSet(candidate.id), g.exitSet(at.id))
            end)
    end)
end)
