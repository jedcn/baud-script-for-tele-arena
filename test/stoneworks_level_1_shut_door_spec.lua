-- Stoneworks level 1, session three: the game lists an exit and then refuses to
-- let you through it.
--
-- Walking back from [!] to [D1] and then trying `n`, the game answered:
--
--     Exits: n,e.
--     > n
--     Sorry, there's no exit in that direction.
--
-- Both are true at once. `[D1]` is a Door the shrine legend says is opened by
-- pushing the stone at `[S1]`, and the stone had not been pushed -- the world
-- resets daily, so the fact that this passage was walked on the 11th says
-- nothing about whether it is open on the 12th. The room's own Description is
-- the tell: "The northern portion of this chamber is obscured by a strange mist.
-- The only visible exit is east through a stone archway." The mist IS the shut
-- door, and `ex` lists the exit behind it regardless.
--
-- Which makes this the session worth freezing hardest, because it is the shape
-- that quietly corrupts a graph. A refused move has already been sent, so the
-- direction is sitting in the pending queue with no arrival coming for it. Drop
-- it and the NEXT room entered -- next move, next session, after a recall --
-- pairs with the stale direction and gets written in as an edge nobody walked.
--
-- Every assertion here PASSES today. It is a guard, not a bug report: the
-- "Sorry, there's no exit in that direction." trigger shifts the queue, and this
-- is what says so from a real walk rather than a hand-fed line.

local replay = dofile("test/log_replay.lua")

local OUTER = "logs/focused-session-tojolias-2026-09-11T21-24-54.log"
local RESUME = "logs/session-tojolias-2026-09-12T10-18-42.log"
local SHUT = "logs/session-tojolias-2026-09-12T10-37-22.log"

-- Only OUTER predates baud recording aliases.
local SETUP = { { "map-area stoneworks-level-1 The Stoneworks, Level 1" } }

-- Eight moves back over mapped rooms from [!] to [D1], then the ninth that the
-- game refused.
local WALK = { "sw", "w", "sw", "s", "w", "w", "w", "w", "n" }

local function roomBySlug(g, slug)
    for _, r in ipairs(g.rooms()) do
        if r.slug == slug then return r end
    end
    return nil
end

describe("Stoneworks level 1 — an exit the game lists but refuses", function()

    local g

    setup(function()
        g = replay.replayChain({ OUTER, RESUME, SHUT }, { setup = SETUP })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the log itself", function()

        it("walks eight mapped rooms and is refused on the ninth move", function()
            assert.are.same(WALK, replay.movesIn(SHUT))
        end)

        it("was told the exit exists and then that it does not", function()
            local f = assert(io.open(SHUT, "r"))
            local buf = f:read("a"); f:close()
            -- Order matters: the Exits line comes first, the refusal after.
            local exitsAt = buf:find("Exits: n,e.", 1, true)
            local refusedAt = buf:find("Sorry, there's no exit in that direction.", 1, true)
            assert.is_truthy(exitsAt, "expected `Exits: n,e.` at [D1]")
            assert.is_truthy(refusedAt, "expected the refusal")
            assert.is_true(refusedAt > exitsAt)
        end)
    end)

    describe("the refused move leaves nothing behind", function()

        it("clears the direction from the pending queue", function()
            -- The whole point. A direction left here pairs with the next room
            -- entered, whenever that is, and becomes an edge nobody walked.
            assert.are.same({}, g.pendingDirs())
        end)

        it("mints no room", function()
            assert.are.equal(27, g.roomCount())
        end)

        it("adds no exit to the room it was refused from", function()
            local d1 = assert(roomBySlug(g, "stonework-chamber-1"))
            assert.are.equal("e,n", g.exitSet(d1.id))
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("attempts no loop closure", function()
            assert.are.equal(0, #g.echoesMatching("linked into"))
        end)
    end)

    describe("a shut Door stays a real edge", function()

        it("leaves [D1]'s north exit pointing where it was walked from", function()
            -- Walked on the 11th, shut on the 12th. Topology is a map fact;
            -- whether a Device has been operated today is not, so the edge
            -- stays and the graph does not learn to doubt it.
            local d1 = assert(roomBySlug(g, "stonework-chamber-1"))
            local north = d1.exits.n
            assert.is_truthy(north, "north should still be a walked edge, not a stub")
            local back = g.db.one(
                "SELECT to_id FROM room_exits WHERE from_id = " .. north
                .. " AND direction = 's'")
            assert.are.equal(d1.id, back.to_id)
        end)

        it("does not turn the refusal into a new frontier", function()
            -- Three stubs, the same three as before this session. A refused move
            -- is not an unexplored exit.
            assert.are.equal(3, #g.stubs())
        end)

        it("keeps the Description that explains the refusal", function()
            local d1 = assert(roomBySlug(g, "stonework-chamber-1"))
            assert.is_truthy(d1.description:find("obscured by a strange mist", 1, true))
            assert.is_truthy(d1.description:find("only visible exit is east", 1, true))
        end)
    end)
end)
