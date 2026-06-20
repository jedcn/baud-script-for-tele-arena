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
            assert.are.equal("white", capturedFn()[6].fg)
        end)

        it("shows cyan in the second fifth", function()
            helper.simulateLine("Experience:   225")  -- 20% of 1125
            assert.are.equal("cyan", capturedFn()[6].fg)
        end)

        it("shows green in the third fifth", function()
            helper.simulateLine("Experience:   450")  -- 40% of 1125
            assert.are.equal("green", capturedFn()[6].fg)
        end)

        it("shows yellow in the fourth fifth", function()
            helper.simulateLine("Experience:   675")  -- 60% of 1125
            assert.are.equal("yellow", capturedFn()[6].fg)
        end)

        it("shows red in the fifth fifth (almost leveled up)", function()
            helper.simulateLine("Experience:   900")  -- 80% of 1125
            assert.are.equal("red", capturedFn()[6].fg)
        end)

        it("shows red at max level", function()
            helper.simulateLine("Experience:   11594700")
            assert.are.equal("red", capturedFn()[6].fg)
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

        it("decreases gold when depositing at vault", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            helper.simulateLine("You deposited 300 gold in your account.")
            assert.are.equal(455, getGold())
        end)

        it("increases gold when withdrawing from vault", function()
            helper.simulateLine("You are carrying 100 gold crowns.")
            helper.simulateLine("You withdrew 1 gold from your account.")
            assert.are.equal(101, getGold())
        end)

        it("decreases gold when buying an item from a shop", function()
            helper.simulateLine("You are carrying 100 gold crowns.")
            helper.simulateLine("Ok, you bought a quarterstaff for 9 crowns.")
            assert.are.equal(91, getGold())
        end)

        it("handles a multi-word item name when buying", function()
            helper.simulateLine("You are carrying 100 gold crowns.")
            helper.simulateLine("Ok, you bought robes for 18 crowns.")
            assert.are.equal(82, getGold())
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
    -- Incoming minor heal from another player trigger
    -- =========================================================================

    describe("Incoming minor heal from another player trigger", function()

        it("increases current vitality by healed amount", function()
            helper.simulateLine("Vitality:     20 / 26")
            helper.simulateLine("Pelayo just intoned a minor healing spell for you which healed 6 damage!")
            local current, max = getVitality()
            assert.are.equal(26, current)
            assert.are.equal(26, max)
        end)

        it("does not exceed max vitality", function()
            helper.simulateLine("Vitality:     24 / 26")
            helper.simulateLine("Pelayo just intoned a minor healing spell for you which healed 6 damage!")
            local current, _ = getVitality()
            assert.are.equal(26, current)
        end)

        it("works when max vitality is not yet known", function()
            helper.simulateLine("Vitality:     20 / 26")
            taPackage.character.vitalityMax = nil
            helper.simulateLine("Pelayo just intoned a minor healing spell for you which healed 6 damage!")
            local current, _ = getVitality()
            assert.are.equal(26, current)
        end)

    end)

    -- =========================================================================
    -- Incoming heal from another player trigger
    -- =========================================================================

    describe("Incoming heal from another player trigger", function()

        it("increases current vitality by healed amount", function()
            helper.simulateLine("Vitality:     8 / 26")
            helper.simulateLine("Pelayo just intoned a healing spell for you which healed 14 damage!")
            local current, max = getVitality()
            assert.are.equal(22, current)
            assert.are.equal(26, max)
        end)

        it("does not exceed max vitality", function()
            helper.simulateLine("Vitality:     24 / 26")
            helper.simulateLine("Pelayo just intoned a healing spell for you which healed 14 damage!")
            local current, _ = getVitality()
            assert.are.equal(26, current)
        end)

        it("works when max vitality is not yet known", function()
            helper.simulateLine("Vitality:     8 / 26")
            taPackage.character.vitalityMax = nil
            helper.simulateLine("Pelayo just intoned a healing spell for you which healed 14 damage!")
            local current, _ = getVitality()
            assert.are.equal(22, current)
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
            assert.are.equal("?", segments[1].text)   -- Name
            assert.are.equal("?", segments[3].text)   -- HP current
            -- MP hidden when mana max is nil
            assert.are.equal("?", segments[6].text)   -- XP current
            assert.are.equal("?", segments[9].text)   -- Status
            assert.are.equal("?", segments[11].text)  -- Gold
        end)

        it("shows player name in first segment when class is unknown", function()
            taPackage.character.name = "Sat"
            assert.are.equal("Sat", capturedFn()[1].text)
        end)

        it("shows name and class in first segment when both known", function()
            taPackage.character.name = "Pelayo"
            helper.simulateLine("Class:        Acolyte")
            assert.are.equal("Pelayo [Acolyte]", capturedFn()[1].text)
        end)

        it("appends follow target when following someone", function()
            taPackage.character.name = "Pelayo"
            helper.simulateLine("Class:        Acolyte")
            taPackage.followTarget = "tojolias"
            assert.are.equal("Pelayo [Acolyte] Following Tojolias", capturedFn()[1].text)
        end)

        it("appends Leader (N) when being followed", function()
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Class:        Warrior")
            taPackage.followedBy = { "Pelayo" }
            assert.are.equal("Tojolias [Warrior] Leader (1)", capturedFn()[1].text)
        end)

        it("shows correct count with multiple followers", function()
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Class:        Warrior")
            taPackage.followedBy = { "Pelayo", "Sat", "Grog" }
            assert.are.equal("Tojolias [Warrior] Leader (3)", capturedFn()[1].text)
        end)

        it("shows current and max vitality in separate segments", function()
            helper.simulateLine("Vitality:     26 / 26")
            local segments = capturedFn()
            assert.are.equal("26",  segments[3].text)
            assert.are.equal("/ 26", segments[4].text)
            assert.are.equal("white", segments[4].fg)
        end)

        it("shows XP as current/nextLevel in separate segments", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   710")
            local segments = capturedFn()
            assert.are.equal("710",    segments[6].text)   -- no MP, XP at [6]
            assert.are.equal("/ 1125", segments[7].text)
            assert.are.equal("white",  segments[7].fg)
        end)

        it("shows XP as current/max at max level", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   11594700")
            local segments = capturedFn()
            assert.are.equal("11594700", segments[6].text)  -- no MP, XP at [6]
            assert.are.equal("/ max",    segments[7].text)
        end)

        it("shows captured Status value", function()
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("Healthy", segments[9].text)   -- no MP, Status at [9]
        end)

        it("colors status red when Thirsty", function()
            helper.simulateLine("Status:       Thirsty")
            assert.are.equal("red", capturedFn()[9].fg)
        end)

        it("colors status red when Hungry", function()
            helper.simulateLine("Status:       Hungry")
            assert.are.equal("red", capturedFn()[9].fg)
        end)

        it("colors status white when Healthy", function()
            helper.simulateLine("Status:       Healthy")
            assert.are.equal("white", capturedFn()[9].fg)
        end)

        it("colors gold amount yellow", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            assert.are.equal("yellow", capturedFn()[11].fg)
        end)

        it("colors MP label green and values cyan", function()
            helper.simulateLine("Mana:         2 / 3")
            local segments = capturedFn()
            assert.are.equal("green", segments[5].fg)  -- "MP:" label
            assert.are.equal("cyan",  segments[6].fg)  -- current
            assert.are.equal("cyan",  segments[7].fg)  -- "/ max"
        end)

        it("shows all values after a full status block", function()
            helper.simulateLine("Vitality:     10 / 26")
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   354")
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("10",      segments[3].text)
            assert.are.equal("/ 26",    segments[4].text)
            assert.are.equal("354",     segments[6].text)   -- no MP, XP at [6]
            assert.are.equal("/ 1125",  segments[7].text)
            assert.are.equal("Healthy", segments[9].text)   -- Status at [9]
        end)

        it("colors vitality green at or above 66%", function()
            helper.simulateLine("Vitality:     26 / 26")  -- 100%
            assert.are.equal("green", capturedFn()[3].fg)
        end)

        it("colors vitality green at exactly 66%", function()
            helper.simulateLine("Vitality:     17 / 26")  -- ~65.4%, just below
            assert.are.equal("yellow", capturedFn()[3].fg)
            helper.resetAll()
            _G.setStatus = function(fn) capturedFn = fn end
            dofile("main.lua")
            helper.simulateLine("Vitality:     18 / 26")  -- ~69.2%, above
            assert.are.equal("green", capturedFn()[3].fg)
        end)

        it("colors vitality yellow between 33% and 66%", function()
            helper.simulateLine("Vitality:     13 / 26")  -- 50%
            assert.are.equal("yellow", capturedFn()[3].fg)
        end)

        it("colors vitality red below 33%", function()
            helper.simulateLine("Vitality:     8 / 26")  -- ~30.8%
            assert.are.equal("red", capturedFn()[3].fg)
        end)

        it("colors vitality white when not yet known", function()
            local segments = capturedFn()
            assert.are.equal("white", segments[3].fg)
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

        it("transitions to accumulating state with 'look' prefix", function()
            helper.simulateLine("look li")
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

        it("does not accumulate the 'look' echo line itself", function()
            helper.simulateLine("look li")
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

        it("strips split health-line fragment when server breaks the line mid-sentence", function()
            -- The server can split "seems to be in good physical health." across two lines.
            -- The fragment "The skeleton warrior seems to be in" ends up accumulated as a
            -- description line; it must be stripped before saving.
            helper.simulateLine("l war")
            helper.simulateLine("The skeleton warrior is wearing tattered armor and mouldering bits of old")
            helper.simulateLine("clothing, and is armed with a shortsword. The skeleton warrior seems to be in")
            helper.simulateLine("good physical health.")
            local entry = getMonsterEntry("skeleton warrior")
            assert.are.equal(
                "The skeleton warrior is wearing tattered armor and mouldering bits of old clothing, and is armed with a shortsword.",
                entry.description
            )
        end)

        it("uses health-line name for gendered variants ('female orc' vs 'orc')", function()
            -- Game describes female orc as "The orc is a smallish humanoid..." but the
            -- health sentence says "The female orc seems to be in good physical health."
            -- The health sentence is the authoritative name source.
            helper.simulateLine("look female")
            helper.simulateLine("The orc is a smallish humanoid with piglike facial features and is covered")
            helper.simulateLine("sparsely by coarse body hair. She stands just over four feet in height, is")
            helper.simulateLine("wearing a leather tunic, and is armed with a dagger. The female orc seems to be in good physical health.")
            local entry = getMonsterEntry("female orc")
            assert.is_not_nil(entry, "monster should be stored under 'female orc'")
        end)

        it("extracts correct name when monster description starts with 'has ... has'", function()
            -- "The giant bat has a wingspan ... and has wicked looking" -- greedy matching
            -- would capture "giant bat has a wingspan ... and" as the name. Non-greedy
            -- must stop at the first ' has '.
            helper.simulateLine("look bat")
            helper.simulateLine("The giant bat has a wingspan of over twelve feet and has wicked looking")
            helper.simulateLine("claws and teeth. The giant bat seems to be in good physical health.")
            local entry = getMonsterEntry("giant bat")
            assert.is_not_nil(entry, "monster should be stored under 'giant bat'")
            assert.are.equal(
                "The giant bat has a wingspan of over twelve feet and has wicked looking claws and teeth.",
                entry.description
            )
        end)

        it("extracts correct name when description uses 'resembles' instead of 'is'/'has'", function()
            -- "The huge rat resembles rats you've seen before, except that it is about
            -- two feet tall" -- without 'resembles' in the verb list, the ' is ' later
            -- in the sentence would capture a huge wrong chunk as the name.
            helper.simulateLine("l rat")
            helper.simulateLine("The huge rat resembles rats you've seen before, except that it is about")
            helper.simulateLine("two feet tall at the shoulder. The huge rat is lightly wounded.")
            local entry = getMonsterEntry("huge rat")
            assert.is_not_nil(entry, "monster should be stored under 'huge rat'")
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
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("lizard woman", call.params[2])
            assert.are.equal("miss", call.params[3])
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

        it("does not double-count when re-entering the same room within an hour", function()
            taPackage.currentRoom = "arena"
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            helper.simulateLine("There is a lizard woman here.")
            helper.simulateLine("There is a lizard woman here.")
            assert.are.equal(2, getMonsterEntry("lizard woman").encounters)
        end)

        it("counts as new encounter after kill clears presence", function()
            taPackage.currentRoom = "arena"
            helper.simulateLine("l li")
            helper.simulateLine("The lizard woman is a five foot tall bipedal humanoid.")
            helper.simulateLine("The lizard woman is lightly wounded.")
            helper.simulateLine("There is a lizard woman here.")
            helper.simulateLine("The lizard woman falls to the ground lifeless!")
            helper.simulateLine("There is a lizard woman here.")
            assert.are.equal(3, getMonsterEntry("lizard woman").encounters)
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

        it("does not double-count if the same monster is seen entering without a kill", function()
            taPackage.currentRoom = "arena"
            helper.simulateLine("l li")
            helper.simulateLine("The lizard man is a bipedal lizard humanoid.")
            helper.simulateLine("The lizard man is lightly wounded.")
            helper.simulateLine("A lizard man enters the arena through the dungeon gate!")
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
-- Arena combat (class-based action)
-- =========================================================================

describe("Arena combat", function()

    local realIo

    before_each(function()
        helper.resetAll()
        realIo = _G.io
        _G.io = { open = function() return nil end }
        dofile("main.lua")
    end)

    after_each(function()
        _G.io = realIo
    end)

    local function lastSend()
        return helper.sendCalls[#helper.sendCalls]
    end

    describe("Sorceror", function()

        before_each(function()
            setClass("Sorceror")
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
        end)

        it("re-casts komiza after a successful discharge", function()
            helper.simulateLine("You discharged the spell at the lizard man for 12 damage!")
            assert.are.equal("cast komiza lizard", lastSend())
        end)

        it("re-casts komiza after a fizzle", function()
            helper.simulateLine("You confuse the key syllables and the spell fails!")
            assert.are.equal("cast komiza lizard", lastSend())
        end)

        it("re-casts komiza after a resist", function()
            helper.simulateLine("Your spell was negated by the lizard man's magickal defenses!")
            assert.are.equal("cast komiza lizard", lastSend())
        end)

        it("clears the pending flag on mental exhaustion", function()
            taPackage.arenaAttackPending = true
            helper.simulateLine("You are still too mentally exhausted from your last incantation!")
            assert.is_false(taPackage.arenaAttackPending)
        end)

    end)

    describe("non-Sorceror", function()

        it("attacks normally for a Warrior", function()
            setClass("Warrior")
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            helper.simulateLine("Your sword hit the lizard man for 5 damage!")
            assert.are.equal("a lizard", lastSend())
        end)

    end)

    describe("loop guard", function()

        it("does not continue the spell loop outside arena fighting", function()
            setClass("Sorceror")
            -- no arenaState set
            helper.simulateLine("You discharged the spell at the lizard man for 12 damage!")
            assert.are.equal(0, #helper.sendCalls)
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

        it("records a hit", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "hit", 10)
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("Mace", call.params[1])
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("hit", call.params[3])
            assert.are.equal(10, call.params[4])
        end)

        it("records a miss", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "miss", nil)
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("miss", call.params[3])
        end)

        it("records a dodge", function()
            TaDb.recordPlayerAttack("Mace", "huge rat", "dodge", nil)
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("dodge", call.params[3])
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

    describe("recordPlayerSpell", function()

        it("records a hit with amount", function()
            TaDb.recordPlayerSpell("komiza", "huge rat", "hit", 7)
            local call = helper.findDbCall("execute", "INSERT INTO player_spells")
            assert.is_not_nil(call)
            assert.are.equal("komiza", call.params[1])
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("hit", call.params[3])
            assert.are.equal(7, call.params[4])
        end)

        it("records a miss with no amount", function()
            TaDb.recordPlayerSpell("komiza", "huge rat", "miss", nil)
            local call = helper.findDbCall("execute", "INSERT INTO player_spells")
            assert.is_not_nil(call)
            assert.are.equal("miss", call.params[3])
            assert.is_nil(call.params[4])
        end)

        it("echoes with amount when present", function()
            TaDb.recordPlayerSpell("motu", "pelayo", "hit", 10)
            assert.are.equal("[DB\xE2\x86\x92player_spells] motu \xE2\x86\x92 pelayo [hit] 10", helper.echoCalls[1])
        end)

        it("echoes without amount when nil", function()
            TaDb.recordPlayerSpell("komiza", "huge rat", "miss", nil)
            assert.are.equal("[DB\xE2\x86\x92player_spells] komiza \xE2\x86\x92 huge rat [miss]", helper.echoCalls[1])
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

-- =========================================================================
-- Re-roll for good stats
-- =========================================================================

describe("re-roll-for-good-stats", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    describe("Physique trigger", function()

        it("captures physique value", function()
            helper.simulateLine("Physique:     24")
            assert.are.equal(24, getPhysique())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Stamina:      24")
            assert.is_nil(getPhysique())
        end)

    end)

    describe("Stamina trigger", function()

        it("captures stamina value", function()
            helper.simulateLine("Stamina:      24")
            assert.are.equal(24, getStamina())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Physique:     24")
            assert.is_nil(getStamina())
        end)

    end)

    describe("alias", function()

        it("sets reRolling to true", function()
            helper.simulateAlias("re-roll-for-good-stats")
            assert.is_true(taPackage.reRolling)
        end)

        it("sends 'status'", function()
            helper.simulateAlias("re-roll-for-good-stats")
            assert.are.equal("status", helper.sendCalls[1])
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
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("hit", call.params[3])
            assert.are.equal(10, call.params[4])
        end)

        it("records a miss using lastAttackTarget", function()
            taPackage.lastAttackTarget = "huge rat"
            helper.simulateLine("Your attack missed!")
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("miss", call.params[3])
        end)

        it("records a dodge", function()
            helper.simulateLine("The huge rat dodged your attack!")
            local call = helper.findDbCall("execute", "INSERT INTO player_attacks")
            assert.is_not_nil(call)
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("dodge", call.params[3])
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

        it("records a player dodge", function()
            helper.simulateLine("You barely dodge the huge rat's attack!")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "DODGE") then found = true end
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

        it("records barmaid meal service and echoes", function()
            helper.simulateLine("The barmaid brings you a meal for 2 crowns.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if msg == "[DB\xE2\x86\x92services] tavern: meal 2gp" then found = true end
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

        local attributeStats = { "Physique", "Stamina", "Agility", "Charisma", "Intellect", "Knowledge" }

        for _, stat in ipairs(attributeStats) do
            it("records a " .. stat .. " increase", function()
                helper.simulateLine(stat .. ":      16")
                helper.simulateLine(stat .. ":      17")
                local found = false
                for _, msg in ipairs(helper.echoCalls) do
                    if string.find(msg, "stat_changes") and string.find(msg, stat) then found = true end
                end
                assert.is_true(found)
            end)

            it("does not record " .. stat .. " change on first reading", function()
                helper.simulateLine(stat .. ":      16")
                local found = false
                for _, msg in ipairs(helper.echoCalls) do
                    if string.find(msg, "stat_changes") and string.find(msg, stat) then found = true end
                end
                assert.is_false(found)
            end)

            it("does not record " .. stat .. " change during re-rolling", function()
                helper.simulateAlias("re-roll-for-good-stats")
                helper.simulateLine(stat .. ":      16")
                helper.simulateLine(stat .. ":      17")
                local found = false
                for _, msg in ipairs(helper.echoCalls) do
                    if string.find(msg, "stat_changes") and string.find(msg, stat) then found = true end
                end
                assert.is_false(found)
            end)
        end

    end)

end)

-- =========================================================================
-- Ring gong and fight in arena
-- =========================================================================

describe("ring-gong-and-fight-in-arena", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        helper.clearDbCalls()
        setClass("Warrior")
    end)

    local function setHP(current, max)
        helper.simulateLine("Vitality:     " .. current .. " / " .. (max or current))
    end

    describe("alias", function()

        it("sets arenaState to 'ringing'", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("ringing", taPackage.arenaState)
        end)

        it("sends 'ring gong'", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("ring gong", helper.sendCalls[1])
        end)

        it("records session start XP from current experience", function()
            taPackage.character.experience = 500
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal(500, taPackage.arenaSessionStartXp)
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.is_nil(taPackage.arenaState)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Class unknown") then warned = true end
            end
            assert.is_true(warned)
        end)

        it("records session start time", function()
            local before = os.time()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            local after = os.time()
            assert.is_true(taPackage.arenaSessionStartTime >= before)
            assert.is_true(taPackage.arenaSessionStartTime <= after)
        end)

        it("bumps arenaXpTimerGen to cancel any prior timer", function()
            taPackage.arenaXpTimerGen = 3
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal(4, taPackage.arenaXpTimerGen)
        end)

        it("echoes session start with XP", function()
            taPackage.character.experience = 1000
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Session started") and string.find(msg, "1000") then
                    found = true
                end
            end
            assert.is_true(found)
        end)

    end)

    describe("stop alias", function()

        it("clears arenaState", function()
            taPackage.arenaState = "fighting"
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            assert.is_nil(taPackage.arenaState)
        end)

        it("clears arenaMonster", function()
            taPackage.arenaMonster = "lizard man"
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            assert.is_nil(taPackage.arenaMonster)
        end)

        it("clears arenaLastCmd", function()
            taPackage.arenaLastCmd = "a lizard"
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            assert.is_nil(taPackage.arenaLastCmd)
        end)

        it("clears session tracking state", function()
            taPackage.arenaSessionStartXp = 500
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            assert.is_nil(taPackage.arenaSessionStartXp)
            assert.is_nil(taPackage.arenaSessionStartTime)
        end)

        it("bumps arenaXpTimerGen to cancel pending timer", function()
            taPackage.arenaXpTimerGen = 2
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            assert.are.equal(3, taPackage.arenaXpTimerGen)
        end)

        it("echoes session summary with XP gained and elapsed minutes", function()
            taPackage.arenaSessionStartXp = 400
            taPackage.arenaSessionStartTime = os.time() - 600  -- 10 minutes ago
            taPackage.character = { experience = 1400 }
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "+1000 XP") and string.find(msg, "10 minutes") then
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("skips summary when no session was started", function()
            taPackage.arenaSessionStartXp = nil
            helper.simulateAlias("stop-ring-gong-and-fight-in-arena")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Session over") then found = true end
            end
            assert.is_false(found)
        end)

    end)

    describe("XP check timer", function()

        local timerCreated

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
            setClass("Warrior")
            _G.createTimer = function(interval, cb, opts)
                timerCreated = { interval = interval, cb = cb, opts = opts }
                return "mock_timer"
            end
            timerCreated = nil
        end)

        it("schedules a 5-minute timer on session start", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.is_not_nil(timerCreated)
            assert.are.equal(300000, timerCreated.interval)
        end)

        it("timer callback sends status", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            timerCreated.cb()
            local found = false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "status" then found = true end
            end
            assert.is_true(found)
        end)

        it("timer callback sets arenaXpCheckPending", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            timerCreated.cb()
            assert.is_true(taPackage.arenaXpCheckPending)
        end)

        it("timer callback does nothing when generation has changed", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            local cb = timerCreated.cb
            taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
            cb()
            assert.is_nil(taPackage.arenaXpCheckPending or nil)
        end)

        it("XP trigger echoes delta when arenaXpCheckPending is set", function()
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time() - 300
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   800")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "+500") then found = true end
            end
            assert.is_true(found)
        end)

        it("XP trigger clears arenaXpCheckPending after echoing", function()
            taPackage.arenaXpCheckPending = true
            taPackage.arenaSessionStartXp = 0
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateLine("Experience:   100")
            assert.is_false(taPackage.arenaXpCheckPending)
        end)

        it("XP trigger does not echo when arenaXpCheckPending is not set", function()
            local before = #helper.echoCalls
            taPackage.arenaXpCheckPending = false
            helper.simulateLine("Experience:   100")
            assert.are.equal(before, #helper.echoCalls)
        end)

    end)

    describe("monster enters arena", function()

        it("captures monster name and starts fighting", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("A skeleton warrior enters the arena through the dungeon gate!")
            assert.are.equal("skeleton warrior", taPackage.arenaMonster)
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        it("sends abbreviated attack using first word", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "A skeleton warrior." }
            helper.simulateLine("A skeleton warrior enters the arena through the dungeon gate!")
            assert.are.equal("a skeleton", helper.sendCalls[1])
        end)

        it("sends abbreviated attack for single-word monster", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "An ogre." }
            helper.simulateLine("An ogre enters the arena through the dungeon gate!")
            assert.are.equal("a ogre", helper.sendCalls[1])
        end)

        it("does nothing when not in ringing state", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("A skeleton warrior enters the arena through the dungeon gate!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("looks at monster before attacking when description is unknown", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = nil
            helper.simulateLine("A huge rat enters the arena through the dungeon gate!")
            assert.are.equal("look huge rat", helper.sendCalls[1])
            assert.are.equal("a huge", helper.sendCalls[2])
        end)

        it("skips look when description is already known", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "A huge rat scurries about." }
            helper.simulateLine("A huge rat enters the arena through the dungeon gate!")
            assert.are.equal("a huge", helper.sendCalls[1])
            assert.is_nil(helper.sendCalls[2])
        end)

        it("skips look when description field is empty string", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "" }
            helper.simulateLine("A huge rat enters the arena through the dungeon gate!")
            assert.are.equal("look huge rat", helper.sendCalls[1])
            assert.are.equal("a huge", helper.sendCalls[2])
        end)

    end)

    describe("our attack results", function()

        it("sends next attack after a hit (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("sends next attack after an adjective-qualified hit (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("Your skillful attack hit the lizard man for 10 damage!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("flees when HP < 50 after a hit", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(15, 100)
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("sends next attack after a miss (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("Your attack missed!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("flees when HP < 50 after a miss", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(10, 100)
            helper.simulateLine("Your attack missed!")
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("sends next attack after monster dodge (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("The lizard man dodged your attack!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("does nothing when not in fighting state", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("Your attack missed!")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("monster death", function()

        it("clears arenaMonster", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.is_nil(taPackage.arenaMonster)
        end)

        it("rings gong again when HP is fine", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("ring gong", helper.sendCalls[1])
        end)

        it("flees when HP < 50 on monster death", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(15, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("does nothing when not in fighting state", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("goes to train when XP has crossed the next level threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("training", taPackage.arenaState)
            assert.are.equal(1, taPackage.arenaTrainingPhase)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("rings gong when XP is below next level threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(60, 100)
            taPackage.character.experience = 500
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("ring gong", helper.sendCalls[1])
        end)

    end)

    describe("auto-training", function()

        it("goes north when arriving at north plaza in training state", function()
            taPackage.arenaState = "training"
            taPackage.arenaTrainingPhase = 1
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal(2, taPackage.arenaTrainingPhase)
            assert.are.equal("n", helper.sendCalls[1])
        end)

        it("buys training and goes south when arriving at training hall", function()
            taPackage.arenaState = "training"
            taPackage.arenaTrainingPhase = 2
            helper.simulateLine("You're in the training hall.")
            local boughtTraining = false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "buy training" then boughtTraining = true end
            end
            assert.is_true(boughtTraining)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("switches to returning state after buying training", function()
            taPackage.arenaState = "training"
            taPackage.arenaTrainingPhase = 2
            helper.simulateLine("You're in the training hall.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.is_nil(taPackage.arenaTrainingPhase)
        end)

    end)

    describe("incoming monster attack", function()

        it("flees when HP drops below 50", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            -- simulate vitality already at 45 (existing trigger already decremented it)
            setHP(45, 100)
            helper.simulateLine("The lizard man attacked you with his scimitar for 13 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("counter-attacks when HP is still fine after monster hit", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("The lizard man attacked you with his scimitar for 2 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("counter-attacks after a glancing blow", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            helper.simulateLine("The lizard man attacked you, but his scimitar glanced off your armor!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("counter-attacks after monster misses", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            helper.simulateLine("The lizard man's poorly executed attack misses you!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("counter-attacks after player dodges monster attack", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            helper.simulateLine("You barely dodge the lizard man's attack!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("does not counter-attack from glance when not fighting", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaMonster = "lizard man"
            helper.simulateLine("The lizard man attacked you, but his scimitar glanced off your armor!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("sends only one attack when monster attacks twice in the same round", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("The lizard man attacked you with his scimitar for 2 damage!")
            helper.simulateLine("The lizard man attacked you, but his scimitar glanced off your armor!")
            local count = 0
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "a lizard" then count = count + 1 end
            end
            assert.are.equal(1, count)
        end)

    end)

    describe("fleeing and healing", function()

        it("continues west when entering north plaza while fleeing", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("buys healing when entering temple while fleeing", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You're in the temple.")
            assert.are.equal("healing", taPackage.arenaState)
            assert.are.equal("buy healing", helper.sendCalls[1])
        end)

        it("schedules a retry and stays fleeing when cannot leave in heat of battle", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You cannot leave in the heat of battle!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)  -- no immediate send
            assert.is_true(taPackage.arenaFleeTimerPending)
        end)

        it("does not stack multiple retries for repeated cannot-leave messages", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You cannot leave in the heat of battle!")
            helper.simulateLine("You cannot leave in the heat of battle!")
            helper.simulateLine("You cannot leave in the heat of battle!")
            assert.are.equal(0, #helper.sendCalls)
            assert.is_true(taPackage.arenaFleeTimerPending)
        end)

        it("starts returning east after healing", function()
            taPackage.arenaState = "healing"
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("e", helper.sendCalls[1])
        end)

        it("continues east when entering north plaza while returning", function()
            taPackage.arenaState = "returning"
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("e", helper.sendCalls[1])
        end)

        it("rings gong when entering arena and no monster left", function()
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = nil
            helper.simulateLine("You're in the arena.")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("ring gong", helper.sendCalls[1])
        end)

        it("resumes attacking when entering arena and monster still alive", function()
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = "cave bear"
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("ignores room entries in other states", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("thirsty and hungry during arena", function()

        it("departs for tavern immediately when thirsty while fighting", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
            assert.is_true(taPackage.needsDrinks)
        end)

        it("departs for tavern immediately when hungry while fighting", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're hungry.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
            assert.is_true(taPackage.needsMeal)
        end)

        it("departs for tavern immediately when thirsty while ringing", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("does not depart again when second need fires after already heading to tavern", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")
            helper.sendCalls = {}
            helper.simulateLine("You're hungry.")
            assert.are.equal(0, #helper.sendCalls)
            assert.is_true(taPackage.needsMeal)
        end)

        it("just sets flag when thirsty while fleeing", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
            assert.is_true(taPackage.needsDrinks)
        end)

        it("goes to tavern state after healing when thirsty", function()
            taPackage.arenaState = "healing"
            taPackage.needsDrinks = true
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("e", helper.sendCalls[1])
        end)

        it("buys 3 drinks when entering tavern with needsDrinks", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy drink", helper.sendCalls[1])
            assert.are.equal("buy drink", helper.sendCalls[2])
            assert.are.equal("buy drink", helper.sendCalls[3])
            assert.is_nil(taPackage.needsDrinks)
        end)

        it("buys 3 meals when entering tavern with needsMeal", function()
            taPackage.arenaState = "tavern"
            taPackage.needsMeal = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy meal", helper.sendCalls[1])
            assert.are.equal("buy meal", helper.sendCalls[2])
            assert.are.equal("buy meal", helper.sendCalls[3])
            assert.is_nil(taPackage.needsMeal)
        end)

        it("buys both drinks and meals when both needed", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            taPackage.needsMeal = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy drink", helper.sendCalls[1])
            assert.are.equal("buy drink", helper.sendCalls[2])
            assert.are.equal("buy drink", helper.sendCalls[3])
            assert.are.equal("buy meal", helper.sendCalls[4])
            assert.are.equal("buy meal", helper.sendCalls[5])
            assert.are.equal("buy meal", helper.sendCalls[6])
        end)

        it("schedules a retry and stays in tavern state when cannot leave in heat of battle", function()
            taPackage.arenaState = "tavern"
            helper.simulateLine("You cannot leave in the heat of battle!")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)  -- no immediate send
            assert.is_true(taPackage.arenaFleeTimerPending)
        end)

        it("navigates north plaza -> ne -> tavern when in tavern state", function()
            taPackage.arenaState = "tavern"
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("ne", helper.sendCalls[1])
        end)

        it("departs tavern sw and transitions to returning", function()
            taPackage.arenaState = "tavern"
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

    end)

    describe("healing trigger ignored outside arena script", function()

        it("does not affect state when arenaState is not healing", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("rate limiting", function()

        local timerCreated

        before_each(function()
            helper.resetAll()
            _G.createTimer = function(interval, cb, opts)
                timerCreated = { interval = interval, cb = cb, opts = opts }
                return "mock_timer"
            end
            dofile("main.lua")
            helper.clearDbCalls()
            timerCreated = nil
        end)

        it("creates 30s timer on move-rate-limit when arena is active", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_not_nil(timerCreated)
            assert.are.equal(30000, timerCreated.interval)
        end)

        it("creates 30s timer on attack-rate-limit when arena is active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaLastCmd = "a skeleton"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.is_not_nil(timerCreated)
            assert.are.equal(30000, timerCreated.interval)
        end)

        it("does not create timer when arenaState is nil", function()
            taPackage.arenaState = nil
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_nil(timerCreated)
        end)

        it("does not create timer for exhaustion when arenaState is nil", function()
            taPackage.arenaState = nil
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.is_nil(timerCreated)
        end)

        it("timer callback sends command when arenaState is still active at fire time", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_not_nil(timerCreated)
            helper.sendCalls = {}
            timerCreated.cb()
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("timer callback sends nothing when arenaState is nil at fire time (stop after rate limit)", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_not_nil(timerCreated)
            taPackage.arenaState = nil
            helper.sendCalls = {}
            timerCreated.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("exhaustion timer callback sends nothing when arenaState is nil at fire time", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaLastCmd = "a skeleton"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.is_not_nil(timerCreated)
            taPackage.arenaState = nil
            helper.sendCalls = {}
            timerCreated.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("second exhaustion message creates a timer that does not fire (generation mismatch)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaLastCmd = "a skeleton"
            -- First exhaustion: creates timer with current generation
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local firstTimer = timerCreated
            assert.is_not_nil(firstTimer)
            -- Second exhaustion: creates another timer with same generation
            timerCreated = nil
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local secondTimer = timerCreated
            assert.is_not_nil(secondTimer)
            -- First timer fires and sends (increments generation)
            helper.sendCalls = {}
            firstTimer.cb()
            assert.are.equal("a skeleton", helper.sendCalls[1])
            -- Second timer fires but generation has moved on — sends nothing
            helper.sendCalls = {}
            secondTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("timer does not fire after a new command supersedes it (generation mismatch)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            taPackage.arenaLastCmd = "a cave"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local staleTimer = timerCreated
            -- Monster dies; arena sends "ring gong", incrementing generation
            helper.simulateLine("The cave bear falls to the ground lifeless!")
            helper.sendCalls = {}
            -- Stale timer fires — generation mismatch, should not send
            staleTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

    end)

end)

describe("cast.heal alias", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sends cast kamotu <character name> with no argument", function()
        taPackage.character.name = "Pelayo"
        helper.simulateAlias("cast.heal")
        assert.are.equal("cast kamotu pelayo", helper.sendCalls[1])
    end)

    it("lowercases the character name", function()
        taPackage.character.name = "Tojolias"
        helper.simulateAlias("cast.heal")
        assert.are.equal("cast kamotu tojolias", helper.sendCalls[1])
    end)

    it("sends nothing when no argument and character name is unknown", function()
        taPackage.character.name = nil
        helper.simulateAlias("cast.heal")
        assert.are.equal(0, #helper.sendCalls)
    end)

    it("sends cast kamotu <target> with one argument", function()
        helper.simulateAlias("cast.heal tojolias")
        assert.are.equal("cast kamotu tojolias", helper.sendCalls[1])
    end)

    it("sends cast kamotu <target> regardless of character name", function()
        taPackage.character.name = "Pelayo"
        helper.simulateAlias("cast.heal tojolias")
        assert.are.equal("cast kamotu tojolias", helper.sendCalls[1])
    end)

end)

describe("cast.minor.heal alias", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sends cast motu <character name> with no argument", function()
        taPackage.character.name = "Pelayo"
        helper.simulateAlias("cast.minor.heal")
        assert.are.equal("cast motu pelayo", helper.sendCalls[1])
    end)

    it("lowercases the character name", function()
        taPackage.character.name = "Tojolias"
        helper.simulateAlias("cast.minor.heal")
        assert.are.equal("cast motu tojolias", helper.sendCalls[1])
    end)

    it("sends nothing when no argument and character name is unknown", function()
        taPackage.character.name = nil
        helper.simulateAlias("cast.minor.heal")
        assert.are.equal(0, #helper.sendCalls)
    end)

    it("sends cast motu <target> with one argument", function()
        helper.simulateAlias("cast.minor.heal tojolias")
        assert.are.equal("cast motu tojolias", helper.sendCalls[1])
    end)

    it("sends cast motu <target> regardless of character name", function()
        taPackage.character.name = "Pelayo"
        helper.simulateAlias("cast.minor.heal tojolias")
        assert.are.equal("cast motu tojolias", helper.sendCalls[1])
    end)

end)

describe("cast.ice.dart alias", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sends cast komiza <target>", function()
        helper.simulateAlias("cast.ice.dart tojolias")
        assert.are.equal("cast komiza tojolias", helper.sendCalls[1])
    end)

end)

describe("cast komiza outbound trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("decrements manaCurrent by 1", function()
        helper.simulateLine("Mana:         10 / 20")
        helper.simulateOutbound("cast komiza tojolias")
        assert.are.equal(9, taPackage.character.manaCurrent)
    end)

    it("does not reduce manaCurrent below 0", function()
        helper.simulateLine("Mana:         0 / 20")
        helper.simulateOutbound("cast komiza tojolias")
        assert.are.equal(0, taPackage.character.manaCurrent)
    end)

    it("does nothing when manaCurrent is unknown", function()
        helper.simulateOutbound("cast komiza tojolias")
        assert.is_nil(taPackage.character.manaCurrent)
    end)

end)

describe("motu inbound trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("records the spell cast via recordPlayerSpell", function()
        helper.simulateLine("You intoned the spell for pelayo which healed 10 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("motu", call.params[1])
        assert.are.equal("pelayo", call.params[2])
        assert.are.equal("hit", call.params[3])
        assert.are.equal(10, call.params[4])
    end)

    it("parses target and amount from the line", function()
        helper.simulateLine("You intoned the spell for tojolias which healed 5 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("tojolias", call.params[2])
        assert.are.equal(5, call.params[4])
    end)

end)

describe("spell discharge trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.lastSpellCast = "komiza"
    end)

    it("records a hit with monster and damage", function()
        helper.simulateLine("You discharged the spell at the skeleton warrior for 8 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("komiza", call.params[1])
        assert.are.equal("skeleton warrior", call.params[2])
        assert.are.equal("hit", call.params[3])
        assert.are.equal(8, call.params[4])
    end)

    it("updates lastAttackTarget on hit", function()
        helper.simulateLine("You discharged the spell at the giant bat for 5 damage!")
        assert.are.equal("giant bat", taPackage.lastAttackTarget)
    end)

    it("falls back to 'unknown' spell when lastSpellCast is nil", function()
        taPackage.lastSpellCast = nil
        helper.simulateLine("You discharged the spell at the imp for 3 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.are.equal("unknown", call.params[1])
    end)

end)

describe("spell fizzle trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.lastSpellCast = "komiza"
        taPackage.lastAttackTarget = "skeleton warrior"
    end)

    it("records a fizzle using lastAttackTarget", function()
        helper.simulateLine("You confuse the key syllables and the spell fails!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("komiza", call.params[1])
        assert.are.equal("skeleton warrior", call.params[2])
        assert.are.equal("fizzle", call.params[3])
        assert.is_nil(call.params[4])
    end)

    it("falls back to 'unknown' monster when lastAttackTarget is nil", function()
        taPackage.lastAttackTarget = nil
        helper.simulateLine("You confuse the key syllables and the spell fails!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.are.equal("unknown", call.params[2])
    end)

end)

describe("spell resist trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.lastSpellCast = "komiza"
    end)

    it("records a resist with monster name from line", function()
        helper.simulateLine("Your spell was negated by the giant bat's magickal defenses!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("komiza", call.params[1])
        assert.are.equal("giant bat", call.params[2])
        assert.are.equal("resist", call.params[3])
        assert.is_nil(call.params[4])
    end)

    it("updates lastAttackTarget on resist", function()
        helper.simulateLine("Your spell was negated by the imp's magickal defenses!")
        assert.are.equal("imp", taPackage.lastAttackTarget)
    end)

end)

describe("cast komiza outbound sets lastSpellCast", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sets lastSpellCast to komiza", function()
        helper.simulateOutbound("cast komiza skel")
        assert.are.equal("komiza", taPackage.lastSpellCast)
    end)

end)

-- =========================================================================
-- Follow
-- =========================================================================

describe("ta.follow", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    describe("ta.follow alias", function()

        it("sets followTarget to lowercase target name", function()
            helper.simulateAlias("ta.follow tojolias")
            assert.are.equal("tojolias", taPackage.followTarget)
        end)

        it("lowercases a mixed-case target name", function()
            helper.simulateAlias("ta.follow Tojolias")
            assert.are.equal("tojolias", taPackage.followTarget)
        end)

        it("echoes confirmation", function()
            helper.simulateAlias("ta.follow tojolias")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "tojolias") then found = true end
            end
            assert.is_true(found)
        end)

        it("sends 'join <target>' via game", function()
            helper.simulateAlias("ta.follow tojolias")
            assert.are.equal("join tojolias", helper.sendCalls[1])
        end)

    end)

    describe("join request trigger (received by leader)", function()

        it("adds to followedBy list when join request received", function()
            helper.simulateLine("Pelayo is asking to join your group.")
            assert.are.equal("Pelayo", taPackage.followedBy[1])
        end)

        it("accumulates multiple followers", function()
            helper.simulateLine("Pelayo is asking to join your group.")
            helper.simulateLine("Sat is asking to join your group.")
            assert.are.equal(2, #taPackage.followedBy)
            assert.are.equal("Pelayo", taPackage.followedBy[1])
            assert.are.equal("Sat", taPackage.followedBy[2])
        end)

        it("sends 'add <name>' in response", function()
            helper.simulateLine("Pelayo is asking to join your group.")
            assert.are.equal("add pelayo", helper.sendCalls[1])
        end)

        it("echoes who is now following", function()
            helper.simulateLine("Pelayo is asking to join your group.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Pelayo") and string.find(msg, "following") then found = true end
            end
            assert.is_true(found)
        end)

    end)

    describe("ta.follow-stop alias", function()

        it("clears followTarget", function()
            taPackage.followTarget = "tojolias"
            helper.simulateAlias("ta.follow-stop")
            assert.is_nil(taPackage.followTarget)
        end)

        it("echoes confirmation", function()
            helper.simulateAlias("ta.follow-stop")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Stopped") then found = true end
            end
            assert.is_true(found)
        end)

    end)

    describe("departure trigger", function()

        it("sends 'e' when followed character goes east", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone to the east.")
            assert.are.equal("e", helper.sendCalls[1])
        end)

        it("sends 'ne' when followed character goes northeast", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone to the northeast.")
            assert.are.equal("ne", helper.sendCalls[1])
        end)

        it("sends 'n' when followed character goes north", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone to the north.")
            assert.are.equal("n", helper.sendCalls[1])
        end)

        it("sends 'sw' when followed character goes southwest", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone to the southwest.")
            assert.are.equal("sw", helper.sendCalls[1])
        end)

        it("sends 'u' when followed character goes upward", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone upward.")
            assert.are.equal("u", helper.sendCalls[1])
        end)

        it("sends 'd' when followed character goes downward", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Tojolias has just gone downward.")
            assert.are.equal("d", helper.sendCalls[1])
        end)

        it("does nothing on upward when followTarget not set", function()
            helper.simulateLine("Tojolias has just gone upward.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing on downward when a different character leaves", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Pelayo has just gone downward.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when a different character leaves", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("Pelayo has just gone to the east.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when followTarget is not set", function()
            helper.simulateLine("Tojolias has just gone to the east.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("matches case-insensitively (capitalized game output)", function()
            helper.simulateAlias("ta.follow tojolias")
            helper.sendCalls = {}
            helper.simulateLine("Tojolias has just gone to the west.")
            assert.are.equal("w", helper.sendCalls[1])
        end)

    end)

    describe("group attack trigger", function()

        before_each(function()
            setClass("Warrior")
            taPackage.followTarget = "tojolias"
        end)

        it("starts the kill loop on the leader's target", function()
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            assert.is_true(taPackage.killActive)
            assert.are.equal("huge rat", taPackage.killTarget)
            assert.are.equal("a huge", helper.sendCalls[1])
        end)

        it("matches the leader case-insensitively", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("TOJOLIAS just attacked the huge rat with a flail!")
            assert.is_true(taPackage.killActive)
        end)

        it("does nothing when the attacker is not the leader", function()
            helper.simulateLine("Pelayo just attacked the huge rat with a sword!")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when not following anyone", function()
            taPackage.followTarget = nil
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does not restart when already killing", function()
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            local generation = taPackage.killGeneration
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            assert.are.equal(generation, taPackage.killGeneration)
        end)

        it("stops when the monster dies, even if another player kills it", function()
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            helper.simulateLine("The huge rat falls to the ground lifeless!")
            assert.is_falsy(taPackage.killActive)
            assert.is_nil(taPackage.killTarget)
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
            assert.is_falsy(taPackage.killActive)
        end)

        it("starts when a monster dodges the leader's attack", function()
            helper.simulateLine("The hobgoblin barely dodged Tojolias's flail!")
            assert.is_true(taPackage.killActive)
            assert.are.equal("hobgoblin", taPackage.killTarget)
            assert.are.equal("a hobgoblin", helper.sendCalls[1])
        end)

        it("does nothing on a dodge of a non-leader's attack", function()
            helper.simulateLine("The hobgoblin barely dodged Pelayo's sword!")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("kill alias", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
            setClass("Warrior")
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateAlias("kill cave lizard")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Class unknown") then warned = true end
            end
            assert.is_true(warned)
        end)

        it("sends attack on start", function()
            helper.simulateAlias("kill cave lizard")
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("uses first word of multi-word target", function()
            helper.simulateAlias("kill lizard man")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("sets killActive and killTarget", function()
            helper.simulateAlias("kill cave lizard")
            assert.is_true(taPackage.killActive)
            assert.are.equal("cave lizard", taPackage.killTarget)
        end)

        it("continues attacking after a hit", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("Your attack hit the cave lizard for 8 damage!")
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("continues attacking after a miss", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("Your attack missed!")
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("continues attacking after monster dodge", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("The cave lizard dodged your attack!")
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("continues attacking after player dodge", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("You barely dodge the cave lizard's attack!")
            assert.are.equal("a cave", helper.sendCalls[1])
        end)

        it("stops and echoes done when monster dies", function()
            helper.simulateAlias("kill cave lizard")
            helper.simulateLine("The cave lizard falls to the ground lifeless!")
            assert.is_falsy(taPackage.killActive)
            assert.is_nil(taPackage.killTarget)
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "dead") then found = true end
            end
            assert.is_true(found)
        end)

        it("kill-stop clears state", function()
            helper.simulateAlias("kill cave lizard")
            helper.simulateAlias("kill-stop")
            assert.is_falsy(taPackage.killActive)
            assert.is_nil(taPackage.killTarget)
        end)

        it("does not start when arena session is active", function()
            taPackage.arenaState = "fighting"
            helper.sendCalls = {}
            helper.simulateAlias("kill cave lizard")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("sends only one attack when pending flag is set", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            -- simulate two rapid hit lines before pending clears
            taPackage.killAttackPending = true
            helper.simulateLine("Your attack hit the cave lizard for 8 damage!")
            -- pending was cleared by hit trigger, one attack re-sent
            local count = 0
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "a cave" then count = count + 1 end
            end
            assert.are.equal(1, count)
        end)

        describe("Sorceror", function()

            before_each(function()
                setClass("Sorceror")
            end)

            it("casts komiza on start instead of attacking", function()
                helper.simulateAlias("kill cave lizard")
                assert.are.equal("cast komiza cave", helper.sendCalls[1])
            end)

            it("re-casts after a successful discharge", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You discharged the spell at the cave lizard for 8 damage!")
                assert.are.equal("cast komiza cave", helper.sendCalls[1])
            end)

            it("re-casts after a fizzle", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You confuse the key syllables and the spell fails!")
                assert.are.equal("cast komiza cave", helper.sendCalls[1])
            end)

            it("re-casts after a resist", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("Your spell was negated by the cave lizard's magickal defenses!")
                assert.are.equal("cast komiza cave", helper.sendCalls[1])
            end)

            it("clears the pending flag on mental exhaustion", function()
                helper.simulateAlias("kill cave lizard")
                taPackage.killAttackPending = true
                helper.simulateLine("You are still too mentally exhausted from your last incantation!")
                assert.is_false(taPackage.killAttackPending)
            end)

        end)

    end)

end)
