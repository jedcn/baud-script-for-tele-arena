-- team_champions_spec.lua
-- team-fight-champions: the wording here is taken from logs of the group doing
-- this by hand (logs/session-pelayo-2026-11-01T21-53-00.log).

local helper = require("test.test_helper")

local THREE = "There are three elven champions here."
local TWO = "There are two elven champions here."
local ONE = "There is an elven champion here."
local NONE = nil

describe("team-fight-champions", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.setClass("High Priest")
    end)

    local function room(occupants)
        if occupants then helper.simulateLine(occupants) end
        helper.simulateLine("Kerhak, Castor, Pollux, and Teekywiki are here.")
        helper.simulateLine("There is nothing on the floor.")
    end

    local function group(state, health, exits)
        helper.simulateLine("Your group currently consists of:")
        helper.simulateLine("  Pelayo                         (L) [HE:100% ST:" .. state .. "]")
        helper.simulateLine("  Pollux                             [HE:" .. (health or 100) .. "% ST:" .. state .. "]")
        helper.simulateLine("Exits: " .. (exits or "e,w") .. ".")
    end

    local function sent(text)
        for _, call in ipairs(helper.sendCalls) do
            if call == text then return true end
        end
        return false
    end

    local function clearSent()
        for k in pairs(helper.sendCalls) do helper.sendCalls[k] = nil end
    end

    local function lastEcho()
        return helper.echoCalls[#helper.echoCalls]
    end

    local function start(occupants)
        helper.simulateAlias("team-fight-champions")
        room(occupants or THREE)
    end

    local function kill()
        helper.simulateLine("The elven champion falls to the ground lifeless!")
    end

    -- A champion leaves, the rest die, and the group musters for the chase.
    local function fleeWestThenClear()
        start()
        helper.simulateLine("The elven champion has just gone to the west.")
        kill()
        room(TWO)
        kill()
        room(ONE)
        kill()
        room(NONE)
    end

    -- The room prints on arrival, then again for the scan once followers land.
    local function arrive(occupants)
        room(occupants)
        helper.fireTimers(1000)
        room(occupants)
    end

    describe("countChampions", function()
        local count = function(s) return taPackage.teamChampions.countChampions(s) end

        it("reads the occupant line", function()
            assert.are.equal(1, count("an elven champion"))
            assert.are.equal(3, count("three elven champions"))
            assert.are.equal(5, count("five elven champions"))
            assert.are.equal(2, count("two elven champions, and an elven warrior"))
            assert.are.equal(0, count("an elven warrior"))
        end)

        it("treats an unknown count word as more than one", function()
            assert.are.equal(2, count("several elven champions"))
        end)
    end)

    describe("ringNext", function()
        local nextExit = function(...) return taPackage.teamChampions.ringNext(...) end

        it("goes straight on, including through the junction", function()
            assert.are.equal("w", nextExit({ "e", "w" }, "w"))
            assert.are.equal("w", nextExit({ "e", "s", "w" }, "w"))
        end)

        it("turns a corner by the exit we did not come in by", function()
            assert.are.equal("n", nextExit({ "e", "n" }, "w"))
        end)

        it("gives up where the way on is not one exit", function()
            assert.is_nil(nextExit({ "n", "s", "e" }, "w"))
            assert.is_nil(nextExit({ "e" }, "w"))
        end)
    end)

    it("refuses to run without a High Priest", function()
        taPackage.character.setClass("Warrior")
        helper.simulateAlias("team-fight-champions")
        assert.is_false(taPackage.teamChampions.running())
    end)

    it("sends the group and the leader at the champions", function()
        start()
        assert.is_true(sent("confer kill champion"))
        assert.is_true(sent("a champion"))
    end)

    it("does not re-engage while the kill loop is running", function()
        start()
        clearSent()
        room(THREE)
        assert.is_false(sent("confer kill champion"))
    end)

    it("re-engages after a death, which ends every kill loop", function()
        start()
        kill()
        clearSent()
        room(TWO)
        assert.is_true(sent("confer kill champion"))
    end)

    it("succeeds once the starting room is empty", function()
        start(ONE)
        kill()
        room(NONE)
        assert.is_false(taPackage.teamChampions.running())
        assert.is_truthy(lastEcho():find("1 killed", 1, true))
    end)

    describe("healing", function()
        it("casts group heal when someone is below 85%", function()
            start()
            group("Resting", 84)
            assert.is_true(sent("cast kusamotumaru"))
        end)

        it("leaves a scratch alone", function()
            start()
            group("Resting", 85)
            assert.is_false(sent("cast kusamotumaru"))
        end)

        it("polls the group during the fight", function()
            start()
            clearSent()
            helper.fireTimers(3000)
            assert.is_true(sent("group"))
        end)
    end)

    describe("chasing", function()
        it("finishes the room before chasing", function()
            start()
            helper.simulateLine("The elven champion has just gone to the west.")
            room(TWO)
            group("Ready")
            assert.is_false(sent("w"))
        end)

        it("stands the group down and waits for everyone to be Ready", function()
            fleeWestThenClear()
            assert.is_true(sent("confer kill-stop"))
            group("Resting")
            assert.is_false(sent("w"))
            group("Ready")
            assert.is_true(sent("w"))
        end)

        it("kills the one it finds next door, then walks back and finishes", function()
            fleeWestThenClear()
            group("Ready")
            clearSent()
            arrive(ONE)
            assert.is_true(sent("confer kill champion"))
            kill()
            room(NONE)
            group("Ready")
            assert.is_true(sent("e"))
            room(NONE)
            assert.is_false(taPackage.teamChampions.running())
        end)

        it("follows the ring round a corner when he isn't one room away", function()
            fleeWestThenClear()
            group("Ready")
            room(NONE)
            clearSent()
            group("Ready", 100, "e,n")
            assert.is_true(sent("n"))
        end)

        it("heads home from two or more, and says the chase was given up", function()
            fleeWestThenClear()
            group("Ready")
            clearSent()
            room(TWO)
            assert.is_false(sent("confer kill champion"))
            group("Ready")
            assert.is_true(sent("e"))
            room(NONE)
            assert.is_false(taPackage.teamChampions.running())
            assert.is_truthy(lastEcho():find("1 chase(s) given up", 1, true))
        end)

        it("fights a lone champion on the way home", function()
            fleeWestThenClear()
            group("Ready")
            room(NONE)
            group("Ready")
            room(TWO)
            group("Ready")
            clearSent()
            arrive(ONE)
            assert.is_true(sent("confer kill champion"))
        end)

        it("fights whatever is at home when it gets back", function()
            fleeWestThenClear()
            group("Ready")
            room(TWO)
            group("Ready")
            clearSent()
            arrive(THREE)
            assert.is_true(sent("confer kill champion"))
        end)

        it("gives up after ten rooms and walks all of them back", function()
            fleeWestThenClear()
            for _ = 1, 10 do
                group("Ready")
                room(NONE)
            end
            clearSent()
            group("Ready")
            assert.is_true(sent("e"))
            for _ = 1, 9 do
                room(NONE)
                group("Ready")
            end
            room(NONE)
            assert.is_false(taPackage.teamChampions.running())
        end)

        it("turns to follow one that flees from a chase fight", function()
            fleeWestThenClear()
            group("Ready")
            arrive(ONE)
            helper.simulateLine("The elven champion has just gone to the south.")
            kill()
            room(NONE)
            clearSent()
            group("Ready", 100, "e,s,w")
            assert.is_true(sent("s"))
        end)

        it("skips the chase if the champion came back by itself", function()
            start()
            helper.simulateLine("The elven champion has just gone to the west.")
            helper.simulateLine("An elven champion has just arrived from the west.")
            kill()
            room(NONE)
            assert.is_false(taPackage.teamChampions.running())
        end)

        it("does not count a move the game refused", function()
            fleeWestThenClear()
            group("Ready")
            helper.simulateLine("You cannot leave in the heat of battle!")
            room(NONE)
            clearSent()
            group("Ready")
            assert.is_true(sent("w"))
            arrive(ONE)
            kill()
            room(NONE)
            group("Ready")
            room(NONE)
            -- One step out, so one step back: the refused move left no trace.
            assert.is_false(taPackage.teamChampions.running())
        end)

        it("stops rather than waits forever when a move goes nowhere", function()
            fleeWestThenClear()
            group("Ready")
            helper.fireTimers(3000)
            helper.fireTimers(3000)
            helper.fireTimers(3000)
            assert.is_false(taPackage.teamChampions.running())
        end)
    end)

    it("clears a kill loop whose target walked out, so the next scan restarts it", function()
        start()
        helper.simulateLine('Sorry, you don\'t see "champion" nearby.')
        assert.is_falsy(taPackage.killActive)
        clearSent()
        room(ONE)
        assert.is_true(sent("confer kill champion"))
    end)

    it("ignores everything once it has stopped", function()
        start()
        helper.simulateAlias("stop-team-fight-champions")
        clearSent()
        kill()
        room(THREE)
        group("Ready", 10)
        assert.is_nil(next(helper.sendCalls))
    end)

    it("stop-team-fight-champions stands the group down", function()
        start()
        clearSent()
        helper.simulateAlias("stop-team-fight-champions")
        assert.is_true(sent("confer kill-stop"))
        assert.is_false(taPackage.teamChampions.running())
        assert.is_falsy(taPackage.killActive)
    end)

    it("stop-all-scripts stops it too", function()
        start()
        clearSent()
        helper.simulateAlias("stop-all-scripts")
        assert.is_true(sent("confer kill-stop"))
        assert.is_false(taPackage.teamChampions.running())
    end)
end)
