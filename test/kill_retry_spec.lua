-- kill_retry_spec.lua
-- After "physically exhausted" the kill loop waits out the melee recovery,
-- reckoned from the last swing the game accepted rather than from the refusal.

local helper = require("test.test_helper")

local EXHAUSTED = "You are still physically exhausted from your previous activities!"

describe("kill loop melee retry", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.setClass("Warrior")
        helper.simulateAlias("kill champion")
    end)

    local function lastTimer()
        return helper.timers[#helper.timers]
    end

    local function swings()
        local n = 0
        for _, call in ipairs(helper.sendCalls) do
            if call == "a champion" then n = n + 1 end
        end
        return n
    end

    it("waits out what is left of 34s since the last accepted swing", function()
        helper.simulateLine("Your attack hit the elven champion for 20 damage!")
        helper.advanceMs(6000)
        helper.simulateLine(EXHAUSTED)
        assert.are.equal(28000, lastTimer().interval)
    end)

    it("counts a miss and a dodge as accepted swings", function()
        helper.simulateLine("Your attack missed!")
        helper.advanceMs(1000)
        helper.simulateLine(EXHAUSTED)
        assert.are.equal(33000, lastTimer().interval)

        helper.simulateLine("The elven champion dodged your attack!")
        helper.advanceMs(2000)
        helper.simulateLine(EXHAUSTED)
        assert.are.equal(32000, lastTimer().interval)
    end)

    it("swings when the wait is over", function()
        helper.simulateLine("Your attack hit the elven champion for 20 damage!")
        helper.simulateLine(EXHAUSTED)
        local before = swings()
        helper.fireTimers(34000)
        assert.are.equal(before + 1, swings())
    end)

    it("asks again shortly if a retry past the mark is refused", function()
        helper.simulateLine("Your attack hit the elven champion for 20 damage!")
        helper.advanceMs(34000)
        helper.simulateLine(EXHAUSTED)
        assert.are.equal(3000, lastTimer().interval)
    end)

    it("asks again shortly with no swing to reckon from", function()
        helper.simulateLine(EXHAUSTED)
        assert.are.equal(3000, lastTimer().interval)
    end)

    it("drops the retry once the kill has stopped", function()
        helper.simulateLine(EXHAUSTED)
        helper.simulateAlias("kill-stop")
        local before = swings()
        helper.fireTimers(3000)
        assert.are.equal(before, swings())
    end)
end)
