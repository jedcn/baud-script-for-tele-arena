-- What the devices schema can and cannot hold.
--
-- There is no Lua API for writing devices, on purpose: there are on the order of
-- twenty in the whole game, they have not changed in thirty years, and they are
-- entered by hand in SQL. So these tests are SQL too. What they check is the
-- shape -- that the schema can express the four effects, that one device can
-- open several Seals, that sealing an exit does not disturb the topology -- since
-- the shape is the only thing there is to get wrong.
--
-- They also pin the two absences that are deliberate, because a later reader
-- would otherwise reasonably add them back: no Device State column, and no
-- cascade on delete.

local helper = require("test.test_helper")
local SqliteDb = dofile("test/sqlite_db.lua")

describe("the devices schema", function()

    local db, TaDb

    -- A tiny world through the real schema, so the tables are the ones ta_db.lua
    -- creates rather than a copy that can drift from them.
    before_each(function()
        helper.resetAll()
        db = SqliteDb.install()
        TaDb = dofile("ta_db.lua")
        local areaId = TaDb.ensureArea("stoneworks-level-1", "The Stoneworks, Level 1")
        TaDb.discoverRoom("stonework chamber", areaId)      -- 1  the riddle chamber
        TaDb.discoverRoom("stonework corridor", areaId)     -- 2
        TaDb.discoverRoom("stonework corridor", areaId)     -- 3  a lever room
        TaDb.discoverRoom("stonework corridor", areaId)     -- 4  a stone room
        TaDb.recordKnownExit(1, "n")
        TaDb.recordKnownExit(1, "e")
        TaDb.recordKnownExit(1, "s")
        TaDb.recordKnownExit(4, "nw")
    end)

    after_each(function()
        if db then db.remove() end
    end)

    local function addDevice(roomId, command, effect, extra)
        db.exec("INSERT INTO devices (room_id, command, effect" .. (extra and extra.cols or "")
            .. ") VALUES (" .. roomId .. ", '" .. command .. "', '" .. effect .. "'"
            .. (extra and extra.vals or "") .. ")")
        return db.one("SELECT MAX(id) AS id FROM devices").id
    end

    describe("holds the four effects", function()

        it("a seal, with no target column of its own", function()
            local id = addDevice(3, "pull lever", "seal")
            local d = db.one("SELECT * FROM devices WHERE id=" .. id)
            assert.are.equal("seal", d.effect)
            -- The sealed thing points back at the device, so all three target
            -- columns stay empty on a seal.
            assert.is_nil(d.dest_room_id)
            assert.is_nil(d.trap_room_id)
            assert.is_nil(d.light_area_id)
        end)

        it("a teleport, with a fixed destination room", function()
            local id = addDevice(4, "push stone", "teleport",
                { cols = ", dest_room_id", vals = ", 2" })
            assert.are.equal(2, db.one("SELECT dest_room_id FROM devices WHERE id=" .. id).dest_room_id)
        end)

        it("a trap device, pointing at the room whose trap it disarms", function()
            local id = addDevice(3, "pull lever", "trap",
                { cols = ", trap_room_id", vals = ", 1" })
            assert.are.equal(1, db.one("SELECT trap_room_id FROM devices WHERE id=" .. id).trap_room_id)
        end)

        it("a light device, pointing at an AREA and not a room", function()
            local areaId = TaDb.areaIdBySlug("stoneworks-level-1")
            local id = addDevice(4, "push stone", "light",
                { cols = ", light_area_id", vals = ", " .. areaId })
            assert.are.equal(areaId, db.one("SELECT light_area_id FROM devices WHERE id=" .. id).light_area_id)
        end)
    end)

    describe("Seals, recorded on the exit they block", function()

        it("lets ONE device open SEVERAL exits", function()
            -- The reason a seal has no target column on the device row. `say komi`
            -- opens two doors; a single column could name only one of them.
            local komi = addDevice(1, "say komi", "seal")
            db.exec("UPDATE room_exits SET sealed_by=" .. komi
                .. " WHERE from_id=1 AND direction IN ('e','s')")
            local rows = db.rows("SELECT direction FROM room_exits WHERE sealed_by="
                .. komi .. " ORDER BY direction")
            assert.are.equal(2, #rows)
            assert.are.equal("e", rows[1].direction)
            assert.are.equal("s", rows[2].direction)
        end)

        it("leaves a walked destination alone when an exit is sealed", function()
            -- Topology is a map fact; whether a device has been worked today is
            -- not. Sealing must not degrade a walked edge to a stub.
            TaDb.linkExit(1, "n", 2)
            local lever = addDevice(3, "pull lever", "seal")
            db.exec("UPDATE room_exits SET sealed_by=" .. lever
                .. " WHERE from_id=1 AND direction='n'")
            local e = db.one("SELECT to_id, sealed_by FROM room_exits WHERE from_id=1 AND direction='n'")
            assert.are.equal(2, e.to_id)
            assert.are.equal(lever, e.sealed_by)
        end)

        it("can seal a stub, before the far side has ever been walked", function()
            -- You know [S1] seals [D1]'s north long before you know what is past
            -- it. An exit-keyed seal can say that; a two-room one could not.
            local lever = addDevice(3, "pull lever", "seal")
            db.exec("UPDATE room_exits SET sealed_by=" .. lever
                .. " WHERE from_id=1 AND direction='e'")
            local e = db.one("SELECT to_id, sealed_by FROM room_exits WHERE from_id=1 AND direction='e'")
            assert.is_nil(e.to_id)
            assert.are.equal(lever, e.sealed_by)
        end)

        it("holds a device that is itself behind another device", function()
            -- Hewn Granite: the lever is behind the tapestry, so `move tapestry`
            -- comes first. A Seal over a Device rather than over an Exit.
            local tapestry = addDevice(3, "move tapestry", "seal")
            local lever = addDevice(3, "pull lever", "seal",
                { cols = ", sealed_by", vals = ", " .. tapestry })
            assert.are.equal(tapestry, db.one("SELECT sealed_by FROM devices WHERE id=" .. lever).sealed_by)
        end)
    end)

    describe("two devices in one room", function()

        it("is allowed when the commands differ", function()
            assert.is_not_nil(addDevice(3, "move tapestry", "seal"))
            assert.is_not_nil(addDevice(3, "pull lever", "seal"))
            assert.are.equal(2, db.one("SELECT COUNT(*) AS n FROM devices WHERE room_id=3").n)
        end)

        it("is refused for the same command twice", function()
            -- `pull lever` takes no argument, so two levers in one room could not
            -- be told apart in the game either.
            addDevice(3, "pull lever", "seal")
            local ok = pcall(function()
                db.exec("INSERT INTO devices (room_id, command, effect)"
                    .. " VALUES (3, 'pull lever', 'seal')")
            end)
            assert.is_false(ok)
        end)
    end)

    describe("deliberate absences", function()

        it("has no column for whether a device has been worked today", function()
            -- Device State belongs to this Reset, not to the map. A column for it
            -- would be wrong by 4am, so nobody should add one.
            local cols = {}
            for _, c in ipairs(db.rows("PRAGMA table_info(devices)")) do cols[c.name] = true end
            assert.is_nil(cols.state)
            assert.is_nil(cols.is_open)
            assert.is_nil(cols.thrown)
            assert.is_nil(cols.open)
        end)

        it("does NOT cascade a delete, so hand-editing must un-point first", function()
            -- Recorded rather than fixed. SQLite is not enforcing these
            -- references (PRAGMA foreign_keys is 0), so deleting a device leaves
            -- exits pointing at an id that is gone. Every deletion in SQL has to
            -- clear room_exits.sealed_by and devices.sealed_by itself -- which is
            -- what CLAUDE.md's device section says to do.
            local komi = addDevice(1, "say komi", "seal")
            db.exec("UPDATE room_exits SET sealed_by=" .. komi .. " WHERE from_id=1 AND direction='e'")
            db.exec("DELETE FROM devices WHERE id=" .. komi)
            local dangling = db.one("SELECT COUNT(*) AS n FROM room_exits e"
                .. " WHERE e.sealed_by IS NOT NULL"
                .. " AND NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = e.sealed_by)")
            assert.are.equal(1, dangling.n)
        end)
    end)

    describe("room entry", function()

        it("announces the devices you can work here", function()
            -- The one thing the script reads devices for: a lever should reach you
            -- before you walk past it.
            addDevice(3, "pull lever", "seal", { cols = ", repeats", vals = ", 'once'" })
            local list = TaDb.devicesInRoom(3)
            assert.are.equal(1, #list)
            assert.are.equal("pull lever", list[1].command)
            assert.are.equal("once", list[1].repeats)
        end)
    end)
end)
