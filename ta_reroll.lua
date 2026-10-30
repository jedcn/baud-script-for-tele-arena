-- ta_reroll.lua -- re-rolling a new character until its stats are good enough
--
-- `re-roll-for-good-stats` and the `re-roll-half-ogre-*` aliases pick a build
-- and send `status`; every character sheet that comes back is judged against it
-- (taPackage.reroll.checkStats, called from main.lua's Vitality trigger), and a
-- roll short of the build is answered with `reroll` until one passes.
--
-- Loaded by main.lua with dofile, at the spot the aliases used to sit. Like
-- ta_nav.lua, a separate chunk that cannot see main.lua's locals; the seam runs
-- through taPackage:
--
--   in    taPackage.character (the stats), taPackage.onRerollAccepted and
--         taPackage.createRerollArmed (ta_create.lua, when farm-for-gold started
--         the re-roll)
--   out   taPackage.reroll.builds (ta_create.lua asks the same "is this roll good
--         enough?"), taPackage.reroll.checkStats, and the state the stat-change
--         triggers read: taPackage.reRolling, taPackage.reRollSuppressStats
--
-- The state keeps its old taPackage.reRoll* names: it survives reloadScript(),
-- so renaming it would stop a re-roll that was running across a reload.

taPackage.reroll = {}


local function reRollResetStats()
    taPackage.reRollCount = 0
    taPackage.reRollBestDeficit = nil
    taPackage.reRollTimerPending = false
    taPackage.reRollSuppressStats = true
    taPackage.reRollGeneration = (taPackage.reRollGeneration or 0) + 1
end

local function scheduleReroll()
    if taPackage.reRollTimerPending then return end
    taPackage.reRollTimerPending = true
    local gen = taPackage.reRollGeneration
    createTimer(500, function()
        if taPackage.reRollGeneration ~= gen then return end
        taPackage.reRollTimerPending = false
        if taPackage.reRolling then send("reroll") end
    end, { repeating = false })
end

local function reRollStatSummary(s)
    return "Int=" .. s.intellect .. " Kno=" .. s.knowledge .. " Phy=" .. s.physique
        .. " Sta=" .. s.stamina .. " Agi=" .. s.agility .. " Cha=" .. s.charisma
end

-- Each re-roll build is a matcher: given the six rolled stats it returns
-- (accepted, summary), where accepted is true once the roll is good enough to
-- stop on. Aliases below pick which matcher the Vitality trigger uses.
local reRollBuilds = {}
-- Readable from other chunks: farm-for-gold (ta_create.lua) asks the same
-- question of a character it finds on login -- "is this roll good enough?" --
-- and has to get the same answer the re-roll stops on.
taPackage.reroll.builds = reRollBuilds

-- Elf Sorceror: exact floors on Int/Kno/Sta, combined Phy+Cha deficit <= 5, Agi ignored.
reRollBuilds.elfSorceror = function(s)
    local floorsOk = s.intellect >= 22 and s.knowledge >= 25 and s.stamina >= 15
    local deficit = math.max(0, 15 - s.physique) + math.max(0, 21 - s.charisma)
    if not taPackage.reRollBestDeficit or deficit < taPackage.reRollBestDeficit then
        taPackage.reRollBestDeficit = deficit
    end
    local summary = reRollStatSummary(s)
        .. " (deficit=" .. deficit .. " best=" .. taPackage.reRollBestDeficit .. ")"
    return floorsOk and deficit <= 5, summary
end

-- Half-Ogre Warrior: simple hard floors — Phy >= 29 AND Sta >= 29 AND Agi >= 15,
-- other stats ignored. (Agi maxes at 17 for this build.)
reRollBuilds.halfOgreWarrior = function(s)
    local accepted = s.physique >= 29 and s.stamina >= 29 and s.agility >= 15
    return accepted, reRollStatSummary(s)
end

-- Half-Ogre Warrior, fast mode: same build, one point looser on the two
-- physicals — Phy >= 28 AND Sta >= 28 AND Agi >= 15. Phy/Sta max at 29/30, so
-- dropping both floors to 28 hits far more often; use it when a playable
-- character sooner is worth more than a maxed one.
reRollBuilds.halfOgreWarriorFast = function(s)
    local accepted = s.physique >= 28 and s.stamina >= 28 and s.agility >= 15
    return accepted, reRollStatSummary(s)
end

-- Half-Ogre Hunter: simple hard floors — Phy >= 28 AND Sta >= 29 AND Agi >= 15,
-- other stats ignored. Max stats are Phy=29 Sta=30 Agi=17, so this accepts up to
-- one point below max on the two physicals (mirroring the Warrior build) and keeps
-- Agi in the 15-29 attack tier. Vitality is not matched — it is fully derived from
-- Stamina.
reRollBuilds.halfOgreHunter = function(s)
    local accepted = s.physique >= 28 and s.stamina >= 29 and s.agility >= 15
    return accepted, reRollStatSummary(s)
end

-- Judge one fresh character sheet. Called by main.lua's Vitality trigger for
-- every sheet, after it has stored the new stats; a no-op unless a re-roll is
-- running.
function taPackage.reroll.checkStats()
    if not taPackage.reRolling then return end

    local stats = {
        intellect = taPackage.character.getIntellect() or 0,
        knowledge = taPackage.character.getKnowledge() or 0,
        physique  = taPackage.character.getPhysique() or 0,
        stamina   = taPackage.character.getStamina() or 0,
        agility   = taPackage.character.getAgility() or 0,
        charisma  = taPackage.character.getCharisma() or 0,
    }

    taPackage.reRollCount = (taPackage.reRollCount or 0) + 1
    local n               = taPackage.reRollCount

    local matcher         = taPackage.reRollMatcher or reRollBuilds.elfSorceror
    local accepted, summary = matcher(stats)

    if accepted then
        taPackage.reRollGeneration = (taPackage.reRollGeneration or 0) + 1
        taPackage.reRollTimerPending = false
        echo("[re-roll] Done after " .. n .. " rolls! " .. summary .. " — type re-roll-stop when finished")
        -- Notify only for a re-roll somebody is watching for. A gold-farming run
        -- creates a throwaway character every cycle, so its stats are ephemeral
        -- and worth nothing on a phone -- and the run neither needs nor waits
        -- for a human, since ta_create.lua takes it from here on its own.
        -- createRerollArmed is that run's "this result is mine" flag; it is
        -- still set here because onRerollAccepted below is what clears it.
        if not taPackage.createRerollArmed then
            sendNtfy("Re-roll complete", "Found a match after " .. n .. " rolls: " .. summary .. ". Type re-roll-stop when finished.")
        end
        -- A scripted run (farm-for-gold) takes it from here: it stops the
        -- re-roll itself and walks the new character to the arena. Defined in
        -- ta_create.lua, and a no-op unless that script is the one that started
        -- this re-roll -- a hand-run re-roll still just stops and waits for you,
        -- which is why the message above still says to stop it yourself.
        if taPackage.onRerollAccepted then taPackage.onRerollAccepted() end
    else
        local time = os.date("%H:%M:%S")
        echo("[re-roll] #" .. n .. " at " .. time .. " — " .. summary .. " — re-rolling...")
        scheduleReroll()
    end
end

-- =========================================================================
-- The aliases
-- =========================================================================

createAlias("^re-roll-for-good-stats$", function()
    taPackage.reRollMatcher = reRollBuilds.elfSorceror
    taPackage.reRolling = true
    reRollResetStats()
    send("status")
end, { type = "regex" })

createAlias("^re-roll-half-ogre-warrior$", function()
    taPackage.reRollMatcher = reRollBuilds.halfOgreWarrior
    taPackage.reRolling = true
    reRollResetStats()
    send("status")
end, { type = "regex" })

createAlias("^re-roll-half-ogre-warrior-fast-mode$", function()
    taPackage.reRollMatcher = reRollBuilds.halfOgreWarriorFast
    taPackage.reRolling = true
    reRollResetStats()
    send("status")
end, { type = "regex" })

createAlias("^re-roll-half-ogre-hunter$", function()
    taPackage.reRollMatcher = reRollBuilds.halfOgreHunter
    taPackage.reRolling = true
    reRollResetStats()
    send("status")
end, { type = "regex" })

createAlias("^re-roll-stop$", function()
    taPackage.reRolling = false
    taPackage.reRollTimerPending = false
    taPackage.reRollGeneration = (taPackage.reRollGeneration or 0) + 1
    echo("[re-roll] Stopped.")
    createTimer(2000, function()
        taPackage.reRollSuppressStats = false
    end, { repeating = false })
end, { type = "regex" })
