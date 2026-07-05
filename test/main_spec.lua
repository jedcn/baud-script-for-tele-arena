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

        it("shows light blue at 0% (just started level)", function()
            helper.simulateLine("Experience:   0")
            assert.are.equal("#66b3ff", capturedFn()[6].fg)
        end)

        it("shows blue-violet in the second fifth", function()
            helper.simulateLine("Experience:   225")  -- 20% of 1125
            assert.are.equal("#9b8cff", capturedFn()[6].fg)
        end)

        it("shows purple/magenta in the third fifth", function()
            helper.simulateLine("Experience:   450")  -- 40% of 1125
            assert.are.equal("#e066e0", capturedFn()[6].fg)
        end)

        it("shows pink-red in the fourth fifth", function()
            helper.simulateLine("Experience:   675")  -- 60% of 1125
            assert.are.equal("#ff6699", capturedFn()[6].fg)
        end)

        it("shows red in the fifth fifth (almost leveled up)", function()
            helper.simulateLine("Experience:   900")  -- 80% of 1125
            assert.are.equal("#ff6666", capturedFn()[6].fg)
        end)

        it("shows red at max level", function()
            helper.simulateLine("Experience:   11594700")
            assert.are.equal("#ff6666", capturedFn()[6].fg)
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

        it("decreases gold when giving coins to another player", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            helper.simulateLine("You gave 100 gold coins to Johnsonite.")
            assert.are.equal(655, getGold())
        end)

        it("increases gold when another player gives you coins", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            helper.simulateLine("Teekywiki just gave you 32 gold coins.")
            assert.are.equal(787, getGold())
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

        it("reduces vitality for a stone giant's boulder", function()
            helper.simulateLine("Vitality:     80 / 80")
            helper.simulateLine("The stone giant hurled a boulder at you for 52 damage!")
            local current, max = getVitality()
            assert.are.equal(28, current)
            assert.are.equal(80, max)
        end)

        it("reduces vitality for a cyclops's throw", function()
            helper.simulateLine("Vitality:     50 / 50")
            helper.simulateLine("The cyclops picks up and hurls you for 22 damage!")
            local current, _ = getVitality()
            assert.are.equal(28, current)
        end)

        it("reduces vitality for a chimera's flame breath", function()
            helper.simulateLine("Vitality:     80 / 80")
            helper.simulateLine("The chimera breathed flames at you for 27 damage!")
            local current, max = getVitality()
            assert.are.equal(53, current)
            assert.are.equal(80, max)
        end)

        it("ignores a boulder thrown at another player", function()
            helper.simulateLine("Vitality:     80 / 80")
            helper.simulateLine("The stone giant hurled a boulder at Pelayo!")
            local current, _ = getVitality()
            assert.are.equal(80, current)
        end)

        it("ignores flames breathed at another player", function()
            helper.simulateLine("Vitality:     80 / 80")
            helper.simulateLine("The chimera breathed flames at Pelayo!")
            local current, _ = getVitality()
            assert.are.equal(80, current)
        end)

    end)

    -- =========================================================================
    -- Entering Tele-Arena trigger
    -- =========================================================================

    describe("Entering Tele-Arena trigger", function()

        it("runs st then i on entering", function()
            helper.simulateLine("Entering Tele-Arena...")
            assert.are.equal("st", helper.sendCalls[1])
            assert.are.equal("i", helper.sendCalls[2])
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Entering the arena gates...")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    -- =========================================================================
    -- Buy passage trigger
    -- =========================================================================

    describe("Buy passage trigger", function()

        it("sends i after boarding the ship", function()
            helper.simulateLine("You buy passage across the great lake and board a ship...")
            assert.are.equal("i", helper.sendCalls[1])
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("You board a ship at the docks.")
            assert.are.equal(0, #helper.sendCalls)
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
    -- Level-up notification
    -- =========================================================================

    describe("Level-up notification", function()

        it("pushes when XP crosses the next-level threshold", function()
            taPackage.character.class = "Warrior"
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Experience:   792683")  -- seeds earned level 12
            assert.are.equal(0, #helper.httpRequestCalls)
            helper.simulateLine("Experience:   815600")  -- level-13 threshold
            assert.are.equal(1, #helper.httpRequestCalls)
            local call = helper.httpRequestCalls[1]
            assert.are.equal("https://ntfy.sh/s5bbs-tele-arena-j5", call.url)
            assert.are.equal("Time to Level Up!", call.options.headers["X-Title"])
            assert.are.equal(
                "Tojolias just passed 815,600 and is ready to train for level 13",
                call.options.body)
        end)

        it("stays silent on the first XP observation", function()
            taPackage.character.class = "Warrior"
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Experience:   815600")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("does not re-fire while XP stays within the same level", function()
            taPackage.character.class = "Warrior"
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Experience:   792683")  -- seeds earned level 12
            helper.simulateLine("Experience:   815600")  -- crosses to level 13
            assert.are.equal(1, #helper.httpRequestCalls)
            helper.simulateLine("Experience:   900000")  -- still level 13
            assert.are.equal(1, #helper.httpRequestCalls)
        end)

        it("does nothing when the class is unknown", function()
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Experience:   792683")
            helper.simulateLine("Experience:   815600")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

    end)

    describe("formatWithCommas", function()

        it("groups thousands with commas", function()
            assert.are.equal("620,046", formatWithCommas(620046))
            assert.are.equal("1,000,000", formatWithCommas(1000000))
        end)

        it("leaves values under 1000 unchanged", function()
            assert.are.equal("313", formatWithCommas(313))
            assert.are.equal("0", formatWithCommas(0))
        end)

        it("accepts numeric strings", function()
            assert.are.equal("620,046", formatWithCommas("620046"))
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

        it("shows only name and class when following someone", function()
            taPackage.character.name = "Pelayo"
            helper.simulateLine("Class:        Acolyte")
            taPackage.followTarget = "tojolias"
            assert.are.equal("Pelayo [Acolyte]", capturedFn()[1].text)
        end)

        it("appends a bare Leader tag when being followed", function()
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Class:        Warrior")
            taPackage.followedBy = { "Pelayo" }
            assert.are.equal("Tojolias [Warrior] Leader", capturedFn()[1].text)
        end)

        it("shows the same Leader tag regardless of follower count", function()
            taPackage.character.name = "Tojolias"
            helper.simulateLine("Class:        Warrior")
            taPackage.followedBy = { "Pelayo", "Sat", "Grog" }
            assert.are.equal("Tojolias [Warrior] Leader", capturedFn()[1].text)
        end)

        it("does not show Leader while following, even with a stale followedBy", function()
            taPackage.character.name = "Johnsonite"
            helper.simulateLine("Class:        Sorceror")
            taPackage.followTarget = "pelayo"
            taPackage.followedBy = { "Grog" }
            assert.are.equal("Johnsonite [Sorceror]", capturedFn()[1].text)
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
            assert.are.equal("710",     segments[6].text)   -- no MP, XP at [6]
            assert.are.equal("/ 1,125", segments[7].text)
            assert.are.equal("white",  segments[7].fg)
        end)

        it("shows XP as current/max at max level", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   11594700")
            local segments = capturedFn()
            assert.are.equal("11,594,700", segments[6].text)  -- no MP, XP at [6]
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

        it("formats large gold amounts with commas", function()
            helper.simulateLine("You are carrying 1234567 gold crowns.")
            assert.are.equal("1,234,567", capturedFn()[11].text)
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
            assert.are.equal("/ 1,125", segments[7].text)
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

        it("re-casts toduza after a successful discharge", function()
            helper.simulateLine("You discharged the spell at the lizard man for 12 damage!")
            assert.are.equal("cast toduza lizard", lastSend())
        end)

        it("re-casts toduza after a fizzle", function()
            helper.simulateLine("You confuse the key syllables and the spell fails!")
            assert.are.equal("cast toduza lizard", lastSend())
        end)

        it("re-casts toduza after a resist", function()
            helper.simulateLine("Your spell was negated by the lizard man's magickal defenses!")
            assert.are.equal("cast toduza lizard", lastSend())
        end)

        it("also melees on a physical hit, independent of the cast loop", function()
            helper.simulateLine("Your dagger hit the lizard man for 3 damage!")
            assert.are.equal("a lizard", lastSend())
        end)

        it("melees and casts toduza when a monster enters", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = true
            taPackage.arenaMonster = nil
            helper.sendCalls = {}
            helper.simulateLine("A lizard man enters the arena through the dungeon gate!")
            local melee, cast = false, false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "a lizard" then melee = true end
                if cmd == "cast toduza lizard" then cast = true end
            end
            assert.is_true(melee)
            assert.is_true(cast)
        end)

        it("clears the cast pending flag on mental exhaustion", function()
            taPackage.arenaCastPending = true
            helper.simulateLine("You are still too mentally exhausted from your last incantation!")
            assert.is_false(taPackage.arenaCastPending)
        end)

        it("clears the attack pending flag on physical exhaustion", function()
            taPackage.arenaAttackPending = true
            helper.simulateLine("You are still physically exhausted from your previous activities!")
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
        TaDb.debug = true
        helper.clearDbCalls()
    end)

    describe("slugForName", function()

        it("returns the base slug when it is unused", function()
            helper.mockDbOneRow = nil  -- every collision probe finds nothing
            assert.are.equal("north-plaza", TaDb.slugForName("north plaza"))
        end)

        it("suffixes the lowest free -N when the base is taken", function()
            -- Probe returns a row for cave and cave-1, nothing for cave-2.
            helper.mockDbOneRow = function(_, params)
                local slug = params[1]
                if slug == "cave" or slug == "cave-1" then return { n = 1 } end
                return nil
            end
            assert.are.equal("cave-2", TaDb.slugForName("cave"))
        end)

    end)

    describe("discoverRoom", function()

        it("inserts the room and returns its new id", function()
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM rooms WHERE slug", 1, true) then
                    return { id = 6 }
                end
                return nil  -- slug is free
            end
            local id = TaDb.discoverRoom("cave", 3)
            assert.are.equal(6, id)
            local ins = helper.findDbCall("execute", "INSERT INTO rooms")
            assert.is_not_nil(ins)
            assert.are.equal("cave", ins.params[1])  -- slug
            assert.are.equal("cave", ins.params[2])  -- name
            assert.are.equal(3, ins.params[3])       -- area_id
        end)

    end)

    describe("exitDestination", function()

        it("returns the recorded destination id", function()
            helper.mockDbOneRow = { to_id = 5 }
            assert.are.equal(5, TaDb.exitDestination(2, "ne"))
        end)

        it("returns nil for an unexplored (NULL) or missing exit", function()
            helper.mockDbOneRow = { to_id = nil }
            assert.is_nil(TaDb.exitDestination(2, "ne"))
            helper.mockDbOneRow = nil
            assert.is_nil(TaDb.exitDestination(2, "w"))
        end)

    end)

    describe("linkExit", function()

        it("upserts a concrete edge", function()
            TaDb.linkExit(5, "ne", 6)
            local call = helper.findDbCall("execute", "INSERT OR REPLACE INTO room_exits")
            assert.is_not_nil(call)
            assert.are.equal(5, call.params[1])
            assert.are.equal("ne", call.params[2])
            assert.are.equal(6, call.params[3])
        end)

    end)

    describe("recordKnownExit", function()

        it("seeds a NULL-destination stub without clobbering", function()
            TaDb.recordKnownExit(5, "w")
            local call = helper.findDbCall("execute", "INSERT OR IGNORE INTO room_exits")
            assert.is_not_nil(call)
            assert.are.equal(5, call.params[1])
            assert.are.equal("w", call.params[2])
        end)

    end)

    describe("ensureArea", function()

        it("inserts if absent and returns the id", function()
            helper.mockDbOneRow = { id = 3 }
            local id = TaDb.ensureArea("first-town", "First Town")
            assert.are.equal(3, id)
            local ins = helper.findDbCall("execute", "INSERT OR IGNORE INTO areas")
            assert.are.equal("first-town", ins.params[1])
            assert.are.equal("First Town", ins.params[2])
        end)

    end)

    describe("findRoomByFingerprint", function()

        -- Stub roomIdsByName and roomExitDirections per query. `existing` maps a
        -- room id to its recorded exit-direction list.
        local function stubRooms(name, ids, existing)
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE name", 1, true) then
                    local rows = {}
                    for _, id in ipairs(ids) do rows[#rows + 1] = { id = id } end
                    return rows
                elseif string.find(sql, "SELECT direction FROM room_exits WHERE from_id", 1, true) then
                    local rows = {}
                    for _, dir in ipairs(existing[params[1]] or {}) do
                        rows[#rows + 1] = { direction = dir }
                    end
                    return rows
                end
                return {}
            end
        end

        it("matches an existing room with the same name and exit-set", function()
            stubRooms("north plaza", { 1, 5 }, { [1] = { "n", "s", "e" } })
            assert.are.equal(1, TaDb.findRoomByFingerprint("north plaza", { "e", "n", "s" }, 5))
        end)

        it("does not match when the exit-set differs (distinct caves)", function()
            stubRooms("cave", { 1, 5 }, { [1] = { "n", "s" } })
            assert.is_nil(TaDb.findRoomByFingerprint("cave", { "n", "s", "e" }, 5))
        end)

        it("returns nil when more than one room matches (ambiguous)", function()
            stubRooms("cave", { 1, 2, 5 }, { [1] = { "n", "s" }, [2] = { "n", "s" } })
            assert.is_nil(TaDb.findRoomByFingerprint("cave", { "n", "s" }, 5))
        end)

    end)

    describe("mergeRoomInto", function()

        it("repoints edges, carries visits, and deletes the provisional room", function()
            -- Provisional room 5 has one outgoing edge 5 --nw--> 4.
            helper.mockDbRows = function(sql)
                if string.find(sql, "SELECT direction, to_id FROM room_exits WHERE from_id", 1, true) then
                    return { { direction = "nw", to_id = 4 } }
                end
                return {}
            end
            TaDb.mergeRoomInto(5, 1)

            local moved = helper.findDbCall("execute", "INSERT OR IGNORE INTO room_exits")
            assert.are.same({ 1, "nw", 4 }, moved.params)  -- outgoing edge moved onto room 1
            assert.is_not_nil(helper.findDbCall("execute", "DELETE FROM room_exits WHERE from_id"))
            local repoint = helper.findDbCall("execute", "SET to_id = ? WHERE to_id")
            assert.are.same({ 1, 5 }, repoint.params)      -- inbound edges now point at 1
            local del = helper.findDbCall("execute", "DELETE FROM rooms WHERE id")
            assert.are.equal(5, del.params[1])
        end)

        it("never creates a self-loop when folding a reverse back-edge", function()
            -- Provisional #5's only edge is its back-edge 5 --sw--> 1 (the merge
            -- target). Naive repointing would make 1 --sw--> 1.
            helper.mockDbRows = function(sql)
                if string.find(sql, "SELECT direction, to_id FROM room_exits WHERE from_id", 1, true) then
                    return { { direction = "sw", to_id = 1 } }
                end
                return {}
            end
            TaDb.mergeRoomInto(5, 1)

            -- No outgoing edge is re-added pointing room 1 at itself.
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute"
                    and string.find(c.sql, "INSERT OR IGNORE INTO room_exits", 1, true) then
                    assert.is_false(c.params[1] == c.params[3])  -- from_id ~= to_id
                end
            end
            -- Inbound edges from the target are reset to unexplored stubs, not looped.
            local reset = helper.findDbCall("execute", "SET to_id = NULL WHERE from_id")
            assert.are.same({ 1, 5 }, reset.params)
        end)

        it("carries the provisional's description onto the target", function()
            helper.mockDbRows = function() return {} end
            TaDb.mergeRoomInto(5, 1)
            local desc = helper.findDbCall("execute", "SET description = COALESCE")
            assert.is_not_nil(desc)
            assert.are.same({ 5, 1 }, desc.params)  -- COALESCE(target, provisional #5) into #1
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
            TaDb.recordPlayerSpell("toduza", "huge rat", "hit", 7)
            local call = helper.findDbCall("execute", "INSERT INTO player_spells")
            assert.is_not_nil(call)
            assert.are.equal("toduza", call.params[1])
            assert.are.equal("huge rat", call.params[2])
            assert.are.equal("hit", call.params[3])
            assert.are.equal(7, call.params[4])
        end)

        it("records a miss with no amount", function()
            TaDb.recordPlayerSpell("toduza", "huge rat", "miss", nil)
            local call = helper.findDbCall("execute", "INSERT INTO player_spells")
            assert.is_not_nil(call)
            assert.are.equal("miss", call.params[3])
            assert.is_nil(call.params[4])
        end)

        it("stores kind as the last bound parameter", function()
            TaDb.recordPlayerSpell("kamotu", "pelayo", "hit", 12, "heal")
            local call = helper.findDbCall("execute", "INSERT INTO player_spells")
            assert.is_not_nil(call)
            assert.are.equal("heal", call.params[6])
        end)

        it("echoes with amount when present", function()
            TaDb.recordPlayerSpell("motu", "pelayo", "hit", 10)
            assert.are.equal("[DB\xE2\x86\x92player_spells] motu \xE2\x86\x92 pelayo [hit] 10", helper.echoCalls[1])
        end)

        it("echoes without amount when nil", function()
            TaDb.recordPlayerSpell("toduza", "huge rat", "miss", nil)
            assert.are.equal("[DB\xE2\x86\x92player_spells] toduza \xE2\x86\x92 huge rat [miss]", helper.echoCalls[1])
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
        taPackage.db.debug = true
        taPackage.mapping = true  -- these exercise the graph, which mapping mode gates
        helper.clearDbCalls()
    end)

    -- Stub queryOne so a room discovery resolves to a fixed new id and slug
    -- probes report "unused". exitDestination (a different SELECT) still returns
    -- nil, so entries take the "unknown exit -> discover" path unless overridden.
    local function stubDiscover(id)
        helper.mockDbOneRow = function(sql)
            if string.find(sql, "SELECT id FROM rooms WHERE slug", 1, true) then
                return { id = id }
            end
            return nil
        end
    end

    describe("room entry trigger", function()

        it("sets currentRoom to the normalized name", function()
            stubDiscover(1)
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("north plaza", taPackage.currentRoom)
        end)

        it("discovers a room through an unknown exit and links both directions", function()
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "ne"
            stubDiscover(6)
            helper.simulateLine("You're in the tavern.")
            assert.is_not_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
            local edges = {}
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute"
                    and string.find(c.sql, "INSERT OR REPLACE INTO room_exits", 1, true) then
                    edges[#edges + 1] = c.params
                end
            end
            assert.are.equal(2, #edges)
            assert.are.same({ 5, "ne", 6 }, edges[1])  -- forward edge
            assert.are.same({ 6, "sw", 5 }, edges[2])  -- reverse back-edge
            assert.are.equal(6, taPackage.currentRoomId)
        end)

        it("re-enters a known room without discovering a new one", function()
            taPackage.currentRoomId = 6
            taPackage.prevRoomId = 6
            taPackage.pendingDirection = "sw"
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 5 }
                elseif string.find(sql, "SELECT name FROM rooms", 1, true) then
                    return { name = "north plaza" }  -- edge dest's name matches the arrival
                end
                return nil
            end
            helper.simulateLine("You're in the north plaza.")
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
            assert.are.equal(5, taPackage.currentRoomId)
            local visit = helper.findDbCall("execute", "UPDATE rooms SET visits")
            assert.are.equal(5, visit.params[1])
        end)

        it("re-resolves when a known edge points at a differently-named room", function()
            -- Spurious re-display: we're in the magic shop (#13), 'go n', and the
            -- game reprints "You're in the magic shop." The edge 13--n-->10 points
            -- at south plaza, so the name won't match -> stay put, don't corrupt #10.
            taPackage.currentRoom = "magic shop"
            taPackage.currentRoomId = 13
            taPackage.prevRoomId = 13
            taPackage.pendingDirection = "n"
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 10 }
                elseif string.find(sql, "SELECT name FROM rooms", 1, true) then
                    return { name = "south plaza" }  -- edge dest is NOT the magic shop
                end
                return nil
            end
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal(13, taPackage.currentRoomId)  -- stayed in the magic shop
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))  -- no new room
        end)

        it("clears pendingDirection after entry", function()
            taPackage.pendingDirection = "n"
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            stubDiscover(9)
            helper.simulateLine("You're in the north plaza.")
            assert.is_nil(taPackage.pendingDirection)
        end)

        it("records zero loot when monster died but no gold found before room change", function()
            taPackage.lastKilledMonster = "huge rat"
            taPackage.pendingLootCheck = true
            stubDiscover(1)
            helper.simulateLine("You're in the north plaza.")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "monster_loot") and string.find(msg, "huge rat") then found = true end
            end
            assert.is_true(found)
            assert.is_nil(taPackage.pendingLootCheck)
        end)

        it("recognizes on/at and no-article room forms", function()
            stubDiscover(1)
            helper.simulateLine("You're on a path.")
            assert.are.equal("path", taPackage.currentRoom)
            helper.simulateLine("You're at an intersection.")
            assert.are.equal("intersection", taPackage.currentRoom)
            helper.simulateLine("You're in small cavern.")
            assert.are.equal("small cavern", taPackage.currentRoom)
        end)

        it("treats a 'You are ...' move brief as an arrival when idle", function()
            stubDiscover(1)
            helper.simulateLine("You are inside the dungeon entrance.")
            assert.are.equal("dungeon entrance", taPackage.currentRoom)
            helper.simulateLine("You are in a large cavern.")
            assert.are.equal("large cavern", taPackage.currentRoom)
        end)

        it("ignores a 'You are ...' line while accumulating a look description", function()
            taPackage.currentRoom = "large cavern"
            taPackage.currentRoomId = 5
            taPackage.monsterDb.state = "accumulating_room"  -- mid-look
            helper.simulateLine("You are in a large cavern.")  -- the look's first line
            assert.are.equal("large cavern", taPackage.currentRoom)  -- unchanged
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
        end)

    end)

    describe("movement alias", function()

        it("sets pendingDirection when player moves north", function()
            helper.simulateAlias("n")
            assert.are.equal("n", taPackage.pendingDirection)
        end)

        it("captures prevRoom and prevRoomId when player moves", function()
            taPackage.currentRoom = "market"
            taPackage.currentRoomId = 4
            helper.simulateAlias("e")
            assert.are.equal("market", taPackage.prevRoom)
            assert.are.equal(4, taPackage.prevRoomId)
        end)

        it("sends the movement command", function()
            helper.simulateAlias("s")
            assert.are.equal("s", helper.sendCalls[1])
        end)

        it("supports up and down", function()
            helper.simulateAlias("u")
            assert.are.equal("u", taPackage.pendingDirection)
            helper.simulateAlias("d")
            assert.are.equal("d", taPackage.pendingDirection)
        end)

    end)

    describe("ex exits capture", function()

        it("seeds a NULL stub per listed direction", function()
            taPackage.currentRoomId = 5
            helper.simulateLine("Exits: n,e,sw.")
            local dirs = {}
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute"
                    and string.find(c.sql, "INSERT OR IGNORE INTO room_exits", 1, true) then
                    assert.are.equal(5, c.params[1])
                    dirs[#dirs + 1] = c.params[2]
                end
            end
            assert.are.same({ "n", "e", "sw" }, dirs)
        end)

        it("is a no-op when the current room is unknown", function()
            taPackage.currentRoomId = nil
            helper.simulateLine("Exits: n,s.")
            assert.is_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO room_exits"))
        end)

    end)

    describe("failed move", function()

        it("clears pendingDirection without touching the graph", function()
            taPackage.pendingDirection = "e"
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            helper.simulateLine("Sorry, there's no exit in that direction.")
            assert.is_nil(taPackage.pendingDirection)
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
            assert.is_nil(helper.findDbCall("execute", "room_exits"))
        end)

        it("treats a trip-and-fall as a rejected move (clears pendingDirection)", function()
            taPackage.pendingDirection = "n"
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_nil(taPackage.pendingDirection)
        end)

        it("does not mis-resolve the reprint after a trip-and-fall", function()
            -- In the magic shop (#13), 'go n' too fast -> trip -> the game reprints
            -- "You're in the magic shop." With pendingDirection cleared, this must
            -- resolve back to #13, not follow the n-edge onto another room.
            taPackage.currentRoom = "magic shop"
            taPackage.currentRoomId = 13
            taPackage.prevRoomId = 13
            taPackage.pendingDirection = "n"
            helper.simulateLine("In your haste, you trip and fall!")
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal(13, taPackage.currentRoomId)
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
        end)

    end)

    describe("map-area alias", function()

        it("sets currentAreaId and new rooms inherit it", function()
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM areas", 1, true) then return { id = 3 } end
                if string.find(sql, "SELECT id FROM rooms WHERE slug", 1, true) then return { id = 7 } end
                return nil
            end
            helper.simulateAlias("map-area first-town First Town")
            assert.are.equal(3, taPackage.currentAreaId)
            local area = helper.findDbCall("execute", "INSERT OR IGNORE INTO areas")
            assert.are.equal("first-town", area.params[1])
            assert.are.equal("First Town", area.params[2])

            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "n"
            helper.simulateLine("You're in a cave.")
            local ins = helper.findDbCall("execute", "INSERT INTO rooms")
            assert.are.equal(3, ins.params[3])  -- area_id inherited
        end)

    end)

    describe("mapping mode", function()

        it("ignores room lines when mapping is off, but still records loot", function()
            taPackage.mapping = false
            taPackage.lastKilledMonster = "huge rat"
            taPackage.pendingLootCheck = true
            helper.simulateLine("You're in the north plaza.")
            -- loot bookkeeping still runs...
            assert.is_not_nil(helper.findDbCall("execute", "INSERT INTO monster_loot"))
            -- ...but the graph is untouched
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
            assert.is_nil(helper.findDbCall("execute", "UPDATE rooms SET visits"))
            assert.is_nil(taPackage.currentRoomId)
        end)

        it("auto-sends look and ex on arrival while mapping", function()
            stubDiscover(1)
            helper.simulateLine("You're in the north plaza.")
            local sent = {}
            for _, c in ipairs(helper.sendCalls) do sent[c] = true end
            assert.is_true(sent["look"])
            assert.is_true(sent["ex"])
        end)

        it("captures the room description via look, ended by the ex reply", function()
            taPackage.currentRoomId = 5
            -- Real stream order: look echo, prose, ex echo, then Exits.
            helper.simulateLine("look")
            helper.simulateLine("You are in the village tavern. The smoke from the oil lamps")
            helper.simulateLine("leaves many shadows and unlit corners.")
            helper.simulateLine("ex")   -- our echoed ex command, must be skipped
            helper.simulateLine("Exits: sw,u.")
            local desc = helper.findDbCall("execute", "UPDATE rooms SET description")
            assert.is_not_nil(desc)
            assert.are.equal(5, desc.params[2])
            assert.is_truthy(desc.params[1]:find("^You are in the village tavern"))  -- no "ex " prefix
            assert.is_truthy(desc.params[1]:find("unlit corners", 1, true))
            assert.is_nil(desc.params[1]:find("ex ", 1, true))
        end)

        it("captures a cave description whose look opens with 'You're in'", function()
            taPackage.currentRoomId = 14
            helper.simulateLine("look")
            helper.simulateLine("You're in a damp, poorly lit cave. Glowing lichens and fungi provide")
            helper.simulateLine("an eerie greenish light. The exits are to the north and south.")
            helper.simulateLine("ex")
            helper.simulateLine("Exits: n,s.")
            local desc = helper.findDbCall("execute", "UPDATE rooms SET description")
            assert.is_not_nil(desc)
            assert.is_truthy(desc.params[1]:find("damp, poorly lit cave", 1, true))
            assert.is_truthy(desc.params[1]:find("greenish light", 1, true))
        end)

        it("flags a newly discovered room as provisional, a reused one as not", function()
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "se"
            stubDiscover(6)
            helper.simulateLine("You're in the north plaza.")
            assert.is_true(taPackage.currentRoomProvisional)

            helper.clearDbCalls()
            taPackage.currentRoomId = 6
            taPackage.prevRoomId = 6
            taPackage.pendingDirection = "sw"
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then return { to_id = 5 } end
                return nil
            end
            helper.simulateLine("You're in the north plaza.")
            assert.is_false(taPackage.currentRoomProvisional)
        end)

        it("closes the loop: merges a provisional room into a fingerprint match on ex", function()
            taPackage.currentRoomId = 5
            taPackage.currentRoom = "north plaza"
            taPackage.currentRoomProvisional = true
            -- Room 1 (existing) shares the name and the observed exit-set {n,s}.
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE name", 1, true) then
                    return { { id = 1 }, { id = 5 } }
                elseif string.find(sql, "SELECT direction FROM room_exits WHERE from_id", 1, true) then
                    if params[1] == 1 then return { { direction = "n" }, { direction = "s" } } end
                    return {}
                end
                return {}  -- mergeRoomInto's "SELECT direction, to_id ..." -> no outgoing edges
            end
            helper.simulateLine("Exits: n,s.")
            assert.are.equal(1, taPackage.currentRoomId)          -- folded into the original
            assert.is_false(taPackage.currentRoomProvisional)
            assert.is_not_nil(helper.findDbCall("execute", "DELETE FROM rooms WHERE id"))
        end)

        it("does not merge a non-provisional room, but still seeds its exits", function()
            taPackage.currentRoomId = 1
            taPackage.currentRoom = "north plaza"
            taPackage.currentRoomProvisional = false
            helper.simulateLine("Exits: n,s.")
            assert.are.equal(1, taPackage.currentRoomId)
            assert.is_nil(helper.findDbCall("execute", "DELETE FROM rooms"))
            assert.is_not_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO room_exits"))
        end)

    end)

    describe("mapping mode aliases", function()

        it("map-on enables mapping and re-scans the current room", function()
            taPackage.mapping = false
            helper.simulateAlias("map-on")
            assert.is_true(taPackage.mapping)
            local bareSent = false
            for _, c in ipairs(helper.sendCalls) do if c == "" then bareSent = true end end
            assert.is_true(bareSent)
        end)

        it("map-off disables mapping", function()
            taPackage.mapping = true
            helper.simulateAlias("map-off")
            assert.is_false(taPackage.mapping)
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

describe("re-roll-half-ogre-warrior", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function lastEcho()
        return helper.echoCalls[#helper.echoCalls]
    end

    describe("alias", function()

        it("sets reRolling to true", function()
            helper.simulateAlias("re-roll-half-ogre-warrior")
            assert.is_true(taPackage.reRolling)
        end)

        it("sends 'status'", function()
            helper.simulateAlias("re-roll-half-ogre-warrior")
            assert.are.equal("status", helper.sendCalls[1])
        end)

    end)

    describe("matching", function()

        before_each(function()
            helper.simulateAlias("re-roll-half-ogre-warrior")
        end)

        it("accepts a roll with Phy >= 29, Sta >= 29 and Agi >= 15", function()
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      29")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     29 / 29")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("ignores Int, Kno and Cha", function()
            helper.simulateLine("Intellect:    1")
            helper.simulateLine("Knowledge:    1")
            helper.simulateLine("Charisma:     1")
            helper.simulateLine("Physique:     30")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("re-rolls when Physique is below 29", function()
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Stamina is below 29", function()
            helper.simulateLine("Physique:     30")
            helper.simulateLine("Stamina:      28")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     28 / 28")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Agility is below 15", function()
            helper.simulateLine("Physique:     30")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      14")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

    end)

end)

describe("Combat triggers", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.db.debug = true
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

        it("scans the room (bare return) before ringing", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("rings the gong once the scan shows an empty room", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[2])
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
            -- Capture only the XP-check timer; session start also arms the
            -- short scan-pump timer, which is not what these tests are about.
            _G.createTimer = function(interval, cb, opts)
                if interval == 300000 then
                    timerCreated = { interval = interval, cb = cb, opts = opts }
                end
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

        it("second-arena XP check fires a Markdown ntfy notification", function()
            taPackage.arenaProfile = "second"
            taPackage.character.name = "Tojolias"
            taPackage.character.class = "Warrior"
            taPackage.character.vitalityCurrent = 313
            taPackage.character.gold = 2900
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            taPackage.arenaXpCheckPending = true
            -- Warrior level 12 threshold is 588,700 and level 13 is 815,600, so
            -- 815,600 - 620,046 = 195,554 XP remain until the next level.
            helper.simulateLine("Experience:   620046")
            assert.are.equal(1, #helper.httpRequestCalls)
            local call = helper.httpRequestCalls[1]
            assert.are.equal("https://ntfy.sh/s5bbs-tele-arena-j5", call.url)
            assert.are.equal("POST", call.options.method)
            assert.are.equal("2nd Arena Check-In", call.options.headers["X-Title"])
            assert.are.equal("true", call.options.headers["X-Markdown"])
            assert.are.equal(
                "[Tojolias]\n"
                    .. "- XP Until Level Up: 195,554\n"
                    .. "- XP: 620,046\n"
                    .. "- HP: 313\n"
                    .. "- Gold: 2,900",
                call.options.body)
        end)

        it("first-arena XP check does not fire an ntfy notification", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   800")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("ntfy notification only fires on the periodic XP check", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaXpCheckPending = false
            helper.simulateLine("Experience:   800")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("ntfy notification is throttled to every 15 minutes", function()
            taPackage.arenaProfile = "second"
            taPackage.character.name = "Tojolias"
            taPackage.character.vitalityCurrent = 313
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()

            -- First periodic check (5 min in) pings.
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620046")
            assert.are.equal(1, #helper.httpRequestCalls)

            -- Next check (10 min in) is within the 15-min window: no ping.
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620100")
            assert.are.equal(1, #helper.httpRequestCalls)

            -- Once 15 min has elapsed since the last ping, it fires again.
            taPackage.arenaLastNtfyTime = os.time() - 900
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620200")
            assert.are.equal(2, #helper.httpRequestCalls)
        end)

    end)

    describe("monster enters arena", function()

        -- The arena is shared; we only adopt a gate spawn when it followed our
        -- own ring (signalled by "You just rang the great gong!").
        before_each(function()
            taPackage.arenaOwnSummonPending = true
        end)

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

        it("ignores a spawn we did not summon (another player's gong)", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = false
            helper.simulateLine("A skeleton warrior enters the arena through the dungeon gate!")
            assert.is_nil(taPackage.arenaMonster)
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("consumes the own-summon flag so a second spawn is not adopted", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("A skeleton warrior enters the arena through the dungeon gate!")
            assert.is_false(taPackage.arenaOwnSummonPending)
        end)

        it("'You just rang the great gong!' arms own-summon while ringing", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = false
            helper.simulateLine("You just rang the great gong!")
            assert.is_true(taPackage.arenaOwnSummonPending)
        end)

        it("another player's gong does not arm own-summon", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = false
            helper.simulateLine("Castor just rang the great gong!")
            assert.is_falsy(taPackage.arenaOwnSummonPending)
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

    describe("scan room before ringing", function()

        it("engages a monster already in the arena instead of ringing", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.mockDbOneRow = { description = "A hobgoblin." }
            helper.simulateLine("There is a hobgoblin here.")
            assert.are.equal("hobgoblin", taPackage.arenaMonster)
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a hobgoblin", helper.sendCalls[1])
        end)

        it("engages the first of several monsters in the room", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.mockDbOneRow = { description = "A hobgoblin." }
            helper.simulateLine("There is a hobgoblin, a huge rat, and a female kobold here.")
            assert.are.equal("hobgoblin", taPackage.arenaMonster)
        end)

        it("singularizes a plural first entry so the death line matches", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.mockDbOneRow = { description = "A huge rat." }
            helper.simulateLine("There is two huge rats, and an orc here.")
            assert.are.equal("huge rat", taPackage.arenaMonster)
        end)

        it("rings the gong when the room is empty", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[1])
            assert.are.equal("ringing", taPackage.arenaState)
        end)

        -- When another player shares the arena, the brief shows "Pollux is
        -- here." with NO "There is ... here." line, so the floor line that ends
        -- the brief is the only reliable terminator. Without it the probe hangs.
        it("rings via the floor line when only another player is present", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.simulateLine("Pollux is here.")
            assert.are.equal(0, #helper.sendCalls)  -- player line is not a terminator
            helper.simulateLine("There is nothing on the floor.")
            assert.are.equal("ring gong", helper.sendCalls[1])
            assert.is_false(taPackage.arenaProbePending)
        end)

        it("still terminates the brief when there is loot on the floor", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.simulateLine("There is a dagger on the floor.")
            assert.are.equal("ring gong", helper.sendCalls[1])
        end)

        it("does not ring on the floor line once a monster was engaged", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.mockDbOneRow = { description = "A hobgoblin." }
            helper.simulateLine("There is a hobgoblin here.")
            helper.simulateLine("There is nothing on the floor.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("hobgoblin", taPackage.arenaMonster)
            -- only the attack was sent, no "ring gong"
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("ring gong", cmd)
            end
        end)

        it("ignores the floor line when no probe is pending", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = false
            helper.simulateLine("There is nothing on the floor.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("ignores the occupant line when no probe is pending", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = false
            helper.simulateLine("There is a hobgoblin here.")
            assert.is_nil(taPackage.arenaMonster)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("clears the probe flag and does nothing if no longer ringing", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            taPackage.arenaProbePending = true
            helper.simulateLine("There is a hobgoblin here.")
            assert.is_false(taPackage.arenaProbePending)
            assert.are.equal("lizard man", taPackage.arenaMonster)
        end)

    end)

    describe("our attack results", function()

        it("sends next attack after a hit (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("sends next attack after an adjective-qualified hit (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("Your skillful attack hit the lizard man for 10 damage!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("flees when HP is below the flee threshold after a hit", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(15, 100)
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        -- Flee threshold is max(75% of maxHP, 25). At 100 max, that's 75.
        it("flees at 75% of max HP for a high-HP character", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(74, 100)  -- just under 75
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
        end)

        it("keeps fighting at exactly the 75% threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(75, 100)  -- not below threshold
            helper.simulateLine("Your attack hit the lizard man for 10 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        -- For a low-HP character the 25 floor kicks in: 75% of 31 is 23, but the
        -- floor raises the threshold to 25 so a cave bear's worst round (23) can't
        -- kill from above-threshold. This is the Johnsonite case (31 max HP).
        it("uses the absolute floor of 25 for a low-HP character", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(24, 31)  -- below floor 25, above 75% (23)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("sends next attack after a miss (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("Your attack missed!")
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("flees when HP is below the flee threshold after a miss", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(10, 100)
            helper.simulateLine("Your attack missed!")
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("sends next attack after monster dodge (HP fine)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
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
            setHP(80, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.is_nil(taPackage.arenaMonster)
        end)

        it("scans the room before ringing again when HP is fine", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("rings the gong after the scan shows an empty room", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[2])
        end)

        it("ignores the death of a monster we are not fighting", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            helper.simulateLine("The huge rat falls to the ground lifeless!")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("lizard man", taPackage.arenaMonster)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("flees when HP is below the flee threshold on monster death", function()
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
            setHP(80, 100)
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("training", taPackage.arenaState)
            assert.are.equal(1, taPackage.arenaTrainingPhase)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        it("scans (then rings) when XP is below next level threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            taPackage.character.experience = 500
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[2])
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

        it("flees when HP drops below the flee threshold", function()
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

        it("scans the room when entering arena and no monster left", function()
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = nil
            helper.simulateLine("You're in the arena.")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
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

        it("buys a drink when entering tavern with needsDrinks", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy drink", helper.sendCalls[1])
            assert.are.equal("sw", helper.sendCalls[2])
            assert.is_nil(taPackage.needsDrinks)
        end)

        it("buys a meal when entering tavern with needsMeal", function()
            taPackage.arenaState = "tavern"
            taPackage.needsMeal = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy meal", helper.sendCalls[1])
            assert.are.equal("sw", helper.sendCalls[2])
            assert.is_nil(taPackage.needsMeal)
        end)

        it("buys both a drink and a meal when both needed", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            taPackage.needsMeal = true
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("buy drink", helper.sendCalls[1])
            assert.are.equal("buy meal", helper.sendCalls[2])
            assert.are.equal("sw", helper.sendCalls[3])
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

    describe("emergency exit on lost navigation", function()

        local function sawSend(cmd)
            for _, c in ipairs(helper.sendCalls) do
                if c == cmd then return true end
            end
            return false
        end

        it("leaves the game when a journey step hits no exit", function()
            taPackage.arenaState = "tavern"
            taPackage.arenaJourney = { steps = { "w" }, index = 1, arriveRoom = "inn" }
            helper.simulateLine("Sorry, there's no exit in that direction.")
            assert.is_true(sawSend("x"))
            assert.is_nil(taPackage.arenaState)   -- session torn down
            assert.is_nil(taPackage.arenaJourney)
        end)

        it("ignores no exit when no journey is active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaJourney = nil
            helper.simulateLine("Sorry, there's no exit in that direction.")
            assert.are.equal(0, #helper.sendCalls)
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        it("ignores no exit when no arena session is running", function()
            taPackage.arenaState = nil
            taPackage.arenaJourney = { steps = { "w" }, index = 1, arriveRoom = "inn" }
            helper.simulateLine("Sorry, there's no exit in that direction.")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("thirst/hunger escape hatch", function()

        local function sawSend(cmd)
            for _, c in ipairs(helper.sendCalls) do
                if c == cmd then return true end
            end
            return false
        end

        it("leaves the game after 20 unrelieved thirst ticks", function()
            taPackage.arenaState = "tavern"  -- stuck en route, never drinking
            for _ = 1, 20 do helper.simulateLine("You're thirsty.") end
            assert.is_true(sawSend("x"))
            assert.is_nil(taPackage.arenaState)
        end)

        it("does not leave the game at 19 thirst ticks", function()
            taPackage.arenaState = "tavern"
            for _ = 1, 19 do helper.simulateLine("You're thirsty.") end
            assert.is_false(sawSend("x"))
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal(19, taPackage.arenaParchedStreak)
        end)

        it("leaves the game after 20 unrelieved hunger ticks", function()
            taPackage.arenaState = "tavern"
            for _ = 1, 20 do helper.simulateLine("You're hungry.") end
            assert.is_true(sawSend("x"))
            assert.is_nil(taPackage.arenaState)
        end)

        it("counts thirst and hunger toward the same streak", function()
            taPackage.arenaState = "tavern"
            for _ = 1, 10 do helper.simulateLine("You're thirsty.") end
            for _ = 1, 10 do helper.simulateLine("You're hungry.") end
            assert.is_true(sawSend("x"))
        end)

        it("resets the streak when the gong is rung", function()
            taPackage.arenaState = "tavern"
            for _ = 1, 15 do helper.simulateLine("You're thirsty.") end
            helper.simulateLine("You just rang the great gong!")
            assert.are.equal(0, taPackage.arenaParchedStreak)
            for _ = 1, 15 do helper.simulateLine("You're thirsty.") end
            assert.is_false(sawSend("x"))
        end)

        it("resets the streak when a drink is bought at the tavern", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            taPackage.arenaParchedStreak = 10
            helper.simulateLine("You're in the tavern.")
            assert.are.equal(0, taPackage.arenaParchedStreak)
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

        it("does NOT schedule a retry on exhaustion while ringing (pump owns it)", function()
            -- The scan pump re-arms itself; the exhaustion handler must not also
            -- schedule a retry (that shared-flag retry was the deadlock source).
            taPackage.arenaState = "ringing"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.is_nil(timerCreated)
        end)

        it("arms a 3s self-healing scan-pump timer on entering ringing", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "orc"
            helper.simulateLine("The orc falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.is_not_nil(timerCreated)
            assert.are.equal(3000, timerCreated.interval)
        end)

        it("the pump tick re-scans and re-arms while still ringing", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "orc"
            helper.simulateLine("The orc falls to the ground lifeless!")
            local tick = timerCreated.cb
            helper.sendCalls = {}
            timerCreated = nil
            tick()
            assert.are.equal("", helper.sendCalls[1])   -- re-scanned (bare return)
            assert.is_not_nil(timerCreated)             -- re-armed
            assert.are.equal(3000, timerCreated.interval)
        end)

        it("the pump tick stops once we leave ringing (engaged a monster)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "orc"
            helper.simulateLine("The orc falls to the ground lifeless!")
            local tick = timerCreated.cb
            -- We engage a monster (state -> fighting, generation bumped).
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = true
            helper.simulateLine("An imp enters the arena through the dungeon gate!")
            assert.are.equal("fighting", taPackage.arenaState)
            helper.sendCalls = {}
            timerCreated = nil
            tick()                                       -- stale tick
            assert.are.equal(0, #helper.sendCalls)       -- did nothing
            assert.is_nil(timerCreated)
        end)

        it("an outdated pump tick no-ops after a newer scan supersedes it", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "orc"
            helper.simulateLine("The orc falls to the ground lifeless!")
            local firstTick = timerCreated.cb
            firstTick()                                  -- runs, bumps gen, arms timer2
            helper.sendCalls = {}
            timerCreated = nil
            firstTick()                                  -- generation has moved on
            assert.are.equal(0, #helper.sendCalls)
            assert.is_nil(timerCreated)
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

        it("stacked exhaustion timers send only one swing (pending guard dedups)", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "skeleton"
            -- First exhaustion: schedules a melee retry
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local firstTimer = timerCreated
            assert.is_not_nil(firstTimer)
            -- Second exhaustion: schedules another retry on the same combat gen
            timerCreated = nil
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local secondTimer = timerCreated
            assert.is_not_nil(secondTimer)
            -- First timer fires and re-melees
            helper.sendCalls = {}
            firstTimer.cb()
            assert.are.equal("a skeleton", helper.sendCalls[1])
            -- Second timer fires but the swing is still pending — no duplicate
            helper.sendCalls = {}
            secondTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("retry timer does not swing after the monster is dead", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local staleTimer = timerCreated
            -- Monster dies; arena clears the target and rings the gong
            helper.simulateLine("The cave bear falls to the ground lifeless!")
            helper.sendCalls = {}
            -- Stale timer fires — no target, so nothing is sent
            staleTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("stale swing retry does not fire after flee is triggered", function()
            -- Regression: a cave bear killed Johnsonite because a 30s-stale
            -- exhaustion retry kept swinging after flee triggered, and every
            -- swing reset the movement cooldown so the escape `w` never landed.
            -- Once fleeing, the retry must no-op.
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local staleTimer = timerCreated
            assert.is_not_nil(staleTimer)
            -- HP drops below the flee threshold; the arena starts fleeing.
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            -- The stale swing retry fires while fleeing — it must stay silent.
            helper.sendCalls = {}
            staleTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("stale cast retry does not fire after flee is triggered", function()
            setClass("Sorceror")
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            helper.simulateLine("You are still too mentally exhausted from your last incantation!")
            local staleTimer = timerCreated
            assert.is_not_nil(staleTimer)
            taPackage.arenaState = "fleeing"
            helper.sendCalls = {}
            staleTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

        it("retry timer does not fire after a new session bumps the combat gen", function()
            setClass("Warrior")
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "skeleton"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local staleTimer = timerCreated
            assert.is_not_nil(staleTimer)
            -- A fresh session bumps arenaCombatGen and re-arms the monster, but
            -- the old timer's captured gen no longer matches, so it stays quiet.
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            taPackage.arenaMonster = "skeleton"
            helper.sendCalls = {}
            staleTimer.cb()
            assert.is_nil(helper.sendCalls[1])
        end)

    end)

end)

-- =========================================================================
-- Ring gong and fight in the SECOND arena
-- =========================================================================
-- Shares the combat engine with the first arena; only navigation differs. The
-- temple and bar are several rooms away and must be walked one paced step at a
-- time (moving too fast makes the character fall), and both arenas' rooms are
-- named "arena"/"temple", so travel is keyed off arenaProfile == "second".

describe("ring-gong-and-fight-in-second-arena", function()

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

        it("sets arenaProfile to 'second'", function()
            helper.simulateAlias("ring-gong-and-fight-in-second-arena")
            assert.are.equal("second", taPackage.arenaProfile)
        end)

        it("starts ringing and scans the room like the first arena", function()
            helper.simulateAlias("ring-gong-and-fight-in-second-arena")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateAlias("ring-gong-and-fight-in-second-arena")
            assert.is_nil(taPackage.arenaState)
        end)

        it("the first-arena alias leaves profile 'first' (not 'second')", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("first", taPackage.arenaProfile)
        end)

    end)

    describe("stop alias", function()

        it("clears profile, journey, and state", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaJourney = { steps = { "s" }, index = 0, arriveRoom = "temple" }
            taPackage.arenaState = "fighting"
            helper.simulateAlias("stop-ring-gong-and-fight-in-second-arena")
            assert.is_nil(taPackage.arenaProfile)
            assert.is_nil(taPackage.arenaJourney)
            assert.is_nil(taPackage.arenaState)
        end)

    end)

    describe("travel to the temple to heal", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == 1000 then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "second"
        end)

        it("flees toward the temple with the first south step", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("paces the next step after an intermediate 'on a path' room", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")  -- sends "s"
            helper.simulateLine("You're on a path.")
            assert.is_not_nil(stepTimer)  -- a 1s pacing timer was armed
            stepTimer.cb()
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("treats 'east plaza' as an intermediate step, not arrival", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaJourney = { steps = { "s", "s", "s", "s" }, index = 2, arriveRoom = "temple" }
            helper.simulateLine("You're in the east plaza.")
            assert.are.equal("fleeing", taPackage.arenaState)  -- did not buy healing
            assert.is_not_nil(stepTimer)
            stepTimer.cb()
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys healing on arriving at the temple", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaJourney = { steps = { "s", "s", "s", "s" }, index = 4, arriveRoom = "temple" }
            helper.simulateLine("You're in the temple.")
            assert.are.equal("healing", taPackage.arenaState)
            assert.are.equal("buy healing", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaJourney)
        end)

        it("does not use first-arena nav (no 'w' at north plaza)", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaJourney = { steps = { "s", "s", "s", "s" }, index = 1, arriveRoom = "temple" }
            helper.simulateLine("You're in the north plaza.")
            for _, c in ipairs(helper.sendCalls) do
                assert.are_not.equal("w", c)
            end
        end)

    end)

    describe("return from the temple after healing", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == 1000 then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "second"
        end)

        it("walks back to the arena, starting with north", function()
            taPackage.arenaState = "healing"
            helper.simulateLine("The priests heal all your wounds for 3 crowns.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("n", helper.sendCalls[#helper.sendCalls])
            assert.are.equal("arena", taPackage.arenaJourney.arriveRoom)
        end)

        it("resumes attacking on arriving back in the arena with the monster alive", function()
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = "cave bear"
            taPackage.arenaJourney = { steps = { "n", "n", "n", "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a cave", helper.sendCalls[#helper.sendCalls])
        end)

        it("scans and rings on arriving back with no monster", function()
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = nil
            taPackage.arenaJourney = { steps = { "n" }, index = 1, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[#helper.sendCalls])
            assert.is_true(taPackage.arenaProbePending)
        end)

    end)

    describe("travel to the bar (inn) to eat and drink", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == 1000 then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "second"
        end)

        it("departs for the bar with the first south step when thirsty", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.is_true(taPackage.needsDrinks)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("does not advance on the departure-room scan left over from the kill", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")   -- departs: first "s" sent
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
            assert.are.equal(1, taPackage.arenaJourney.index)
            -- The trailing "You're in the arena." brief from the finished fight is
            -- the room we're leaving, not a move — it must not schedule a step.
            helper.simulateLine("You're in the arena.")
            assert.is_nil(stepTimer)
            assert.are.equal(1, taPackage.arenaJourney.index)
        end)

        it("stays in sync: one real move advances exactly one step (s then s, not w)", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")     -- step 1: "s"
            helper.simulateLine("You're in the arena.") -- departure scan: ignored
            helper.simulateLine("You're on a path.")    -- first real move
            assert.is_not_nil(stepTimer)
            stepTimer.cb()
            -- The route is {s,s,...}; after one real move the next step is the
            -- second "s", NOT "w" (the desync that walked into "no exit").
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
            assert.are.equal(2, taPackage.arenaJourney.index)
        end)

        it("passes through north plaza as an intermediate step to the inn", function()
            taPackage.arenaState = "tavern"
            taPackage.arenaJourney = { steps = { "s", "s", "w", "w", "sw", "sw" }, index = 4, arriveRoom = "inn" }
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("tavern", taPackage.arenaState)  -- not arrival
            assert.is_not_nil(stepTimer)
            stepTimer.cb()
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys a drink on arriving at the inn, then walks back", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            taPackage.arenaJourney = { steps = { "sw" }, index = 6, arriveRoom = "inn" }
            helper.simulateLine("You're in the inn.")
            local drinks = 0
            for _, c in ipairs(helper.sendCalls) do
                if c == "buy drink" then drinks = drinks + 1 end
            end
            assert.are.equal(1, drinks)
            assert.is_nil(taPackage.needsDrinks)
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("ne", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys a meal on arriving at the inn when hungry", function()
            taPackage.arenaState = "tavern"
            taPackage.needsMeal = true
            taPackage.arenaJourney = { steps = { "sw" }, index = 6, arriveRoom = "inn" }
            helper.simulateLine("You're in the inn.")
            local meals = 0
            for _, c in ipairs(helper.sendCalls) do
                if c == "buy meal" then meals = meals + 1 end
            end
            assert.are.equal(1, meals)
            assert.is_nil(taPackage.needsMeal)
        end)

        it("heads to the bar after healing when still thirsty, on reaching the arena", function()
            taPackage.arenaState = "returning"
            taPackage.needsDrinks = true
            taPackage.arenaMonster = "cave bear"
            taPackage.arenaJourney = { steps = { "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

    end)

    describe("trips and falls when moving too fast", function()

        local tripTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == 2000 then tripTimer = { cb = cb } end
                return "mock_timer"
            end
            tripTimer = nil
            taPackage.arenaProfile = "second"
        end)

        it("re-sends the current step after tripping mid-walk", function()
            taPackage.arenaState = "returning"
            taPackage.arenaJourney = { steps = { "ne", "ne", "e", "e", "n", "n" }, index = 5, arriveRoom = "arena" }
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_not_nil(tripTimer)  -- a retry timer was armed
            tripTimer.cb()
            assert.are.equal("n", helper.sendCalls[#helper.sendCalls])  -- step 5, not advanced
            assert.are.equal(5, taPackage.arenaJourney.index)
        end)

        it("does nothing when no journey is active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaJourney = nil
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_nil(tripTimer)
        end)

        it("drops the retry if a new journey starts before it fires", function()
            taPackage.arenaState = "returning"
            taPackage.arenaJourney = { steps = { "n" }, index = 1, arriveRoom = "arena" }
            taPackage.arenaJourneyGen = 3
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_not_nil(tripTimer)
            taPackage.arenaJourneyGen = 4  -- a new leg started
            local before = #helper.sendCalls
            tripTimer.cb()
            assert.are.equal(before, #helper.sendCalls)  -- stale retry no-op
        end)

        it("also recovers on the first-arena profile (its shop trip is a journey too)", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaState = "potions"
            taPackage.arenaJourney = { steps = { "w", "s", "s" }, index = 2, arriveRoom = "magic shop" }
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_not_nil(tripTimer)
            tripTimer.cb()
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])  -- step 2, not advanced
            assert.are.equal(2, taPackage.arenaJourney.index)
        end)

    end)

    describe("monster appears in a puff of smoke", function()

        before_each(function()
            taPackage.arenaProfile = "second"
            taPackage.arenaOwnSummonPending = true
        end)

        it("adopts the summoned monster and starts fighting", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "A troll." }
            helper.simulateLine("A troll appears in a puff of reddish smoke!")
            assert.are.equal("troll", taPackage.arenaMonster)
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a troll", helper.sendCalls[#helper.sendCalls])
        end)

        it("ignores a spawn we did not summon (own-summon not armed)", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaOwnSummonPending = false
            helper.simulateLine("A troll appears in a puff of reddish smoke!")
            assert.is_nil(taPackage.arenaMonster)
            assert.are.equal("ringing", taPackage.arenaState)
        end)

        it("matches other smoke colors too", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = { description = "An ogre." }
            helper.simulateLine("An ogre appears in a puff of greenish smoke!")
            assert.are.equal("ogre", taPackage.arenaMonster)
        end)

    end)

    describe("no training in the second arena", function()

        before_each(function()
            taPackage.arenaProfile = "second"
        end)

        it("keeps fighting through a level-up instead of leaving to train", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(80, 100)
            taPackage.character.experience = 1120  -- past a level threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The cave bear falls to the ground lifeless!")
            assert.are_not.equal("training", taPackage.arenaState)
            -- resumes the ring loop, does not send the arena-1 training move
            assert.are.equal("ringing", taPackage.arenaState)
        end)

    end)

    describe("blocked first step out of the arena", function()

        local retryTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == 2000 then retryTimer = { cb = cb } end
                return "mock_timer"
            end
            retryTimer = nil
            taPackage.arenaProfile = "second"
        end)

        it("retries the blocked south step, not a hardcoded west", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaLastCmd = "s"
            taPackage.arenaRetryGeneration = 0
            helper.simulateLine("You cannot leave in the heat of battle!")
            assert.is_not_nil(retryTimer)
            retryTimer.cb()
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

    end)

end)

-- =========================================================================
-- Magic-shop potion runs (strength/agility potions, both arenas)
-- =========================================================================
-- Reactive round trip like healing: when a potion wears off (identical line for
-- rowan and hyssop) we walk to the "magic shop", re-buy and re-drink both, and
-- walk back. Uses the shared paced-journey pump, so both arenas do it — each by
-- its own route.

describe("magic-shop potion runs", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        helper.clearDbCalls()
        setClass("Warrior")
    end)

    describe("a potion wears off", function()

        it("heads to the shop (second arena, first step 's') when fighting", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
            assert.is_true(taPackage.needsPotions)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("heads to the shop (first arena, first step 'w') when fighting", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("departs when the tingle fires while ringing", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "ringing"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
        end)

        it("just flags when the tingle fires mid-trip (e.g. fleeing)", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "fleeing"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.is_true(taPackage.needsPotions)
        end)

        it("does not double-depart on the second potion's tingle line", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            helper.sendCalls = {}
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal(0, #helper.sendCalls)
            assert.are.equal("potions", taPackage.arenaState)
        end)

        it("does nothing outside an arena session", function()
            taPackage.arenaState = nil
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.is_nil(taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("arriving at the shop", function()

        it("re-buys and re-drinks both potions, then walks back (second arena)", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "potions"
            taPackage.needsPotions = true
            taPackage.arenaJourney = { steps = { "s", "s", "w", "w", "n", "n" }, index = 6, arriveRoom = "magic shop" }
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal("buy rowan", helper.sendCalls[1])
            assert.are.equal("buy hyssop", helper.sendCalls[2])
            assert.are.equal("drink rowan", helper.sendCalls[3])
            assert.are.equal("drink hyssop", helper.sendCalls[4])
            assert.is_nil(taPackage.needsPotions)
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])  -- first step home (s,s,e,e,n,n)
        end)

        it("walks back on the first-arena route (starts 'n')", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaState = "potions"
            taPackage.arenaJourney = { steps = { "w", "s", "s" }, index = 3, arriveRoom = "magic shop" }
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("n", helper.sendCalls[#helper.sendCalls])
        end)

        it("treats an intermediate room as a step, not the shop", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaState = "potions"
            taPackage.arenaJourney = { steps = { "w", "s", "s" }, index = 1, arriveRoom = "magic shop" }
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal("potions", taPackage.arenaState)  -- not arrived
            for _, c in ipairs(helper.sendCalls) do
                assert.are_not.equal("buy rowan", c)
            end
        end)

    end)

    describe("returning to the arena from the shop", function()

        it("resumes combat when nothing else is owed", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = "troll"
            taPackage.arenaJourney = { steps = { "n" }, index = 1, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a troll", helper.sendCalls[#helper.sendCalls])
        end)

        it("makes the shop trip after healing when a potion also wore off", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.arenaJourney = { steps = { "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])  -- first step to the shop
        end)

        it("does the shop before food when both are owed", function()
            taPackage.arenaProfile = "second"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.needsDrinks = true
            taPackage.arenaJourney = { steps = { "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
        end)

        -- The first arena walks home via room-name navigation (no journey), so a
        -- potion that wore off mid-errand must still be serviced on that path.
        it("services a deferred potion run on the first arena's room-name return", function()
            taPackage.arenaProfile = "first"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.arenaJourney = nil
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])  -- first step of the shop route
        end)

    end)

    it("stop clears needsPotions", function()
        taPackage.arenaProfile = "second"
        taPackage.needsPotions = true
        taPackage.arenaState = "potions"
        helper.simulateAlias("stop-ring-gong-and-fight-in-second-arena")
        assert.is_nil(taPackage.needsPotions)
    end)

end)

-- =========================================================================
-- Errand departure must not race a gong summon (problem.log deadlock)
-- =========================================================================
-- A potion wore off in the ring gap while our gong ring was still in flight.
-- The old code departed for the shop immediately, flipping the state out of
-- "ringing", so the warlock that then materialized was never adopted — and the
-- shop walk jammed on "You cannot leave in the heat of battle!" (a state the
-- retry didn't cover). The character stood there taking hits until stopped by
-- hand. The fix: defer the errand while a summon is pending, and service it
-- from the next clear ring gap.

describe("errand vs. in-flight gong summon", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        setClass("Warrior")
        taPackage.arenaProfile = "second"
    end)

    it("defers the shop run while a ring is in flight, then fights the summon", function()
        -- Ringing gap, gong just rung and awaiting its monster.
        taPackage.arenaState = "ringing"
        taPackage.arenaRingPending = true
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        -- Did NOT bail out to the shop: still ringing, no walk sent.
        assert.are.equal("ringing", taPackage.arenaState)
        assert.is_true(taPackage.needsPotions)
        for _, c in ipairs(helper.sendCalls) do
            assert.are_not.equal("s", c)  -- no shop-route step
        end

        -- The summon we rang for now lands and must be adopted and fought.
        taPackage.arenaOwnSummonPending = true
        helper.mockDbOneRow = { description = "A warlock." }
        helper.simulateLine("A warlock appears in a puff of reddish smoke!")
        assert.are.equal("fighting", taPackage.arenaState)
        assert.are.equal("warlock", taPackage.arenaMonster)
    end)

    it("makes the deferred shop run from the next clear ring gap", function()
        taPackage.needsPotions = true
        taPackage.arenaState = "ringing"
        taPackage.arenaProbePending = true
        -- The bare-return probe comes back with an empty room.
        helper.simulateLine("There is nobody here.")
        helper.simulateLine("There is nothing on the floor.")
        assert.are.equal("potions", taPackage.arenaState)
        assert.are.equal("s", helper.sendCalls[#helper.sendCalls])  -- first shop step
    end)

    it("rings normally from a clear gap when no errand is owed", function()
        taPackage.arenaState = "ringing"
        taPackage.arenaProbePending = true
        helper.simulateLine("There is nobody here.")
        helper.simulateLine("There is nothing on the floor.")
        assert.are.equal("ring gong", helper.sendCalls[#helper.sendCalls])
    end)

    it("retries a shop step blocked by heat of battle", function()
        local retryTimer
        _G.createTimer = function(interval, cb, opts)
            if interval == 2000 then retryTimer = { cb = cb } end
            return "mock_timer"
        end
        taPackage.arenaState = "potions"
        taPackage.arenaLastCmd = "s"
        taPackage.arenaRetryGeneration = 0
        helper.simulateLine("You cannot leave in the heat of battle!")
        assert.is_not_nil(retryTimer)
        retryTimer.cb()
        assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
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

describe("cast.fire.dart alias", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sends cast toduza <target>", function()
        helper.simulateAlias("cast.fire.dart tojolias")
        assert.are.equal("cast toduza tojolias", helper.sendCalls[1])
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

end)

describe("cast toduza outbound trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("decrements manaCurrent by 2", function()
        helper.simulateLine("Mana:         10 / 20")
        helper.simulateOutbound("cast toduza tojolias")
        assert.are.equal(8, taPackage.character.manaCurrent)
    end)

    it("does not reduce manaCurrent below 0", function()
        helper.simulateLine("Mana:         0 / 20")
        helper.simulateOutbound("cast toduza tojolias")
        assert.are.equal(0, taPackage.character.manaCurrent)
    end)

    it("does nothing when manaCurrent is unknown", function()
        helper.simulateOutbound("cast toduza tojolias")
        assert.is_nil(taPackage.character.manaCurrent)
    end)

end)

describe("motu inbound trigger", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    -- The land message doesn't name the spell, so we record whichever heal was
    -- last cast. INSERT param order: spell, target, outcome, amount, recorded_at, kind.
    it("records the last-cast heal spell (kamotu) with kind 'heal'", function()
        taPackage.lastSpellCast = "kamotu"
        helper.simulateLine("You intoned the spell for pelayo which healed 10 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("kamotu", call.params[1])
        assert.are.equal("pelayo", call.params[2])
        assert.are.equal("hit", call.params[3])
        assert.are.equal(10, call.params[4])
        assert.are.equal("heal", call.params[6])
    end)

    it("records motu when motu was the last heal cast", function()
        taPackage.lastSpellCast = "motu"
        helper.simulateLine("You intoned the spell for pelayo which healed 7 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.are.equal("motu", call.params[1])
        assert.are.equal("heal", call.params[6])
    end)

    it("falls back to 'unknown' spell but still kind 'heal' when none tracked", function()
        taPackage.lastSpellCast = nil
        helper.simulateLine("You intoned the spell for pelayo which healed 7 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.are.equal("unknown", call.params[1])
        assert.are.equal("heal", call.params[6])
    end)

    it("parses target and amount from the line", function()
        taPackage.lastSpellCast = "kamotu"
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
        taPackage.lastSpellCast = "toduza"
    end)

    it("records a hit with monster and damage", function()
        helper.simulateLine("You discharged the spell at the skeleton warrior for 8 damage!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("toduza", call.params[1])
        assert.are.equal("skeleton warrior", call.params[2])
        assert.are.equal("hit", call.params[3])
        assert.are.equal(8, call.params[4])
        assert.are.equal("offense", call.params[6])
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
        taPackage.lastSpellCast = "toduza"
        taPackage.lastAttackTarget = "skeleton warrior"
    end)

    it("records a fizzle using lastAttackTarget", function()
        helper.simulateLine("You confuse the key syllables and the spell fails!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("toduza", call.params[1])
        assert.are.equal("skeleton warrior", call.params[2])
        assert.are.equal("fizzle", call.params[3])
        assert.is_nil(call.params[4])
        assert.are.equal("offense", call.params[6])
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
        taPackage.lastSpellCast = "toduza"
    end)

    it("records a resist with monster name from line", function()
        helper.simulateLine("Your spell was negated by the giant bat's magickal defenses!")
        local call = helper.findDbCall("execute", "INSERT INTO player_spells")
        assert.is_not_nil(call)
        assert.are.equal("toduza", call.params[1])
        assert.are.equal("giant bat", call.params[2])
        assert.are.equal("resist", call.params[3])
        assert.is_nil(call.params[4])
        assert.are.equal("offense", call.params[6])
    end)

    it("updates lastAttackTarget on resist", function()
        helper.simulateLine("Your spell was negated by the imp's magickal defenses!")
        assert.are.equal("imp", taPackage.lastAttackTarget)
    end)

end)

describe("cast outbound sets lastSpellCast", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("sets lastSpellCast to toduza", function()
        helper.simulateOutbound("cast toduza skel")
        assert.are.equal("toduza", taPackage.lastSpellCast)
    end)

    it("sets lastSpellCast to kamotu", function()
        helper.simulateOutbound("cast kamotu pelayo")
        assert.are.equal("kamotu", taPackage.lastSpellCast)
    end)

    it("sets lastSpellCast to motu", function()
        helper.simulateOutbound("cast motu pelayo")
        assert.are.equal("motu", taPackage.lastSpellCast)
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

        it("clears a stale followedBy list when we start following", function()
            taPackage.followedBy = { "Grog" }
            helper.simulateAlias("ta.follow tojolias")
            assert.is_nil(taPackage.followedBy)
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

        it("leaves followDebug falsy without a debug suffix", function()
            helper.simulateAlias("ta.follow tojolias")
            assert.is_falsy(taPackage.followDebug)
        end)

        it("sets followDebug when given a ' debug' suffix", function()
            helper.simulateAlias("ta.follow tojolias debug")
            assert.is_true(taPackage.followDebug)
            assert.are.equal("tojolias", taPackage.followTarget)
        end)

        it("strips ' debug' from the join command", function()
            helper.simulateAlias("ta.follow tojolias debug")
            assert.are.equal("join tojolias", helper.sendCalls[1])
        end)

        it("notes debug mode in the confirmation echo", function()
            helper.simulateAlias("ta.follow tojolias debug")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "debug") then found = true end
            end
            assert.is_true(found)
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

        it("does not add when we are following someone (not the leader)", function()
            taPackage.followTarget = "pelayo"
            helper.simulateLine("Johnsonite is asking to join your group.")
            assert.are.equal(0, #helper.sendCalls)
            assert.is_nil(taPackage.followedBy)
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

    describe("confer command trigger", function()

        before_each(function()
            setClass("Warrior")
            taPackage.followTarget = "tojolias"
        end)

        it("starts the kill loop on 'confer kill <monster>' from the leader", function()
            helper.simulateLine("From Tojolias (to group): kill lizard")
            assert.is_true(taPackage.killActive)
            assert.are.equal("lizard", taPackage.killTarget)
            assert.are.equal("a lizard", helper.sendCalls[1])
        end)

        it("ignores commands not on the allowlist", function()
            helper.simulateLine("From Tojolias (to group): drop sword")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("scans the group and heals the most injured on 'confer heal.allies' as an Acolyte", function()
            setClass("Acolyte")
            helper.simulateLine("From Tojolias (to group): heal.allies")
            assert.are.equal("group", helper.sendCalls[1])
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 88% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE: 60% ST:Ready]")
            helper.simulateLine("You're in a cave.")
            assert.are.equal("cast kamotu Teekywiki", helper.sendCalls[1])
        end)

        it("does nothing on 'confer heal.allies' when not an Acolyte", function()
            helper.simulateLine("From Tojolias (to group): heal.allies")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("ignores conferred commands from a non-leader", function()
            helper.simulateLine("From Pelayo (to group): kill lizard")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when not following anyone", function()
            taPackage.followTarget = nil
            helper.simulateLine("From Tojolias (to group): kill lizard")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("drink trigger", function()

        it("buys a drink when the leader does", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The barmaid brings a drink over to Tojolias in exchange for a few coins.")
            assert.are.equal("b drink", helper.sendCalls[1])
        end)

        it("does nothing when a different character buys a drink", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The barmaid brings a drink over to Pelayo in exchange for a few coins.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when not following anyone", function()
            helper.simulateLine("The barmaid brings a drink over to Tojolias in exchange for a few coins.")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("meal trigger", function()

        it("buys a meal when the leader does", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The barmaid brings a hot meal over to Tojolias in exchange for a handful")
            assert.are.equal("buy meal", helper.sendCalls[1])
        end)

        it("does nothing when a different character buys a meal", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The barmaid brings a hot meal over to Pelayo in exchange for a handful")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when not following anyone", function()
            helper.simulateLine("The barmaid brings a hot meal over to Tojolias in exchange for a handful")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("temple heal trigger", function()

        it("buys healing when the leader is healed at the temple", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The temple priests take Tojolias into another chamber briefly, after which")
            assert.are.equal("buy healing", helper.sendCalls[1])
        end)

        it("does nothing when a different character is healed", function()
            taPackage.followTarget = "tojolias"
            helper.simulateLine("The temple priests take Pelayo into another chamber briefly, after which")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does nothing when not following anyone", function()
            helper.simulateLine("The temple priests take Tojolias into another chamber briefly, after which")
            assert.are.equal(0, #helper.sendCalls)
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

        it("starts when the leader swings and misses", function()
            helper.simulateLine("Tojolias's poorly executed attack misses the cyclops!")
            assert.is_true(taPackage.killActive)
            assert.are.equal("cyclops", taPackage.killTarget)
            assert.are.equal("a cyclops", helper.sendCalls[1])
        end)

        it("does nothing on a non-leader's missed attack", function()
            helper.simulateLine("Pelayo's poorly executed attack misses the cyclops!")
            assert.is_falsy(taPackage.killActive)
            assert.are.equal(0, #helper.sendCalls)
        end)

        describe("debug follows through from ta.follow", function()

            local function countKillTrace()
                local count = 0
                for _, msg in ipairs(helper.echoCalls) do
                    if string.find(msg, "[K]", 1, true) then count = count + 1 end
                end
                return count
            end

            it("inherits follow debug into the spawned kill", function()
                helper.simulateAlias("ta.follow tojolias debug")
                helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
                assert.is_true(taPackage.killActive)
                assert.is_true(taPackage.followDebug)
                assert.is_true(countKillTrace() > 0)
            end)

            it("emits no kill trace when following without debug", function()
                helper.simulateAlias("ta.follow tojolias")
                helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
                assert.is_true(taPackage.killActive)
                assert.are.equal(0, countKillTrace())
            end)

            it("logs a join-skip decision when already killing in another room", function()
                helper.simulateAlias("ta.follow tojolias debug")
                helper.simulateLine("Tojolias just attacked the huge rat with a flail!")
                helper.echoCalls = {}
                -- Leader moves on and engages a new monster while our loop is
                -- still pinned to the (never-seen-dead) huge rat.
                helper.simulateLine("Tojolias just attacked the cave bear with a flail!")
                assert.are.equal("huge rat", taPackage.killTarget)
                local logged = false
                for _, msg in ipairs(helper.echoCalls) do
                    if string.find(msg, "join-skip", 1, true)
                        and string.find(msg, "cave bear", 1, true) then
                        logged = true
                    end
                end
                assert.is_true(logged)
            end)

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

        it("does not set killDebug without a debug suffix", function()
            helper.simulateAlias("kill cave lizard")
            assert.is_falsy(taPackage.killDebug)
            local traced = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "[K]", 1, true) then traced = true end
            end
            assert.is_false(traced)
        end)

        it("sets killDebug and traces with a ' debug' suffix", function()
            helper.simulateAlias("kill cave lizard debug")
            assert.is_true(taPackage.killDebug)
            assert.are.equal("cave lizard", taPackage.killTarget)
            local traced = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "[K]", 1, true) then traced = true end
            end
            assert.is_true(traced)
        end)

        it("clears killDebug when the target dies", function()
            helper.simulateAlias("kill cave lizard debug")
            helper.simulateLine("The cave lizard falls to the ground lifeless!")
            assert.is_falsy(taPackage.killDebug)
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

        it("stop-kill clears state", function()
            helper.simulateAlias("kill cave lizard")
            helper.simulateAlias("stop-kill")
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

            it("melees and casts toduza on start", function()
                helper.simulateAlias("kill cave lizard")
                assert.are.equal("a cave", helper.sendCalls[1])
                assert.are.equal("cast toduza cave", helper.sendCalls[2])
            end)

            it("keeps meleeing after a hit, independent of the cast loop", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("Your attack hit the cave lizard for 8 damage!")
                assert.are.equal("a cave", helper.sendCalls[1])
            end)

            it("re-casts after a successful discharge", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You discharged the spell at the cave lizard for 8 damage!")
                assert.are.equal("cast toduza cave", helper.sendCalls[1])
            end)

            it("re-casts after a fizzle", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You confuse the key syllables and the spell fails!")
                assert.are.equal("cast toduza cave", helper.sendCalls[1])
            end)

            it("re-casts after a resist", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("Your spell was negated by the cave lizard's magickal defenses!")
                assert.are.equal("cast toduza cave", helper.sendCalls[1])
            end)

            it("clears the cast pending flag on mental exhaustion", function()
                helper.simulateAlias("kill cave lizard")
                taPackage.castPending = true
                helper.simulateLine("You are still too mentally exhausted from your last incantation!")
                assert.is_false(taPackage.castPending)
            end)

        end)

        describe("Acolyte", function()

            before_each(function()
                setClass("Acolyte")
                -- These tests exercise the automatic in-combat healing, which is
                -- gated off by default; turn it on for them.
                taPackage.acolyteAutoHealDisabled = false
            end)

            it("melees on start like everyone else", function()
                helper.simulateAlias("kill cave lizard")
                assert.are.equal("a cave", helper.sendCalls[1])
            end)

            it("checks the group on attack exhaustion", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                assert.are.equal("group", helper.sendCalls[1])
            end)

            it("heals the most injured member from the group listing", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                helper.sendCalls = {}
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Johnsonite                         [HE:100% ST:Ready]")
                helper.simulateLine("  Pelayo                             [HE: 82% ST:Ready]")
                helper.simulateLine("  Teekywiki                          [HE: 70% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal("cast kamotu Teekywiki", helper.sendCalls[1])
            end)

            it("uses motu instead of kamotu when in the arena", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                taPackage.arenaState = "fighting"
                helper.sendCalls = {}
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Pelayo                             [HE: 82% ST:Ready]")
                helper.simulateLine("  Teekywiki                          [HE: 70% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal("cast motu Teekywiki", helper.sendCalls[1])
            end)

            it("parses the leader's (L) marker line", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                helper.sendCalls = {}
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Tojolias                       (L) [HE: 55% ST:Resting]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal("cast kamotu Tojolias", helper.sendCalls[1])
            end)

            it("heals only one member per group listing", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                helper.sendCalls = {}
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Pelayo                             [HE: 82% ST:Ready]")
                helper.simulateLine("  Teekywiki                          [HE: 70% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                local heals = 0
                for _, cmd in ipairs(helper.sendCalls) do
                    if cmd:match("^cast kamotu ") then heals = heals + 1 end
                end
                assert.are.equal(1, heals)
            end)

            it("does not heal when everyone is at or above the threshold", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                helper.sendCalls = {}
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Johnsonite                         [HE:100% ST:Ready]")
                helper.simulateLine("  Teekywiki                          [HE: 95% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal(0, #helper.sendCalls)
            end)

            it("does not abort the scan on combat noise before the listing", function()
                helper.simulateAlias("kill cave lizard")
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                helper.sendCalls = {}
                helper.simulateLine("The cave bear attacked you with its claws for 5 damage!")
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Teekywiki                          [HE: 70% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal("cast kamotu Teekywiki", helper.sendCalls[1])
            end)

            it("ignores a group listing typed outside a scan", function()
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Pelayo                             [HE: 50% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                assert.are.equal(0, #helper.sendCalls)
            end)

            it("clears castPending on mental exhaustion even out of combat", function()
                taPackage.castPending = true
                helper.simulateLine("You are still too mentally exhausted from your last incantation!")
                assert.is_false(taPackage.castPending)
            end)

            it("clears castPending when mana is too low (no kill active)", function()
                taPackage.castPending = true
                helper.simulateLine("Your mana is too low to cast that spell.")
                assert.is_false(taPackage.castPending)
            end)

            it("clears arenaCastPending when mana is too low", function()
                taPackage.arenaCastPending = true
                helper.simulateLine("Your mana is too low to cast that spell.")
                assert.is_false(taPackage.arenaCastPending)
            end)

            it("clears castPending on a fizzle even out of combat", function()
                taPackage.castPending = true
                helper.simulateLine("You confuse the key syllables and the spell fails!")
                assert.is_false(taPackage.castPending)
            end)

        end)

        describe("Acolyte with auto-heal disabled", function()

            before_each(function()
                setClass("Acolyte")
                -- The hard-coded default, made explicit here.
                taPackage.acolyteAutoHealDisabled = true
            end)

            it("melees on start", function()
                helper.simulateAlias("kill cave lizard")
                assert.are.equal("a cave", helper.sendCalls[1])
            end)

            it("does not scan the group on attack exhaustion", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                for _, cmd in ipairs(helper.sendCalls) do
                    assert.are_not.equal("group", cmd)
                end
            end)

            it("never casts a heal across an exhaustion-driven scan", function()
                helper.simulateAlias("kill cave lizard")
                helper.sendCalls = {}
                helper.simulateLine("You are still physically exhausted from your previous activities!")
                -- A group listing arriving anyway must not be acted on.
                helper.simulateLine("Your group currently consists of:")
                helper.simulateLine("  Teekywiki                          [HE: 40% ST:Ready]")
                helper.simulateLine("You're in a cave.")
                for _, cmd in ipairs(helper.sendCalls) do
                    assert.is_nil(cmd:match("^cast kamotu"))
                end
            end)

        end)

    end)

    describe("heal.allies alias", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
        end)

        it("scans the group and heals the most injured as an Acolyte", function()
            setClass("Acolyte")
            helper.simulateAlias("heal.allies")
            assert.are.equal("group", helper.sendCalls[1])
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 88% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE: 60% ST:Ready]")
            helper.simulateLine("Exits: n,sw.")
            assert.are.equal("cast kamotu Teekywiki", helper.sendCalls[1])
        end)

        it("chases the listing with `ex` so a terminator line always arrives", function()
            setClass("Acolyte")
            helper.simulateAlias("heal.allies")
            assert.are.equal("group", helper.sendCalls[1])
            assert.are.equal("ex", helper.sendCalls[2])
        end)

        it("finalizes off the `ex` reply (no following line needed)", function()
            setClass("Acolyte")
            helper.simulateAlias("heal.allies")
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 88% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE: 60% ST:Ready]")
            -- The "Exits:" line is the guaranteed terminator from `ex`.
            helper.simulateLine("Exits: n,sw.")
            assert.are.equal("cast kamotu Teekywiki", helper.sendCalls[1])
        end)

        it("does nothing and warns when not an Acolyte", function()
            setClass("Warrior")
            helper.simulateAlias("heal.allies")
            assert.are.equal(0, #helper.sendCalls)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Acolyte") then warned = true end
            end
            assert.is_true(warned)
        end)

    end)

    describe("heal-allies-in-loop alias", function()

        local timers
        local realCreateTimer

        local function lastLoopTimer()
            -- The 60s loop timer (the only timer this feature schedules).
            for i = #timers, 1, -1 do
                if timers[i].interval == 60000 then return timers[i] end
            end
        end

        before_each(function()
            helper.resetAll()
            timers = {}
            realCreateTimer = _G.createTimer
            _G.createTimer = function(interval, cb, opts)
                table.insert(timers, { interval = interval, cb = cb, opts = opts })
                return "mock_timer"
            end
            dofile("main.lua")
        end)

        after_each(function()
            _G.createTimer = realCreateTimer
        end)

        it("scans immediately and schedules a 60s loop as an Acolyte", function()
            setClass("Acolyte")
            helper.simulateAlias("heal-allies-in-loop")
            assert.are.equal("group", helper.sendCalls[1])
            assert.is_not_nil(lastLoopTimer())
        end)

        it("tops off a member below 95% (looser than heal.allies' 90%)", function()
            setClass("Acolyte")
            helper.simulateAlias("heal-allies-in-loop")
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 92% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE: 98% ST:Ready]")
            helper.simulateLine("You're in a cave.")
            assert.are.equal("cast kamotu Pelayo", helper.sendCalls[1])
        end)

        it("does not heal when everyone is at or above 95%", function()
            setClass("Acolyte")
            helper.simulateAlias("heal-allies-in-loop")
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 95% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE:100% ST:Ready]")
            helper.simulateLine("You're in a cave.")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("the loop tick re-scans and reschedules", function()
            setClass("Acolyte")
            helper.simulateAlias("heal-allies-in-loop")
            local loop = lastLoopTimer()
            helper.sendCalls = {}
            local before = #timers
            loop.cb()
            assert.are.equal("group", helper.sendCalls[1])
            assert.is_true(#timers > before)
        end)

        it("stop-heal-allies-in-loop keeps a pending tick from firing", function()
            setClass("Acolyte")
            helper.simulateAlias("heal-allies-in-loop")
            local loop = lastLoopTimer()
            helper.simulateAlias("stop-heal-allies-in-loop")
            helper.sendCalls = {}
            loop.cb()
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("warns and does not loop when not an Acolyte", function()
            setClass("Warrior")
            helper.simulateAlias("heal-allies-in-loop")
            assert.are.equal(0, #helper.sendCalls)
            assert.is_nil(lastLoopTimer())
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Acolyte") then warned = true end
            end
            assert.is_true(warned)
        end)

    end)

    describe("heal-allies-in-loop hit reaction", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
            setClass("Acolyte")
        end)

        it("scans the group when a group member takes a hit", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            assert.are.equal("group", helper.sendCalls[1])
            assert.are.equal("ex", helper.sendCalls[2])
        end)

        it("scans when the healer itself is hit (for N damage)", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked you with its claws for 6 damage!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("heals the most injured member the hit revealed", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Johnsonite                         [HE: 38% ST:Ready]")
            helper.simulateLine("Exits: w,d.")
            assert.are.equal("cast kamotu Johnsonite", helper.sendCalls[1])
        end)

        it("does not scan on a glancing blow (no damage)", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked Johnsonite, but its claws glanced off Johnsonite's armor!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("collapses a monster's two claws in one round into a single scan", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            local scans = 0
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "group" then scans = scans + 1 end
            end
            assert.are.equal(1, scans)
        end)

        it("does not scan when the loop is not active", function()
            taPackage.healLoopActive = false
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does not scan after the loop is stopped", function()
            helper.simulateAlias("heal-allies-in-loop")
            helper.simulateAlias("stop-heal-allies-in-loop")
            helper.sendCalls = {}
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does not scan when not an Acolyte", function()
            setClass("Warrior")
            taPackage.healLoopActive = true
            helper.simulateLine("The cave bear attacked Johnsonite with its claws!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("scans when a stone giant's boulder lands on an ally", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The stone giant hurled a boulder at Pelayo!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("scans when a stone giant's boulder lands on the healer", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The stone giant hurled a boulder at you for 52 damage!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("scans when a cyclops's throw lands on an ally", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cyclops picks up and hurls Teekywiki!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("scans when a cyclops's throw lands on the healer", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The cyclops picks up and hurls you for 22 damage!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("scans when a chimera's flame breath lands on an ally", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The chimera breathed flames at Pelayo!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("scans when a chimera's flame breath lands on the healer", function()
            taPackage.healLoopActive = true
            helper.simulateLine("The chimera breathed flames at you for 27 damage!")
            assert.are.equal("group", helper.sendCalls[1])
        end)

        it("does not scan on special attacks when the loop is not active", function()
            taPackage.healLoopActive = false
            helper.simulateLine("The stone giant hurled a boulder at Pelayo!")
            helper.simulateLine("The cyclops picks up and hurls Teekywiki!")
            helper.simulateLine("The chimera breathed flames at Pelayo!")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("stop-all-scripts", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
        end)

        it("stops the kill, heal loop, arena, tavern, and mapping scripts together", function()
            taPackage.killActive = true
            taPackage.healLoopActive = true
            taPackage.arenaState = "fighting"
            taPackage.tavernMode = true
            taPackage.mapping = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_falsy(taPackage.killActive)
            assert.is_false(taPackage.healLoopActive)
            assert.is_nil(taPackage.arenaState)
            assert.is_false(taPackage.tavernMode)
            assert.is_false(taPackage.mapping)
        end)

        it("is a safe no-op when nothing is running", function()
            assert.has_no.errors(function()
                helper.simulateAlias("stop-all-scripts")
            end)
            assert.is_falsy(taPackage.killActive)
            assert.is_falsy(taPackage.healLoopActive)
            assert.is_nil(taPackage.arenaState)
        end)

        local function echoed(needle)
            for _, text in ipairs(helper.echoCalls) do
                if text:find(needle, 1, true) then return true end
            end
            return false
        end

        it("reports each script it stopped", function()
            taPackage.killActive = true
            taPackage.healLoopActive = true
            taPackage.arenaState = "fighting"
            taPackage.tavernMode = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_true(echoed("[all] Stopped arena."))
            assert.is_true(echoed("[all] Stopped heal loop."))
            assert.is_true(echoed("[all] Stopped kill."))
            assert.is_true(echoed("[all] Stopped hang-around-in-tavern."))
        end)

        it("stops mapping too", function()
            taPackage.mapping = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_false(taPackage.mapping)
            assert.is_true(echoed("[all] Stopped mapping."))
        end)

        it("reports scripts that were not running", function()
            helper.simulateAlias("stop-all-scripts")
            assert.is_true(echoed("[all] arena not running."))
            assert.is_true(echoed("[all] heal loop not running."))
            assert.is_true(echoed("[all] kill not running."))
            assert.is_true(echoed("[all] hang-around-in-tavern not running."))
        end)

        it("reports a mix of stopped and not-running scripts", function()
            taPackage.killActive = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_true(echoed("[all] Stopped kill."))
            assert.is_true(echoed("[all] arena not running."))
        end)

    end)

    describe("group-heal decision logging", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
            setClass("Acolyte")
        end)

        -- Did any echoed line contain the given substring?
        local function logged(substr)
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, substr, 1, true) then return true end
            end
            return false
        end

        it("logs that all allies are at full health when nobody is hurt", function()
            helper.simulateAlias("heal.allies")
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE:100% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE:100% ST:Ready]")
            helper.simulateLine("Exits: n,sw.")
            assert.is_true(logged("all 2 allies at full health, taking no action"))
        end)

        it("logs hurt-but-above-threshold when allies are hurt but none need healing", function()
            helper.simulateAlias("heal.allies")
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 95% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE:100% ST:Ready]")
            helper.simulateLine("Exits: n,sw.")
            assert.is_true(logged("1 of 2 allies hurt but all at or above 90%, taking no action"))
        end)

        it("logs the count and most-injured member when healing", function()
            helper.simulateAlias("heal.allies")
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 88% ST:Ready]")
            helper.simulateLine("  Teekywiki                          [HE: 60% ST:Ready]")
            helper.simulateLine("Exits: n,sw.")
            assert.is_true(logged("2 of 2 allies below 90%, healing most injured Teekywiki at 60%"))
        end)

        it("labels the scan origin (loop tick) in the log", function()
            local timers = {}
            local realCreateTimer = _G.createTimer
            _G.createTimer = function(interval, cb, opts)
                table.insert(timers, { interval = interval, cb = cb, opts = opts })
                return "mock_timer"
            end
            helper.simulateAlias("heal-allies-in-loop")
            local loop
            for i = #timers, 1, -1 do
                if timers[i].interval == 60000 then loop = timers[i] break end
            end
            helper.echoCalls = {}
            loop.cb()
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 50% ST:Ready]")
            helper.simulateLine("Exits: n,sw.")
            _G.createTimer = realCreateTimer
            assert.is_true(logged("loop tick: 1 of 1 allies below 95%, healing most injured Pelayo at 50%"))
        end)

    end)

    describe("non-caster classes", function()

        before_each(function()
            helper.resetAll()
            dofile("main.lua")
            setClass("Warrior")
        end)

        it("does not send group on attack exhaustion", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does not heal off a group listing", function()
            helper.simulateAlias("kill cave lizard")
            helper.sendCalls = {}
            helper.simulateLine("Your group currently consists of:")
            helper.simulateLine("  Pelayo                             [HE: 50% ST:Ready]")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

end)

describe("Follow sessions", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function sent(cmd)
        for _, c in ipairs(helper.sendCalls) do
            if c == cmd then return true end
        end
        return false
    end

    local function echoed(fragment)
        for _, e in ipairs(helper.echoCalls) do
            if string.find(e, fragment, 1, true) then return true end
        end
        return false
    end

    it("ta.follow joins, requests status, and arms the start capture", function()
        helper.simulateAlias("ta.follow Pelayo")
        assert.is_true(sent("join Pelayo"))
        assert.is_true(sent("status"))
        assert.is_true(taPackage.followStartXpPending)
        assert.is_false(taPackage.followEndXpPending)
    end)

    it("captures starting XP from the status that follows ta.follow", function()
        helper.simulateAlias("ta.follow Pelayo")
        helper.simulateLine("Experience:   100")
        assert.are.equal(100, taPackage.followSessionStartXp)
        assert.is_false(taPackage.followStartXpPending)
        assert.is_true(echoed("Session started. XP: 100"))
    end)

    it("ta.unfollow leaves, clears follow state, and requests status", function()
        helper.simulateAlias("ta.follow Pelayo")
        helper.simulateLine("Experience:   100")
        helper.sendCalls = {}
        helper.simulateAlias("ta.unfollow")
        assert.is_true(sent("leave"))
        assert.is_true(sent("status"))
        assert.is_nil(taPackage.followTarget)
        assert.is_nil(taPackage.followDebug)
        assert.is_true(taPackage.followEndXpPending)
    end)

    it("reports the XP gained over a full follow session", function()
        helper.simulateAlias("ta.follow Pelayo")
        helper.simulateLine("Experience:   100")
        helper.simulateAlias("ta.unfollow")
        helper.simulateLine("Experience:   175")
        assert.is_true(echoed("gained 75 XP (total: 175)"))
        assert.is_nil(taPackage.followSessionStartXp)
        assert.is_false(taPackage.followEndXpPending)
    end)

    it("reports unknown starting XP if ta.unfollow runs without a captured start", function()
        taPackage.followEndXpPending = true
        helper.simulateLine("Experience:   175")
        assert.is_true(echoed("starting XP unknown (total: 175)"))
    end)

    it("does not treat a routine Experience line as a session boundary", function()
        helper.simulateLine("Experience:   100")
        assert.is_false(echoed("Session started"))
        assert.is_false(echoed("Session over"))
    end)

end)

describe("Attack badges", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function lastBadge()
        return helper.cechoBgCalls[#helper.cechoBgCalls]
    end

    it("echoes a blue-on-near-white HIT badge with the damage amount", function()
        helper.simulateLine("Your attack hit the stone giantess for 12 damage!")
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(" HIT 12 ", badge.text)
        assert.are.equal("#2563eb", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end)

    it("does not badge a miss", function()
        helper.simulateLine("Your attack missed!")
        assert.are.equal(0, #helper.cechoBgCalls)
    end)

    it("does not badge a dodge", function()
        helper.simulateLine("The stone giantess dodged your attack!")
        assert.are.equal(0, #helper.cechoBgCalls)
    end)

    it("badges each swing of a multi-hit burst", function()
        helper.simulateLine("Your attack hit the stone giantess for 12 damage!")
        helper.simulateLine("Your attack hit the stone giantess for 25 damage!")
        helper.simulateLine("Your attack hit the stone giantess for 18 damage!")
        local texts = {}
        for _, c in ipairs(helper.cechoBgCalls) do table.insert(texts, c.text) end
        assert.are.same({ " HIT 12 ", " HIT 25 ", " HIT 18 " }, texts)
    end)

    it("does not badge a party member's attack", function()
        helper.simulateLine("Teekywiki just attacked the stone giantess with a broadsword!")
        assert.are.equal(0, #helper.cechoBgCalls)
    end)

    -- Incoming damage: same bold, padded, near-white block as outgoing, but
    -- pink/red to mark damage we take rather than deal.
    local function assertIncomingHit(line, expectedText)
        helper.simulateLine(line)
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(expectedText, badge.text)
        assert.are.equal("#ff5fd7", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end

    it("echoes a pink TOOK badge when a monster damages us", function()
        assertIncomingHit("The stone giantess attacked you with a club for 9 damage!", " TOOK 9 ")
    end)

    it("badges a hurled-boulder special attack", function()
        assertIncomingHit("The stone giant hurled a boulder at you for 52 damage!", " TOOK 52 ")
    end)

    it("badges a pick-up-and-hurl special attack", function()
        assertIncomingHit("The cyclops picks up and hurls you for 22 damage!", " TOOK 22 ")
    end)

    it("badges a flame-breath special attack", function()
        assertIncomingHit("The dragon breathed flames at you for 30 damage!", " TOOK 30 ")
    end)

    it("badges a warlock's discharged-spell special attack", function()
        assertIncomingHit("The warlock discharged a searing ball of flame at you for 47 damage!", " TOOK 47 ")
    end)

    it("badges a warlock's shower-of-flame variant", function()
        assertIncomingHit("The warlock discharged a shower of flame at you for 32 damage!", " TOOK 32 ")
    end)

    it("badges a stygian dragon's bite special attack", function()
        assertIncomingHit("The stygian dragon viciously bit you for 39 damage!", " TOOK 39 ")
    end)

    it("badges a stygian dragon's tail-lash special attack", function()
        assertIncomingHit("The stygian dragon lashed out with its tail for 35 damage!", " TOOK 35 ")
    end)

    it("badges a minotaur chieftain's charge special attack", function()
        assertIncomingHit("The minotaur chieftain charged you for 42 damage!", " TOOK 42 ")
    end)

    it("does not badge a special attack that lands on a party member", function()
        helper.simulateLine("The stone giant hurled a boulder at Pelayo!")
        assert.are.equal(0, #helper.cechoBgCalls)
    end)

    -- Traps print no damage number; we stash HP, ask for "st", and recover the
    -- loss from the fresh Vitality line.
    describe("trap badges", function()
        local TRAPS = {
            "A spiked trap catches your foot and pain shoots up your leg!",
            "Several crossbow bolts fire from holes in the walls, striking you!",
            "Several large stones fall on you from above!",
        }

        before_each(function()
            helper.simulateLine("Vitality:     50 / 60")
        end)

        for _, TRAP in ipairs(TRAPS) do
            it("stashes HP and requests a status check on: " .. TRAP, function()
                helper.simulateLine(TRAP)
                assert.are.equal(50, taPackage.trapHpBefore)
                assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
            end)

            it("badges the HP lost once the status returns for: " .. TRAP, function()
                helper.simulateLine(TRAP)
                helper.simulateLine("Vitality:     30 / 60")
                local badge = lastBadge()
                assert.are.equal(" TRAP 20 ", badge.text)
                assert.are.equal("#ff5fd7", badge.color)
                assert.are.equal("#e0e0e0", badge.backgroundColor)
                assert.is_true(badge.bold)
                assert.is_nil(taPackage.trapHpBefore)
            end)
        end

        it("does not badge if HP did not drop", function()
            helper.simulateLine(TRAPS[1])
            helper.simulateLine("Vitality:     50 / 60")
            assert.are.equal(0, #helper.cechoBgCalls)
        end)

        it("does not badge a plain status check with no pending trap", function()
            helper.simulateLine("Vitality:     40 / 60")
            assert.are.equal(0, #helper.cechoBgCalls)
        end)
    end)

    -- Area-effect spells print no damage number either; same trick as traps. The
    -- cast message word-wraps, so we only ever see/match the first physical line.
    describe("area-effect spell badges", function()
        local CAST = "The warlock just discharged a storm of ice shards at hostile people in the"

        before_each(function()
            helper.simulateLine("Vitality:     50 / 60")
        end)

        it("stashes HP and requests a status check", function()
            helper.simulateLine(CAST)
            assert.are.equal(50, taPackage.aoeHpBefore)
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("badges the HP lost once the status returns", function()
            helper.simulateLine(CAST)
            helper.simulateLine("Vitality:     38 / 60")
            local badge = lastBadge()
            assert.are.equal(" AOE 12 ", badge.text)
            assert.are.equal("#ff5fd7", badge.color)
            assert.are.equal("#e0e0e0", badge.backgroundColor)
            assert.is_true(badge.bold)
            assert.is_nil(taPackage.aoeHpBefore)
        end)

        it("matches any caster and any area-effect spell", function()
            helper.simulateLine(
                "The ogre mage just discharged a wave of fire at hostile people in the")
            assert.are.equal(50, taPackage.aoeHpBefore)
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("does not badge if HP did not drop", function()
            helper.simulateLine(CAST)
            helper.simulateLine("Vitality:     50 / 60")
            assert.are.equal(0, #helper.cechoBgCalls)
        end)
    end)

end)

-- =========================================================================
-- hang-around-in-tavern
-- =========================================================================

describe("hang-around-in-tavern", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function lastSend()
        return helper.sendCalls[#helper.sendCalls]
    end

    describe("starting", function()

        it("refuses when not in a tavern/bar", function()
            taPackage.currentRoom = "north plaza"
            helper.simulateAlias("hang-around-in-tavern")
            assert.is_falsy(taPackage.tavernMode)
        end)

        it("enters tavern mode when the room is a tavern", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern")
            assert.is_true(taPackage.tavernMode)
        end)

        it("also accepts a bar room", function()
            taPackage.currentRoom = "village bar"
            helper.simulateAlias("hang-around-in-tavern")
            assert.is_true(taPackage.tavernMode)
        end)

        it("looks around and primes status on start", function()
            taPackage.currentRoom = "village tavern"
            helper.simulateAlias("hang-around-in-tavern")
            local looked, statused = false, false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "look" then looked = true end
                if cmd == "st" then statused = true end
            end
            assert.is_true(looked)
            assert.is_true(statused)
        end)

    end)

    describe("stopping", function()

        it("leaves tavern mode without exiting the game", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern")
            helper.sendCalls = {}
            helper.simulateAlias("stop-hang-around-in-tavern")
            assert.is_false(taPackage.tavernMode)
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

    end)

    describe("eating and drinking", function()

        before_each(function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern")
            helper.sendCalls = {}
        end)

        it("buys a meal when hungry", function()
            helper.simulateLine("You're hungry.")
            assert.are.equal("buy meal", lastSend())
        end)

        it("buys a drink when thirsty", function()
            helper.simulateLine("You're thirsty.")
            assert.are.equal("buy drink", lastSend())
        end)

    end)

    describe("out of tavern mode", function()

        it("does not buy meals when not hanging around", function()
            helper.simulateLine("You're hungry.")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("buy meal", cmd)
            end
        end)

    end)

    describe("exiting the game", function()

        before_each(function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern")
            helper.sendCalls = {}
        end)

        it("sends x when HP drops below 50%", function()
            helper.simulateLine("Vitality:     29 / 60")
            assert.are.equal("x", lastSend())
            assert.is_false(taPackage.tavernMode)
        end)

        it("stays in the game when HP is at or above 50%", function()
            helper.simulateLine("Vitality:     30 / 60")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
            assert.is_true(taPackage.tavernMode)
        end)

        it("sends x when a drink is unaffordable", function()
            helper.simulateLine("You can't afford drink.")
            assert.are.equal("x", lastSend())
            assert.is_false(taPackage.tavernMode)
        end)

        it("sends x when a meal is unaffordable", function()
            helper.simulateLine("You can't afford a meal.")
            assert.are.equal("x", lastSend())
            assert.is_false(taPackage.tavernMode)
        end)

        it("ignores low HP when not hanging around", function()
            helper.simulateAlias("stop-hang-around-in-tavern")
            helper.sendCalls = {}
            helper.simulateLine("Vitality:     5 / 60")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

    end)

end)

describe("message-me-when-you-see", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    it("pushes an ntfy notification the first time the phrase is seen", function()
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        assert.are.equal(0, #helper.httpRequestCalls)

        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)

        local call = helper.httpRequestCalls[1]
        assert.are.equal("https://ntfy.sh/s5bbs-tele-arena-j5", call.url)
        assert.are.equal("message-me-when-you-see", call.options.headers["X-Title"])
        assert.are.equal(
            "Heads up- I just saw: odd tingling sensation washes over",
            call.options.body)
    end)

    it("only fires once even if the phrase reappears", function()
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
    end)

    it("removes its own trigger after firing", function()
        local before = #helper.triggers
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        assert.are.equal(before + 1, #helper.triggers)
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(before, #helper.triggers)
    end)

    it("accepts an unquoted phrase", function()
        helper.simulateAlias("message-me-when-you-see odd tingling sensation washes over")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal(
            "Heads up- I just saw: odd tingling sensation washes over",
            helper.httpRequestCalls[1].options.body)
    end)

    it("stays silent until the phrase actually appears", function()
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("Nothing unusual happens.")
        assert.are.equal(0, #helper.httpRequestCalls)
    end)

end)
