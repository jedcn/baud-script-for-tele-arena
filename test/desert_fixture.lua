-- Shared setup for the desert specs, which chain progressively more of the
-- re-walk: each spec replays every session up to the one it is about, because
-- the graph a session builds only makes sense on top of the ones before it.
--
-- The seed is what the sewers hand to the walk, plus the one room of the OLD
-- desert the first session touched before resetting it.
--
-- `town-sewer-1` is where `map-here` anchors, at the top of the shaft up from the
-- sewers. Its `u` leads to the old crude stone building, which is what the first
-- move of session one resolves to -- so the old room has to be here, or the reset
-- deletes nothing and the walk never cold-starts. The other 47 rooms of the old
-- desert are not seeded: the reset removes the lot, and nothing in any session
-- looks at them.

local M = {}

-- In walking order. A spec takes the prefix it needs.
M.LOGS = {
    "logs/session-tojolias-2026-09-14T19-50-04.log",  -- the strip in from the sewers
    "logs/session-tojolias-2026-09-14T20-12-25.log",  -- east and round the first loop
    "logs/session-tojolias-2026-09-14T20-21-08.log",  -- the south-west arm, and a
                                                      -- closure the mapper missed
}

-- The first `n` sessions. A spec asks for the prefix it is about, rather than
-- reaching for M.LOGS directly: adding a later session to the list would
-- otherwise silently change what every earlier spec replays, which is exactly
-- what happened the first time session three was added.
function M.upTo(n)
    local out = {}
    for i = 1, n do out[i] = assert(M.LOGS[i], "no session " .. i) end
    return out
end

function M.seed()
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

-- Read the graph once and hand back lookups. g.rooms() is a query per room
-- against a real sqlite3 process, so calling it inside a walk is what makes a
-- spec take minutes.
function M.index(g)
    local byId, bySlug = {}, {}
    for _, r in ipairs(g.rooms()) do
        byId[r.id] = r
        bySlug[r.slug] = r
    end
    -- Follow `dirs` from a room, the way the session walked it. Slugs are not used
    -- past the start: they are a function of mint order, and what these specs mean
    -- is "the room three moves that way".
    local function follow(room, dirs)
        for dir in dirs:gmatch("%S+") do
            local id = room.exits[dir]
            assert(id, "no walked exit " .. dir .. " from " .. room.slug)
            room = assert(byId[id], dir .. " from " .. room.slug .. " leads to a room that is gone")
        end
        return room
    end
    return {
        byId = byId,
        bySlug = function(slug) return bySlug[slug] end,
        follow = follow,
        areaOf = function(slug)
            return g.db.one("SELECT a.slug AS s FROM rooms r JOIN areas a ON a.id = r.area_id"
                .. " WHERE r.slug = '" .. slug .. "'").s
        end,
        deserts = function()
            return g.db.one("SELECT COUNT(*) AS n FROM rooms WHERE area_id ="
                .. " (SELECT id FROM areas WHERE slug = 'desert')").n
        end,
    }
end

return M
