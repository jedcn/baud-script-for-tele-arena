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
-- The expectations are taken from map/shrine/stoneworks-1.txt, checked against
-- the walk move by move before being frozen.
--
-- They were the SPECIFICATION for a fix rather than a description of one, and
-- failed for two days while a second group asserted the buggy behaviour instead
-- (which is what proved the harness reproduced the live session faithfully). The
-- fix landed on 2026-09-13: findLoopClosure now refuses a candidate whose stored
-- Description differs from the one just captured. Both groups collapsed into this
-- one when it did.

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

    -- These were two groups until the mapper was fixed. One asserted the walk
    -- reproduced the live session BUG AND ALL, which is what proved the harness
    -- faithful; the other stated what the graph should be, and failed. The fix
    -- (a description check in findLoopClosure) flipped them, so the
    -- characterisation half has done its job and is gone.
    describe("builds a correct graph", function()

        it("mints one room per room walked: 25, not 23", function()
            -- Before the fix this was 23. Two rooms were lost to a single false
            -- closure: one merged away, and one never minted at all because the
            -- mapper then followed an edge it thought it already had.
            assert.are.equal(25, g.roomCount())
        end)

        it("closes no loop, because the walk never returns anywhere", function()
            assert.are.equal(0, #g.echoesMatching("linked into"))
        end)

        it("never records an exit a room's own description denies", function()
            assert.are.same({}, g.corridorMismatches())
        end)

        it("leaves the entry chamber's north exit an unwalked stub", function()
            -- The desert Crossing, never walked. Before the fix the merge had
            -- filled it with a corridor -- and that stub being empty is exactly
            -- what made the chamber eligible for the false closure.
            local entry = roomBySlug(g, "stonework-chamber")
            assert.is_false(entry.exits.n, "north should be an unwalked stub")
        end)

        it("keeps the two chambers with exits n,e,s apart", function()
            -- The drawing has two: [@] at the desert door, and the box five moves
            -- south of it. Their descriptions are nothing alike -- one carries the
            -- cryptic message, the other says "The only visible exits are north,
            -- south, and east" -- which is the evidence the fix consults.
            local chambers = {}
            for _, r in ipairs(g.rooms()) do
                if r.name == "stonework chamber" and g.exitSet(r.id) == "e,n,s" then
                    chambers[#chambers + 1] = r
                end
            end
            assert.are.equal(2, #chambers)
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("leaves 6 stubs on the frontier", function()
            -- Four the buggy run also had, plus two the merge had hidden: the
            -- swallowed chamber's east exit, and the entry chamber's north --
            -- restoring the desert Crossing restores a frontier with it.
            assert.are.equal(6, #g.stubs())
        end)
    end)
end)
