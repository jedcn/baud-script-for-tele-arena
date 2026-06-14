-- main_spec.lua
-- Tests for triggers and status display in main.lua

local helper = require("test.test_helper")

describe("Warrior XP table", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    describe("getLevelForXp", function()

        it("returns 1 at 0 XP", function()
            assert.are.equal(1, getLevelForXp(0))
        end)

        it("returns 1 for the user's current XP of 354", function()
            assert.are.equal(1, getLevelForXp(354))
        end)

        it("returns 2 at exactly 1125 XP", function()
            assert.are.equal(2, getLevelForXp(1125))
        end)

        it("returns 2 just below the level 3 threshold", function()
            assert.are.equal(2, getLevelForXp(3239))
        end)

        it("returns 25 at max XP", function()
            assert.are.equal(25, getLevelForXp(11594700))
        end)

    end)

    describe("xpColor (via status bar segments)", function()

        local capturedFn

        before_each(function()
            helper.resetAll()
            _G.setStatus = function(fn) capturedFn = fn end
            dofile("main.lua")
            helper.simulateLine("Class:        Warrior")
        end)

        -- Warrior level 1: 0 XP (start) → 1125 XP (end)
        -- fifth boundaries: 0-224, 225-449, 450-674, 675-899, 900-1124

        it("shows white at 0% (just started level)", function()
            helper.simulateLine("Experience:   0")
            assert.are.equal("white", capturedFn()[5].fg)
        end)

        it("shows cyan in the second fifth", function()
            helper.simulateLine("Experience:   225")  -- 20% of 1125
            assert.are.equal("cyan", capturedFn()[5].fg)
        end)

        it("shows green in the third fifth", function()
            helper.simulateLine("Experience:   450")  -- 40% of 1125
            assert.are.equal("green", capturedFn()[5].fg)
        end)

        it("shows yellow in the fourth fifth", function()
            helper.simulateLine("Experience:   675")  -- 60% of 1125
            assert.are.equal("yellow", capturedFn()[5].fg)
        end)

        it("shows red in the fifth fifth (almost leveled up)", function()
            helper.simulateLine("Experience:   900")  -- 80% of 1125
            assert.are.equal("red", capturedFn()[5].fg)
        end)

        it("shows red at max level", function()
            helper.simulateLine("Experience:   11594700")
            assert.are.equal("red", capturedFn()[5].fg)
        end)

    end)

    describe("getXpForNextLevel", function()

        it("returns 1125 when at level 1", function()
            assert.are.equal(1125, getXpForNextLevel(354))
        end)

        it("returns the level 3 threshold when at level 2", function()
            assert.are.equal(3240, getXpForNextLevel(1125))
        end)

        it("returns nil at max level", function()
            assert.is_nil(getXpForNextLevel(11594700))
        end)

    end)

    describe("other classes", function()

        it("Rogue level 2 threshold is 1120", function()
            assert.are.equal(2, getLevelForXp(1120, "Rogue"))
            assert.are.equal(1, getLevelForXp(1119, "Rogue"))
        end)

        it("Acolyte and Necrolyte share the same thresholds", function()
            assert.are.equal(getLevelForXp(1150, "Acolyte"), getLevelForXp(1150, "Necrolyte"))
        end)

        it("Sorceror and Druid share the same thresholds", function()
            assert.are.equal(getLevelForXp(1180, "Sorceror"), getLevelForXp(1180, "Druid"))
        end)

        it("Sorceror level 2 threshold is 1180", function()
            assert.are.equal(2, getLevelForXp(1180, "Sorceror"))
            assert.are.equal(1, getLevelForXp(1179, "Sorceror"))
        end)

        it("Rogue max level XP is 11221500", function()
            assert.are.equal(25, getLevelForXp(11221500, "Rogue"))
            assert.is_nil(getXpForNextLevel(11221500, "Rogue"))
        end)

    end)

end)

