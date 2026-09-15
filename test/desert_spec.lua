-- The desert, session one: the strip from the sewers down to the first room of
-- the desert proper, walked 2026-09-14 after the old 48-room desert was reset.
--
-- The desert is the area that broke the mapper. It has never been mapped: what
-- was in the database was 48 rooms of which three carried exits their own
-- descriptions denied -- the signature of a false loop closure, where two rooms
-- are merged and the survivor wears both sets of exits. The shrine's drawing is
-- 103 rooms and 120 edges, so eighteen independent loops, which is why.
--
-- This session is deliberately the loop-free part: the storage rooms, the crude
-- stone building, the seven sandy passages and the first `desert` room. It is
-- the fixture for three things, none of which the stoneworks logs could show:
--
--   * a Seam crossed in the WRONG ORDER, and what that costs. The walk crossed
--     into the old desert, reset the area from inside it, and cold-started --
--     which leaves both sides of the stairs unlinked, because the move that
--     crossed was consumed before the reset and the cold start has no direction
--     to link. The repair was two UPDATEs by hand; walking it again cannot fix
--     it, since an area-scoped fingerprint search will mint a duplicate of
--     town-sewer-1 inside the desert rather than recognise it.
--   * a cold start into a freshly emptied area, which is the one case where
--     map-area's resolve-by-name is safe: nothing of that area is left to match.
--   * the desert's own prose dialect, and the two sentences that qualify it.
--     Rooms say "Huge black outcroppings of rock block travel in all directions
--     except to the east and southwest", and a LANDMARK way out gets a sentence
--     of its own: "The entrance to a crude circular stone building lies to the
--     north", "a crude stone archway leads out into the desert to the south".
--     Both are real exits `ex` lists, and reading only the first sentence
--     reported them as defects until this walk.

local replay = dofile("test/log_replay.lua")

local LOGS = { "logs/session-tojolias-2026-09-14T19-50-04.log" }

-- What the sewers hand to this walk, and the one room of the OLD desert the walk
-- touched before resetting it.
--
-- `town-sewer-1` is where `map-here` anchors, at the top of the shaft up from the
-- sewers. Its `u` leads to the old crude stone building, which is what the first
-- move of the session resolves to -- so the old room has to be here, or the reset
-- deletes nothing and the walk never cold-starts. The other 47 rooms of the old
-- desert are not seeded: the reset removes the lot, and nothing in the session
-- looks at them.
local function seedBefore()
    local SEWERS = "(SELECT id FROM areas WHERE slug = 'sewers-level-3')"
    local DESERT = "(SELECT id FROM areas WHERE slug = 'desert')"
    local ROOM = "(SELECT id FROM rooms WHERE slug = '%s')"
    return {
        "INSERT INTO areas (slug, name) VALUES ('sewers-level-3', 'Sewers, Level 3')",
        "INSERT INTO areas (slug, name) VALUES ('desert', 'The Desert')",
        "INSERT INTO rooms (slug, name, area_id, x, y, z) VALUES"
            .. " ('town-sewer-1', 'town sewer', " .. SEWERS .. ", 8, 5, -1)",
        "INSERT INTO rooms (slug, name, area_id, x, y, z) VALUES"
            .. " ('town-sewer', 'town sewer', " .. SEWERS .. ", 8, 5, -2)",
        "INSERT INTO rooms (slug, name, description, area_id) VALUES"
            .. " ('crude-stone-building', 'crude stone building',"
            .. " 'You are in a circular stone building approximately forty feet in"
            .. " diameter.', " .. DESERT .. ")",
        -- The shaft, and the Seam as it stood: walked in both directions.
        "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
            .. ROOM:format("town-sewer-1") .. ", 'd', " .. ROOM:format("town-sewer") .. ")",
        "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
            .. ROOM:format("town-sewer") .. ", 'u', " .. ROOM:format("town-sewer-1") .. ")",
        "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
            .. ROOM:format("town-sewer-1") .. ", 'u', "
            .. ROOM:format("crude-stone-building") .. ")",
        "INSERT INTO room_exits (from_id, direction, to_id) VALUES ("
            .. ROOM:format("crude-stone-building") .. ", 'd', "
            .. ROOM:format("town-sewer-1") .. ")",
    }
end

-- The strip as the shrine draws it (map/shrine/desert.txt, the top row and the
-- chain south), and as `ex` answered on the walk. Followed from the building
-- rather than asserted by slug, so a change in mint order cannot make this pass
-- for the wrong reason.
local STRIP = {
    { dir = "w",  slug = "storage-room",    exits = "e,w" },
    { dir = "w",  slug = "storage-room-1",  exits = "e" },      -- dead end
    { dir = "e",  slug = "storage-room",    exits = "e,w" },
    { dir = "e",  slug = "crude-stone-building", exits = "d,e,w" },
    { dir = "e",  slug = "sandy-passage",   exits = "e,w" },
    { dir = "e",  slug = "sandy-passage-1", exits = "s,w" },
    { dir = "s",  slug = "sandy-passage-2", exits = "n,s" },
    { dir = "s",  slug = "sandy-passage-3", exits = "n,s" },
    { dir = "s",  slug = "sandy-passage-4", exits = "n,w" },
    { dir = "w",  slug = "sandy-passage-5", exits = "e,w" },
    { dir = "w",  slug = "sandy-passage-6", exits = "e,w" },
    { dir = "w",  slug = "sandy-passage-7", exits = "e,s" },
    { dir = "s",  slug = "desert",          exits = "e,n,sw" },
}

