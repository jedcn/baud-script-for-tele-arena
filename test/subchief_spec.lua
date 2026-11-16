-- subchief_spec.lua
-- hit-subchief-once-and-let-him-heal. The wording is from Pelayo doing this by
-- hand (logs/session-pelayo-2026-11-15T20-13-02.log), wrapped as the BBS wraps it.

local helper = require("test.test_helper")

local DESC = "The orc subchief is a smallish humanoid with piglike facial features and is"
local HEALTHY = "to be in good physical health."
local WOUNDED = "to be moderately wounded."
local HIT = "Your attack hit the orc subchief for 55 damage!"
local BATTLE = "You cannot leave in the heat of battle!"

describe("hit-subchief-once-and-let-him-heal", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.exitGamePending = nil
    end)

    local function sends() return helper.sendCalls end
    local function clear() helper.sendCalls = {} end

    local function lookReply(exits, health)
        helper.simulateLine("Exits: " .. exits .. ".")
        helper.simulateLine(DESC)
        helper.simulateLine(health)
    end

    -- The hit, then the look after it.
    local function hit(after)
        helper.simulateLine(HIT)
        helper.simulateLine(DESC)
        helper.simulateLine(after or "to be moderately wounded.")
    end

    local function arrive()
        helper.simulateLine("You're in a cave.")
    end

    local function start()
        helper.simulateAlias("hit-subchief-once-and-let-him-heal")
    end

    it("looks first", function()
        start()
        assert.are.same({ "ex", "l sub" }, sends())
    end)

    it("hits a healthy subchief once, then leaves by the first exit", function()
        start()
        clear()
        lookReply("s,w", HEALTHY)
        assert.are.same({ "a sub" }, sends())
        hit()
        assert.are.same({ "a sub", "l sub", "s" }, sends())
    end)

    it("looks after the hit and says what it left him at", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        helper.simulateLine(HIT)
        assert.are.same({ "l sub" }, sends())
        helper.simulateLine(DESC)
        helper.simulateLine(WOUNDED)
        assert.are.same({ "l sub", "s" }, sends())
        assert.is_truthy(helper.echoCalls[#helper.echoCalls]:find(
            "Hit 1 for 55, leaving him moderately wounded.", 1, true))
    end)

    it("names each condition the look can report", function()
        local said = {}
        for _, line in ipairs({
            "subchief is lightly wounded.",
            "to be wounded.",
            "to be moderately wounded.",
            "The orc subchief is sorely wounded.",
        }) do
            helper.resetAll()
            dofile("main.lua")
            start()
            lookReply("s,w", HEALTHY)
            hit(line)
            said[#said + 1] = helper.echoCalls[#helper.echoCalls]:match("leaving him ([^;.]+)")
        end
        assert.are.same({ "lightly wounded", "wounded", "moderately wounded",
            "sorely wounded" }, said)
    end)

    it("swings again when the hit left him only lightly wounded", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        hit("subchief is lightly wounded.")
        assert.are.same({ "l sub", "a sub" }, sends())
        hit("to be moderately wounded.")
        assert.are.same({ "l sub", "a sub", "l sub", "s" }, sends())
    end)

    it("leaves once he's merely wounded", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        hit("to be wounded.")
        assert.are.same({ "l sub", "s" }, sends())
    end)

    it("still leaves if he fled from the hit", function()
        start()
        lookReply("s,w", HEALTHY)
        helper.simulateLine(HIT)
        clear()
        helper.simulateLine('Sorry, you don\'t see "sub" nearby.')
        assert.are.same({ "s" }, sends())
    end)

    it("swings again after a miss or a dodge, not after a hit", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        helper.simulateLine("Your attack missed!")
        assert.are.same({}, sends())
        helper.fireTimers(3000)
        assert.are.same({ "a sub" }, sends())
        helper.simulateLine("The orc subchief dodged your attack!")
        helper.fireTimers(3000)
        assert.are.same({ "a sub", "a sub" }, sends())
    end)

    it("retries the move out until the game lets us go", function()
        start()
        lookReply("n,se", HEALTHY)
        hit()
        clear()
        helper.simulateLine(BATTLE)
        helper.fireTimers(3000)
        helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
        helper.fireTimers(3000)
        assert.are.same({ "n", "n" }, sends())
    end)

    -- The room he fled into on 2026-11-15: out by ne, back by s.
    it("waits next door, then asks the way back instead of reversing", function()
        start()
        lookReply("ne,nw", HEALTHY)
        hit()       -- out ne
        arrive()
        clear()
        helper.fireTimers(30000)
        assert.are.same({ "ex", "l sub" }, sends())
        helper.simulateLine("Exits: s.")
        helper.simulateLine("The orc subchief is to the south!")
        arrive()
        assert.are.same({ "ex", "l sub", "s", "ex", "l sub" }, sends())
    end)

    it("swings at once if he walked into the room we're waiting in", function()
        start()
        lookReply("ne,nw", HEALTHY)
        hit()
        arrive()
        helper.fireTimers(30000)
        clear()
        lookReply("s", HEALTHY)
        assert.are.same({ "a sub" }, sends())
    end)

    it("doesn't hit a wounded subchief; steps out and gives him longer", function()
        start()
        clear()
        lookReply("ne,nw", WOUNDED)
        assert.are.same({ "ne" }, sends())
    end)

    it("follows him when he has moved next door", function()
        start()
        clear()
        helper.simulateLine("Exits: n,s.")
        helper.simulateLine("The orc subchief is to the south!")
        assert.are.same({ "s" }, sends())
        arrive()
        assert.are.same({ "s", "ex", "l sub" }, sends())
        clear()
        lookReply("ne,nw", HEALTHY)
        hit()
        assert.are.same({ "a sub", "l sub", "ne" }, sends())
    end)

    it("stops when he can't be found", function()
        start()
        helper.simulateLine('Sorry, you don\'t see "sub" nearby.')
        assert.is_false(taPackage.subchief.running())
    end)

    it("stops on stop-hit-subchief and ignores its timers after", function()
        start()
        lookReply("s,w", HEALTHY)
        hit()
        arrive()
        helper.simulateAlias("stop-hit-subchief")
        clear()
        helper.fireTimers()
        assert.are.same({}, sends())
    end)

    it("is stopped by stop-all-scripts", function()
        start()
        helper.simulateAlias("stop-all-scripts")
        assert.is_false(taPackage.subchief.running())
    end)

    it("stops once the guard is taking us out of the game", function()
        start()
        lookReply("s,w", HEALTHY)
        hit()
        arrive()
        taPackage.exitGamePending = true
        clear()
        helper.fireTimers(30000)
        assert.are.same({}, sends())
        assert.is_false(taPackage.subchief.running())
    end)

    it("leaves the guard watching our HP", function()
        taPackage.character.setClass("High Priest")
        taPackage.inGame = true
        start()
        taPackage.character.setVitality(900, 1750)
        clear()
        helper.simulateLine("The orc subchief attacked you with his flail for 100 damage!")
        assert.are.same({ "x" }, sends())
    end)
end)