describe("Tele-Arena triggers", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    -- =========================================================================
    -- Gold triggers
    -- =========================================================================

    describe("Gold triggers", function()

        it("sets gold from inventory line", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            assert.are.equal(755, getGold())
        end)

        it("increases gold when looting a corpse", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            helper.simulateLine("You found 5 gold crowns while searching the lizard woman's corpse.")
            assert.are.equal(760, getGold())
        end)

        it("accumulates loot gold from zero when inventory not yet seen", function()
            helper.simulateLine("You found 5 gold crowns while searching the lizard woman's corpse.")
            assert.are.equal(5, getGold())
        end)

        it("sets gold when carrying gold and items", function()
            helper.simulateLine("You are carrying 675 gold crowns, and a shortsword.")
            assert.are.equal(675, getGold())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("You are carrying a shortsword.")
            assert.is_nil(getGold())
        end)

    end)

    -- =========================================================================
    -- Healing trigger
    -- =========================================================================

    describe("Healing trigger", function()

        it("restores vitality to max", function()
            helper.simulateLine("Vitality:     13 / 26")
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            local current, max = getVitality()
            assert.are.equal(26, current)
            assert.are.equal(26, max)
        end)

        it("deducts the cost from gold", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal(753, getGold())
        end)

        it("works when vitality max is not yet known", function()
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            local current, _ = getVitality()
            assert.is_nil(current)
        end)

    end)

    -- =========================================================================
    -- Incoming damage trigger
    -- =========================================================================

    describe("Incoming damage trigger", function()

        it("reduces current vitality by damage amount", function()
            helper.simulateLine("Vitality:     26 / 26")
            helper.simulateLine("The lizard woman attacked you with her spear for 7 damage!")
            local current, max = getVitality()
            assert.are.equal(19, current)
            assert.are.equal(26, max)
        end)

        it("does nothing when vitality is not yet known", function()
            helper.simulateLine("The lizard woman attacked you with her spear for 7 damage!")
            local current, _ = getVitality()
            assert.is_nil(current)
        end)

        it("stacks multiple hits", function()
            helper.simulateLine("Vitality:     26 / 26")
            helper.simulateLine("The lizard woman attacked you with her spear for 3 damage!")
            helper.simulateLine("The lizard woman attacked you with her spear for 7 damage!")
            local current, _ = getVitality()
            assert.are.equal(16, current)
        end)

    end)

    -- =========================================================================
    -- Status trigger
    -- =========================================================================

    describe("Status trigger", function()

        it("captures Healthy status", function()
            helper.simulateLine("Status:       Healthy")
            assert.are.equal("Healthy", getCharacterStatus())
        end)

        it("captures other status values", function()
            helper.simulateLine("Status:       Poisoned")
            assert.are.equal("Poisoned", getCharacterStatus())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Race:         Half-ogre")
            assert.is_nil(getCharacterStatus())
        end)

    end)

    -- =========================================================================
    -- Class trigger
    -- =========================================================================

    describe("Class trigger", function()

        it("captures class", function()
            helper.simulateLine("Class:        Warrior")
            assert.are.equal("Warrior", getClass())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Race:         Half-ogre")
            assert.is_nil(getClass())
        end)

    end)

    -- =========================================================================
    -- Level trigger
    -- =========================================================================

    describe("Level trigger", function()

        it("captures level", function()
            helper.simulateLine("Level:        1")
            assert.are.equal(1, getLevel())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Intellect:    8")
            assert.is_nil(getLevel())
        end)

    end)

    -- =========================================================================
    -- Experience trigger
    -- =========================================================================

    describe("Experience trigger", function()

        it("captures experience value", function()
            helper.simulateLine("Experience:   354")
            assert.are.equal(354, getExperience())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Intellect:    8")
            assert.is_nil(getExperience())
        end)

    end)

    -- =========================================================================
    -- Vitality trigger
    -- =========================================================================

    describe("Vitality trigger", function()

        it("captures current and max vitality", function()
            helper.simulateLine("Vitality:     26 / 26")
            local current, max = getVitality()
            assert.are.equal(26, current)
            assert.are.equal(26, max)
        end)

        it("captures when current differs from max", function()
            helper.simulateLine("Vitality:     10 / 26")
            local current, max = getVitality()
            assert.are.equal(10, current)
            assert.are.equal(26, max)
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Mana:         0 / 0")
            local current, max = getVitality()
            assert.is_nil(current)
            assert.is_nil(max)
        end)

    end)

    -- =========================================================================
    -- Status bar segments
    -- =========================================================================

    describe("status bar segments", function()

        local capturedFn

        before_each(function()
            helper.resetAll()
            -- Capture the function passed to setStatus
            _G.setStatus = function(fn) capturedFn = fn end
            dofile("main.lua")
        end)

        it("shows ? for all values when nothing captured yet", function()
            local segments = capturedFn()
            assert.are.equal("?", segments[2].text)   -- HP current
            assert.are.equal("?", segments[5].text)   -- XP current
            assert.are.equal("?", segments[8].text)   -- Status
            assert.are.equal("?", segments[10].text)  -- Gold
        end)

        it("shows current and max vitality in separate segments", function()
            helper.simulateLine("Vitality:     26 / 26")
            local segments = capturedFn()
            assert.are.equal("26",  segments[2].text)
            assert.are.equal("/ 26", segments[3].text)
            assert.are.equal("white", segments[3].fg)
        end)

        it("shows XP as current/nextLevel in separate segments", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   710")
            local segments = capturedFn()
            assert.are.equal("710",   segments[5].text)
            assert.are.equal("/ 1125", segments[6].text)
            assert.are.equal("white",  segments[6].fg)
        end)

        it("shows XP as current/max at max level", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   11594700")
            local segments = capturedFn()
            assert.are.equal("11594700", segments[5].text)
            assert.are.equal("/ max",     segments[6].text)
        end)

        it("shows captured Status value", function()
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("Healthy", segments[8].text)
        end)

        it("shows all values after a full status block", function()
            helper.simulateLine("Vitality:     10 / 26")
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   354")
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("10",    segments[2].text)
            assert.are.equal("/ 26",   segments[3].text)
            assert.are.equal("354",   segments[5].text)
            assert.are.equal("/ 1125", segments[6].text)
            assert.are.equal("Healthy", segments[8].text)
        end)

        it("colors vitality green at or above 66%", function()
            helper.simulateLine("Vitality:     26 / 26")  -- 100%
            assert.are.equal("green", capturedFn()[2].fg)
        end)

        it("colors vitality green at exactly 66%", function()
            helper.simulateLine("Vitality:     17 / 26")  -- ~65.4%, just below
            assert.are.equal("yellow", capturedFn()[2].fg)
            helper.resetAll()
            _G.setStatus = function(fn) capturedFn = fn end
            dofile("main.lua")
            helper.simulateLine("Vitality:     18 / 26")  -- ~69.2%, above
            assert.are.equal("green", capturedFn()[2].fg)
        end)

        it("colors vitality yellow between 33% and 66%", function()
            helper.simulateLine("Vitality:     13 / 26")  -- 50%
            assert.are.equal("yellow", capturedFn()[2].fg)
        end)

        it("colors vitality red below 33%", function()
            helper.simulateLine("Vitality:     8 / 26")  -- ~30.8%
            assert.are.equal("red", capturedFn()[2].fg)
        end)

        it("colors vitality white when not yet known", function()
            local segments = capturedFn()
            assert.are.equal("white", segments[2].fg)
        end)

    end)

end)

