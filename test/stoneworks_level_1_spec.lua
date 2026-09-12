-- Log-driven mapper tests for the Stoneworks, Level 1.
--
-- This level was chosen because it is the hard case in one place: it has loops,
-- it has dead-reckoning drift (three edges in map/shrine/stoneworks-1.txt cannot
-- be satisfied by any grid assignment), ~50 rooms, and every one of them is
-- called "stonework chamber" or "stonework corridor". A mapper that gets this
-- level right is not going to be embarrassed by anywhere else.
--
-- Each test replays a real session log and asserts on the GRAPH that came out,
-- not on the SQL that built it. Adding a case means walking somewhere, saving
-- the log, and stating what should be in the database afterwards.
--
-- Two groups below, and the difference matters:
--
--   "reproduces the session"  Characterisation. These lock the harness down by
--                            asserting the replay matches what the live run
--                            actually produced -- bug and all. If one of these
--                            breaks, the harness has drifted from reality and
--                            nothing else here can be trusted.
--
--   "builds a correct graph"  The real expectations, taken from the shrine
--                             drawing. THESE FAIL TODAY. That is the point of
--                             the suite: they are the specification for the
--                             mapper fix, not a description of it.

local replay = dofile("test/log_replay.lua")

local OUTER = "logs/focused-session-tojolias-2026-09-11T21-24-54.log"
-- Per-log, because a chain needs one list each. This log predates baud
-- logging aliases, so its `map-area` has to be supplied.
local SETUP = { { "map-area stoneworks-level-1 The Stoneworks, Level 1" } }

-- The walk is 24 moves along the outer edge from [@], confirmed move-for-move
-- against map/shrine/stoneworks-1.txt: every arrival's exit-set matches the box
-- the drawing puts it on, including [T1] at move 12, [D1] at 16 and [S2] at 24.
local OUTER_MOVES = { "s", "s", "se", "sw", "s", "s", "se", "e", "ne", "ne",
                      "e", "se", "s", "sw", "sw", "s", "e", "e", "e", "e",
                      "s", "se", "e", "se" }

local function roomBySlug(g, slug)
    for _, r in ipairs(g.rooms()) do
        if r.slug == slug then return r end
    end
    return nil
end

describe("Stoneworks level 1 — outer-edge walk", function()

    local g

    setup(function()
        g = replay.replay(OUTER, { setup = SETUP })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the log itself", function()

        it("sends the 24 outer-edge moves, in order", function()
            -- 25 moves in the log: it opens with the `s` that carries you in
            -- from the desert, across a Crossing that was never mapped. The
            -- mapping walk is everything after it.
            local moves = replay.movesIn(OUTER)
            assert.are.equal(25, #moves)
            assert.are.equal("s", moves[1])
            local walk = {}
            for i = 2, #moves do walk[#walk + 1] = moves[i] end
            assert.are.same(OUTER_MOVES, walk)
        end)

        it("captures a description for every room it minted", function()
            for _, r in ipairs(g.rooms()) do
                assert.is_truthy(r.description, "no description on " .. r.slug)
            end
        end)
    end)

    describe("reproduces the session (characterisation — bug and all)", function()

        it("mints 23 rooms for a 25-room walk", function()
            assert.are.equal(23, g.roomCount())
        end)

        it("closes a loop that was never walked, exactly once", function()
            assert.are.equal(1, #g.echoesMatching("linked into"))
        end)

        it("leaves every edge reciprocal despite that", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("leaves 4 stubs on the frontier", function()
            assert.are.equal(4, #g.stubs())
        end)

        it("gives the entry chamber a north edge into a corridor, not the desert",
            function()
                -- The bug, stated plainly. 1087's own description ends "There is
                -- also a stone archway leading out into the desert to the
                -- north", so this edge is the merge overwriting the Crossing.
                local entry = roomBySlug(g, "stonework-chamber")
                local north = entry.exits.n
                assert.is_truthy(north)
                assert.are.equal("stonework corridor",
                    g.db.one("SELECT name FROM rooms WHERE id = " .. north).name)
            end)
    end)

    describe("builds a correct graph (the specification — FAILS TODAY)", function()

        it("mints one room per room walked: 25, not 23", function()
            assert.are.equal(25, g.roomCount())
        end)

        it("never records an exit a room's own description denies", function()
            assert.are.same({}, g.corridorMismatches())
        end)

        it("leaves the entry chamber's north exit an unwalked stub", function()
            -- The Crossing back to the desert was never walked, so `n` must
            -- still be a Stub. It being anything else is what made this chamber
            -- eligible for a false closure in the first place.
            local entry = roomBySlug(g, "stonework-chamber")
            assert.is_false(entry.exits.n, "north should be an unwalked stub")
        end)

        it("keeps the two chambers with exits n,e,s apart", function()
            -- The drawing has two: [@] at the desert door, and the box five
            -- moves south of it. They differ in description -- one carries the
            -- cryptic message, the other says "The only visible exits are
            -- north, south, and east".
            local chambers = {}
            for _, r in ipairs(g.rooms()) do
                if r.name == "stonework chamber" and g.exitSet(r.id) == "e,n,s" then
                    chambers[#chambers + 1] = r
                end
            end
            assert.are.equal(2, #chambers)
        end)

        it("leaves 5 stubs on the frontier, not 4", function()
            -- The four it has, plus the east exit of the chamber that the merge
            -- swallowed. These five are where the remaining ~26 rooms hang.
            assert.are.equal(5, #g.stubs())
        end)
    end)
end)
