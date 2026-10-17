-- The Elven Valley wall path: a loop closure "confirmed" by a corridor in which
-- every room is the same.
--
-- The path around Mytthos is a rectangle of rooms all called "path in the Elven
-- Valley", all with the same description, nearly all with exits e,w. Walking w
-- from path-in-the-elven-valley-7 minted a new e,w room, and findLoopClosure
-- offered -12 for it: same name, same exits, same description, and -12's e an
-- unwalked stub. The next three rooms west agreed with -12's neighbours -11, -10
-- and -9, because every one of them is e,w -- so it merged, closing a six-room
-- ring of nothing but e moves. Two rooms later the walk reached "-7" and `ex`
-- had no s (logs/session-pelayo-2026-10-17T17-15-32.log, line 267).
--
-- The same thing happened on 2026-10-02, and was cut by hand (c7a5fc7). Agreement
-- that any room in the corridor would have given is no evidence: a confirming
-- room only counts once the chain has passed through a room that does not look
-- like the one it started on.

local replay = dofile("test/mapper/log_replay.lua")

local LOG = "test/fixtures/session-logs/session-pelayo-2026-10-17T17-15-32.log"

-- The path as the live map held it when the session began. The log turns
-- mapping on itself (`$ map-here path-in-the-elven-valley-7`).
local SEED = "test/mapper/elven_valley_path_at_session_start.sql"

describe("The Elven Valley path: a closure confirmed only by identical rooms", function()

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

    it("does not close -7's west arm into -12", function()
        local w = exitOf("path-in-the-elven-valley-7", "w")
        assert.is_not_nil(w, "path-in-the-elven-valley-7 has a w exit")
        assert.are_not.equal("path-in-the-elven-valley-12", w.to_slug)
        local e = exitOf("path-in-the-elven-valley-12", "e")
        assert.is_not_nil(e, "path-in-the-elven-valley-12 has an e exit")
        assert.is_nil(e.to_id, "path-in-the-elven-valley-12 e should still be unwalked")
    end)

    it("keeps the rooms walked west of -7 as rooms of their own", function()
        local w = exitOf("path-in-the-elven-valley-7", "w")
        assert.is_not_nil(w.to_id, "path-in-the-elven-valley-7 w was walked")
        local back = exitOf(w.to_slug, "e")
        assert.are.equal("path-in-the-elven-valley-7", back and back.to_slug)
    end)
end)