-- =========================================================================
-- Db module
-- =========================================================================

describe("Db", function()

    local Db
    local tmpPath = "./test/monsters_test_tmp.lua"

    before_each(function()
        Db = dofile("db.lua")
        os.remove(tmpPath)
    end)

    after_each(function()
        os.remove(tmpPath)
    end)

    it("returns empty table when file does not exist", function()
        local result = Db.load(tmpPath)
        assert.are.same({}, result)
    end)

    it("round-trips a monster record", function()
        local monsters = {
            ["giant bat"] = {
                description = "The giant bat has a wingspan of over twelve feet.",
                firstSeen = "2026-06-12",
                encounters = 3,
            }
        }
        Db.save(tmpPath, monsters)
        local loaded = Db.load(tmpPath)
        assert.are.equal("The giant bat has a wingspan of over twelve feet.", loaded["giant bat"].description)
        assert.are.equal("2026-06-12", loaded["giant bat"].firstSeen)
        assert.are.equal(3, loaded["giant bat"].encounters)
    end)

    it("round-trips multiple monster records", function()
        local monsters = {
            ["lizard woman"] = { description = "She has scaley skin.", firstSeen = "2026-06-12", encounters = 1 },
            ["giant bat"] = { description = "It has large wings.", firstSeen = "2026-06-12", encounters = 5 },
        }
        Db.save(tmpPath, monsters)
        local loaded = Db.load(tmpPath)
        assert.are.equal("She has scaley skin.", loaded["lizard woman"].description)
        assert.are.equal("It has large wings.", loaded["giant bat"].description)
    end)

    it("handles descriptions with commas and apostrophes", function()
        local monsters = {
            ["lizard woman"] = {
                description = "She has greyish scaley skin, and sharp claws and teeth.",
                firstSeen = "2026-06-12",
                encounters = 1,
            }
        }
        Db.save(tmpPath, monsters)
        local loaded = Db.load(tmpPath)
        assert.are.equal("She has greyish scaley skin, and sharp claws and teeth.", loaded["lizard woman"].description)
    end)

end)

