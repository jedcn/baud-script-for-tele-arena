-- subchief_spec.lua
-- hit-subchief-and-let-him-heal. The wording is from Pelayo doing this by
-- hand (logs/session-pelayo-2026-11-15T20-13-02.log), wrapped as the BBS wraps it.

local helper = require("test.test_helper")

local DESC = "The orc subchief is a smallish humanoid with piglike facial features and is"
local HEALTHY = "to be in good physical health."
local WOUNDED = "to be moderately wounded."
local HIT = "Your attack hit the orc subchief for 55 damage!"
local BATTLE = "You cannot leave in the heat of battle!"

describe("hit-subchief-and-let-him-heal", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.exitGamePending = nil
    end)

    -- What the loop sends, less its `st` readings, which have a spec of their own.
    local function sends()
        local out = {}
        for _, c in ipairs(helper.sendCalls) do
            if c ~= "st" then out[#out + 1] = c end
        end
        return out
    end
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
        helper.simulateAlias("hit-subchief-and-let-him-heal")
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

    it("sends st at the start and as it leaves after a hit, not between swings", function()
        start()
        assert.are.same({ "st", "ex", "l sub" }, helper.sendCalls)
        lookReply("s,w", HEALTHY)
        clear()
        hit("subchief is lightly wounded.")
        hit("to be moderately wounded.")
        assert.are.same({ "l sub", "a sub", "l sub", "st", "s" }, helper.sendCalls)
    end)

    it("prints XP per round and per hour from its own st readings", function()
        start()
        helper.simulateLine("Experience:   61000000")
        lookReply("s,w", HEALTHY)
        hit("subchief is lightly wounded.")
        hit("to be moderately wounded.")
        helper.advanceMs(120000)
        helper.simulateLine("Experience:   61026000")
        assert.is_truthy(helper.echoCalls[#helper.echoCalls]:find(
            "Round: +26,000 XP from 2 hits (110 damage). Total +26,000 XP in 2m, 780,000 XP/hr.",
            1, true))
    end)

    it("ignores an st the player typed", function()
        start()
        helper.simulateLine("Experience:   61000000")
        local n = #helper.echoCalls
        helper.simulateLine("Experience:   61005000")
        assert.are.equal(n, #helper.echoCalls)
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

    it("swings again when he's wounded, and leaves once he's moderately wounded", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        hit("to be wounded.")
        assert.are.same({ "l sub", "a sub" }, sends())
        hit("to be moderately wounded.")
        assert.are.same({ "l sub", "a sub", "l sub", "s" }, sends())
    end)

    it("leaves a sorely wounded subchief alone", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        hit("The orc subchief is sorely wounded.")
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

    it("swings again when the game says it's too soon", function()
        start()
        lookReply("s,w", HEALTHY)
        clear()
        helper.simulateLine("You are still physically exhausted from your previous activities!")
        helper.fireTimers(3000)
        assert.are.same({ "a sub" }, sends())
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
        helper.fireTimers(20000)
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
        helper.fireTimers(20000)
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

    it("drinks water when thirsty", function()
        start()
        clear()
        helper.simulateLine("You're thirsty.")
        assert.are.same({ "drink water" }, sends())
        helper.simulateLine("The water quenches your thirst.")
        assert.is_true(taPackage.subchief.running())
    end)

    it("leaves the drink to the arena's trigger in a group", function()
        taPackage.followTarget = "Kerhak"
        start()
        clear()
        helper.simulateLine("You're thirsty.")
        assert.are.same({ "drink water" }, sends())   -- one, not two
    end)

    it("doesn't drink when it isn't running", function()
        helper.simulateLine("You're thirsty.")
        assert.are.same({}, sends())
    end)

    it("stops when the waterskin is empty", function()
        start()
        helper.simulateLine("You're thirsty.")
        helper.simulateLine("The waterskin is empty!")
        assert.is_false(taPackage.subchief.running())
    end)

    it("stops when there's no waterskin", function()
        start()
        helper.simulateLine("You're thirsty.")
        helper.simulateLine("Sorry, but you don't seem to have one.")
        assert.is_false(taPackage.subchief.running())
    end)

    describe("ntfy", function()
        local function ntfys()
            local out = {}
            for _, c in ipairs(helper.httpRequestCalls) do
                out[#out + 1] = { title = c.options.headers["X-Title"], body = c.options.body }
            end
            return out
        end

        before_each(function() taPackage._character.name = "Pelayo" end)

        it("leaves the game first when the loop ends on its own, then notifies", function()
            start()
            helper.simulateLine("Experience:   61000000")
            clear()
            helper.simulateLine('Sorry, you don\'t see "sub" nearby.')
            assert.are.same({ "x" }, sends())
            assert.are.same({}, ntfys())        -- not until we're out
            helper.simulateLine("Exiting Tele-Arena...")
            assert.are.equal(1, #ntfys())
            assert.are.equal("Subchief loop ended", ntfys()[1].title)
            assert.is_truthy(ntfys()[1].body:find(
                "Pelayo: Can't find the subchief here or next door. Out of the game.", 1, true))
        end)

        it("says why for running out of water", function()
            start()
            helper.simulateLine("You're thirsty.")
            helper.simulateLine("The waterskin is empty!")
            helper.simulateLine("Exiting Tele-Arena...")
            assert.is_truthy(ntfys()[1].body:find("Thirsty with no water", 1, true))
        end)

        it("notifies anyway if the game never confirms the exit", function()
            start()
            helper.simulateLine('Sorry, you don\'t see "sub" nearby.')
            helper.fireTimers(60000)
            assert.are.equal(1, #ntfys())
            assert.is_truthy(ntfys()[1].body:find("never confirmed the exit", 1, true))
            helper.simulateLine("Exiting Tele-Arena...")   -- late: no second one
            assert.are.equal(1, #ntfys())
        end)

        it("notifies when something else takes us out of the game", function()
            start()
            helper.simulateLine("Exiting Tele-Arena...")
            assert.is_false(taPackage.subchief.running())
            assert.is_truthy(ntfys()[1].body:find("Pelayo: Left the game.", 1, true))
        end)

        it("ends and notifies, sending nothing, when the connection drops", function()
            start()
            lookReply("s,w", HEALTHY)
            hit()
            arrive()                                  -- waiting next door
            clear()
            helper.simulateLine("Username: ")
            helper.fireTimers()
            assert.is_false(taPackage.subchief.running())
            -- The username is auto-login's; nothing of the loop's went out.
            for _, c in ipairs(sends()) do
                assert.is_nil(({ ex = 1, ["l sub"] = 1, x = 1, s = 1 })[c])
            end
            assert.are.equal(1, #ntfys())
            assert.is_truthy(ntfys()[1].body:find(
                "Pelayo: Disconnected from the game. Already out of the game.", 1, true))
        end)

        it("stops at its next timer if it missed the prompt", function()
            start()
            lookReply("s,w", HEALTHY)
            hit()
            arrive()
            taPackage.inGame = false
            clear()
            helper.fireTimers(20000)
            assert.are.same({}, sends())
            assert.is_false(taPackage.subchief.running())
        end)

        it("neither exits nor notifies when stopped by hand", function()
            start()
            clear()
            helper.simulateAlias("stop-hit-subchief")
            helper.simulateAlias("stop-all-scripts")
            helper.fireTimers(60000)
            assert.are.same({}, sends())
            assert.are.same({}, ntfys())
        end)

        it("sends an update every 30 minutes while running", function()
            start()
            helper.simulateLine("Experience:   61000000")
            lookReply("s,w", HEALTHY)
            hit()
            helper.advanceMs(30 * 60000)
            helper.simulateLine("Experience:   61450000")
            helper.fireTimers(30 * 60000)
            assert.are.same({ { title = "Subchief update",
                body = "Pelayo: 1 hits in 30m, +450,000 XP, 900,000 XP/hr." } }, ntfys())
            helper.fireTimers(30 * 60000)
            assert.are.equal(2, #ntfys())
            helper.simulateAlias("stop-hit-subchief")
            helper.fireTimers(30 * 60000)
            assert.are.equal(2, #ntfys())
        end)
    end)

    it("ignores that reply when we didn't ask for a drink", function()
        start()
        helper.simulateLine("Sorry, but you don't seem to have one.")
        assert.is_true(taPackage.subchief.running())
    end)

    -- 2026-11-17 02:12:34: a timer left over from an earlier step fired after
    -- the loop had moved on, and started a second chain of moves.
    it("drops a timer armed in a step the loop has since left", function()
        start()
        lookReply("s,w", HEALTHY)
        hit()                                   -- out s
        helper.simulateLine(BATTLE)             -- retry armed
        arrive()                                -- ...but the s went through
        clear()
        helper.fireTimers(3000)
        assert.are.same({}, sends())
        helper.fireTimers(20000)
        assert.are.same({ "ex", "l sub" }, sends())
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
        helper.fireTimers(20000)
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
