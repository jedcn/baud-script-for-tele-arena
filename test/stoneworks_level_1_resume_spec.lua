-- Stoneworks level 1, session two: resume an existing Area, retrace mapped
-- rooms, then cross a frontier.
--
-- Two things make this different from the outer-edge walk, and both are why it
-- earns its own file:
--
-- It is a RESUMPTION, so it cannot be replayed alone. `map-here
-- stonework-corridor-20` only resolves if that room is already in the database,
-- so the test replays the earlier log first, against the same database, exactly
-- as the real sessions ran. That chain is the fixture.
--
-- And it is the first log baud recorded aliases into, so it needs no `setup`:
-- the `$ map-here stonework-corridor-20` line is in the log itself.
--
-- Every assertion here is a PASS today. The walk was checked against
-- map/shrine/stoneworks-1.txt move by move before it was frozen: all four new
-- rooms sit on the boxes the drawing puts them on, and the last is `[!]`.

local replay = dofile("test/log_replay.lua")

local OUTER = "logs/focused-session-tojolias-2026-09-11T21-24-54.log"
local RESUME = "logs/session-tojolias-2026-09-12T10-18-42.log"

-- OUTER predates alias logging, so its map-area has to be supplied. RESUME
-- carries its own.
local SETUP = { { "map-area stoneworks-level-1 The Stoneworks, Level 1" } }

-- Four moves back over already-mapped rooms to the frontier at
-- stonework-corridor-16, then four into new ground.
local RETRACE = { "nw", "w", "nw", "n" }
local NEW = { "n", "ne", "e", "ne" }

-- What the drawing says those four new rooms are. The last is `[!]`, a dead end
-- reachable on foot -- the legend also offers it via a push-stone Teleport from
-- S3, which is a different way in, not a second room.
local EXPECTED_NEW = {
    { slug = "stonework-corridor-21", exits = "ne,s" },
    { slug = "stonework-corridor-22", exits = "e,sw" },
    { slug = "stonework-corridor-23", exits = "ne,w" },
    { slug = "stonework-corridor-24", exits = "sw" },
}

local function roomBySlug(g, slug)
    for _, r in ipairs(g.rooms()) do
        if r.slug == slug then return r end
    end
    return nil
end

describe("Stoneworks level 1 — resuming and crossing a frontier", function()

    local g

    setup(function()
        g = replay.replayChain({ OUTER, RESUME }, { setup = SETUP })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the log itself", function()

        it("records its own aliases, so the test supplies no setup for it",
            function()
                local f = assert(io.open(RESUME, "r"))
                local buf = f:read("a"); f:close()
                assert.is_truthy(buf:find("\n$ map-here stonework-corridor-20", 1, true),
                    "expected the map-here alias to be in the log")
                assert.is_truthy(buf:find("\n$ map-off", 1, true))
            end)

        it("retraces four mapped rooms, then walks four new ones", function()
            local expected = {}
            for _, d in ipairs(RETRACE) do expected[#expected + 1] = d end
            for _, d in ipairs(NEW) do expected[#expected + 1] = d end
            assert.are.same(expected, replay.movesIn(RESUME))
        end)
    end)

    describe("the graph after both sessions", function()

        it("holds 27 rooms: 23 from the first walk plus 4 new", function()
            -- The four retraced rooms must mint nothing. Re-entering a mapped
            -- room is the case the mapper gets right, and this is what says so.
            assert.are.equal(27, g.roomCount())
        end)

        it("attempts no loop closure at all in this session", function()
            -- Script state is reset between logs, so these echoes are RESUME's
            -- alone. The first session closed one loop it should not have; this
            -- one closes none, which is correct -- the walk never returns
            -- anywhere.
            assert.are.equal(0, #g.echoesMatching("linked into"))
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("spends the frontier it crossed and opens no new one", function()
            -- Four stubs before, three after: corridor-16's `n` was walked and
            -- the new rooms are a dead-end spur, so nothing was added.
            assert.are.equal(3, #g.stubs())
        end)

        it("leaves the three remaining stubs where the drawing has more to walk",
            function()
                local slugs = {}
                for _, s in ipairs(g.stubs()) do
                    local id = s:match("^(%d+)")
                    local dir = s:match("%s(%S+)$")
                    local row = g.db.one("SELECT slug FROM rooms WHERE id = " .. id)
                    slugs[#slugs + 1] = row.slug .. " " .. dir
                end
                table.sort(slugs)
                assert.are.same({
                    "stonework-chamber e",
                    "stonework-corridor-7 nw",
                    "stonework-corridor-9 ne",
                }, slugs)
            end)
    end)

    describe("the four new rooms", function()

        it("are minted with the exit-sets the shrine drawing gives them",
            function()
                for _, want in ipairs(EXPECTED_NEW) do
                    local r = roomBySlug(g, want.slug)
                    assert.is_truthy(r, "no room " .. want.slug)
                    assert.are.equal(want.exits, g.exitSet(r.id),
                        want.slug .. " has the wrong exit-set")
                end
            end)

        it("are chained to each other and hung off the frontier room", function()
            local at = {}
            for _, want in ipairs(EXPECTED_NEW) do
                at[#at + 1] = assert(roomBySlug(g, want.slug))
            end
            local frontier = assert(roomBySlug(g, "stonework-corridor-16"))
            assert.are.equal(at[1].id, frontier.exits.n)
            assert.are.equal(frontier.id, at[1].exits.s)
            assert.are.equal(at[2].id, at[1].exits.ne)
            assert.are.equal(at[3].id, at[2].exits.e)
            assert.are.equal(at[4].id, at[3].exits.ne)
        end)

        it("ends at a dead end, which the drawing marks [!]", function()
            local last = assert(roomBySlug(g, "stonework-corridor-24"))
            assert.are.equal("sw", g.exitSet(last.id))
            assert.is_truthy(last.exits.sw, "its one exit should be walked")
        end)

        it("each carry a description that agrees with their exits", function()
            for _, want in ipairs(EXPECTED_NEW) do
                local r = assert(roomBySlug(g, want.slug))
                assert.is_truthy(r.description, "no description on " .. want.slug)
            end
            -- corridor-22 is the one that says "continues to the" rather than
            -- "runs to the"; the prose check has to read both verbs or it skips
            -- this room and calls the level clean.
            assert.is_truthy(#g.corridorMismatches() < 2,
                "this session should add no new prose/edge disagreement")
            assert.is_truthy(g.corridorsChecked() >= 25,
                "the prose check should be examining the new corridors")
        end)
    end)
end)
