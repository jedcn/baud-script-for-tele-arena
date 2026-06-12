-- main_spec.lua
-- Tests for triggers and status display in main.lua

local helper = require("test.test_helper")

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

        it("does not fire on unrelated lines", function()
            helper.simulateLine("You are carrying a shortsword.")
            assert.is_nil(getGold())
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
            assert.are.equal("?", segments[2].text)  -- Vitality
            assert.are.equal("?", segments[4].text)  -- XP
            assert.are.equal("?", segments[6].text)  -- Status
            assert.are.equal("?", segments[8].text)  -- Gold
        end)

        it("shows captured Vitality as current/max", function()
            helper.simulateLine("Vitality:     26 / 26")
            local segments = capturedFn()
            assert.are.equal("26/26", segments[2].text)
        end)

        it("shows captured Experience value", function()
            helper.simulateLine("Experience:   354")
            local segments = capturedFn()
            assert.are.equal("354", segments[4].text)
        end)

        it("shows captured Status value", function()
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("Healthy", segments[6].text)
        end)

        it("shows all values after a full status block", function()
            helper.simulateLine("Vitality:     10 / 26")
            helper.simulateLine("Experience:   354")
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("10/26", segments[2].text)
            assert.are.equal("354", segments[4].text)
            assert.are.equal("Healthy", segments[6].text)
        end)

    end)

end)
