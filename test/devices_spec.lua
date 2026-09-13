-- Devices and Seals, tested against real SQLite rather than the call recorder.
--
-- The point of the table is what it can express, so the assertions are on rows:
-- that one device can seal two exits, that deleting a device leaves nothing
-- dangling, that a teleport cannot be given a repeat behaviour. None of that is
-- visible in "did it issue this statement".

local helper = require("test.test_helper")
local SqliteDb = dofile("test/sqlite_db.lua")

describe("Devices", function()

    local db, TaDb

    -- A tiny world: one area, four rooms, and exits between them. Built through
    -- the real schema so the devices table is the one ta_db.lua creates.
    before_each(function()
        helper.resetAll()
        db = SqliteDb.install()
        TaDb = dofile("ta_db.lua")
        local areaId = TaDb.ensureArea("stoneworks-level-1", "The Stoneworks, Level 1")
        TaDb.discoverRoom("stonework chamber", areaId)      -- 1  [D1]
        TaDb.discoverRoom("stonework corridor", areaId)     -- 2
        TaDb.discoverRoom("stonework corridor", areaId)     -- 3  [S1] lever room
        TaDb.discoverRoom("stonework corridor", areaId)     -- 4  [S2] stone room
        TaDb.recordKnownExit(1, "n")
        TaDb.recordKnownExit(1, "e")
        TaDb.recordKnownExit(2, "s")
        TaDb.recordKnownExit(4, "nw")
    end)

    after_each(function()
        if db then db.remove() end
    end)

    describe("recording one", function()

        it("stores the room you operate it in, the command and the effect", function()
            local id = TaDb.addDevice(3, "pull lever", "seal")
            local d = TaDb.deviceById(id)
            assert.are.equal(3, d.room_id)
            assert.are.equal("pull lever", d.command)
            assert.are.equal("seal", d.effect)
        end)

        it("refuses a second device with the same command in one room", function()
            assert.is_not_nil(TaDb.addDevice(3, "pull lever", "seal"))
            -- `pull lever` takes no argument, so two levers in one room could not
            -- be told apart in the first place.
            assert.is_nil(TaDb.addDevice(3, "pull lever", "seal"))
        end)

        it("allows two devices in one room when the commands differ", function()
            -- The Hewn Granite case: move the tapestry, then pull the lever.
            local tapestry = TaDb.addDevice(3, "move tapestry", "seal")
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            assert.is_not_nil(tapestry)
            assert.is_not_nil(lever)
            assert.are.equal(2, #TaDb.devicesInRoom(3))
        end)

        it("records that one device is behind another", function()
            local tapestry = TaDb.addDevice(3, "move tapestry", "seal")
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            TaDb.setDeviceField(lever, "sealed_by", tapestry)
            assert.are.equal(tapestry, TaDb.deviceById(lever).sealed_by)
        end)

        it("rejects a field that is not a device column", function()
            local id = TaDb.addDevice(3, "pull lever", "seal")
            local ok, err = TaDb.setDeviceField(id, "room_id = 9; DROP TABLE", "x")
            assert.is_nil(ok)
            assert.is_truthy(err)
        end)
    end)

    describe("Seals", function()

        it("marks an exit as sealed by a device", function()
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            assert.are.equal(1, TaDb.setExitSeal(1, "n", lever))
            local row = db.one("SELECT sealed_by FROM room_exits WHERE from_id=1 AND direction='n'")
            assert.are.equal(lever, row.sealed_by)
        end)

        it("lets ONE device seal SEVERAL exits", function()
            -- `say komi` opens two doors. This is the reason the seal is recorded
            -- from the exit's side: a target column on the device row could name
            -- only one of them.
            local komi = TaDb.addDevice(1, "say komi", "seal")
            TaDb.setExitSeal(1, "n", komi)
            TaDb.setExitSeal(1, "e", komi)
            local sealed = TaDb.exitsSealedBy(komi)
            assert.are.equal(2, #sealed)
            local dirs = {}
            for _, e in ipairs(sealed) do dirs[#dirs + 1] = e.direction end
            table.sort(dirs)
            assert.are.same({ "e", "n" }, dirs)
        end)

        it("does not create the exit it seals", function()
            -- A Seal goes ON an exit and does not remove or invent one: [D1]
            -- answered "Exits: n,e." while refusing `n`.
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            assert.are.equal(0, TaDb.setExitSeal(1, "sw", lever))
            assert.is_nil(db.one("SELECT 1 AS x FROM room_exits WHERE from_id=1 AND direction='sw'"))
        end)

        it("leaves the sealed exit's destination alone", function()
            -- Topology is a map fact; whether a Device has been worked today is
            -- not. Sealing must not degrade a walked edge to a stub.
            TaDb.linkExit(1, "n", 2)
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            TaDb.setExitSeal(1, "n", lever)
            local row = db.one("SELECT to_id FROM room_exits WHERE from_id=1 AND direction='n'")
            assert.are.equal(2, row.to_id)
        end)

        it("clears a seal when given no device", function()
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            TaDb.setExitSeal(1, "n", lever)
            TaDb.setExitSeal(1, "n", nil)
            local row = db.one("SELECT sealed_by FROM room_exits WHERE from_id=1 AND direction='n'")
            assert.is_nil(row.sealed_by)
        end)
    end)

    describe("effects that point somewhere", function()

        it("gives a teleport a fixed destination room", function()
            local stone = TaDb.addDevice(4, "push stone", "teleport")
            TaDb.setDeviceField(stone, "dest_room_id", 2)
            assert.are.equal(2, TaDb.deviceById(stone).dest_room_id)
        end)

        it("gives a trap device the room whose trap it disarms", function()
            local lever = TaDb.addDevice(3, "pull lever", "trap")
            TaDb.setDeviceField(lever, "trap_room_id", 1)
            assert.are.equal(1, TaDb.deviceById(lever).trap_room_id)
        end)

        it("gives a light device an area, not a room", function()
            local areaId = TaDb.areaIdBySlug("stoneworks-level-1")
            local stone = TaDb.addDevice(4, "push stone", "light")
            TaDb.setDeviceField(stone, "light_area_id", areaId)
            assert.are.equal(areaId, TaDb.deviceById(stone).light_area_id)
        end)
    end)

    describe("repeat behaviour", function()

        it("stores once and toggle", function()
            local a = TaDb.addDevice(3, "pull lever", "seal")
            TaDb.setDeviceField(a, "repeats", "once")
            assert.are.equal("once", TaDb.deviceById(a).repeats)
            TaDb.setDeviceField(a, "repeats", "toggle")
            assert.are.equal("toggle", TaDb.deviceById(a).repeats)
        end)

        it("leaves it NULL by default, which is what a teleport keeps", function()
            local stone = TaDb.addDevice(4, "push stone", "teleport")
            assert.is_nil(TaDb.deviceById(stone).repeats)
        end)
    end)

    describe("deleting one", function()

        it("un-seals every exit that named it, so nothing dangles", function()
            -- Nothing enforces these references, so the cleanup has to be done
            -- in code or the exit keeps an id that is gone.
            local komi = TaDb.addDevice(1, "say komi", "seal")
            TaDb.setExitSeal(1, "n", komi)
            TaDb.setExitSeal(1, "e", komi)
            TaDb.deleteDevice(komi)
            assert.are.equal(0, db.one(
                "SELECT COUNT(*) AS n FROM room_exits WHERE sealed_by IS NOT NULL").n)
        end)

        it("un-points any device that was behind it", function()
            local tapestry = TaDb.addDevice(3, "move tapestry", "seal")
            local lever = TaDb.addDevice(3, "pull lever", "seal")
            TaDb.setDeviceField(lever, "sealed_by", tapestry)
            TaDb.deleteDevice(tapestry)
            assert.is_nil(TaDb.deviceById(lever).sealed_by)
        end)

        it("reports 0 for a device that was not there", function()
            assert.are.equal(0, TaDb.deleteDevice(999))
        end)
    end)

    describe("the schema after migration", function()

        it("has dropped room_notes", function()
            assert.is_nil(db.one(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='room_notes'"))
        end)

        it("holds no record of whether a device has been worked today", function()
            -- Device State belongs to this Reset, not to the map. A column for it
            -- would be wrong by 4am.
            local cols = {}
            for _, c in ipairs(db.rows("PRAGMA table_info(devices)")) do
                cols[c.name] = true
            end
            assert.is_nil(cols.state)
            assert.is_nil(cols.is_open)
            assert.is_nil(cols.thrown)
        end)
    end)
end)
