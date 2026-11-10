-- guard_spec.lua
-- The guard: heal, then flee, when hurt with no script running. The case it is
-- for is Pelayo's death of 2026-11-09 (logs/session-pelayo-2026-11-09T09-48-20.log):
-- two elven champions, no script, eight minutes.

local helper = require("test.test_helper")

local HIT = "The elven champion attacked you with his shining sword for 100 damage!"

describe("guard", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.setClass("High Priest")
        -- Walk in from the southeast, as Pelayo did.
        helper.simulateAlias("nw")
        helper.simulateLine("You're in the guild hall.")
        for k in pairs(helper.sendCalls) do helper.sendCalls[k] = nil end
        for k in pairs(helper.echoCalls) do helper.echoCalls[k] = nil end
    end)

    local function sent(text)
        for _, call in ipairs(helper.sendCalls) do
            if call == text then return true end
        end
        return false
    end

    local function count(text)
        local n = 0
        for _, call in ipairs(helper.sendCalls) do
            if call == text then n = n + 1 end
        end
        return n
    end

    local function echoed(fragment)
        for _, e in ipairs(helper.echoCalls) do
            if e:find(fragment, 1, true) then return true end
        end
        return false
    end

    -- 900 of 1718 is just above half (859); the hit takes it to 800.
    local function hitBelowHalf()
        taPackage.character.setVitality(900, 1718)
        helper.simulateLine(HIT)
    end

    it("heals and steps back the way we came in, below half with no script running", function()
        hitBelowHalf()
        assert.is_true(sent("cast kusamotumaru"))
        assert.is_true(sent("se"))
        assert.is_true(echoed("[guard] Down to 800 HP (under 859)"))
    end)

    it("stays put above half", function()
        taPackage.character.setVitality(1000, 1718)
        helper.simulateLine(HIT)
        assert.is_false(sent("se"))
        assert.is_false(sent("cast kusamotumaru"))
    end)

    it("stays put when vitality is unknown", function()
        helper.simulateLine(HIT)
        assert.are.equal(0, #helper.sendCalls)
    end)

    it("leaves it to a script that is running", function()
        taPackage.killActive = true
        hitBelowHalf()
        assert.is_false(sent("se"))
        assert.is_false(sent("cast kusamotumaru"))
    end)

    it("still acts while only the follow XP poll is running", function()
        taPackage.followXpPollActive = true
        hitBelowHalf()
        assert.is_true(sent("se"))
    end)

    it("doesn't cast without the group heal", function()
        taPackage.character.setClass("Warrior")
        hitBelowHalf()
        assert.is_false(sent("cast kusamotumaru"))
        assert.is_true(sent("se"))
    end)

    it("tries the step again 2s after it is refused", function()
        hitBelowHalf()
        helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
        assert.are.equal(1, count("se"))
        helper.fireTimers(2000)
        assert.are.equal(2, count("se"))
    end)

    it("tries again when held in combat, and takes the step off the arrival queue", function()
        hitBelowHalf()
        helper.simulateLine("You cannot leave in the heat of battle!")
        assert.are.equal(0, #taPackage.pendingDirs)
        helper.fireTimers(2000)
        assert.are.equal(2, count("se"))
    end)

    it("is done once it arrives, and a hit there starts the next flee", function()
        hitBelowHalf()
        helper.simulateLine("You're in the north plaza.")
        assert.is_true(echoed("[guard] Out, went se."))
        assert.is_false(taPackage.guard.fleeing())
        helper.simulateLine(HIT)
        -- Back the way it just came in: se into the plaza, so nw out of it.
        assert.is_true(sent("nw"))
    end)

    it("doesn't take a reprinted room for an arrival", function()
        hitBelowHalf()
        helper.simulateLine("In your haste, you trip and fall!")
        helper.simulateLine("You're in the guild hall.")
        assert.is_true(taPackage.guard.fleeing())
        helper.fireTimers(2000)
        assert.are.equal(2, count("se"))
    end)

    it("asks for the exits when it doesn't know the way in", function()
        taPackage.lastArrivalDir = nil
        hitBelowHalf()
        assert.is_true(sent("ex"))
        helper.simulateLine("Exits: n,s,d.")
        assert.is_true(sent("n"))
    end)

    it("asks for the exits when the way in isn't there", function()
        hitBelowHalf()
        helper.simulateLine("Sorry, there's no exit in that direction.")
        assert.is_true(sent("ex"))
        helper.simulateLine("Exits: w,e.")
        assert.is_true(sent("w"))
    end)

    it("gives up after 15 tries", function()
        hitBelowHalf()
        for _ = 1, 15 do
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            helper.fireTimers(2000)
        end
        assert.are.equal(15, count("se"))
        assert.is_true(echoed("[guard] Still here after 15 tries"))
        assert.is_false(taPackage.guard.fleeing())
    end)

    it("stop-all-scripts stops a flee", function()
        hitBelowHalf()
        helper.simulateAlias("stop-all-scripts")
        assert.is_true(echoed("[all] Stopped guard."))
        helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
        helper.fireTimers(2000)
        assert.are.equal(1, count("se"))
    end)
end)
