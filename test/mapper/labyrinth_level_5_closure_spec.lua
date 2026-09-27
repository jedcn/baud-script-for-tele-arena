-- The labyrinth, Level 5: a loop closure that ran out of evidence.
--
-- Walking s, e, e, n from labyrinth-289 goes through two new rooms (the page's
-- row 3, columns 35 and 40) and back into two walked ones: labyrinth-286 (row 3,
-- column 45) and labyrinth-287 above it. The mapper held a closure on the first
-- new room -- it "was" labyrinth-276, two columns left, also e,n,s with an
-- unwalked n -- and the next two rooms agreed with 276's neighbours (277 e,w;
-- 278 n,s,w). The fourth move could not be checked, because 278's n was
-- unwalked, and the rule was to settle on the agreement so far. So three real
-- rooms were folded into 276/277/278, and the walk after that was stopped by the
-- lost-room guard (logs/session-teekywiki-2026-09-26T16-13-38.log, line 4248).
--
-- Two things were wrong. Running out of evidence is not agreement, so the
-- chain is now dropped rather than merged. And the third room sat EXACTLY on
-- labyrinth-286's square with 286's exits: a match the mapper trusts outright
-- everywhere else, suppressed here because a chain was pending. Such a match now
-- overrules the chain.

local replay = dofile("test/mapper/log_replay.lua")

local LOG = "logs/session-teekywiki-2026-09-26T16-13-38.log"

-- The walk above happens at line 4148 of a 4,547-line session. Replaying the
-- 4,147 lines before it took eight minutes (74,322 sqlite3 processes) and did
-- nothing but build the Level 5 map the walk runs into. So that map is frozen
-- instead, and only the walk is replayed.
--
-- labyrinth_level_5_at_line_4147.sql is exactly what a replay of lines 1-4147
-- leaves in the database, less the 203 inert Level 1 stand-ins that only kept
-- the slugs numbered as in the real session. At that line mapping is on, the
-- mapper stands in labyrinth-289 at (5,6,0), and no closure is held -- which is
-- all `map-here labyrinth-289` needs to reproduce.
--
-- Regenerate it only if a change to the mapper alters what it builds BEFORE
-- line 4148: replay the log with `{ to = 4147 }` and the old stand-in seed (see
-- git history of this file), then dump areas, the non-stand-in rooms and every
-- room_exits row with `sqlite3 -header <db> ".mode insert <table>" ...`.
local SEED = "test/mapper/labyrinth_level_5_at_line_4147.sql"

describe("The labyrinth, Level 5: a closure that ran out of evidence", function()

    local g

    setup(function()
        g = replay.replayChain({ LOG }, {
            seedFile = SEED,
            setup = { { "map-here labyrinth-289" } },
            from = 4148,
        })
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

    it("does not fold the new rooms into labyrinth-276", function()
        -- South of 289 is the first new room, not 276. (276's own n is walked
        -- later in this same log, lines 4417-4427, so it is not simply left open.)
        local s = exitOf("labyrinth-289", "s")
        assert.is_not_nil(s, "labyrinth-289 has an s exit")
        assert.is_not_nil(s.to_id, "labyrinth-289 s is unwalked")
        assert.are_not.equal("labyrinth-276", s.to_slug)
        local back = exitOf(s.to_slug, "n")
        assert.are.equal("labyrinth-289", back and back.to_slug)
    end)

    it("closes the loop onto labyrinth-286 instead", function()
        -- The room east of the two new ones is 286 itself: its w is walked now.
        local w = exitOf("labyrinth-286", "w")
        assert.is_not_nil(w, "labyrinth-286 has a w exit")
        assert.is_not_nil(w.to_id, "labyrinth-286 w is still unwalked")
    end)

    it("is never stopped by the lost-room guard", function()
        assert.are.equal(0, #g.echoesMatching("mapping OFF: `ex` says"))
    end)
end)
