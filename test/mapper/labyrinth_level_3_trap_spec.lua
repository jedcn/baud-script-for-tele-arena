-- The labyrinth, Level 3: the corridor that looks like somewhere you have been.
--
-- Walking east from labyrinth-122, the rooms run e,w / n,w / n,s / e,s up the
-- shrine page's column 30. Two boxes to the left, already walked, are
-- labyrinth-104 / 103 / 102 / 101, running e,w / n,w / n,s / e,n,s up column 25.
-- Every room is "labyrinth" with the same description, so for three rooms in a
-- row the two runs are indistinguishable.
--
-- The mapper held a loop closure on the first (the new e,w room "is" 104, whose
-- w is unwalked) and confirmed it on the second (n,w, as 103 is). It merged both,
-- followed the old edges north, and was stopped two rooms later by the lost-room
-- guard, when `ex` said e,s where 101 has e,n,s. That happened on two walks in a
-- row (logs/session-teekywiki-2026-09-25T21-28-18.log and ...T21-35-13.log).
--
-- A closure is now held for up to three predicted rooms, and the third one here
-- refutes it before anything is merged.

local replay = dofile("test/mapper/log_replay.lua")

local LOG = "logs/session-teekywiki-2026-09-25T21-28-18.log"   -- the corridor, and the trap

-- The walk resumes from an earlier session,
-- logs/session-teekywiki-2026-09-25T21-07-06.log, which went down to Level 3,
-- ran map-area, and walked five rooms (labyrinth-100 .. labyrinth-104). Replaying
-- its 2,025 lines to rebuild those five rooms took most of this spec's runtime,
-- so they are frozen instead.
--
-- labyrinth_level_3_after_first_log.sql is exactly what a replay of that session
-- leaves in the database, less the 100 inert Level 1 stand-ins that only kept the
-- slugs numbered as in the real session -- with labyrinth-104's description
-- already cleaned. Before the second walk, "Tojolias logs OFF. [...]" was cleaned
-- off the front of it (adcf538). The polluted description had been hiding the
-- trap: a closure is refused when descriptions differ, and cleaning it is what
-- let 104 be proposed.
--
-- Regenerate it only if a change to the mapper alters what that first session
-- builds: replay it alone with the old stand-in seed (see git history of this
-- file), apply the description cleanup, then dump areas, the non-stand-in rooms,
-- room_exits and player_location with
-- `sqlite3 -header <db> ".mode insert <table>" ...`.
local SEED = "test/mapper/labyrinth_level_3_after_first_log.sql"

describe("The labyrinth, Level 3: a corridor that mimics a walked one", function()

    local g

    setup(function()
        g = replay.replayChain({ LOG }, { seedFile = SEED })
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    local function exitOf(slug, dir)
        return g.db.one(
            "SELECT e.to_id AS to_id, t.slug AS to_slug FROM room_exits e JOIN rooms r ON r.id = e.from_id"
            .. " LEFT JOIN rooms t ON t.id = e.to_id WHERE r.slug = '" .. slug
            .. "' AND e.direction = '" .. dir .. "'")
    end

    it("never merges the new corridor into labyrinth-104", function()
        -- 104's west side is still unwalked: nothing was folded onto it.
        local w = exitOf("labyrinth-104", "w")
        assert.is_not_nil(w, "labyrinth-104 has a w exit")
        assert.is_nil(w.to_id, "labyrinth-104 w was linked to " .. tostring(w.to_slug))
    end)

    it("is never stopped by the lost-room guard", function()
        -- The guard firing is the symptom: the walk was believed to be somewhere
        -- it was not. Echoes are the last log's.
        assert.are.equal(0, #g.echoesMatching("mapping OFF: `ex` says"))
    end)

    it("refuses the closure on the room that tells the two runs apart", function()
        assert.is_true(#g.echoesMatching("refused") > 0)
    end)
end)
