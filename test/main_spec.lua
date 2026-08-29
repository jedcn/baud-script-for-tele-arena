-- main_spec.lua
-- Tests for triggers and status display in main.lua

local helper = require("test.test_helper")

-- True when `list` (e.g. helper.echoCalls) contains `value`. Handy for asserting
-- an echo was emitted without depending on its position among other echoes.
local function tableContains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Was `text` run through runCommand or sent? Handy where a command may take
-- either path (send for a plain game command, runCommand for an alias).
local function ranCommandGlobal(text)
    return tableContains(helper.runCommandCalls, text)
        or tableContains(helper.sendCalls, text)
end

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

    -- `buy promotion` at level 25 renames the class and restarts the character
    -- at level 1 / 0 XP on a 105-level ladder (docs/shrine/PROMOTED_EXP_CHART.md).
    describe("promoted classes", function()

        it("a freshly promoted Knight is level 1 with a next threshold", function()
            assert.are.equal(1, getLevelForXp(0, "Knight"))
            assert.are.equal(71136, getXpForNextLevel(0, "Knight"))
        end)

        it("Knight level 2 threshold is 71136", function()
            assert.are.equal(2, getLevelForXp(71136, "Knight"))
            assert.are.equal(1, getLevelForXp(71135, "Knight"))
        end)

        it("Knight, Master Archer and Beast Master share the same ladder", function()
            assert.are.equal(getXpForNextLevel(0, "Knight"), getXpForNextLevel(0, "Master Archer"))
            assert.are.equal(getXpForNextLevel(0, "Knight"), getXpForNextLevel(0, "Beast Master"))
        end)

        it("High Priest and Necromancer share the same ladder", function()
            assert.are.equal(79976, getXpForNextLevel(0, "High Priest"))
            assert.are.equal(getXpForNextLevel(0, "High Priest"), getXpForNextLevel(0, "Necromancer"))
        end)

        it("Arch Druid and Arch Magus share the same ladder", function()
            assert.are.equal(91520, getXpForNextLevel(0, "Arch Druid"))
            assert.are.equal(getXpForNextLevel(0, "Arch Druid"), getXpForNextLevel(0, "Arch Magus"))
        end)

        it("Blackguard has a ladder of its own", function()
            assert.are.equal(69680, getXpForNextLevel(0, "Blackguard"))
        end)

        it("the ladder runs to level 105, not 25", function()
            assert.are.equal(26, getLevelForXp(39866400, "Knight"))
            assert.are.equal(105, getLevelForXp(5158539075, "Knight"))
            assert.is_nil(getXpForNextLevel(5158539075, "Knight"))
        end)

    end)

    -- The crash that motivated the tables: a promoted class the script had no
    -- table for indexed a nil `thresholds`, which took the status bar down.
    describe("an unknown class", function()

        it("returns nil rather than erroring or borrowing the Warrior ladder", function()
            assert.is_nil(getLevelForXp(354, "Squire"))
            assert.is_nil(getXpForNextLevel(354, "Squire"))
        end)

        it("leaves hasUntrainedLevel false", function()
            helper.simulateLine("Class:        Squire")
            helper.simulateLine("Level:        1")
            helper.simulateLine("Experience:   354")
            assert.is_false(hasUntrainedLevel())
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

        it("records an item found while searching, against the current room, once", function()
            taPackage.lastKilledMonster = "anaconda"
            taPackage.mapping = true
            taPackage.currentRoomId = 54
            helper.simulateLine("While searching the area, you notice a ruby key, which you add to your possessions.")
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_not_nil(call)
            assert.are.equal("anaconda", call.params[1])
            assert.are.equal("a ruby key", call.params[2])
            assert.are.equal(54, call.params[4])   -- room_id
            -- one-line and wrapped triggers are mutually exclusive: exactly one fires
            local n = 0
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute" and string.find(c.sql, "INSERT INTO item_drops", 1, true) then n = n + 1 end
            end
            assert.are.equal(1, n)
        end)

        it("records the wrapped first-line pickup (game split it across two lines)", function()
            taPackage.lastKilledMonster = "anaconda"
            taPackage.mapping = true
            taPackage.currentRoomId = 54
            helper.simulateLine("While searching the area, you notice a ruby key, which you add to your")
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_not_nil(call)
            assert.are.equal("a ruby key", call.params[2])
            assert.are.equal(54, call.params[4])
        end)

        it("records an item noticed but not carried (inventory full) against the room", function()
            taPackage.lastKilledMonster = "anaconda"
            taPackage.mapping = true
            taPackage.currentRoomId = 54
            helper.simulateLine("While searching the area, you notice a ruby key, but you can't carry it.")
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_not_nil(call)
            assert.are.equal("anaconda", call.params[1])
            assert.are.equal("a ruby key", call.params[2])
            assert.are.equal(54, call.params[4])   -- room_id -- item still in this room
        end)

        it("leaves the pickup room NULL when not mapping (currentRoomId is stale)", function()
            taPackage.lastKilledMonster = "anaconda"
            taPackage.mapping = false
            taPackage.currentRoomId = 999   -- stale anchor from an old session
            helper.simulateLine("While searching the area, you notice a ruby key, which you add to your possessions.")
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_not_nil(call)
            assert.is_nil(call.params[4])
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

        -- The "very powerful" heal line is long enough that Tele-Arena's
        -- server-side wrap pushes " damage!" onto the next physical line, so the
        -- trigger sees only "...which healed 129" and the trailing "damage!"
        -- arrives as a separate, ignored line.
        it("increases vitality for a wrapped very-powerful heal (no trailing damage!)", function()
            helper.simulateLine("Vitality:    20 / 200")
            helper.simulateLine("Pelayo just intoned a very powerful healing spell for you which healed 129")
            helper.simulateLine("damage!")
            local current, max = getVitality()
            assert.are.equal(149, current)
            assert.are.equal(200, max)
        end)

    end)

    -- =========================================================================
    -- Incoming damage trigger
    -- =========================================================================

    describe("AOE spell trigger", function()

        it("runs st when an AOE spell is cast (wrapped first line)", function()
            helper.simulateLine("The warlock just discharged a storm of ice shards at hostile monsters in the")
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("runs st when the AOE line is not wrapped", function()
            helper.simulateLine("The warlock just discharged a storm of ice shards at hostile monsters in the area!")
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("ignores a single-target discharge", function()
            helper.simulateLine("Johnsonite just discharged a small shard of ice at the huge rat!")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

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

        it("reduces vitality for a hydra's fireball", function()
            helper.simulateLine("Vitality:    100 / 100")
            helper.simulateLine("The hydra expelled a ball of fire at you for 78 damage!")
            local current, max = getVitality()
            assert.are.equal(22, current)
            assert.are.equal(100, max)
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

    -- Thirty seconds of silence is indistinguishable from a hang, and the only
    -- line printed nearby is a stale "melee-retry", which reads like "still
    -- fighting". That pair cost a real training trip in
    -- logs/session-garbageman-2026-08-15T19-21-55.log.
    describe("refused move announces its retry", function()

        it("says what it will retry and when", function()
            taPackage.arenaState = "training"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            local said = false
            for _, text in ipairs(helper.echoCalls) do
                if text and text:find("refused (still resting)", 1, true)
                    and text:find("\"w\"", 1, true) then
                    said = true
                end
            end
            assert.is_true(said)
        end)

        it("is silent outside an arena run", function()
            local before = #helper.echoCalls
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.are.equal(before, #helper.echoCalls)
        end)

    end)

    -- A general facility, not an arena or gold-farming one: any script can read
    -- taPackage.died. Wording from
    -- logs/session-kerhak-2026-08-09T14-48-21.log lines 3243-3246.
    -- One round of potions, at the start, never refreshed. The farming run is a
    -- sprint to a single level, not an open-ended grind, so a second round can
    -- only push the finish line out: re-drinking at t+10 re-imposes a 10-minute
    -- training taint, and a level earned at t+11 could not be banked until t+20.
    describe("potion restock during a gold-farming run", function()

        local LAPSED = "An odd tingling sensation washes over you briefly!"

        it("does not head back to the shop", function()
            helper.simulateAlias("start-gold-farming")
            taPackage.arenaState = "fighting"
            taPackage.arenaPotionsActive = 2
            helper.simulateLine(LAPSED)
            assert.is_falsy(taPackage.needsPotions)
            assert.are_not.equal("potions", taPackage.arenaState)
        end)

        it("still counts the potion down so training can proceed", function()
            helper.simulateAlias("start-gold-farming")
            taPackage.arenaState = "fighting"
            taPackage.arenaPotionsActive = 2
            helper.simulateLine(LAPSED)
            assert.are.equal(1, taPackage.arenaPotionsActive)
            helper.simulateLine(LAPSED)
            assert.are.equal(0, taPackage.arenaPotionsActive)
        end)

        -- An ordinary arena run is an open-ended grind and still restocks.
        it("leaves an ordinary arena run restocking as before", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaPotionsActive = 2
            setClass("Warrior")
            helper.simulateLine(LAPSED)
            assert.is_true(taPackage.needsPotions)
        end)

    end)

    -- Carried gold does not survive being cut off. On 2026-08-15 Kerhak was
    -- handed 10,617 gold, banked 5,500, and the ~5,100 still on him when the
    -- connection dropped at the last warning was gone in the morning.
    describe("nightly BBS shutdown", function()

        -- First line of the warning block. The second carries the countdown and
        -- so changes; this one is identical at 5, 4, 3, 2 and 1 minutes.
        local WARNING = "Sorry to interrupt here, but the BBS will be shutting"

        it("leaves the game", function()
            helper.simulateLine(WARNING)
            assert.is_true(tableContains(helper.sendCalls, "x"))
        end)

        it("stops every running script first", function()
            taPackage.arenaState = "fighting"
            taPackage.killActive = true
            helper.simulateLine(WARNING)
            assert.is_nil(taPackage.arenaState)
            assert.is_falsy(taPackage.killActive)
        end)

        it("says so in the log and notifies", function()
            helper.simulateLine(WARNING)
            local said = false
            for _, text in ipairs(helper.echoCalls) do
                if text and text:find("[shutdown]", 1, true) then said = true end
            end
            assert.is_true(said)
            assert.is_true(#helper.httpRequestCalls > 0)
        end)

        -- The warning repeats five times; the retry loop is already working.
        it("acts once per session", function()
            helper.simulateLine(WARNING)
            local sent = #helper.sendCalls
            helper.simulateLine(WARNING)
            helper.simulateLine(WARNING)
            assert.are.equal(sent, #helper.sendCalls)
        end)

        -- "x" is treated like a move and is refused while the physical cooldown
        -- runs, which is why we answer the 5-minute warning rather than the last
        -- one: exitGameWithRetry needs room to re-send.
        it("keeps retrying until the game confirms", function()
            helper.simulateLine(WARNING)
            local before = #helper.sendCalls
            helper.fireTimers(2000)
            assert.is_true(#helper.sendCalls > before)
            helper.simulateLine("Exiting Tele-Arena...")
            local after = #helper.sendCalls
            helper.fireTimers(2000)
            helper.fireTimers(2000)
            assert.are.equal(after, #helper.sendCalls)
        end)

    end)

    describe("death detection", function()

        local KILLED = "As the final blow strikes your body you fall unconscious."

        it("records the death", function()
            helper.simulateLine(KILLED)
            assert.is_true(taPackage.died)
            assert.is_not_nil(taPackage.diedAt)
        end)

        -- The problem it exists to solve: a death is nearly invisible to a
        -- running script, which carries on issuing commands into a world that
        -- has moved on.
        it("stops every long-running script", function()
            taPackage.arenaState = "fighting"
            taPackage.killActive = true
            taPackage.healLoopActive = true
            helper.simulateLine(KILLED)
            assert.is_nil(taPackage.arenaState)
            assert.is_falsy(taPackage.killActive)
            assert.is_false(taPackage.healLoopActive)
        end)

        it("says so in the session log and pushes a notification", function()
            helper.simulateLine(KILLED)
            local said = false
            for _, text in ipairs(helper.echoCalls) do
                if text and text:find("KILLED", 1, true) then said = true end
            end
            assert.is_true(said)
            assert.is_true(#helper.httpRequestCalls > 0)
        end)

        -- Cleared in one place, so the episode ends for every reader at once.
        it("clears on the next entry into the game", function()
            helper.simulateLine(KILLED)
            helper.simulateLine("Entering Tele-Arena...")
            assert.is_nil(taPackage.died)
            assert.is_nil(taPackage.diedAt)
        end)

        it("is not set by an ordinary revive", function()
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_falsy(taPackage.died)
        end)

        -- The revive line cannot carry this on its own: a suicide prints it too,
        -- and the gold-farming loop hangs its restart off it.
        it("stops the farming loop restarting after a death", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(KILLED)
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_falsy(taPackage.creating)
            assert.is_nil(taPackage.createRestarting)
        end)

        it("still restarts the farming loop after our own suicide", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("After intense mental preparation, you take your own life!")
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_true(taPackage.creating)
            assert.is_true(taPackage.createRestarting)
        end)

        -- The soulstone case, which is what made the guard fire on the wrong
        -- awakenings. A death survived with a soulstone revives at the temple
        -- and never re-enters the game, so nothing ever clears the flag: read as
        -- a bare boolean it still said "died" hours later, and the suicide that
        -- ends the next farming round was refused as a death.
        it("does not read a stale death as this awakening", function()
            helper.simulateLine(KILLED)
            -- The death stopped every script; the run is picked back up by hand.
            helper.simulateAlias("start-gold-farming")
            helper.advanceMs(60 * 60 * 1000)
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_true(taPackage.creating)
            assert.is_true(taPackage.createRestarting)
            -- ...and the flag itself is still there for everyone else.
            assert.is_true(taPackage.died)
        end)

        -- The line the death's own revive arrives on is a second behind it, so
        -- the window has to be generous enough to cover a slow BBS.
        it("still catches the death's own revive a few seconds later", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(KILLED)
            helper.advanceMs(3000)
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_falsy(taPackage.creating)
            assert.is_nil(taPackage.createRestarting)
        end)

        -- Outside a farming run there is no gear staged at any gate and no loop
        -- to refuse to restart, and main.lua has already said the character
        -- died -- so the create script has nothing to add.
        it("says nothing about staging gear when not farming", function()
            helper.simulateLine(KILLED)
            local before = #helper.echoCalls
            helper.simulateLine("You awaken after an unknown amount of time...")
            for i = before + 1, #helper.echoCalls do
                local text = helper.echoCalls[i]
                assert.is_nil(text and text:find("[create]", 1, true))
            end
        end)

        -- Read, not consumed: a second reader must still see it.
        it("stays readable for other scripts until re-entry", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(KILLED)
            helper.simulateLine("You awaken after an unknown amount of time...")
            assert.is_true(taPackage.died)
        end)

    end)

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

        it("records the crossing as a bidirectional 'passage' move", function()
            -- The ferry is a real map edge, so buying passage must set up a
            -- "passage" move from the docks we're leaving. The arrival brief then
            -- links the two docks; the reverse of a passage is a passage.
            taPackage.currentRoomId = 7
            taPackage.currentRoom = "docks"
            helper.simulateLine("You buy passage across the great lake and board a ship...")
            assert.are.equal("passage", taPackage.pendingDirection)
            assert.are.equal(7, taPackage.prevRoomId)
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

        it("captures a promoted class whose name has a space", function()
            helper.simulateLine("Class:        Beast Master")
            assert.are.equal("Beast Master", getClass())
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

        -- A farming character is levelled and thrown away by design, so its
        -- levels are not worth a push. The handover to the banker still is.
        it("stays silent during a gold-farming run", function()
            taPackage.character.class = "Warrior"
            taPackage.character.name = "Garbageman"
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Experience:   792683")  -- seeds earned level 12
            helper.simulateLine("Experience:   815600")  -- crosses to level 13
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        -- The bank runs whether or not the push does, so a crossing that
        -- happened while farming is not announced late once farming stops.
        it("does not announce a crossing that happened while farming", function()
            taPackage.character.class = "Warrior"
            taPackage.character.name = "Garbageman"
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Experience:   792683")
            helper.simulateLine("Experience:   815600")
            helper.simulateAlias("stop-gold-farming")
            helper.simulateLine("Experience:   815600")
            assert.are.equal(0, #helper.httpRequestCalls)
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
    -- Encumberance trigger
    -- =========================================================================

    describe("Encumberance trigger", function()

        it("captures current and max encumberance", function()
            helper.simulateLine("Encumberance: 1000 / 1000")
            local current, max = getEncumberance()
            assert.are.equal(1000, current)
            assert.are.equal(1000, max)
        end)

        it("captures when current is below max", function()
            helper.simulateLine("Encumberance: 250 / 1000")
            local current, max = getEncumberance()
            assert.are.equal(250, current)
            assert.are.equal(1000, max)
        end)

        it("computes the percentage of max", function()
            helper.simulateLine("Encumberance: 750 / 1000")
            assert.are.equal(75, getEncumberancePercent())
        end)

        it("reports 100% when fully encumbered", function()
            helper.simulateLine("Encumberance: 1000 / 1000")
            assert.are.equal(100, getEncumberancePercent())
        end)

        it("percentage is nil when encumberance is unknown", function()
            assert.is_nil(getEncumberancePercent())
        end)

        it("does not fire on unrelated lines", function()
            helper.simulateLine("Vitality:     26 / 26")
            local current, max = getEncumberance()
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
            assert.are.equal("?", segments[6].text)   -- XP remaining
            assert.are.equal("?", segments[8].text)   -- Status
            assert.are.equal("?", segments[10].text)  -- Gold
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

        it("shows only the XP remaining to next level as a label and parenthetical", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   710")
            local segments = capturedFn()
            -- No MP: name[1], HP:[2..4]. XP tail is always label[5] + remaining[6].
            assert.are.equal("XP:",   segments[5].text)
            assert.are.equal("(415)", segments[6].text)  -- 1,125 - 710
            assert.are.equal("cyan",  segments[6].fg)
        end)

        it("formats XP-remaining with commas", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   30000")
            -- next threshold for Warrior above 30,000 is 36,000; 6,000 remains
            assert.are.equal("(6,000)", capturedFn()[6].text)
        end)

        it("shows XP remaining regardless of how far it is to the next level", function()
            helper.simulateLine("Class:        Acolyte")
            helper.simulateLine("Experience:   1622269")
            local segments = capturedFn()
            assert.are.equal("XP:", segments[5].text)
            assert.are.equal("(120,531)", segments[6].text)  -- 1,742,800 - 1,622,269
            assert.are.equal("cyan", segments[6].fg)
        end)

        it("shows '(max)' for XP at max level", function()
            helper.simulateLine("Class:        Warrior")
            helper.simulateLine("Experience:   11594700")
            local segments = capturedFn()
            assert.are.equal("XP:",   segments[5].text)
            assert.are.equal("(max)", segments[6].text)
        end)

        it("marks earned-but-untrained levels with a red glued caret", function()
            -- Kerhak: level 11 Hunter with 630,707 XP. A Hunter needs 588,700
            -- for level 12, so the level is earned but not yet trained.
            helper.simulateLine("Class:        Hunter")
            helper.simulateLine("Level:        11")
            helper.simulateLine("Experience:   630707")
            local segments = capturedFn()
            assert.are.equal("(184,893)", segments[6].text)  -- 815,600 - 630,707
            assert.are.equal("^",    segments[7].text)
            assert.are.equal("red",  segments[7].fg)
            assert.is_true(segments[7].glue)
        end)

        it("shows no caret once the earned level has been trained", function()
            helper.simulateLine("Class:        Hunter")
            helper.simulateLine("Level:        12")
            helper.simulateLine("Experience:   630707")
            local segments = capturedFn()
            assert.are.equal("(184,893)", segments[6].text)
            assert.are.equal("Status:", segments[7].text)
        end)

        it("shows no caret when short of the next threshold", function()
            helper.simulateLine("Class:        Hunter")
            helper.simulateLine("Level:        11")
            helper.simulateLine("Experience:   588699")  -- one short of level 12
            local segments = capturedFn()
            assert.are.equal("Status:", segments[7].text)
        end)

        it("shows no caret when the level is unknown", function()
            helper.simulateLine("Class:        Hunter")
            helper.simulateLine("Experience:   630707")
            local segments = capturedFn()
            assert.are.equal("Status:", segments[7].text)
        end)

        describe("XP-change marker", function()

            -- Acolyte, mid-level: 1,622,269 XP leaves 120,531 to level 20
            -- (1,742,800). Gaining 14,000 leaves 106,531 — no threshold crossed,
            -- so the marker reads as a straight countdown.
            local function gain14k()
                helper.simulateLine("Class:        Acolyte")
                helper.simulateLine("Experience:   1622269")
                helper.simulateLine("Experience:   1636269")
            end

            it("shows nothing on the first XP reading of a session", function()
                helper.simulateLine("Class:        Acolyte")
                helper.simulateLine("Experience:   1622269")
                local segments = capturedFn()
                assert.are.equal("(120,531)", segments[6].text)
                assert.are.equal("Status:",   segments[7].text)
            end)

            it("shows how far the XP figure just moved, in bold orange", function()
                gain14k()
                local segments = capturedFn()
                assert.are.equal("(106,531)", segments[6].text)
                assert.are.equal("-14,000",   segments[7].text)
                assert.are.equal("#ff8700",   segments[7].fg)
                assert.is_true(segments[7].bold)
                assert.is_nil(segments[7].glue)  -- its own field, not a mark on the XP
                assert.are.equal("Status:",   segments[8].text)
            end)

            it("hides the marker once three seconds have passed", function()
                gain14k()
                helper.advanceMs(3000)
                assert.are.equal("Status:", capturedFn()[7].text)
            end)

            it("still shows the marker just under three seconds", function()
                gain14k()
                helper.advanceMs(2999)
                assert.are.equal("-14,000", capturedFn()[7].text)
            end)

            it("re-renders the bar itself so the marker hides without server traffic", function()
                -- baud only re-evaluates the status function when data arrives;
                -- a quiet three seconds would leave the marker stuck on screen.
                gain14k()
                local refresh
                for _, timer in ipairs(helper.timers) do
                    if timer.interval == 3100 then refresh = timer end
                end
                assert.is_not_nil(refresh)
                helper.advanceMs(3100)
                local reRendered
                _G.setStatus = function(fn) reRendered = fn end
                refresh.callback()
                assert.is_not_nil(reRendered)
                assert.are.equal("Status:", reRendered()[7].text)
            end)

            it("shows nothing when a status poll repeats the same XP", function()
                helper.simulateLine("Class:        Acolyte")
                helper.simulateLine("Experience:   1622269")
                helper.simulateLine("Experience:   1622269")
                assert.are.equal("Status:", capturedFn()[7].text)
            end)

            it("counts up when training past a threshold resets the countdown", function()
                -- Warrior at 30,000 needs 6,000 more for level 6 (36,000);
                -- at 44,000 the target becomes level 7 (66,300), 22,300 away.
                helper.simulateLine("Class:        Warrior")
                helper.simulateLine("Experience:   30000")
                helper.simulateLine("Experience:   44000")
                local segments = capturedFn()
                assert.are.equal("(22,300)", segments[6].text)
                assert.are.equal("+16,300", segments[7].text)
            end)

            it("shows nothing at max level, where there is no figure to move", function()
                helper.simulateLine("Class:        Warrior")
                helper.simulateLine("Experience:   11594700")
                helper.simulateLine("Experience:   11594800")
                local segments = capturedFn()
                assert.are.equal("(max)",   segments[6].text)
                assert.are.equal("Status:", segments[7].text)
            end)

            it("sits after the untrained-level caret", function()
                helper.simulateLine("Class:        Hunter")
                helper.simulateLine("Level:        11")
                helper.simulateLine("Experience:   630000")
                helper.simulateLine("Experience:   630707")
                local segments = capturedFn()
                assert.are.equal("(184,893)", segments[6].text)
                assert.are.equal("^",         segments[7].text)
                assert.are.equal("-707",      segments[8].text)
                assert.are.equal("Status:",   segments[9].text)
            end)
        end)

        it("shifts Status/Gold in after the XP tail", function()
            helper.simulateLine("Class:        Acolyte")
            helper.simulateLine("Experience:   1622269")
            helper.simulateLine("Status:       Healthy")
            helper.simulateLine("You are carrying 557 gold crowns.")
            local segments = capturedFn()
            assert.are.equal("Status:",  segments[7].text)
            assert.are.equal("Healthy",  segments[8].text)
            assert.are.equal("Gold:",    segments[9].text)
            assert.are.equal("557",      segments[10].text)
        end)

        it("shows captured Status value", function()
            helper.simulateLine("Status:       Healthy")
            local segments = capturedFn()
            assert.are.equal("Healthy", segments[8].text)   -- no MP, Status at [8]
        end)

        it("colors status red when Thirsty", function()
            helper.simulateLine("Status:       Thirsty")
            assert.are.equal("red", capturedFn()[8].fg)
        end)

        it("colors status red when Hungry", function()
            helper.simulateLine("Status:       Hungry")
            assert.are.equal("red", capturedFn()[8].fg)
        end)

        it("colors status white when Healthy", function()
            helper.simulateLine("Status:       Healthy")
            assert.are.equal("white", capturedFn()[8].fg)
        end)

        it("colors gold amount yellow", function()
            helper.simulateLine("You are carrying 755 gold crowns.")
            assert.are.equal("yellow", capturedFn()[10].fg)
        end)

        it("formats large gold amounts with commas", function()
            helper.simulateLine("You are carrying 1234567 gold crowns.")
            assert.are.equal("1,234,567", capturedFn()[10].text)
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
            assert.are.equal("(771)",   segments[6].text)   -- no MP, XP remaining at [6] (1,125 - 354)
            assert.are.equal("Healthy", segments[8].text)   -- Status at [8]
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

    describe("Acolyte", function()

        it("does not self-heal on physical exhaustion (leaves for the temple instead)", function()
            setClass("Acolyte")
            taPackage.character.name = "Pelayo"
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            helper.sendCalls = {}
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.is_nil(cmd:match("^cast motu"))
            end
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

    describe("setExitLock", function()

        it("ensures a stub then sets the lock columns", function()
            TaDb.setExitLock(5, "n", "bronze", "bronze")
            assert.is_not_nil(helper.findDbCall("execute", "INSERT OR IGNORE INTO room_exits"))
            local upd = helper.findDbCall("execute", "UPDATE room_exits SET lock_key")
            assert.is_not_nil(upd)
            assert.are.same({ "bronze", "bronze", 5, "n" }, upd.params)
        end)

        it("records a door whose key is unknown", function()
            TaDb.setExitLock(5, "e", nil, "iron")
            local upd = helper.findDbCall("execute", "UPDATE room_exits SET lock_key")
            assert.is_nil(upd.params[1])          -- key unknown
            assert.are.equal("iron", upd.params[2])
            assert.are.equal(5, upd.params[3])
            assert.are.equal("e", upd.params[4])
        end)

        it("never clobbers a known key back to NULL (COALESCE)", function()
            -- A turn-away ("locked stone door prevents your exit") passes key=nil
            -- but must not erase a key we learned earlier by walking through.
            TaDb.setExitLock(5, "e", nil, "iron")
            local upd = helper.findDbCall("execute", "UPDATE room_exits SET lock_key")
            assert.is_not_nil(string.find(upd.sql, "COALESCE(?, lock_key)", 1, true))
        end)

    end)

    describe("room notes", function()

        it("addRoomNote inserts the note and returns the new id", function()
            helper.mockDbOneRow = { id = 7 }   -- last_insert_rowid()
            local id = TaDb.addRoomNote(12, "say komi here to open the south door")
            assert.are.equal(7, id)
            local ins = helper.findDbCall("execute", "INSERT INTO room_notes")
            assert.is_not_nil(ins)
            assert.are.equal(12, ins.params[1])
            assert.are.equal("say komi here to open the south door", ins.params[2])
        end)

        it("roomNotes returns the room's notes oldest-first", function()
            helper.mockDbRows = { { id = 1, note = "first" }, { id = 2, note = "second" } }
            local notes = TaDb.roomNotes(12)
            assert.are.equal(2, #notes)
            assert.are.equal("first", notes[1].note)
            local q = helper.findDbCall("query", "FROM room_notes WHERE room_id")
            assert.are.same({ 12 }, q.params)
        end)

        it("roomNotes returns an empty table when a room has none", function()
            helper.mockDbRows = nil
            assert.are.same({}, TaDb.roomNotes(99))
        end)

        it("deleteRoomNote removes one note by id and returns the count", function()
            helper.mockExecuteReturn = 1
            local removed = TaDb.deleteRoomNote(7)
            assert.are.equal(1, removed)
            local del = helper.findDbCall("execute", "DELETE FROM room_notes WHERE id")
            assert.are.same({ 7 }, del.params)
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

    describe("listAreas", function()

        it("returns the area rows", function()
            helper.mockDbRows = { { slug = "first-town", name = "first-town" },
                                  { slug = "first-dungeon", name = "first-dungeon" } }
            local areas = TaDb.listAreas()
            assert.are.equal(2, #areas)
            assert.are.equal("first-town", areas[1].slug)
            assert.are.equal("first-dungeon", areas[2].slug)
        end)

    end)

    describe("areaIdBySlug", function()

        it("returns the area id for a known slug", function()
            helper.mockDbOneRow = { id = 2 }
            assert.are.equal(2, TaDb.areaIdBySlug("first-dungeon"))
        end)

        it("returns nil for an unknown slug", function()
            helper.mockDbOneRow = nil
            assert.is_nil(TaDb.areaIdBySlug("nope"))
        end)

    end)

    describe("resetArea", function()

        it("nulls inbound edges, deletes the area's exits and rooms, returns the count", function()
            helper.mockExecuteReturn = 33
            local removed = TaDb.resetArea(2)
            assert.are.equal(33, removed)
            local nullEdges = helper.findDbCall("execute", "UPDATE room_exits SET to_id = NULL WHERE to_id IN")
            assert.is_not_nil(nullEdges)
            assert.are.same({ 2 }, nullEdges.params)
            local delExits = helper.findDbCall("execute", "DELETE FROM room_exits WHERE from_id IN")
            assert.are.same({ 2 }, delExits.params)
            local delRooms = helper.findDbCall("execute", "DELETE FROM rooms WHERE area_id")
            assert.are.same({ 2 }, delRooms.params)
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

        it("skips a name+exit-set match whose coordinate disagrees", function()
            stubRooms("cave", { 1, 5 }, { [1] = { "n", "s" } })
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 5, y = 5, z = 0 }  -- candidate #1 sits elsewhere
                end
                return nil
            end
            assert.is_nil(TaDb.findRoomByFingerprint("cave", { "n", "s" }, 5, { x = 9, y = 9, z = 0 }))
        end)

        it("keeps a name+exit-set match whose coordinate agrees", function()
            stubRooms("cave", { 1, 5 }, { [1] = { "n", "s" } })
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 5, y = 5, z = 0 }
                end
                return nil
            end
            assert.are.equal(1, TaDb.findRoomByFingerprint("cave", { "n", "s" }, 5, { x = 5, y = 5, z = 0 }))
        end)

        it("keeps a match whose coordinate is unknown (guard is inert)", function()
            stubRooms("cave", { 1, 5 }, { [1] = { "n", "s" } })
            helper.mockDbOneRow = nil  -- candidate #1 has no stored coordinate
            assert.are.equal(1, TaDb.findRoomByFingerprint("cave", { "n", "s" }, 5, { x = 9, y = 9, z = 0 }))
        end)

    end)

    describe("findLoopClosure", function()

        -- Stub roomIdsByName + roomExitDirections (like stubRooms above) and, via
        -- mockDbOneRow, exitDestination for each room's `back` exit. `dests` maps
        -- a room id to the to_id of its return exit (a number = already walked;
        -- nil/absent = an unexplored return door).
        local function stub(name, ids, exits, dests)
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE name", 1, true) then
                    local rows = {}
                    for _, id in ipairs(ids) do rows[#rows + 1] = { id = id } end
                    return rows
                elseif string.find(sql, "SELECT direction FROM room_exits WHERE from_id", 1, true) then
                    local rows = {}
                    for _, dir in ipairs(exits[params[1]] or {}) do
                        rows[#rows + 1] = { direction = dir }
                    end
                    return rows
                end
                return {}
            end
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = (dests or {})[params[1]] }
                end
                return nil
            end
        end

        it("closes onto the room whose return door is unexplored", function()
            -- We walked sw; the return door is ne. Room 1 (real ts-5) has ne,nw,sw
            -- with an unexplored ne -> that's the loop closure.
            stub("town sewers", { 1, 9 }, { [1] = { "ne", "nw", "sw" } }, { [1] = nil })
            assert.are.equal(1, TaDb.findLoopClosure("town sewers", { "ne", "nw", "sw" }, 9, "ne"))
        end)

        it("rejects a look-alike whose return door is already walked", function()
            -- Same name + exit-set, but its ne already leads to room 7: it commits
            -- to a different neighbour, so it isn't the room we just entered.
            stub("town sewers", { 1, 9 }, { [1] = { "ne", "nw", "sw" } }, { [1] = 7 })
            assert.is_nil(TaDb.findLoopClosure("town sewers", { "ne", "nw", "sw" }, 9, "ne"))
        end)

        it("does not match when the exit-set differs", function()
            stub("town sewers", { 1, 9 }, { [1] = { "ne", "sw" } }, { [1] = nil })
            assert.is_nil(TaDb.findLoopClosure("town sewers", { "ne", "nw", "sw" }, 9, "ne"))
        end)

        it("returns nil when two candidates both qualify (ambiguous)", function()
            stub("town sewers", { 1, 2, 9 },
                { [1] = { "ne", "nw", "sw" }, [2] = { "ne", "nw", "sw" } },
                { [1] = nil, [2] = nil })
            assert.is_nil(TaDb.findLoopClosure("town sewers", { "ne", "nw", "sw" }, 9, "ne"))
        end)

        it("returns nil without a back direction", function()
            stub("town sewers", { 1, 9 }, { [1] = { "ne", "nw", "sw" } }, { [1] = nil })
            assert.is_nil(TaDb.findLoopClosure("town sewers", { "ne", "nw", "sw" }, 9, nil))
        end)

    end)

    describe("coordinates", function()

        it("roomCoord returns the stored coordinate", function()
            helper.mockDbOneRow = { x = 3, y = -2, z = 1 }
            assert.are.same({ x = 3, y = -2, z = 1 }, TaDb.roomCoord(7))
        end)

        it("roomCoord returns nil when the room has no coordinate", function()
            helper.mockDbOneRow = { x = nil, y = nil, z = nil }
            assert.is_nil(TaDb.roomCoord(7))
            helper.mockDbOneRow = nil
            assert.is_nil(TaDb.roomCoord(7))
        end)

        it("setRoomCoord writes x/y/z for the room", function()
            TaDb.setRoomCoord(7, 3, -2, 1)
            local call = helper.findDbCall("execute", "UPDATE rooms SET x = ?, y = ?, z = ?")
            assert.is_not_nil(call)
            assert.are.same({ 3, -2, 1, 7 }, call.params)
        end)

        it("findRoomAtCoord returns the unique room at the coordinate", function()
            helper.mockDbRows = { { id = 12 } }
            assert.are.equal(12, TaDb.findRoomAtCoord(2, "cave", 4, 4, 0, 9))
        end)

        it("findRoomAtCoord returns nil when nothing matches", function()
            helper.mockDbRows = {}
            assert.is_nil(TaDb.findRoomAtCoord(2, "cave", 4, 4, 0, 9))
        end)

        it("findRoomAtCoord returns nil when more than one room matches", function()
            helper.mockDbRows = { { id = 12 }, { id = 13 } }
            assert.is_nil(TaDb.findRoomAtCoord(2, "cave", 4, 4, 0, 9))
        end)

    end)

    describe("roomBySlug", function()

        it("returns the room row for a slug", function()
            helper.mockDbOneRow = { id = 91, name = "cave", area_id = 2, x = -4, y = -11, z = -1 }
            local room = TaDb.roomBySlug("cave-11")
            assert.are.equal(91, room.id)
            assert.are.equal("cave", room.name)
            assert.are.equal(-4, room.x)
        end)

        it("returns nil for an unknown slug", function()
            helper.mockDbOneRow = nil
            assert.is_nil(TaDb.roomBySlug("nope"))
        end)

    end)

    describe("setRoomTrap", function()

        it("writes the trap type for the room", function()
            TaDb.setRoomTrap(7, "spiked trap")
            local call = helper.findDbCall("execute", "UPDATE rooms SET trap = ?")
            assert.is_not_nil(call)
            assert.are.same({ "spiked trap", 7 }, call.params)
        end)

    end)

    describe("setPlayerLocation", function()

        it("upserts the character's current room", function()
            TaDb.setPlayerLocation("Pelayo", 110)
            local call = helper.findDbCall("execute", "INSERT INTO player_location")
            assert.is_not_nil(call)
            assert.are.equal("Pelayo", call.params[1])
            assert.are.equal(110, call.params[2])
        end)

    end)

    describe("roomsMatchingFingerprint", function()

        local function stub(ids_slugs, exitmap)
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "rooms WHERE name", 1, true) then
                    local rows = {}
                    for _, it in ipairs(ids_slugs) do
                        rows[#rows + 1] = { id = it[1], slug = it[2] }
                    end
                    return rows
                elseif string.find(sql, "room_exits WHERE from_id", 1, true) then
                    local rows = {}
                    for _, dir in ipairs(exitmap[params[1]] or {}) do
                        rows[#rows + 1] = { direction = dir }
                    end
                    return rows
                end
                return {}
            end
        end

        it("returns every room whose name and exit-set match", function()
            stub({ { 4, "cave-3" }, { 9, "cave-8" }, { 12, "cave-11" } },
                 { [4] = { "e", "w" }, [9] = { "e", "w" }, [12] = { "n", "s" } })
            local m = TaDb.roomsMatchingFingerprint("cave", { "e", "w" })
            assert.are.equal(2, #m)
            local slugs = {}
            for _, x in ipairs(m) do slugs[x.slug] = true end
            assert.is_true(slugs["cave-3"])
            assert.is_true(slugs["cave-8"])
            assert.is_nil(slugs["cave-11"])  -- different exit-set
        end)

        it("returns empty when nothing matches", function()
            stub({ { 4, "cave-3" } }, { [4] = { "n" } })
            assert.are.equal(0, #TaDb.roomsMatchingFingerprint("cave", { "e", "w" }))
        end)

    end)

    describe("roomsInAreaMatching", function()

        -- Stub an area lookup plus the rooms filed under it. `area` is the slug
        -- the caller is allowed to resolve; anything else looks like an unknown
        -- area (queryOne returns nil).
        local function stub(area, rooms)
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "FROM areas WHERE slug", 1, true) then
                    return params[1] == area and { id = 7 } or nil
                end
                return nil
            end
            helper.mockDbRows = function(sql)
                if string.find(sql, "FROM rooms WHERE area_id", 1, true) then
                    return rooms
                end
                return {}
            end
        end

        it("matches a room by its exact slug", function()
            stub("sewers", {
                { id = 358, slug = "town-sewers-17", name = "town sewers" },
                { id = 359, slug = "town-sewers-18", name = "town sewers" },
            })
            local m = TaDb.roomsInAreaMatching("sewers", "town-sewers-18")
            assert.are.equal(1, #m)
            assert.are.equal(359, m[1].id)
        end)

        it("matches a room by its slugified display name", function()
            stub("third-town", { { id = 1011, slug = "town-square", name = "town square" } })
            local m = TaDb.roomsInAreaMatching("third-town", "town-square")
            assert.are.equal(1, #m)
            assert.are.equal(1011, m[1].id)
        end)

        -- The suffix an area's duplicate rooms get is unguessable, so the name
        -- form has to reach a room whose slug does NOT equal it: "arena" must
        -- find third-town's "arena-2".
        it("finds a suffixed room by its unsuffixed name", function()
            stub("third-town", { { id = 1014, slug = "arena-2", name = "arena" } })
            local m = TaDb.roomsInAreaMatching("third-town", "arena")
            assert.are.equal(1, #m)
            assert.are.equal(1014, m[1].id)
        end)

        it("returns every candidate when the name form is ambiguous", function()
            stub("third-town", {
                { id = 1012, slug = "plaza-a", name = "underground plaza" },
                { id = 1015, slug = "plaza-b", name = "underground plaza" },
                { id = 1019, slug = "plaza-c", name = "underground plaza" },
            })
            -- Three rooms share the name and none is called that, so the caller
            -- must reject rather than guess.
            assert.are.equal(3, #TaDb.roomsInAreaMatching("third-town", "underground-plaza"))
            -- ...and the exact slug still narrows it to one.
            local one = TaDb.roomsInAreaMatching("third-town", "plaza-c")
            assert.are.equal(1, #one)
            assert.are.equal(1019, one[1].id)
        end)

        -- The first room to claim a name keeps the bare slug and every later
        -- namesake is suffixed, so the one room genuinely called
        -- `underground-plaza` also answers to the name all three share. Match
        -- both together and it becomes the one room that cannot be named.
        it("lets an exact slug outrank the name it shares", function()
            stub("third-town", {
                { id = 1012, slug = "underground-plaza",   name = "underground plaza" },
                { id = 1015, slug = "underground-plaza-1", name = "underground plaza" },
                { id = 1019, slug = "underground-plaza-2", name = "underground plaza" },
            })
            local m = TaDb.roomsInAreaMatching("third-town", "underground-plaza")
            assert.are.equal(1, #m)
            assert.are.equal(1012, m[1].id)
        end)

        it("returns an empty list when the area has no such room", function()
            stub("sewers", { { id = 340, slug = "town-sewers", name = "town sewers" } })
            assert.are.equal(0, #TaDb.roomsInAreaMatching("sewers", "no-such-room"))
        end)

        -- nil (unknown area) is deliberately distinct from an empty list (known
        -- area, no such room) so navigate-to can report the two differently.
        it("returns nil when the area itself is unknown", function()
            stub("sewers", {})
            assert.is_nil(TaDb.roomsInAreaMatching("nowhere", "town-sewers-18"))
        end)

    end)

    describe("roomRef", function()

        it("joins the area and room slugs", function()
            helper.mockDbOneRow = { slug = "town-sewers-18", area = "sewers" }
            assert.are.equal("sewers/town-sewers-18", TaDb.roomRef(359))
        end)

        it("falls back to the bare slug for a room with no area", function()
            helper.mockDbOneRow = { slug = "orphan-room", area = nil }
            assert.are.equal("orphan-room", TaDb.roomRef(99))
        end)

        it("returns nil for an unknown room", function()
            helper.mockDbOneRow = nil
            assert.is_nil(TaDb.roomRef(12345))
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

        it("fills the target's unexplored stub with the provisional's destination", function()
            -- Loop closure: provisional #5 knows 5 --ne--> 4, but the target #1's
            -- own ne is still an open frontier. The IGNORE keeps the stub, so a
            -- follow-up UPDATE must upgrade #1's NULL ne to 4.
            helper.mockDbRows = function(sql)
                if string.find(sql, "SELECT direction, to_id FROM room_exits WHERE from_id", 1, true) then
                    return { { direction = "ne", to_id = 4 } }
                end
                return {}
            end
            TaDb.mergeRoomInto(5, 1)
            local fill = helper.findDbCall("execute", "SET to_id = ? WHERE from_id = ? AND direction = ? AND to_id IS NULL")
            assert.is_not_nil(fill)
            assert.are.same({ 4, 1, "ne" }, fill.params)  -- #1's ne frontier filled with 4
        end)

        it("does not fill a stub when the provisional's edge is itself unexplored", function()
            -- Provisional's own edge has no destination (NULL), so there's nothing
            -- to promote a frontier to -- guard on a real numeric destination.
            helper.mockDbRows = function(sql)
                if string.find(sql, "SELECT direction, to_id FROM room_exits WHERE from_id", 1, true) then
                    return { { direction = "ne", to_id = nil } }
                end
                return {}
            end
            TaDb.mergeRoomInto(5, 1)
            assert.is_nil(helper.findDbCall("execute", "SET to_id = ? WHERE from_id = ? AND direction = ? AND to_id IS NULL"))
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

    describe("recordItemDrop", function()

        it("records monster, item, and the room it was found in", function()
            TaDb.recordItemDrop("anaconda", "a ruby key", 54)
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_not_nil(call)
            assert.are.equal("anaconda", call.params[1])
            assert.are.equal("a ruby key", call.params[2])
            assert.are.equal(54, call.params[4])   -- room_id
        end)

        it("stores a nil room as NULL", function()
            TaDb.recordItemDrop("anaconda", "a ruby key", nil)
            local call = helper.findDbCall("execute", "INSERT INTO item_drops")
            assert.is_nil(call.params[4])
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

        it("echoes any notes on the room it enters", function()
            stubDiscover(1)
            -- Return note rows only for the room_notes query; {} for everything else
            -- (fingerprint/exit lookups) so the entry path isn't disturbed.
            helper.mockDbRows = function(sql)
                if string.find(sql, "FROM room_notes", 1, true) then
                    return { { id = 1, note = "pull lever or a trap fires ahead" } }
                end
                return {}
            end
            helper.simulateLine("You're in the north plaza.")
            assert.is_true(tableContains(helper.echoCalls, "[note] pull lever or a trap fires ahead"))
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

        -- The fifth preposition, and the last to be noticed: one known room
        -- uses it, between the first town's south plaza and the mountains.
        -- Missing it cost the mapper that room entirely and stalled a
        -- navigate-to walk mid-route.
        it("recognizes an 'outside' move brief", function()
            stubDiscover(1)
            helper.simulateLine("You're outside the town gates.")
            assert.are.equal("town gates", taPackage.currentRoom)
            helper.simulateLine("You are outside the town gates.")
            assert.are.equal("town gates", taPackage.currentRoom)
        end)

        it("ignores a 'You are ...' line while accumulating a look description", function()
            taPackage.currentRoom = "large cavern"
            taPackage.currentRoomId = 5
            taPackage.monsterDb.state = "accumulating_room"  -- mid-look
            helper.simulateLine("You are in a large cavern.")  -- the look's first line
            assert.are.equal("large cavern", taPackage.currentRoom)  -- unchanged
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
        end)

        it("treats the broken 'You at ...' brief as an arrival", function()
            stubDiscover(1)
            helper.simulateLine("You at the bottom of a stairwell.")
            assert.are.equal("bottom of a stairwell", taPackage.currentRoom)
        end)

        it("does not mint a phantom room from a 'look <dir>' peek", function()
            taPackage.currentRoom = "cave"
            taPackage.currentRoomId = 5
            stubDiscover(99)
            helper.simulateLine("look e")                       -- peek east
            assert.is_true(taPackage.suppressRoomEntry)
            helper.simulateLine("You're in an enormous natural cavern.")  -- the neighbor
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))  -- no phantom
            assert.are.equal("cave", taPackage.currentRoom)      -- still where we were
            assert.is_falsy(taPackage.suppressRoomEntry)         -- flag consumed
        end)

        it("a real move clears a stale look-suppress flag", function()
            taPackage.suppressRoomEntry = true                   -- e.g. a look that hit a wall
            helper.simulateAlias("n")
            assert.is_nil(taPackage.suppressRoomEntry)
        end)

        it("stamps the origin coordinate on a cold-start room", function()
            stubDiscover(1)  -- no pendingDirection: nothing to dead-reckon from
            helper.simulateLine("You're in a cave.")
            local call = helper.findDbCall("execute", "UPDATE rooms SET x = ?, y = ?, z = ?")
            assert.is_not_nil(call)
            assert.are.same({ 0, 0, 0, 1 }, call.params)
            assert.are.same({ x = 0, y = 0, z = 0 }, taPackage.coord)
        end)

        it("dead-reckons the coordinate of a room reached through an unknown exit", function()
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "n"
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE slug", 1, true) then
                    return { id = 1 }                       -- freshly minted room id
                elseif string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    if params[1] == 5 then return { x = 0, y = 0, z = 0 } end  -- prev room
                    return nil                              -- minted room has no coord yet
                end
                return nil                                  -- exitDestination: unknown exit
            end
            helper.mockDbRows = {}                           -- findRoomAtCoord: no match
            helper.simulateLine("You're in a cave.")
            local call = helper.findDbCall("execute", "UPDATE rooms SET x = ?, y = ?, z = ?")
            assert.are.same({ 0, 1, 0, 1 }, call.params)     -- north is +y
            assert.are.same({ x = 0, y = 1, z = 0 }, taPackage.coord)
        end)

        it("mints a provisional on an unknown exit and links it, deferring closure to Exits", function()
            -- We no longer identify the arrival room by coordinate here (that was
            -- exit-blind and glued distinct rooms that dead-reckon to the same
            -- spot). An unknown exit always mints a provisional and links the
            -- edge; the Exits handler folds it into a real room only if the
            -- exit-set matches. So a discovery DOES happen at this step.
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "n"
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM rooms WHERE slug", 1, true) then
                    return { id = 8 }                       -- discoverRoom's new id
                end
                return nil                                  -- exitDestination unknown; no coord stored
            end
            helper.simulateLine("You're in a cave.")
            assert.is_not_nil(helper.findDbCall("execute", "INSERT INTO rooms"))  -- provisional minted
            assert.are.equal(8, taPackage.currentRoomId)
            assert.is_true(taPackage.currentRoomProvisional)
            local edges = {}
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute"
                    and string.find(c.sql, "INSERT OR REPLACE INTO room_exits", 1, true) then
                    edges[#edges + 1] = c.params
                end
            end
            assert.are.same({ 5, "n", 8 }, edges[1])         -- forward edge
            assert.are.same({ 8, "s", 5 }, edges[2])         -- reverse back-edge
        end)

        it("adopts the entered known room's area so rooms minted onward inherit it", function()
            -- Session started in second-town (area 7) via map-here, then walked
            -- across a frontier into a known sewers room (area 8). Creation of
            -- subsequent rooms must follow us into the sewers, not stay in 7.
            taPackage.currentAreaId = 7
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "d"
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 340 }                      -- known edge 5 --d--> 340
                elseif string.find(sql, "SELECT name FROM rooms", 1, true) then
                    return { name = "town sewers" }             -- dest name confirms the edge
                elseif string.find(sql, "SELECT area_id FROM rooms", 1, true) then
                    return { area_id = 8 }                      -- 340 lives in the sewers
                elseif string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 0, y = 0, z = -1 }             -- stored coord for 340
                end
                return nil
            end
            helper.simulateLine("You're in the town sewers.")
            assert.are.equal(340, taPackage.currentRoomId)
            assert.are.equal(8, taPackage.currentAreaId)        -- followed the room into its area
        end)

        it("leaves the current area untouched when the entered room has no area", function()
            taPackage.currentAreaId = 7
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "n"
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 60 }                       -- known edge to a legacy room
                elseif string.find(sql, "SELECT name FROM rooms", 1, true) then
                    return { name = "cave" }
                elseif string.find(sql, "SELECT area_id FROM rooms", 1, true) then
                    return { area_id = nil }                    -- unfiled legacy row
                elseif string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 0, y = 0, z = 0 }
                end
                return nil
            end
            helper.simulateLine("You're in a cave.")
            assert.are.equal(60, taPackage.currentRoomId)
            assert.are.equal(7, taPackage.currentAreaId)        -- unchanged
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

        it("emits no [mapdbg] on a plain ex while not mapping", function()
            taPackage.mapping = false
            taPackage.currentRoomId = 42
            helper.simulateLine("Exits: n,sw.")
            local leaked = false
            for _, m in ipairs(helper.echoCalls) do
                if string.find(m, "[mapdbg] Exits trigger", 1, true) then leaked = true end
            end
            assert.is_false(leaked)
        end)

        it("reports which listed exits are unexplored vs mapped", function()
            taPackage.currentRoomId = 111
            -- ne and nw already lead somewhere; s is a stub (no destination).
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    local dir = params[2]
                    if dir == "ne" then return { to_id = 50 } end
                    if dir == "nw" then return { to_id = 60 } end
                    return { to_id = nil }  -- s unexplored
                end
                return nil
            end
            helper.simulateLine("Exits: ne,s,nw.")
            assert.is_true(tableContains(helper.echoCalls,
                "[map] unexplored exits: s  (mapped: ne, nw)"))
        end)

        it("reports when every listed exit is already mapped", function()
            taPackage.currentRoomId = 111
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 50 }  -- every direction leads somewhere
                end
                return nil
            end
            helper.simulateLine("Exits: n,s.")
            assert.is_true(tableContains(helper.echoCalls, "[map] all exits mapped: n, s"))
        end)

        it("records the character's location after capturing exits", function()
            taPackage.currentRoomId = 110
            taPackage.character.name = "Pelayo"
            helper.simulateLine("Exits: n,s.")
            local loc = helper.findDbCall("execute", "INSERT INTO player_location")
            assert.is_not_nil(loc)
            assert.are.equal("Pelayo", loc.params[1])
            assert.are.equal(110, loc.params[2])
        end)

        it("does not record location without a logged-in character name", function()
            taPackage.currentRoomId = 110
            taPackage.character.name = nil
            helper.simulateLine("Exits: n,s.")
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO player_location"))
        end)

    end)

    describe("map-print-room-slug", function()

        it("probes the current room with a bare return then ex", function()
            helper.simulateAlias("map-print-room-slug")
            assert.is_not_nil(taPackage.slugProbe)
            local sentBare, sentEx = false, false
            for _, c in ipairs(helper.sendCalls) do
                if c == "" then sentBare = true elseif c == "ex" then sentEx = true end
            end
            assert.is_true(sentBare)
            assert.is_true(sentEx)
        end)

        it("captures the room name for the probe without mapping", function()
            taPackage.slugProbe = { name = nil }
            taPackage.mapping = true  -- probe wins even when mapping is on
            helper.simulateLine("You're in a cave.")
            assert.are.equal("cave", taPackage.slugProbe.name)
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))  -- no discovery
        end)

        it("prints the definitive slug when exactly one room matches", function()
            taPackage.slugProbe = { name = "cave" }
            helper.mockDbRows = function(sql)
                if string.find(sql, "rooms WHERE name", 1, true) then
                    return { { id = 4, slug = "cave-3" } }
                elseif string.find(sql, "room_exits WHERE from_id", 1, true) then
                    return { { direction = "e" }, { direction = "w" } }
                end
                return {}
            end
            helper.simulateLine("Exits: e,w.")
            assert.is_nil(taPackage.slugProbe)  -- probe consumed
            local hit = false
            for _, m in ipairs(helper.echoCalls) do
                if string.find(m, "map-here cave-3", 1, true) then hit = true end
            end
            assert.is_true(hit)
        end)

        it("prints all candidates when several rooms match", function()
            taPackage.slugProbe = { name = "cave" }
            helper.mockDbRows = function(sql)
                if string.find(sql, "rooms WHERE name", 1, true) then
                    return { { id = 4, slug = "cave-3" }, { id = 9, slug = "cave-8" } }
                elseif string.find(sql, "room_exits WHERE from_id", 1, true) then
                    return { { direction = "e" }, { direction = "w" } }
                end
                return {}
            end
            helper.simulateLine("Exits: e,w.")
            local hit = false
            for _, m in ipairs(helper.echoCalls) do
                if string.find(m, "cave-3", 1, true) and string.find(m, "cave-8", 1, true) then hit = true end
            end
            assert.is_true(hit)
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

        it("treats a rest-rejected move as rejected (clears pendingDirection)", function()
            taPackage.pendingDirection = "se"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
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

    describe("locked doors", function()

        it("tags the crossed edge and its reverse after passing a locked door", function()
            taPackage.currentRoomId = 5
            taPackage.prevRoomId = 5
            taPackage.pendingDirection = "n"
            stubDiscover(6)
            -- The unlock line arrives just before the destination brief.
            helper.simulateLine("Your bronze key unlocks the bronze door and allows you to pass through.")
            assert.are.same({ key = "bronze", door = "bronze" }, taPackage.pendingLock)
            helper.simulateLine("You're in a cave.")
            local locks = {}
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute"
                    and string.find(c.sql, "UPDATE room_exits SET lock_key", 1, true) then
                    locks[#locks + 1] = c.params
                end
            end
            assert.are.same({ "bronze", "bronze", 5, "n" }, locks[1])  -- crossed edge
            assert.are.same({ "bronze", "bronze", 6, "s" }, locks[2])  -- reverse (door blocks both ways)
            assert.is_nil(taPackage.pendingLock)
        end)

        it("records a blocked door we lack the key for and clears the pending direction", function()
            taPackage.currentRoomId = 5
            taPackage.pendingDirection = "e"
            helper.simulateLine("The locked iron door prevents your exit in that direction.")
            local upd = helper.findDbCall("execute", "UPDATE room_exits SET lock_key")
            assert.is_not_nil(upd)
            assert.is_nil(upd.params[1])           -- key unknown
            assert.are.equal("iron", upd.params[2])
            assert.are.equal(5, upd.params[3])
            assert.are.equal("e", upd.params[4])
            assert.is_nil(taPackage.pendingDirection)
        end)

    end)

    describe("room traps", function()

        it("tags the current room with the trap type sprung there", function()
            taPackage.currentRoomId = 5
            helper.simulateLine("A spiked trap catches your foot and pain shoots up your leg!")
            local call = helper.findDbCall("execute", "UPDATE rooms SET trap = ?")
            assert.is_not_nil(call)
            assert.are.same({ "spiked trap", 5 }, call.params)
        end)

        it("distinguishes crossbow, falling-rock, and trap-door hazards", function()
            taPackage.currentRoomId = 5
            helper.simulateLine("Several crossbow bolts fire from holes in the walls, striking you!")
            assert.are.equal("crossbow trap", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
            helper.clearDbCalls()
            helper.simulateLine("Several large stones fall on you from above!")
            assert.are.equal("falling rocks", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
            helper.clearDbCalls()
            helper.simulateLine("A huge stone block slams down on you from above!")
            assert.are.equal("falling block", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
            helper.clearDbCalls()
            helper.simulateLine("A scything blade slices into your stomach!")
            assert.are.equal("scything blade", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
            helper.clearDbCalls()
            helper.simulateLine("A ball of flame explodes from an opening in the wall and engulfs you!")
            assert.are.equal("flame trap", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
            helper.clearDbCalls()
            helper.simulateLine("You just fell through a trap door in the floor!")
            assert.are.equal("trap door", helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params[1])
        end)

        it("does not tag a room when mapping is off", function()
            taPackage.mapping = false
            taPackage.currentRoomId = 5
            helper.simulateLine("A spiked trap catches your foot and pain shoots up your leg!")
            assert.is_nil(helper.findDbCall("execute", "UPDATE rooms SET trap = ?"))
        end)

        it("primes a downward move on a trap-door fall so the pit maps a floor below", function()
            taPackage.currentRoomId = 146
            taPackage.currentRoom = "cave"
            helper.simulateLine("You just fell through a trap door in the floor!")
            -- tagged the room we fell from
            assert.are.same({ "trap door", 146 }, helper.findDbCall("execute", "UPDATE rooms SET trap = ?").params)
            -- and set up the fall as a downward move so the next brief dead-reckons z-1
            assert.are.equal("d", taPackage.pendingDirection)
            assert.are.equal(146, taPackage.prevRoomId)
        end)

    end)

    describe("map-area alias", function()

        it("sets the area and new rooms inherit it", function()
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

        it("begins mapping here: turns mapping on, resets the anchor, bare-returns", function()
            taPackage.mapping = false
            taPackage.currentRoomId = 99  -- stale anchor from before
            taPackage.prevRoomId = 98
            taPackage.pendingDirection = "n"
            taPackage.coord = { x = 5, y = 5, z = 0 }
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM areas", 1, true) then return { id = 3 } end
                return nil
            end
            helper.simulateAlias("map-area caves")
            assert.is_true(taPackage.mapping)
            assert.is_nil(taPackage.currentRoomId)
            assert.is_nil(taPackage.prevRoomId)
            assert.is_nil(taPackage.pendingDirection)
            assert.is_nil(taPackage.coord)
            local bareSent = false
            for _, c in ipairs(helper.sendCalls) do if c == "" then bareSent = true end end
            assert.is_true(bareSent)
        end)

        it("re-files the room you're standing in into the new area", function()
            -- Crossed a frontier into a fresh area and stopped on the entry room,
            -- which was discovered under the previous area's id. map-area moves it.
            taPackage.currentRoomId = 42
            taPackage.currentAreaId = 7  -- previous (second-town) area
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM areas", 1, true) then return { id = 3 } end
                return nil
            end
            helper.simulateAlias("map-area sewers The Sewers")
            local moved = helper.findDbCall("execute", "UPDATE rooms SET area_id")
            assert.is_not_nil(moved)
            assert.are.equal(3, moved.params[1])   -- new area id
            assert.are.equal(42, moved.params[2])  -- the anchored room
            assert.are.equal(3, taPackage.currentAreaId)
        end)

        it("does not move any room when there's no current anchor", function()
            taPackage.currentRoomId = nil
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM areas", 1, true) then return { id = 3 } end
                return nil
            end
            helper.simulateAlias("map-area caves")
            assert.is_nil(helper.findDbCall("execute", "UPDATE rooms SET area_id"))
        end)

    end)

    describe("map-here alias", function()

        it("anchors currentRoomId, coord, and area from the named room", function()
            taPackage.mapping = false
            helper.mockDbOneRow = { id = 91, name = "cave", area_id = 2, x = -4, y = -11, z = -1 }
            helper.simulateAlias("map-here cave-11")
            assert.is_true(taPackage.mapping)
            assert.are.equal(91, taPackage.currentRoomId)
            assert.are.equal("cave", taPackage.currentRoom)
            assert.are.equal(2, taPackage.currentAreaId)
            assert.are.same({ x = -4, y = -11, z = -1 }, taPackage.coord)
            assert.is_nil(taPackage.prevRoomId)
            assert.is_nil(taPackage.pendingDirection)
            assert.is_false(taPackage.currentRoomProvisional)
        end)

        it("stamps the player's location at the anchor room", function()
            taPackage.character.name = "Pelayo"
            helper.mockDbOneRow = { id = 91, name = "cave", area_id = 2, x = -4, y = -11, z = -1 }
            helper.simulateAlias("map-here cave-11")
            local loc = helper.findDbCall("execute", "INSERT INTO player_location")
            assert.is_not_nil(loc)
            assert.are.equal("Pelayo", loc.params[1])
            assert.are.equal(91, loc.params[2])
        end)

        it("does not reprint or re-resolve (no room INSERT, no visit)", function()
            helper.mockDbOneRow = { id = 91, name = "cave", area_id = 2, x = -4, y = -11, z = -1 }
            helper.simulateAlias("map-here cave-11")
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO rooms"))
            assert.is_nil(helper.findDbCall("execute", "UPDATE rooms SET visits"))
        end)

        it("leaves coord nil when the room has no stored coordinate", function()
            helper.mockDbOneRow = { id = 5, name = "cave", area_id = 2, x = nil, y = nil, z = nil }
            helper.simulateAlias("map-here cave")
            assert.are.equal(5, taPackage.currentRoomId)
            assert.is_nil(taPackage.coord)
        end)

        it("does nothing for an unknown slug", function()
            taPackage.currentRoomId = 7
            helper.mockDbOneRow = nil
            helper.simulateAlias("map-here bogus")
            assert.are.equal(7, taPackage.currentRoomId)  -- unchanged
            assert.is_true(tableContains(helper.echoCalls, "[map] no room with slug: bogus"))
        end)

    end)

    describe("map-list-areas alias", function()

        it("echoes each area slug", function()
            helper.mockDbRows = { { slug = "first-town", name = "first-town" },
                                  { slug = "first-dungeon", name = "first-dungeon" } }
            helper.simulateAlias("map-list-areas")
            assert.is_true(tableContains(helper.echoCalls, "first-town"))
            assert.is_true(tableContains(helper.echoCalls, "first-dungeon"))
        end)

        it("reports when nothing has been mapped", function()
            helper.mockDbRows = {}
            helper.simulateAlias("map-list-areas")
            assert.is_true(tableContains(helper.echoCalls, "[map] no areas mapped yet"))
        end)

    end)

    describe("map-reset-area alias", function()

        it("resets the named area and forgets the mapping anchor", function()
            taPackage.currentRoomId = 42
            taPackage.prevRoomId = 41
            taPackage.pendingDirection = "n"
            taPackage.coord = { x = 1, y = 2, z = 0 }
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT id FROM areas", 1, true) then return { id = 2 } end
                return nil
            end
            helper.mockExecuteReturn = 33
            helper.simulateAlias("map-reset-area first-dungeon")
            assert.is_not_nil(helper.findDbCall("execute", "DELETE FROM rooms WHERE area_id"))
            assert.is_nil(taPackage.currentRoomId)
            assert.is_nil(taPackage.prevRoomId)
            assert.is_nil(taPackage.pendingDirection)
            assert.is_nil(taPackage.coord)
        end)

        it("does nothing for an unknown area slug", function()
            helper.mockDbOneRow = nil  -- areaIdBySlug finds no area
            helper.simulateAlias("map-reset-area bogus")
            assert.is_nil(helper.findDbCall("execute", "DELETE FROM rooms WHERE area_id"))
            assert.is_true(tableContains(helper.echoCalls, "[map] no such area: bogus"))
        end)

    end)

    describe("map-add-note alias", function()

        -- roomBySlug is a queryOne on "... FROM rooms WHERE slug = ?"; addRoomNote
        -- ends with a "last_insert_rowid()" queryOne. Route both from one stub.
        local function stubSlug(knownSlug, roomId, newNoteId)
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "FROM rooms WHERE slug", 1, true) then
                    if params[1] == knownSlug then return { id = roomId } end
                    return nil
                end
                if string.find(sql, "last_insert_rowid", 1, true) then
                    return { id = newNoteId }
                end
                return nil
            end
        end

        it("attaches a note to the current room when the first word isn't a slug", function()
            taPackage.mapping = true
            taPackage.currentRoomId = 12
            stubSlug("no-such-slug", nil, 3)
            helper.simulateAlias("map-add-note say komi here to open the south door")
            local ins = helper.findDbCall("execute", "INSERT INTO room_notes")
            assert.is_not_nil(ins)
            assert.are.equal(12, ins.params[1])
            assert.are.equal("say komi here to open the south door", ins.params[2])
        end)

        it("attaches to a room named by slug, stripping the slug from the note", function()
            taPackage.mapping = false          -- by-slug works even when not mapping
            taPackage.currentRoomId = nil
            stubSlug("cave-11", 20, 8)
            helper.simulateAlias("map-add-note cave-11 pull lever to disarm the trap ahead")
            local ins = helper.findDbCall("execute", "INSERT INTO room_notes")
            assert.is_not_nil(ins)
            assert.are.equal(20, ins.params[1])
            assert.are.equal("pull lever to disarm the trap ahead", ins.params[2])
        end)

        it("refuses when not anchored and no slug is given", function()
            taPackage.mapping = false
            taPackage.currentRoomId = nil
            stubSlug("cave-11", 20, 8)          -- "say" won't match, so no target
            helper.simulateAlias("map-add-note say komi here")
            assert.is_nil(helper.findDbCall("execute", "INSERT INTO room_notes"))
            assert.is_true(tableContains(helper.echoCalls,
                "[map] not anchored on a room -- map first, or target one by slug:"
                .. " map-add-note <room-slug> say komi here"))
        end)

    end)

    describe("map-notes alias", function()

        it("lists the current room's notes with their ids", function()
            taPackage.mapping = true
            taPackage.currentRoomId = 12
            helper.mockDbRows = { { id = 4, note = "say komi to open south" },
                                  { id = 5, note = "rest is safe here" } }
            helper.simulateAlias("map-notes")
            assert.is_true(tableContains(helper.echoCalls, "  #4  say komi to open south"))
            assert.is_true(tableContains(helper.echoCalls, "  #5  rest is safe here"))
        end)

        it("lists a room named by slug", function()
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "FROM rooms WHERE slug", 1, true) then return { id = 20 } end
                return nil
            end
            helper.mockDbRows = { { id = 9, note = "lever here" } }
            helper.simulateAlias("map-notes cave-11")
            assert.is_true(tableContains(helper.echoCalls, "[map] notes on cave-11:"))
            assert.is_true(tableContains(helper.echoCalls, "  #9  lever here"))
        end)

        it("reports an unknown slug", function()
            helper.mockDbOneRow = nil
            helper.simulateAlias("map-notes bogus-room")
            assert.is_true(tableContains(helper.echoCalls, "[map] no such room: bogus-room"))
        end)

    end)

    describe("map-del-note alias", function()

        it("deletes a note by id", function()
            helper.mockExecuteReturn = 1
            helper.simulateAlias("map-del-note 7")
            local del = helper.findDbCall("execute", "DELETE FROM room_notes WHERE id")
            assert.are.same({ 7 }, del.params)
            assert.is_true(tableContains(helper.echoCalls, "[map] deleted note #7"))
        end)

        it("reports when there's no such note", function()
            helper.mockExecuteReturn = 0
            helper.simulateAlias("map-del-note 999")
            assert.is_true(tableContains(helper.echoCalls, "[map] no note #999"))
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

        it("closes a drifted loop by topology when the coordinate match misses", function()
            -- We walked sw into provisional 5; dead-reckoning drifted, so the
            -- fingerprint (coordinate) match misses. The fallback uses the return
            -- door (ne): room 1 has the same exit-set with an unexplored ne, so
            -- it's the closure. Coord then snaps to room 1's stored position.
            taPackage.currentRoomId = 5
            taPackage.currentRoom = "town sewers"
            taPackage.currentRoomProvisional = true
            taPackage.currentEntryDir = "sw"        -- back = ne
            taPackage.coord = { x = 9, y = 9, z = 0 }  -- drifted
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE name", 1, true) then
                    return { { id = 1 }, { id = 5 } }
                elseif string.find(sql, "SELECT direction FROM room_exits WHERE from_id", 1, true) then
                    if params[1] == 1 then
                        return { { direction = "ne" }, { direction = "nw" }, { direction = "sw" } }
                    end
                    return {}
                end
                return {}  -- mergeRoomInto outgoing -> none
            end
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 0, y = 0, z = 0 }   -- room 1 sits elsewhere -> fingerprint misses
                elseif string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = nil }           -- room 1's ne return door is unexplored
                end
                return nil
            end
            helper.simulateLine("Exits: ne,nw,sw.")
            assert.are.equal(1, taPackage.currentRoomId)          -- closed onto room 1 topologically
            assert.is_false(taPackage.currentRoomProvisional)
            assert.are.same({ x = 0, y = 0, z = 0 }, taPackage.coord)  -- re-anchored to room 1
            assert.is_not_nil(helper.findDbCall("execute", "DELETE FROM rooms WHERE id"))
        end)

        it("does not topo-close when the return door already leads somewhere", function()
            -- Same shape, but room 1's ne is already walked (leads to 7): it's a
            -- look-alike, not the room we entered, so no merge -> no duplicate fold.
            taPackage.currentRoomId = 5
            taPackage.currentRoom = "town sewers"
            taPackage.currentRoomProvisional = true
            taPackage.currentEntryDir = "sw"
            taPackage.coord = { x = 9, y = 9, z = 0 }
            helper.mockDbRows = function(sql, params)
                if string.find(sql, "SELECT id FROM rooms WHERE name", 1, true) then
                    return { { id = 1 }, { id = 5 } }
                elseif string.find(sql, "SELECT direction FROM room_exits WHERE from_id", 1, true) then
                    if params[1] == 1 then
                        return { { direction = "ne" }, { direction = "nw" }, { direction = "sw" } }
                    end
                    return {}
                end
                return {}
            end
            helper.mockDbOneRow = function(sql)
                if string.find(sql, "SELECT x, y, z FROM rooms", 1, true) then
                    return { x = 0, y = 0, z = 0 }
                elseif string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 7 }             -- ne already leads to room 7
                end
                return nil
            end
            helper.simulateLine("Exits: ne,nw,sw.")
            assert.are.equal(5, taPackage.currentRoomId)          -- stayed the provisional
            assert.is_nil(helper.findDbCall("execute", "DELETE FROM rooms WHERE id"))
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

        it("map-off disables mapping", function()
            taPackage.mapping = true
            helper.simulateAlias("map-off")
            assert.is_false(taPackage.mapping)
        end)

        it("map-on no longer exists (folded into map-area / map-here)", function()
            taPackage.mapping = false
            helper.simulateAlias("map-on")
            assert.is_false(taPackage.mapping)  -- no alias matched, nothing happened
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

describe("re-roll-half-ogre-warrior-fast-mode", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function lastEcho()
        return helper.echoCalls[#helper.echoCalls]
    end

    describe("alias", function()

        it("sets reRolling to true", function()
            helper.simulateAlias("re-roll-half-ogre-warrior-fast-mode")
            assert.is_true(taPackage.reRolling)
        end)

        it("sends 'status'", function()
            helper.simulateAlias("re-roll-half-ogre-warrior-fast-mode")
            assert.are.equal("status", helper.sendCalls[1])
        end)

    end)

    describe("matching", function()

        before_each(function()
            helper.simulateAlias("re-roll-half-ogre-warrior-fast-mode")
        end)

        it("accepts a roll with Phy >= 28, Sta >= 28 and Agi >= 15", function()
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      28")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     28 / 28")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("ignores Int, Kno and Cha", function()
            helper.simulateLine("Intellect:    1")
            helper.simulateLine("Knowledge:    1")
            helper.simulateLine("Charisma:     1")
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      28")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     28 / 28")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("re-rolls when Physique is below 28", function()
            helper.simulateLine("Physique:     27")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Stamina is below 28", function()
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      27")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     27 / 27")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Agility is below 15", function()
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      14")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        -- The counterpart to the gold-farming case below: a re-roll somebody
        -- started by hand is one they are waiting on, so it still pings.
        it("pushes an ntfy notification for a hand-run re-roll", function()
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      28")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     28 / 28")
            assert.are.equal(1, #helper.httpRequestCalls)
            assert.are.equal("Re-roll complete",
                helper.httpRequestCalls[1].options.headers["X-Title"])
        end)

    end)

end)

-- The prompt wording throughout is transcribed from a hand-driven creation run,
-- logs/session-garbageman-2026-08-15T07-30-44.log lines 129-298, trailing
-- spaces and all.
describe("start-gold-farming", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function ranCommand(text)
        for _, cmd in ipairs(helper.runCommandCalls) do
            if cmd == text then return true end
        end
        return false
    end

    describe("before the alias is run", function()

        -- These lines all show up outside character creation -- "<< hit return
        -- >>" after a normal `x` out of the game, for one -- and a stray "1" or
        -- "6" landing in the arena is a real command. Nothing may be answered
        -- until the alias arms it.
        it("answers nothing", function()
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("Select an option: ")
            helper.simulateLine("Select a race: ")
            helper.simulateLine("Select a class: ")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("answering the creation prompts", function()

        before_each(function()
            helper.simulateAlias("start-gold-farming")
        end)

        it("sends nothing until a prompt arrives", function()
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("answers the whole sequence from the log", function()
            helper.simulateLine("Select an option: ")
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("Select a race: ")
            helper.simulateLine("Select a complexion: ")
            helper.simulateLine("Select an eye color: ")
            helper.simulateLine("Select a hair color: ")
            helper.simulateLine("Select a hair style: ")
            helper.simulateLine("Select a hair length: ")
            helper.simulateLine("Select a class: ")
            assert.are.same(
                { "2", "", "", "", "", "6", "1", "1", "1", "1", "1", "1" },
                helper.sendCalls)
        end)

        it("answers '6' for Half-Ogre", function()
            helper.simulateLine("Select a race: ")
            assert.are.same({ "6" }, helper.sendCalls)
        end)

        it("answers '1' for Warrior", function()
            helper.simulateLine("Select a class: ")
            assert.are.same({ "1" }, helper.sendCalls)
        end)

        -- "1" on this menu is Resurect Old Character, which would end the run
        -- with the same character we started with rather than a new one.
        it("answers '2' at the post-death menu, not '1'", function()
            helper.simulateLine("Select an option: ")
            assert.are.same({ "2" }, helper.sendCalls)
        end)

        it("answers '1' for every cosmetic prompt", function()
            helper.simulateLine("Select a complexion: ")
            helper.simulateLine("Select an eye color: ")
            helper.simulateLine("Select a hair color: ")
            helper.simulateLine("Select a hair style: ")
            helper.simulateLine("Select a hair length: ")
            assert.are.same({ "1", "1", "1", "1", "1" }, helper.sendCalls)
        end)

        -- An empty string, not a space: baud appends "\r\n" to whatever it is
        -- given, so "" is a bare carriage return while " " would be a space the
        -- BBS has to reject.
        it("pages the intro with a bare carriage return", function()
            helper.simulateLine("<< hit return >>")
            assert.are.same({ "" }, helper.sendCalls)
        end)

        -- One trigger answers the whole "Select a ...:" family. If a second,
        -- more general one were ever added alongside it, both would fire on the
        -- same line and the spare digit would sit in the BBS input buffer until
        -- the game started, then arrive in the arena as chat.
        it("answers each prompt exactly once", function()
            helper.simulateLine("Select a race: ")
            assert.are.equal(1, #helper.sendCalls)
        end)

        it("stops answering once we are in the game", function()
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            assert.is_false(taPackage.creating)
            local answersBefore = #helper.sendCalls
            helper.simulateLine("<< hit return >>")
            helper.simulateLine("Select a race: ")
            assert.are.equal(answersBefore, #helper.sendCalls)
        end)

    end)

    describe("handing off to the re-roll", function()

        before_each(function()
            helper.simulateAlias("start-gold-farming")
        end)

        -- The entry `st`/`i` replies are still in flight here, and the `st`
        -- reply's "Vitality:" line is what the re-roll counts a roll on. Arming
        -- the matcher now would score the new character's opening stats as roll
        -- #1 before a matcher had been chosen.
        it("does not start on 'Entering Tele-Arena...'", function()
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            assert.is_false(ranCommand("re-roll-half-ogre-warrior-fast-mode"))
            assert.is_falsy(taPackage.reRolling)
        end)

        it("starts on the inventory reply, once the sheet has landed", function()
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.is_true(ranCommand("re-roll-half-ogre-warrior-fast-mode"))
            assert.is_true(taPackage.reRolling)
        end)

        it("starts it only once", function()
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            local runsBefore = #helper.runCommandCalls
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.are.equal(runsBefore, #helper.runCommandCalls)
        end)

        -- A gold line from any other errand must not start a re-roll.
        it("does not start on a gold line outside a creation run", function()
            helper.simulateAlias("stop-gold-farming")
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.is_false(ranCommand("re-roll-half-ogre-warrior-fast-mode"))
        end)

    end)

    -- TA_INIT_CMD cannot reach a dead character: entering the game is what
    -- arms it, and a dead character never enters. TA_LOGIN_CMD fires at the
    -- username prompt instead, which happens on both paths.
    describe("arming from the environment", function()

        local function loadWith(env)
            helper.resetAll()
            helper.env = env
            dofile("main.lua")
        end

        it("TA_LOGIN_CMD arms creation at the username prompt", function()
            loadWith({ TA_CHARACTER = "garbageman", TA_PASSWORD = "x",
                       TA_LOGIN_CMD = "start-gold-farming" })
            helper.simulateLine("Username:")
            assert.is_true(taPackage.creating)
        end)

        -- The whole point: this is the path a dead character takes. It never
        -- prints "Entering Tele-Arena...", so nothing downstream of that line
        -- can be relied on to arm anything.
        it("answers the resurrect menu on the dead-character path", function()
            loadWith({ TA_CHARACTER = "garbageman", TA_PASSWORD = "x",
                       TA_LOGIN_CMD = "start-gold-farming" })
            helper.simulateLine("Username:")
            helper.simulateLine("Password:")
            helper.simulateLine("Make your selection (1,2,3,...):")
            helper.simulateLine("1) Resurect Old Character for 0 Credits.")
            helper.simulateLine("2) Create New Character")
            helper.simulateLine("3) Exit")
            helper.simulateLine("Select an option: ")
            -- username, password, the menu's "5", then "2" for Create New
            assert.are.same({ "garbageman", "x", "5", "2" }, helper.sendCalls)
        end)

        it("runs TA_LOGIN_CMD only once per login prompt", function()
            loadWith({ TA_CHARACTER = "garbageman", TA_PASSWORD = "x",
                       TA_LOGIN_CMD = "start-gold-farming" })
            helper.simulateLine("Username:")
            local runs = #helper.runCommandCalls
            helper.simulateLine("Username:")
            assert.are.equal(runs + 1, #helper.runCommandCalls)
        end)

        it("does nothing when TA_LOGIN_CMD is unset", function()
            loadWith({ TA_CHARACTER = "garbageman", TA_PASSWORD = "x" })
            helper.simulateLine("Username:")
            assert.is_falsy(taPackage.creating)
        end)

        -- Regression: TA_INIT_CMD fires off the inventory reply, and main.lua's
        -- gold trigger is registered before ta_create.lua's. Left unguarded,
        -- re-arming there both stranded prompt-answering in-game and cleared
        -- the handoff flag the next trigger was about to read, costing the
        -- re-roll entirely.
        it("TA_INIT_CMD cannot re-arm creation on top of the re-roll handoff", function()
            loadWith({ TA_CHARACTER = "garbageman", TA_PASSWORD = "x",
                       TA_INIT_CMD = "start-gold-farming" })
            helper.simulateLine("Username:")
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.is_false(taPackage.creating)
            assert.is_true(taPackage.reRolling)
        end)

    end)

    describe("gearing up and heading for the arena", function()

        -- Drive a scripted run all the way to an accepted roll. The command
        -- record is cleared just before the accepting roll lands, so everything
        -- in it afterwards is a walk step and not the handoff that started the
        -- re-roll in the first place.
        local function reachAcceptedRoll()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            for k in pairs(helper.runCommandCalls) do helper.runCommandCalls[k] = nil end
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      16")
            helper.simulateLine("Vitality:     30 / 30")
        end

        -- Run the paced walk to completion. Each pump arms the next timer, so
        -- fireTimers advances exactly one step per call.
        local function walkToEnd()
            for _ = 1, 40 do
                if not taPackage.createWalk then break end
                helper.fireTimers(taPackage.arenaStepDelayMs)
            end
        end

        it("runs the sequence, in order, once the roll is accepted", function()
            reachAcceptedRoll()
            walkToEnd()
            assert.are.same({
                "re-roll-stop",
                "s", "sw",
                "get robes", "equip robes",
                "get warhammer", "equip warhammer",
                "ne", "s",
                "buy-potions",
                "n", "n", "e",
                "rg 1",
                "arena-potions-drunk",
            }, helper.runCommandCalls)
        end)

        -- Stat potions were tried, dropped, and are now back: they take the hit
        -- rate from 37% to 64%, and the 22m 24s training taint that made them a
        -- wash the first time is now bought off at the temple for 25 crowns
        -- (see the note above CREATE_STEPS in ta_create.lua).
        it("detours to the magic shop for both stat potions", function()
            reachAcceptedRoll()
            walkToEnd()
            assert.is_true(ranCommand("buy-potions"))
        end)

        -- The report has to land AFTER rg 1, because starting a session zeroes
        -- arenaPotionsActive. Reversed, the arena would think the character is
        -- clean and bounce off the guild hall on its first level.
        it("tells the arena about the potions after starting it, not before", function()
            reachAcceptedRoll()
            walkToEnd()
            local rg, report
            for i, cmd in ipairs(helper.runCommandCalls) do
                if cmd == "rg 1" then rg = i end
                if cmd == "arena-potions-drunk" then report = i end
            end
            assert.is_not_nil(rg)
            assert.is_not_nil(report)
            assert.is_true(report > rg)
        end)

        -- The detour rejoins the original walk rather than replacing it: the
        -- character still has to end up in the arena, two rooms north and one east
        -- of the magic shop.
        it("still ends the walk in the arena", function()
            reachAcceptedRoll()
            walkToEnd()
            local last = {}
            for i = #helper.runCommandCalls - 4, #helper.runCommandCalls do
                last[#last + 1] = helper.runCommandCalls[i]
            end
            assert.are.same({ "n", "n", "e", "rg 1", "arena-potions-drunk" }, last)
        end)

        -- The user's explicit ask, and load-bearing: accepting a roll leaves
        -- taPackage.reRolling true, so every later status block -- including the
        -- ones rg 1 pulls -- would be fed back through the matcher.
        it("stops the re-roll first, before it walks anywhere", function()
            reachAcceptedRoll()
            assert.are.equal("re-roll-stop", helper.runCommandCalls[1])
            assert.is_false(taPackage.reRolling)
        end)

        -- A gold-farming cycle throws its character away, so its stats are not
        -- news; the phone would buzz once per cycle for a number nobody acts on.
        -- The hand-run re-roll still notifies (see the fast-mode suite above).
        it("sends no ntfy notification for a scripted run", function()
            reachAcceptedRoll()
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("paces the steps instead of sending them in one burst", function()
            reachAcceptedRoll()
            assert.are.equal(1, #helper.runCommandCalls)
            helper.fireTimers(taPackage.arenaStepDelayMs)
            assert.are.equal(2, #helper.runCommandCalls)
        end)

        it("ends the walk after the last step", function()
            reachAcceptedRoll()
            walkToEnd()
            assert.is_nil(taPackage.createWalk)
        end)

        -- A hand-run re-roll is someone watching numbers go by. Marching the
        -- character off to ring a gong would be a nasty surprise.
        it("does not fire for a hand-run re-roll", function()
            helper.simulateAlias("re-roll-half-ogre-warrior-fast-mode")
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      16")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_nil(taPackage.createWalk)
            assert.is_false(ranCommand("rg 1"))
            -- and it is still running, waiting for a hand-typed re-roll-stop
            assert.is_true(taPackage.reRolling)
        end)

        it("does not fire on a roll that was rejected", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            helper.simulateLine("Physique:     10")
            helper.simulateLine("Stamina:      10")
            helper.simulateLine("Agility:      10")
            helper.simulateLine("Vitality:     20 / 20")
            assert.is_nil(taPackage.createWalk)
        end)

        describe("a move the game refused", function()

            -- No room brief follows either line, so a clock-driven walk would
            -- carry on and run the rest of the list one room too far back.
            --
            -- The two refusals get different waits on purpose. A trip clears in
            -- a couple of seconds; being told to rest means the physical
            -- cooldown is running, which is tens of seconds. That one bites
            -- every run -- the walk starts right after ~76 rerolls -- and at the
            -- trip's 2s it spent 13 commands grinding through it live, in
            -- logs/session-garbageman-2026-08-15T14-17-19.log.
            for _, case in ipairs({
                { line = "In your haste, you trip and fall!", delay = 2000 },
                { line = "Sorry, you'll have to rest a while before you can move.",
                  delay = 30000 },
            }) do
                it("retries after '" .. case.line .. "' in " .. case.delay .. "ms", function()
                    reachAcceptedRoll()
                    helper.fireTimers(taPackage.arenaStepDelayMs) -- "s"
                    assert.are.equal("s", helper.runCommandCalls[#helper.runCommandCalls])
                    helper.simulateLine(case.line)
                    helper.fireTimers(case.delay)
                    assert.are.equal("s", helper.runCommandCalls[#helper.runCommandCalls])
                    -- and the walk carries on from there, not from further along
                    helper.fireTimers(taPackage.arenaStepDelayMs)
                    assert.are.equal("sw", helper.runCommandCalls[#helper.runCommandCalls])
                end)
            end

            -- The distinction is the whole point of the fix, so pin it: the rest
            -- refusal must NOT retry on the trip's short cadence.
            it("does not retry a rest refusal on the trip's 2s cadence", function()
                reachAcceptedRoll()
                helper.fireTimers(taPackage.arenaStepDelayMs) -- "s"
                local runsBefore = #helper.runCommandCalls
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.fireTimers(2000)
                assert.are.equal(runsBefore, #helper.runCommandCalls)
            end)

            -- The retry bumps the generation; the pacing timer already in flight
            -- must land as a no-op rather than sending the step a second time.
            it("does not double-send when the paced timer also fires", function()
                reachAcceptedRoll()
                helper.fireTimers(taPackage.arenaStepDelayMs) -- "s"
                helper.simulateLine("In your haste, you trip and fall!")
                helper.fireTimers() -- both the stale pacing timer and the retry
                local sCount = 0
                for _, c in ipairs(helper.runCommandCalls) do
                    if c == "s" then sCount = sCount + 1 end
                end
                assert.are.equal(2, sCount) -- the original and one retry
            end)

            it("is inert when no walk is running", function()
                assert.has_no.errors(function()
                    helper.simulateLine("In your haste, you trip and fall!")
                end)
            end)

        end)

        it("stop-gold-farming halts a walk in progress", function()
            reachAcceptedRoll()
            helper.fireTimers(taPackage.arenaStepDelayMs)
            helper.simulateAlias("stop-gold-farming")
            assert.is_nil(taPackage.createWalk)
            local runsBefore = #helper.runCommandCalls
            helper.fireTimers()
            assert.are.equal(runsBefore, #helper.runCommandCalls)
        end)

        it("stop-all-scripts halts a walk in progress", function()
            reachAcceptedRoll()
            helper.fireTimers(taPackage.arenaStepDelayMs)
            helper.simulateAlias("stop-all-scripts")
            assert.is_nil(taPackage.createWalk)
        end)

    end)

    -- rg 1 does the fighting and the whole training trip itself (checkTrainingNeeded,
    -- toTraining = { "w", "n" }, "buy training"). This loop only takes the wheel
    -- afterwards, back in the arena, where rg 1 would otherwise ring and fight on.
    describe("cashing out after training", function()

        local TRAINED = "After a rigorous mental and physical training session, you managed to blend"

        local function walkToEnd()
            for _ = 1, 40 do
                if not taPackage.createWalk then break end
                if taPackage.createWalk.awaiting then break end
                helper.fireTimers(taPackage.arenaStepDelayMs)
            end
        end

        -- Walk out of the arena and into the tavern, where the arrival prints the
        -- room brief the handover reads its recipient off. Transcribed from
        -- logs/session-garbageman-2026-08-16T02-29-07.log (line 1885): NPC line,
        -- occupant line, floor line. `occupants` is the middle line, or nil for a
        -- tavern with no players in it, where the game prints "There is nobody
        -- here." in its place. Leaves the walk parked on the inventory reply.
        local function arriveInTavern(occupants)
            walkToEnd()
            helper.simulateLine("There is a barkeep, and a barmaid here.")
            helper.simulateLine(occupants or "There is nobody here.")
            helper.simulateLine("There is nothing on the floor.")
            walkToEnd()
        end

        local function arriveInTavernWithKerhak()
            arriveInTavern("Kerhak is here.")
        end

        -- A gold-farming run that has reached the arena and just banked a level.
        --
        -- The gold matters: main.lua's own handler for this line charges the
        -- training fee, and setGold runs the arena's gold floor, which
        -- emergency-exits the run (clearing arenaState) if the balance lands
        -- under 50. A character with nothing in its pockets therefore never
        -- reaches our handler at all.
        local function trainDuringGoldFarming()
            helper.simulateAlias("start-gold-farming")
            taPackage.arenaState = "training"
            setLevel(1)
            setGold(1372)
            helper.simulateLine(TRAINED)
        end

        it("arms the cash-out on the training confirmation", function()
            trainDuringGoldFarming()
            assert.is_true(taPackage.createCashOutArmed)
            -- but does not move yet: the arena is still walking us home
            assert.is_nil(taPackage.createWalk)
        end)

        it("takes over when the arena gets back home, and stops the arena", function()
            trainDuringGoldFarming()
            assert.is_true(taPackage.onArenaArrivedHome())
            assert.is_nil(taPackage.arenaState)
            assert.is_not_nil(taPackage.createWalk)
        end)

        it("walks to the tavern and asks what it is carrying", function()
            trainDuringGoldFarming()
            for k in pairs(helper.runCommandCalls) do helper.runCommandCalls[k] = nil end
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            assert.are.same({ "w", "ne", "i" }, helper.runCommandCalls)
        end)

        -- The amount is whatever the reply says, not our own tracked figure: the
        -- arena spends on healing, food and training as it goes. The name is
        -- spelled the way the brief spelled it, so the give names exactly who the
        -- game said was standing there.
        it("hands over the amount the inventory reports", function()
            trainDuringGoldFarming()
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            helper.simulateLine("You are carrying 1372 gold crowns.")
            assert.is_true(ranCommand("give Kerhak 1372 gold"))
        end)

        it("runs the whole sequence in order", function()
            trainDuringGoldFarming()
            for k in pairs(helper.runCommandCalls) do helper.runCommandCalls[k] = nil end
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            helper.simulateLine("You are carrying 1372 gold crowns.")
            walkToEnd()
            -- parked on the second `i`, the gate in front of the suicide
            helper.simulateLine("You are carrying 0 gold crowns.")
            walkToEnd()
            assert.are.same({
                "w", "ne", "i", "give Kerhak 1372 gold",
                "sw", "s", "sw",
                "unequip robes", "drop robes",
                "unequip warhammer", "drop warhammer",
                "i", "suicide",
            }, helper.runCommandCalls)
        end)

        -- The receiving character is whoever the tavern's own room brief names,
        -- not a name compiled into the script: the farm should keep working when
        -- the gold is being collected by somebody other than Kerhak.
        describe("who the gold goes to", function()

            local function stopped(word)
                for _, text in ipairs(helper.echoCalls) do
                    if text and text:find("STOPPED", 1, true)
                        and text:find(word, 1, true) then return true end
                end
                return false
            end

            it("gives to whoever the brief names", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavern("Pollux is here.")
                helper.simulateLine("You are carrying 900 gold crowns.")
                assert.is_true(ranCommand("give Pollux 900 gold"))
            end)

            it("reports the handover against that name", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavern("Pollux is here.")
                helper.simulateLine("You are carrying 900 gold crowns.")
                walkToEnd()
                helper.simulateLine("You are carrying 0 gold crowns.")
                local call = helper.httpRequestCalls[#helper.httpRequestCalls]
                assert.are.equal("Gave 900 gold to Pollux", call.options.body)
            end)

            -- An empty tavern prints "There is nobody here." in the occupant
            -- slot, so the only thing that ends the brief is the floor line.
            -- Walking on from it would drop the gear and take the takings into
            -- the suicide.
            it("stops when the tavern is empty", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavern(nil)
                assert.is_nil(taPackage.createWalk)
                assert.is_false(taPackage.createCharacterRunning())
                assert.is_true(stopped("nobody"))
                assert.is_true(#helper.httpRequestCalls > 0)
            end)

            it("does not ask what it is carrying when nobody is there", function()
                trainDuringGoldFarming()
                for k in pairs(helper.runCommandCalls) do helper.runCommandCalls[k] = nil end
                taPackage.onArenaArrivedHome()
                arriveInTavern(nil)
                helper.fireTimers()
                assert.are.same({ "w", "ne" }, helper.runCommandCalls)
            end)

            -- A guess would be a live command sending the whole harvest to
            -- whoever happened to be sitting in a public bar.
            it("stops when more than one character is there", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavern("Kerhak and Pollux are here.")
                assert.is_nil(taPackage.createWalk)
                assert.is_false(taPackage.createCharacterRunning())
                assert.is_true(stopped("Kerhak, Pollux"))
                assert.is_true(#helper.httpRequestCalls > 0)
            end)

            it("does not hand anything over when the brief never comes", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                walkToEnd() -- parked on the brief after "ne"
                helper.fireTimers(10000) -- the reply timeout walks on to `i`
                walkToEnd()
                helper.simulateLine("You are carrying 900 gold crowns.")
                assert.is_false(ranCommand("give Kerhak 900 gold"))
                assert.is_nil(taPackage.createWalk)
                assert.is_true(stopped("no room brief"))
            end)

            -- A refused "ne" never reaches the tavern, so no brief is coming and
            -- the refusal is ours: retry the move rather than sitting out the
            -- timeout and arriving at the give with nobody to give to.
            it("retries the move into the tavern when it trips", function()
                trainDuringGoldFarming()
                for k in pairs(helper.runCommandCalls) do helper.runCommandCalls[k] = nil end
                taPackage.onArenaArrivedHome()
                walkToEnd()
                helper.simulateLine("In your haste, you trip and fall!")
                helper.fireTimers(2000)
                assert.are.same({ "w", "ne", "ne" }, helper.runCommandCalls)
                assert.are.equal("recipient", taPackage.createWalk.awaiting)
            end)

            -- The brief's other two lines must stay out of the roster: an NPC
            -- line would otherwise hand the takings to the barkeep.
            it("does not mistake the NPCs for the recipient", function()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavern(nil)
                assert.is_false(ranCommand("give a barkeep 900 gold"))
                assert.is_true(stopped("nobody"))
            end)

        end)

        -- A suicide takes whatever is still being carried with it, so a hard
        -- zero read back from the game is the only proof the handover landed.
        describe("the gate in front of the suicide", function()

            local function reachTheGate()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavernWithKerhak()
                helper.simulateLine("You are carrying 1372 gold crowns.")
                walkToEnd()
                assert.are.equal("zero-gold", taPackage.createWalk.awaiting)
            end

            -- The most recent push, not the only one: the training confirmation
            -- that starts this cycle pings on its own account.
            local function lastNtfy()
                local call = helper.httpRequestCalls[#helper.httpRequestCalls]
                return call.options.headers["X-Title"], call.options.body
            end

            it("goes through with the suicide on zero", function()
                reachTheGate()
                helper.simulateLine("You are carrying 0 gold crowns.")
                walkToEnd()
                assert.is_true(ranCommand("suicide"))
            end)

            -- The harvest for the cycle, reported once the game has confirmed
            -- the gold actually left our hands -- the give alone proves nothing.
            it("reports the handover once the zero comes back", function()
                reachTheGate()
                helper.simulateLine("You are carrying 0 gold crowns.")
                local title, body = lastNtfy()
                assert.are.equal("Farming", title)
                assert.are.equal("Gave 1372 gold to Kerhak", body)
            end)

            it("stops instead of destroying gold still in hand", function()
                reachTheGate()
                helper.simulateLine("You are carrying 617 gold crowns.")
                helper.fireTimers()
                helper.fireTimers()
                assert.is_false(ranCommand("suicide"))
                assert.is_nil(taPackage.createWalk)
                assert.is_false(taPackage.createCharacterRunning())
                assert.is_true(#helper.httpRequestCalls > 0)
            end)

            it("notifies the failure rather than the handover", function()
                reachTheGate()
                helper.simulateLine("You are carrying 617 gold crowns.")
                local title, body = lastNtfy()
                assert.are.equal("Farming", title)
                assert.are.equal("Encountered a problem. Exited game.", body)
            end)

            -- Standing there with the gear already dropped only starves the
            -- character, so it leaves with the takings instead.
            it("exits the game", function()
                reachTheGate()
                helper.simulateLine("You are carrying 617 gold crowns.")
                assert.are.equal("x", helper.sendCalls[#helper.sendCalls])
            end)

        end)

        it("skips the handover when carrying nothing, and walks on", function()
            trainDuringGoldFarming()
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            helper.simulateLine("You are carrying 0 gold crowns.")
            assert.is_false(ranCommand("give kerhak 0 gold"))
            walkToEnd()
            assert.is_true(ranCommand("drop warhammer"))
        end)

        -- Nothing changed hands, so the zero at the gate is not a handover to
        -- report -- a "Gave 0 gold" push would be noise once per empty cycle.
        it("reports no handover when there was nothing to hand over", function()
            trainDuringGoldFarming()
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            helper.simulateLine("You are carrying 0 gold crowns.")
            walkToEnd()
            local pushes = #helper.httpRequestCalls
            helper.simulateLine("You are carrying 0 gold crowns.")
            assert.are.equal(pushes, #helper.httpRequestCalls)
        end)

        -- An `i` that draws no reply must not park the walk in the tavern forever.
        it("carries on if the inventory reply never arrives", function()
            trainDuringGoldFarming()
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            assert.are.equal("gold", taPackage.createWalk.awaiting)
            helper.fireTimers(10000)
            assert.is_nil(taPackage.createWalk.awaiting)
            walkToEnd()
            assert.is_true(ranCommand("drop warhammer"))
        end)

        -- A refusal while parked on a reply belongs to something else; rewinding
        -- would re-run the step before it and lose the reply.
        it("ignores a move refusal while waiting on the inventory", function()
            trainDuringGoldFarming()
            taPackage.onArenaArrivedHome()
            arriveInTavernWithKerhak()
            local before = #helper.runCommandCalls
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(2000)
            assert.are.equal(before, #helper.runCommandCalls)
            assert.are.equal("gold", taPackage.createWalk.awaiting)
        end)

        -- A hand-started rg 1 must never end with the character in the tavern
        -- and its gear on the floor.
        it("does not fire for an arena run this loop did not start", function()
            taPackage.arenaState = "training"
            setLevel(1)
            helper.simulateLine(TRAINED)
            assert.is_nil(taPackage.createCashOutArmed)
            assert.is_false(taPackage.onArenaArrivedHome())
        end)

        it("leaves an ordinary arrival home alone", function()
            helper.simulateAlias("start-gold-farming")
            assert.is_false(taPackage.onArenaArrivedHome())
        end)

        -- Gold has weight, so a character that only ever receives it fills up.
        -- Seen live: 13 handovers, 1323/1450 encumbrance, then a refusal.
        describe("the recipient is too full to accept", function()

            local FULL = "Sorry, Kerhak can't carry that much more gold."

            local function handoverRefused()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavernWithKerhak()
                helper.simulateLine("You are carrying 822 gold crowns.")
                helper.simulateLine(FULL)
            end

            it("stops at the refusal", function()
                handoverRefused()
                assert.is_nil(taPackage.createWalk)
                assert.is_false(taPackage.createCharacterRunning())
            end)

            -- Last time this happened the walk carried on and the gear was on
            -- the floor before anything noticed, six steps later.
            it("keeps the gear on rather than dropping it", function()
                handoverRefused()
                helper.fireTimers()
                helper.fireTimers()
                assert.is_false(ranCommand("drop robes"))
                assert.is_false(ranCommand("drop warhammer"))
                assert.is_false(ranCommand("suicide"))
            end)

            it("names who is full, and notifies", function()
                handoverRefused()
                local said = false
                for _, text in ipairs(helper.echoCalls) do
                    if text and text:find("STOPPED", 1, true)
                        and text:find("Kerhak", 1, true) then said = true end
                end
                assert.is_true(said)
                assert.is_true(#helper.httpRequestCalls > 0)
            end)

            it("is inert outside a cash-out walk", function()
                assert.has_no.errors(function() helper.simulateLine(FULL) end)
            end)

        end)

        -- Kerhak is the whole point: the gold has to end up somewhere that
        -- survives this character being replaced. No Kerhak, no run.
        describe("nobody there to take the gold", function()

            local MISSING = "Sorry, you don't see \"kerhak\" nearby."

            local function giveIntoAnEmptyRoom()
                trainDuringGoldFarming()
                taPackage.onArenaArrivedHome()
                arriveInTavernWithKerhak()
                helper.simulateLine("You are carrying 799 gold crowns.")
                helper.simulateLine(MISSING)
            end

            it("stops the run", function()
                giveIntoAnEmptyRoom()
                assert.is_nil(taPackage.createWalk)
                assert.is_falsy(taPackage.goldFarming)
                assert.is_false(taPackage.createCharacterRunning())
            end)

            -- Walking on would drop the gear and leave the takings in the pocket
            -- of a character we are about to throw away.
            it("does not drop the gear", function()
                giveIntoAnEmptyRoom()
                helper.fireTimers()
                helper.fireTimers()
                assert.is_false(ranCommand("drop robes"))
                assert.is_false(ranCommand("drop warhammer"))
            end)

            it("says why, in the session log", function()
                giveIntoAnEmptyRoom()
                local said = false
                for _, text in ipairs(helper.echoCalls) do
                    if text and text:find("STOPPED", 1, true)
                        and text:find("kerhak", 1, true) then
                        said = true
                    end
                end
                assert.is_true(said)
            end)

            -- An unattended loop that stops silently just looks like a loop that
            -- is still running. sendNtfy goes out over httpRequest, not httpPost.
            it("pushes a notification", function()
                giveIntoAnEmptyRoom()
                assert.is_true(#helper.httpRequestCalls > 0)
            end)

            -- This line is one of the commonest in the game: it is what a whiffed
            -- attack prints when the monster is already dead. Ungated, it would
            -- halt the loop on almost every arena fight.
            it("ignores it outside a cash-out walk", function()
                helper.simulateAlias("start-gold-farming")
                taPackage.arenaState = "fighting"
                assert.has_no.errors(function()
                    helper.simulateLine("Sorry, you don't see \"flame\" nearby.")
                end)
                assert.is_true(taPackage.goldFarming)
            end)

            -- Nor during the gear-up walk, which names no targets.
            it("ignores it during the gear-up walk", function()
                helper.simulateAlias("start-gold-farming")
                helper.simulateLine("Select a class: ")
                helper.simulateLine("Entering Tele-Arena...")
                helper.simulateLine("You are carrying 830 gold crowns.")
                helper.simulateLine("Physique:     29")
                helper.simulateLine("Stamina:      30")
                helper.simulateLine("Agility:      16")
                helper.simulateLine("Vitality:     30 / 30")
                helper.simulateLine("Sorry, you don't see \"flame\" nearby.")
                assert.is_not_nil(taPackage.createWalk)
            end)

        end)

    end)

    -- Round trip complete: throw the character away and start over. Almost all
    -- of the restart is the creation triggers at the top of the file doing their
    -- original job again; only the BBS menu "5" needed anything new.
    describe("starting the next character", function()

        local AWAKEN = "You awaken after an unknown amount of time..."
        -- After a death the BBS redraws its menu as a full-screen box, so the
        -- prompt arrives as that box's status bar rather than as the "Make your
        -- selection" line an ordinary login sees. These are the real bytes with
        -- ANSI stripped (what triggers are handed), from the archived
        -- session-garbageman-2026-08-15T07-30-44.log line 151.
        -- Exactly what a trigger is handed, trailing escape and all. baud strips
        -- SGR colour codes only (ANSIParser.ts:312), so the BBS's closing
        -- cursor-left survives -- which is what made the first live run of the
        -- loop sit at the BBS forever with an end-of-line anchor.
        local COMMAND_PROMPT = "■ 20:11:28 ■ 15-AUG-26 ■ Command ■ : \27[1D"

        it("re-arms the creation prompts once the death is confirmed", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(AWAKEN)
            assert.is_true(taPackage.creating)
        end)

        it("answers the BBS command prompt with 5", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(AWAKEN)
            helper.simulateLine(COMMAND_PROMPT)
            assert.are.equal("5", helper.sendCalls[#helper.sendCalls])
        end)

        it("then answers the resurrect menu, closing the loop", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(AWAKEN)
            helper.simulateLine(COMMAND_PROMPT)
            helper.simulateLine("Select an option: ")
            helper.simulateLine("Select a race: ")
            helper.simulateLine("Select a class: ")
            assert.are.same({ "5", "2", "6", "1" }, helper.sendCalls)
        end)

        -- Only once per death. The BBS redraws that prompt whenever it likes,
        -- and a spare "5" would sit in its input buffer until the game started
        -- and then arrive in the arena as chat.
        it("answers the command prompt only once", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine(AWAKEN)
            helper.simulateLine(COMMAND_PROMPT)
            local sent = #helper.sendCalls
            helper.simulateLine(COMMAND_PROMPT)
            assert.are.equal(sent, #helper.sendCalls)
        end)

        -- main.lua's own login answer covers the menu during an ordinary login;
        -- this must not double up on it.
        it("is inert during an ordinary login", function()
            helper.simulateLine(COMMAND_PROMPT)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("does not restart a death outside a gold-farming run", function()
            helper.simulateLine(AWAKEN)
            assert.is_falsy(taPackage.creating)
            helper.simulateLine(COMMAND_PROMPT)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("stop-gold-farming ends the loop instead of restarting", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateAlias("stop-gold-farming")
            helper.simulateLine(AWAKEN)
            assert.is_false(taPackage.creating)
            helper.simulateLine(COMMAND_PROMPT)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    -- The arena is where a run spends nearly all its time, so it is where a
    -- dropped connection lands, and the expensive phase to lose.
    describe("continue-farming-gold-from-arena", function()

        it("arms the loop and starts the arena", function()
            taPackage.currentRoom = "arena"
            helper.simulateAlias("continue-farming-gold-from-arena")
            assert.is_true(taPackage.goldFarming)
            assert.is_true(ranCommand("rg 1"))
        end)

        it("is reachable under the other word order too", function()
            taPackage.currentRoom = "arena"
            helper.simulateAlias("continue-gold-farming-from-arena")
            assert.is_true(ranCommand("rg 1"))
        end)

        -- start-/stop- take both word orders for the same reason: the wrong one
        -- silently doing nothing looks exactly like a script that failed to arm.
        it("start- and stop- take both word orders too", function()
            helper.simulateAlias("start-farming-gold")
            assert.is_true(taPackage.goldFarming)
            helper.simulateAlias("stop-farming-gold")
            assert.is_falsy(taPackage.goldFarming)
            helper.simulateAlias("start-gold-farming")
            assert.is_true(taPackage.goldFarming)
            helper.simulateAlias("stop-gold-farming")
            assert.is_falsy(taPackage.goldFarming)
        end)

        -- Resuming is only worth anything if the cash-out still fires at the end.
        it("still cashes out when the level lands", function()
            taPackage.currentRoom = "arena"
            helper.simulateAlias("continue-farming-gold-from-arena")
            taPackage.arenaState = "training"
            setLevel(1)
            setGold(1372)
            helper.simulateLine(
                "After a rigorous mental and physical training session, you managed to blend")
            assert.is_true(taPackage.createCashOutArmed)
        end)

        it("refuses when standing somewhere else", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("continue-farming-gold-from-arena")
            assert.is_false(ranCommand("rg 1"))
            assert.is_falsy(taPackage.goldFarming)
        end)

        -- No brief seen since connecting is not an error, just unverifiable.
        it("proceeds when the room is not known yet", function()
            helper.simulateAlias("continue-farming-gold-from-arena")
            assert.is_true(ranCommand("rg 1"))
        end)

        -- A reload keeps taPackage, so a half-finished walk or an armed cash-out
        -- from before the drop must not survive into the resumed run.
        it("clears stale state from the interrupted run", function()
            taPackage.currentRoom = "arena"
            taPackage.createWalk = { steps = { "x" }, index = 1, label = "cash-out" }
            taPackage.createCashOutArmed = true
            taPackage.createRestarting = true
            helper.simulateAlias("continue-farming-gold-from-arena")
            assert.is_nil(taPackage.createWalk)
            assert.is_nil(taPackage.createCashOutArmed)
            assert.is_nil(taPackage.createRestarting)
            assert.is_true(taPackage.goldFarming)
        end)

    end)

    -- Entering the game and creating a character are not the same event. A live
    -- character goes from the main menu straight to "Entering Tele-Arena...",
    -- with no resurrect menu and none of the creation questions -- which is
    -- exactly what a reconnect looks like.
    describe("reconnecting with a live character", function()

        it("does not re-roll a character it did not create", function()
            helper.resetAll()
            helper.env = { TA_CHARACTER = "garbageman", TA_PASSWORD = "x",
                           TA_LOGIN_CMD = "start-gold-farming" }
            dofile("main.lua")
            helper.simulateLine("Username:")
            -- straight in: no "Select an option:", no race, no class
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 1500 gold crowns.")
            assert.is_falsy(taPackage.reRolling)
            local rolled = false
            for _, c in ipairs(helper.runCommandCalls) do
                if c == "re-roll-half-ogre-warrior-fast-mode" then rolled = true end
            end
            assert.is_false(rolled)
        end)

        -- ...but a real creation, which answers the class question last, still does.
        it("still re-rolls a character it did create", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.is_true(taPackage.reRolling)
        end)

    end)

    describe("stop-gold-farming", function()

        it("disarms the prompt answers", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateAlias("stop-gold-farming")
            helper.simulateLine("Select a race: ")
            assert.is_false(taPackage.creating)
            assert.are.equal(0, #helper.sendCalls)
        end)

        -- A stop between "Entering Tele-Arena..." and the inventory reply means
        -- we no longer want the re-roll either.
        it("cancels a re-roll that is armed but not yet started", function()
            helper.simulateAlias("start-gold-farming")
            helper.simulateLine("Select a class: ")
            helper.simulateLine("Entering Tele-Arena...")
            helper.simulateAlias("stop-gold-farming")
            helper.simulateLine("You are carrying 830 gold crowns.")
            assert.is_false(ranCommand("re-roll-half-ogre-warrior-fast-mode"))
        end)

        it("is a safe no-op when nothing is running", function()
            assert.has_no.errors(function()
                helper.simulateAlias("stop-gold-farming")
            end)
        end)

    end)

end)

-- Gold has weight. Overnight on 2026-08-16 the receiving character took 13
-- gifts totalling 10,617 gold, hit 1323/1450 encumbrance, and the next handover
-- was refused with "Sorry, Kerhak can't carry that much more gold." -- stopping
-- the farm with 822 gold stranded.
describe("start-banking", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local RECEIVED = "Garbageman just gave you 842 gold coins."

    local function walkToEnd()
        for _ = 1, 20 do
            if not taPackage.createWalk then break end
            helper.fireTimers(taPackage.arenaStepDelayMs)
        end
    end

    it("does nothing until it is armed", function()
        helper.simulateLine(RECEIVED)
        assert.is_nil(taPackage.createWalk)
        assert.are.equal(0, #helper.sendCalls)
    end)

    -- Deposit exactly what arrived, not the purse. The receiver is idling in a
    -- tavern buying its own meals and drinks, and a purchase it can't afford
    -- makes it leave the game -- so banking its own money ends the idle.
    it("walks to the vaults, deposits what was handed over, and returns", function()
        helper.simulateAlias("start-banking")
        helper.simulateLine(RECEIVED)
        walkToEnd()
        assert.are.same({ "sw", "n", "d", "deposit 842", "u", "s", "ne" },
                        helper.runCommandCalls)
    end)

    it("deposits the amount from each handover, not a fixed one", function()
        helper.simulateAlias("start-banking")
        helper.simulateLine("Garbageman just gave you 817 gold coins.")
        walkToEnd()
        helper.simulateLine("Garbageman just gave you 1000 gold coins.")
        walkToEnd()
        assert.are.same({ "sw", "n", "d", "deposit 817", "u", "s", "ne",
                          "sw", "n", "d", "deposit 1000", "u", "s", "ne" },
                        helper.runCommandCalls)
    end)

    -- A second handover mid-trip must not restart the walk from step 1, which
    -- would then be walked from the wrong room.
    it("ignores a second handover while already out", function()
        helper.simulateAlias("start-banking")
        helper.simulateLine(RECEIVED)
        helper.fireTimers(taPackage.arenaStepDelayMs)
        local before = #helper.runCommandCalls
        helper.simulateLine("Garbageman just gave you 200 gold coins.")
        assert.are.equal(before, #helper.runCommandCalls)
    end)

    it("stop-banking and stop-all-scripts both halt it", function()
        helper.simulateAlias("start-banking")
        helper.simulateAlias("stop-banking")
        assert.is_false(taPackage.bankingRunning())
        helper.simulateAlias("start-banking")
        helper.simulateAlias("stop-all-scripts")
        assert.is_false(taPackage.bankingRunning())
    end)

end)

describe("re-roll-half-ogre-hunter", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    local function lastEcho()
        return helper.echoCalls[#helper.echoCalls]
    end

    describe("alias", function()

        it("sets reRolling to true", function()
            helper.simulateAlias("re-roll-half-ogre-hunter")
            assert.is_true(taPackage.reRolling)
        end)

        it("sends 'status'", function()
            helper.simulateAlias("re-roll-half-ogre-hunter")
            assert.are.equal("status", helper.sendCalls[1])
        end)

    end)

    describe("matching", function()

        before_each(function()
            helper.simulateAlias("re-roll-half-ogre-hunter")
        end)

        it("accepts a roll with Phy >= 28, Sta >= 29 and Agi >= 15", function()
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      29")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     29 / 29")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("sends an ntfy push when a match is accepted", function()
            assert.are.equal(0, #helper.httpRequestCalls)
            helper.simulateLine("Physique:     28")
            helper.simulateLine("Stamina:      29")
            helper.simulateLine("Agility:      15")
            helper.simulateLine("Vitality:     29 / 29")
            assert.are.equal(1, #helper.httpRequestCalls)
            local call = helper.httpRequestCalls[1]
            assert.are.equal("Re-roll complete", call.options.headers["X-Title"])
            assert.is_truthy(string.find(call.options.body, "Found a match"))
        end)

        it("does not send an ntfy push while still re-rolling", function()
            helper.simulateLine("Physique:     27")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("ignores Int, Kno and Cha", function()
            helper.simulateLine("Intellect:    1")
            helper.simulateLine("Knowledge:    1")
            helper.simulateLine("Charisma:     1")
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "Done after"))
        end)

        it("re-rolls when Physique is below 28", function()
            helper.simulateLine("Physique:     27")
            helper.simulateLine("Stamina:      30")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     30 / 30")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Stamina is below 29", function()
            helper.simulateLine("Physique:     29")
            helper.simulateLine("Stamina:      28")
            helper.simulateLine("Agility:      17")
            helper.simulateLine("Vitality:     28 / 28")
            assert.is_truthy(string.find(lastEcho(), "re%-rolling"))
        end)

        it("re-rolls when Agility is below 15", function()
            helper.simulateLine("Physique:     29")
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
        -- Real sessions always run through beginArenaSession("1"), which sets
        -- the profile; the training gate now keys on it (ARENA_HAS_TRAINING), so
        -- default it here for tests that drive combat without the alias.
        taPackage.arenaProfile = "1"
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

    -- One alias now covers all three arenas: the arena is an argument, given as
    -- its number, with an optional "quiet". "rg" is the short form.
    describe("arena selector argument", function()

        it("defaults to arena 1 when no arena is given", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("1", taPackage.arenaProfile)
        end)

        it("accepts arena digits", function()
            for _, digit in ipairs({ "1", "2", "3" }) do
                helper.simulateAlias("ring-gong-and-fight-in-arena " .. digit)
                assert.are.equal(digit, taPackage.arenaProfile)
            end
        end)

        -- The spelled-out names are gone: one name per arena, everywhere.
        it("refuses the spelled-out arena names", function()
            for _, word in ipairs({ "first", "second", "third" }) do
                helper.simulateAlias("ring-gong-and-fight-in-arena " .. word)
                assert.is_nil(taPackage.arenaState)
            end
        end)

        it("leaves debug on by default", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 2")
            assert.is_true(taPackage.arenaDebug)
        end)

        it("turns debug off with quiet", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 2 quiet")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
        end)

        it("accepts bare quiet (first arena)", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena quiet")
            assert.are.equal("1", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
        end)

        -- The old flag stays valid so typing it out of habit isn't an error.
        it("still accepts an explicit debug", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 2 debug")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaDebug)
        end)

        it("refuses to start on an unknown argument", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena fourth")
            assert.is_nil(taPackage.arenaState)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "fourth", 1, true) and string.find(msg, "usage", 1, true) then
                    warned = true
                end
            end
            assert.is_true(warned)
        end)

        it("starts the named arena from the short 'rg' alias", function()
            helper.simulateAlias("rg 2")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.are.equal("ringing", taPackage.arenaState)
        end)

        it("gets debug on the short alias too, without asking", function()
            helper.simulateAlias("rg 3")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaDebug)
        end)

        it("takes quiet on the short alias too", function()
            helper.simulateAlias("rg 3 quiet")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
        end)

        it("defaults the short alias to the first arena", function()
            helper.simulateAlias("rg")
            assert.are.equal("1", taPackage.arenaProfile)
        end)

    end)

    -- team-fight-in-arena starts the very same session as the solo aliases, with
    -- one extra flag. These cover the flag and the shared argument parsing; the
    -- cooperative behaviour itself is exercised under "team arena fighting".
    describe("team-fight-in-arena alias", function()

        it("starts a team session in the first arena by default", function()
            helper.simulateAlias("team-fight-in-arena")
            assert.are.equal("1", taPackage.arenaProfile)
            assert.are.equal("ringing", taPackage.arenaState)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("takes the same arena selector as the solo aliases", function()
            helper.simulateAlias("team-fight-in-arena 3")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("runs with debug on without being asked", function()
            helper.simulateAlias("team-fight-in-arena 3")
            assert.is_true(taPackage.arenaDebug)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("takes quiet alongside the arena", function()
            helper.simulateAlias("team-fight-in-arena 2 quiet")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
            assert.is_true(taPackage.arenaTeam)
        end)

        -- "tfia" is to team-fight-in-arena what "rg" is to the solo alias.
        it("starts the named arena from the short 'tfia' alias", function()
            helper.simulateAlias("tfia 2")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.are.equal("ringing", taPackage.arenaState)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("takes the same flags on the short alias", function()
            helper.simulateAlias("tfia 3 quiet")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("defaults the short alias to arena 1", function()
            helper.simulateAlias("tfia")
            assert.are.equal("1", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaTeam)
        end)

        it("refuses to start on an unknown argument", function()
            helper.simulateAlias("team-fight-in-arena fourth")
            assert.is_nil(taPackage.arenaState)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "team-fight-in-arena", 1, true)
                    and string.find(msg, "fourth", 1, true) then
                    warned = true
                end
            end
            assert.is_true(warned)
        end)

        -- The solo aliases must stay solo: a stray team flag would make them
        -- wait on a roster that nobody else is part of.
        it("leaves the solo aliases in solo mode", function()
            helper.simulateAlias("rg 2")
            assert.is_false(taPackage.arenaTeam)
        end)

        -- `exit-if-solo` is the flag that lets a character too weak to fight
        -- the arena alone bail out when its team disappears.
        it("arms exit-if-solo when asked", function()
            helper.simulateAlias("tfia 3 exit-if-solo")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaTeam)
            assert.is_true(taPackage.arenaExitIfSolo)
        end)

        it("leaves exit-if-solo off by default", function()
            helper.simulateAlias("tfia 3")
            assert.is_false(taPackage.arenaExitIfSolo)
        end)

        -- Word order is not significant for any of the other flags and must not
        -- become significant for this one.
        it("takes exit-if-solo alongside the other flags in any order", function()
            helper.simulateAlias("team-fight-in-arena exit-if-solo quiet 2")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
            assert.is_true(taPackage.arenaExitIfSolo)
        end)

        -- A solo run is alone by definition, so honouring the flag there would
        -- exit one threshold after starting. Say so rather than accepting the
        -- word and silently doing nothing, which looks like it worked.
        it("refuses exit-if-solo on the solo aliases, and says so", function()
            helper.simulateAlias("rg 2 exit-if-solo")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaTeam)
            assert.is_false(taPackage.arenaExitIfSolo)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "exit-if-solo", 1, true)
                    and string.find(msg, "team mode", 1, true) then
                    warned = true
                end
            end
            assert.is_true(warned)
        end)

        -- The threshold cannot ride along as a bare number -- a digit is the
        -- arena selector -- so it must still be rejected rather than quietly
        -- restarting the run in a different arena.
        it("still rejects an unknown word after exit-if-solo", function()
            helper.simulateAlias("tfia 3 exit-if-solo 5m")
            assert.is_nil(taPackage.arenaState)
        end)

        -- `support-only` is the flag for the team shape where two characters
        -- stand in the arena purely as extra bodies for the monster to split its
        -- attacks across, so all the XP goes to the third.
        it("arms support-only when asked", function()
            helper.simulateAlias("tfia 3 support-only")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_true(taPackage.arenaTeam)
            assert.is_true(taPackage.arenaSupportOnly)
        end)

        it("leaves support-only off by default", function()
            helper.simulateAlias("tfia 3")
            assert.is_false(taPackage.arenaSupportOnly)
        end)

        it("takes support-only alongside the other flags in any order", function()
            helper.simulateAlias("team-fight-in-arena support-only quiet exit-if-solo 3")
            assert.are.equal("3", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaDebug)
            assert.is_true(taPackage.arenaExitIfSolo)
            assert.is_true(taPackage.arenaSupportOnly)
        end)

        -- There is nobody to support alone, so accepting the word would leave a
        -- character standing in the arena that never swings at anything. Say so,
        -- exactly as exit-if-solo does.
        it("refuses support-only on the solo aliases, and says so", function()
            helper.simulateAlias("rg 2 support-only")
            assert.are.equal("2", taPackage.arenaProfile)
            assert.is_false(taPackage.arenaTeam)
            assert.is_false(taPackage.arenaSupportOnly)
            local warned = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "support-only", 1, true)
                    and string.find(msg, "team mode", 1, true) then
                    warned = true
                end
            end
            assert.is_true(warned)
        end)

        -- Reconnecting mid-flee. The BBS drops a character while it is running
        -- for the temple; TA_INIT_CMD="tfia 3" brings it back in and starts a
        -- session on the spot. The entry `st` has already landed by then, so
        -- the HP is known -- but the session used to scan the room, find
        -- whatever monster is still standing there, and swing at it. That swing
        -- is what puts us in the heat of battle, so the flee that fires one
        -- combat line later cannot leave the room. In the third arena that is a
        -- 400-damage round spent for nothing.
        it("walks out instead of engaging when the session starts hurt", function()
            setHP(273, 440)
            helper.simulateAlias("tfia 3")
            assert.are.equal("fleeing", taPackage.arenaState)
        end)

        it("does not probe the room when the session starts hurt", function()
            setHP(273, 440)
            helper.simulateAlias("tfia 3")
            for _, sent in ipairs(helper.sendCalls) do
                assert.are_not.equal("", sent)
            end
        end)

        it("says why it is leaving when the session starts hurt", function()
            setHP(273, 440)
            helper.simulateAlias("tfia 3")
            local said = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "Starting hurt", 1, true) then said = true end
            end
            assert.is_true(said)
        end)

        -- The gate must not fire on a healthy character: the ordinary start is
        -- a scan of the room, and turning that into a temple trip would make
        -- every session begin by walking away from the arena.
        it("scans the room as usual when the session starts healthy", function()
            setHP(440, 440)
            helper.simulateAlias("tfia 3")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.is_true(taPackage.arenaProbePending)
        end)

        -- Vitality unknown is not evidence of being hurt (arenaHeal.isLow says
        -- so), and a fresh character that has never read a status must not be
        -- sent to the temple before its first fight.
        it("scans the room as usual when vitality is unknown", function()
            helper.simulateAlias("tfia 3")
            assert.are.equal("ringing", taPackage.arenaState)
        end)

    end)

    describe("stop alias", function()

        it("clears arenaState", function()
            taPackage.arenaState = "fighting"
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaState)
        end)

        it("clears arenaMonster", function()
            taPackage.arenaMonster = "lizard man"
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaMonster)
        end)

        it("clears arenaLastCmd", function()
            taPackage.arenaLastCmd = "a lizard"
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaLastCmd)
        end)

        it("clears session tracking state", function()
            taPackage.arenaSessionStartXp = 500
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaSessionStartXp)
            assert.is_nil(taPackage.arenaSessionStartTime)
        end)

        it("bumps arenaXpTimerGen to cancel pending timer", function()
            taPackage.arenaXpTimerGen = 2
            helper.simulateAlias("stop-arena-fight")
            assert.are.equal(3, taPackage.arenaXpTimerGen)
        end)

        it("echoes session summary with XP gained and elapsed minutes", function()
            taPackage.arenaSessionStartXp = 400
            taPackage.arenaSessionStartTime = os.time() - 600  -- 10 minutes ago
            taPackage.character = { experience = 1400 }
            helper.simulateAlias("stop-arena-fight")
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
            helper.simulateAlias("stop-arena-fight")
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

        -- XP is only knowable from a status block -- a kill prints the gold it
        -- dropped and nothing about experience -- so a level earned between two
        -- polls is invisible until the next one. On a flat five-minute cadence
        -- that is up to five minutes spent fighting for XP that buys nothing,
        -- roughly a tenth of a 21-minute cycle. So the poll tightens as the
        -- threshold approaches. A Warrior needs 1125 for level 2.
        describe("tightens as the level approaches", function()

            local intervals

            before_each(function()
                intervals = {}
                _G.createTimer = function(interval, cb, opts)
                    table.insert(intervals, interval)
                    return "mock_timer"
                end
            end)

            local function delayAfterXp(xp)
                setClass("Warrior")
                setLevel(1)
                setExperience(xp)
                intervals = {}
                helper.simulateAlias("ring-gong-and-fight-in-arena")
                for _, i in ipairs(intervals) do
                    -- the scan pump also arms a short timer; the XP check is the
                    -- only one armed at one of these three cadences
                    if i == 300000 or i == 60000 or i == 30000 then return i end
                end
                return nil
            end

            it("stays at 5 minutes while far away", function()
                assert.are.equal(300000, delayAfterXp(0))
            end)

            -- Inside one kill's worth: a cave bear went for 520 XP in
            -- logs/session-garbageman-2026-08-15T19-45-33.log, so the very next
            -- kill can finish the job.
            it("drops to a minute within 600 of the threshold", function()
                assert.are.equal(60000, delayAfterXp(600))   -- 525 remaining
            end)

            it("drops to 30s within 200 of the threshold", function()
                assert.are.equal(30000, delayAfterXp(1000))  -- 125 remaining
            end)

            it("falls back to 5 minutes when XP is not known yet", function()
                intervals = {}
                helper.simulateAlias("ring-gong-and-fight-in-arena")
                local found
                for _, i in ipairs(intervals) do
                    if i == 300000 or i == 60000 or i == 30000 then found = i end
                end
                assert.are.equal(300000, found)
            end)

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
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Tojolias"
            taPackage.character.class = "Warrior"
            taPackage.character.level = 12
            taPackage.character.vitalityCurrent = 313
            taPackage.character.encumberanceCurrent = 750
            taPackage.character.encumberanceMax = 1000
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
                    .. "- Lvl: 12\n"
                    .. "- HP: 313\n"
                    .. "- Encumberance: 75%\n"
                    .. "- Gold: 2,900",
                call.options.body)
        end)

        it("marks an earned-but-untrained level with a caret on the Lvl line", function()
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Tojolias"
            taPackage.character.class = "Warrior"
            -- Still reported as level 11 by the game, but 620,046 XP is past the
            -- 588,700 a Warrior needs for level 12: earned, not yet trained.
            taPackage.character.level = 11
            taPackage.character.vitalityCurrent = 313
            taPackage.character.encumberanceCurrent = 750
            taPackage.character.encumberanceMax = 1000
            taPackage.character.gold = 2900
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620046")
            assert.are.equal(1, #helper.httpRequestCalls)
            assert.are.equal(
                "[Tojolias]\n"
                    .. "- XP Until Level Up: 195,554\n"
                    .. "- Lvl: 11^\n"
                    .. "- HP: 313\n"
                    .. "- Encumberance: 75%\n"
                    .. "- Gold: 2,900",
                helper.httpRequestCalls[1].options.body)
        end)

        it("first-arena XP check fires an ntfy notification with a first-arena title", function()
            taPackage.arenaProfile = "1"
            taPackage.character.name = "Tojolias"
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   800")
            assert.are.equal(1, #helper.httpRequestCalls)
            local call = helper.httpRequestCalls[1]
            assert.are.equal("https://ntfy.sh/s5bbs-tele-arena-j5", call.url)
            assert.are.equal("Arena Check-In", call.options.headers["X-Title"])
            assert.are.equal("true", call.options.headers["X-Markdown"])
        end)

        -- A farming character is levelled and thrown away by design, so a
        -- check-in on its XP and gold every half hour is a push nobody is
        -- waiting for. The handover to the banker still is.
        it("stays silent during a gold-farming run", function()
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Garbageman"
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateAlias("start-gold-farming")
            local before = #helper.httpRequestCalls
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620046")
            assert.are.equal(before, #helper.httpRequestCalls)
        end)

        -- The on-screen echo is not a push and stays: the run has to be
        -- readable by whoever is looking at the session.
        it("still echoes arena progress during a gold-farming run", function()
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Garbageman"
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateAlias("start-gold-farming")
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   800")
            local found = false
            for _, msg in ipairs(helper.echoCalls) do
                if string.find(msg, "+500", 1, true) then found = true end
            end
            assert.is_true(found)
        end)

        -- Nothing about the silence is sticky: the next check-in after the
        -- round ends pings as usual.
        it("resumes check-ins once farming stops", function()
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Garbageman"
            taPackage.character.class = "Warrior"
            taPackage.character.level = 12
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()
            helper.simulateAlias("start-gold-farming")
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620046")
            helper.simulateAlias("stop-gold-farming")
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620100")
            -- The one push that got through is the second check, not a
            -- suppressed first one arriving late: 815,600 - 620,100 = 195,500.
            assert.are.equal(1, #helper.httpRequestCalls)
            assert.is_truthy(helper.httpRequestCalls[1].options.body:find(
                "XP Until Level Up: 195,500", 1, true))
        end)

        it("ntfy notification only fires on the periodic XP check", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaXpCheckPending = false
            helper.simulateLine("Experience:   800")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        it("ntfy notification is throttled to every 45 minutes", function()
            taPackage.arenaProfile = "2"
            taPackage.character.name = "Tojolias"
            taPackage.character.vitalityCurrent = 313
            taPackage.arenaSessionStartXp = 300
            taPackage.arenaSessionStartTime = os.time()

            -- First periodic check (5 min in) pings.
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620046")
            assert.are.equal(1, #helper.httpRequestCalls)

            -- Next check (10 min in) is within the 45-min window: no ping.
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620100")
            assert.are.equal(1, #helper.httpRequestCalls)

            -- 30 min used to be the window, and no longer is: still silent.
            taPackage.arenaLastNtfyTime = os.time() - 1800
            taPackage.arenaXpCheckPending = true
            helper.simulateLine("Experience:   620150")
            assert.are.equal(1, #helper.httpRequestCalls)

            -- Once 45 min has elapsed since the last ping, it fires again.
            taPackage.arenaLastNtfyTime = os.time() - 2700
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

        -- The look has to name the monster the same single-word way the attack
        -- does. "look huge rat" is not a command the game recognises at all — it
        -- gets broadcast to the room as speech instead ("From Kerhak: look huge
        -- rat"), which in team mode spams every character in the arena.
        it("looks at monster before attacking when description is unknown", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = nil
            helper.simulateLine("A huge rat enters the arena through the dungeon gate!")
            assert.are.equal("look huge", helper.sendCalls[1])
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
            assert.are.equal("look huge", helper.sendCalls[1])
            assert.are.equal("a huge", helper.sendCalls[2])
        end)

        -- A one-word monster needs no truncation; this is the case that already
        -- worked, and must keep working.
        it("looks at a single-word monster by its whole name", function()
            taPackage.arenaState = "ringing"
            helper.mockDbOneRow = nil
            helper.simulateLine("A hobgoblin enters the arena through the dungeon gate!")
            assert.are.equal("look hobgoblin", helper.sendCalls[1])
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

        -- The gong recovers against the last accepted SWING, and never answers
        -- inside the first 18s of one. See ARENA_RING_FLOOR_MS.
        describe("the ring floor", function()

            local function probe()
                taPackage.arenaProbePending = true
                helper.simulateLine("There is nothing on the floor.")
            end

            it("holds the ring while the swing clock is inside the floor", function()
                taPackage.arenaState = "ringing"
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(17999)
                probe()
                assert.are.equal(0, #helper.sendCalls)
            end)

            it("rings once the floor has passed", function()
                taPackage.arenaState = "ringing"
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(18000)
                probe()
                assert.are.equal("ring gong", helper.sendCalls[1])
            end)

            it("rings immediately when no swing has landed to hold against", function()
                -- First summon of a session: nothing has spent the clock yet.
                taPackage.arenaState = "ringing"
                taPackage.arenaLastSwingAt = nil
                probe()
                assert.are.equal("ring gong", helper.sendCalls[1])
            end)

            it("leaves a held tick able to ring on the next pump pass", function()
                -- The held tick must not claim arenaRingPending, or the summon
                -- loop would wedge behind a ring that was never sent.
                taPackage.arenaState = "ringing"
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(3000)
                probe()
                assert.are.equal(0, #helper.sendCalls)
                assert.is_falsy(taPackage.arenaRingPending)
                helper.advanceMs(15000)
                probe()
                assert.are.equal("ring gong", helper.sendCalls[1])
            end)

            it("does not hold a ring after a long errand away from the arena", function()
                taPackage.arenaState = "ringing"
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(600000)
                probe()
                assert.are.equal("ring gong", helper.sendCalls[1])
            end)

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

        -- For a low-HP character the absolute floor kicks in where the 75% rule
        -- would not: 75% of 31 is 23, and the floor raises the threshold above
        -- that. This is the Johnsonite case (31 max HP).
        --
        -- The floor is 20, lowered from 25 to cut the gold-farming loop's temple
        -- trips (a 34 HP character fled after 9 damage, 8 round trips in one
        -- ~28-minute cycle). That trade is deliberate and it is a real one: 25
        -- was chosen so a cave bear's worst observed round (23) could not kill
        -- from above the threshold, and 20 no longer guarantees that. Asserted
        -- against arenaHeal.FLOOR rather than a literal so the intent — "the
        -- absolute floor overrides the percentage for low-HP characters" —
        -- survives the number being retuned again.
        it("uses the absolute floor for a low-HP character", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            -- one below the floor, and above 75% of 31 (23), so only the floor
            -- can be what triggers the flee
            setHP(taPackage.arenaHeal.FLOOR - 1, 31)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        -- Which of the two rules binds depends on max HP, and it is easy to get
        -- backwards. At 34 max the percentage gives 25 and the floor 20, so the
        -- percentage wins and lowering the FLOOR alone changes nothing at all
        -- for such a character. The floor only takes over once maxHp * FRACTION
        -- falls beneath it. These two pin the 34 HP case, which is what a fresh
        -- half-ogre warrior in the gold-farming loop actually has.
        it("uses the percentage when it is higher than the floor", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(24, 34)  -- below the percentage threshold of 25, above the floor
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
        end)

        it("stays in the fight just above the binding threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(26, 34)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
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
            assert.is_not_nil(taPackage.arenaJourney)   -- walking, not phase-hopping
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

        -- The training hall refuses anyone under a stat potion. Rather than wait
        -- the 22-minute taint out, walk to the temple and have it dispelled --
        -- toTemple for the first arena is { "w", "w" }.
        it("goes to the temple to buy restoring while stat potions are active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 2
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("restoring", taPackage.arenaState)
            assert.are.equal("temple", taPackage.arenaJourney.arriveRoom)
            assert.are.equal("w", helper.sendCalls[1])
        end)

        -- Arriving at the temple spends the 25 crowns and walks straight home;
        -- the confirmation line is what actually clears the taint, so the count is
        -- deliberately NOT zeroed here.
        it("buys restoring on arrival at the temple, then walks home", function()
            taPackage.arenaState = "restoring"
            taPackage.arenaPotionsActive = 2
            taPackage.arenaJourney = { steps = { "w", "w" }, index = 2, arriveRoom = "temple" }
            helper.simulateLine("You're in the temple.")
            assert.are.equal("buy restoring", helper.sendCalls[1])
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("arena", taPackage.arenaJourney.arriveRoom)
            assert.are.equal(2, taPackage.arenaPotionsActive)
        end)

        -- The confirmation clears the taint outright. Restoring does not care how
        -- many potions were up, so this zeroes rather than decrements.
        it("zeroes the potion count on the restoring confirmation", function()
            taPackage.arenaState = "returning"
            -- Enough to pay for it: the same line is also charged against our
            -- gold, and dropping under ARENA_MIN_GOLD emergency-exits the session
            -- (which would nil the count rather than zero it).
            setGold(800)
            taPackage.arenaPotionsActive = 2
            helper.simulateLine("The priests restore your body and mind to it's former state for 25 crowns.")
            assert.are.equal(0, taPackage.arenaPotionsActive)
        end)

        -- If the buy never lands (an empty purse) the count stays up, so without a
        -- one-shot guard we would walk to the temple, fail, come home and set out
        -- again forever. One attempt, then fall back to fighting the taint off.
        it("does not return to the temple after a restore that did not land", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            taPackage.character.experience = 1120
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 2
            taPackage.arenaRestoreTried = true  -- already spent our one attempt
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.is_nil(taPackage.arenaJourney)
            assert.are.equal("", helper.sendCalls[1])  -- scanned, did not walk anywhere
        end)

        it("trains once the stat potions have drained to zero", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 0
            helper.simulateLine("The lizard man falls to the ground lifeless!")
            assert.are.equal("training", taPackage.arenaState)
            assert.is_not_nil(taPackage.arenaJourney)   -- walking, not phase-hopping
            assert.are.equal("w", helper.sendCalls[1])
        end)

        -- Regression: a thirst/hunger tick between our swing and its resolution
        -- flips state to "tavern" while arenaMonster is still set; the swing then
        -- lands the kill. The death must still clear arenaMonster even though we
        -- are no longer "fighting", or the errand's return path resumes swinging
        -- at a corpse forever (something-went-wrong-focused.log).
        it("clears arenaMonster when the kill lands after an errand departed", function()
            taPackage.arenaState = "tavern"
            taPackage.arenaMonster = "troll"
            setHP(80, 100)
            helper.simulateLine("The troll falls to the ground lifeless!")
            assert.is_nil(taPackage.arenaMonster)
            -- Still walking to the bar: no ring/scan should fire mid-errand.
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("rings for a fresh monster on arriving home after a mid-errand kill", function()
            -- The troll died during the bar trip, so arenaMonster is already nil.
            -- Arriving back in the arena must ring, not attack the dead troll.
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = nil
            taPackage.arenaJourney = { steps = { "n" }, index = 6, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("ringing", taPackage.arenaState)
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[#helper.sendCalls])
        end)

    end)

    describe("lost target (attack whiffs on a monster that is gone)", function()

        -- Belt-and-suspenders for any stale arenaMonster: the game answers a
        -- swing at an absent monster with "Sorry, you don't see "X" nearby." and
        -- nothing else re-drives the loop, so without this the run wedges
        -- re-attacking a ghost and never rings (something-went-wrong-focused.log).
        it("clears the monster and scans to ring when the target is gone", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "troll"
            helper.simulateLine("Sorry, you don't see \"troll\" nearby.")
            assert.is_nil(taPackage.arenaMonster)
            assert.are.equal("ringing", taPackage.arenaState)
            helper.simulateLine("There is nobody here.")
            assert.are.equal("ring gong", helper.sendCalls[#helper.sendCalls])
        end)

        it("ignores the line when not fighting (e.g. mid-errand)", function()
            taPackage.arenaState = "tavern"
            helper.simulateLine("Sorry, you don't see \"troll\" nearby.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    -- The trip is a paced journey now, arena -> north plaza -> guild hall and
    -- back, the same machinery the other two arenas use. It used to react to
    -- each room name and send the next move at once, which paced it at the
    -- round-trip latency and left a trip with nothing to recover it.
    describe("auto-training", function()

        local stepTimer
        -- The level-up push's fallback timeout, so the "no sheet came back" case
        -- can fire exactly that timer (this block drops every other one).
        local levelUpTimer

        before_each(function()
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                if interval == 5000 then levelUpTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            levelUpTimer = nil
            -- Depart the way the game does: a kill that crosses the level
            -- threshold sends us to train.
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "lizard man"
            setHP(80, 100)
            taPackage.character.experience = 1120   -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            helper.simulateLine("The lizard man falls to the ground lifeless!")
        end)

        it("sets off west, then paces north to the guild hall", function()
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
            helper.simulateLine("You're in the north plaza.")
            assert.is_not_nil(stepTimer)          -- paced, not immediate
            stepTimer.cb()
            assert.are.equal("n", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys training and walks home on arrival at the guild hall", function()
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the guild hall.")
            local boughtTraining = false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "buy training" then boughtTraining = true end
            end
            assert.is_true(boughtTraining)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("switches to returning state after buying training", function()
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the guild hall.")
            assert.are.equal("returning", taPackage.arenaState)
        end)

        -- On the guild-hall success line we bank the level locally (the game's own
        -- Level line lags until the next status poll, and a stale level would
        -- re-trigger a training trip on the next kill), charge the fee
        -- (next level x 5 gold), and flag a potion restock for the way home.
        it("banks the level, charges the fee, and re-buys potions on a successful train", function()
            taPackage.arenaState = "returning"
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.gold = 500
            taPackage.arenaPotionsActive = 0
            helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
            assert.are.equal(2, taPackage.character.level)   -- banked locally
            assert.are.equal(490, taPackage.character.gold)  -- 500 - (2 x 5)
            assert.is_true(taPackage.needsPotions)           -- restock on the way home
        end)

        it("records the training fee as a service", function()
            helper.clearDbCalls()
            taPackage.arenaState = "returning"
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.character.experience = 1120
            taPackage.character.gold = 500
            helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
            local recorded = false
            for _, c in ipairs(helper.dbCalls) do
                if c.sql and c.sql:find("services") and c.params and c.params[1] == "training" then
                    recorded = true
                end
            end
            assert.is_true(recorded)
        end)

        it("ignores the training-success line outside an arena session", function()
            taPackage.arenaState = nil
            taPackage.character.level = 1
            taPackage.character.gold = 500
            helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
            assert.are.equal(1, taPackage.character.level)  -- untouched
            assert.are.equal(500, taPackage.character.gold)
        end)

        -- The push is held until the character sheet we ask for comes back with
        -- the new maxima, so the notification can say what the level was worth.
        local function trainForNtfy()
            taPackage.arenaState = "returning"
            taPackage.character.name = "Tojolias"
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.character.experience = 1120
            taPackage.character.gold = 500
            taPackage.character.vitalityMax = 411
            taPackage.character.manaMax = 17
            helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
        end

        it("pushes a level-up ntfy once the fresh sheet lands", function()
            trainForNtfy()
            -- Nothing pushed yet: we asked for a sheet and are waiting on it.
            assert.are.equal(0, #helper.httpRequestCalls)
            local askedForSheet = false
            for _, s in ipairs(helper.sendCalls) do
                if s == "st" then askedForSheet = true end
            end
            assert.is_true(askedForSheet)

            helper.simulateLine("Mana:         18 / 18")
            helper.simulateLine("Vitality:     434 / 434")

            assert.are.equal(1, #helper.httpRequestCalls)
            local call = helper.httpRequestCalls[1]
            assert.are.equal("https://ntfy.sh/s5bbs-tele-arena-j5", call.url)
            assert.are.equal("Leveled Up!", call.options.headers["X-Title"])
            local body = call.options.body
            assert.is_truthy(body:find("trained to level 2", 1, true))
            assert.is_truthy(body:find("- New HP: 434, gain of 23 HP", 1, true))
            assert.is_truthy(body:find("- New MP: 18, gain of 1 MP", 1, true))
            -- Stat gains read above the bookkeeping, as in the example wording.
            assert.is_true(body:find("New HP", 1, true) < body:find("Training cost", 1, true))
        end)

        -- Same silence as the threshold crossing: a farming round trains
        -- repeatedly and nobody is waiting to hear about any of it.
        it("pushes nothing for a level trained during a gold-farming run", function()
            helper.simulateAlias("start-gold-farming")
            local before = #helper.httpRequestCalls
            trainForNtfy()
            helper.simulateLine("Mana:         18 / 18")
            helper.simulateLine("Vitality:     434 / 434")
            assert.are.equal(before, #helper.httpRequestCalls)
        end)

        -- Held at the push, not at the point it is armed, so the fresh sheet is
        -- still asked for and the tracked maxima follow the level up.
        it("still refreshes the sheet for a level trained while farming", function()
            helper.simulateAlias("start-gold-farming")
            trainForNtfy()
            local askedForSheet = false
            for _, s in ipairs(helper.sendCalls) do
                if s == "st" then askedForSheet = true end
            end
            assert.is_true(askedForSheet)
            helper.simulateLine("Vitality:     434 / 434")
            assert.are.equal(434, taPackage.character.vitalityMax)
        end)

        -- A warrior's sheet says "0 / 0" every level; the line would be noise.
        it("omits the MP line for a character with no mana pool", function()
            taPackage.character.manaMax = 0
            trainForNtfy()
            taPackage.character.manaMax = 0
            helper.simulateLine("Vitality:     434 / 434")
            local body = helper.httpRequestCalls[1].options.body
            assert.is_truthy(body:find("- New HP: 434", 1, true))
            assert.is_nil(body:find("New MP", 1, true))
        end)

        -- An `st` already in flight when we trained reports the pre-level maximum.
        -- Flushing on it would claim a gain of 0, so wait for the real one.
        it("ignores a stale sheet whose maximum has not moved", function()
            trainForNtfy()
            helper.simulateLine("Vitality:     380 / 411")
            assert.are.equal(0, #helper.httpRequestCalls)

            helper.simulateLine("Vitality:     434 / 434")
            assert.are.equal(1, #helper.httpRequestCalls)
            assert.is_truthy(helper.httpRequestCalls[1].options.body:find("gain of 23 HP", 1, true))
        end)

        -- No sheet came back. Better a notification without the stat lines than
        -- no notification at all.
        it("pushes without the stat lines when no sheet comes back", function()
            trainForNtfy()
            levelUpTimer.cb()
            assert.are.equal(1, #helper.httpRequestCalls)
            local body = helper.httpRequestCalls[1].options.body
            assert.is_truthy(body:find("trained to level 2", 1, true))
            -- The stale maxima are still what we hold, so both gains read as 0.
            assert.is_truthy(body:find("- New HP: 411, gain of 0 HP", 1, true))
            assert.is_truthy(body:find("- Training cost: 10 gold", 1, true))
        end)

        -- Whichever of the sheet and the timeout arrives second must find nothing
        -- left to send.
        it("pushes only once when the timeout fires after the sheet", function()
            trainForNtfy()
            helper.simulateLine("Vitality:     434 / 434")
            levelUpTimer.cb()
            assert.are.equal(1, #helper.httpRequestCalls)
        end)

        -- Nothing is pending, so an ordinary status poll must not push anything.
        it("does not push on a Vitality line outside a level-up", function()
            helper.simulateLine("Vitality:     434 / 434")
            assert.are.equal(0, #helper.httpRequestCalls)
        end)

        -- Backstop: if we reach the hall while still potion-tainted, it refuses us
        -- ("...whole and untainted..."). The success line never fires, so we were
        -- neither leveled nor charged; just force the drain count positive so we
        -- keep fighting until the potion wears off and then retry.
        it("recovers when training is refused for being potion-tainted", function()
            taPackage.arenaState = "returning"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 0
            helper.simulateLine("Your mind and body must be whole and untainted before you may train.")
            assert.are.equal(1, taPackage.character.level)     -- unchanged (never leveled)
            assert.are.equal(1, taPackage.arenaPotionsActive)  -- forced positive: keep draining
        end)

        it("ignores the training-refused line outside an arena session", function()
            taPackage.arenaState = nil
            taPackage.character.level = 2
            helper.simulateLine("Your mind and body must be whole and untainted before you may train.")
            assert.are.equal(2, taPackage.character.level)  -- untouched
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

        -- Special-verb damage lines ("breathed flames", boulder, bite, charge, …)
        -- only match the incoming-damage handler that subtracts HP; unlike the
        -- generic "attacked you" phrasing they have no counter-attack trigger, so
        -- before the fix nothing re-evaluated the flee decision when one landed. A
        -- chimera's flame breath could then drop HP well below the flee threshold
        -- and just sit there taking hits until our own next swing resolved — which,
        -- if that swing had bounced on exhaustion, was a full 30s away.
        it("flees on a special-verb hit (breathed flames) that crosses the threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "chimera"
            setHP(100, 100)
            -- First breath (TOOK 23) → 77, still above the 75-HP threshold.
            helper.simulateLine("The chimera breathed flames at you for 23 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
            -- Second breath (TOOK 42) → 35, below threshold → flee immediately,
            -- without waiting for one of our own swings to resolve.
            helper.simulateLine("The chimera breathed flames at you for 42 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("does not flee on a special-verb hit while HP stays above the threshold", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "chimera"
            setHP(90, 100)
            helper.simulateLine("The chimera breathed flames at you for 10 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        it("subtracts HP on a flame giant's blast of flame", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "flame giant"
            setHP(500, 500)
            helper.simulateLine("The flame giant exhaled a blast of flame at you for 388 damage!")
            local current = getVitality()
            assert.are.equal(112, current)
        end)

    end)

    describe("fleeing and healing", function()

        local stepTimer

        -- Flee for real: low HP on our own swing sends us walking to the temple.
        local function fleeing()
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
        end

        it("sets off west, then paces west again to the temple", function()
            fleeing()
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
            helper.simulateLine("You're in the north plaza.")
            assert.is_not_nil(stepTimer)          -- paced, not immediate
            stepTimer.cb()
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys healing on arrival at the temple", function()
            fleeing()
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the temple.")
            assert.are.equal("healing", taPackage.arenaState)
            assert.are.equal("buy healing", helper.sendCalls[#helper.sendCalls])
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

        it("starts walking home after healing", function()
            fleeing()
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the temple.")
            taPackage.character.gold = 500
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("e", helper.sendCalls[#helper.sendCalls])
        end)

        -- Walking home from the temple, with the arena's own arrival dispatch.
        local function returning(monster)
            fleeing()
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the temple.")
            taPackage.character.gold = 500
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            taPackage.arenaMonster = monster
        end

        it("paces east through north plaza on the way back", function()
            returning(nil)
            assert.are.equal("e", helper.sendCalls[#helper.sendCalls])
        end)

        it("scans the room when entering arena and no monster left", function()
            returning(nil)
            helper.simulateLine("You're in the arena.")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[#helper.sendCalls])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("resumes attacking when entering arena and monster still alive", function()
            returning("cave bear")
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a cave", helper.sendCalls[#helper.sendCalls])
        end)

        it("ignores room entries in other states", function()
            taPackage.arenaState = "ringing"
            helper.simulateLine("You're in the north plaza.")
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    -- Damage taken during an errand is invisible to checkFleeArena, which only
    -- looks at HP while arenaState == "fighting". So a character can finish a
    -- potion or food run and walk back into the arena already under the flee
    -- floor. Resuming combat there is close to fatal: the first swing puts us in
    -- the heat of battle, and the flee that fires a moment later can no longer
    -- leave the room. Arriving un-engaged is the last free exit, so take it.
    describe("walking back into the arena hurt", function()

        local function said(text)
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == text then return true end
            end
            return false
        end

        -- Land in the arena at the end of an errand leg, at the given health.
        local function arrivesHome(hp, max, monster)
            taPackage.arenaJourney = { steps = { "e" }, index = 2, arriveRoom = "arena" }
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = monster
            setHP(hp, max)
            helper.sendCalls = {}
            helper.simulateLine("You're in the arena.")
        end

        it("sets out for the temple instead of resuming the fight", function()
            arrivesHome(10, 100, "cave bear")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        -- The whole point: not one attack goes out. An attack is what locks the
        -- door behind us.
        it("does not swing on the way in", function()
            arrivesHome(10, 100, "cave bear")
            assert.is_false(said("a cave"))
        end)

        it("heals before an owed potion restock", function()
            taPackage.needsPotions = true
            arrivesHome(10, 100, nil)
            assert.are.equal("fleeing", taPackage.arenaState)
            -- Still owed — the shop run happens on the next arrival, healthy.
            assert.is_true(taPackage.needsPotions)
        end)

        it("heals before an owed food or drink run", function()
            taPackage.needsDrinks = true
            arrivesHome(10, 100, nil)
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.is_true(taPackage.needsDrinks)
        end)

        it("resumes the fight as usual when it comes home healthy", function()
            arrivesHome(100, 100, "cave bear")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a cave", helper.sendCalls[#helper.sendCalls])
        end)

        it("rings as usual when it comes home healthy to an empty arena", function()
            arrivesHome(100, 100, nil)
            assert.are.equal("ringing", taPackage.arenaState)
        end)

        -- An unread vitality is not evidence of being hurt. Before the first
        -- status line there is nothing to compare against, and treating that as
        -- low would walk a fresh character straight back out of the arena.
        it("does not turn around when vitality has never been read", function()
            taPackage.arenaJourney = { steps = { "e" }, index = 2, arriveRoom = "arena" }
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = "cave bear"
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- Reported back only once we are actually well: the hold is a request to
        -- stop summoning while we are one hit from death, which is still true.
        it("keeps the team's gong held rather than reporting back", function()
            taPackage.arenaTeam = true
            taPackage.arenaAnnouncedNeedsHealing = true
            arrivesHome(10, 100, "cave bear")
            assert.is_false(said("I am healed"))
        end)

        it("reports back once it comes home healthy", function()
            taPackage.arenaTeam = true
            taPackage.arenaAnnouncedNeedsHealing = true
            arrivesHome(100, 100, "cave bear")
            assert.is_true(said("I am healed"))
        end)

        -- The live case, from the 2026-08-09 third-arena team fight: a giantess
        -- breathed for 167 while we were walking to the magic shop, so we came
        -- back at 273/440 — and attacked. Under the max-vitality bands a 440 max
        -- character must be at full health to fight at all, so this is now the
        -- clearest possible turn-around.
        it("turns around at the third arena's much higher floor", function()
            taPackage.arenaProfile = "3"
            arrivesHome(273, 440, "flame giantess")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
            assert.is_false(said("a flame"))
        end)

        -- The other decision point taken standing in the arena. A clear room is
        -- the window in which leaving works; ringing spends it.
        it("heals instead of ringing at a clear-room ring gap", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            taPackage.arenaRingPending = false
            setHP(10, 100)
            helper.sendCalls = {}
            helper.simulateLine("There is nobody here.")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.is_false(said("ring gong"))
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("rings at a clear-room ring gap when healthy", function()
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            taPackage.arenaRingPending = false
            setHP(100, 100)
            helper.sendCalls = {}
            helper.simulateLine("There is nobody here.")
            assert.is_true(said("ring gong"))
        end)

    end)

    -- Team mode derives its ring order from the arena brief the probe already
    -- prints, so getting the roster out of that brief is the foundation for
    -- everything below it.
    describe("team roster from the room brief", function()

        before_each(function()
            taPackage.arenaTeam = true
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            -- arenaScanRoom empties the roster as it sends the probe, so the
            -- brief always lands on a clean slate.
            taPackage.arenaTeamRoster = {}
        end)

        it("reads a single other player", function()
            helper.simulateLine("Pelayo is here.")
            assert.are.same({ "Pelayo" }, taPackage.arenaTeamRoster)
        end)

        it("reads a two-player conjunction", function()
            helper.simulateLine("Tojolias and Teekywiki are here.")
            assert.are.same({ "Tojolias", "Teekywiki" }, taPackage.arenaTeamRoster)
        end)

        it("reads an Oxford-comma list without leaving an empty entry", function()
            helper.simulateLine("Pelayo, Tojolias, and Johnsonite are here.")
            assert.are.same({ "Pelayo", "Tojolias", "Johnsonite" }, taPackage.arenaTeamRoster)
        end)

        it("reads a four-player list", function()
            helper.simulateLine("Castor, Pelayo, Teekywiki, and Tojolias are here.")
            assert.are.same({ "Castor", "Pelayo", "Teekywiki", "Tojolias" },
                taPackage.arenaTeamRoster)
        end)

        -- The empty-room line ends in "nobody here.", not " is here.", so the
        -- anchored pattern cannot match it. If that ever regressed, "There" would
        -- silently join the roster and push everyone down a slot.
        it("does not take 'There' from the empty-room line", function()
            helper.simulateLine("There is nobody here.")
            assert.are.same({}, taPackage.arenaTeamRoster)
        end)

        it("does not take a monster from the occupant line", function()
            helper.simulateLine("There is a hobgoblin here.")
            assert.are.same({}, taPackage.arenaTeamRoster)
        end)

        it("does not take a plural monster count from the occupant line", function()
            helper.simulateLine("There are three warlocks here.")
            assert.are.same({}, taPackage.arenaTeamRoster)
        end)

        it("ignores the roster line outside team mode", function()
            taPackage.arenaTeam = false
            helper.simulateLine("Pelayo is here.")
            assert.are.same({}, taPackage.arenaTeamRoster)
        end)

        -- Scoped to the brief we asked for, so a player standing in some room we
        -- walk through on an errand never enters the arena roster.
        it("ignores the roster line when no probe is pending", function()
            taPackage.arenaProbePending = false
            helper.simulateLine("Pelayo is here.")
            assert.are.same({}, taPackage.arenaTeamRoster)
        end)

    end)

    -- The whole point of team mode: several characters see the same empty arena
    -- at the same moment and exactly one of them rings.
    describe("team staggered gong ring", function()

        -- Walk the brief the way the game prints it: the roster line, then the
        -- floor line that ends it and drives the ring decision.
        local function probeFindsEmptyArenaWith(rosterLine)
            taPackage.arenaTeam = true
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            taPackage.arenaTeamRoster = {}
            -- The real probe runs through arenaScanRoom, which clears the ring
            -- guard so the cycle can ring again; without this a second probe
            -- can't ring and a retry test would pass for the wrong reason.
            taPackage.arenaRingPending = false
            if rosterLine then helper.simulateLine(rosterLine) end
            helper.simulateLine("There is nothing on the floor.")
        end

        local function rangGong()
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "ring gong" then return true end
            end
            return false
        end

        -- Slot 0 used to ring with no stagger at all on the first attempt of a
        -- cycle, and that is the path that double-summoned onto Teekywiki (see
        -- arenaTeamRing). A ring already sent has nothing left to cancel when
        -- the team-mate's ring arrives a moment later; only a pending timer has.
        it("waits its gap even when first in the order", function()
            taPackage.character.name = "Castor"
            probeFindsEmptyArenaWith("Pelayo and Tojolias are here.")
            assert.is_false(rangGong())
            assert.are.equal(0, taPackage.arenaTeamSlot)
            helper.fireTimers(1 * 2000)
            assert.is_true(rangGong())
        end)

        it("holds off when someone sorts ahead of us", function()
            taPackage.character.name = "Pelayo"
            probeFindsEmptyArenaWith("Castor and Tojolias are here.")
            assert.is_false(rangGong())
            assert.are.equal(1, taPackage.arenaTeamSlot)
        end)

        it("takes a slot per character ahead of us", function()
            taPackage.character.name = "Tojolias"
            probeFindsEmptyArenaWith("Castor, Pelayo, and Johnsonite are here.")
            assert.is_false(rangGong())
            assert.are.equal(3, taPackage.arenaTeamSlot)
        end)

        it("orders case-insensitively", function()
            taPackage.character.name = "castor"
            probeFindsEmptyArenaWith("Pelayo is here.")
            assert.are.equal(0, taPackage.arenaTeamSlot)
        end)

        -- Alone in the arena, team mode has to behave exactly like a solo run.
        it("rings immediately when nobody else is here", function()
            taPackage.character.name = "Tojolias"
            probeFindsEmptyArenaWith(nil)
            assert.is_true(rangGong())
            assert.are.equal(0, taPackage.arenaTeamSlot)
        end)

        it("rings once its turn comes round", function()
            taPackage.character.name = "Pelayo"
            probeFindsEmptyArenaWith("Castor is here.")
            assert.is_false(rangGong())
            helper.fireTimers(2 * 2000)
            assert.is_true(rangGong())
        end)

        -- max(slot, 1) put slots 0 and 1 on the SAME 2s schedule, so two clients
        -- that ticked together rang together — exactly the pairing (Kerhak at 0,
        -- Teekywiki at 1) that double-summoned. Every slot gets its own instant.
        it("does not put slot 0 and slot 1 on the same instant", function()
            taPackage.character.name = "Castor"
            probeFindsEmptyArenaWith("Pelayo is here.")
            helper.fireTimers(2 * 2000)   -- slot 1's instant passes first
            assert.is_false(rangGong())
            helper.fireTimers(1 * 2000)
            assert.is_true(rangGong())
        end)

        -- A ring that bounces off "physically exhausted" used to be a special
        -- case, because slot 0's first attempt of a cycle had no pending timer
        -- for an incoming ring to cancel and so got re-sent blind on every pump
        -- tick. In company there is no fast path left to fall off, so first
        -- attempt and retry are the same path. What must still hold is that the
        -- gen guard calls those timers off, and that a character alone never
        -- pays the wait.
        describe("slot 0 in company", function()

            it("takes the timer path on the first attempt and on the retry", function()
                taPackage.character.name = "Castor"
                probeFindsEmptyArenaWith("Pelayo is here.")
                assert.is_false(rangGong())
                -- The ring bounced; the pump re-probes and we come round again.
                probeFindsEmptyArenaWith("Pelayo is here.")
                assert.are.equal(0, taPackage.arenaTeamSlot)
                assert.is_false(rangGong())
                helper.fireTimers(2000)
                assert.is_true(rangGong())
            end)

            it("stands down when the team-mate rings during that gap", function()
                taPackage.character.name = "Castor"
                probeFindsEmptyArenaWith("Pelayo is here.")
                helper.sendCalls = {}
                probeFindsEmptyArenaWith("Pelayo is here.")
                assert.is_false(rangGong())
                helper.simulateLine("Pelayo just rang the great gong!")
                helper.fireTimers(2000)
                assert.is_false(rangGong())
            end)

            -- Alone there is nobody to collide with, so the wait would be dead
            -- time on every cycle of a solo run.
            it("keeps the fast path when alone", function()
                taPackage.character.name = "Castor"
                probeFindsEmptyArenaWith(nil)
                helper.sendCalls = {}
                probeFindsEmptyArenaWith(nil)
                assert.is_true(rangGong())
            end)

            -- Company arriving mid-session takes the stagger away from us, and
            -- company leaving gives the fast path back: the roster is re-derived
            -- on every probe, so neither needs its own bookkeeping.
            it("follows the roster when company comes and goes", function()
                taPackage.character.name = "Castor"
                probeFindsEmptyArenaWith("Pelayo is here.")
                assert.is_false(rangGong())
                probeFindsEmptyArenaWith(nil)
                assert.is_true(rangGong())
            end)

        end)

        -- A character that walked out for potions or healing stops appearing in
        -- the brief, so the next one along inherits the front of the order. This
        -- is what makes the team survive without a designated leader.
        it("moves up the order when the character ahead leaves the arena", function()
            taPackage.character.name = "Pelayo"
            probeFindsEmptyArenaWith("Castor is here.")
            assert.are.equal(1, taPackage.arenaTeamSlot)
            probeFindsEmptyArenaWith(nil)
            assert.is_true(rangGong())
            assert.are.equal(0, taPackage.arenaTeamSlot)
        end)

        -- Re-probing bumps arenaRingGen, which is what cancels a pending ring. If
        -- the pump kept its solo 3s interval it would re-probe a slot-2 character
        -- before its 4s turn arrived, every cycle, and that character would never
        -- ring at all.
        it("widens the scan pump so a late slot still gets its turn", function()
            -- A kill drops us back into "ringing", which re-probes and arms the
            -- pump using the slot the previous probe worked out.
            taPackage.arenaTeam = true
            taPackage.arenaTeamSlot = 2
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "dragon"
            helper.timers = {}
            helper.simulateLine("The dragon falls to the ground lifeless!")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal(1, #helper.timers)
            assert.are.equal(3000 + 2 * 2000, helper.timers[1].interval)
        end)

        it("leaves the scan pump at its solo interval in slot 0", function()
            taPackage.arenaTeam = true
            taPackage.arenaTeamSlot = 0
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "dragon"
            helper.timers = {}
            helper.simulateLine("The dragon falls to the ground lifeless!")
            assert.are.equal(3000, helper.timers[1].interval)
        end)

        it("leaves the solo ring unstaggered", function()
            taPackage.character.name = "Tojolias"
            taPackage.arenaTeam = false
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            helper.simulateLine("Castor and Pelayo are here.")
            helper.simulateLine("There is nothing on the floor.")
            assert.is_true(rangGong())
        end)

        -- The broadcast ring is the lock. Whoever gets it out first has claimed
        -- the summon, and everyone still counting down has to stand down.
        describe("standing down when someone else rings first", function()

            it("cancels a pending ring", function()
                taPackage.character.name = "Pelayo"
                probeFindsEmptyArenaWith("Castor is here.")
                helper.simulateLine("Castor just rang the great gong!")
                helper.fireTimers(1 * 2000)
                assert.is_false(rangGong())
            end)

            -- Nothing is armed once we stand down, so without a fresh pump tick
            -- a summon that never lands (the ringer bounced off "still
            -- physically exhausted", or walked out) would leave us idle forever.
            it("re-arms the scan pump so a summon that never lands can't wedge us", function()
                taPackage.character.name = "Pelayo"
                probeFindsEmptyArenaWith("Castor is here.")
                helper.timers = {}
                helper.simulateLine("Castor just rang the great gong!")
                assert.are.equal(1, #helper.timers)
                helper.fireTimers()
                assert.are.equal("", helper.sendCalls[#helper.sendCalls])
            end)

            -- The ring can land in the middle of our own probe. The floor line
            -- ending that brief is what drives the ring decision, so if the probe
            -- were left live a slot-0 character would ring on top of the very
            -- summon it just stood down for.
            it("abandons a brief that is still arriving", function()
                taPackage.character.name = "Castor"
                taPackage.arenaTeam = true
                taPackage.arenaState = "ringing"
                taPackage.arenaProbePending = true
                taPackage.arenaTeamRoster = {}
                helper.simulateLine("Pelayo just rang the great gong!")
                helper.simulateLine("There is nothing on the floor.")
                assert.is_false(rangGong())
            end)

            it("is not fooled by our own ring", function()
                taPackage.character.name = "Castor"
                taPackage.arenaTeam = true
                taPackage.arenaState = "ringing"
                local genBefore = taPackage.arenaRingGen
                helper.simulateLine("You just rang the great gong!")
                assert.are.equal(genBefore, taPackage.arenaRingGen)
                assert.is_true(taPackage.arenaOwnSummonPending)
            end)

            it("ignores another player's ring outside team mode", function()
                taPackage.arenaTeam = false
                taPackage.arenaState = "ringing"
                local genBefore = taPackage.arenaRingGen
                helper.simulateLine("Castor just rang the great gong!")
                assert.are.equal(genBefore, taPackage.arenaRingGen)
            end)

            it("ignores another player's ring while we are already fighting", function()
                taPackage.arenaTeam = true
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "hobgoblin"
                helper.simulateLine("Castor just rang the great gong!")
                assert.are.equal("fighting", taPackage.arenaState)
                assert.are.equal("hobgoblin", taPackage.arenaMonster)
            end)

        end)

        -- Having stood down, we still have to fight the thing our team-mate
        -- summoned — otherwise standing down would just mean not fighting.
        describe("adopting a team-mate's summon", function()

            before_each(function()
                taPackage.arenaTeam = true
                taPackage.arenaState = "ringing"
                taPackage.arenaOwnSummonPending = false
                helper.mockDbOneRow = { description = "A hobgoblin." }
            end)

            it("engages a monster we did not summon (first arena)", function()
                helper.simulateLine("A hobgoblin enters the arena through the dungeon gate!")
                assert.are.equal("hobgoblin", taPackage.arenaMonster)
                assert.are.equal("fighting", taPackage.arenaState)
            end)

            it("engages a monster we did not summon (puff of smoke)", function()
                helper.simulateLine("A hobgoblin appears in a puff of green smoke!")
                assert.are.equal("hobgoblin", taPackage.arenaMonster)
                assert.are.equal("fighting", taPackage.arenaState)
            end)

            it("still ignores a summon that is not ours outside team mode", function()
                taPackage.arenaTeam = false
                helper.simulateLine("A hobgoblin enters the arena through the dungeon gate!")
                assert.is_nil(taPackage.arenaMonster)
                assert.are.equal("ringing", taPackage.arenaState)
            end)

            -- A spawn arriving mid-fight belongs to nobody here: we already have
            -- a monster, and swapping targets would abandon it half-killed.
            it("does not steal our attention while already fighting", function()
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "cave bear"
                helper.simulateLine("A hobgoblin enters the arena through the dungeon gate!")
                assert.are.equal("cave bear", taPackage.arenaMonster)
            end)

        end)

    end)

    -- A team can be built out of characters that could not each survive the
    -- arena alone. `exit-if-solo` is what stops the weakest one grinding itself
    -- to death after the others drop, get lost or die: alone for EXIT_MS, leave
    -- the game.
    describe("leaving the arena when alone (exit-if-solo)", function()

        local EXIT_MS, POLL_MS

        before_each(function()
            EXIT_MS = taPackage.arenaSolo.EXIT_MS
            POLL_MS = taPackage.arenaSolo.POLL_MS
            taPackage.arenaTeam = true
            taPackage.arenaExitIfSolo = true
            taPackage.arenaState = "ringing"
            taPackage.arenaTeamRoster = {}
            -- beginArenaSession does this; these tests drive the clock without
            -- going through the alias, so arm the heartbeat by hand.
            taPackage.arenaSolo.arm()
        end)

        -- The poll re-arms from its own callback, so each fireTimers advances
        -- exactly one tick -- which is also how the script's other pumps are
        -- driven in these tests.
        local function tick()
            helper.fireTimers(POLL_MS)
        end

        local function leftTheGame()
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "x" then return true end
            end
            return false
        end

        -- Wait out the threshold in whole polls, the way the real clock does:
        -- the stamp is only read on a tick, so time passing on its own is not
        -- enough to trigger anything.
        local function waitAlone(ms)
            helper.advanceMs(ms)
            tick()
        end

        describe("between fights", function()

            it("does not start the clock while a team-mate is present", function()
                taPackage.arenaTeamRoster = { "Kerhak" }
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            it("starts the clock on an empty arena", function()
                tick()
                assert.are.equal(helper.currentMs, taPackage.arenaSoloSince)
                assert.is_false(leftTheGame())
            end)

            it("holds on just under the threshold", function()
                tick()
                waitAlone(EXIT_MS - 1)
                assert.is_false(leftTheGame())
                assert.is_not_nil(taPackage.arenaSoloSince)
            end)

            it("leaves the game once the threshold passes", function()
                tick()
                waitAlone(EXIT_MS)
                assert.is_true(leftTheGame())
                -- arenaEmergencyExit tears the session down, so no stale combat
                -- timer can re-arm behind the exit.
                assert.is_nil(taPackage.arenaState)
            end)

            it("resets the clock when company comes back", function()
                tick()
                waitAlone(EXIT_MS - 1)
                taPackage.arenaTeamRoster = { "Kerhak" }
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
                -- And the next stretch alone starts from scratch rather than
                -- inheriting the time already served.
                taPackage.arenaTeamRoster = {}
                tick()
                waitAlone(EXIT_MS - 1)
                assert.is_false(leftTheGame())
            end)

            -- arenaScanRoom empties the roster as it sends its probe, so a tick
            -- landing in that gap would read a blank that means "not answered
            -- yet", not "nobody here".
            it("skips a tick that lands mid-probe", function()
                taPackage.arenaProbePending = true
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
            end)

        end)

        describe("during a fight", function()

            before_each(function()
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "stone giant"
            end)

            -- The scan pump stops the moment we engage, so nothing refreshes the
            -- roster -- and this is exactly the state in which being left alone
            -- is fatal. The poll has to ask for the brief itself.
            it("asks for the brief itself", function()
                tick()
                assert.is_true(taPackage.arenaSoloProbePending)
                assert.are.equal("", helper.sendCalls[#helper.sendCalls])
            end)

            it("resets the clock when the brief names a team-mate", function()
                taPackage.arenaSoloSince = helper.currentMs
                tick()
                helper.simulateLine("Kerhak and Pollux are here.")
                helper.simulateLine("There is nothing on the floor.")
                assert.is_nil(taPackage.arenaSoloSince)
                assert.is_false(taPackage.arenaSoloProbePending)
            end)

            -- No roster line is printed at all when nobody else is there, so the
            -- floor line is the only place "we are alone" becomes knowable.
            it("starts the clock when the brief names nobody", function()
                tick()
                helper.simulateLine("There is nothing on the floor.")
                assert.are.equal(helper.currentMs, taPackage.arenaSoloSince)
            end)

            it("leaves the game mid-fight once the threshold passes", function()
                tick()
                helper.simulateLine("There is nothing on the floor.")
                helper.advanceMs(EXIT_MS)
                tick()
                helper.simulateLine("There is nothing on the floor.")
                assert.is_true(leftTheGame())
                assert.is_nil(taPackage.arenaState)
            end)

            -- Our probe carries its own pending flag precisely so the ring
            -- machinery, which gates on arenaProbePending, stays dormant: a
            -- monster in the brief must not be engaged and the floor line must
            -- not drive a ring decision while we are already fighting.
            it("does not engage or ring off the back of its own brief", function()
                tick()
                helper.simulateLine("There is a hobgoblin here.")
                helper.simulateLine("There is nothing on the floor.")
                assert.are.equal("stone giant", taPackage.arenaMonster)
                assert.are.equal("fighting", taPackage.arenaState)
                for _, cmd in ipairs(helper.sendCalls) do
                    assert.are_not.equal("ring gong", cmd)
                end
            end)

        end)

        -- We cannot see the arena from the magic shop, and must not bank
        -- solitude while we are the ones who are absent.
        describe("while away on an errand", function()

            it("pauses the clock", function()
                tick()
                assert.is_not_nil(taPackage.arenaSoloSince)
                taPackage.arenaState = "potions"
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            it("cannot leave the game", function()
                tick()
                taPackage.arenaState = "potions"
                helper.advanceMs(EXIT_MS * 2)
                tick()
                assert.is_false(leftTheGame())
            end)

            -- The walk home runs as "returning", and its last steps are still
            -- nowhere near the arena.
            it("pauses on a journey even in an arena state", function()
                tick()
                taPackage.arenaJourney = { steps = { "n" }, index = 1 }
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            -- An errand must not end the timer chain: the rest of the run would
            -- be unprotected in a session that otherwise looks healthy.
            it("keeps polling, so it recovers when we get back", function()
                taPackage.arenaState = "potions"
                tick()
                taPackage.arenaState = "ringing"
                tick()
                assert.is_not_nil(taPackage.arenaSoloSince)
            end)

        end)

        -- Only the poll may conclude "alone"; everything else may only reset the
        -- clock. A missed signal then costs a slower detection, never a wrong
        -- one.
        describe("signals that prove we have company", function()

            it("takes another player's gong ring", function()
                tick()
                assert.is_not_nil(taPackage.arenaSoloSince)
                helper.simulateLine("Castor just rang the great gong!")
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            -- Mid-fight that trigger has nothing else to do and returns early,
            -- which is precisely when the clock is running unattended.
            it("takes a gong ring heard mid-fight", function()
                taPackage.arenaState = "fighting"
                taPackage.arenaSoloSince = helper.currentMs
                helper.simulateLine("Castor just rang the great gong!")
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            -- Our own ring proves nothing about anyone else.
            it("ignores our own gong ring", function()
                taPackage.arenaSoloSince = helper.currentMs
                helper.simulateLine("You just rang the great gong!")
                assert.is_not_nil(taPackage.arenaSoloSince)
            end)

            -- A team-mate announcing a heal run is alive and talking -- and is
            -- about to be legitimately absent, which is the case most likely to
            -- trip a false exit.
            it("takes a team-mate's heal announcement", function()
                tick()
                helper.simulateLine("From Kerhak: I need healing")
                assert.is_nil(taPackage.arenaSoloSince)
            end)

            it("takes a team-mate's all-clear", function()
                tick()
                helper.simulateLine("From Kerhak: I am healed")
                assert.is_nil(taPackage.arenaSoloSince)
            end)

        end)

        describe("when the flag is off", function()

            before_each(function()
                taPackage.arenaExitIfSolo = false
                taPackage.arenaSoloSince = nil
                -- Re-arm with the flag off, which is the no-op path a real
                -- session without exit-if-solo takes.
                taPackage.arenaSolo.arm()
            end)

            it("never starts a clock or leaves the game", function()
                tick()
                helper.advanceMs(EXIT_MS * 2)
                tick()
                assert.is_nil(taPackage.arenaSoloSince)
                assert.is_false(leftTheGame())
            end)

        end)

        describe("teardown", function()

            it("is cleared by stopping the arena", function()
                tick()
                taPackage.stopArena()
                assert.is_nil(taPackage.arenaExitIfSolo)
                assert.is_nil(taPackage.arenaSoloSince)
                assert.is_nil(taPackage.arenaSoloProbePending)
            end)

            -- There is no timer-cancellation API, so a tick armed before the
            -- stop will still fire. The generation guard is what makes it a
            -- no-op instead of an exit from a session that is already over.
            it("survives a tick armed before the stop", function()
                tick()
                helper.advanceMs(EXIT_MS)
                taPackage.stopArena()
                helper.sendCalls = {}
                tick()
                assert.is_false(leftTheGame())
            end)

            it("is cleared by stop-all-scripts", function()
                tick()
                helper.simulateAlias("stop-all-scripts")
                assert.is_nil(taPackage.arenaExitIfSolo)
                assert.is_nil(taPackage.arenaSoloSince)
            end)

        end)

    end)

    -- A character that flees is still standing in the arena until a move
    -- actually lands, and the move can be refused for seconds by the
    -- heat-of-battle guard or the rest clock. Summoning into that window drops a
    -- fresh monster on someone who is one hit from death, so the escapee calls
    -- out and everyone else holds the gong until it is back.
    describe("holding the gong for a team-mate who needs healing", function()

        local function said(text)
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == text then return true end
            end
            return false
        end

        local function rangGong()
            return said("ring gong")
        end

        -- As in the staggered-ring tests: walk the brief the way the game prints
        -- it, ending on the floor line that drives the ring decision.
        local function probeFindsEmptyArena()
            taPackage.arenaTeam = true
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            taPackage.arenaTeamRoster = {}
            taPackage.arenaRingPending = false
            helper.simulateLine("There is nothing on the floor.")
        end

        describe("hearing a team-mate call out", function()

            before_each(function()
                taPackage.character.name = "Castor"
                taPackage.arenaTeam = true
            end)

            it("declines to ring while a team-mate is escaping", function()
                helper.simulateLine("From Pelayo: I need healing")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
            end)

            -- Slot 0's fast path rings with no stagger at all, which is exactly
            -- the path that outruns a 2s flee retry. It has to be held too.
            it("holds even in slot 0, where the ring is otherwise immediate", function()
                helper.simulateLine("From Pelayo: I need healing")
                probeFindsEmptyArena()
                assert.are.equal(0, taPackage.arenaTeamSlot or 0)
                assert.is_false(rangGong())
            end)

            it("rings again once the team-mate reports back", function()
                helper.simulateLine("From Pelayo: I need healing")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
                helper.simulateLine("From Pelayo: I am healed")
                helper.advanceMs(4000)
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            -- Every held client comes off the hold on this one line, so they all
            -- reach a ring decision in the same instant. That is the collision
            -- that killed Teekywiki: Kerhak rang off the very tick that released
            -- it. The character that just healed gets first refusal instead.
            it("stands off the gong for a beat after the all-clear", function()
                helper.simulateLine("From Pelayo: I need healing")
                helper.simulateLine("From Pelayo: I am healed")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
            end)

            -- ...but only for a beat: if the returning character never rings —
            -- it died on the way back, or was stopped by hand — the ordinary
            -- order has to take over rather than idling the arena.
            it("rings once the grace lapses and nobody else has", function()
                helper.simulateLine("From Pelayo: I need healing")
                helper.simulateLine("From Pelayo: I am healed")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
                helper.advanceMs(4000)
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            -- The grace is not a second hold: it must not gate a team that never
            -- heard an all-clear at all.
            it("does not stand off when no all-clear has been heard", function()
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            -- Everyone has to be back, not just the most recent caller.
            it("keeps holding while a second team-mate is still out", function()
                helper.simulateLine("From Pelayo: I need healing")
                helper.simulateLine("From Tojolias: I need healing")
                helper.simulateLine("From Pelayo: I am healed")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
                helper.simulateLine("From Tojolias: I am healed")
                helper.advanceMs(4000)
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            -- The backstop that keeps a death or a hand-stopped script from
            -- idling the whole team forever waiting for an all-clear that is
            -- never coming.
            -- The escapee calls out only once, so the lease is the sole thing
            -- keeping the hold alive for the whole episode — and the sole
            -- backstop against a death or hand-stopped script holding it forever.
            it("holds well past the point a short lease would have lapsed", function()
                helper.simulateLine("From Pelayo: I need healing")
                taPackage.arenaTeamHealing["pelayo"] = os.time() - 120
                probeFindsEmptyArena()
                assert.is_false(rangGong())
            end)

            it("releases the hold when the lease expires", function()
                helper.simulateLine("From Pelayo: I need healing")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
                taPackage.arenaTeamHealing["pelayo"] = os.time() - 181
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            it("forgets an expired lease rather than accumulating it", function()
                helper.simulateLine("From Pelayo: I need healing")
                taPackage.arenaTeamHealing["pelayo"] = os.time() - 181
                probeFindsEmptyArena()
                assert.is_nil(taPackage.arenaTeamHealing["pelayo"])
            end)

            -- A team-mate who heals and later gets hurt again places a fresh
            -- hold; the earlier all-clear must not have made us deaf to them.
            it("holds again when the same team-mate calls out a second time", function()
                helper.simulateLine("From Pelayo: I need healing")
                helper.simulateLine("From Pelayo: I am healed")
                helper.simulateLine("From Pelayo: I need healing")
                probeFindsEmptyArena()
                assert.is_false(rangGong())
            end)

            -- Holding the gong must never mean standing next to something that
            -- is already hitting us: only the summon is suppressed.
            it("still engages a monster that is already in the room", function()
                helper.simulateLine("From Pelayo: I need healing")
                helper.mockDbOneRow = { description = "A hobgoblin." }
                taPackage.arenaState = "ringing"
                taPackage.arenaProbePending = true
                helper.simulateLine("There is a hobgoblin here.")
                assert.are.equal("fighting", taPackage.arenaState)
                assert.are.equal("hobgoblin", taPackage.arenaMonster)
            end)

            -- The group-chat channel carries remote commands and belongs to its
            -- own trigger. A loose (.+) for the name would swallow it.
            it("is not tripped by the group-chat channel", function()
                helper.simulateLine("From Pelayo (to group): I need healing")
                probeFindsEmptyArena()
                assert.is_true(rangGong())
            end)

            it("ignores the call outside team mode", function()
                taPackage.arenaTeam = false
                helper.simulateLine("From Pelayo: I need healing")
                taPackage.arenaState = "ringing"
                taPackage.arenaProbePending = true
                helper.simulateLine("There is nothing on the floor.")
                assert.is_true(rangGong())
            end)

        end)

        describe("calling out when we are the one fleeing", function()

            before_each(function()
                taPackage.arenaProfile = "1"
                taPackage.arenaTeam = true
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "cave bear"
            end)

            it("announces before taking the first step out", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                assert.are.equal("fleeing", taPackage.arenaState)
                assert.is_true(said("I need healing"))
            end)

            -- arenaLastCmd drives the blocked-move retries. If the announcement
            -- went through arenaSend it would be stamped there and the retry
            -- would re-say the message instead of re-walking the escape step.
            it("leaves the escape step as the command a retry will re-send", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                assert.are.equal("w", taPackage.arenaLastCmd)
            end)

            it("says nothing in a solo run", function()
                taPackage.arenaTeam = false
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                assert.are.equal("fleeing", taPackage.arenaState)
                assert.is_false(said("I need healing"))
            end)

            -- Once per flee, however long the escape drags on: the call is a
            -- request to hold the gong, and repeating it adds nothing the lease
            -- doesn't already carry.
            it("does not repeat when the monster blocks the way out", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                helper.sendCalls = {}
                helper.simulateLine("You cannot leave in the heat of battle!")
                assert.is_false(said("I need healing"))
            end)

            it("does not repeat when the rest clock blocks the way out", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                helper.sendCalls = {}
                taPackage.arenaLastCmd = "w"
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                assert.is_false(said("I need healing"))
            end)

            -- Repeatedly blocked and taking hits the whole time: still one call.
            it("says it once across a long, repeatedly blocked escape", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                helper.simulateLine("You cannot leave in the heat of battle!")
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.simulateLine("The cave bear attacked you with a claw for 3 damage!")
                local calls = 0
                for _, cmd in ipairs(helper.sendCalls) do
                    if cmd == "I need healing" then calls = calls + 1 end
                end
                assert.are.equal(1, calls)
            end)

            -- The flag is cleared by the all-clear, so a later flee in the same
            -- session is a fresh episode and calls out again. Healed to full
            -- before walking in: arriving home still under the threshold no
            -- longer reports back, it turns around for the temple again.
            it("calls out again on a second flee after reporting back", function()
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                taPackage.arenaJourney = { steps = { "e" }, index = 2, arriveRoom = "arena" }
                taPackage.arenaState = "returning"
                taPackage.arenaMonster = nil
                setHP(100, 100)
                helper.simulateLine("You're in the arena.")
                helper.sendCalls = {}
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "cave bear"
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                assert.is_true(said("I need healing"))
            end)

            -- An errand walk-out blocked by the same lines is a full-health
            -- character running for a drink, not an emergency.
            it("stays quiet when an errand walk-out is blocked", function()
                taPackage.arenaState = "tavern"
                taPackage.arenaLastCmd = "w"
                helper.simulateLine("You cannot leave in the heat of battle!")
                assert.is_false(said("I need healing"))
            end)

        end)

        describe("reporting back", function()

            -- Speech only carries to the room you are standing in, so the
            -- all-clear has to be said from the arena. Said at the temple — four
            -- rooms away in the third arena — it would reach nobody and the hold
            -- would expire on a timeout every single trip.
            local function arriveHomeFromTemple()
                taPackage.arenaProfile = "1"
                taPackage.arenaState = "returning"
                taPackage.arenaMonster = nil
                taPackage.arenaJourney = { steps = { "e" }, index = 2, arriveRoom = "arena" }
                helper.simulateLine("You're in the arena.")
            end

            it("says the all-clear on arriving back in the arena", function()
                taPackage.arenaTeam = true
                taPackage.arenaAnnouncedNeedsHealing = true
                arriveHomeFromTemple()
                assert.is_true(said("I am healed"))
            end)

            it("does not say it at the temple", function()
                taPackage.arenaTeam = true
                taPackage.arenaProfile = "1"
                taPackage.arenaAnnouncedNeedsHealing = true
                -- The heal is charged for, and a balance that goes negative
                -- trips the low-gold bailout and tears the session down.
                taPackage.character.gold = 5000
                taPackage.arenaState = "healing"
                helper.simulateLine("The priests heal all your wounds for 100 crowns.")
                assert.is_false(said("I am healed"))
                assert.are.equal("returning", taPackage.arenaState)
            end)

            -- arenaArrivedHome is shared by the bar, magic shop and guild hall
            -- returns, which never placed a hold.
            it("stays quiet on an ordinary errand return", function()
                taPackage.arenaTeam = true
                taPackage.arenaAnnouncedNeedsHealing = false
                arriveHomeFromTemple()
                assert.is_false(said("I am healed"))
            end)

            it("only reports back once", function()
                taPackage.arenaTeam = true
                taPackage.arenaAnnouncedNeedsHealing = true
                arriveHomeFromTemple()
                helper.sendCalls = {}
                arriveHomeFromTemple()
                assert.is_false(said("I am healed"))
            end)

            -- End to end, from the hit that triggers the flee to the all-clear.
            it("completes the round trip from flee to all-clear", function()
                taPackage.arenaProfile = "1"
                taPackage.arenaTeam = true
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "cave bear"
                taPackage.character.gold = 5000
                setHP(10, 100)
                helper.simulateLine("Your attack hit the cave bear for 5 damage!")
                assert.is_true(said("I need healing"))
                taPackage.arenaState = "healing"
                helper.simulateLine("The priests heal all your wounds for 100 crowns.")
                helper.sendCalls = {}
                taPackage.arenaJourney = { steps = { "e" }, index = 2, arriveRoom = "arena" }
                helper.simulateLine("You're in the arena.")
                assert.is_true(said("I am healed"))
            end)

        end)

        -- stop-arena-fight has to clear the hold too: a lease left behind would
        -- be honoured by the next session and hold its gong for a character that
        -- finished healing long ago.
        it("clears the hold when the session stops", function()
            taPackage.arenaTeam = true
            helper.simulateLine("From Pelayo: I need healing")
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaTeamHealing)
            assert.is_nil(taPackage.arenaAnnouncedNeedsHealing)
        end)

        it("starts a new session deaf to a stale hold", function()
            taPackage.arenaTeam = true
            helper.simulateLine("From Pelayo: I need healing")
            setClass("Warrior")
            helper.simulateAlias("team-fight-in-arena")
            assert.are.same({}, taPackage.arenaTeamHealing)
            assert.is_false(taPackage.arenaAnnouncedNeedsHealing)
        end)

    end)

    -- Support-only mode. Two characters stand in the arena purely as extra
    -- bodies for the monster to split its attacks across, so all the XP goes to
    -- the third -- XP here is awarded by damage share, so the only way to give
    -- it away is to not swing. The exception is the emergency the gong hold
    -- above exists for: a team-mate below its flee threshold is pinned in the
    -- room by the heat-of-battle guard until the monster is dead, so the same
    -- announcement that holds the gong also opens the supports' swords.
    describe("support-only", function()

        local function said(text)
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == text then return true end
            end
            return false
        end

        local function attacked()
            return said("a flame")
        end

        -- Standing in the arena, locked onto a monster, not assisting anyone.
        local function supportingInAFight()
            taPackage.arenaTeam = true
            taPackage.arenaSupportOnly = true
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "flame giant"
            taPackage.arenaAttackPending = false
            taPackage.arenaCastPending = false
            helper.sendCalls = {}
        end

        local function monsterHitsUs()
            helper.simulateLine("The flame giant attacked you with a club for 12 damage!")
        end

        it("does not swing when the monster attacks it", function()
            supportingInAFight()
            monsterHitsUs()
            assert.is_false(attacked())
        end)

        -- The case the kick in the need-healing trigger exists for. A support
        -- never swings, so arenaSwingAccepted never fires and the only other
        -- re-drives are the incoming-attack triggers -- which fire only when the
        -- monster picks US. If it is beating on the character that just called
        -- for help, nothing would ever start the burst.
        it("attacks the moment a team-mate calls for healing, unprompted", function()
            supportingInAFight()
            helper.simulateLine("From Pelayo: I need healing")
            assert.is_true(attacked())
        end)

        it("keeps swinging while the team-mate is away", function()
            supportingInAFight()
            helper.simulateLine("From Pelayo: I need healing")
            helper.sendCalls = {}
            taPackage.arenaAttackPending = false
            monsterHitsUs()
            assert.is_true(attacked())
        end)

        -- Standing down immediately, rather than finishing the monster: every
        -- swing after the emergency is XP taken from the character we are here
        -- to feed.
        it("stands down again when the team-mate reports back", function()
            supportingInAFight()
            helper.simulateLine("From Pelayo: I need healing")
            helper.simulateLine("From Pelayo: I am healed")
            helper.sendCalls = {}
            taPackage.arenaAttackPending = false
            monsterHitsUs()
            assert.is_false(attacked())
        end)

        -- The assist rides the gong hold's lease, so it inherits its expiry: a
        -- support that never hears the all-clear (the announcer died, or dropped
        -- its connection) must not swing for the rest of the session.
        it("stands down when the lease lapses without an all-clear", function()
            supportingInAFight()
            helper.simulateLine("From Pelayo: I need healing")
            taPackage.arenaTeamHealing["pelayo"] = os.time() - 181
            helper.sendCalls = {}
            taPackage.arenaAttackPending = false
            monsterHitsUs()
            assert.is_false(attacked())
        end)

        -- The second half of the ask: supports cover each other too. A pinned
        -- support needs the monster dead for exactly the same reason.
        it("assists a fellow support who calls for healing", function()
            supportingInAFight()
            helper.simulateLine("From Kerhak: I need healing")
            assert.is_true(attacked())
        end)

        -- The flag must not leak into ordinary team mode: the character being
        -- levelled hears the same announcement and must simply keep fighting.
        it("leaves a plain team member swinging throughout", function()
            supportingInAFight()
            taPackage.arenaSupportOnly = false
            monsterHitsUs()
            assert.is_true(attacked())
        end)

        -- Casting is attacking: a Sorceror gives away XP with toduza just as
        -- surely as with its sword.
        it("holds a Sorceror's toduza too, and casts once assisting", function()
            setClass("Sorceror")
            supportingInAFight()
            monsterHitsUs()
            assert.is_false(said("cast toduza flame"))
            taPackage.arenaCastPending = false
            helper.simulateLine("From Pelayo: I need healing")
            assert.is_true(said("cast toduza flame"))
        end)

        -- Supports keep their place in the ring order. The character being
        -- levelled cannot know its team-mates are supports, so the stagger has
        -- to keep working unmodified -- and a character that is not swinging has
        -- a permanently fresh physical clock, so it clears the gong's floor
        -- immediately after a kill instead of waiting out ARENA_RING_FLOOR_MS.
        it("still rings the gong", function()
            taPackage.character.name = "Castor"
            taPackage.arenaTeam = true
            taPackage.arenaSupportOnly = true
            taPackage.arenaState = "ringing"
            taPackage.arenaProbePending = true
            taPackage.arenaTeamRoster = {}
            taPackage.arenaRingPending = false
            helper.sendCalls = {}
            helper.simulateLine("There is nothing on the floor.")
            assert.is_true(said("ring gong"))
        end)

        -- Fleeing is untouched: a hurt support walks out, and announces on the
        -- way so nobody summons on top of it -- which is also what opens the
        -- other support's swords.
        it("still flees and calls for healing when hurt", function()
            taPackage.arenaTeam = true
            taPackage.arenaSupportOnly = true
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "flame giant"
            setHP(10, 100)
            helper.sendCalls = {}
            -- A support never swings, so the flee check rides an incoming hit
            -- rather than the resolution of one of our own attacks.
            monsterHitsUs()
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.is_true(said("I need healing"))
        end)

        it("is cleared by stop-all-scripts", function()
            setClass("Warrior")
            helper.simulateAlias("tfia 3 support-only")
            assert.is_true(taPackage.arenaSupportOnly)
            helper.simulateAlias("stop-all-scripts")
            assert.is_nil(taPackage.arenaSupportOnly)
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

        -- Walk to the bar the way the game does, so the buys happen on arrival.
        local barStepTimer
        local function atTheBar(setup)
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then barStepTimer = { cb = cb } end
                return "mock_timer"
            end
            barStepTimer = nil
            taPackage.arenaState = "fighting"
            setup()
            helper.simulateLine("You're thirsty.")       -- departs for the bar
            helper.simulateLine("You're in the north plaza.")
            barStepTimer.cb()
            helper.sendCalls = {}
            helper.simulateLine("You're in the tavern.")
        end

        -- Healing while also thirsty now walks home and sets out again, rather
        -- than cutting the corner from the temple to the tavern: arriving home
        -- is the one place errands get dispatched, so every errand starts there.
        it("walks home after healing, and the arrival sends us on for a drink", function()
            local stepTimer
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")   -- flees
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the temple.")
            taPackage.needsDrinks = true
            taPackage.character.gold = 500
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("returning", taPackage.arenaState)
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            taPackage.arenaMonster = nil
            helper.simulateLine("You're in the arena.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys a drink on arrival with needsDrinks", function()
            atTheBar(function() taPackage.needsDrinks = true end)
            assert.are.equal("buy drink", helper.sendCalls[1])
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.needsDrinks)
        end)

        it("buys a meal on arrival with needsMeal", function()
            atTheBar(function() taPackage.needsMeal = true end)
            local bought = false
            for _, cmd in ipairs(helper.sendCalls) do if cmd == "buy meal" then bought = true end end
            assert.is_true(bought)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.needsMeal)
        end)

        it("buys both when both are owed", function()
            atTheBar(function() taPackage.needsMeal = true end)
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

        it("paces w then ne to the bar", function()
            local stepTimer
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
            helper.simulateLine("You're in the north plaza.")
            assert.is_not_nil(stepTimer)          -- paced, not immediate
            stepTimer.cb()
            assert.are.equal("ne", helper.sendCalls[#helper.sendCalls])
        end)

        it("departs the bar sw and transitions to returning", function()
            atTheBar(function() taPackage.needsDrinks = true end)
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
            local stepTimer
            _G.createTimer = function(interval, cb)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")       -- departs for the bar
            taPackage.arenaParchedStreak = 10
            helper.simulateLine("You're in the north plaza.")
            stepTimer.cb()
            helper.simulateLine("You're in the tavern.")
            assert.are.equal(0, taPackage.arenaParchedStreak)
        end)

    end)

    describe("healing trigger ignored outside arena script", function()

        it("does not affect state when arenaState is not healing", function()
            taPackage.arenaState = "fighting"
            taPackage.character.gold = 500
            helper.simulateLine("The priests heal all your wounds for 2 crowns.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("leaving the game when broke during an arena run", function()

        it("exits and stops when healing is unaffordable", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You can't afford healing.")
            assert.are.equal("x", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaState)
        end)

        it("exits and stops when a rowan potion is unaffordable", function()
            taPackage.arenaState = "potions"
            helper.simulateLine("You can't afford a rowan potion.")
            assert.are.equal("x", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaState)
        end)

        it("exits and stops when a hyssop potion is unaffordable", function()
            taPackage.arenaState = "potions"
            helper.simulateLine("You can't afford a hyssop potion.")
            assert.are.equal("x", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaState)
        end)

        it("does nothing on a can't-afford line outside arena/tavern", function()
            helper.simulateLine("You can't afford healing.")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

        it("exits and stops when gold falls below the 50 floor", function()
            taPackage.arenaState = "fighting"
            taPackage.character.gold = 500
            helper.simulateLine("You found 3 gold crowns while searching the orc's corpse.")
            assert.is_not_nil(taPackage.arenaState)  -- 503 is fine
            helper.sendCalls = {}
            taPackage.character.gold = 80
            helper.simulateLine("The priests heal all your wounds for 40 crowns.")  -- -> 40
            assert.are.equal("x", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaState)
        end)

        it("stays in the game at exactly the 50 floor", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You are carrying 50 gold crowns.")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        it("ignores a low balance when no arena run is active", function()
            taPackage.arenaState = nil
            helper.simulateLine("You are carrying 5 gold crowns.")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

    end)

    describe("emergency exit retries until the game confirms", function()

        local timers

        before_each(function()
            helper.resetAll()
            timers = {}
            _G.createTimer = function(interval, cb, opts)
                table.insert(timers, { interval = interval, cb = cb, opts = opts })
                return "mock_timer"
            end
            dofile("main.lua")
            helper.clearDbCalls()
        end)

        local function countX()
            local n = 0
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "x" then n = n + 1 end
            end
            return n
        end

        it("sends x immediately and arms a 2s retry, tearing down the run", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You can't afford healing.")
            assert.are.equal(1, countX())
            assert.is_true(taPackage.exitGamePending)
            assert.is_nil(taPackage.arenaState)  -- session torn down
            assert.are.equal(2000, timers[#timers].interval)
        end)

        it("re-sends x when the retry timer fires (still rest-blocked)", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You can't afford healing.")
            assert.are.equal(1, countX())
            -- The game rejects the move; firing the armed retry re-sends x and
            -- re-arms the next attempt.
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            timers[#timers].cb()
            assert.are.equal(2, countX())
            timers[#timers].cb()
            assert.are.equal(3, countX())
        end)

        it("stops retrying once the game confirms Exiting Tele-Arena...", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You can't afford healing.")
            local armed = timers[#timers]
            helper.simulateLine("Exiting Tele-Arena...")
            assert.is_false(taPackage.exitGamePending)
            -- A stale timer that fires after confirmation must not re-send x.
            armed.cb()
            assert.are.equal(1, countX())
        end)

        it("stops retrying when the run is stopped manually", function()
            taPackage.arenaState = "fleeing"
            helper.simulateLine("You can't afford healing.")
            local armed = timers[#timers]
            taPackage.stopArena()
            assert.is_false(taPackage.exitGamePending)
            armed.cb()
            assert.are.equal(1, countX())
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

        it("creates 2s timer on move-rate-limit while fleeing", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_not_nil(timerCreated)
            assert.are.equal(2000, timerCreated.interval)
        end)

        it("creates 30s timer on move-rate-limit for a non-flee errand walk", function()
            taPackage.arenaState = "tavern"
            taPackage.arenaLastCmd = "w"
            helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
            assert.is_not_nil(timerCreated)
            assert.are.equal(30000, timerCreated.interval)
        end)

        it("polls every 2s on attack-rate-limit when arena is active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaLastCmd = "a skeleton"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            assert.is_not_nil(timerCreated)
            assert.are.equal(2000, timerCreated.interval)
        end)

        -- The re-arm triggers all match combat lines addressed to US, so a monster
        -- busy with a teammate leaves this retry as the ONLY thing that resumes
        -- our swing. At the old 30s that was a 30s hole in team damage output.
        it("resumes the swing itself when only a teammate is being attacked", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "stone giant"
            taPackage.arenaLastCmd = "a stone"
            helper.simulateLine("You are still physically exhausted from your previous activities!")
            local retry = timerCreated
            assert.are.equal(2000, retry.interval)
            -- Rounds go by in which the monster names the teammate, not us.
            helper.sendCalls = {}
            helper.simulateLine("The stone giant's poorly executed attack misses Kerhak!")
            assert.are.equal(0, #helper.sendCalls)  -- nothing re-armed us
            retry.cb()
            assert.are.equal("a stone", helper.sendCalls[1])
        end)

        -- The physical cooldown is a fixed wall-clock timer that starts when a
        -- swing is ACCEPTED. Reckoning the wait from that instant (rather than
        -- polling the whole window) is what cuts ~10 rejected commands per
        -- cooldown down to about one.
        describe("physical cooldown reckoning", function()

            local EXHAUSTED = "You are still physically exhausted from your previous activities!"

            local function fighting()
                taPackage.arenaState = "fighting"
                taPackage.arenaMonster = "skeleton"
            end

            it("stamps the swing time on hit, miss and dodge alike", function()
                fighting()
                helper.advanceMs(1000)
                helper.simulateLine("Your attack hit the skeleton for 15 damage!")
                assert.are.equal(1000, taPackage.arenaLastSwingAt)
                helper.advanceMs(1000)
                helper.simulateLine("Your attack missed!")
                assert.are.equal(2000, taPackage.arenaLastSwingAt)
                helper.advanceMs(1000)
                helper.simulateLine("The skeleton dodged your attack!")
                assert.are.equal(3000, taPackage.arenaLastSwingAt)
            end)

            it("waits out the remaining cooldown instead of polling it", function()
                fighting()
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(5000)
                timerCreated = nil
                helper.simulateLine(EXHAUSTED)
                -- 35s cooldown - 5s elapsed - 2s margin
                assert.are.equal(28000, timerCreated.interval)
            end)

            it("does not restart the wait on a later rejection in the same cooldown", function()
                -- The anti-drift property: timing from the rejection would arm a
                -- fresh full cooldown here and stall us well past recovery.
                fighting()
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(5000)
                helper.simulateLine(EXHAUSTED)
                assert.are.equal(28000, timerCreated.interval)
                helper.advanceMs(20000)  -- now 25s past the swing
                helper.simulateLine(EXHAUSTED)
                assert.are.equal(8000, timerCreated.interval)
            end)

            it("drops to the tail poll once inside the margin", function()
                fighting()
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(34000)
                timerCreated = nil
                helper.simulateLine(EXHAUSTED)
                assert.are.equal(2000, timerCreated.interval)
            end)

            it("polls when no swing has landed to reckon from", function()
                -- Straight after a ring: the gong spent the clock, not a swing.
                fighting()
                taPackage.arenaLastSwingAt = nil
                helper.simulateLine(EXHAUSTED)
                assert.are.equal(2000, timerCreated.interval)
            end)

            it("polls when the last swing is stale after an errand trip", function()
                fighting()
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(600000)  -- ten minutes at the temple
                timerCreated = nil
                helper.simulateLine(EXHAUSTED)
                assert.are.equal(2000, timerCreated.interval)
            end)

            -- Groundwork for measuring the gong's own cooldown. The stamp sits
            -- ahead of the trigger's state gate on purpose, so it records the
            -- acceptance even on the paths that return early, and it must not
            -- disturb the swing clock the melee reckoning runs on.
            it("stamps ring acceptance without touching the swing clock", function()
                fighting()
                taPackage.arenaLastSwingAt = 1000
                helper.advanceMs(7000)
                helper.simulateLine("You just rang the great gong!")
                assert.are.equal(7000, taPackage.arenaLastRingAt)
                assert.are.equal(1000, taPackage.arenaLastSwingAt)
            end)

            it("still swings when the reckoned timer fires", function()
                fighting()
                taPackage.arenaLastCmd = "a skeleton"
                taPackage.arenaLastSwingAt = 0
                helper.advanceMs(5000)
                timerCreated = nil
                helper.simulateLine(EXHAUSTED)
                helper.sendCalls = {}
                timerCreated.cb()
                assert.are.equal("a skeleton", helper.sendCalls[1])
            end)

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
-- named "arena"/"temple", so travel is keyed off arenaProfile == "2".

describe("ring-gong-and-fight-in-arena 2", function()

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

        it("sets arenaProfile to '2'", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 2")
            assert.are.equal("2", taPackage.arenaProfile)
        end)

        it("starts ringing and scans the room like the first arena", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 2")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateAlias("ring-gong-and-fight-in-arena 2")
            assert.is_nil(taPackage.arenaState)
        end)

        it("the bare alias leaves profile '1' (not '2')", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena")
            assert.are.equal("1", taPackage.arenaProfile)
        end)

    end)

    describe("stop alias", function()

        it("clears profile, journey, and state", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaJourney = { steps = { "s" }, index = 0, arriveRoom = "temple" }
            taPackage.arenaState = "fighting"
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaProfile)
            assert.is_nil(taPackage.arenaJourney)
            assert.is_nil(taPackage.arenaState)
        end)

    end)

    describe("travel to the temple to heal", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "2"
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
            assert.is_not_nil(stepTimer)  -- the pacing timer was armed
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
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "2"
        end)

        it("walks back to the arena, starting with north", function()
            taPackage.arenaState = "healing"
            taPackage.character.gold = 500
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
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "2"
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
            taPackage.arenaProfile = "2"
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
            taPackage.arenaProfile = "1"
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
            taPackage.arenaProfile = "2"
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
            taPackage.arenaProfile = "2"
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
            taPackage.arenaProfile = "2"
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
-- ring-gong-and-fight-in-arena 3
--
-- Same shared combat/XP/potion engine as the other two, but a new combination:
-- paced-route navigation (like the second arena) AND a training hall (like the
-- first). Its temple/bar/shop/guild-hall are distant, reached by fixed
-- direction step-lists (ARENA_NAV["3"]); a banked level walks a paced route to
-- the "guild hall" rather than the first arena's room-name trip.
-- =========================================================================
describe("ring-gong-and-fight-in-arena 3", function()

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

        it("sets arenaProfile to '3'", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 3")
            assert.are.equal("3", taPackage.arenaProfile)
        end)

        it("starts ringing and scans the room like the other arenas", function()
            helper.simulateAlias("ring-gong-and-fight-in-arena 3")
            assert.are.equal("ringing", taPackage.arenaState)
            assert.are.equal("", helper.sendCalls[1])
            assert.is_true(taPackage.arenaProbePending)
        end)

        it("does not start when class is unknown", function()
            setClass(nil)
            helper.simulateAlias("ring-gong-and-fight-in-arena 3")
            assert.is_nil(taPackage.arenaState)
        end)

    end)

    describe("stop alias", function()

        it("clears profile, journey, and state", function()
            taPackage.arenaProfile = "3"
            taPackage.arenaJourney = { steps = { "sw" }, index = 0, arriveRoom = "temple" }
            taPackage.arenaState = "fighting"
            helper.simulateAlias("stop-arena-fight")
            assert.is_nil(taPackage.arenaProfile)
            assert.is_nil(taPackage.arenaJourney)
            assert.is_nil(taPackage.arenaState)
        end)

    end)

    describe("travel to the temple to heal", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "3"
        end)

        it("flees toward the temple with the first step 'sw'", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        -- The third arena's threshold is banded on MAX vitality, not a
        -- percentage: under 500 max flee on any damage at all; 500-600 max flee
        -- below 500; 600-800 max flee below 600; over 800 max the percentage
        -- rule (75%) takes back over. The 400 floor is dead here, and the
        -- percentage is dead in every band but the top one — the cases below
        -- pick HP where the rules answer differently, so a regression fails.

        -- Smallest band: 450 max, so the threshold is 450 and a single point of
        -- damage puts us under it. 449 is way above both 75% (337) and 400.
        it("flees on a single point of damage under 500 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(449, 450)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("keeps fighting at full health under 500 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(450, 450)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- Middle band: 550 max flees below 500. 499 is above 75% (412) and above
        -- the old 400 floor, so only the band can trigger this.
        it("flees below 500 for a 500-600 max HP character", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(499, 550)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("keeps fighting at exactly 500 for a 500-600 max HP character", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(500, 550)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- 600 max sits in the middle band, not the high one: it flees below 500,
        -- so 550 keeps fighting. This is the boundary that is easy to get
        -- backwards.
        it("treats exactly 600 max HP as the 500 band", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(550, 600)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- Flat band: 600-800 max flees below 600. At 800 max the percentage rule
        -- would have said 600 too, so use 700 max, where 75% is 525 — fleeing at
        -- 599 can only be the band.
        it("flees below 600 for a character over 600 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(599, 700)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("keeps fighting at exactly 600 for a character over 600 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(600, 700)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- 800 max is the seam: 75% of 800 is 600, which is what the flat band
        -- says too, so both rules agree and 600 still keeps fighting.
        it("treats exactly 800 max HP as the 600 band", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(600, 800)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- Top band: over 800 max goes back to 75%. The live case is a 998-max
        -- Knight, where 75% is 748 — well above the flat 600 the band used to
        -- give, so fleeing at 747 can only be the percentage.
        it("flees at 75% of max for a character over 800 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(747, 998)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("keeps fighting at 75% of max for a character over 800 max HP", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(748, 998)  -- floor(998 * 0.75) = 748, and the test is strict <
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        -- The bands are third-arena only: the first arena still uses 75% and the
        -- absolute floor, so a 450 max character there fights on at 400.
        it("leaves the first arena on the percentage rule", function()
            taPackage.arenaProfile = "1"
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(400, 450)  -- above 75% of 450 (337), so no flee
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fighting", taPackage.arenaState)
        end)

        it("buys healing on arriving at the temple", function()
            taPackage.arenaState = "fleeing"
            taPackage.arenaJourney = { steps = { "sw", "se", "ne", "e" }, index = 4, arriveRoom = "temple" }
            helper.simulateLine("You're in the temple.")
            assert.are.equal("healing", taPackage.arenaState)
            assert.are.equal("buy healing", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaJourney)
        end)

        -- Regression: the real flee leg threads through "You're in an underground
        -- plaza." rooms (article "an"), which the "in the" movement trigger never
        -- matched — so the walk wedged after the first "sw" and never advanced (the
        -- 2026-07-18 flee log). Drive the whole leg one arrival at a time to prove
        -- every "an underground plaza" hop now counts and schedules the next step.
        it("walks the full flee leg through 'an underground plaza' hops to the temple", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(10, 100)
            helper.simulateLine("Your attack hit the cave bear for 5 damage!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])

            helper.simulateLine("You're in an underground plaza.")
            stepTimer.cb()
            assert.are.equal("se", helper.sendCalls[#helper.sendCalls])

            helper.simulateLine("You're in the town square.")
            stepTimer.cb()
            assert.are.equal("ne", helper.sendCalls[#helper.sendCalls])

            helper.simulateLine("You're in an underground plaza.")
            stepTimer.cb()
            assert.are.equal("e", helper.sendCalls[#helper.sendCalls])

            helper.simulateLine("You're in the temple.")
            assert.are.equal("healing", taPackage.arenaState)
            assert.are.equal("buy healing", helper.sendCalls[#helper.sendCalls])
            assert.is_nil(taPackage.arenaJourney)
        end)

        it("walks back to the arena starting 'w' after healing", function()
            taPackage.arenaState = "healing"
            taPackage.character.gold = 500
            helper.simulateLine("The priests heal all your wounds for 3 crowns.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
            assert.are.equal("arena", taPackage.arenaJourney.arriveRoom)
        end)

    end)

    describe("travel to the bar (tavern) to eat and drink", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "3"
        end)

        it("departs for the tavern with the first step 'sw' when thirsty", function()
            taPackage.arenaState = "fighting"
            helper.simulateLine("You're thirsty.")
            assert.are.equal("tavern", taPackage.arenaState)
            assert.is_true(taPackage.needsDrinks)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys a drink on arriving at the tavern, then walks back 'se'", function()
            taPackage.arenaState = "tavern"
            taPackage.needsDrinks = true
            taPackage.arenaJourney = { steps = { "sw", "nw" }, index = 2, arriveRoom = "tavern" }
            helper.simulateLine("You're in the tavern.")
            local drinks = 0
            for _, c in ipairs(helper.sendCalls) do
                if c == "buy drink" then drinks = drinks + 1 end
            end
            assert.are.equal(1, drinks)
            assert.is_nil(taPackage.needsDrinks)
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("se", helper.sendCalls[#helper.sendCalls])
        end)

    end)

    describe("training hall (paced route, unlike the second arena)", function()

        local stepTimer

        before_each(function()
            _G.createTimer = function(interval, cb, opts)
                if interval == taPackage.arenaStepDelayMs then stepTimer = { cb = cb } end
                return "mock_timer"
            end
            stepTimer = nil
            taPackage.arenaProfile = "3"
        end)

        -- HP kept well above the third arena's 500 flee floor (75% of 1000 = 750),
        -- so the monster-death handler trains rather than fleeing first.
        it("walks the paced route to the guild hall on a banked level (first step 'sw')", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(900, 1000)
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 0  -- clean, so it may train
            helper.simulateLine("The cave bear falls to the ground lifeless!")
            assert.are.equal("training", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
            assert.are.equal("guild hall", taPackage.arenaJourney.arriveRoom)
        end)

        -- Third arena's temple detour uses its own route, not the first arena's:
        -- toTemple = { "sw", "se", "ne", "e" }.
        it("walks the paced route to the temple while a stat potion is still active", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaMonster = "cave bear"
            setHP(900, 1000)
            taPackage.character.experience = 1120
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.arenaPotionsActive = 1  -- tainted; hall would refuse
            helper.simulateLine("The cave bear falls to the ground lifeless!")
            assert.are.equal("restoring", taPackage.arenaState)
            assert.are.equal("temple", taPackage.arenaJourney.arriveRoom)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("buys training on arriving at the guild hall, then walks home 's'", function()
            taPackage.arenaState = "training"
            taPackage.arenaJourney = { steps = { "sw", "se", "ne", "n" }, index = 4, arriveRoom = "guild hall" }
            helper.simulateLine("You're in the guild hall.")
            assert.are.equal("buy training", helper.sendCalls[1])
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
            assert.are.equal("arena", taPackage.arenaJourney.arriveRoom)
        end)

        it("does not use the first-arena room-name training (no 'w' phase)", function()
            taPackage.arenaState = "training"
            taPackage.arenaJourney = { steps = { "sw", "se", "ne", "n" }, index = 1, arriveRoom = "guild hall" }
            helper.simulateLine("You're in the east plaza.")  -- intermediate step
            assert.is_not_nil(stepTimer)
            stepTimer.cb()
            assert.are.equal("se", helper.sendCalls[#helper.sendCalls])  -- next paced step, not "buy training"
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
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
            assert.is_true(taPackage.needsPotions)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])
        end)

        it("heads to the shop (first arena, first step 'w') when fighting", function()
            taPackage.arenaProfile = "1"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])
        end)

        it("heads to the shop (third arena, first step 'sw') when fighting", function()
            taPackage.arenaProfile = "3"
            taPackage.arenaState = "fighting"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("sw", helper.sendCalls[#helper.sendCalls])
        end)

        it("departs when the tingle fires while ringing", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "ringing"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("potions", taPackage.arenaState)
        end)

        it("just flags when the tingle fires mid-trip (e.g. fleeing)", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "fleeing"
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("fleeing", taPackage.arenaState)
            assert.is_true(taPackage.needsPotions)
        end)

        it("does not double-depart on the second potion's tingle line", function()
            taPackage.arenaProfile = "2"
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

        it("decrements the active-potion count on each wear-off", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "fighting"
            taPackage.arenaPotionsActive = 2
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal(1, taPackage.arenaPotionsActive)
        end)

        -- When a level is owed we deliberately let the potions lapse (the hall
        -- refuses a potion-tainted character), so a wear-off must NOT trigger a
        -- restock — we drain and keep fighting instead.
        it("drains instead of restocking when a level is owed", function()
            taPackage.arenaProfile = "1"
            taPackage.arenaState = "fighting"
            taPackage.character.class = "Rogue"
            taPackage.character.level = 1
            taPackage.character.experience = 1120  -- Rogue level 2 threshold
            taPackage.arenaPotionsActive = 2
            helper.simulateLine("An odd tingling sensation washes over you briefly!")
            assert.are.equal("fighting", taPackage.arenaState)  -- no shop trip
            assert.is_nil(taPackage.arenaJourney)
            assert.is_nil(taPackage.needsPotions)
            assert.are.equal(1, taPackage.arenaPotionsActive)  -- one drained
            assert.are.equal(0, #helper.sendCalls)
        end)

    end)

    describe("arriving at the shop", function()

        it("re-buys and re-drinks both potions, then walks back (second arena)", function()
            taPackage.arenaProfile = "2"
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
            taPackage.arenaProfile = "1"
            taPackage.arenaState = "potions"
            taPackage.arenaJourney = { steps = { "w", "s", "s" }, index = 3, arriveRoom = "magic shop" }
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("n", helper.sendCalls[#helper.sendCalls])
        end)

        it("walks back on the third-arena route (starts 'nw')", function()
            taPackage.arenaProfile = "3"
            taPackage.arenaState = "potions"
            taPackage.arenaJourney = { steps = { "sw", "se", "se", "se" }, index = 4, arriveRoom = "magic shop" }
            helper.simulateLine("You're in the magic shop.")
            assert.are.equal("returning", taPackage.arenaState)
            assert.are.equal("nw", helper.sendCalls[#helper.sendCalls])
        end)

        it("treats an intermediate room as a step, not the shop", function()
            taPackage.arenaProfile = "1"
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
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "returning"
            taPackage.arenaMonster = "troll"
            taPackage.arenaJourney = { steps = { "n" }, index = 1, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("fighting", taPackage.arenaState)
            assert.are.equal("a troll", helper.sendCalls[#helper.sendCalls])
        end)

        it("makes the shop trip after healing when a potion also wore off", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.arenaJourney = { steps = { "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("s", helper.sendCalls[#helper.sendCalls])  -- first step to the shop
        end)

        it("does the shop before food when both are owed", function()
            taPackage.arenaProfile = "2"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.needsDrinks = true
            taPackage.arenaJourney = { steps = { "n" }, index = 4, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
        end)

        -- The first arena walks home by journey too now, so a potion that wore
        -- off mid-errand is serviced on arrival exactly as it is for the others.
        it("services a deferred potion run when the first arena walks home", function()
            taPackage.arenaProfile = "1"
            taPackage.arenaState = "returning"
            taPackage.needsPotions = true
            taPackage.arenaJourney = { steps = { "e", "e" }, index = 2, arriveRoom = "arena" }
            helper.simulateLine("You're in the arena.")
            assert.are.equal("potions", taPackage.arenaState)
            assert.are.equal("w", helper.sendCalls[#helper.sendCalls])  -- first step of the shop route
        end)

    end)

    it("stop clears needsPotions", function()
        taPackage.arenaProfile = "2"
        taPackage.needsPotions = true
        taPackage.arenaState = "potions"
        helper.simulateAlias("stop-arena-fight")
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
        taPackage.arenaProfile = "2"
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

describe("spell-name translation aliases", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
    end)

    -- Targeted spells: alias <target> -> cast <intoned> <target>.
    local targeted = {
        ["cast-minor-heal"]       = "motu",
        ["cast-heal"]             = "kamotu",
        ["cast-minor-hurt"]       = "tami",
        ["cast-cure-poison"]      = "dobudani",
        ["cast-greater-heal"]     = "gimotu",
        ["cast-hurt"]             = "katami",
        ["cast-deific-heal"]      = "kusamotu",
        ["cast-greater-hurt"]     = "gitami",
        ["cast-remove-paralysis"] = "takumi",
        ["cast-deific-hurt"]      = "kusatami",
        ["cast-restore-stats"]    = "ganazi",
    }

    for alias, spell in pairs(targeted) do
        it(alias .. " <target> sends cast " .. spell .. " <target>", function()
            helper.simulateAlias(alias .. " tojolias")
            assert.are.equal("cast " .. spell .. " tojolias", helper.sendCalls[1])
            assert.are.equal(1, #helper.sendCalls)
        end)
    end

    -- Area spells: alias (no target) -> cast <intoned>.
    local area = {
        ["cast-minor-heal-area"]   = "motumaru",
        ["cast-heal-area"]         = "kamotumaru",
        ["cast-cure-poison-area"]  = "dobudanimaru",
        ["cast-greater-heal-area"] = "gimotumaru",
        ["cast-deific-heal-area"]  = "kusamotumaru",
    }

    for alias, spell in pairs(area) do
        it(alias .. " sends bare cast " .. spell, function()
            helper.simulateAlias(alias)
            assert.are.equal("cast " .. spell, helper.sendCalls[1])
            assert.are.equal(1, #helper.sendCalls)
        end)
    end

    -- The area alias must not also fire the same-stem targeted alias, and
    -- vice-versa (they differ only by a trailing "-area" vs a space + target).
    it("does not fire the targeted alias for an area cast", function()
        helper.simulateAlias("cast-minor-heal-area")
        assert.are.equal(1, #helper.sendCalls)
        assert.are.equal("cast motumaru", helper.sendCalls[1])
    end)

    it("does not fire the area alias for a targeted cast", function()
        helper.simulateAlias("cast-minor-heal tojolias")
        assert.are.equal(1, #helper.sendCalls)
        assert.are.equal("cast motu tojolias", helper.sendCalls[1])
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

        it("'k <monster>' shorthand behaves like 'kill <monster>'", function()
            helper.simulateAlias("k cave lizard")
            assert.is_true(taPackage.killActive)
            assert.are.equal("cave lizard", taPackage.killTarget)
            assert.are.equal("a cave", helper.sendCalls[1])
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

        it("kill-stop clears state", function()
            helper.simulateAlias("kill cave lizard")
            helper.simulateAlias("kill-stop")
            assert.is_falsy(taPackage.killActive)
            assert.is_nil(taPackage.killTarget)
        end)

        describe("kill-all", function()
            it("sends a bare return to probe the room", function()
                helper.simulateAlias("kill-all")
                assert.are.equal("", helper.sendCalls[1])
                assert.is_true(taPackage.killAllActive)
            end)

            it("engages the first monster from the room brief", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("You're in a flagstone corridor.")
                helper.simulateLine("There is a warlock here.")
                helper.simulateLine("Tojolias is here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("warlock", taPackage.killTarget)
            end)

            it("ignores player lines and never targets a player", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("Tojolias is here.")
                assert.is_falsy(taPackage.killActive)
                assert.is_nil(taPackage.killTarget)
            end)

            it("de-pluralises a monster count", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There are three warlocks here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("warlock", taPackage.killTarget)
            end)

            it("de-pluralises a multi-word monster count", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There are three ogre mages here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("ogre mage", taPackage.killTarget)
            end)

            it("de-pluralises an irregular -i plural", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There are two affreeti here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("affreet", taPackage.killTarget)
            end)

            it("targets the first of a mixed monster list, then the rest", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("You're in an enormous chamber.")
                helper.simulateLine("There are three warlocks, and a stone giantess here.")
                helper.simulateLine("Tojolias is here.")
                helper.simulateLine("There is nothing on the floor.")
                helper.simulateLine("Tojolias has just gone to the north.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("warlock", taPackage.killTarget)
                -- Clear the three warlocks; each death re-scans the room.
                helper.simulateLine("The warlock falls to the ground lifeless!")
                helper.simulateLine("There are two warlocks, and a stone giantess here.")
                helper.simulateLine("The warlock falls to the ground lifeless!")
                helper.simulateLine("There is a warlock, and a stone giantess here.")
                helper.simulateLine("The warlock falls to the ground lifeless!")
                -- Only the giantess remains; she is not a count, so no strip.
                helper.simulateLine("There is a stone giantess here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("stone giantess", taPackage.killTarget)
            end)

            it("ignores the floor line and targets the monster", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("You're in an enormous chamber.")
                helper.simulateLine("There are two stygian dragons here.")
                helper.simulateLine("Tojolias is here.")
                helper.simulateLine("There is nothing on the floor.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("stygian dragon", taPackage.killTarget)
                assert.is_true(taPackage.killAllActive)
            end)

            it("re-scans and re-engages after a monster dies", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There are three warlocks here.")
                helper.sendCalls = {}
                helper.simulateLine("The warlock falls to the ground lifeless!")
                -- The death re-scans the room...
                assert.are.equal("", helper.sendCalls[1])
                assert.is_true(taPackage.killAllActive)
                -- ...and the brief with one fewer warlock re-engages it.
                helper.simulateLine("There are two warlocks here.")
                assert.is_true(taPackage.killActive)
                assert.are.equal("warlock", taPackage.killTarget)
            end)

            it("ends the sweep when the room is clear", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There is a warlock here.")
                helper.simulateLine("The warlock falls to the ground lifeless!")
                helper.simulateLine("There is nobody here.")
                assert.is_falsy(taPackage.killAllActive)
                assert.is_falsy(taPackage.killActive)
            end)

            it("does not start when an arena session is active", function()
                taPackage.arenaState = "fighting"
                helper.sendCalls = {}
                helper.simulateAlias("kill-all")
                assert.is_falsy(taPackage.killAllActive)
                assert.are.equal(0, #helper.sendCalls)
            end)

            it("kill-stop halts an in-progress sweep", function()
                helper.simulateAlias("kill-all")
                helper.simulateLine("There is a warlock here.")
                helper.simulateAlias("kill-stop")
                assert.is_falsy(taPackage.killAllActive)
                assert.is_falsy(taPackage.killActive)
                -- A later death line must not restart the sweep.
                helper.sendCalls = {}
                helper.simulateLine("The warlock falls to the ground lifeless!")
                assert.are.equal(0, #helper.sendCalls)
            end)
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

        -- Team mode rides on the same session as a solo arena run, so the one
        -- stopArena teardown covers it — but a leftover arenaTeam flag would make
        -- the NEXT solo run silently cooperative, so assert it is cleared too.
        it("clears team-mode state along with the arena session", function()
            taPackage.arenaState = "fighting"
            taPackage.arenaTeam = true
            taPackage.arenaTeamRoster = { "Pelayo" }
            taPackage.arenaTeamSlot = 2
            helper.simulateAlias("stop-all-scripts")
            assert.is_nil(taPackage.arenaTeam)
            assert.is_nil(taPackage.arenaTeamRoster)
            assert.is_nil(taPackage.arenaTeamSlot)
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
            assert.is_true(echoed("[all] Stopped hang-around-in-tavern-and-deposit-gold."))
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
            assert.is_true(echoed("[all] hang-around-in-tavern-and-deposit-gold not running."))
        end)

        it("reports a mix of stopped and not-running scripts", function()
            taPackage.killActive = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_true(echoed("[all] Stopped kill."))
            assert.is_true(echoed("[all] arena not running."))
        end)

        it("stops the train-and-exit watch too", function()
            taPackage.trainWatch = { triggers = {} }
            helper.simulateAlias("stop-all-scripts")
            assert.is_nil(taPackage.trainWatch)
            assert.is_true(echoed("[all] Stopped train-and-exit."))
        end)

        it("stops character creation too", function()
            taPackage.creating = true
            taPackage.createRerollPending = true
            helper.simulateAlias("stop-all-scripts")
            assert.is_false(taPackage.creating)
            assert.is_nil(taPackage.createRerollPending)
            assert.is_true(echoed("[all] Stopped gold-farming."))
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

    it("badges a hydra's fireball special attack", function()
        assertIncomingHit("The hydra expelled a ball of fire at you for 78 damage!", " TOOK 78 ")
    end)

    it("does not badge a special attack that lands on a party member", function()
        helper.simulateLine("The stone giant hurled a boulder at Pelayo!")
        assert.are.equal(0, #helper.cechoBgCalls)
    end)

    -- Healing we cast: green, to distinguish it from blue damage-dealt. The
    -- target is uppercased to match the shouty HIT/TOOK style.
    it("echoes a green HEALED badge naming the target and amount", function()
        helper.simulateLine("You intoned the spell for Pelayo which healed 13 damage!")
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(" HEALED PELAYO FOR 13 ", badge.text)
        assert.are.equal("#16a34a", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end)

    it("echoes a green HEALED BY badge when a party member minor-heals us", function()
        helper.simulateLine("Pelayo just intoned a minor healing spell for you which healed 6 damage!")
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(" HEALED BY PELAYO FOR 6 ", badge.text)
        assert.are.equal("#16a34a", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end)

    it("echoes a green HEALED BY badge when a party member heals us", function()
        helper.simulateLine("Pelayo just intoned a healing spell for you which healed 14 damage!")
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(" HEALED BY PELAYO FOR 14 ", badge.text)
        assert.are.equal("#16a34a", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end)

    it("echoes a green HEALED BY badge for a wrapped very-powerful heal", function()
        helper.simulateLine("Pelayo just intoned a very powerful healing spell for you which healed 129")
        local badge = lastBadge()
        assert.is_not_nil(badge)
        assert.are.equal(" HEALED BY PELAYO FOR 129 ", badge.text)
        assert.are.equal("#16a34a", badge.color)
        assert.are.equal("#e0e0e0", badge.backgroundColor)
        assert.is_true(badge.bold)
    end)

    -- The area heals print one line with the amount everyone got. We badge it
    -- and credit our own vitality without an "st" round trip.
    describe("area heal we cast", function()
        before_each(function()
            helper.simulateLine("Vitality:     50 / 200")
        end)

        it("echoes a green HEALED GROUP badge with the amount", function()
            helper.simulateLine(
                "You discharged the spell at friendly people in the area, healing 104 damage!")
            local badge = lastBadge()
            assert.is_not_nil(badge)
            assert.are.equal(" HEALED GROUP FOR 104 ", badge.text)
            assert.are.equal("#16a34a", badge.color)
            assert.are.equal("#e0e0e0", badge.backgroundColor)
            assert.is_true(badge.bold)
        end)

        it("adds the healed amount to our vitality", function()
            helper.simulateLine(
                "You discharged the spell at friendly people in the area, healing 104 damage!")
            assert.are.equal(154, taPackage.character.vitalityCurrent)
            assert.are.equal(200, taPackage.character.vitalityMax)
        end)

        it("clamps the gain at max vitality", function()
            helper.simulateLine("Vitality:     180 / 200")
            helper.simulateLine(
                "You discharged the spell at friendly people in the area, healing 104 damage!")
            assert.are.equal(200, taPackage.character.vitalityCurrent)
        end)

        it("does not fire for a non-heal area spell", function()
            helper.simulateLine("You discharged the spell at friendly people in the area!")
            assert.are.equal(0, #helper.cechoBgCalls)
            assert.are.equal(50, taPackage.character.vitalityCurrent)
        end)
    end)

    -- Receiving someone else's area heal names no amount, so we stash HP, ask
    -- for "st", and recover the gain from the fresh Vitality line.
    describe("area heal cast on us", function()
        local CAST = "Pelayo just discharged a very dark bluish mist at friendly people in the area!"

        before_each(function()
            helper.simulateLine("Vitality:     50 / 200")
        end)

        it("stashes HP and requests a status check", function()
            helper.simulateLine(CAST)
            assert.are.equal(50, taPackage.groupHealHpBefore)
            assert.are.equal("Pelayo", taPackage.groupHealCaster)
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("badges the HP gained once the status returns", function()
            helper.simulateLine(CAST)
            helper.simulateLine("Vitality:     154 / 200")
            local badge = lastBadge()
            assert.are.equal(" HEALED BY PELAYO FOR 104 ", badge.text)
            assert.are.equal("#16a34a", badge.color)
            assert.are.equal("#e0e0e0", badge.backgroundColor)
            assert.is_true(badge.bold)
            assert.is_nil(taPackage.groupHealHpBefore)
        end)

        it("matches the lesser mist tiers and any caster", function()
            helper.simulateLine("Tojolias just discharged a bluish mist at friendly people in the area!")
            assert.are.equal("Tojolias", taPackage.groupHealCaster)
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("matches a wrapped first line", function()
            helper.simulateLine("Pelayo just discharged a very dark bluish mist at friendly people in the")
            assert.are.equal(50, taPackage.groupHealHpBefore)
            assert.are.equal("st", helper.sendCalls[#helper.sendCalls])
        end)

        it("does not badge when a non-heal area spell leaves HP unchanged", function()
            helper.simulateLine("Pelayo just discharged a thick greyish mist at friendly people in the area!")
            helper.simulateLine("Vitality:     50 / 200")
            assert.are.equal(0, #helper.cechoBgCalls)
        end)

        it("does not badge our own cast as an incoming heal", function()
            helper.simulateLine(
                "You discharged the spell at friendly people in the area, healing 104 damage!")
            assert.is_nil(taPackage.groupHealHpBefore)
        end)
    end)

    -- Traps print no damage number; we stash HP, ask for "st", and recover the
    -- loss from the fresh Vitality line.
    describe("trap badges", function()
        local TRAPS = {
            "A spiked trap catches your foot and pain shoots up your leg!",
            "Several crossbow bolts fire from holes in the walls, striking you!",
            "Several large stones fall on you from above!",
            "A huge stone block slams down on you from above!",
            "A scything blade slices into your stomach!",
            "A ball of flame explodes from an opening in the wall and engulfs you!",
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
-- hang-around-in-tavern-and-deposit-gold
-- =========================================================================

describe("hang-around-in-tavern-and-deposit-gold", function()

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
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_falsy(taPackage.tavernMode)
        end)

        it("enters tavern mode when the room is a tavern", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_true(taPackage.tavernMode)
        end)

        it("also accepts a bar room", function()
            taPackage.currentRoom = "village bar"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_true(taPackage.tavernMode)
        end)

        it("primes status on start", function()
            taPackage.currentRoom = "village tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            local statused = false
            for _, cmd in ipairs(helper.sendCalls) do
                if cmd == "st" then statused = true end
            end
            assert.is_true(statused)
        end)

        -- A `look` here would be pure noise: send() is asynchronous, so its
        -- reply can't reach the room check that already ran, and a look's
        -- opening line is deliberately never treated as an arrival.
        it("does not send a look on start", function()
            taPackage.currentRoom = "village tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("look", cmd)
            end
        end)

        -- The room name has to be tracked outside mapping mode, or an ordinary
        -- session never knows where it is and the alias always refuses.
        it("starts after simply walking in, with mapping off", function()
            taPackage.mapping = false
            taPackage.currentRoom = nil
            helper.simulateLine("You're in the tavern.")
            assert.are.equal("tavern", taPackage.currentRoom)
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_true(taPackage.tavernMode)
        end)

    end)

    -- The second half of the name. Idling in the tavern is the situation gold
    -- arrives in, so the two are armed and disarmed together.
    describe("banking", function()

        it("arms banking on start", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_true(taPackage.bankingRunning())
        end)

        it("does not arm banking when the room is refused", function()
            taPackage.currentRoom = "north plaza"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            assert.is_false(taPackage.bankingRunning())
        end)

        it("deposits gold that arrives while hanging around", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.sendCalls = {}
            helper.simulateLine("Garbageman just gave you 822 gold coins.")
            assert.are.equal("sw", helper.sendCalls[1])
        end)

        it("disarms banking on stop", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.simulateAlias("stop-hang-around-in-tavern-and-deposit-gold")
            assert.is_false(taPackage.bankingRunning())
        end)

        -- Logged out, so nothing should still be walking to the vaults.
        it("disarms banking when it exits the game", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.simulateLine("Vitality:     29 / 60")
            assert.is_false(taPackage.bankingRunning())
        end)

        it("disarms banking via stop-all-scripts", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.simulateAlias("stop-all-scripts")
            assert.is_false(taPackage.bankingRunning())
        end)

    end)

    describe("stopping", function()

        it("leaves tavern mode without exiting the game", function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.sendCalls = {}
            helper.simulateAlias("stop-hang-around-in-tavern-and-deposit-gold")
            assert.is_false(taPackage.tavernMode)
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

    end)

    describe("eating and drinking", function()

        before_each(function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
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
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
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
            helper.simulateAlias("stop-hang-around-in-tavern-and-deposit-gold")
            helper.sendCalls = {}
            helper.simulateLine("Vitality:     5 / 60")
            for _, cmd in ipairs(helper.sendCalls) do
                assert.are_not.equal("x", cmd)
            end
        end)

    end)

    -- How long it has been up, how much gold has arrived, and the rate. The
    -- rate is the figure the run exists to produce, so every place that reports
    -- has a test: gold arriving, the 10-minute heartbeat, stopping, and quitting.
    describe("session accounting", function()

        local function echoed(needle)
            for _, text in ipairs(helper.echoCalls) do
                if text:find(needle, 1, true) then return true end
            end
            return false
        end

        before_each(function()
            taPackage.currentRoom = "tavern"
            helper.simulateAlias("hang-around-in-tavern-and-deposit-gold")
            helper.echoCalls = {}
        end)

        -- Backdate the start so the elapsed time is a known quantity. os.time()
        -- is the real clock here, and a test that ran in zero seconds could
        -- never exercise the rate at all.
        local function ageBy(seconds)
            taPackage.tavernStartTime = os.time() - seconds
        end

        it("starts the clock and the total at zero", function()
            assert.are.equal(0, taPackage.tavernGoldReceived)
            assert.is_truthy(taPackage.tavernStartTime)
        end)

        it("totals the gold that arrives", function()
            helper.simulateLine("Garbageman just gave you 822 gold coins.")
            helper.simulateLine("Garbageman just gave you 178 gold coins.")
            assert.are.equal(1000, taPackage.tavernGoldReceived)
        end)

        it("reports uptime, running total and rate when gold arrives", function()
            ageBy(3600)
            helper.simulateLine("Garbageman just gave you 1200 gold coins.")
            assert.is_true(echoed("+1200 gold from Garbageman"))
            assert.is_true(echoed("up 1h 0m"))
            assert.is_true(echoed("1,200 gold received"))
            assert.is_true(echoed("20.0 gold/min"))
        end)

        -- Under a minute there is no honest rate to quote: the first handover
        -- divided by a few seconds reads as tens of thousands per minute.
        it("withholds the rate in the first minute", function()
            helper.simulateLine("Garbageman just gave you 822 gold coins.")
            assert.is_true(echoed("rate n/a yet"))
        end)

        it("checks in on the status heartbeat", function()
            ageBy(1800)
            helper.simulateLine("Garbageman just gave you 900 gold coins.")
            helper.echoCalls = {}
            helper.fireTimers(600000)
            assert.is_true(echoed("up 30m, 900 gold received (30.0 gold/min)"))
        end)

        it("reports the session when stopped", function()
            ageBy(600)
            helper.simulateLine("Garbageman just gave you 300 gold coins.")
            helper.echoCalls = {}
            helper.simulateAlias("stop-hang-around-in-tavern-and-deposit-gold")
            assert.is_true(echoed("Session: up 10m, 300 gold received (30.0 gold/min)"))
        end)

        it("reports the session when it leaves the game", function()
            ageBy(600)
            helper.simulateLine("Garbageman just gave you 300 gold coins.")
            helper.echoCalls = {}
            helper.simulateLine("Vitality:     29 / 60")
            assert.is_true(echoed("Session: up 10m, 300 gold received (30.0 gold/min)"))
        end)

        it("does not count gold when not hanging around", function()
            helper.simulateAlias("stop-hang-around-in-tavern-and-deposit-gold")
            helper.simulateLine("Garbageman just gave you 822 gold coins.")
            assert.are.equal(0, taPackage.tavernGoldReceived)
        end)

    end)

end)

describe("message-me-when-you-see", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.name = "Grond"
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
            "Heads up- Grond just saw: odd tingling sensation washes over",
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
            "Heads up- Grond just saw: odd tingling sensation washes over",
            helper.httpRequestCalls[1].options.body)
    end)

    it("falls back to ? when the character name isn't known yet", function()
        taPackage.character.name = nil
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(
            "Heads up- ? just saw: odd tingling sensation washes over",
            helper.httpRequestCalls[1].options.body)
    end)

    it("stays silent until the phrase actually appears", function()
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("Nothing unusual happens.")
        assert.are.equal(0, #helper.httpRequestCalls)
    end)

    it("does not exit the game", function()
        helper.simulateAlias('message-me-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(0, #helper.sendCalls)
    end)

end)

describe("message-me-and-exit-when-you-see", function()

    local timers

    before_each(function()
        helper.resetAll()
        timers = {}
        _G.createTimer = function(interval, cb, opts)
            table.insert(timers, { interval = interval, cb = cb, opts = opts })
            return "mock_timer"
        end
        dofile("main.lua")
        taPackage.character.name = "Grond"
    end)

    local function countX()
        local n = 0
        for _, cmd in ipairs(helper.sendCalls) do
            if cmd == "x" then n = n + 1 end
        end
        return n
    end

    it("notifies and leaves the game when the phrase is seen", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        assert.are.equal(0, #helper.httpRequestCalls)
        assert.are.equal(0, countX())

        helper.simulateLine("An odd tingling sensation washes over you briefly!")

        assert.are.equal(1, #helper.httpRequestCalls)
        local call = helper.httpRequestCalls[1]
        assert.are.equal("message-me-and-exit-when-you-see",
            call.options.headers["X-Title"])
        assert.are.equal(
            "Heads up- Grond just saw: odd tingling sensation washes over",
            call.options.body)
        assert.are.equal(1, countX())
        assert.is_true(taPackage.exitGamePending)
        assert.are.equal(2000, timers[#timers].interval)
    end)

    it("re-sends x when the retry timer fires (still rest-blocked)", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, countX())

        helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
        timers[#timers].cb()
        assert.are.equal(2, countX())
        timers[#timers].cb()
        assert.are.equal(3, countX())
    end)

    it("stops retrying once the game confirms Exiting Tele-Arena...", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        local armed = timers[#timers]

        helper.simulateLine("Exiting Tele-Arena...")
        assert.is_false(taPackage.exitGamePending)
        armed.cb()
        assert.are.equal(1, countX())
    end)

    it("only fires once even if the phrase reappears", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("Exiting Tele-Arena...")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal(1, countX())
    end)

    it("accepts an unquoted phrase", function()
        helper.simulateAlias(
            "message-me-and-exit-when-you-see odd tingling sensation washes over")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal(1, countX())
    end)

    it("stays silent and stays put until the phrase appears", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("Nothing unusual happens.")
        assert.are.equal(0, #helper.httpRequestCalls)
        assert.are.equal(0, countX())
    end)

    it("does not also fire the non-exiting watcher alias", function()
        helper.simulateAlias(
            'message-me-and-exit-when-you-see "odd tingling sensation washes over"')
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal("message-me-and-exit-when-you-see",
            helper.httpRequestCalls[1].options.headers["X-Title"])
    end)

end)

describe("buy-potions", function()

    before_each(function()
        helper.resetAll()
        _G.createTimer = function() return "mock_timer" end
        dofile("main.lua")
    end)

    it("buys and drinks each stat potion in turn", function()
        helper.simulateAlias("buy-potions")
        assert.are.same(
            { "buy rowan", "drink rowan", "buy hyssop", "drink hyssop" },
            helper.sendCalls)
    end)

end)

describe("wait-for-potions-to-wear-off-and-exit", function()

    before_each(function()
        helper.resetAll()
        _G.createTimer = function() return "mock_timer" end
        dofile("main.lua")
        taPackage.character.name = "Grond"
    end)

    local function countX()
        local n = 0
        for _, cmd in ipairs(helper.sendCalls) do
            if cmd == "x" then n = n + 1 end
        end
        return n
    end

    it("notifies and leaves the game when a potion wears off", function()
        helper.simulateAlias("wait-for-potions-to-wear-off-and-exit")
        assert.are.equal(0, #helper.httpRequestCalls)
        assert.are.equal(0, countX())

        helper.simulateLine("An odd tingling sensation washes over you briefly!")

        assert.are.equal(1, #helper.httpRequestCalls)
        local call = helper.httpRequestCalls[1]
        assert.are.equal("wait-for-potions-to-wear-off-and-exit",
            call.options.headers["X-Title"])
        assert.are.equal(
            "Heads up- Grond just saw: An odd tingling sensation washes over",
            call.options.body)
        assert.are.equal(1, countX())
        assert.is_true(taPackage.exitGamePending)
    end)

    it("stays silent and stays put until a potion wears off", function()
        helper.simulateAlias("wait-for-potions-to-wear-off-and-exit")
        helper.simulateLine("Nothing unusual happens.")
        assert.are.equal(0, #helper.httpRequestCalls)
        assert.are.equal(0, countX())
    end)

    it("only fires once even if another potion wears off", function()
        helper.simulateAlias("wait-for-potions-to-wear-off-and-exit")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("Exiting Tele-Arena...")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal(1, countX())
    end)

end)

describe("train-and-exit-once-potions-wear-off", function()

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        taPackage.character.name = "Grond"
        setLevel(12)
        setGold(500)
    end)

    local function countSends(cmd)
        local n = 0
        for _, sent in ipairs(helper.sendCalls) do
            if sent == cmd then n = n + 1 end
        end
        return n
    end

    local function echoed(needle)
        for _, text in ipairs(helper.echoCalls) do
            if text:find(needle, 1, true) then return true end
        end
        return false
    end

    -- Run the alias and answer its bare return with the guild hall's brief.
    local function arm()
        helper.simulateAlias("train-and-exit-once-potions-wear-off")
        helper.simulateLine("You're in the guild hall.")
    end

    it("confirms the room off the bare return's brief before arming", function()
        helper.simulateAlias("train-and-exit-once-potions-wear-off")
        assert.are.equal(1, countSends(""))
        assert.is_false(echoed("[train] Waiting in the guild hall"))

        helper.simulateLine("You're in the guild hall.")
        assert.is_not_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] Waiting in the guild hall"))
    end)

    it("refuses to arm outside a guild hall", function()
        helper.simulateAlias("train-and-exit-once-potions-wear-off")
        helper.simulateLine("You're in the north plaza.")
        assert.is_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] Not in a guild hall (room: the north plaza)"))
        -- and a later potion expiry does nothing at all
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(0, countSends("buy training"))
        assert.are.equal(0, countSends("x"))
    end)

    -- A brief that never arrives (not in the game, wedged connection) must not
    -- leave us armed with no idea where we are standing.
    it("gives up when no room brief comes back", function()
        helper.simulateAlias("train-and-exit-once-potions-wear-off")
        helper.fireTimers()
        assert.is_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] No room brief came back"))
    end)

    it("keeps the armed watch when the confirmation timeout fires late", function()
        arm()
        helper.fireTimers()
        assert.is_not_nil(taPackage.trainWatch)
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, countSends("buy training"))
    end)

    -- The room brief only decides the arming; room lines during the long wait that
    -- follows are none of the watch's business.
    it("ignores room briefs once armed", function()
        arm()
        helper.simulateLine("You're in the north plaza.")
        assert.is_not_nil(taPackage.trainWatch)
    end)

    it("buys training when a potion wears off, then leaves the game", function()
        arm()
        assert.are.equal(0, countSends("buy training"))

        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, countSends("buy training"))
        -- Still in the game: we wait for the hall's verdict before exiting.
        assert.are.equal(0, countSends("x"))

        helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
        assert.are.equal(1, countSends("x"))
        assert.is_true(taPackage.exitGamePending)
        assert.is_nil(taPackage.trainWatch)
    end)

    -- The push waits on the character sheet the training trigger asks for. We
    -- send "st" before the watch's "x", so the game answers the sheet on its way
    -- out and the notification still carries the stat gains.
    it("banks the level and pushes the existing level-up notification", function()
        arm()
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
        assert.are.equal(13, getLevel())
        assert.are.equal(435, getGold()) -- 500 - 13 * 5
        helper.simulateLine("Vitality:     434 / 434")
        assert.are.equal(1, #helper.httpRequestCalls)
        assert.are.equal("Leveled Up!", helper.httpRequestCalls[1].options.headers["X-Title"])
        assert.is_true(helper.httpRequestCalls[1].options.body:find("[Grond] trained to level 13!", 1, true) ~= nil)
        assert.is_true(helper.httpRequestCalls[1].options.body:find("- New HP: 434", 1, true) ~= nil)
    end)

    -- Both stat potions are normally up, so the first tingle can still leave us
    -- tainted. Keep waiting rather than exiting without the level.
    it("keeps waiting when the hall says we are still tainted", function()
        arm()
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("Your mind and body must be whole and untainted before you may train.")
        assert.are.equal(0, countSends("x"))
        assert.is_not_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] Still potion-tainted"))

        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(2, countSends("buy training"))
        helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
        assert.are.equal(1, countSends("x"))
    end)

    it("only buys once while waiting for the hall's verdict", function()
        arm()
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, countSends("buy training"))
    end)

    it("leaves the game when no training is owed after all", function()
        arm()
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        helper.simulateLine("You are not ready for any further training, you must first prove")
        assert.are.equal(1, countSends("x"))
        assert.is_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] No training owed"))
    end)

    it("stops on stop-train-and-exit and stops listening", function()
        arm()
        helper.simulateAlias("stop-train-and-exit")
        assert.is_nil(taPackage.trainWatch)
        assert.is_true(echoed("[train] Stopped waiting to train."))
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(0, countSends("buy training"))
    end)

    it("does not arm a second watch when run twice", function()
        arm()
        helper.simulateAlias("train-and-exit-once-potions-wear-off")
        assert.is_true(echoed("[train] Already waiting to train"))
        helper.simulateLine("An odd tingling sensation washes over you briefly!")
        assert.are.equal(1, countSends("buy training"))
    end)

    -- Outside this watch (and outside an arena run) the training-success trigger
    -- must stay inert: nothing asked us to bank a level or leave the game.
    it("leaves the success line alone when no watch is armed", function()
        helper.simulateLine("After a rigorous mental and physical training session, you managed to blend")
        assert.are.equal(12, getLevel())
        assert.are.equal(0, #helper.httpRequestCalls)
        assert.are.equal(0, countSends("x"))
    end)

end)

describe("navigate-to", function()

    -- A miniature world, enough for the reference lookups and the room
    -- fingerprint probe. The two "north plaza" rooms are the point: they share a
    -- display name and differ only by exit-set, which is why the start check
    -- fingerprints rather than matching on the name.
    local AREAS = { { id = 1, slug = "first-town" }, { id = 7, slug = "second-town" },
                    { id = 8, slug = "sewers" }, { id = 14, slug = "third-town" } }
    local ROOMS = {
        [1]    = { id = 1,    slug = "north-plaza",          name = "north plaza",       area = 1,
                   exits = { "e", "n", "ne", "nw", "s", "w" } },
        [274]  = { id = 274,  slug = "north-plaza-1",        name = "north plaza",       area = 7,
                   exits = { "e", "n", "s", "sw", "w" } },
        [340]  = { id = 340,  slug = "town-sewers",          name = "town sewers",       area = 8,
                   exits = { "u", "se" } },
        -- Where the ruined-town route ends, so its `to` reference resolves.
        [966]  = { id = 966,  slug = "ruined-plaza",         name = "ruined plaza",      area = 1,
                   exits = { "n", "ne", "e", "s", "w", "nw" } },
        [359]  = { id = 359,  slug = "town-sewers-18",       name = "town sewers",       area = 8,
                   exits = { "e", "n", "s", "w" } },
        -- The junction the ruby, platinum and onyx doors open off, and where
        -- after-doors ends. Here so that route's `to` resolves.
        [426]  = { id = 426,  slug = "town-sewers-63",       name = "town sewers",       area = 8,
                   exits = { "e", "n", "s", "u", "w" } },
        -- The hydra's room: where the hydra leg ends and the stoneworks leg
        -- begins. Here so the hydra route's `to` resolves and it can be walked
        -- on its own.
        [543]  = { id = 543,  slug = "town-sewers-165",      name = "town sewers",       area = 8,
                   exits = { "n", "w" } },
        -- Slugs are numbered globally but references resolve within one area,
        -- so the room holding the bare `underground-plaza` slug can sit in a
        -- different town from its namesakes. That is what leaves third-town
        -- with two rooms sharing a name and neither answering to it.
        -- Where the third-town chain ends and the route home begins.
        [1011] = { id = 1011, slug = "town-square",          name = "town square",       area = 14,
                   exits = { "e", "ne", "nw", "se", "sw" } },
        [1012] = { id = 1012, slug = "underground-plaza",    name = "underground plaza", area = 1,  exits = {} },
        [1015] = { id = 1015, slug = "underground-plaza-1",  name = "underground plaza", area = 14, exits = {} },
        [1019] = { id = 1019, slug = "underground-plaza-2",  name = "underground plaza", area = 14, exits = {} },
    }

    local function areaIdBySlug(slug)
        for _, a in ipairs(AREAS) do if a.slug == slug then return a.id end end
        return nil
    end

    local function installWorld()
        helper.mockDbOneRow = function(sql, params)
            if string.find(sql, "FROM areas WHERE slug", 1, true) then
                local id = areaIdBySlug(params[1])
                return id and { id = id } or nil
            end
            if string.find(sql, "LEFT JOIN areas a ON a.id = r.area_id", 1, true) then
                local r = ROOMS[params[1]]
                if not r then return nil end
                for _, a in ipairs(AREAS) do
                    if a.id == r.area then return { slug = r.slug, area = a.slug } end
                end
                return { slug = r.slug, area = nil }
            end
            return nil
        end
        helper.mockDbRows = function(sql, params)
            if string.find(sql, "FROM rooms WHERE area_id", 1, true) then
                local out = {}
                for _, r in pairs(ROOMS) do
                    if r.area == params[1] then
                        out[#out + 1] = { id = r.id, slug = r.slug, name = r.name }
                    end
                end
                return out
            end
            if string.find(sql, "FROM rooms WHERE name", 1, true) then
                local out = {}
                for _, r in pairs(ROOMS) do
                    if r.name == params[1] then out[#out + 1] = { id = r.id, slug = r.slug } end
                end
                return out
            end
            if string.find(sql, "FROM room_exits WHERE from_id", 1, true) then
                local r = ROOMS[params[1]]
                local out = {}
                for _, d in ipairs(r and r.exits or {}) do out[#out + 1] = { direction = d } end
                return out
            end
            if string.find(sql, "FROM areas ORDER BY id", 1, true) then
                local out = {}
                for _, a in ipairs(AREAS) do out[#out + 1] = { slug = a.slug, name = a.slug } end
                return out
            end
            return {}
        end
    end

    -- A short stand-in for the real 16-step sewers route, so the tests read as
    -- tests of the engine rather than of one hard-coded direction list. The key
    -- is only a label; `to` is what says where the route ends.
    local ROUTE = { from = "second-town/north-plaza", to = "sewers/town-sewers-18",
                    steps = { "sw", "d", "se" } }

    local function route(overrides)
        local r = { from = ROUTE.from, to = ROUTE.to, steps = ROUTE.steps }
        for k, v in pairs(overrides or {}) do r[k] = v end
        taPackage.navRoutes["sewers/town-sewers-18"] = r
        return r
    end

    -- A room brief, in the order the game prints it: room line, occupants,
    -- floor. `floor` is the text after "There is " (nil means a bare floor).
    local function brief(roomName, floor)
        helper.simulateLine("You're in the " .. roomName .. ".")
        helper.simulateLine("There is nobody here.")
        helper.simulateLine(floor and ("There is " .. floor .. " lying on the floor.")
                                  or "There is nothing on the floor.")
    end

    -- Answer the start probe with a room's brief and exit-set. The floor line
    -- lands before `Exits:` in the real game, which is what lets the probe carry
    -- the starting room's floor into the walk.
    local function answerProbe(roomId, floor)
        local r = ROOMS[roomId]
        brief(r.name, floor)
        helper.simulateLine("Exits: " .. table.concat(r.exits, ",") .. ".")
    end

    local function sent(cmd)
        local n = 0
        for _, s in ipairs(helper.sendCalls) do if s == cmd then n = n + 1 end end
        return n
    end

    local function lastEchoes()
        return table.concat(helper.echoCalls, "\n")
    end

    before_each(function()
        helper.resetAll()
        dofile("main.lua")
        installWorld()
    end)

    describe("choosing a route", function()

        it("refuses an unknown destination and lists what it does know", function()
            helper.simulateAlias("navigate-to nowhere/at-all")
            assert.is_truthy(lastEchoes():find("I don't know a route to 'nowhere/at-all'", 1, true))
            assert.is_truthy(lastEchoes():find("town-3/ruby-door", 1, true))
            assert.are.equal(0, #helper.sendCalls)
        end)

        -- A name we've agreed on but haven't walked yet. Reporting it as
        -- unknown would be a lie, and reporting nothing would look like a bug.
        -- Registered here rather than borrowed from the live table, which no
        -- longer has one -- all twelve routes are recorded.
        it("says a named-but-unwalked route hasn't been recorded yet", function()
            taPackage.navRoutes["town-3/not-walked-yet"] = { pending = true }
            helper.simulateAlias("navigate-to town-3/not-walked-yet")
            local out = lastEchoes()
            assert.is_truthy(out:find("I know the name town-3/not-walked-yet", 1, true))
            assert.is_truthy(out:find("give me the starting room and the steps", 1, true))
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("refuses a route with a step it can't make sense of", function()
            route({ steps = { "sw", { shrug = true }, "se" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.is_truthy(lastEchoes():find("Step 2 of the route", 1, true))
            assert.are.equal(0, #helper.sendCalls)
        end)

        it("reports an unknown area in a route rather than walking", function()
            route({ from = "no-such-town/north-plaza" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("there's no area called 'no-such-town'", 1, true))
            assert.are.equal(0, sent("sw"))
        end)

        it("reports an ambiguous room reference with the candidates", function()
            route({ from = "third-town/underground-plaza" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            local out = lastEchoes()
            assert.is_truthy(out:find("is ambiguous", 1, true))
            assert.is_truthy(out:find("third-town/underground-plaza-1", 1, true))
            assert.is_truthy(out:find("third-town/underground-plaza-2", 1, true))
            assert.are.equal(0, sent("sw"))
        end)

        -- The room genuinely called `north-plaza` also answers to the display
        -- name it shares with second-town's. Without the slug winning, the one
        -- room named after itself is the one room that can't be named -- which
        -- is what made desert/stonework-chamber unreachable.
        it("takes the exact slug over the name it shares", function()
            route({ from = "first-town/north-plaza" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(1)
            assert.is_falsy(lastEchoes():find("is ambiguous", 1, true))
            assert.are.equal(1, sent("sw"))
        end)

        -- The one recorded route that starts outside the town-3 chain, and the
        -- reason the start check has to fingerprint: both towns have a room
        -- called "north plaza", and walking sixty wilderness steps from the
        -- wrong one would march the character into the sewers' walls instead.
        describe("the ruined-town route", function()

            it("is sixty-one directions from the first town's north plaza", function()
                local r = taPackage.navRoutes["ruined-town"]
                -- Stated literally at both ends so the leg runs on a host with
                -- no map: an empty tele-arena.db makes every <area>/<room>
                -- reference unresolvable.
                assert.are.same({ room = "north plaza", exits = "e,n,ne,nw,s,w" }, r.from)
                assert.are.same({ room = "ruined plaza" }, r.to)
                assert.are.equal(61, #r.steps)
                for i, step in ipairs(r.steps) do
                    assert.is_true(type(step) == "string",
                        "step " .. i .. " should be a plain direction")
                end
            end)

            it("sets off south from first-town's north plaza", function()
                helper.simulateAlias("navigate-to ruined-town")
                answerProbe(1)
                assert.are.equal(1, sent("s"))
            end)

            it("refuses to walk it from second-town's north plaza", function()
                helper.simulateAlias("navigate-to ruined-town")
                answerProbe(274)
                assert.are.equal(0, sent("s"))
                assert.is_truthy(lastEchoes():find("I don't know how to get there from here.", 1, true))
            end)

            -- The script opens tele-arena.db relative to the working directory,
            -- and on a host that has never mapped anything that call makes an
            -- empty database rather than failing. Every <area>/<room> reference
            -- is then unresolvable -- "there's no area called 'first-town'
            -- (known areas: )" -- so this leg names both its ends literally and
            -- asks the map nothing.
            it("walks on a host whose map is empty", function()
                helper.mockDbOneRow = function() return nil end
                helper.mockDbRows = function() return {} end
                helper.simulateAlias("navigate-to ruined-town")
                answerProbe(1)
                assert.are.equal(1, sent("s"))
                assert.is_falsy(lastEchoes():find("known areas", 1, true))
            end)

        end)

        -- The way back is ruined-town inverted rather than a walk of its own, so
        -- the property worth testing is that it really is the inverse: a typo in
        -- either list shows up as a step that doesn't mirror.
        describe("the town-1/north-plaza route back", function()

            local OPP = { n = "s", s = "n", e = "w", w = "e", ne = "sw",
                          sw = "ne", nw = "se", se = "nw", u = "d", d = "u" }

            it("mirrors ruined-town step for step", function()
                local out  = taPackage.navRoutes["ruined-town"]
                local back = taPackage.navRoutes["town-1/north-plaza"]
                assert.are.equal(#out.steps, #back.steps)
                for i, step in ipairs(back.steps) do
                    assert.are.equal(OPP[out.steps[#out.steps - i + 1]], step,
                        "step " .. i .. " should reverse the other route's")
                end
            end)

            it("swaps the two routes' ends", function()
                local out  = taPackage.navRoutes["ruined-town"]
                local back = taPackage.navRoutes["town-1/north-plaza"]
                assert.are.equal(out.to.room, back.from.room)
                assert.are.equal(out.from.room, back.to.room)
            end)

            it("sets off south from the ruined plaza", function()
                helper.simulateAlias("navigate-to town-1/north-plaza")
                answerProbe(966)
                assert.are.equal(1, sent("s"))
            end)

            it("refuses to walk it from the north plaza", function()
                helper.simulateAlias("navigate-to town-1/north-plaza")
                answerProbe(1)
                assert.are.equal(0, sent("s"))
                assert.is_truthy(lastEchoes():find("I don't know how to get there from here.", 1, true))
            end)

        end)

        -- The whole of the third-town chain walked backwards in one leg. Unlike
        -- town-1/north-plaza this is a recorded walk rather than an inversion,
        -- so there is no mirror property to assert -- what can be checked is
        -- that it still meets the outward chain where the two must agree.
        -- after-doors is the first four legs in one, and it is composition
        -- rather than a new walk: every direction in it is already in one of the
        -- four, so these tests are about the seams.
        describe("the after-doors route", function()

            local function AFTER() return taPackage.navRoutes["town-3/after-doors"] end

            it("starts where ruby-door starts and ends where get-onyx-key ends", function()
                assert.are.equal(taPackage.navRoutes["town-3/ruby-door"].from, AFTER().from)
                assert.are.equal("second-town/north-plaza", AFTER().from)
                assert.are.equal(taPackage.navRoutes["town-3/get-onyx-key"].to, AFTER().to)
                assert.are.equal("sewers/town-sewers-63", AFTER().to)
            end)

            -- The walk down from the plaza is ruby-door's, step for step. What
            -- is NOT carried over is its trailing `door` probe: that probe ends
            -- a walk by design, and here the door is walked through and gone on
            -- from.
            it("opens with ruby-door's sixteen steps and no door probe", function()
                local lead = taPackage.navRoutes["town-3/ruby-door"].steps
                assert.are.equal(16, #lead)
                for i = 1, #lead do
                    assert.are.equal(lead[i], AFTER().steps[i])
                end
                assert.is_nil(AFTER().door)
            end)

            it("gates the three doors in order, each with the errand for its key", function()
                local gates = {}
                for _, step in ipairs(AFTER().steps) do
                    if type(step) == "table" and step.door then gates[#gates + 1] = step end
                end
                assert.are.equal(3, #gates)
                assert.are.same({ door = "s", key = "ruby",
                                  detour = "town-3/get-ruby-key" }, gates[1])
                assert.are.same({ door = "e", key = "platinum",
                                  detour = "town-3/get-platinum-key-from-63" }, gates[2])
                assert.are.same({ door = "s", key = "onyx",
                                  detour = "town-3/get-onyx-key" }, gates[3])
                for _, g in ipairs(gates) do
                    assert.is_truthy(taPackage.navRoutes[g.detour])
                end
            end)

            -- Each errand is a round trip to the room it is called from, which
            -- is what lets it be spliced in without moving the walk: the gate
            -- that follows is tried from the same room it was refused in.
            it("only detours to errands that come back to where they started", function()
                for _, step in ipairs(AFTER().steps) do
                    if type(step) == "table" and step.detour then
                        local errand = taPackage.navRoutes[step.detour]
                        assert.are.equal(errand.from, errand.to)
                    end
                end
            end)

            -- The shape tests above read the table; this one puts the real route
            -- through the real pre-flight -- both ends resolved, every step and
            -- every gate's errand checked -- and watches it set off. A typo in
            -- any of the three detour names stops it here.
            it("passes its pre-flight and sets off from the north plaza", function()
                helper.simulateAlias("navigate-to town-3/after-doors")
                answerProbe(274)
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                assert.are.equal(1, sent("sw"))
                local out = lastEchoes()
                assert.is_falsy(out:find("fix the route table", 1, true))
                assert.is_falsy(out:find("I don't know how to get there from here.", 1, true))
                assert.is_truthy(out:find(
                    "22 steps, plus a key errand for any door that's locked.", 1, true))
            end)

            -- Nothing on these twenty-two steps needs a rope or a potion. They
            -- are asked for because part-2 starts where this ends, and the
            -- junction is the wrong side of the sewers to find out you're
            -- missing one: you'd walk back up to the plaza and down again.
            describe("checking for part-2's items before setting off", function()

                -- Assigned from part-2's list, not transcribed, so a change to
                -- what part-2 needs is a change to what this checks for.
                it("asks for exactly what part-2 requires", function()
                    assert.are.equal(taPackage.navRoutes["town-3/part-2"].requires,
                                     AFTER().requires)
                    assert.are.same({ "coil of rope", "verbena potion" }, AFTER().requires)
                end)

                it("asks what it is carrying before the first step", function()
                    helper.simulateAlias("navigate-to town-3/after-doors")
                    answerProbe(274)
                    assert.are.equal(1, sent("i"))
                    assert.are.equal(0, sent("sw"))
                end)

                -- Whose requirement it is, said out loud: "this route needs a
                -- coil of rope" of a route with no pit on it sends you looking
                -- for a problem that isn't there.
                it("refuses in part-2's name, not its own", function()
                    helper.simulateAlias("navigate-to town-3/after-doors")
                    answerProbe(274)
                    helper.simulateLine("You are carrying 559 gold crowns, and a waterskin(3).")
                    assert.are.equal(0, sent("sw"))
                    assert.is_nil(taPackage.navigate)
                    local out = lastEchoes()
                    assert.is_truthy(out:find(
                        "town-3/part-2, which carries on from where this ends, needs"
                        .. " a coil of rope and a verbena potion", 1, true))
                    assert.is_falsy(out:find("This route needs", 1, true))
                end)

                -- Part-1 on its own is a legitimate thing to walk, so the check
                -- is a courtesy like every other: overridable.
                it("walks it anyway when told to", function()
                    helper.simulateAlias("navigate-to town-3/after-doors anyway")
                    answerProbe(274)
                    assert.are.equal(0, sent("i"))
                    assert.are.equal(1, sent("sw"))
                end)

            end)

            -- Both doors off the junction are tried and stepped back from, so
            -- the leg ends at the junction however many of them were locked.
            it("steps back from each door it opens off the junction", function()
                local s = AFTER().steps
                assert.are.equal("d", s[18])   -- 62 -> 63
                assert.are.equal("w", s[20])   -- 106 -> 63, reversing the platinum gate
                assert.are.equal("n", s[22])   -- 117 -> 63, reversing the onyx gate
                assert.are.equal(22, #s)
            end)

        end)

        -- The other eight legs in one. Where after-doors had to decide things,
        -- this one only walks: every key it needs is fetched by a leg inside the
        -- run, so it is a concatenation, and these tests are about the joins.
        describe("the after-doors-to-town-3 route", function()

            local LEGS = { "town-3/hydra", "town-3/stoneworks-entrance",
                           "town-3/stone-lvl-2", "town-3/stone-lvl-3",
                           "town-3/stone-lvl-4", "town-3/stone-lvl-5",
                           "town-3/stone-lvl-6", "town-3/temple" }

            local function CHAIN() return taPackage.navRoutes["town-3/after-doors-to-town-3"] end

            -- The pair is the whole journey, and the seam between them is that
            -- after-doors stops exactly where this one starts.
            it("begins where after-doors ends", function()
                assert.are.equal(taPackage.navRoutes["town-3/after-doors"].to, CHAIN().from)
                assert.are.equal("sewers/town-sewers-63", CHAIN().from)
            end)

            it("names the eight legs in order", function()
                local named = {}
                for i, entry in ipairs(CHAIN().legs) do
                    named[i] = (type(entry) == "table") and entry.route or entry
                end
                assert.are.same(LEGS, named)
            end)

            -- The first leg's start is the joined route's own, checked before
            -- the walk sets off; the other seven get a seam apiece.
            it("flattens to the legs' steps, less the two dropped, plus seven seams", function()
                local total = 0
                for _, name in ipairs(LEGS) do
                    total = total + #taPackage.navRoutes[name].steps
                end
                assert.are.equal(359, total)
                assert.are.equal(total - 2 + 7, #taPackage.navRouteSteps(CHAIN()))
            end)

            -- The temple leg walks two rooms past the town square, into the
            -- underground plaza and then the temple. Dropped here only: run by
            -- hand, town-3/temple still goes all the way.
            it("stops in the town square by dropping the temple leg's last two", function()
                local temple = taPackage.navRoutes["town-3/temple"].steps
                assert.are.equal(103, #temple)
                assert.are.equal("ne", temple[102])
                assert.are.equal("e", temple[103])
                local last = CHAIN().legs[#CHAIN().legs]
                assert.are.equal("town-3/temple", last.route)
                assert.are.equal(2, last.drop)
                local flat = taPackage.navRouteSteps(CHAIN())
                assert.are.equal("w", flat[#flat])
            end)

            -- Where it stops is where the way home starts, so the two compose.
            it("ends where town-2 begins", function()
                assert.are.equal("third-town/town-square", CHAIN().to)
                assert.are.equal("town square", taPackage.navRoutes["town-2"].from.room)
            end)

            -- The rope and the potion strand you in different places, so both
            -- are asked for before a step is taken.
            it("asks for the rope and the potion together", function()
                assert.are.same({ "coil of rope", "verbena potion" }, CHAIN().requires)
                assert.are.equal("drink verbena", CHAIN().onPoison)
                helper.simulateAlias("navigate-to town-3/after-doors-to-town-3")
                answerProbe(426)
                assert.are.equal(1, sent("i"))
                assert.are.equal(0, sent("s"))
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                assert.are.equal(1, sent("s"))    -- the onyx door, hydra's first step
            end)

            it("passes its pre-flight, seams and all", function()
                helper.simulateAlias("navigate-to town-3/after-doors-to-town-3")
                answerProbe(426)
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                local out = lastEchoes()
                assert.is_falsy(out:find("fix the route table", 1, true))
                assert.is_falsy(out:find("no such route", 1, true))
                assert.is_falsy(out:find("I don't know how to get there from here.", 1, true))
                assert.is_truthy(out:find("364 steps", 1, true))
            end)

        end)

        -- part-1 and part-2 are the same two routes under names that say what
        -- order to run them in. Identity, not equality: they must be the very
        -- same table, so a correction to one route can't leave the other name
        -- pointing at a stale copy of it.
        describe("the part-1/part-2 names", function()

            it("are the same tables as the routes they rename", function()
                assert.are.equal(taPackage.navRoutes["town-3/after-doors"],
                                 taPackage.navRoutes["town-3/part-1"])
                assert.are.equal(taPackage.navRoutes["town-3/after-doors-to-town-3"],
                                 taPackage.navRoutes["town-3/part-2"])
            end)

            -- Named in the order they're walked: part-1 ends where part-2 starts.
            it("run in order", function()
                assert.are.equal(taPackage.navRoutes["town-3/part-1"].to,
                                 taPackage.navRoutes["town-3/part-2"].from)
            end)

            it("walks part-1 from the north plaza", function()
                helper.simulateAlias("navigate-to town-3/part-1")
                answerProbe(274)
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                local out = lastEchoes()
                assert.is_falsy(out:find("I don't know a route", 1, true))
                assert.is_truthy(out:find("22 steps", 1, true))
                assert.are.equal(1, sent("sw"))
            end)

            it("walks part-2 from the junction", function()
                helper.simulateAlias("navigate-to town-3/part-2")
                answerProbe(426)
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                local out = lastEchoes()
                assert.is_falsy(out:find("I don't know a route", 1, true))
                assert.is_truthy(out:find("364 steps", 1, true))
                assert.are.equal(1, sent("s"))
            end)

        end)

        -- A variant is an alternative ENDING asked for as a trailing word. The
        -- live one, chasm-is-clear, is pending -- so these build their own to
        -- test the flattening, and use the live one for the plumbing.
        describe("route variants", function()

            -- Two legs of three steps each, the second of which has another
            -- ending. Small enough that the expected step lists are readable.
            local function twoLegRoute()
                taPackage.navRoutes["t/leg-a"] = { from = "x", steps = { "n", "n", "n" } }
                taPackage.navRoutes["t/leg-b"] = { from = "y", steps = { "s", "s", "s" } }
                local r = { from = "x", legs = { "t/leg-a", "t/leg-b" },
                            variants = { alt = { leg = "t/leg-b", keep = 1,
                                                 steps = { "e", "w" } } } }
                taPackage.navRoutes["t/joined"] = r
                return r
            end

            it("walks the ordinary ending when no variant is asked for", function()
                local flat = taPackage.navRouteSteps(twoLegRoute())
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s", "s", "s" }, flat)
            end)

            -- The shared prefix stays shared: leg-a whole, the seam, then one
            -- step of leg-b before the variant's own ending takes over.
            it("keeps the prefix and swaps the ending", function()
                local flat = taPackage.navRouteSteps(twoLegRoute(), "alt")
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s", "e", "w" }, flat)
            end)

            -- A variant's steps are final; the leg entry's drop is about where
            -- the ORDINARY ending stops and has nothing to say about this one.
            it("ignores the leg's drop when the variant replaces its tail", function()
                local r = twoLegRoute()
                r.legs[2] = { route = "t/leg-b", drop = 2 }
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s" },
                                taPackage.navRouteSteps(r))
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s", "e", "w" },
                                taPackage.navRouteSteps(r, "alt"))
            end)

            -- The variant is how the walk ENDS, so the legs after the one it
            -- diverges inside are dropped too. Caught late: with the variant
            -- on the last leg there is nothing after it to wrongly append, and
            -- the live chasm-is-clear diverges two legs from the end.
            it("drops the legs after the one it diverges inside", function()
                local r = twoLegRoute()
                taPackage.navRoutes["t/leg-c"] = { from = "z", steps = { "e", "e" } }
                r.legs = { "t/leg-a", "t/leg-b", "t/leg-c" }
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s", "s", "s",
                                  { seam = "t/leg-c" }, "e", "e" },
                                taPackage.navRouteSteps(r))
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "s", "e", "w" },
                                taPackage.navRouteSteps(r, "alt"))
            end)

            -- How chasm-is-clear is shaped: replace the leg whole, but keep
            -- the seam check that runs in front of it. Below the riddle door
            -- that fingerprint is the only check the walk has.
            it("keeps the seam check when the variant replaces a leg whole", function()
                local r = twoLegRoute()
                r.variants.alt.keep = 0
                assert.are.same({ "n", "n", "n", { seam = "t/leg-b" }, "e", "w" },
                                taPackage.navRouteSteps(r, "alt"))
            end)

            it("works on a route that gives its steps directly", function()
                local r = { from = "x", steps = { "n", "n", "n" },
                            variants = { alt = { keep = 2, steps = { "e" } } } }
                assert.are.same({ "n", "n", "e" }, taPackage.navRouteSteps(r, "alt"))
            end)

            -- The other shape a variant can take: not an ending inside one leg,
            -- but a shorter way through the MIDDLE of the route. The legs carry
            -- their own variants of the name and the walk carries on past them.
            describe("a variant taken from the legs' own", function()

                -- leg-a has a short way through it; leg-b doesn't.
                local function perLegRoute()
                    taPackage.navRoutes["t/leg-a"] =
                        { from = "x", steps = { "n", "n", "n" },
                          variants = { alt = { keep = 1, steps = { "ne" } } } }
                    taPackage.navRoutes["t/leg-b"] = { from = "y", steps = { "s", "s", "s" } }
                    local r = { from = "x", legs = { "t/leg-a", "t/leg-b" },
                                variants = { alt = { fromLegs = true } } }
                    taPackage.navRoutes["t/joined"] = r
                    return r
                end

                -- The point of the whole shape: leg-a is replaced and leg-b is
                -- still walked. An ending would have thrown leg-b away.
                it("replaces the leg and carries on through the rest", function()
                    assert.are.same({ "n", "ne", { seam = "t/leg-b" }, "s", "s", "s" },
                                    taPackage.navRouteSteps(perLegRoute(), "alt"))
                end)

                it("leaves a leg with no variant of that name alone", function()
                    local r = perLegRoute()
                    taPackage.navRoutes["t/leg-b"].variants = { other = { keep = 0, steps = {} } }
                    assert.are.same({ "n", "ne", { seam = "t/leg-b" }, "s", "s", "s" },
                                    taPackage.navRouteSteps(r, "alt"))
                end)

                it("applies it to every leg that has one", function()
                    local r = perLegRoute()
                    taPackage.navRoutes["t/leg-b"].variants =
                        { alt = { keep = 2, steps = { "sw" } } }
                    assert.are.same({ "n", "ne", { seam = "t/leg-b" }, "s", "s", "sw" },
                                    taPackage.navRouteSteps(r, "alt"))
                end)

                -- Same as an ending: the variant says where the leg finishes, so
                -- the leg entry's drop has nothing left to say.
                it("ignores the leg entry's drop", function()
                    local r = perLegRoute()
                    r.legs[1] = { route = "t/leg-a", drop = 2 }
                    assert.are.same({ "n", "ne", { seam = "t/leg-b" }, "s", "s", "s" },
                                    taPackage.navRouteSteps(r, "alt"))
                end)

                it("keeps the seam in front of a leg it replaces whole", function()
                    local r = perLegRoute()
                    taPackage.navRoutes["t/leg-b"].variants = { alt = { keep = 0, steps = { "e" } } }
                    assert.are.same({ "n", "ne", { seam = "t/leg-b" }, "e" },
                                    taPackage.navRouteSteps(r, "alt"))
                end)

                -- The trap this shape brings with it: ask for the short way,
                -- have no leg offer one, and walk the long way in silence.
                it("refuses when no leg has a variant of that name", function()
                    local r = perLegRoute()
                    taPackage.navRoutes["t/leg-a"].variants = nil
                    local flat, err = taPackage.navRouteSteps(r, "alt")
                    assert.is_nil(flat)
                    assert.is_truthy(err:find("no leg of this route has one called 'alt'", 1, true))
                end)

                it("refuses on a route that isn't built from legs", function()
                    local r = { from = "x", steps = { "n" },
                                variants = { alt = { fromLegs = true } } }
                    local flat, err = taPackage.navRouteSteps(r, "alt")
                    assert.is_nil(flat)
                    assert.is_truthy(err:find("this route isn't built from legs", 1, true))
                end)

                it("refuses when a leg's variant has no steps recorded yet", function()
                    local r = perLegRoute()
                    taPackage.navRoutes["t/leg-a"].variants = { alt = { pending = true } }
                    local flat, err = taPackage.navRouteSteps(r, "alt")
                    assert.is_nil(flat)
                    assert.is_truthy(err:find("no steps recorded yet", 1, true))
                end)

            end)

            it("refuses a variant name the route doesn't have", function()
                local flat, err = taPackage.navRouteSteps(twoLegRoute(), "nope")
                assert.is_nil(flat)
                assert.is_truthy(err:find("no 'nope' variant", 1, true))
            end)

            -- The one outcome worse than refusing: you ask for the other
            -- ending, the leg name is a typo, and it walks the ordinary one.
            it("refuses a variant whose leg this route doesn't walk", function()
                local r = twoLegRoute()
                r.variants.alt.leg = "t/leg-typo"
                local flat, err = taPackage.navRouteSteps(r, "alt")
                assert.is_nil(flat)
                assert.is_truthy(err:find("no leg of this route is called that", 1, true))
            end)

            it("refuses a variant with no steps recorded yet", function()
                local r = twoLegRoute()
                r.variants.alt = { leg = "t/leg-b", pending = true }
                local flat, err = taPackage.navRouteSteps(r, "alt")
                assert.is_nil(flat)
                assert.is_truthy(err:find("no steps recorded yet", 1, true))
            end)

            -- The first leg's chasm-is-clear: the same twenty-three steps, and
            -- no sweep on the end. The hydra is walked past rather than killed,
            -- because the pearl key its corpse drops is already in the pack.
            describe("the chasm-is-clear way through the hydra's room", function()

                local function LEG() return taPackage.navRoutes["town-3/hydra"] end

                it("is the leg's steps without the sweep", function()
                    local steps, flat = LEG().steps, taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.equal(24, #steps)
                    assert.are.equal(23, #flat)
                    for i = 1, 23 do assert.are.same(steps[i], flat[i]) end
                end)

                -- What the last step is, and so what keep = 23 is dropping. A
                -- correction to the leg that moves the sweep makes it wrong.
                it("drops the sweep that fetches the pearl key, and nothing else", function()
                    assert.are.same({ killAll = true, untilFound = "pearl key" },
                                    LEG().steps[24])
                    for _, s in ipairs(taPackage.navRouteSteps(LEG(), "chasm-is-clear")) do
                        assert.is_falsy(type(s) == "table" and s.killAll)
                    end
                end)

                -- Same room at the end either way: the way out of the sewers
                -- runs through it, so we walk in and straight back out.
                it("still ends in the hydra's room", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.equal("sewers/town-sewers-165", LEG().to)
                    assert.are.equal("n", flat[#flat])
                end)

                -- Runnable on its own, and on its own it wants only the rope:
                -- the pearl doors are on the leg after this one.
                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/hydra chasm-is-clear")
                    answerProbe(426)
                    helper.simulateLine("You are carrying a coil of rope.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/hydra chasm-is-clear", 1, true))
                    assert.is_truthy(out:find("23 steps", 1, true))
                    assert.are.equal(1, sent("s"))
                end)

                -- And in the chain: one step shorter, the seam after it intact,
                -- and no sweep left anywhere in the walk.
                it("shortens the chain by 1 and carries on into the stoneworks", function()
                    local chain = taPackage.navRoutes["town-3/part-2"]
                    local flat = taPackage.navRouteSteps(chain, "chasm-is-clear")
                    for i = 1, 23 do assert.are.same(LEG().steps[i], flat[i]) end
                    assert.are.same({ seam = "town-3/stoneworks-entrance" }, flat[24])
                    local sweeps = 0
                    for _, s in ipairs(taPackage.navRouteSteps(chain)) do
                        if type(s) == "table" and s.killAll then sweeps = sweeps + 1 end
                    end
                    assert.are.equal(1, sweeps)
                    for _, s in ipairs(flat) do
                        assert.is_falsy(type(s) == "table" and s.killAll)
                    end
                end)

                -- The pearl key is NOT wanted. The two stone doors it opens are
                -- on the leg after this one and they don't relock, so a run
                -- that can ask for chasm-is-clear is a run that finds them
                -- already open. Asking for the key refused the fast way to
                -- every character that hadn't personally killed the hydra.
                it("walks the chain without a pearl key", function()
                    helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear")
                    answerProbe(426)
                    helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                    local out = lastEchoes()
                    assert.is_falsy(out:find("pearl key", 1, true))
                    assert.is_falsy(out:find("not setting off", 1, true))
                    assert.are.equal(1, sent("s"))
                end)

                -- The ordinary walk fetches it on the way, so it asks for the
                -- rope and the potion and nothing else.
                it("doesn't ask the ordinary chain for a pearl key", function()
                    helper.simulateAlias("navigate-to town-3/part-2")
                    answerProbe(426)
                    helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                    local out = lastEchoes()
                    assert.is_falsy(out:find("pearl key", 1, true))
                    assert.are.equal(1, sent("s"))
                end)

                -- Both ways of walking it want exactly the same two things, so
                -- `anyway` names the same two either way.
                it("names the same pack for anyway as the ordinary chain", function()
                    helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear anyway")
                    answerProbe(426)
                    local out = lastEchoes()
                    assert.is_truthy(out:find("without checking for", 1, true))
                    assert.is_falsy(out:find("pearl key", 1, true))
                    assert.are.equal(1, sent("s"))
                end)

                -- And the variant declares no list of its own for part-1 to
                -- disagree with: one list, on the route, for both ways.
                it("leaves part-1 asking for the rope and the potion only", function()
                    local p1 = taPackage.navRoutes["town-3/part-1"]
                    local v = taPackage.navRoutes["town-3/part-2"].variants["chasm-is-clear"]
                    assert.are.same({ "coil of rope", "verbena potion" }, p1.requires)
                    assert.is_nil(v.requires)
                end)

            end)

            -- chasm-is-clear is stored as the DIFFERENCE from the temple leg:
            -- The short way through level two, for a run where its lever and
            -- its first stone are already thrown. Written out whole, as the
            -- user gave it, so the keep/steps encoding is checked against the
            -- walk rather than trusted.
            describe("the chasm-is-clear way through stone-lvl-2", function()

                local WALK = {
                    { cmd = "say komi" }, "e", "se", "se", "se", "sw", "sw", "se",  --  1- 8
                    "sw", "se", "e", "se", "s", "sw", "sw", "s",                    --  9-16
                    "e", "e", "e", "e", "s", "se", "e", "se",                       -- 17-24
                    { cmd = "push stone" },                                         -- 25
                    "e", "e", "e", "d",                                             -- 26-29
                }

                local function LEG() return taPackage.navRoutes["town-3/stone-lvl-2"] end

                it("is the walk that was given, 29 steps against 43", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(43, #LEG().steps)
                end)

                -- Where the two part. A correction to the leg that moves this
                -- boundary makes keep = 8 wrong, and this is what says so.
                it("shares the leg's first 8 steps and parts at 9", function()
                    local steps = LEG().steps
                    for i = 1, 8 do assert.are.same(steps[i], WALK[i]) end
                    assert.are.equal("e", steps[9])
                    assert.are.equal("sw", WALK[9])
                end)

                -- The check on the transcription: two walks agreeing on their
                -- last thirteen steps is not a coincidence. The short way's
                -- eight own steps land exactly where the long way's twenty-two
                -- land, and from there they are the same directions.
                it("rejoins the ordinary route at its step 31", function()
                    local steps = LEG().steps
                    for i = 0, 12 do
                        assert.are.same(steps[31 + i], WALK[17 + i])
                    end
                    assert.are.equal(43, 31 + 12)
                    assert.are.equal(29, 17 + 12)
                end)

                -- What the 22 replaced steps were for, and why they can go: the
                -- lever and the first stone stay thrown between runs.
                it("skips the lever and the first stone, and keeps the second", function()
                    local skipped = {}
                    for i = 9, 30 do
                        local s = LEG().steps[i]
                        if type(s) == "table" then skipped[#skipped + 1] = s.cmd end
                    end
                    assert.are.same({ "pull lever", "push stone" }, skipped)
                    local kept = {}
                    for _, s in ipairs(WALK) do
                        if type(s) == "table" then kept[#kept + 1] = s.cmd end
                    end
                    assert.are.same({ "say komi", "push stone" }, kept)
                end)

                -- It still opens with the riddle: the east door out of the
                -- entrance chamber does not stay open the way a lever stays
                -- thrown, and without `say komi` there is nothing to walk.
                it("still says komi", function()
                    assert.are.same({ cmd = "say komi" },
                                    taPackage.navRouteSteps(LEG(), "chasm-is-clear")[1])
                end)

                -- Runnable on its own, which is how a new segment gets checked
                -- without the 250 steps in front of it.
                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/stone-lvl-2 chasm-is-clear")
                    brief("stonework chamber")
                    helper.simulateLine("Exits: e,n,s.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/stone-lvl-2 chasm-is-clear",
                        1, true))
                    assert.is_truthy(out:find("29 steps", 1, true))
                    assert.are.equal(1, sent("say komi"))
                end)

                -- And in the chain: 14 steps shorter, the seams either side of
                -- it intact, and the walk carrying on to level three -- which an
                -- ENDING variant could not have done.
                it("shortens the chain by 14 and carries on past level two", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
                    assert.are.same({ seam = "town-3/stone-lvl-2" }, flat[62])
                    for i = 1, 29 do assert.are.same(WALK[i], flat[62 + i]) end
                    assert.are.same({ seam = "town-3/stone-lvl-3" }, flat[92])
                    assert.are.equal(197, #flat)
                end)

            end)

            -- The short way through level three, written out whole as the
            -- user gave it, so the keep/steps encoding is checked against the
            -- walk rather than trusted.
            describe("the chasm-is-clear way through stone-lvl-3", function()

                local WALK = {
                    "w", "sw", "w", "nw", "n", "nw", "ne",   --  1- 7
                    "ne", "e", "ne",                         --  8-10
                    { cmd = "say arok" },                    -- 11
                    "n", "n", "d",                           -- 12-14
                }

                local function LEG() return taPackage.navRoutes["town-3/stone-lvl-3"] end

                it("is the walk that was given, 14 steps against 47", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(47, #LEG().steps)
                end)

                -- Where the two part. A correction to the leg that moves this
                -- boundary makes keep = 3 wrong, and this is what says so.
                it("shares the leg's first 3 steps and parts at 4", function()
                    local steps = LEG().steps
                    for i = 1, 3 do assert.are.same(steps[i], WALK[i]) end
                    assert.are.equal("sw", steps[4])
                    assert.are.equal("nw", WALK[4])
                end)

                -- Not a step of it is new: it is the ordinary route's first
                -- three and then its last eleven, so the room the third `w`
                -- lands in is the room step 36 lands in. Two independent walks
                -- agreeing on eleven consecutive steps is the check on the
                -- transcription.
                it("is the leg's first 3 steps and its last 11", function()
                    local steps = LEG().steps
                    for i = 0, 10 do
                        assert.are.same(steps[37 + i], WALK[4 + i])
                    end
                    assert.are.equal(47, 37 + 10)
                    assert.are.equal(14, 4 + 10)
                end)

                -- What the 33 dropped steps were for, and why they can go: the
                -- lever stays pulled between runs -- and so, which is the part
                -- that matters, do the traps it disarms.
                it("skips the lever, which is the only command in the 33", function()
                    local skipped = {}
                    for i = 4, 36 do
                        local s = LEG().steps[i]
                        if type(s) == "table" then skipped[#skipped + 1] = s.cmd end
                    end
                    assert.are.same({ "pull lever" }, skipped)
                end)

                -- It still says the riddle: `arok` opens the way down to level
                -- four, and a riddle door does not stay open the way a lever
                -- stays pulled.
                it("still says arok", function()
                    local kept = {}
                    for _, s in ipairs(taPackage.navRouteSteps(LEG(), "chasm-is-clear")) do
                        if type(s) == "table" then kept[#kept + 1] = s.cmd end
                    end
                    assert.are.same({ "say arok" }, kept)
                end)

                -- Runnable on its own, which is how a new segment gets checked
                -- without the 100 steps in front of it.
                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/stone-lvl-3 chasm-is-clear")
                    brief("stonework chamber")
                    helper.simulateLine("Exits: u,w.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/stone-lvl-3 chasm-is-clear",
                        1, true))
                    assert.is_truthy(out:find("14 steps", 1, true))
                    assert.are.equal(1, sent("w"))
                end)

                -- And in the chain: 33 steps shorter, the seams either side of
                -- it intact, and the walk carrying on to level four.
                it("shortens the chain by 33 and carries on past level three", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
                    assert.are.same({ seam = "town-3/stone-lvl-3" }, flat[92])
                    for i = 1, 14 do assert.are.same(WALK[i], flat[92 + i]) end
                    assert.are.same({ seam = "town-3/stone-lvl-4" }, flat[107])
                end)

            end)

            -- The short way through level four, written out whole as the user
            -- gave it, so the keep/steps encoding is checked against the walk
            -- rather than trusted.
            describe("the chasm-is-clear way through stone-lvl-4", function()

                local WALK = {
                    "w", "sw", "s", "w", "w", "sw", "nw", "w",   --  1- 8
                    "n", "nw", "nw", "n", "d",                   --  9-13
                }

                local function LEG() return taPackage.navRoutes["town-3/stone-lvl-4"] end

                it("is the walk that was given, 13 steps against 42", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(42, #LEG().steps)
                end)

                -- Where the two part. A correction to the leg that moves this
                -- boundary makes keep = 8 wrong, and this is what says so.
                it("shares the leg's first 8 steps and parts at 9", function()
                    local steps = LEG().steps
                    for i = 1, 8 do assert.are.same(steps[i], WALK[i]) end
                    assert.are.equal("s", steps[9])
                    assert.are.equal("n", WALK[9])
                end)

                -- Not a step of it is new: the leg's first eight and then its
                -- last FIVE. Level three's join takes its leg's last six
                -- because the retrace comes back to where its kept prefix
                -- ended; here it lands one room short, and the leg's step 37
                -- (`n`) is what covers that -- so taking six would walk an `n`
                -- too many. Found live: it stopped a walk at chain step 118.
                it("is the leg's first 8 steps and its last 5", function()
                    local steps = LEG().steps
                    for i = 0, 4 do
                        assert.are.same(steps[38 + i], WALK[9 + i])
                    end
                    assert.are.equal(42, 38 + 4)
                    assert.are.equal(13, 9 + 4)
                end)

                -- What the 29 dropped steps were for, and why they can go: the
                -- lever stays pulled between runs -- and so do the traps it
                -- disarms, which is the part that decides whether this is safe.
                it("skips the lever, which is the only command in the 29", function()
                    local skipped = {}
                    for i = 9, 37 do
                        local s = LEG().steps[i]
                        if type(s) == "table" then skipped[#skipped + 1] = s.cmd end
                    end
                    assert.are.same({ "pull lever" }, skipped)
                end)

                -- The only variant here with no command at all: no riddle on
                -- this level, and the `d` at the end is unguarded.
                it("is all directions and no commands", function()
                    for _, s in ipairs(taPackage.navRouteSteps(LEG(), "chasm-is-clear")) do
                        assert.are.equal("string", type(s))
                    end
                end)

                -- Runnable on its own, which is how a new segment gets checked
                -- without the 100 steps in front of it.
                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/stone-lvl-4 chasm-is-clear")
                    brief("stonework chamber")
                    helper.simulateLine("Exits: u,w.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/stone-lvl-4 chasm-is-clear",
                        1, true))
                    assert.is_truthy(out:find("13 steps", 1, true))
                    assert.are.equal(1, sent("w"))
                end)

                -- And in the chain: 29 steps shorter, the seams either side of
                -- it intact, and the walk carrying on to level five.
                it("shortens the chain by 29 and carries on past level four", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
                    assert.are.same({ seam = "town-3/stone-lvl-4" }, flat[107])
                    for i = 1, 13 do assert.are.same(WALK[i], flat[107 + i]) end
                    assert.are.same({ seam = "town-3/stone-lvl-5" }, flat[121])
                end)

            end)

            -- The short way through level five, written out whole as the user
            -- gave it, so the keep/steps encoding is checked against the walk
            -- rather than trusted.
            describe("the chasm-is-clear way through stone-lvl-5", function()

                local WALK = {
                    "se", "s", "se", "se",                      --  1- 4
                    "sw", "sw", "sw",                           --  5- 7
                    "w", "s", "se", "se", "s", "d",             --  8-13
                }

                local function LEG() return taPackage.navRoutes["town-3/stone-lvl-5"] end

                it("is the walk that was given, 13 steps against 36", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(36, #LEG().steps)
                end)

                -- Where the two part. A correction to the leg that moves this
                -- boundary makes keep = 4 wrong, and this is what says so.
                it("shares the leg's first 4 steps and parts at 5", function()
                    local steps = LEG().steps
                    for i = 1, 4 do assert.are.same(steps[i], WALK[i]) end
                    assert.are.equal("e", steps[5])
                    assert.are.equal("sw", WALK[5])
                end)

                -- Unlike levels three and four this one takes steps of its own
                -- rather than being made only of the leg's: three between the
                -- divergence and the rejoin. What it rejoins is the check --
                -- its last seven are the leg's steps 30-36, direction for
                -- direction.
                it("rejoins the ordinary route at its step 30", function()
                    local steps = LEG().steps
                    for i = 0, 6 do
                        assert.are.same(steps[30 + i], WALK[7 + i])
                    end
                    assert.are.equal(36, 30 + 6)
                    assert.are.equal(13, 7 + 6)
                end)

                -- What the 25 replaced steps were for, and why they can go: the
                -- lever stays pulled between runs -- and so do the traps it
                -- disarms, which is what decides whether this is safe.
                it("skips the lever, which is the only command in the 25", function()
                    local skipped = {}
                    for i = 5, 29 do
                        local s = LEG().steps[i]
                        if type(s) == "table" then skipped[#skipped + 1] = s.cmd end
                    end
                    assert.are.same({ "pull lever" }, skipped)
                end)

                -- No riddle on this level either, so nothing survives but
                -- directions.
                it("is all directions and no commands", function()
                    for _, s in ipairs(taPackage.navRouteSteps(LEG(), "chasm-is-clear")) do
                        assert.are.equal("string", type(s))
                    end
                end)

                -- Runnable on its own, from the one start chamber down here
                -- that can't be confused with another floor's.
                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/stone-lvl-5 chasm-is-clear")
                    brief("stonework chamber")
                    helper.simulateLine("Exits: se,u.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/stone-lvl-5 chasm-is-clear",
                        1, true))
                    assert.is_truthy(out:find("13 steps", 1, true))
                    assert.are.equal(1, sent("se"))
                end)

                -- And in the chain: 23 steps shorter, the seams either side of
                -- it intact, and the walk carrying on to level six.
                it("shortens the chain by 23 and carries on past level five", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
                    assert.are.same({ seam = "town-3/stone-lvl-5" }, flat[121])
                    for i = 1, 13 do assert.are.same(WALK[i], flat[121 + i]) end
                    assert.are.same({ seam = "town-3/stone-lvl-6" }, flat[135])
                end)

            end)

            -- The short way through level six, written out whole as the user
            -- gave it, so the keep/steps encoding is checked against the walk
            -- rather than trusted.
            describe("the chasm-is-clear way through stone-lvl-6", function()

                local WALK = {
                    "ne", "ne", "e", "ne", "ne",                --  1- 5
                    "ne", "se", "e",                            --  6- 8
                    "ne", "nw", "nw", "n", "n", "d",             --  9-14
                }

                local function LEG() return taPackage.navRoutes["town-3/stone-lvl-6"] end

                it("is the walk that was given, 14 steps against 27", function()
                    local flat = taPackage.navRouteSteps(LEG(), "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(27, #LEG().steps)
                end)

                -- Where the two part. A correction to the leg that moves this
                -- boundary makes keep = 5 wrong, and this is what says so.
                it("shares the leg's first 5 steps and parts at 6", function()
                    local steps = LEG().steps
                    for i = 1, 5 do assert.are.same(steps[i], WALK[i]) end
                    assert.are.equal("se", steps[6])
                    assert.are.equal("ne", WALK[6])
                end)

                -- Its last six are the leg's steps 22-27, which is the check on
                -- the transcription: it comes back in where the lever's retrace
                -- would have come back in anyway.
                it("rejoins the ordinary route at its step 22", function()
                    local steps = LEG().steps
                    for i = 0, 5 do
                        assert.are.same(steps[22 + i], WALK[9 + i])
                    end
                    assert.are.equal(27, 22 + 5)
                    assert.are.equal(14, 9 + 5)
                end)

                -- The three steps in between are the leg's own 6-8 with the
                -- first two swapped. Recorded because it looks like a
                -- transposition and must not be quietly straightened out --
                -- nothing down here is mapped, so ne-then-se and se-then-ne
                -- need not land in the same chamber. If this ever changes, it
                -- should be because a walk said so.
                it("takes the leg's steps 6-8 with the first two swapped", function()
                    local steps = LEG().steps
                    assert.are.same({ "se", "ne", "e" }, { steps[6], steps[7], steps[8] })
                    assert.are.same({ "ne", "se", "e" }, { WALK[6], WALK[7], WALK[8] })
                end)

                -- What the 16 replaced steps were for, and why they can go: the
                -- lever stays pulled between runs -- and so do the traps it
                -- disarms, which is what decides whether this is safe.
                it("skips the lever, which is the only command in the 16", function()
                    local skipped = {}
                    for i = 6, 21 do
                        local s = LEG().steps[i]
                        if type(s) == "table" then skipped[#skipped + 1] = s.cmd end
                    end
                    assert.are.same({ "pull lever" }, skipped)
                end)

                it("is all directions and no commands", function()
                    for _, s in ipairs(taPackage.navRouteSteps(LEG(), "chasm-is-clear")) do
                        assert.are.equal("string", type(s))
                    end
                end)

                it("runs as the leg on its own", function()
                    helper.simulateAlias("navigate-to town-3/stone-lvl-6 chasm-is-clear")
                    brief("stonework chamber")
                    helper.simulateLine("Exits: ne,u.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/stone-lvl-6 chasm-is-clear",
                        1, true))
                    assert.is_truthy(out:find("14 steps", 1, true))
                    assert.are.equal(1, sent("ne"))
                end)

                -- And in the chain: 13 steps shorter, the seam before it
                -- intact, and the walk carrying on into the temple leg.
                it("shortens the chain by 13 and carries on to the temple leg", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
                    assert.are.same({ seam = "town-3/stone-lvl-6" }, flat[135])
                    for i = 1, 14 do assert.are.same(WALK[i], flat[135 + i]) end
                    assert.are.same({ seam = "town-3/temple" }, flat[150])
                end)

            end)

            -- Every leg below the riddle door now has one, which is what makes
            -- the chain 198 steps against 364: six short ways and six seams.
            it("gives every stoneworks leg a chasm-is-clear of its own", function()
                for n = 2, 6 do
                    local leg = taPackage.navRoutes["town-3/stone-lvl-" .. n]
                    assert.is_truthy(leg.variants
                        and leg.variants["chasm-is-clear"], "level " .. n)
                end
                assert.is_truthy(
                    taPackage.navRoutes["town-3/temple"].variants["chasm-is-clear"])
            end)

            -- 26 shared steps kept, 20 of its own. This is the walk the user
            -- gave, written out whole -- so the shared-prefix encoding is
            -- checked against what was actually walked rather than trusted.
            describe("the chasm-is-clear ending", function()

                local WALK = {
                    "e", "e", "e", "e", "e", "e", "s", "e", "e", "e",   --  1-10
                    "s", "s", "s", "s", "w", "w", "s", "s", "s", "w",   -- 11-20
                    "w", "w", "w", "s", "s", "w", "s", "s", "e", "e",   -- 21-30
                    "e", "e", "e", "e", "s", "s", "s", "w", "s", "s",   -- 31-40
                    "w", "w", "w", "w", "w", "w", "w",                  -- 41-47
                }

                -- Flattened from the temple leg's start, the variant is the
                -- walk exactly. 47 steps, none of them a lever.
                it("is the walk that was given, from the temple leg's start", function()
                    local flat = taPackage.navRouteSteps(
                        taPackage.navRoutes["town-3/temple"], "chasm-is-clear")
                    assert.are.same(WALK, flat)
                    assert.are.equal(47, #flat)
                    for _, s in ipairs(flat) do assert.are.equal("string", type(s)) end
                end)

                -- Where the two endings separate. If a correction to the temple
                -- leg ever moves that boundary, keep = 26 is wrong and this is
                -- what says so.
                it("shares the temple leg's first 26 steps and parts at 27", function()
                    local temple = taPackage.navRoutes["town-3/temple"].steps
                    for i = 1, 26 do assert.are.equal(temple[i], WALK[i]) end
                    assert.are.equal("w", temple[27])
                    assert.are.equal("s", WALK[27])
                end)

                -- Both lever runs are in the 77 steps this replaces, which is
                -- the whole reason it is shorter: the walls are already down.
                it("skips both of the temple leg's levers", function()
                    local temple = taPackage.navRoutes["town-3/temple"]
                    local levers = 0
                    for i = 27, #temple.steps do
                        if type(temple.steps[i]) == "table" then levers = levers + 1 end
                    end
                    assert.are.equal(2, levers)
                    assert.are.equal(77, #temple.steps - 26)
                end)

                -- End to end on the live chain: the seams and the shared prefix
                -- still there, the ordinary ending gone.
                it("shortens the whole chain from 364 steps to 197", function()
                    local chain = taPackage.navRoutes["town-3/part-2"]
                    assert.are.equal(364, #taPackage.navRouteSteps(chain))
                    local flat = taPackage.navRouteSteps(chain, "chasm-is-clear")
                    assert.are.equal(197, #flat)
                    -- 150 is the temple seam, so 151.. is the temple leg.
                    assert.are.same({ seam = "town-3/temple" }, flat[150])
                    for i = 1, 47 do assert.are.equal(WALK[i], flat[150 + i]) end
                end)

                -- The steps live on the temple leg, and the chain asks the legs
                -- for their own. So a walk that dies late can be picked up at
                -- the temple seam and finished by hand, and it walks the same 47
                -- steps rather than a second transcription.
                it("is recorded on the temple leg and taken from it by the chain", function()
                    local own = taPackage.navRoutes["town-3/temple"].variants["chasm-is-clear"]
                    assert.are.equal(26, own.keep)
                    assert.are.equal(21, #own.steps)
                    local chainV = taPackage.navRoutes["town-3/part-2"].variants["chasm-is-clear"]
                    assert.is_true(chainV.fromLegs)
                    assert.is_nil(chainV.leg)
                    assert.is_nil(chainV.steps)
                    assert.are.same(
                        WALK, taPackage.navRouteSteps(taPackage.navRoutes["town-3/temple"],
                                                      "chasm-is-clear"))
                end)

                it("runs as the leg on its own from the temple seam", function()
                    helper.simulateAlias("navigate-to town-3/temple chasm-is-clear")
                    -- A fingerprint start, so the probe is answered with the
                    -- brief and exits rather than a room out of the map.
                    brief("stonework chamber")
                    helper.simulateLine("Exits: e,u.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/temple chasm-is-clear", 1, true))
                    assert.is_truthy(out:find("47 steps", 1, true))
                    assert.are.equal(1, sent("e"))
                end)

                -- A borrowing that names a leg with no such variant would
                -- otherwise flatten to the ordinary ending in silence.
                it("refuses a borrowing the named leg can't honour", function()
                    local r = twoLegRoute()
                    r.variants.alt = { leg = "t/leg-b" }
                    local flat, err = taPackage.navRouteSteps(r, "alt")
                    assert.is_nil(flat)
                    assert.is_truthy(err:find("no such variant of its own", 1, true))
                end)

                it("walks it when asked for by name", function()
                    helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear")
                    answerProbe(426)
                    helper.simulateLine(
                        "You are carrying a coil of rope, and a verbena potion.")
                    local out = lastEchoes()
                    assert.is_truthy(out:find("Walking to town-3/part-2 chasm-is-clear", 1, true))
                    assert.is_truthy(out:find("197 steps", 1, true))
                    assert.are.equal(1, sent("s"))
                end)

            end)

            it("takes the variant under either name for the route", function()
                for _, name in ipairs({ "town-3/part-2", "town-3/after-doors-to-town-3" }) do
                    assert.is_truthy(taPackage.navRoutes[name].variants["chasm-is-clear"])
                end
            end)

            it("names the variants it knows when given one it doesn't", function()
                helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clea")
                local out = lastEchoes()
                assert.is_truthy(out:find("I don't know a 'chasm-is-clea' variant of town-3/part-2",
                                          1, true))
                assert.is_truthy(out:find("I know: chasm-is-clear.", 1, true))
                assert.are.equal(0, #helper.sendCalls)
            end)

            -- A destination we don't know is still reported whole. Splitting
            -- it would report a route we don't know AND a variant we don't
            -- know, which is two wrong answers to one typo.
            it("doesn't split an unknown destination into route and variant", function()
                helper.simulateAlias("navigate-to town-3/part-9 chasm-is-clear")
                assert.is_truthy(lastEchoes():find(
                    "I don't know a route to 'town-3/part-9 chasm-is-clear'", 1, true))
            end)

            -- The flags still peel off around it: `quiet` goes, the variant
            -- stays, and what's left is the route.
            it("takes the variant alongside the trailing flags", function()
                helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear quiet")
                answerProbe(426)
                helper.simulateLine(
                    "You are carrying a coil of rope, and a verbena potion.")
                local out = lastEchoes()
                assert.is_truthy(out:find("Walking to town-3/part-2 chasm-is-clear", 1, true))
                assert.is_truthy(out:find("197 steps", 1, true))
                assert.is_falsy(out:find("trace on", 1, true))
            end)

            -- End to end on a variant that does have steps: the walk sets off,
            -- counts the variant's ending, and says which one it's walking.
            it("walks a recorded variant and says so", function()
                local r = taPackage.navRoutes["town-3/part-1"]
                r.variants = { ["chasm-is-clear"] = { keep = 2, steps = { "n" } } }
                helper.simulateAlias("navigate-to town-3/part-1 chasm-is-clear")
                answerProbe(274)
                helper.simulateLine("You are carrying a coil of rope, and a verbena potion.")
                local out = lastEchoes()
                assert.is_truthy(out:find("Walking to town-3/part-1 chasm-is-clear", 1, true))
                assert.is_truthy(out:find("3 steps", 1, true))
                assert.are.equal(1, sent("sw"))
                r.variants = nil
            end)

        end)

        -- get-platinum-key-from-63 is get-platinum-key with its first two steps
        -- taken off: `s` through the ruby door and `d` down to the junction.
        -- They are kept as two transcripts rather than one shared table, so this
        -- is what stops a correction to either from silently splitting them.
        describe("the platinum errand from the junction", function()

            it("is the long errand minus its walk down from the ruby door", function()
                local full  = taPackage.navRoutes["town-3/get-platinum-key"].steps
                local short = taPackage.navRoutes["town-3/get-platinum-key-from-63"].steps
                assert.are.equal("s", full[1])
                assert.are.equal("d", full[2])
                assert.are.equal(#full - 2, #short)
                for i = 1, #short do
                    assert.are.same(full[i + 2], short[i])
                end
            end)

            -- The long errand ends at the junction, so the short one both starts
            -- and ends there -- which is what lets it be run on its own, and
            -- what lets after-doors splice it in without moving us.
            it("starts and ends at the junction the doors open off", function()
                local r = taPackage.navRoutes["town-3/get-platinum-key-from-63"]
                assert.are.equal("sewers/town-sewers-63", r.from)
                assert.are.equal("sewers/town-sewers-63", r.to)
                assert.are.equal(taPackage.navRoutes["town-3/get-platinum-key"].to, r.to)
            end)

        end)

        describe("the town-2 route home", function()

            local function askToWalk()
                helper.simulateAlias("navigate-to town-2")
                brief("town square")
                helper.simulateLine("Exits: ne,e,se,sw,nw.")
            end

            it("is 201 steps from the town square to the north plaza", function()
                local r = taPackage.navRoutes["town-2"]
                -- Literal at both ends so the leg runs on a host with no map,
                -- the same reason ruined-town states both of its ends.
                assert.are.same({ room = "town square", exits = "e,ne,nw,se,sw" }, r.from)
                assert.are.same({ room = "north plaza" }, r.to)
                assert.are.equal(201, #r.steps)
            end)

            -- The stone teleports rather than opening a wall, and the game glues
            -- the arrival onto the push message, so no room brief fires for it.
            -- A cmd step advances on a pause, which is the only thing that can
            -- advance it -- if this ever became a direction the walk would hang.
            it("takes one command, and it is the stone", function()
                local cmds = {}
                for i, step in ipairs(taPackage.navRoutes["town-2"].steps) do
                    if type(step) ~= "string" then cmds[#cmds + 1] = { i = i, step = step } end
                end
                assert.are.equal(1, #cmds)
                assert.are.equal("push stone", cmds[1].step.cmd)
            end)

            -- The one stretch both routes describe: the path between the plaza
            -- and the sewers. A typo in either end shows up here.
            it("ends by reversing ruby-door's first two steps", function()
                local out  = taPackage.navRoutes["town-3/ruby-door"].steps
                local back = taPackage.navRoutes["town-2"].steps
                local OPP  = { n = "s", s = "n", e = "w", w = "e", ne = "sw",
                               sw = "ne", nw = "se", se = "nw", u = "d", d = "u" }
                assert.are.equal(OPP[out[1]], back[#back])
                assert.are.equal(OPP[out[2]], back[#back - 1])
            end)

            -- The trap door drops you into the pit going this way too, and the
            -- walls can't be climbed unaided, so nothing moves until the rope
            -- is confirmed.
            it("asks for the rope before setting off", function()
                askToWalk()
                assert.are.equal(1, sent("i"))
                assert.are.equal(0, sent("e"))
            end)

            it("sets off east into the stoneworks once the rope is there", function()
                askToWalk()
                helper.simulateLine("You are carrying a coil of rope and a glowstone.")
                assert.are.equal(1, sent("e"))
            end)

            -- Second town's north plaza is where this route ENDS. Setting off
            -- from it would walk 201 steps of stoneworks into the sewers' walls.
            it("refuses to walk it from the north plaza", function()
                helper.simulateAlias("navigate-to town-2")
                answerProbe(274)
                assert.are.equal(0, sent("i"))
                assert.are.equal(0, sent("e"))
                assert.is_truthy(lastEchoes():find("I don't know how to get there from here.", 1, true))
            end)

            it("walks on a host whose map is empty", function()
                helper.mockDbOneRow = function() return nil end
                helper.mockDbRows = function() return {} end
                askToWalk()
                helper.simulateLine("You are carrying a coil of rope.")
                assert.are.equal(1, sent("e"))
                assert.is_falsy(lastEchoes():find("known areas", 1, true))
            end)

        end)

    end)

    -- Where the map can't tell one room from another -- the stoneworks has
    -- twenty-four chambers sharing eleven fingerprints between them -- a route
    -- states its start literally instead of naming a room.
    describe("a start given as a fingerprint", function()

        local FROM = { room = "north plaza", exits = "e,n,s,sw,w" }

        it("walks when the room we're in matches", function()
            route({ from = FROM })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))
        end)

        -- The game lists exits in its own order; the route writes them in any.
        it("does not care what order the exits are listed in", function()
            route({ from = { room = "north plaza", exits = "w,sw,s,n,e" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))
        end)

        it("refuses when the exits don't match", function()
            route({ from = FROM })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(1)               -- first-town's north plaza: more exits
            assert.are.equal(0, sent("sw"))
            local out = lastEchoes()
            assert.is_truthy(out:find("I don't know how to get there from here.", 1, true))
            assert.is_truthy(out:find("a room called 'north plaza' with exits e,n,s,sw,w", 1, true))
        end)

        it("refuses when the room name doesn't match", function()
            route({ from = { room = "grand hall", exits = "e,n,s,sw,w" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(0, sent("sw"))
            assert.is_truthy(lastEchoes():find("I don't know how to get there from here.", 1, true))
        end)

        -- Some rooms have never had an `ex` run in them, so their exit-set
        -- isn't known. A name-only check is worth more than none, but it is
        -- weak, and it says so rather than pretending otherwise.
        it("accepts a start given as a name alone, and warns that it is weak", function()
            route({ from = { room = "north plaza" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))
            local out = lastEchoes()
            assert.is_truthy(out:find("Going on the room name alone", 1, true))
            -- ...and reports what it saw, so the check can be tightened.
            assert.is_truthy(out:find("exits are e,n,s,sw,w", 1, true))
        end)

        it("still refuses a name-only start in a differently named room", function()
            route({ from = { room = "grand hall" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(0, sent("sw"))
        end)

        -- A fingerprint start must not quietly skip the other pre-flight check.
        it("still checks the pack for what the route needs", function()
            route({ from = FROM, requires = "coil of rope" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(1, sent("i"))
            assert.are.equal(0, sent("sw"))
            helper.simulateLine("You are carrying a coil of rope.")
            assert.are.equal(1, sent("sw"))
        end)

    end)

    -- The trace exists to answer a specific question: what interval the game
    -- will accept without tripping us. That is a question about gaps, so every
    -- line carries the time since the previous traced event.
    describe("the timing trace", function()

        -- On by default: a trip we have to remember to ask for is a trip we
        -- mostly miss, and catching them is the whole point while the pace is
        -- still being tuned.
        it("traces a plain walk without being asked", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            local out = lastEchoes()
            assert.is_truthy(out:find("[nav|t]", 1, true))
            assert.is_truthy(out:find("send step 1/3 sw", 1, true))
        end)

        it("reports the pace and encumbrance it started with", function()
            route()
            setEncumberance(120, 200)
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            -- Read the pace rather than repeating it: it is still being tuned,
            -- and a literal here just breaks on the next adjustment.
            assert.is_truthy(lastEchoes():find(
                "pace " .. taPackage.navStepDelayMs .. "ms, encumbrance 60%", 1, true))
        end)

        it("says so when encumbrance has never been read", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("encumbrance unknown (run st)", 1, true))
        end)

        it("can be silenced with quiet", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18 quiet")
            answerProbe(274)
            assert.is_falsy(lastEchoes():find("[nav|t]", 1, true))
            assert.are.equal(1, sent("sw"))   -- and still walks
        end)

        it("still resolves the destination with debug appended", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18 debug")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))   -- not treated as an unknown route
        end)

        it("records how far into the walk a trip happened", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18 debug")
            answerProbe(274)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("In your haste, you trip and fall!")
            assert.is_truthy(lastEchoes():find("TRIPPED on step 2/3", 1, true))
        end)

        it("summarises the walk when it ends", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18 debug")
            answerProbe(274)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")
            assert.is_truthy(lastEchoes():find("walk ended: 3/3 steps, 0 trip(s)", 1, true))
        end)

    end)

    describe("the start check", function()

        it("probes the room before moving", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(1, sent(""))
            assert.are.equal(1, sent("ex"))
            assert.are.equal(0, sent("sw"))  -- nothing walked until the probe answers
        end)

        it("walks the first step when the fingerprint is the route's start", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))
        end)

        -- The whole reason the check fingerprints instead of matching on name.
        it("refuses from the same-named room in another town", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(1)  -- first-town's north plaza: same name, different exits
            local out = lastEchoes()
            assert.is_truthy(out:find("I don't know how to get there from here.", 1, true))
            assert.is_truthy(out:find("first-town/north-plaza", 1, true))
            assert.is_truthy(out:find("starts at second-town/north-plaza", 1, true))
            assert.are.equal(0, sent("sw"))
        end)

        it("refuses when the room matches nothing mapped", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            helper.simulateLine("You're in the mysterious grotto.")
            helper.simulateLine("Exits: n,s.")
            assert.is_truthy(lastEchoes():find("no room I have mapped", 1, true))
            assert.are.equal(0, sent("sw"))
        end)

        it("reports a probe that never comes back", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            helper.fireTimers(5000)
            assert.is_truthy(lastEchoes():find("never told me what room I'm in", 1, true))
            assert.are.equal(0, sent("sw"))
        end)

    end)

    -- The user also plays from a VPS with no tele-arena.db, and dbOpen makes an
    -- empty one silently rather than failing -- so on that machine every map
    -- reference in every route fails to resolve, and navigate-to refused before
    -- sending a thing. But the map contributes no DIRECTIONS: a route's steps
    -- are literals, and the map is only ever asked to check where we are. So
    -- walk, and say what couldn't be checked.
    describe("on a machine with no map", function()

        -- An empty tele-arena.db: no areas, no rooms, no error.
        local function noMap()
            helper.mockDbOneRow = nil
            helper.mockDbRows = {}
        end

        it("walks a route whose ends it can't resolve", function()
            route()
            noMap()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(1, sent("ex"))
            helper.simulateLine("You're in the north plaza.")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            assert.are.equal(1, sent("sw"))
        end)

        -- Said once, before anything is sent. A walk that quietly checked
        -- nothing would be the worst of both.
        it("says up front which checks it can't make", function()
            route()
            noMap()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            local out = lastEchoes()
            assert.is_truthy(out:find("No map on this machine", 1, true))
            assert.is_truthy(out:find("can't check where this route starts or where it ends",
                1, true))
            assert.is_truthy(out:find("walking on the recorded directions alone", 1, true))
        end)

        -- A route can name one end as a map reference and the other as a
        -- fingerprint, and the fingerprint end is checked here as well as
        -- anywhere -- so it must not be listed among the losses.
        it("doesn't claim to have lost a check it can still make", function()
            route({ from = { room = "north plaza", exits = "e,n,s,sw,w" } })
            noMap()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            local out = lastEchoes()
            assert.is_truthy(out:find("can't check where it ends", 1, true))
            assert.is_falsy(out:find("where this route starts", 1, true))
            -- ...and the start really is still checked, from the fingerprint.
            helper.simulateLine("You're in the north plaza.")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            assert.are.equal(1, sent("sw"))
        end)

        it("still refuses a fingerprint start that doesn't match, map or no map", function()
            route({ from = { room = "north plaza", exits = "e,n,s,sw,w" } })
            noMap()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            helper.simulateLine("You're in the mysterious grotto.")
            helper.simulateLine("Exits: n,s.")
            assert.are.equal(0, sent("sw"))
            assert.is_truthy(lastEchoes():find("I don't know how to get there from here.", 1, true))
        end)

        -- And says where we actually are, which is all the user has to go on.
        it("names the room it found instead of the one it expected", function()
            route()
            noMap()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            helper.simulateLine("You're in the north plaza.")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            local out = lastEchoes()
            assert.is_truthy(out:find("can't check I'm at second-town/north-plaza", 1, true))
            assert.is_truthy(out:find("I'm in 'north plaza' with exits e,n,s,sw,w", 1, true))
            assert.is_falsy(out:find("I don't know how to get there from here.", 1, true))
        end)

        -- The distinction the whole thing turns on: no areas at all is a machine
        -- without a map, and one unknown area among others is a broken route.
        -- The second still refuses, exactly as before.
        it("still refuses a bad reference when there IS a map", function()
            route({ from = "nowhere/at-all" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(0, #helper.sendCalls)
            local out = lastEchoes()
            assert.is_truthy(out:find("there's no area called 'nowhere'", 1, true))
            assert.is_falsy(out:find("No map on this machine", 1, true))
        end)

        it("still refuses a room that doesn't exist in an area that does", function()
            route({ to = "second-town/no-such-room" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(0, #helper.sendCalls)
            assert.is_truthy(lastEchoes():find("there's no room 'no-such-room'", 1, true))
        end)

        -- Seams are the checks that survive, and which ones survive depends on
        -- how the leg names its starting room.
        describe("seams", function()

            local function joined(legTwoFrom)
                taPackage.navRoutes["sewers/leg-one"] =
                    { from = "second-town/north-plaza", steps = { "sw", "d" } }
                taPackage.navRoutes["sewers/leg-two"] =
                    { from = legTwoFrom, steps = { "se" } }
                taPackage.navRoutes["sewers/joined"] =
                    { from = "second-town/north-plaza",
                      legs = { "sewers/leg-one", "sewers/leg-two" } }
            end

            local function walkToTheSeam(legTwoFrom)
                joined(legTwoFrom)
                noMap()
                helper.simulateAlias("navigate-to sewers/joined")
                helper.simulateLine("You're in the north plaza.")
                helper.simulateLine("Exits: e,n,s,sw,w.")
                helper.simulateLine("You're on a path.")          -- sw
                helper.fireTimers(taPackage.navStepDelayMs)
                helper.simulateLine("You're in the town sewers.") -- d
                helper.fireTimers(taPackage.navStepDelayMs)       -- the seam probe
            end

            -- A seam naming a mapped room: nothing here can identify it, so the
            -- walk is no worse off than it is between any two ordinary steps.
            it("carries on past a seam that names a map reference", function()
                walkToTheSeam("sewers/town-sewers-18")
                helper.simulateLine("You're in the town sewers.")
                helper.simulateLine("Exits: u,se.")
                local out = lastEchoes()
                assert.is_truthy(out:find(
                    "No map here, so the sewers/leg-two seam can't be checked", 1, true))
                assert.is_truthy(out:find("I'm in 'town sewers' with exits se,u", 1, true))
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(1, sent("se"))
            end)

            -- A seam that fingerprints its room needs no map and keeps working.
            -- This is the one that matters: below the riddle door nothing is
            -- mapped, so six of the third-town chain's seven seams are these.
            it("still checks a seam that names the room outright", function()
                walkToTheSeam({ room = "town sewers", exits = "u,se" })
                helper.simulateLine("You're in the town sewers.")
                helper.simulateLine("Exits: u,se.")
                assert.is_truthy(lastEchoes():find("At the sewers/leg-two seam", 1, true))
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(1, sent("se"))
            end)

            -- And still STOPS on one, which is the whole reason they're worth
            -- keeping: an unmapped walk that drifts is caught at the next seam.
            it("still stops at a fingerprint seam that doesn't match", function()
                walkToTheSeam({ room = "town sewers", exits = "u,se" })
                helper.simulateLine("You're in the mysterious grotto.")
                helper.simulateLine("Exits: n,s.")
                assert.is_truthy(lastEchoes():find("seam I expected", 1, true))
                assert.is_nil(taPackage.navigate)
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(0, sent("se"))
            end)

        end)

        -- The route this was built for. Six of its seven seams are fingerprints
        -- and survive; the seventh names sewers/town-sewers-165 and doesn't.
        it("counts what survives on the third-town chain", function()
            noMap()
            helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear")
            local out = lastEchoes()
            assert.is_truthy(out:find("or 1 of its 7 seams", 1, true))
            assert.is_truthy(out:find("6 seams name the room outright", 1, true))
            assert.is_truthy(out:find("those are still checked", 1, true))
        end)

        it("walks the third-town chain rather than refusing", function()
            noMap()
            helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear")
            helper.simulateLine("You're in the town sewers.")
            helper.simulateLine("Exits: e,n,s,u.")
            helper.simulateLine(
                "You are carrying a coil of rope, and a verbena potion.")
            assert.is_truthy(lastEchoes():find("197 steps", 1, true))
            assert.are.equal(1, sent("s"))
        end)

    end)

    -- The BBS hangs up 56 steps into a 197-step walk. The trace says which step
    -- that was, and re-walking the first 55 by hand to get back to it is half an
    -- hour. `from-step N` picks the walk up there instead.
    describe("resuming a walk in the middle", function()

        local LONG = { "sw", "d", "se", "e", "n" }

        local function resumeAt(n, from)
            route({ steps = LONG })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 from-step " .. n)
            answerProbe(from or 274)
        end

        it("sends the step it was told to, not the first one", function()
            resumeAt(3)
            assert.are.equal(0, sent("sw"))   -- steps 1 and 2 are behind us
            assert.are.equal(0, sent("d"))
            assert.are.equal(1, sent("se"))
        end)

        it("carries on from there to the end", function()
            resumeAt(3)
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("e"))
            helper.simulateLine("You're in a wide sewer tunnel.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("n"))
        end)

        it("counts what is left, not the whole route", function()
            resumeAt(3)
            assert.is_truthy(lastEchoes():find("from step 3 — 3 of its 5 steps left", 1, true))
        end)

        -- The start check is the one thing a resume cannot have: we are in the
        -- middle of the route, so the room it would check for is the room we are
        -- guaranteed NOT to be in.
        it("walks from a room that isn't the route's start", function()
            resumeAt(3, 1)   -- first-town's north plaza; the route starts in second-town's
            assert.are.equal(1, sent("se"))
            local out = lastEchoes()
            assert.is_falsy(out:find("I don't know how to get there from here.", 1, true))
            assert.is_truthy(out:find("taking your word", 1, true))
            assert.is_truthy(out:find("north plaza", 1, true))   -- says where we actually are
        end)

        -- Still probes, though: a resume that never gets an answer is a resume
        -- that doesn't know whether the connection is back.
        it("still waits for the room probe before moving", function()
            route({ steps = LONG })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 from-step 3")
            assert.are.equal(1, sent("ex"))
            assert.are.equal(0, sent("se"))
        end)

        it("still checks what we're carrying", function()
            route({ steps = LONG, requires = "coil of rope" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 from-step 3")
            answerProbe(274)
            assert.are.equal(1, sent("i"))
            assert.are.equal(0, sent("se"))
            helper.simulateLine("You are carrying a coil of rope.")
            assert.are.equal(1, sent("se"))
        end)

        it("refuses a step number the route doesn't have", function()
            resumeAt(9)
            assert.are.equal(0, sent("se"))
            assert.is_nil(taPackage.navigate)
            assert.is_truthy(lastEchoes():find("is 5 steps, so there's no step 9", 1, true))
        end)

        it("refuses step zero", function()
            resumeAt(0)
            assert.is_truthy(lastEchoes():find("no step 0", 1, true))
        end)

        -- Two words where every other flag is one, and it can be given in any
        -- order alongside them.
        it("takes from-step alongside the other flags", function()
            route({ steps = LONG })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 from-step 3 quiet")
            answerProbe(274)
            assert.are.equal(1, sent("se"))
            assert.is_falsy(lastEchoes():find("[nav|t]", 1, true))
        end)

        it("takes it before the other flags too", function()
            route({ steps = LONG })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 quiet from-step 3")
            answerProbe(274)
            assert.are.equal(1, sent("se"))
        end)

        it("still knows the destination when from-step is given", function()
            resumeAt(3)
            assert.is_falsy(lastEchoes():find("I don't know a route", 1, true))
        end)

        -- A locked door splices its key errand into the walk, which renumbers
        -- every step after it -- so on a gated route the trace's number is only
        -- an index into THIS list if no errand had gone in yet.
        it("warns that a gated route's numbering can have shifted", function()
            helper.simulateAlias("navigate-to town-3/part-1 from-step 20")
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("renumbers every step after them", 1, true))
            assert.is_truthy(lastEchoes():find("'/22'", 1, true))
        end)

        it("says nothing about renumbering on a route with no doors", function()
            resumeAt(3)
            assert.is_falsy(lastEchoes():find("renumbers", 1, true))
        end)

        -- The real case, end to end: the 197-step chasm-is-clear walk cut off at
        -- step 56, picked up from the room it stopped in.
        it("resumes the third-town chain at the step the trace named", function()
            helper.simulateAlias("navigate-to town-3/part-2 chasm-is-clear from-step 56")
            answerProbe(426)
            helper.simulateLine(
                "You are carrying a coil of rope, and a verbena potion.")
            local out = lastEchoes()
            assert.is_truthy(out:find("Walking to town-3/part-2 chasm-is-clear from step 56"
                .. " — 142 of its 197 steps left", 1, true))
            local flat = taPackage.navRouteSteps(
                taPackage.navRoutes["town-3/part-2"], "chasm-is-clear")
            assert.are.equal(1, sent(flat[56]))
            -- index counts steps started, and step 56 has now been sent.
            assert.are.equal(56, taPackage.navigate.index)
        end)

    end)

    describe("walking", function()

        local function startWalking()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("paces one step per arrival, in order", function()
            startWalking()
            assert.are.equal(1, sent("sw"))

            helper.simulateLine("You're on a path.")
            assert.are.equal(0, sent("d"))   -- not until the pacing delay elapses
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("d"))

            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

        -- A walk inherits its arrival phrasings from the room triggers, so an
        -- unhandled preposition doesn't misread a step -- it drops it, and the
        -- walk waits forever for a brief that has already gone past. That is
        -- what "You're outside the town gates." did on 2026-08-04, two steps
        -- into ruined-town.
        it("advances on an 'outside' arrival brief", function()
            startWalking()
            helper.simulateLine("You're outside the town gates.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("d"))
        end)

        -- The map is read-only to navigate-to. Setting pendingDirection is an
        -- instruction to the mapper to record an edge, so a walk must not; a
        -- stale one left behind would also dead-reckon the user's next manual
        -- move from a room many steps away.
        it("never sets pendingDirection", function()
            startWalking()
            assert.is_nil(taPackage.pendingDirection)
        end)

        -- The room description a `look` produces opens with "You are in ...",
        -- which is indistinguishable from an arrival by wording alone.
        it("is not advanced by a look reply", function()
            startWalking()
            helper.simulateLine("look")           -- the game echoes the command
            helper.simulateLine("You are in a wide sewer tunnel.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(0, sent("d"))
        end)

        it("announces arrival at the end of the step list", function()
            startWalking()
            helper.simulateLine("You're on a path.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")   -- 3rd and last step
            assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        it("stops rather than guessing when the last room is the wrong one", function()
            startWalking()
            helper.simulateLine("You're on a path.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the grand hall.")
            assert.is_truthy(lastEchoes():find("ended up in 'grand hall'", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- A `to` stated literally checks arrival on the brief's name alone,
        -- which is all the check ever compared -- so it holds up where the map
        -- can't answer at all.
        describe("with the far end named literally", function()

            local function startWalkingTo(roomName)
                route({ to = { room = roomName } })
                helper.simulateAlias("navigate-to sewers/town-sewers-18")
                answerProbe(274)
                helper.fireTimers(taPackage.navStepDelayMs)
            end

            it("announces arrival when the last brief names that room", function()
                startWalkingTo("ruined plaza")
                helper.simulateLine("You're on a path.")
                helper.fireTimers(taPackage.navStepDelayMs)
                helper.simulateLine("You're in the town sewers.")
                helper.fireTimers(taPackage.navStepDelayMs)
                -- The article is dropped before the name is compared.
                helper.simulateLine("You're in a ruined plaza.")
                assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
                assert.is_nil(taPackage.navigate)
            end)

            it("stops when it names some other room", function()
                startWalkingTo("ruined plaza")
                helper.simulateLine("You're on a path.")
                helper.fireTimers(taPackage.navStepDelayMs)
                helper.simulateLine("You're in the town sewers.")
                helper.fireTimers(taPackage.navStepDelayMs)
                helper.simulateLine("You're in an ancient temple.")
                assert.is_truthy(lastEchoes():find("ended up in 'ancient temple'", 1, true))
                assert.is_nil(taPackage.navigate)
            end)

        end)

    end)

    describe("moves the game refuses", function()

        local function startWalking()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("stops on a direction with no exit and names the step", function()
            startWalking()
            helper.simulateLine("Sorry, there's no exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("step 1 of 3 (sw)", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- A trip is now two-phase: wait out the stumble, look at the floor (the
        -- fall may have cost us an item), then walk on.
        it("re-sends the same step after a trip, without advancing", function()
            startWalking()
            assert.are.equal(1, sent("sw"))
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(taPackage.navTripRetryMs)
            brief("north plaza")               -- the reply to our floor check
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("sw"))    -- same step again
            assert.are.equal(0, sent("d"))     -- and the walk did not advance
        end)

        it("swallows a room reprint after a trip rather than counting it", function()
            startWalking()
            helper.simulateLine("In your haste, you trip and fall!")
            helper.simulateLine("You're in the north plaza.")  -- reprint, not an arrival
            helper.fireTimers(taPackage.navTripRetryMs)
            brief("north plaza")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("sw"))
            assert.are.equal(0, sent("d"))
        end)

        -- Being winded is the fight catching up, not the pace. Every one of the
        -- twelve seen in play landed on the first move after a kill-all.
        describe("winded after a fight", function()

            it("retries the move without checking the floor", function()
                startWalking()
                -- The opening probe sends one bare return of its own.
                local returns = sent("")
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.fireTimers(taPackage.navRestRetryMs)
                assert.are.equal(2, sent("sw"))
                -- No further bare return: nothing was dropped, nothing to look for.
                assert.are.equal(returns, sent(""))
                assert.is_falsy(lastEchoes():find("Nothing dropped in the fall", 1, true))
            end)

            it("is not counted as a trip", function()
                startWalking()
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.simulateAlias("stop-navigating")
                local out = lastEchoes()
                assert.is_truthy(out:find("0 trip(s)", 1, true))
                assert.is_truthy(out:find("winded 1x", 1, true))
            end)

            it("reports the first and then every fifth", function()
                startWalking()
                for _ = 1, 5 do
                    helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                    helper.fireTimers(taPackage.navRestRetryMs)
                end
                local out = lastEchoes()
                assert.are.equal(2, select(2, out:gsub("Winded from the fight", "")))
                assert.is_truthy(out:find("attempt 5", 1, true))
            end)

            -- Counted from the step, not from the walk. after-doors clears three
            -- rooms and comes out of each winded, and its first live run
            -- announced the third episode as "attempt 20" -- which reads as one
            -- move refused twenty times rather than the first refusal of a new
            -- one. The walk total is still what the closing trace reports.
            it("counts the attempts against the move, not the whole walk", function()
                startWalking()
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.fireTimers(taPackage.navRestRetryMs)
                brief("path")                                  -- the move gets through
                helper.fireTimers(taPackage.navStepDelayMs)    -- on to the next step
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                local out = lastEchoes()
                assert.are.equal(2, select(2, out:gsub("attempt 1%)", "")))
                assert.is_falsy(out:find("attempt 2", 1, true))
                helper.simulateAlias("stop-navigating")
                assert.is_truthy(lastEchoes():find("winded 2x", 1, true))
            end)

            it("walks on once the move gets through", function()
                startWalking()
                helper.simulateLine("Sorry, you'll have to rest a while before you can move.")
                helper.fireTimers(taPackage.navRestRetryMs)
                brief("north plaza")
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(1, sent("d"))
            end)

        end)

    end)

    -- Tripping sometimes shakes an item out of the pack, and the game says
    -- nothing when it does, so the only tell is the floor changing.
    describe("items dropped in a fall", function()

        local function tripAfterStartingOn(startFloor)
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274, startFloor)
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(taPackage.navTripRetryMs)
        end

        it("looks at the floor before walking on", function()
            tripAfterStartingOn(nil)
            assert.are.equal(2, sent(""))  -- the opening probe, then the floor check
        end)

        it("picks up an item that appeared", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a yarrow potion")
            assert.are.equal(1, sent("get yarrow"))
            assert.is_truthy(lastEchoes():find("shook loose the yarrow potion", 1, true))
        end)

        -- `get` reads one word and ignores the rest, and which word answers is
        -- not predictable: "a coil of rope" takes `get rope` but refuses
        -- `get coil` — and `get coil of rope` is read as `get coil`, so passing
        -- the whole name is no help. This is the live failure from 2026-08-01.
        it("falls back to another word when the first is not recognised", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a coil of rope")
            assert.are.equal(1, sent("get coil"))
            helper.simulateLine("Sorry, but no such item is here.")
            assert.are.equal(1, sent("get rope"))       -- last word next
            assert.are.equal(0, sent("get coil of rope"))
        end)

        it("confirms the pick-up when the game accepts a word", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a coil of rope")
            helper.simulateLine("Sorry, but no such item is here.")
            helper.simulateLine("Ok, you got a coil of rope.")
            assert.is_truthy(lastEchoes():find("Picked the coil of rope back up.", 1, true))
        end)

        it("gives up loudly when no word is recognised", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a coil of rope")
            helper.simulateLine("Sorry, but no such item is here.")
            helper.simulateLine("Sorry, but no such item is here.")
            assert.is_truthy(lastEchoes():find("Couldn't work out how to pick the coil of rope", 1, true))
        end)

        it("works through several dropped items in turn", function()
            tripAfterStartingOn(nil)
            helper.simulateLine("There is a waterskin, and a torch lying on the floor.")
            assert.are.equal(1, sent("get torch"))      -- alphabetical: torch first
            helper.simulateLine("Ok, you got a torch.")
            assert.are.equal(1, sent("get waterskin"))
        end)

        -- The case that motivated comparing against the room's floor rather than
        -- our inventory: the sewers really do have a rue potion lying in one room.
        it("leaves an item that was already there", function()
            tripAfterStartingOn("a rue potion")
            brief("north plaza", "a rue potion")
            assert.are.equal(0, sent("get rue potion"))
            assert.is_truthy(lastEchoes():find("Nothing dropped in the fall.", 1, true))
        end)

        it("picks up only what is new when something was already there", function()
            tripAfterStartingOn("a rue potion")
            helper.simulateLine("There is a rue potion, and a yarrow potion lying on the floor.")
            assert.are.equal(1, sent("get yarrow"))
            assert.are.equal(0, sent("get rue"))
        end)

        -- Duplicates are real ("a bronze key, a waterskin, and a bronze key"),
        -- so the comparison counts copies rather than treating the floor as a set.
        it("notices a second copy of an item already on the floor", function()
            tripAfterStartingOn("a bronze key")
            helper.simulateLine("There is a bronze key, and a bronze key lying on the floor.")
            assert.are.equal(1, sent("get bronze"))
        end)

        it("walks on when nothing was dropped", function()
            tripAfterStartingOn(nil)
            brief("north plaza")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("sw"))
        end)

        it("walks on after picking something up", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a yarrow potion")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("sw"))
        end)

        it("reports a pick-up refused for encumbrance", function()
            tripAfterStartingOn(nil)
            brief("north plaza", "a yarrow potion")
            helper.simulateLine("You can't carry anything else.")
            assert.is_truthy(lastEchoes():find("pack is full", 1, true))
        end)

        -- Guessing here risks pocketing someone else's property.
        it("refuses to guess when the room's floor was never seen", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateLine("You're on a path.")   -- arrival with no floor line
            taPackage.navigate.floor = nil             -- so this room's floor is unknown
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(taPackage.navTripRetryMs)
            assert.is_truthy(lastEchoes():find("never saw this room's floor", 1, true))
            assert.are.equal(1, sent(""))              -- no floor check sent
        end)

        it("tracks the floor of each room it walks into", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274, "a rue potion")
            brief("path", "a torch")                   -- arrival in the next room
            assert.are.same({ "torch" }, taPackage.navigate.floor)
        end)

    end)

    describe("the locked door at the end of a route", function()

        local function walkToTheDoor()
            route({ door = { dir = "s", key = "ruby" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateLine("You're on a path.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")  -- arrived
            helper.fireTimers(taPackage.navStepDelayMs)                            -- door probe fires
        end

        it("tries the door direction after arriving", function()
            walkToTheDoor()
            assert.are.equal(1, sent("s"))
        end)

        it("stops and asks for the key when the door is locked", function()
            walkToTheDoor()
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("A locked stone door blocks the way", 1, true))
            assert.is_truthy(out:find("I need to go get the key (the ruby key).", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- Not every locked door is a route's final probe: the platinum errand
        -- walks through the ruby door on its first step. Naming the step is
        -- what says which door was shut.
        it("names the step when a door blocks the middle of a route", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("blocks step 1 of sewers/town-sewers-18", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        it("reports the key it already holds when the door opens", function()
            walkToTheDoor()
            helper.simulateLine("Your ruby key unlocks the stone door and allows you to pass through.")
            helper.simulateLine("You're in the town sewers.")
            local out = lastEchoes()
            assert.is_truthy(out:find("My ruby key opened the door", 1, true))
            assert.is_truthy(out:find("needs no detour", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        it("says so when the door is simply open", function()
            walkToTheDoor()
            helper.simulateLine("You're in the town sewers.")
            assert.is_truthy(lastEchoes():find("door was already open", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- Passing the door leaves us one room PAST the route's destination, and
        -- "town sewers" (shared by 170 rooms) says nothing about where that is,
        -- so the room is named from the map instead.
        it("names the room beyond the door from the map", function()
            -- 359 --s--> 425 is the ruby-keyed stone door in the real graph.
            helper.mockDbOneRow = function(sql, params)
                if string.find(sql, "FROM areas WHERE slug", 1, true) then
                    return params[1] == "second-town" and { id = 7 }
                        or (params[1] == "sewers" and { id = 8 } or nil)
                end
                if string.find(sql, "SELECT to_id FROM room_exits", 1, true) then
                    return { to_id = 425 }
                end
                if string.find(sql, "LEFT JOIN areas a ON a.id = r.area_id", 1, true) then
                    return params[1] == 425 and { slug = "town-sewers-62", area = "sewers" } or nil
                end
                return nil
            end
            walkToTheDoor()
            helper.simulateLine("You're in the town sewers.")
            local out = lastEchoes()
            assert.is_truthy(out:find("standing in sewers/town-sewers-62", 1, true))
            assert.is_truthy(out:find("one room past sewers/town-sewers-18", 1, true))
        end)

    end)

    -- navigate-to reads the map and never writes to it. Walking is not
    -- exploring: the rooms on a route are already known, and recording a
    -- scripted walk would count visits, stamp coordinates and move the player
    -- location for a trip the map has nothing to learn from.
    describe("leaving the map alone", function()

        local function countExecutes()
            local n = 0
            for _, c in ipairs(helper.dbCalls) do
                if c.method == "execute" then n = n + 1 end
            end
            return n
        end

        local function walkTheWholeRoute()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateLine("You're on a path.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            helper.simulateLine("You're in the town sewers.")
        end

        it("suspends mapping mode for the walk", function()
            taPackage.mapping = true
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.is_false(taPackage.mapping)
            assert.is_truthy(lastEchoes():find("Mapping was on — suspended it", 1, true))
        end)

        it("writes nothing to the database, even with mapping on", function()
            taPackage.mapping = true
            local before = countExecutes()
            walkTheWholeRoute()
            assert.are.equal(before, countExecutes())
        end)

        it("does not send the mapper's look/ex probes on arrival", function()
            taPackage.mapping = true
            walkTheWholeRoute()
            assert.are.equal(0, sent("look"))
            -- The one `ex` is the start-of-walk room probe, not a per-room scan.
            assert.are.equal(1, sent("ex"))
        end)

        -- Resuming would be worse than leaving it off: the mapper's anchor is
        -- wherever the walk began, so the next manual move would link an edge
        -- from a room many steps away and mint duplicates.
        it("leaves mapping off afterwards and says how to re-anchor", function()
            taPackage.mapping = true
            walkTheWholeRoute()
            assert.is_false(taPackage.mapping)
            assert.is_truthy(lastEchoes():find("Re-anchor with map-here <slug>", 1, true))
        end)

        it("says nothing about mapping when it was already off", function()
            taPackage.mapping = false
            walkTheWholeRoute()
            assert.is_falsy(lastEchoes():find("Re-anchor with map-here", 1, true))
            assert.is_falsy(lastEchoes():find("Mapping was on", 1, true))
        end)

        it("still reports the anchor when a walk is stopped part-way", function()
            taPackage.mapping = true
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateAlias("stop-navigating")
            assert.is_truthy(lastEchoes():find("Re-anchor with map-here <slug>", 1, true))
        end)

    end)

    -- A route can end by clearing the room, which is how a door key is come by:
    -- the game auto-searches each corpse and announces what it finds.
    describe("clearing the destination", function()

        -- Two moves, a sweep, then one more move: the shape of the ruby-key
        -- errand, which clears a room and then walks back the way it came.
        local SWEEP_STEPS = { "sw", "d", { killAll = true }, "se" }

        -- Walk as far as the sweep step and let it start.
        local function sweeping()
            route({ steps = SWEEP_STEPS })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")           -- 2nd step done; the sweep is next
            helper.fireTimers(taPackage.navStepDelayMs)
        end

        it("starts kill-all when it reaches a sweep step", function()
            sweeping()
            assert.is_truthy(lastEchoes():find("Clearing the room with kill-all", 1, true))
            assert.is_true(taPackage.killAllActive)
        end)

        it("does not start the sweep if the walk was stopped first", function()
            route({ steps = SWEEP_STEPS })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")
            helper.simulateAlias("stop-navigating")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.is_falsy(taPackage.killAllActive)
        end)

        -- The sweep's own scans reprint the room. Counting those as arrivals
        -- would run the step list on while the character stood still fighting.
        it("ignores the room briefs the sweep itself prints", function()
            sweeping()
            local before = sent("se")
            helper.simulateLine("You're in the town sewers.")
            helper.simulateLine("You're in the town sewers.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(before, sent("se"))
            assert.is_true(taPackage.killAllActive)   -- still sweeping
        end)

        it("walks on once the room is clear", function()
            sweeping()
            helper.simulateLine("There is nobody here.")   -- room clear, sweep ends
            assert.is_truthy(lastEchoes():find("Room cleared.", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
            brief("town sewers")
            assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- The three key errands each ran their sweep for 65-99 seconds, long
        -- after the key was in hand. A sweep that names what it wants stops
        -- when it has it.
        describe("a sweep that stops once it has what it came for", function()

            local WANT = { "sw", "d", { killAll = true, untilFound = "ruby key" }, "se" }

            local function sweepingFor()
                route({ steps = WANT })
                helper.simulateAlias("navigate-to sewers/town-sewers-18")
                answerProbe(274)
                brief("path")
                helper.fireTimers(taPackage.navStepDelayMs)
                brief("town sewers")
                helper.fireTimers(taPackage.navStepDelayMs)
            end

            it("says what it is fighting for", function()
                sweepingFor()
                assert.is_truthy(lastEchoes():find("Clearing the room until I get a ruby key", 1, true))
            end)

            -- Of the four keys these errands fetch, one starts with a vowel,
            -- and "until I get a onyx key" is what the first live run said.
            it("gets the article right for a key that starts with a vowel", function()
                route({ steps = { "sw", "d", { killAll = true, untilFound = "onyx key" }, "se" } })
                helper.simulateAlias("navigate-to sewers/town-sewers-18")
                answerProbe(274)
                brief("path")
                helper.fireTimers(taPackage.navStepDelayMs)
                brief("town sewers")
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.is_truthy(lastEchoes():find("until I get an onyx key", 1, true))
            end)

            it("stops fighting and walks on when it drops", function()
                sweepingFor()
                assert.is_true(taPackage.killAllActive)
                helper.simulateLine("While searching the area, you notice a ruby key, which you add to your possessions.")
                assert.is_falsy(taPackage.killAllActive)
                assert.is_nil(taPackage.navSweep)
                assert.is_truthy(lastEchoes():find("leaving the rest of the room", 1, true))
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(1, sent("se"))
            end)

            it("keeps fighting for anything else that turns up", function()
                sweepingFor()
                helper.simulateLine("While searching the area, you notice a bronze key, which you add to your possessions.")
                assert.is_true(taPackage.killAllActive)
                helper.fireTimers(taPackage.navStepDelayMs)
                assert.are.equal(0, sent("se"))
            end)

            -- Without a stated want, the old behaviour stands: clear the room.
            it("clears the whole room when nothing is named", function()
                route({ steps = { "sw", "d", { killAll = true }, "se" } })
                helper.simulateAlias("navigate-to sewers/town-sewers-18")
                answerProbe(274)
                brief("path")
                helper.fireTimers(taPackage.navStepDelayMs)
                brief("town sewers")
                helper.fireTimers(taPackage.navStepDelayMs)
                helper.simulateLine("While searching the area, you notice a ruby key, which you add to your possessions.")
                assert.is_true(taPackage.killAllActive)
            end)

            -- A monster that runs takes the key with it, and the room brief
            -- can't show that: by the time it says "nobody here" the monster is
            -- a room away. The departure line as it goes past is the only
            -- record of where the key went, so the sweep keeps a list.
            describe("noting a monster that walks out", function()

                local function gone()
                    return taPackage.navSweep and taPackage.navSweep.gone
                end

                it("records which way it went, and the way back", function()
                    sweepingFor()
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    assert.are.equal(1, #gone())
                    assert.are.equal("ogre mage", gone()[1].monster)
                    assert.are.equal("ne", gone()[1].out)
                    assert.are.equal("sw", gone()[1].back)
                end)

                -- "has just gone upward.", never "to the up".
                it("handles the vertical wording", function()
                    sweepingFor()
                    helper.simulateLine("The ogre mage has just gone downward.")
                    assert.are.equal("d", gone()[1].out)
                    assert.are.equal("u", gone()[1].back)
                end)

                -- The ogre mage in the live log left south, came back, and was
                -- still there to be killed. Chasing south afterwards would have
                -- walked away from the room the key was actually in.
                it("forgets a departure once that monster comes back", function()
                    sweepingFor()
                    helper.simulateLine("The ogre mage has just gone to the south.")
                    helper.simulateLine("An ogre mage has just arrived from the south.")
                    assert.are.equal(0, #gone())
                end)

                it("forgets it however it comes back", function()
                    sweepingFor()
                    helper.simulateLine("The ogre mage has just gone downward.")
                    helper.simulateLine("An ogre mage has just arrived from above.")
                    assert.are.equal(0, #gone())
                end)

                -- Players trip the same wording, and "^The " alone doesn't rule
                -- them out — a player may be called "The Ripper". Monster names
                -- are lowercase; player names are not.
                it("ignores a player walking out", function()
                    sweepingFor()
                    helper.simulateLine("Tojolias has just gone to the north.")
                    helper.simulateLine("The Ripper has just gone to the north.")
                    assert.is_falsy(gone())
                end)

                -- A sweep with nothing to find has nothing to chase.
                it("records nothing for a sweep that named no want", function()
                    route({ steps = { "sw", "d", { killAll = true }, "se" } })
                    helper.simulateAlias("navigate-to sewers/town-sewers-18")
                    answerProbe(274)
                    brief("path")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    assert.is_falsy(gone())
                end)

                -- A kill-all run by hand is nobody's business but the user's.
                it("leaves a hand-run sweep alone", function()
                    taPackage.killAllActive = true            -- as `kill-all` would
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    assert.is_nil(taPackage.navSweep)
                end)

            end)

            -- Cleared the room, no key, and something walked out mid-fight: it
            -- has the key. Follow it, clear that room, come home. The chase is
            -- three ordinary steps spliced in after the sweep step, so the
            -- errand's own next step still follows once we're back.
            --
            -- Directions here are all distinct from the route's own so `sent`
            -- can tell a chase leg from a step of the errand.
            describe("chasing a monster that walked off with the key", function()

                local CHASE = { "w", "d", { killAll = true, untilFound = "platinum key" }, "e" }

                local function chasing()
                    route({ steps = CHASE })
                    helper.simulateAlias("navigate-to sewers/town-sewers-18")
                    answerProbe(274)
                    brief("path")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)
                end

                -- Walk the chase leg and let the chased room's sweep start.
                local function intoTheChaseRoom()
                    chasing()
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    helper.simulateLine("There is nobody here.")   -- clear, and no key
                    helper.fireTimers(taPackage.navStepDelayMs)    -- the chase leg
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- the chased room's sweep
                end

                -- The live sequence: fled south, came back, fled northeast and
                -- stayed gone. Northeast is the one worth walking.
                it("follows the departure nobody saw come back", function()
                    chasing()
                    helper.simulateLine("The ogre mage has just gone to the south.")
                    helper.simulateLine("An ogre mage has just arrived from the south.")
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    helper.simulateLine("There is nobody here.")
                    assert.is_truthy(lastEchoes():find("the ogre mage left ne before it died", 1, true))
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("ne"))
                    assert.are.equal(0, sent("s"))    -- not the one it came back from
                    assert.are.equal(0, sent("e"))    -- the errand's own next step waits
                end)

                it("clears the chased room for the same thing", function()
                    intoTheChaseRoom()
                    assert.is_truthy(lastEchoes():find("Clearing the room until I get a platinum key", 1, true))
                    assert.is_true(taPackage.killAllActive)
                end)

                it("stops the chased room the moment the key turns up", function()
                    intoTheChaseRoom()
                    helper.simulateLine("While searching the area, you notice a platinum key, which you add to your possessions.")
                    assert.is_truthy(lastEchoes():find("leaving the rest of the room", 1, true))
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("sw"))   -- straight back the way we came
                end)

                -- A chase that finds nothing is not a new way for a run to
                -- stop: it walks home and lets the errand finish, and the door
                -- probe reports the locked door as it always did.
                it("walks back and carries on when the chase finds nothing", function()
                    intoTheChaseRoom()
                    helper.simulateLine("There is nobody here.")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("sw"))
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("e"))    -- the errand's own next step, at last
                    brief("town sewers")
                    assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
                end)

                it("does not chase a monster that came back", function()
                    chasing()
                    helper.simulateLine("The ogre mage has just gone to the south.")
                    helper.simulateLine("An ogre mage has just arrived from the south.")
                    helper.simulateLine("There is nobody here.")
                    assert.is_truthy(lastEchoes():find("Room cleared.", 1, true))
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("e"))
                    assert.are.equal(0, sent("s"))
                end)

                it("does not chase when nothing walked out", function()
                    chasing()
                    helper.simulateLine("There is nobody here.")
                    assert.is_truthy(lastEchoes():find("Room cleared.", 1, true))
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("e"))
                end)

                -- Two chases is two rooms off the route, which is as far as one
                -- runaway gets to drag us. The return legs unwind on their own:
                -- a nested chase splices ahead of the outer one's way home.
                it("follows a second flight, then lets the third go", function()
                    intoTheChaseRoom()
                    helper.simulateLine("The ogre mage has just gone to the north.")
                    helper.simulateLine("There is nobody here.")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(1, sent("n"))                 -- chased again
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)
                    helper.simulateLine("The ogre mage has just gone to the northwest.")
                    helper.simulateLine("There is nobody here.")
                    assert.is_truthy(lastEchoes():find("2 rooms off the route already", 1, true))
                    helper.fireTimers(taPackage.navStepDelayMs)
                    assert.are.equal(0, sent("nw"))                -- not a third time
                    assert.are.equal(1, sent("s"))                 -- heads home instead
                end)

                -- The cap is per errand sweep, not per walk: a route that
                -- clears two rooms gets two chases for each of them.
                it("gives each errand sweep its own budget", function()
                    route({ steps = { "w", { killAll = true, untilFound = "platinum key" }, "d",
                                      { killAll = true, untilFound = "platinum key" }, "e" } })
                    helper.simulateAlias("navigate-to sewers/town-sewers-18")
                    answerProbe(274)
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- first sweep
                    helper.simulateLine("The ogre mage has just gone to the northeast.")
                    helper.simulateLine("There is nobody here.")
                    assert.are.equal(1, taPackage.navigate.chases)
                    helper.fireTimers(taPackage.navStepDelayMs)    -- the chase leg
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- the chased room's sweep
                    helper.simulateLine("There is nobody here.")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- home
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- "d"
                    brief("town sewers")
                    helper.fireTimers(taPackage.navStepDelayMs)    -- second sweep
                    assert.are.equal(0, taPackage.navigate.chases)
                end)

            end)

        end)

        it("announces a key found while searching a corpse", function()
            sweeping()
            helper.simulateLine("While searching the area, you notice a ruby key, which you add to your possessions.")
            assert.is_truthy(lastEchoes():find("Got the ruby key.", 1, true))
        end)

        -- The line hard-wraps at the terminal width, so "possessions." lands on
        -- the following line and the first form never matches.
        it("announces a key when the line wrapped", function()
            sweeping()
            helper.simulateLine("While searching the area, you notice a ruby key, which you add to your")
            assert.is_truthy(lastEchoes():find("Got the ruby key.", 1, true))
        end)

        it("stays quiet about ordinary loot", function()
            sweeping()
            helper.simulateLine("While searching the area, you notice a waterskin, which you add to your possessions.")
            assert.is_falsy(lastEchoes():find("Got the waterskin", 1, true))
        end)

        -- Breaking off mid-sweep would stop us attacking without stopping the
        -- room attacking us — both sewers destinations held four live monsters
        -- on arrival. So the room gets finished first.
        it("keeps fighting when the pack is too full to take what was found", function()
            sweeping()
            assert.is_true(taPackage.killAllActive)
            helper.simulateLine("While searching the area, you notice a ruby key, but you can't carry it.")
            assert.is_true(taPackage.killAllActive)   -- still sweeping
            assert.is_truthy(lastEchoes():find("Clearing the room first", 1, true))
        end)

        -- Whatever the errand went for may be the thing on that floor, so
        -- walking on would carry the character away from it.
        it("stops the run once the room is clear, naming what was left behind", function()
            sweeping()
            helper.simulateLine("While searching the area, you notice a ruby key, but you can't carry it.")
            helper.simulateLine("There is nobody here.")   -- room clear, sweep ends
            local out = lastEchoes()
            assert.is_truthy(out:find("the ruby key is still on the floor here", 1, true))
            assert.is_truthy(out:find("Stopped sewers/town-sewers-18.", 1, true))
            assert.is_falsy(taPackage.killAllActive)
            assert.is_nil(taPackage.navigate)
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(0, sent("se"))    -- the return leg is not walked
        end)

        -- A kill-all or kill run by hand is nobody's business but the user's; a
        -- full pack there may be irrelevant to whatever they're doing.
        it("leaves a hand-run sweep alone", function()
            taPackage.killAllActive = true            -- as `kill-all` would
            helper.simulateLine("While searching the area, you notice a ruby key, but you can't carry it.")
            assert.is_true(taPackage.killAllActive)
            assert.is_falsy(lastEchoes():find("Clearing the room first", 1, true))
        end)

        it("ignores a full pack when nothing is running at all", function()
            helper.simulateLine("While searching the area, you notice a ruby key, but you can't carry it.")
            assert.is_falsy(lastEchoes():find("Clearing the room first", 1, true))
        end)

    end)

    -- The most common refused move in the logs by a wide margin (11,655 of
    -- them). It prints no room line, so without handling the walk stops dead
    -- and says nothing at all.
    describe("interrupted by combat", function()

        local function blocked()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            helper.simulateLine("You cannot leave in the heat of battle!")
        end

        -- Stopping would throw away a forty-step walk to any wandering rat, and
        -- leave the character in the fight regardless.
        it("keeps the walk alive and retries the blocked step", function()
            blocked()
            assert.is_not_nil(taPackage.navigate)
            assert.are.equal(1, sent("sw"))
            helper.fireTimers(taPackage.navCombatRetryMs)
            assert.are.equal(2, sent("sw"))
            assert.is_truthy(lastEchoes():find("has me in combat", 1, true))
        end)

        it("retries the same step rather than advancing", function()
            blocked()
            helper.fireTimers(taPackage.navCombatRetryMs)
            assert.are.equal(0, sent("d"))          -- step 2 stays queued
            assert.are.equal(1, taPackage.navigate.index)
        end)

        it("walks on normally once the step gets through", function()
            blocked()
            helper.fireTimers(taPackage.navCombatRetryMs)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("d"))
        end)

        -- Once, then every fifth: a walk pinned down by something it can't get
        -- away from must be visible, without burying the screen.
        it("reports the first block and then every fifth", function()
            blocked()
            for _ = 2, 5 do
                helper.fireTimers(taPackage.navCombatRetryMs)
                helper.simulateLine("You cannot leave in the heat of battle!")
            end
            local out = lastEchoes()
            local n = select(2, out:gsub("has me in combat", ""))
            assert.are.equal(2, n)                  -- attempts 1 and 5
            assert.is_truthy(out:find("attempt 5", 1, true))
        end)

    end)

    describe("stopping", function()

        local function startWalking()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("stop-navigating halts the walk", function()
            startWalking()
            helper.simulateAlias("stop-navigating")
            assert.is_nil(taPackage.navigate)
            assert.is_truthy(lastEchoes():find("Stopped walking.", 1, true))
            -- A step timer already in flight must not resume it.
            helper.simulateLine("You're on a path.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(0, sent("d"))
        end)

        it("stop-navigating says so when nothing is running", function()
            helper.simulateAlias("stop-navigating")
            assert.is_truthy(lastEchoes():find("Not currently walking anywhere.", 1, true))
        end)

        it("stop-all-scripts halts the walk too", function()
            startWalking()
            helper.simulateAlias("stop-all-scripts")
            assert.is_nil(taPackage.navigate)
            assert.is_truthy(lastEchoes():find("[all] Stopped navigate.", 1, true))
        end)

        it("refuses to start a second walk while one is running", function()
            startWalking()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.is_truthy(lastEchoes():find("Already walking to", 1, true))
        end)

        -- A sweep is part of the walk, so "stopped" has to mean the character
        -- stops swinging too — not stands there fighting a room on its own.
        it("stop-navigating halts a sweep the route started", function()
            route({ steps = { "sw", { killAll = true } } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.is_true(taPackage.killAllActive)
            helper.simulateAlias("stop-navigating")
            assert.is_falsy(taPackage.killAllActive)
            assert.is_nil(taPackage.navSweep)
        end)

    end)

    -- The hydra route drops through a trap door into a pit that can't be
    -- climbed "unaided", so a rope-less character walks in and stays there.
    -- Better to find that out standing in the sewers.
    describe("an errand that needs an item", function()

        local function askToWalk()
            route({ requires = "coil of rope" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("asks what it is carrying before setting off", function()
            askToWalk()
            assert.are.equal(1, sent("i"))
            assert.are.equal(0, sent("sw"))   -- nothing moves until the answer
        end)

        it("walks once the item is there", function()
            askToWalk()
            helper.simulateLine("You are carrying 559 gold crowns, a coil of rope, and a waterskin(3).")
            assert.are.equal(1, sent("sw"))
        end)

        -- The listing wraps at the terminal width, so an item can straddle the
        -- break. Read line by line and "coil of rope" is never there to find.
        it("finds an item split across a wrapped line", function()
            askToWalk()
            helper.simulateLine("You are carrying 559 gold crowns, a glowstone, a coil of")
            assert.are.equal(0, sent("sw"))   -- sentence unfinished; still reading
            helper.simulateLine("rope, a ration of food, and a waterskin(3).")
            assert.are.equal(1, sent("sw"))
        end)

        it("refuses and stays put when the item is missing", function()
            askToWalk()
            helper.simulateLine("You are carrying 559 gold crowns, and a waterskin(3).")
            assert.are.equal(0, sent("sw"))
            assert.is_nil(taPackage.navigate)
            local out = lastEchoes()
            assert.is_truthy(out:find("needs a coil of rope and I'm not carrying one", 1, true))
            -- Say what we did see, so a near miss is obvious rather than baffling.
            assert.is_truthy(out:find("Carrying: 559 gold crowns, and a waterskin(3).", 1, true))
        end)

        it("says so when the game never answers", function()
            askToWalk()
            helper.fireTimers(5000)
            assert.are.equal(0, sent("sw"))
            assert.is_truthy(lastEchoes():find("never listed what I'm carrying", 1, true))
        end)

        -- A concatenated route needs everything its legs need, and the two the
        -- third-town chain needs strand you in different places: the rope in the
        -- hydra's pit, the potion out in the desert with the poison working.
        -- Setting off holding one of the two is how you learn about the other
        -- from the bottom of the pit.
        describe("more than one item", function()

            local BOTH = { "coil of rope", "verbena potion" }

            local function askToWalkForBoth()
                route({ requires = BOTH })
                helper.simulateAlias("navigate-to sewers/town-sewers-18")
                answerProbe(274)
            end

            it("walks when both are there", function()
                askToWalkForBoth()
                helper.simulateLine("You are carrying a coil of rope, a verbena potion, and 12 gold crowns.")
                assert.are.equal(1, sent("sw"))
            end)

            -- Naming what is missing rather than what is needed: told "this
            -- route needs a verbena potion" while holding one, you go looking
            -- for the wrong problem.
            it("names only the one that is missing", function()
                askToWalkForBoth()
                helper.simulateLine("You are carrying a coil of rope, and 12 gold crowns.")
                assert.are.equal(0, sent("sw"))
                local out = lastEchoes()
                assert.is_truthy(out:find("needs a verbena potion and I'm not carrying one", 1, true))
                assert.is_falsy(out:find("coil of rope and", 1, true))
            end)

            it("names both when both are missing", function()
                askToWalkForBoth()
                helper.simulateLine("You are carrying 12 gold crowns.")
                assert.is_truthy(lastEchoes():find(
                    "needs a coil of rope and a verbena potion and I'm not carrying them", 1, true))
            end)

            it("names both when told 'anyway'", function()
                route({ requires = BOTH })
                helper.simulateAlias("navigate-to sewers/town-sewers-18 anyway")
                answerProbe(274)
                assert.are.equal(0, sent("i"))
                assert.is_truthy(lastEchoes():find(
                    "without checking for a coil of rope and a verbena potion", 1, true))
            end)

            it("still takes a bare string, as every route but one does", function()
                askToWalk()
                helper.simulateLine("You are carrying a coil of rope.")
                assert.are.equal(1, sent("sw"))
            end)

        end)

        it("ignores lines before the listing", function()
            askToWalk()
            helper.simulateLine("Someone shouts something rude.")
            helper.simulateLine("You are carrying a coil of rope.")
            assert.are.equal(1, sent("sw"))
        end)

        -- The check is a courtesy, not a lock: the potion may be on the floor a
        -- room away, or today's hazard survivable without it.
        it("sets off regardless when told 'anyway'", function()
            route({ requires = "verbena potion" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 anyway")
            answerProbe(274)
            assert.are.equal(0, sent("i"))       -- never asked
            assert.are.equal(1, sent("sw"))
            assert.is_truthy(lastEchoes():find("without checking for a verbena potion", 1, true))
        end)

        it("takes 'anyway' alongside the other flags, in any order", function()
            route({ requires = "verbena potion" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 anyway quiet")
            answerProbe(274)
            assert.are.equal(1, sent("sw"))
            assert.is_falsy(lastEchoes():find("[nav|t]", 1, true))   -- quiet still applied
        end)

        it("still overrides on a fingerprint start", function()
            route({ from = { room = "north plaza", exits = "e,n,s,sw,w" },
                    requires = "verbena potion" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18 anyway")
            answerProbe(274)
            assert.are.equal(0, sent("i"))
            assert.are.equal(1, sent("sw"))
        end)

        it("leaves a route with no requirement alone", function()
            route()
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            assert.are.equal(0, sent("i"))
            assert.are.equal(1, sent("sw"))
        end)

    end)

    -- Poison on the way to the stoneworks comes from the sewer fauna, not from
    -- a trap at a known step, so the cure hangs off the announcement.
    describe("getting poisoned on the way", function()

        local function walking(overrides)
            route(overrides or { onPoison = "drink verbena" })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("drinks the cure when the game says we're poisoned", function()
            walking()
            helper.simulateLine("You're poisoned!")
            assert.are.equal(1, sent("drink verbena"))
            assert.is_truthy(lastEchoes():find("Poisoned — drink verbena.", 1, true))
        end)

        it("keeps walking afterwards", function()
            walking()
            brief("path")
            helper.simulateLine("You're poisoned!")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("d"))       -- step 2 still goes out
        end)

        -- The cure's reply is not a room brief, so it must not be mistaken for
        -- an arrival — but confirm it out loud, since the drink can fail.
        it("confirms the drink without advancing the walk", function()
            walking()
            brief("path")
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You feel somehow different after drinking the potion.")
            assert.is_truthy(lastEchoes():find("Drank it.", 1, true))
            assert.are.equal(0, sent("d"))       -- no step until the pace elapses
        end)

        it("says so when there is nothing left to drink", function()
            walking()
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("Sorry, but you don't seem to have one.")
            assert.is_truthy(lastEchoes():find("Nothing left to drink", 1, true))
            assert.is_not_nil(taPackage.navigate)   -- and walks on regardless
        end)

        -- The line repeats every tick for as long as the poison lasts, two or
        -- three lines apart. Answering each one would empty the pack.
        it("drinks once however often the poison line repeats", function()
            walking()
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You're poisoned!")
            assert.are.equal(1, sent("drink verbena"))
        end)

        it("does not drink again on the tail of ticks after a cure", function()
            walking()
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You feel somehow different after drinking the potion.")
            helper.simulateLine("You're poisoned!")   -- a tick still in flight
            assert.are.equal(1, sent("drink verbena"))
        end)

        it("treats a fresh poisoning once the cooldown has passed", function()
            walking()
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You feel somehow different after drinking the potion.")
            helper.advanceMs(15000)
            helper.simulateLine("You're poisoned!")
            assert.are.equal(2, sent("drink verbena"))
        end)

        it("counts the poisonings in the closing trace", function()
            walking()
            helper.simulateLine("You're poisoned!")
            helper.simulateLine("You feel somehow different after drinking the potion.")
            helper.advanceMs(15000)
            helper.simulateLine("You're poisoned!")
            helper.simulateAlias("stop-navigating")
            assert.is_truthy(lastEchoes():find("poisoned 2x", 1, true))
        end)

        it("leaves a route with no cure declared alone", function()
            walking({})
            helper.simulateLine("You're poisoned!")
            assert.are.equal(0, sent("drink verbena"))
        end)

        -- "you don't seem to have one" answers plenty of other commands.
        it("ignores a refusal it didn't cause", function()
            walking()
            helper.simulateLine("Sorry, but you don't seem to have one.")
            assert.is_falsy(lastEchoes():find("Nothing left to drink", 1, true))
        end)

    end)

    -- A trap door prints TWO arrival briefs for one move: the room walked into,
    -- then the pit fallen into. Counting both runs the step list a move ahead
    -- of the character.
    describe("falling through a trap door", function()

        it("does not count the pit as a step of its own", function()
            route({ steps = { "sw", "d", "se", "n" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")                                        -- step 1 landed
            helper.simulateLine("You just fell through a trap door in the floor!")
            brief("pit")                                         -- not a step
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("d"))
            assert.are.equal(0, sent("se"))
            -- And the climb back out is an ordinary step: its brief advances.
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

    end)

    -- Getting to third-town is not all walking: there are levers to pull and
    -- stones to push. Nothing in the game reliably answers such a command, so
    -- the pacing pause is what says it has had its chance.
    -- A route can be built by naming other routes instead of listing steps.
    -- Naming rather than copying is the point: the legs stay runnable on their
    -- own, and the directions exist in one place, so there is no second copy to
    -- drift.
    describe("a route built from other routes", function()

        local function legs(spec)
            taPackage.navRoutes["sewers/leg-one"] =
                { from = "second-town/north-plaza", steps = { "sw", "d" } }
            taPackage.navRoutes["sewers/leg-two"] =
                { from = { room = "town sewers", exits = "u,se" }, steps = { "se", "n", "e" } }
            taPackage.navRoutes["sewers/joined"] =
                { from = "second-town/north-plaza", to = "sewers/town-sewers-18",
                  legs = spec or { "sewers/leg-one", "sewers/leg-two" } }
            return taPackage.navRoutes["sewers/joined"]
        end

        local function flat(spec)
            return taPackage.navRouteSteps(legs(spec))
        end

        it("walks the legs in order", function()
            local steps = flat()
            assert.are.equal("sw", steps[1])
            assert.are.equal("d", steps[2])
            assert.are.equal("se", steps[4])
            assert.are.equal("n", steps[5])
            assert.are.equal("e", steps[6])
        end)

        -- One seam per join, and none before the first leg: that leg's start is
        -- the joined route's own, already checked before the walk sets off.
        it("puts a seam before every leg but the first", function()
            local steps = flat()
            assert.are.equal(6, #steps)
            assert.are.same({ seam = "sewers/leg-two" }, steps[3])
            for i, step in ipairs(steps) do
                if i ~= 3 then assert.are_not.equal("table", type(step)) end
            end
        end)

        it("drops steps off the end of a leg that asks", function()
            local steps = flat({ "sewers/leg-one", { route = "sewers/leg-two", drop = 2 } })
            assert.are.equal(4, #steps)
            assert.are.equal("se", steps[4])   -- `n` and `e` dropped
        end)

        -- Flattened fresh each time. The walk owns its list because a locked
        -- gate splices into it, and a leg's own table must not be touched.
        it("leaves the legs alone", function()
            local route = legs()
            local first = taPackage.navRouteSteps(route)
            table.insert(first, "n")
            assert.are.equal(2, #taPackage.navRoutes["sewers/leg-one"].steps)
            assert.are.equal(6, #taPackage.navRouteSteps(route))
        end)

        it("refuses a leg that names no known route", function()
            legs({ "sewers/leg-one", "sewers/nowhere" })
            helper.simulateAlias("navigate-to sewers/joined")
            assert.are.equal(0, sent(""))
            assert.is_truthy(lastEchoes():find(
                "leg 2 is 'sewers/nowhere', and there's no such route", 1, true))
        end)

        it("refuses a leg that is itself joined from legs", function()
            legs()
            taPackage.navRoutes["sewers/leg-two"] = { from = "second-town/north-plaza",
                                                      legs = { "sewers/leg-one" } }
            helper.simulateAlias("navigate-to sewers/joined")
            assert.is_truthy(lastEchoes():find("and I don't join those", 1, true))
        end)

        it("walks the whole thing, seam and all", function()
            legs()
            helper.simulateAlias("navigate-to sewers/joined")
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("6 steps", 1, true))
            brief("path")                                  -- sw
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")                           -- d
            helper.fireTimers(taPackage.navStepDelayMs)    -- the seam
            answerProbe(340)                               -- town sewers, exits u,se
            assert.is_truthy(lastEchoes():find("At the sewers/leg-two seam", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

    end)

    -- A seam moves nowhere. It is the join between two legs of a joined route,
    -- asking the room we have arrived in whether it is where the next leg
    -- begins -- the check that leg makes for itself when it is run by hand, and
    -- for the stoneworks legs the only thing standing between a miscounted
    -- repeat and a character walking into walls a hundred steps later.
    describe("checking the room at a seam", function()

        -- Both `from` shapes a leg can have: room 274 is a real mapped room, so
        -- NEXT_MAPPED exercises the reference branch and NEXT_FP the literal one.
        local NEXT_FP = { from = { room = "north plaza", exits = "e,n,s,sw,w" },
                          to = "sewers/town-sewers-18", steps = { "n" } }
        local NEXT_MAPPED = { from = "second-town/north-plaza",
                              to = "sewers/town-sewers-18", steps = { "n" } }

        local function walkToSeam(leg)
            taPackage.navRoutes["sewers/next-leg"] = leg or NEXT_FP
            route({ steps = { "sw", { seam = "sewers/next-leg" }, "se" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")                                  -- step 1 lands
            helper.fireTimers(taPackage.navStepDelayMs)    -- the seam goes out
        end

        it("asks the room where it is without moving", function()
            walkToSeam()
            -- Two: the start check asked once before the walk set off, and this
            -- is the same question asked again at the join.
            assert.are.equal(2, sent("ex"))
            assert.are.equal(0, sent("se"))
        end)

        -- The bare return the seam sends brings a room brief back with it. Read
        -- as an arrival it would advance the walk a step past the character.
        it("does not let its own reply advance the walk", function()
            walkToSeam()
            brief("north plaza")
            assert.are.equal(0, sent("se"))
        end)

        it("walks on when the room is where the next leg starts", function()
            walkToSeam()
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("At the sewers/next-leg seam", 1, true))
            assert.is_truthy(lastEchoes():find("as expected, carrying on", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

        it("stops when the room name is wrong", function()
            walkToSeam()
            brief("stonework corridor")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            local out = lastEchoes()
            assert.is_truthy(out:find("At the sewers/next-leg seam I expected", 1, true))
            assert.is_truthy(out:find("a room called 'north plaza'", 1, true))
            assert.is_truthy(out:find("but I'm in 'stonework corridor'", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        it("stops when the exits are wrong", function()
            walkToSeam()
            brief("north plaza")
            helper.simulateLine("Exits: ne,s.")
            assert.is_truthy(lastEchoes():find("but I'm in 'north plaza' with exits ne,s", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- The leg is the resume point: it is exactly what you would run by hand
        -- from wherever the walk actually got to.
        it("names the leg to resume from", function()
            walkToSeam()
            brief("stonework corridor")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            assert.is_truthy(lastEchoes():find(
                "Get to where sewers/next-leg starts and run it on its own", 1, true))
        end)

        -- The other resume point: the seam is step 2 of the joined walk, so
        -- from-step 1 redoes the last move and from-step 2 takes it as landed.
        it("names both from-step numbers for the joined walk", function()
            walkToSeam()
            brief("stonework corridor")
            helper.simulateLine("Exits: e,n,s,sw,w.")
            local out = lastEchoes()
            assert.is_truthy(out:find(
                "run navigate-to sewers/town-sewers-18 from-step 1 "
                .. "or run navigate-to sewers/town-sewers-18 from-step 2", 1, true))
        end)

        -- The hydra-to-stoneworks seam is this shape: the leg names a mapped
        -- room rather than a fingerprint, so the check goes through the map.
        it("checks a leg whose start is a map reference", function()
            walkToSeam(NEXT_MAPPED)
            answerProbe(274)
            assert.is_truthy(lastEchoes():find("as expected, carrying on", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

        it("stops rather than hanging when the room never answers", function()
            walkToSeam()
            helper.fireTimers(5000)
            assert.are.equal(0, sent("se"))
            assert.is_truthy(lastEchoes():find("never told me what room I'm in at the", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        it("leaves no probe armed when stopped mid-seam", function()
            walkToSeam()
            helper.simulateAlias("stop-navigating")
            assert.is_nil(taPackage.slugProbe)
            assert.is_nil(taPackage.navigate)
        end)

        it("refuses a route whose seam names no known route", function()
            route({ steps = { "sw", { seam = "sewers/nowhere" } } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(0, sent(""))
            assert.is_truthy(lastEchoes():find(
                "checks we've reached 'sewers/nowhere', and there's no such route", 1, true))
        end)

    end)

    -- A gate is a door the route expects to find shut some of the time. The move
    -- is the question -- open, opened by a key we hold, or refused -- and only
    -- the refusal costs anything: the errand that fetches the key.
    describe("doors on the way", function()

        -- A round trip, as every key errand is. Deliberately shares no direction
        -- with the gate or the route around it, so counting what was sent says
        -- which of the three moved.
        local ERRAND = { from = "sewers/town-sewers-18", to = "sewers/town-sewers-18",
                         steps = { "n", "s" } }

        local function gated(gate, steps)
            taPackage.navRoutes["sewers/errand"] = ERRAND
            route({ steps = steps or { "sw", gate, "se" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")                                  -- step 1 lands
            helper.fireTimers(taPackage.navStepDelayMs)     -- the gate goes out
        end

        local function GATE(overrides)
            local g = { door = "e", key = "ruby", detour = "sewers/errand" }
            for k, v in pairs(overrides or {}) do g[k] = v end
            return g
        end

        it("walks the door direction like any other step", function()
            gated(GATE())
            assert.are.equal(1, sent("e"))
        end)

        it("walks on when the door is simply open", function()
            gated(GATE())
            brief("town sewers")
            assert.is_truthy(lastEchoes():find("The e door was already open", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

        -- The branch that makes the whole thing worth having: a key we fetched
        -- yesterday opens the door today, and the errand is skipped.
        it("names the key when one we hold opens the door", function()
            gated(GATE())
            helper.simulateLine("Your ruby key unlocks the stone door and allows you to pass through.")
            brief("town sewers")
            assert.is_truthy(lastEchoes():find("My ruby key opened the e door", 1, true))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
            assert.are.equal(0, sent("n"))                 -- the errand never ran
        end)

        it("runs the errand when the door is locked, then tries the door again", function()
            gated(GATE())
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("The e door is locked and I don't have the ruby key", 1, true))
            assert.is_truthy(out:find("by way of sewers/errand (2 steps)", 1, true))
            -- The errand's two steps, then the same door for a second time.
            assert.are.equal(1, sent("e"))
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("n"))
            brief("town sewers")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("s"))
            brief("town sewers-18")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("e"))                 -- the gate, retried
            assert.are.equal(0, sent("se"))                -- and the route not run on
        end)

        it("finishes the route once the retried door opens", function()
            gated(GATE())
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            helper.fireTimers(taPackage.navStepDelayMs)    -- errand step 1
            brief("town sewers")
            helper.fireTimers(taPackage.navStepDelayMs)    -- errand step 2
            brief("town sewers-18")
            helper.fireTimers(taPackage.navStepDelayMs)    -- the gate again
            helper.simulateLine("Your ruby key unlocks the stone door and allows you to pass through.")
            brief("town sewers")
            helper.fireTimers(taPackage.navStepDelayMs)    -- the last step
            assert.are.equal(1, sent("se"))
            brief("town sewers")
            assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- The errand is meant to end holding the key. If the door is still shut
        -- after it, walking it again would only fetch a key we now have.
        it("stops rather than running the errand twice", function()
            gated(GATE())
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers")
            helper.fireTimers(taPackage.navStepDelayMs)
            brief("town sewers-18")
            helper.fireTimers(taPackage.navStepDelayMs)    -- the gate again
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            assert.is_truthy(lastEchoes():find(
                "Walked sewers/errand and the e door is still locked", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- Every locked door was a hard stop before gates existed, and one with
        -- nowhere to go for the key still is.
        it("still stops at a locked door with no errand to run", function()
            gated({ door = "e", key = "ruby" })
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("A locked stone door blocks step 2", 1, true))
            assert.is_truthy(out:find("(the ruby key)", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- A final `door` probe is sent after the last step, so the walk still
        -- remembers that step's kind. If the last step were a gate, a refusal at
        -- the probe would otherwise fetch a key for a door one room back and
        -- then walk the probe again.
        it("does not treat a final door probe as the gate before it", function()
            taPackage.navRoutes["sewers/errand"] = ERRAND
            route({ steps = { "sw", GATE() }, door = { dir = "s", key = "ruby" } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
            brief("path")                                  -- step 1 lands
            helper.fireTimers(taPackage.navStepDelayMs)    -- the gate goes out
            brief("town sewers")                           -- through it, and arrived
            helper.fireTimers(taPackage.navStepDelayMs)    -- the door probe goes out
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            local out = lastEchoes()
            assert.is_truthy(out:find("A locked stone door blocks the way on", 1, true))
            assert.are.equal(0, sent("n"))                 -- the errand never ran
            assert.is_nil(taPackage.navigate)
        end)

        -- A gate is a move, so it can be tripped on, and re-sending it is safe.
        -- Read from the step's `door` rather than the step itself, which is a
        -- table -- the walk would otherwise sit waiting on a step it never sent.
        it("re-sends the door after a trip", function()
            gated(GATE())
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(taPackage.navTripRetryMs)
            helper.simulateLine("There is nothing on the floor.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(2, sent("e"))
        end)

        -- Splicing writes into the walk's step list. Were that the route's own
        -- table, the errand would be welded into the route for the rest of the
        -- session and walked again whether the door was locked or not.
        it("does not weld the errand into the route", function()
            gated(GATE())
            local before = #taPackage.navRoutes["sewers/town-sewers-18"].steps
            helper.simulateLine("The locked stone door prevents your exit in that direction.")
            assert.are.equal(before, #taPackage.navRoutes["sewers/town-sewers-18"].steps)
            assert.are.equal(before + 2, #taPackage.navigate.steps)
        end)

        it("says the step count is a floor when a route has a gate", function()
            gated(GATE())
            assert.is_truthy(lastEchoes():find(
                "3 steps, plus a key errand for any door that's locked.", 1, true))
        end)

        -- The errand is named by string, so a typo in it is invisible until the
        -- day a door happens to be locked. Check it with the rest of the route,
        -- standing still, before anything is sent.
        it("refuses a route whose errand names no known route", function()
            taPackage.navRoutes["sewers/errand"] = ERRAND
            route({ steps = { "sw", GATE({ detour = "sewers/nowhere" }) } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.are.equal(0, sent(""))
            assert.is_truthy(lastEchoes():find(
                "Step 2 of the route to sewers/town-sewers-18 sends us to 'sewers/nowhere'", 1, true))
        end)

        it("refuses a route whose errand is itself malformed", function()
            taPackage.navRoutes["sewers/errand"] = { from = ERRAND.from, to = ERRAND.to,
                                                    steps = { "n", 7 } }
            route({ steps = { "sw", GATE() } })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            assert.is_truthy(lastEchoes():find("whose step 2 isn't a direction", 1, true))
        end)

    end)

    describe("commands along the way", function()

        local function walkWithCommand(steps)
            route({ steps = steps })
            helper.simulateAlias("navigate-to sewers/town-sewers-18")
            answerProbe(274)
        end

        it("sends the command and walks on after the usual pause", function()
            walkWithCommand({ "sw", { cmd = "pull lever" }, "se" })
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("pull lever"))
            assert.are.equal(0, sent("se"))          -- paced, not immediate
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("se"))
        end)

        -- A lever pull may well reprint the room. Treating that as an arrival
        -- would send the next direction while the character is still standing
        -- where it was, putting the walk a step ahead of the character.
        it("does not let a reply to the command advance the walk", function()
            walkWithCommand({ "sw", { cmd = "pull lever" }, "se", "n" })
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)   -- pull lever
            brief("path")                                 -- the lever's reply
            helper.fireTimers(taPackage.navStepDelayMs)
            -- One step came out of that pause, not two: had the reply been
            -- counted, "n" would already be on its way while the character was
            -- still standing where the lever is.
            assert.are.equal(1, sent("se"))
            assert.are.equal(0, sent("n"))
        end)

        it("arrives when the command is the last step", function()
            walkWithCommand({ "sw", { cmd = "push stone" } })
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("push stone"))
            assert.is_truthy(lastEchoes():find("Arrived at sewers/town-sewers-18.", 1, true))
            assert.is_nil(taPackage.navigate)
        end)

        -- Repeating a move is harmless; repeating a lever pull works it twice.
        it("does not re-send a command when a later move trips", function()
            walkWithCommand({ "sw", { cmd = "pull lever" }, "se" })
            brief("path")
            helper.fireTimers(taPackage.navStepDelayMs)   -- pull lever
            helper.fireTimers(taPackage.navStepDelayMs)   -- se
            helper.simulateLine("In your haste, you trip and fall!")
            helper.fireTimers(taPackage.navTripRetryMs)
            helper.simulateLine("There is nothing on the floor.")
            helper.fireTimers(taPackage.navStepDelayMs)
            assert.are.equal(1, sent("pull lever"))
            assert.are.equal(2, sent("se"))
        end)

    end)

end)

-- The BBS login and menu sequence that sits between connecting and being in
-- the game. Real prompt text taken from logs/session-kerhak-2026-08-07T15-10-53.log.
describe("Auto-login", function()

    -- main.lua reads the environment as it loads, so a test has to set it
    -- before dofile rather than after.
    local function loadWith(env)
        helper.resetAll()
        for key, value in pairs(env) do helper.env[key] = value end
        dofile("main.lua")
    end

    local function sends()
        local copy = {}
        for i, text in ipairs(helper.sendCalls) do copy[i] = text end
        return copy
    end

    local function clearSends()
        for k in pairs(helper.sendCalls) do helper.sendCalls[k] = nil end
    end

    it("answers the username prompt with TA_CHARACTER", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        assert.are.same({ "kerhak" }, sends())
    end)

    it("answers the password prompt with TA_PASSWORD", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_PASSWORD = "hunter2" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("Password: ")
        assert.are.same({ "hunter2" }, sends())
    end)

    it("answers the nonstop prompt with n", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        assert.are.same({ "n" }, sends())
    end)

    -- "N" means nonstop: having answered once, the BBS prints the second
    -- prompt without waiting for it. A second "n" fell through to the main
    -- menu, which rejected it and redisplayed itself.
    it("answers only the first nonstop prompt", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        assert.are.same({ "n" }, sends())
    end)

    -- The second 5 outlived the menu: the BBS still held it when the game
    -- started, and Tele-Arena delivered it as chat ("From Tojolias: 5").
    it("picks 5 only once even if the menu is redisplayed", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        helper.simulateLine("Main System Menu (TOP)")
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        assert.are.same({ "5" }, sends())
    end)

    it("picks 5 at the main system menu", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        assert.are.same({ "5" }, sends())
    end)

    -- The real transcript, line for line, from
    -- logs/session-tojolias-2026-08-11T22-49-54.log.
    it("walks the whole sequence in order", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_PASSWORD = "hunter2" })
        helper.simulateLine("Username: ")
        helper.simulateLine("Password: ")
        helper.simulateLine("Greetings, Kerhak, glad to see you back again.")
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        helper.simulateLine(" 01  Malak                  OLD    F  482   USER      ---  Othello")
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        helper.simulateLine("Main System Menu (TOP)")
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        helper.simulateLine("to exit): ")
        -- st/i are the existing on-entry character-sheet pull, not login.
        helper.simulateLine("Entering Tele-Arena...")
        assert.are.same({ "kerhak", "hunter2", "n", "5", "st", "i" }, sends())
    end)

    -- The whole point of the pending gate: "n" is north once we are in the
    -- game, so a menu answer escaping into the arena walks the character.
    it("stops answering once we are in the arena", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_PASSWORD = "hunter2" })
        helper.simulateLine("Username: ")
        helper.simulateLine("Entering Tele-Arena...")
        clearSends()

        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        helper.simulateLine("Password: ")
        assert.are.same({}, sends())
    end)

    it("re-arms at a fresh username prompt after a reconnect", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_PASSWORD = "hunter2" })
        helper.simulateLine("Username: ")
        helper.simulateLine("Entering Tele-Arena...")
        clearSends()

        helper.simulateLine("Username: ")
        helper.simulateLine("Password: ")
        assert.are.same({ "kerhak", "hunter2" }, sends())
    end)

    -- Running baud by hand, with no environment set, must behave exactly as it
    -- did before auto-login existed.
    it("sends nothing at any prompt when TA_CHARACTER is unset", function()
        loadWith({})
        helper.simulateLine("Username: ")
        helper.simulateLine("Password: ")
        helper.simulateLine("(N)onstop, (Q)uit, or (C)ontinue?")
        helper.simulateLine("Make your selection (1,2,3,4,5,6,7,8,9,0,D,G,T,F,I,R,E,M,A,L,B,? for help, or X")
        assert.are.same({}, sends())
    end)

    it("says so rather than guessing when TA_PASSWORD is unset", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        clearSends()
        helper.simulateLine("Password: ")
        assert.are.same({}, sends())
        assert.is_true(tableContains(helper.echoCalls,
            "[login] TA_PASSWORD is not set - type the password yourself"))
    end)

    -- TA_INIT_CMD: what to run once we are actually in the game. It goes
    -- through runCommand rather than send because it is usually an alias, and
    -- it waits for the entry st/i replies because the aliases worth running
    -- need the character sheet.
    local function enterTheGame()
        helper.simulateLine("Username: ")
        helper.simulateLine("Entering Tele-Arena...")
    end

    -- The tail of the entry `i`, which is what says the sheet has landed.
    local function inventoryReply()
        helper.simulateLine("You are carrying 100 gold crowns, a glowstone.")
    end

    it("runs TA_INIT_CMD once the entry character sheet has landed", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "rg 2" })
        enterTheGame()
        inventoryReply()
        assert.are.same({ "rg 2" }, helper.runCommandCalls)
    end)

    -- Firing it in the "Entering Tele-Arena..." handler would beat the st reply
    -- back, and "rg" refuses to start without a known class.
    it("does not run TA_INIT_CMD before the sheet has landed", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "rg 2" })
        enterTheGame()
        assert.are.same({}, helper.runCommandCalls)
    end)

    it("runs TA_INIT_CMD only once, not on every later inventory check", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "rg 2" })
        enterTheGame()
        inventoryReply()
        inventoryReply()
        assert.are.same({ "rg 2" }, helper.runCommandCalls)
    end)

    it("runs nothing when TA_INIT_CMD is unset", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        enterTheGame()
        inventoryReply()
        assert.are.same({}, helper.runCommandCalls)
    end)

    -- An init command belongs to the login that armed it. A connection dropped
    -- before the sheet came back must not run it against the next login.
    it("re-arms TA_INIT_CMD on a reconnect rather than carrying it over", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "rg 2" })
        enterTheGame()

        helper.simulateLine("Username: ")
        inventoryReply()
        assert.are.same({}, helper.runCommandCalls)

        helper.simulateLine("Entering Tele-Arena...")
        inventoryReply()
        assert.are.same({ "rg 2" }, helper.runCommandCalls)
    end)

    -- The point of runCommand: "rg 2" is an alias, and send() would put the
    -- literal text on the wire instead of starting an arena session.
    it("really executes the alias, arena session and all", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "rg 2" })
        enterTheGame()
        helper.simulateLine("Class:        Warrior")
        inventoryReply()

        assert.are.equal("2", taPackage.arenaProfile)
        assert.are.equal("ringing", taPackage.arenaState)
    end)

    -- Older baud (the VPS copy) has no runCommand. A plain game command still
    -- works that way; an alias does not, so it says so.
    it("falls back to send, loudly, when baud has no runCommand", function()
        loadWith({ TA_CHARACTER = "kerhak", TA_INIT_CMD = "look" })
        -- _G, not a bare assignment: main.lua is dofile'd into the real global
        -- table, so a plain `runCommand = nil` here would land in busted's
        -- insulated copy and the script would never see it. resetAll puts the
        -- mock back for the next test.
        _G.runCommand = nil
        enterTheGame()
        clearSends()
        inventoryReply()

        assert.are.same({ "look" }, sends())
        assert.is_true(tableContains(helper.echoCalls,
            "[login] this baud has no runCommand - sending as a raw command"))
    end)

    -- baud runs outbound triggers on script sends too, so the auto-sent
    -- username feeds the same name capture a typed one does.
    it("learns the character name from the username it sent", function()
        loadWith({ TA_CHARACTER = "kerhak" })
        helper.simulateLine("Username: ")
        helper.simulateOutbound("kerhak")
        assert.are.equal("Kerhak", taPackage.character.name)
    end)

end)