describe("The desert, session one", function()

    local g
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

    local function bySlug(slug)
        index()
        return bySlugIndex[slug]
    end

    local function areaOf(slug)
        return g.db.one("SELECT a.slug AS s FROM rooms r JOIN areas a ON a.id = r.area_id"
            .. " WHERE r.slug = '" .. slug .. "'").s
    end

    setup(function()
        g = replay.replayChain(LOGS, { seed = seedBefore() })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the reset and the cold start", function()

        it("empties the area and mints it again from nothing", function()
            -- 12 rooms: two storage rooms, the building, seven sandy passages and
            -- the first room of the desert proper. The old building is gone and a
            -- new one stands in its place -- same slug, because the reset freed it.
            assert.are.equal(12, g.db.one(
                "SELECT COUNT(*) AS n FROM rooms WHERE area_id ="
                .. " (SELECT id FROM areas WHERE slug = 'desert')").n)
            assert.are.equal(1, #g.echoesMatching("reset area desert"))
            assert.are.equal("desert", areaOf("crude-stone-building"))
        end)

        it("resolves the cold start by name, which is safe only here", function()
            -- map-area cold-starting resolves the room it is standing in BY NAME,
            -- and where names repeat that is a coin toss. Straight after a reset it
            -- is not a gamble at all: every room of that area is gone, so the name
            -- matches nothing and a fresh room is minted. Any other order wants
            -- the anchor kept instead (see 8399ddb).
            assert.are.equal(1, #g.echoesMatching("mapping desert from here"))
            assert.are.equal(0, #g.echoesMatching("kept anchor"))
        end)
    end)

    describe("the strip", function()

        it("walks the shrine's top row and the chain south", function()
            local at = assert(bySlug("crude-stone-building"))
            for i, step in ipairs(STRIP) do
                local id = at.exits[step.dir]
                assert.is_truthy(id, "step " .. i .. " (" .. step.dir .. ") leads nowhere from "
                    .. at.slug)
                local nxt = byId[id]
                assert.is_truthy(nxt, "step " .. i .. " lands on a room that is gone")
                assert.are.equal(step.slug, nxt.slug, "step " .. i .. " (" .. step.dir .. ")")
                assert.are.equal(step.exits, g.exitSet(nxt.id), "exits of " .. nxt.slug)
                at = nxt
            end
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("records no exit a room's own description denies", function()
            -- The check that found the old desert's damage. Nine of the twelve
            -- rooms name their exits in prose here -- the sandy passages, the
            -- storage rooms and the desert room -- so it is not passing by looking
            -- at nothing.
            assert.are.same({}, g.proseMismatches())
            assert.is_true(g.prosesChecked() >= 9,
                "only " .. g.prosesChecked() .. " rooms were read")
        end)

        it("counts the landmark ways out that prose gives their own sentence",
            function()
                -- Two of them, and both are real exits `ex` lists. sandy-passage-7
                -- says "The passage continues to the east and a crude stone archway
                -- leads out into the desert to the south"; the desert room says
                -- "The entrance to a crude circular stone building lies to the
                -- north". Read only the first sentence of either and the exit we
                -- walked in through reads as a defect.
                local archway = assert(bySlug("sandy-passage-7"))
                assert.is_truthy(archway.description:find("archway leads out", 1, true))
                assert.are.equal("e,s", g.exitSet(archway.id))
                local first = assert(bySlug("desert"))
                assert.is_truthy(first.description:find("entrance to a crude circular", 1, true))
                assert.are.equal("e,n,sw", g.exitSet(first.id))
            end)

        it("leaves the two frontiers the drawing says are there", function()
            -- `e` and `sw` out of the first desert room, and nothing else -- bar
            -- the stairs the next test is about.
            -- g.rooms() records an unwalked Stub as `false`, a walked edge as an
            -- id, and a direction with no exit at all as nil.
            local first = assert(bySlug("desert"))
            assert.are.equal(false, first.exits.e, "e is a Stub")
            assert.are.equal(false, first.exits.sw, "sw is a Stub")
            assert.is_truthy(first.exits.n, "n is walked, back up the strip")
        end)
    end)

    describe("the Seam, crossed in the wrong order", function()

        it("leaves the stairs unlinked at both ends", function()
            -- The cost of resetting from INSIDE the area. The `u` that crossed was
            -- consumed resolving to the old building; the reset then re-stubbed the
            -- sewers' side of it, and the cold start minted a building with no
            -- direction to link. Both ends are Stubs, and nothing in the session
            -- says so -- which is why this is asserted rather than remembered.
            assert.are.equal(false, assert(bySlug("crude-stone-building")).exits.d,
                "the building's d is a Stub")
            assert.are.equal(false, assert(bySlug("town-sewer-1")).exits.u,
                "the sewers' u is a Stub")
        end)

        it("keeps the sewers out of the new area", function()
            -- The rooms the walk passed through on the way up are still the sewers'.
            -- A cold start that had resolved to one of them by name would have filed
            -- it into the desert instead.
            assert.are.equal("sewers-level-3", areaOf("town-sewer-1"))
            assert.are.equal("sewers-level-3", areaOf("town-sewer"))
        end)
    end)
end)