-- =========================================================================
-- Monster database triggers
-- =========================================================================

describe("Monster database", function()

    local realIo

    before_each(function()
        helper.resetAll()
        -- Prevent file writes during trigger tests
        realIo = _G.io
        _G.io = { open = function() return nil end }
        dofile("main.lua")
    end)

    after_each(function()
        _G.io = realIo
    end)

    describe("look command", function()

        it("transitions to accumulating state", function()
            helper.simulateLine("l li")
            assert.are.equal("accumulating", getMonsterDbState())
        end)

        it("records the look target", function()
            helper.simulateLine("l li")
            assert.are.equal("li", taPackage.monsterDb.lookTarget)
        end)

        it("does not accumulate the echo line itself", function()
            helper.simulateLine("l li")
            assert.are.equal(0, #taPackage.monsterDb.accumulatedLines)
        end)

    end)

    describe("description accumulation", function()

        it("accumulates non-health lines", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            assert.are.equal(1, #taPackage.monsterDb.accumulatedLines)
            assert.are.equal("accumulating", getMonsterDbState())
        end)

        it("accumulates multiple lines", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid who's features")
            helper.simulateLine("resemble those of a large lizard.")
            assert.are.equal(2, #taPackage.monsterDb.accumulatedLines)
        end)

        it("finalizes on a wounded health line", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            assert.are.equal("idle", getMonsterDbState())
        end)

        it("extracts canonical name from description first line", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            assert.is_not_nil(getMonsterEntry("lizard woman"))
        end)

        it("does not include the health line in the description", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            local entry = getMonsterEntry("lizard woman")
            assert.is_nil(string.find(entry.description, "wounded"))
        end)

        it("joins multi-line description with spaces", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid who's features")
            helper.simulateLine("resemble those of a large lizard.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            local entry = getMonsterEntry("lizard woman")
            assert.are.equal(
                "The lizard woman is a five foot tall bipedal humanoid who's features resemble those of a large lizard.",
                entry.description
            )
        end)

        it("sets lastAttackTarget on finalization", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            assert.are.equal("lizard woman", taPackage.lastAttackTarget)
        end)

        it("miss after look uses lastAttackTarget set by look", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            helper.simulateLine("Your attack missed!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "MISS lizard woman") then found = true end
            end
            assert.is_true(found)
        end)

        it("aborts on room navigation line without saving", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("idle", getMonsterDbState())
            assert.is_nil(getMonsterEntry("lizard woman"))
        end)

        it("aborts on 'There is' line without saving", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("There is a blue robed priest here.")
            assert.are.equal("idle", getMonsterDbState())
            assert.is_nil(getMonsterEntry("lizard woman"))
        end)

        it("finalizes on 'falls to the ground lifeless' line", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman falls to the ground lifeless!")
            assert.are.equal("idle", getMonsterDbState())
            assert.is_not_nil(getMonsterEntry("lizard woman"))
        end)

    end)

    describe("second look", function()

        it("updates description and increments encounters", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid with sharp claws.")
            helper.simulateLine("The lizard woman is badly wounded.")
            local entry = getMonsterEntry("lizard woman")
            assert.are.equal(
                "The lizard woman is a five foot tall bipedal humanoid with sharp claws.",
                entry.description
            )
            assert.are.equal(2, entry.encounters)
        end)

    end)

    describe("room scan trigger", function()

        it("does not create a record for an unknown monster", function()
            helper.simulateLine("There is a blue robed priest here.")
            assert.is_nil(getMonsterEntry("blue robed priest"))
        end)

        it("increments encounters for a known monster", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            helper.simulateLine("There is a lizard woman here.")
            assert.are.equal(2, getMonsterEntry("lizard woman").encounters)
        end)

    end)

    describe("monster enters trigger", function()

        it("does not create a record for an unknown monster entering", function()
            helper.simulateLine("A lizard man enters the arena through the dungeon gate!")
            assert.is_nil(getMonsterEntry("lizard man"))
        end)

        it("increments encounters when a known monster enters", function()
            helper.simulateLine("l li")
            helper.simulateLine("The lizard man is a bipedal lizard humanoid.")
            helper.simulateLine("The lizard man is lightly wounded.")
            helper.simulateLine("A lizard man enters the arena through the dungeon gate!")
            assert.are.equal(2, getMonsterEntry("lizard man").encounters)
        end)

        it("handles 'An' prefix for monsters starting with a vowel", function()
            helper.simulateLine("l og")
            helper.simulateLine("The ogre is a large brutish humanoid.")
            helper.simulateLine("The ogre is lightly wounded.")
            helper.simulateLine("An ogre enters the arena through the dungeon gate!")
            assert.are.equal(2, getMonsterEntry("ogre").encounters)
        end)

    end)

end)

-- =========================================================================
-- ta_db module
-- =========================================================================

describe("ta_db", function()

    local TaDb

    before_each(function()
        helper.resetAll()
        TaDb = dofile("ta_db.lua")
        helper.clearDbCalls()
    end)

    describe("visitRoom", function()

        it("upserts via INSERT OR IGNORE then UPDATE", function()
            TaDb.visitRoom("north plaza", nil)
            assert.is_not_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO rooms"))
            assert.is_not_nil(helper.findDbCall("execute", "UPDATE rooms"))
        end)

        it("passes room name as first param to INSERT", function()
            TaDb.visitRoom("north plaza", nil)
            local call = helper.findDbCall("execute", "INSERT OR IGNORE INTO rooms")
            assert.are.equal("north plaza", call.params[1])
        end)

        it("echoes the room name", function()
            TaDb.visitRoom("north plaza", nil)
            assert.are.equal("[DB\xE2\x86\x92rooms] north plaza", helper.echoCalls[1])
        end)

    end)

    describe("recordExit", function()

        it("inserts an exit and echoes it", function()
            TaDb.recordExit("north plaza", "east", "arena")
            local call = helper.findDbCall("execute", "room_exits")
            assert.is_not_nil(call)
            assert.are.equal("north plaza", call.params[1])
            assert.are.equal("east", call.params[2])
            assert.are.equal("arena", call.params[3])
            assert.are.equal("[DB\xE2\x86\x92room_exits] north plaza --east--> arena", helper.echoCalls[1])
        end)

    end)

    describe("upsertMonster", function()

        it("upserts via INSERT OR IGNORE then UPDATE", function()
            TaDb.upsertMonster("lizard woman", "She has scaley skin.")
            assert.is_not_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO monsters"))
            local upd = helper.findDbCall("execute", "UPDATE monsters SET description")
            assert.is_not_nil(upd)
            assert.are.equal("She has scaley skin.", upd.params[1])
            assert.are.equal("lizard woman", upd.params[2])
        end)

        it("echoes the monster name", function()
            TaDb.upsertMonster("lizard woman", "She has scaley skin.")
            assert.are.equal("[DB\xE2\x86\x92monsters] lizard woman", helper.echoCalls[1])
        end)

    end)

    describe("recordMonsterSeen", function()

        it("does nothing when execute returns 0 rows changed (monster unknown)", function()
            TaDb.recordMonsterSeen("huge rat")
            assert.are.equal(0, #helper.echoCalls)
        end)

        it("echoes when execute returns rows changed (monster known)", function()
            helper.mockExecuteReturn = 1
            TaDb.recordMonsterSeen("huge rat")
            assert.are.equal("[DB\xE2\x86\x92monsters] seen: huge rat", helper.echoCalls[1])
        end)

    end)

    describe("recordPlayerAttack", function()

        it("records a hit and echoes damage", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "hit", 10)
            local call = helper.findDbCall("execute", "player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("Mace", call.params[1])
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("hit", call.params[3])
            assert.are.equal(10, call.params[4])
            assert.are.equal("[DB\xE2\x86\x92player_attacks] Mace HIT huge rat: 10 dmg", helper.echoCalls[1])
        end)

        it("records a miss and echoes without damage", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "miss", nil)
            assert.are.equal("[DB\xE2\x86\x92player_attacks] Mace MISS huge rat", helper.echoCalls[1])
        end)

        it("records a dodge", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "dodge", nil)
            assert.are.equal("[DB\xE2\x86\x92player_attacks] Mace DODGE huge rat", helper.echoCalls[1])
        end)

    end)

    describe("recordMonsterAttack", function()

        it("records a hit and echoes damage", function()
            TaDb.recordMonsterAttack("huge rat", "hit", 3)
            local call = helper.findDbCall("execute", "monster_attacks")
            assert.is_not_nil(call)
            assert.are.equal("[DB\xE2\x86\x92monster_attacks] huge rat HIT you: 3 dmg", helper.echoCalls[1])
        end)

        it("records a miss", function()
            TaDb.recordMonsterAttack("huge rat", "miss", nil)
            assert.are.equal("[DB\xE2\x86\x92monster_attacks] huge rat MISS", helper.echoCalls[1])
        end)

        it("records a glanced hit", function()
            TaDb.recordMonsterAttack("huge rat", "glanced", nil)
            assert.are.equal("[DB\xE2\x86\x92monster_attacks] huge rat GLANCED", helper.echoCalls[1])
        end)

    end)

    describe("recordMonsterLoot", function()

        it("records gold and echoes", function()
            TaDb.recordMonsterLoot("lizard woman", 4)
            local call = helper.findDbCall("execute", "monster_loot")
            assert.is_not_nil(call)
            assert.are.equal("lizard woman", call.params[1])
            assert.are.equal(4, call.params[2])
            assert.are.equal("[DB\xE2\x86\x92monster_loot] lizard woman: 4 gold", helper.echoCalls[1])
        end)

        it("records zero gold", function()
            TaDb.recordMonsterLoot("huge rat", 0)
            assert.are.equal("[DB\xE2\x86\x92monster_loot] huge rat: 0 gold", helper.echoCalls[1])
        end)

    end)

    describe("recordService", function()

        it("upserts via INSERT OR IGNORE then UPDATE", function()
            TaDb.recordService("healing", "temple", 2)
            assert.is_not_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO services"))
            assert.is_not_nil(helper.findDbCall("execute", "UPDATE services"))
            assert.are.equal("[DB\xE2\x86\x92services] temple: healing 2gp", helper.echoCalls[1])
        end)

    end)

    describe("recordStatChange", function()

        it("inserts a stat change and echoes", function()
            TaDb.recordStatChange("Level", 1, 2)
            local call = helper.findDbCall("execute", "stat_changes")
            assert.is_not_nil(call)
            assert.are.equal("Level", call.params[1])
            assert.are.equal(1, call.params[2])
            assert.are.equal(2, call.params[3])
        end)

    end)

end)

-- =========================================================================
-- main.lua triggers for world map and combat
-- =========================================================================

describe("World map triggers", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        helper.clearDbCalls()
    end)

    describe("room entry trigger", function()

        it("sets currentRoom", function()
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("north plaza", taPackage.currentRoom)
        end)

        it("calls visitRoom via echo", function()
            helper.simulateLine("You're in the north plaza.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "north plaza") then found = true end
            end
            assert.is_true(found)
        end)

        it("clears pendingDirection after entry", function()
            taPackage.pendingDirection = "n"
            helper.simulateLine("You're in the north plaza.")
            assert.is_nil(taPackage.pendingDirection)
        end)

        it("calls recordExit when pendingDirection and prevRoom are set", function()
            taPackage.currentRoom = "market"
            taPackage.pendingDirection = "north"
            taPackage.prevRoom = "market"
            helper.simulateLine("You're in the north plaza.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "room_exits") then found = true end
            end
            assert.is_true(found)
        end)

        it("records zero loot when monster died but no gold found before room change", function()
            taPackage.lastKilledMonster = "huge rat"
            taPackage.pendingLootCheck = true
            helper.simulateLine("You're in the north plaza.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "monster_loot") and string.find(msg, "huge rat") then found = true end
            end
            assert.is_true(found)
            assert.is_nil(taPackage.pendingLootCheck)
        end)

    end)

    describe("movement alias", function()

        it("sets pendingDirection when player moves north", function()
            helper.simulateAlias("n")
            assert.are.equal("n", taPackage.pendingDirection)
        end)

        it("sets prevRoom when player moves", function()
            taPackage.currentRoom = "market"
            helper.simulateAlias("e")
            assert.are.equal("market", taPackage.prevRoom)
        end)

        it("sends the movement command", function()
            helper.simulateAlias("s")
            assert.are.equal("s", helper.sendCalls[1])
        end)

    end)

end)

describe("Combat triggers", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        helper.clearDbCalls()
    end)

    describe("player attack outcomes", function()

        it("records a hit with damage", function()
            helper.simulateLine("Your attack hit the huge rat for 10 damage!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "HIT huge rat: 10 dmg") then found = true end
            end
            assert.is_true(found)
        end)

        it("records a miss using lastAttackTarget", function()
            taPackage.lastAttackTarget = "huge rat"
            helper.simulateLine("Your attack missed!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "MISS huge rat") then found = true end
            end
            assert.is_true(found)
        end)

        it("records a dodge", function()
            helper.simulateLine("The huge rat dodged your attack!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "DODGE huge rat") then found = true end
            end
            assert.is_true(found)
        end)

    end)

    describe("monster attack outcomes", function()

        it("records a hit and reduces vitality", function()
            helper.simulateLine("Vitality:     26 / 26")
            helper.simulateLine("The lizard woman attacked you with her spear for 7 damage!")
            local current, _ = getVitality()
            assert.are.equal(19, current)
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "HIT you: 7 dmg") then found = true end
            end
            assert.is_true(found)
        end)

        it("stacks multiple monster hits", function()
            helper.simulateLine("Vitality:     26 / 26")
            helper.simulateLine("The lizard woman attacked you with her spear for 3 damage!")
            helper.simulateLine("The lizard woman attacked you with her spear for 7 damage!")
            local current, _ = getVitality()
            assert.are.equal(16, current)
        end)

        it("records a glance", function()
            helper.simulateLine("The huge rat attacked you, but its claws glanced off your armor!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "GLANCED") then found = true end
            end
            assert.is_true(found)
        end)

        it("records a miss", function()
            helper.simulateLine("The huge rat's claws misses you!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "MISS") then found = true end
            end
            assert.is_true(found)
        end)

    end)

    describe("kill and loot", function()

        it("sets lastKilledMonster when monster dies", function()
            helper.simulateLine("The huge rat falls to the ground lifeless!")
            assert.are.equal("huge rat", taPackage.lastKilledMonster)
            assert.is_true(taPackage.pendingLootCheck)
        end)

        it("records loot gold and clears kill state", function()
            helper.simulateLine("The huge rat falls to the ground lifeless!")
            helper.simulateLine("You found 3 gold crowns while searching the huge rat's corpse.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "monster_loot") and string.find(msg, "huge rat") then found = true end
            end
            assert.is_true(found)
            assert.is_nil(taPackage.lastKilledMonster)
            assert.is_nil(taPackage.pendingLootCheck)
        end)

    end)

    describe("services", function()

        it("records healing service and echoes", function()
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if msg == "[DB\xE2\x86\x92services] temple: healing 2gp" then found = true end
            end
            assert.is_true(found)
        end)

        it("records barmaid drink service and echoes", function()
            helper.simulateLine("The barmaid brings you a drink for 1 crowns.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if msg == "[DB\xE2\x86\x92services] tavern: drink 1gp" then found = true end
            end
            assert.is_true(found)
        end)

    end)

    describe("stat changes", function()

        it("records a level-up", function()
            helper.simulateLine("Level:        1")
            helper.simulateLine("Level:        2")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "stat_changes") and string.find(msg, "Level") then found = true end
            end
            assert.is_true(found)
        end)

        it("does not record a stat change on first level reading", function()
            helper.simulateLine("Level:        1")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "stat_changes") then found = true end
            end
            assert.is_false(found)
        end)

    end)

end)
