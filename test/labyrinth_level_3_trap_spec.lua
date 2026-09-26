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

local replay = dofile("test/log_replay.lua")

local LOGS = {
    "logs/session-teekywiki-2026-09-25T21-07-06.log",   -- down to Level 3, map-area
    "logs/session-teekywiki-2026-09-25T21-28-18.log",   -- the corridor, and the trap
}

-- The real walk minted labyrinth-100 first because Level 1 already held
-- `labyrinth` .. `labyrinth-99`. Inert stand-ins keep the numbering, so the
-- second log's `map-here labyrinth-100` names the right room.
local function seed()
    local out = { "INSERT INTO areas (slug, name) VALUES ('labyrinth-level-1', 'The Labyrinth, Level 1')" }
    local L1 = "(SELECT id FROM areas WHERE slug = 'labyrinth-level-1')"
    out[#out + 1] = "INSERT INTO rooms (slug, name, area_id) VALUES ('labyrinth', 'labyrinth', " .. L1 .. ")"
    for i = 1, 99 do
        out[#out + 1] = "INSERT INTO rooms (slug, name, area_id) VALUES ('labyrinth-" .. i
            .. "', 'labyrinth', " .. L1 .. ")"
    end
    return out
end

describe("The labyrinth, Level 3: a corridor that mimics a walked one", function()

    local g

    setup(function()
        g = replay.replayChain(LOGS, { seed = seed(), sqlBefore = { [2] = {
            -- Before the second walk, "Tojolias logs OFF. [...]" was cleaned off
            -- the front of labyrinth-104's description (adcf538). The polluted
            -- description had been hiding the trap: a closure is refused when
            -- descriptions differ, and cleaning it is what let 104 be proposed.
            "UPDATE rooms SET description = substr(description, instr(description, 'You are wandering'))"
                .. " WHERE slug = 'labyrinth-104'",
        } } })
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
