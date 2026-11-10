-- guard_spec.lua
-- The guard: leave the game when hurt with no script running. The case it is
-- for is Pelayo's death of 2026-11-09 (logs/session-pelayo-2026-11-09T09-48-20.log):
-- two elven champions, no script, eight minutes.

local helper = require("test.test_helper")

local HIT = "The elven champion attacked you with his shining sword for 100 damage!"

describe("guard", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.setClass("High Priest")
        taPackage.exitGamePending = nil
        taPackage.inGame = true
    end)

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

    it("leaves the game below half with no script running", function()
        hitBelowHalf()
        assert.are.equal(1, count("x"))
        assert.is_true(echoed("[guard] Down to 800 HP (under 859)"))
    end)

    it("sends a notification saying who left and why", function()
        taPackage._character.name = "Pelayo"
        hitBelowHalf()
        assert.are.equal(1, #helper.httpRequestCalls)
        local call = helper.httpRequestCalls[1]
        assert.are.equal("Left the game hurt", call.options.headers["X-Title"])
        assert.are.equal(
            "Pelayo was down to 800 of 1718 HP with no script running, and is leaving the game.",
            call.options.body)
    end)

    it("sends one notification, not one per hit", function()
        hitBelowHalf()
        helper.simulateLine(HIT)
        assert.are.equal(1, #helper.httpRequestCalls)
    end)

    it("sends no notification above half", function()
        taPackage.character.setVitality(1000, 1718)
        helper.simulateLine(HIT)
        assert.are.equal(0, #helper.httpRequestCalls)
    end)

    it("doesn't heal or move first", function()
        hitBelowHalf()
        assert.are.same({ "x" }, helper.sendCalls)
    end)

    it("keeps sending x every 2s until the game lets us out", function()
        hitBelowHalf()
        helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
        helper.fireTimers(2000)
        assert.are.equal(2, count("x"))
        helper.simulateLine("Exiting Tele-Arena...")
        helper.fireTimers(2000)
        assert.are.equal(2, count("x"))
    end)

    it("starts no second exit on the next hit", function()
        hitBelowHalf()
        helper.simulateLine(HIT)
        assert.are.equal(1, count("x"))
    end)

    it("stays put above half", function()
        taPackage.character.setVitality(1000, 1718)
        helper.simulateLine(HIT)
        assert.are.equal(0, count("x"))
    end)

    it("stays put when vitality is unknown", function()
        helper.simulateLine(HIT)
        assert.are.equal(0, count("x"))
    end)

    it("leaves it to a script that is running", function()
        taPackage.killActive = true
        hitBelowHalf()
        assert.are.equal(0, count("x"))
    end)

    it("still acts while only the follow XP poll is running", function()
        taPackage.followXpPollActive = true
        hitBelowHalf()
        assert.are.equal(1, count("x"))
    end)
end)
