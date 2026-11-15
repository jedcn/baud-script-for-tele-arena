-- The characters table, through real SQLite: one row per character holding
-- its location and drain flag, and the one-time move of the two tables it
-- replaced (player_location, drained_characters).

local helper = require("test.test_helper")
local SqliteDb = dofile("test/mapper/sqlite_db.lua")

describe("the characters table", function()

    local db

    before_each(function()
        helper.resetAll()
        db = SqliteDb.install()
    end)

    after_each(function()
        if db then db.remove() end
    end)

    it("moves player_location and drained_characters rows over, then drops both", function()
        db.exec("CREATE TABLE player_location (player TEXT PRIMARY KEY, room_id INTEGER, updated_at TEXT)")
        db.exec("INSERT INTO player_location VALUES ('Pollux', 101, '2026-11-12T20:15:00')")
        db.exec("INSERT INTO player_location VALUES ('Castor', 102, '2026-11-12T20:16:00')")
        db.exec("CREATE TABLE drained_characters (player TEXT PRIMARY KEY, drained_at TEXT)")
        db.exec("INSERT INTO drained_characters VALUES ('Pollux', '2026-11-12T20:15:31')")
        db.exec("INSERT INTO drained_characters VALUES ('Kerhak', '2026-08-07T18:00:00')")

        local TaDb = dofile("ta_db.lua")

        assert.are.equal(101, TaDb.playerLocation("Pollux"))
        assert.are.equal(102, TaDb.playerLocation("Castor"))
        assert.is_nil(TaDb.playerLocation("Kerhak"))
        assert.is_true(TaDb.isDrained("Pollux"))
        assert.is_true(TaDb.isDrained("Kerhak"))
        assert.is_false(TaDb.isDrained("Castor"))
        local gone = db.rows("SELECT name FROM sqlite_master WHERE name IN"
            .. " ('player_location', 'drained_characters')")
        assert.are.equal(0, #gone)

        -- A reload finds nothing left to move and changes nothing.
        TaDb = dofile("ta_db.lua")
        assert.are.equal(101, TaDb.playerLocation("Pollux"))
        assert.is_true(TaDb.isDrained("Pollux"))
    end)

    it("keeps location and drain apart on the same row", function()
        local TaDb = dofile("ta_db.lua")
        TaDb.setPlayerLocation("Pollux", 7)
        TaDb.setDrained("Pollux", true)
        TaDb.clearPlayerLocation("Pollux")
        assert.is_nil(TaDb.playerLocation("Pollux"))
        assert.is_true(TaDb.isDrained("Pollux"))      -- losing track keeps the drain

        TaDb.setPlayerLocation("Pollux", 8)
        TaDb.setDrained("Pollux", false)
        assert.are.equal(8, TaDb.playerLocation("Pollux"))  -- restoring keeps the room
        assert.is_false(TaDb.isDrained("Pollux"))
        assert.are.equal(1, #db.rows("SELECT player FROM characters"))
    end)
end)
