--
-- This script will be read by [baud](https://github.com/jedcn/baud).
--
-- Details [here](https://github.com/jedcn/baud?tab=readme-ov-file#loading-scripts)
--
echo("Starting to read main.lua")

-- SCRIPT_DIR is set by Baud to the directory containing this script
local scriptDir = SCRIPT_DIR
if not scriptDir then
    error("SCRIPT_DIR not set - are you running this through Baud?")
end

-- Derive absolute directory from debug info so io.open paths work regardless
-- of baud's working directory (which may be /).
local function absoluteScriptDir()
    local src = debug.getinfo(1, "S").source
    if src and src:sub(1, 1) == "@" then
        local path = src:sub(2)
        if path:sub(1, 1) == "/" then
            return path:match("^(.+)/[^/]+$") .. "/"
        end
    end
    -- Fallback: baud data dir, which is a known writable absolute path.
    -- os.getenv cannot see it: baud runs Lua as WASM, so os.getenv reads the
    -- emscripten sandbox environment and HOME comes back nil, which silently
    -- made this "/Library/Application Support/baud/" -- a path off the root of
    -- the filesystem. baud's own getenv reads the real environment.
    local home = (getenv and getenv("HOME")) or os.getenv("HOME") or ""
    return home .. "/Library/Application Support/baud/"
end

-- =========================================================================
-- State
-- =========================================================================

if not taPackage then
    taPackage = {}
    taPackage.character = {}
end

if not taPackage.roomPresence then
    taPackage.roomPresence = {}
end

if not taPackage.monsterDb then
    local Db = dofile(scriptDir .. "db.lua")
    local dbPath = absoluteScriptDir() .. "monsters.lua"
    taPackage.monsterDb = {
        monsters = Db.load(dbPath),
        db = Db,
        dbPath = dbPath,
        state = "idle",
        lookTarget = nil,
        accumulatedLines = {},
    }
end

taPackage.db = dofile(scriptDir .. "ta_db.lua")

function setCharacterStatus(value)
    taPackage.character.status = value
end

function getCharacterStatus()
    return taPackage.character.status
end

function setVitality(current, max)
    taPackage.character.vitalityCurrent = tonumber(current)
    taPackage.character.vitalityMax = tonumber(max)
end

function getVitality()
    return taPackage.character.vitalityCurrent, taPackage.character.vitalityMax
end

-- Encumberance is the game's carried-weight gauge, printed on the "st" sheet as
-- "current / max" (e.g. 1000 / 1000 = fully loaded). Stored like Vitality/Mana.
function setEncumberance(current, max)
    taPackage.character.encumberanceCurrent = tonumber(current)
    taPackage.character.encumberanceMax = tonumber(max)
end

function getEncumberance()
    return taPackage.character.encumberanceCurrent, taPackage.character.encumberanceMax
end

-- Encumberance as a whole-number percentage of max (0-100+), or nil if either
-- value is missing or max is 0. Display-only helper for notifications.
function getEncumberancePercent()
    local current, max = getEncumberance()
    if not current or not max or max == 0 then return nil end
    return math.floor((current / max) * 100 + 0.5)
end

function setMana(current, max)
    taPackage.character.manaCurrent = tonumber(current)
    taPackage.character.manaMax = tonumber(max)
end

function getMana()
    return taPackage.character.manaCurrent, taPackage.character.manaMax
end

function setExperience(value)
    local previous = taPackage.character.experience
    local current = tonumber(value)
    taPackage.character.experience = current
    -- The status bar flashes how far the XP figure just moved, and this is the
    -- one place that knows a move happened. recordXpChange is defined with the
    -- status bar, further down the chunk, so it only exists once the script has
    -- finished loading -- which is always true by the time a trigger calls us.
    if recordXpChange then recordXpChange(previous, current) end
end

function getExperience()
    return taPackage.character.experience
end

-- Group an integer into comma-separated thousands, e.g. 620046 -> "620,046".
-- Display-only (notifications); returns non-numbers unchanged.
function formatWithCommas(n)
    local num = tonumber(n)
    if not num then return tostring(n) end
    local s = tostring(math.floor(num))
    while true do
        local replaced
        s, replaced = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

-- Fire-and-forget push to our ntfy topic. `title` becomes the notification
-- title (ntfy's X-Title header), `body` the message. Pass markdown=true to have
-- ntfy render the body as Markdown (X-Markdown header). No callback — a failed
-- ping must never disturb whatever loop triggered it.
function sendNtfy(title, body, markdown)
    local headers = { ["X-Title"] = title }
    if markdown then
        headers["X-Markdown"] = "true"
    end
    httpRequest("https://ntfy.sh/s5bbs-tele-arena-j5", {
        method = "POST",
        headers = headers,
        body = body,
    })
end

function setClass(value)
    taPackage.character.class = value
end

function getClass()
    return taPackage.character.class
end

function setLevel(value)
    taPackage.character.level = tonumber(value)
end

function getLevel()
    return taPackage.character.level
end

-- Forward declaration: setGold is the single chokepoint every gold change flows
-- through, so the arena's "below the minimum to keep going" safety check hangs
-- off it. The real definition (with the floor and the emergency exit) lives
-- alongside the other arena helpers much later; assigning to this local there
-- (see `function checkArenaGoldFloor()`, no `local`) lets setGold close over it.
local checkArenaGoldFloor

function setGold(value)
    taPackage.character.gold = tonumber(value)
    if checkArenaGoldFloor then checkArenaGoldFloor() end
end

function getGold()
    return taPackage.character.gold
end

function setPhysique(value)
    taPackage.character.physique = tonumber(value)
end

function getPhysique()
    return taPackage.character.physique
end

function setStamina(value)
    taPackage.character.stamina = tonumber(value)
end

function getStamina()
    return taPackage.character.stamina
end

function setAgility(value)
    taPackage.character.agility = tonumber(value)
end

function getAgility()
    return taPackage.character.agility
end

function setCharisma(value)
    taPackage.character.charisma = tonumber(value)
end

function getCharisma()
    return taPackage.character.charisma
end

function setIntellect(value)
    taPackage.character.intellect = tonumber(value)
end

function getIntellect()
    return taPackage.character.intellect
end

function setKnowledge(value)
    taPackage.character.knowledge = tonumber(value)
end

function getKnowledge()
    return taPackage.character.knowledge
end

-- =========================================================================
-- XP tables by class (from "help Exp1" and "help Exp2")
-- =========================================================================

local xpThresholds     = {
    Warrior = {
        [1] = 0,
        [2] = 1125,
        [3] = 3240,
        [4] = 8025,
        [5] = 17890,
        [6] = 36000,
        [7] = 66300,
        [8] = 113400,
        [9] = 182600,
        [10] = 280200,
        [11] = 413000,
        [12] = 588700,
        [13] = 815600,
        [14] = 1102800,
        [15] = 1460100,
        [16] = 1898300,
        [17] = 2428600,
        [18] = 3063100,
        [19] = 3814700,
        [20] = 4696900,
        [21] = 5724000,
        [22] = 6911200,
        [23] = 8274200,
        [24] = 9829700,
        [25] = 11594700,
    },
    Archer = {
        [1] = 0,
        [2] = 1125,
        [3] = 3240,
        [4] = 8025,
        [5] = 17890,
        [6] = 36000,
        [7] = 66300,
        [8] = 113400,
        [9] = 182600,
        [10] = 280200,
        [11] = 413000,
        [12] = 588700,
        [13] = 815600,
        [14] = 1102800,
        [15] = 1460100,
        [16] = 1898300,
        [17] = 2428600,
        [18] = 3063100,
        [19] = 3814700,
        [20] = 4696900,
        [21] = 5724000,
        [22] = 6911200,
        [23] = 8274200,
        [24] = 9829700,
        [25] = 11594700,
    },
    Hunter = {
        [1] = 0,
        [2] = 1125,
        [3] = 3240,
        [4] = 8025,
        [5] = 17890,
        [6] = 36000,
        [7] = 66300,
        [8] = 113400,
        [9] = 182600,
        [10] = 280200,
        [11] = 413000,
        [12] = 588700,
        [13] = 815600,
        [14] = 1102800,
        [15] = 1460100,
        [16] = 1898300,
        [17] = 2428600,
        [18] = 3063100,
        [19] = 3814700,
        [20] = 4696900,
        [21] = 5724000,
        [22] = 6911200,
        [23] = 8274200,
        [24] = 9829700,
        [25] = 11594700,
    },
    Rogue = {
        [1] = 0,
        [2] = 1120,
        [3] = 3200,
        [4] = 7860,
        [5] = 17440,
        [6] = 35000,
        [7] = 64400,
        [8] = 109900,
        [9] = 177000,
        [10] = 271500,
        [11] = 400000,
        [12] = 570100,
        [13] = 789600,
        [14] = 1067600,
        [15] = 1413500,
        [16] = 1837500,
        [17] = 2350800,
        [18] = 2964800,
        [19] = 3692200,
        [20] = 4546000,
        [21] = 5540000,
        [22] = 6689000,
        [23] = 8008000,
        [24] = 9513300,
        [25] = 11221500,
    },
    Acolyte = {
        [1] = 0,
        [2] = 1150,
        [3] = 3490,
        [4] = 9025,
        [5] = 20640,
        [6] = 42200,
        [7] = 78200,
        [8] = 134300,
        [9] = 216900,
        [10] = 333500,
        [11] = 492000,
        [12] = 701800,
        [13] = 972800,
        [14] = 1315900,
        [15] = 1742800,
        [16] = 2266200,
        [17] = 2899600,
        [18] = 3657600,
        [19] = 4555300,
        [20] = 5609100,
        [21] = 6836000,
        [22] = 8254100,
        [23] = 9882100,
        [24] = 11739900,
        [25] = 13848000,
    },
    Sorceror = {
        [1] = 0,
        [2] = 1180,
        [3] = 3800,
        [4] = 10290,
        [5] = 24160,
        [6] = 50000,
        [7] = 93500,
        [8] = 161400,
        [9] = 261500,
        [10] = 402700,
        [11] = 595000,
        [12] = 849600,
        [13] = 1178400,
        [14] = 1594900,
        [15] = 2113200,
        [16] = 2748800,
        [17] = 3518100,
        [18] = 4438700,
        [19] = 5529300,
        [20] = 6809500,
        [21] = 8300000,
        [22] = 10022900,
        [23] = 12001000,
        [24] = 14258400,
        [25] = 16820200,
    },
}
-- Classes that share thresholds with others
xpThresholds.Necrolyte = xpThresholds.Acolyte
xpThresholds.Druid     = xpThresholds.Sorceror

function getLevelForXp(xp, class)
    local thresholds = xpThresholds[class or "Warrior"]
    for lvl = 25, 2, -1 do
        if xp >= thresholds[lvl] then return lvl end
    end
    return 1
end

function getXpForNextLevel(xp, class)
    local currentLevel = getLevelForXp(xp, class)
    if currentLevel >= 25 then return nil end
    local thresholds = xpThresholds[class or "Warrior"]
    return thresholds[currentLevel + 1]
end

-- True when we have banked enough XP for a level we haven't trained for yet:
-- the level our XP earns us has outrun the level the game reports. Training is
-- a manual trip to a guild hall (and some arenas have none), so that gap can
-- stay open for a long time — the status bar flags it with a "^".
-- Deliberately independent of checkTrainingNeeded, which additionally gates on
-- the arena profile: the mark is about the character, not about whether the
-- arena script is about to act on it.
function hasUntrainedLevel()
    local xp, class, level = getExperience(), getClass(), getLevel()
    -- Any unknown, or a class we have no XP table for, means we can't tell —
    -- and getLevelForXp would silently fall back to the Warrior table.
    if not (xp and class and level and xpThresholds[class]) then return false end
    return getLevelForXp(xp, class) > level
end

-- Push a "ready to train for the next level" notification the moment XP crosses
-- a level threshold. We track the XP-derived level in character.earnedLevel and
-- alert once each time it climbs. XP doesn't reset on training, so after
-- training the earned level holds until the next threshold — one clean alert
-- per level. Fires regardless of arena profile; runs on every status poll.
function checkLevelUpNotification(xp)
    local class = getClass()
    -- Only act on classes we have a real XP table for; getLevelForXp silently
    -- falls back to Warrior otherwise, which would give a wrong threshold.
    if not (xp and class and xpThresholds[class]) then return end
    local newEarned = getLevelForXp(xp, class)
    local prev = taPackage.character.earnedLevel
    if prev == nil then
        -- First observation: seed silently so we only alert on later crossings,
        -- not on every fresh login / script reload.
        taPackage.character.earnedLevel = newEarned
        return
    end
    if newEarned > prev then
        taPackage.character.earnedLevel = newEarned
        local threshold = xpThresholds[class][newEarned]
        -- thresholds[N] is the XP required to reach level N (verified against the
        -- game's own `help Exp1` table and a real training event), so crossing it
        -- means you've earned enough to train up to level N.
        sendNtfy("Time to Level Up!",
            (taPackage.character.name or "?") .. " just passed "
                .. formatWithCommas(threshold)
                .. " and is ready to train for level " .. newEarned)
    end
end

-- Progress through the current level, from just-leveled (blue) to about-to-level
-- (red), walking across the color wheel through violet/magenta/pink in between.
-- All light/readable tints so the value stays visible against a dark status bar.
-- =========================================================================
-- Triggers
-- =========================================================================

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

-- A normalized, color-coded badge echoed right after a combat line so the
-- result doesn't get lost in the fast scroll of party/monster chatter. Both
-- badges share the same bold, padded, near-white block so they read as a
-- matched pair; only the foreground color differs: blue for damage we deal,
-- pink/red for damage we take. Defined here (above the Vitality trigger) so the
-- trap handler below can badge from there too.
local BADGE_BG = "#e0e0e0"
local OUTGOING_FG = "#2563eb" -- blue: damage we deal
local INCOMING_FG = "#ff5fd7" -- pink/red: damage we take
local HEAL_FG = "#16a34a" -- green: healing we cast (blue is reserved for damage dealt)
local function badge(fg, text)
    cechoBg(fg, BADGE_BG, " " .. text .. " ", true)
end
local function outgoingBadge(text) badge(OUTGOING_FG, text) end
local function incomingBadge(text) badge(INCOMING_FG, text) end
local function healingBadge(text) badge(HEAL_FG, text) end

-- On entering the arena, pull our character sheet (st) and inventory (i) so the
-- script's tracked state is populated right away instead of waiting for the
-- first manual status check. TA_INIT_CMD rides on the tail of this: the `i`
-- reply's gold line is what tells runLoginInitCmd the sheet has landed, so
-- dropping the `i` here would strand it.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    -- A character is in the game again, so whatever death preceded this is over
    -- as far as every reader of taPackage.died is concerned. Cleared here, in
    -- one place, rather than by whichever script happened to look first.
    taPackage.died = nil
    taPackage.diedAt = nil
    send("st")
    send("i")
end, { type = "regex" })

createTrigger("^Status:\\s+(\\S+)$", function(matches)
    setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Mana:\\s+(\\d+) / (\\d+)$", function(matches)
    setMana(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Encumberance:\\s+(\\d+) / (\\d+)$", function(matches)
    setEncumberance(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    -- A trap hurt us without printing a damage number; the trap handler stashed
    -- our HP and fired "st", so this fresh Vitality line lets us recover the hit
    -- as the drop from the stashed value.
    local trapBefore = taPackage.trapHpBefore
    if trapBefore then
        taPackage.trapHpBefore = nil
        local lost = trapBefore - tonumber(matches[2])
        if lost > 0 then incomingBadge("TRAP " .. lost) end
    end
    -- Same trick for an area-effect spell: the caster's handler stashed our HP
    -- and fired "st", so this fresh Vitality line recovers the hit and badges it.
    local aoeBefore = taPackage.aoeHpBefore
    if aoeBefore then
        taPackage.aoeHpBefore = nil
        local lost = aoeBefore - tonumber(matches[2])
        if lost > 0 then incomingBadge("AOE " .. lost) end
    end
    -- And the mirror image: a party member's area heal landed on us. It names no
    -- amount, so its handler stashed our HP and fired "st" — the gain is the
    -- *rise* from the stashed value. A heal that hit us at full HP gains
    -- nothing, and the non-heal area spells gain nothing either; both stay
    -- silent rather than badging a zero.
    local groupHealBefore = taPackage.groupHealHpBefore
    if groupHealBefore then
        taPackage.groupHealHpBefore = nil
        local gained = tonumber(matches[2]) - groupHealBefore
        if gained > 0 then
            healingBadge("HEALED BY " .. string.upper(taPackage.groupHealCaster or "?")
                .. " FOR " .. gained)
        end
    end
    setVitality(matches[2], matches[3])
    -- A held level-up notification is waiting on exactly this line for the new
    -- HP/MP maxima. Defined with the training trigger far below, so it only
    -- exists once the chunk has loaded (always true by the time a line arrives).
    if noticeLevelUpStats then noticeLevelUpStats() end
    if not taPackage.reRolling then return end

    local stats = {
        intellect = taPackage.character.intellect or 0,
        knowledge = taPackage.character.knowledge or 0,
        physique  = taPackage.character.physique or 0,
        stamina   = taPackage.character.stamina or 0,
        agility   = taPackage.character.agility or 0,
        charisma  = taPackage.character.charisma or 0,
    }

    taPackage.reRollCount = (taPackage.reRollCount or 0) + 1
    local n               = taPackage.reRollCount

    local matcher         = taPackage.reRollMatcher or reRollBuilds.elfSorceror
    local accepted, summary = matcher(stats)

    if accepted then
        taPackage.reRollGeneration = (taPackage.reRollGeneration or 0) + 1
        taPackage.reRollTimerPending = false
        echo("[re-roll] Done after " .. n .. " rolls! " .. summary .. " — type re-roll-stop when finished")
        sendNtfy("Re-roll complete", "Found a match after " .. n .. " rolls: " .. summary .. ". Type re-roll-stop when finished.")
        -- A scripted run (start-gold-farming) takes it from here: it stops the
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
end, { type = "regex" })

createTrigger("^Class:\\s+(\\S+)$", function(matches)
    setClass(matches[2])
end, { type = "regex" })

createTrigger("^Weapon:\\s+(.+)$", function(matches)
    taPackage.character.weapon = matches[2]
end, { type = "regex" })

createTrigger("^Physique:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getPhysique()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Physique", oldVal, newVal)
    end
    setPhysique(newVal)
end, { type = "regex" })

createTrigger("^Stamina:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getStamina()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Stamina", oldVal, newVal)
    end
    setStamina(newVal)
end, { type = "regex" })

createTrigger("^Agility:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getAgility()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Agility", oldVal, newVal)
    end
    setAgility(newVal)
end, { type = "regex" })

createTrigger("^Charisma:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getCharisma()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Charisma", oldVal, newVal)
    end
    setCharisma(newVal)
end, { type = "regex" })

createTrigger("^Intellect:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getIntellect()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Intellect", oldVal, newVal)
    end
    setIntellect(newVal)
end, { type = "regex" })

createTrigger("^Knowledge:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = getKnowledge()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Knowledge", oldVal, newVal)
    end
    setKnowledge(newVal)
end, { type = "regex" })

createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
    setGold(matches[2])
    -- The last reply of the `st`/`i` pair the entry trigger fires, so this is
    -- the moment the character sheet is fully parsed and an init command can
    -- safely run. It is a no-op on every other inventory check.
    runLoginInitCmd()
end, { type = "regex" })

-- Buying passage across the great lake charges us, but the ship message doesn't
-- report the fare, so fire an inventory check to re-capture our current gold.
--
-- The ferry is also a real map edge. It teleports between the two towns' docks,
-- which share the name "docks", so without recording the crossing the mapper
-- would fold the far docks into the near one by name and then mis-link the next
-- move across the seam. Record it as a "passage" move (mirroring a move alias):
-- the arrival brief then links the two docks with a bidirectional ferry edge.
-- "passage" has no grid delta, so it never distorts either town's coordinates.
createTrigger("^You buy passage across the great lake and board a ship", function()
    taPackage.suppressRoomEntry = nil
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.prevRoomId = taPackage.currentRoomId
    taPackage.pendingDirection = "passage"
    send("i")
end, { type = "regex" })

createTrigger("^You found (\\d+) gold crowns while searching the (.+)'s corpse\\.$", function(matches)
    local found = tonumber(matches[2])
    local monster = matches[3]
    setGold((getGold() or 0) + found)
    taPackage.db.recordMonsterLoot(monster, found)
    if taPackage.lastKilledMonster == monster then
        taPackage.pendingLootCheck = nil
        taPackage.lastKilledMonster = nil
    end
end, { type = "regex" })

createTrigger("^You found (\\d+) gold crowns while searching the area\\.$", function(matches)
    local found = tonumber(matches[2])
    local monster = taPackage.lastKilledMonster or "unknown"
    setGold((getGold() or 0) + found)
    taPackage.db.recordMonsterLoot(monster, found)
    taPackage.pendingLootCheck = nil
    taPackage.lastKilledMonster = nil
end, { type = "regex" })

-- An item found while searching a corpse. The game hard-wraps this line at the
-- terminal width, so it arrives whole (short items) or split after "...add to
-- your" (the "possessions." lands on the next line). Match both forms -- they're
-- mutually exclusive, so only one fires per pickup. Record it against the room
-- we're standing in (only trusted while mapping; currentRoomId is stale
-- otherwise) so the map can show where items -- notably door keys -- are found.
local function recordSearchItem(item)
    local monster = taPackage.lastKilledMonster or "unknown"
    local roomId = taPackage.mapping and taPackage.currentRoomId or nil
    taPackage.db.recordItemDrop(monster, item, roomId)
end
createTrigger("^While searching the area, you notice (.+), which you add to your possessions\\.$", function(matches)
    recordSearchItem(matches[2])
end, { type = "regex" })
createTrigger("^While searching the area, you notice (.+), which you add to your$", function(matches)
    recordSearchItem(matches[2])
end, { type = "regex" })
-- Same discovery, but your inventory was full so you couldn't pick it up. The
-- item still exists in this room, so record it the same way -- the map cares
-- where a key was *found*, not whether we happened to be carrying room for it.
createTrigger("^While searching the area, you notice (.+), but you can't carry it\\.$", function(matches)
    recordSearchItem(matches[2])
end, { type = "regex" })

createTrigger("^You gave (\\d+) gold coins to (.+)\\.$", function(matches)
    local amount = tonumber(matches[2])
    setGold((getGold() or 0) - amount)
end, { type = "regex" })

createTrigger("^(.+) just gave you (\\d+) gold coins\\.$", function(matches)
    local amount = tonumber(matches[3])
    setGold((getGold() or 0) + amount)
end, { type = "regex" })

createTrigger("^You deposited (\\d+) gold in your account\\.$", function(matches)
    local amount = tonumber(matches[2])
    setGold((getGold() or 0) - amount)
end, { type = "regex" })

createTrigger("^You withdrew (\\d+) gold from your account\\.$", function(matches)
    local amount = tonumber(matches[2])
    setGold((getGold() or 0) + amount)
end, { type = "regex" })

createTrigger("^Ok, you bought .+ for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    setGold((getGold() or 0) - cost)
end, { type = "regex" })

createTrigger("^The priests heal all your wounds for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    setGold((getGold() or 0) - cost)
    local _, max = getVitality()
    if max then
        setVitality(max, max)
    end
    taPackage.db.recordService("healing", "temple", cost)
end, { type = "regex" })

-- =========================================================================
-- Monster database
-- =========================================================================

local function isHealthLine(line)
    return string.find(line, "wounded") ~= nil
        or string.match(line, "health%.$") ~= nil
        or string.find(line, "falls to the ground lifeless") ~= nil
end

local function extractMonsterName(firstLine)
    -- Try several first-sentence verbs; take the shortest match so that a description
    -- like "The huge rat resembles … and is …" picks "huge rat" via "resembles" rather
    -- than the longer capture via the later "is".
    local best = nil
    for _, verb in ipairs({ " is ", " has ", " resembles ", " appears " }) do
        local name = string.match(firstLine, "^The (.-)" .. verb)
        if name and (best == nil or #name < #best) then
            best = name
        end
    end
    return best
end

-- The health sentence always names the monster explicitly ("The female orc seems to be…",
-- "It looks as if the lizard man is…"). Use that as the canonical name — it's more
-- reliable than parsing the description's first line (which may say "The orc is…"
-- for a "female orc", giving the wrong name).
local function extractNameFromHealthLine(line)
    return string.match(line, "^The (.-) seems to be")
        or string.match(line, "^The (.-) appears to be")
        or string.match(line, "^The (.-) is .-wounded")
        or string.match(line, "^The (.-) falls to the ground")
        or string.match(line, "^It looks as if the (.-) is ")
end

-- When the server puts description text and the health sentence on the same line
-- (e.g. "claws and teeth. The X seems to be in good physical health."), pull out
-- the description part that precedes the health sentence.
local function descPrefixFromHealthLine(line)
    local lastPos = nil
    for _, sep in ipairs({ ". The ", ". It " }) do
        local pos = 1
        while true do
            local found = string.find(line, sep, pos, true)
            if not found then break end
            lastPos = found
            pos = found + 1
        end
    end
    if lastPos then
        return string.sub(line, 1, lastPos)
    end
    return nil
end

local function upsertMonster(name, description)
    local db = taPackage.monsterDb.monsters
    local today = os.date("%Y-%m-%d")
    if db[name] then
        db[name].description = description
        db[name].encounters = db[name].encounters + 1
    else
        db[name] = { description = description, firstSeen = today, encounters = 1 }
    end
    pcall(taPackage.monsterDb.db.save, taPackage.monsterDb.dbPath, db)
end

function getMonsterEntry(name)
    return taPackage.monsterDb.monsters[name]
end

function getMonsterDbState()
    return taPackage.monsterDb.state
end

local function startLook(target)
    taPackage.monsterDb.state = "accumulating"
    taPackage.monsterDb.lookTarget = target
    taPackage.monsterDb.accumulatedLines = {}
end

createTrigger("^l (.+)$", function(matches)
    startLook(matches[2])
end, { type = "regex" })

createTrigger("^look (.+)$", function(matches)
    startLook(matches[2])
end, { type = "regex" })

-- Bare "look" or "l" (no target) = room description
createTrigger("^look$", function()
    taPackage.monsterDb.state = "accumulating_room"
    taPackage.monsterDb.accumulatedLines = {}
end, { type = "regex" })

createTrigger("^l$", function()
    taPackage.monsterDb.state = "accumulating_room"
    taPackage.monsterDb.accumulatedLines = {}
end, { type = "regex" })

-- `look <dir>` / `l <dir>` peeks at the adjacent room; its reply opens with
-- "You're in <that room>." — indistinguishable from an arrival brief. Flag it so
-- the very next room brief is ignored rather than mapped as a phantom room. A
-- real move clears the flag (see the movement aliases), so a look that returns
-- no room (a wall) can't leave the flag armed against your next real arrival.
local function suppressNextRoomEntry()
    taPackage.suppressRoomEntry = true
end
createTrigger("^look ([nsewud][sewn]?)$", suppressNextRoomEntry, { type = "regex" })
createTrigger("^l ([nsewud][sewn]?)$", suppressNextRoomEntry, { type = "regex" })

-- After 1 hour a monster in the same room is treated as a new encounter:
-- by then it has healed back to full health and is effectively a fresh data point.
local PRESENCE_TIMEOUT = 3600

local function presenceKey(room, monster) return room .. "|" .. monster end

local function isNewEncounter(monster)
    local room = taPackage.currentRoom
    if not room then return true end
    local seenAt = taPackage.roomPresence[presenceKey(room, monster)]
    if seenAt == nil then return true end
    return (os.time() - seenAt) > PRESENCE_TIMEOUT
end

local function markPresent(monster)
    local room = taPackage.currentRoom
    if room then
        taPackage.roomPresence[presenceKey(room, monster)] = os.time()
    end
end

local function clearPresence(monster)
    local room = taPackage.currentRoom
    if room then
        taPackage.roomPresence[presenceKey(room, monster)] = nil
    end
end

local function recordEncounter(name)
    local entry = taPackage.monsterDb.monsters[name]
    if entry then
        entry.encounters = entry.encounters + 1
        pcall(taPackage.monsterDb.db.save, taPackage.monsterDb.dbPath, taPackage.monsterDb.monsters)
    end
end

createTrigger("^There is a (.+) here\\.$", function(matches)
    local name = matches[2]
    if isNewEncounter(name) then
        recordEncounter(name)
        taPackage.db.recordMonsterSeen(name)
    end
    markPresent(name)
end, { type = "regex" })

createTrigger("^An? (.+) enters ", function(matches)
    local name = matches[2]
    if isNewEncounter(name) then
        recordEncounter(name)
        taPackage.db.recordMonsterSeen(name)
    end
    markPresent(name)
end, { type = "regex" })

local DIRECTION_PATTERN = "^[nsewud][sewn]?$"

local function trimLine(line)
    return (line or ""):match("^%s*(.-)%s*$")
end

-- Published for the navigation chunk, which lives in its own file (see the
-- dofile of ta_nav.lua) and so cannot see main.lua's locals. A field costs no
-- local slot, which is the other half of why the split works.
taPackage.trimLine = trimLine

local function isRoomLine(line)
    return string.match(line, "^You're in ")
        or string.match(line, "^You are in ")
        or string.match(line, "^You are inside ")
        or string.match(line, "^You are outside ")
end

-- A look description runs until the paired `ex` reply ("Exits: ...") — the one
-- reliable terminator, and only our auto-`ex` produces it (look prose describes
-- exits in English, never as "Exits:"). We must NOT terminate on room-brief
-- phrasings: a cave's look opens "You're in a damp, poorly lit cave. Glowing
-- lichens..." — bailing on "^You're in " would swallow the whole description.
-- (`Sorry,` covers a command failing mid-look.)
local function isRoomDescTerminator(line)
    return string.match(line, "^Exits:")
        or string.match(line, "^Sorry,")
end

local function cleanRoomDesc(desc)
    -- Strip "look " or "l " prefix if the echo got accumulated
    desc = desc:gsub("^look%s+", ""):gsub("^l%s+", "")
    -- Strip trailing single direction word (e.g. " e", " sw", " d")
    desc = desc:gsub("%s+[nsewud][sewn]?$", "")
    return desc
end

createTrigger("^(.+)$", function(matches)
    local line = trimLine(matches[2])

    if taPackage.monsterDb.state == "accumulating_room" then
        -- Skip our own echoed commands (look starts the capture, ex ends it).
        if line == "look" or line == "l" or line == "ex" then return end
        if isRoomDescTerminator(line) then
            local lines = taPackage.monsterDb.accumulatedLines
            if #lines > 0 and taPackage.currentRoomId then
                local desc = cleanRoomDesc(table.concat(lines, " "))
                if #desc > 0 then
                    taPackage.db.setRoomDescription(taPackage.currentRoomId, desc)
                end
            end
            taPackage.monsterDb.state = "idle"
            taPackage.monsterDb.accumulatedLines = {}
        else
            table.insert(taPackage.monsterDb.accumulatedLines, line)
        end
        return
    end

    if taPackage.monsterDb.state ~= "accumulating" then return end
    if string.match(line, "^l .") or string.match(line, "^look .") then return end
    if isRoomLine(line) or string.match(line, "^There is ") then
        taPackage.monsterDb.state = "idle"
        taPackage.monsterDb.accumulatedLines = {}
        return
    end
    if isHealthLine(line) then
        local lines = taPackage.monsterDb.accumulatedLines
        -- Extract description text that precedes the health sentence on the same line
        -- (e.g. "claws and teeth. The X seems to be in good physical health.")
        local prefix = descPrefixFromHealthLine(line)
        if prefix then table.insert(lines, prefix) end
        if #lines > 0 then
            -- The health sentence names the monster explicitly ("The female orc seems to be…");
            -- when the health line has a description prefix, strip it first to isolate the sentence.
            local healthSentence = prefix and string.sub(line, #prefix + 2) or line
            local canonicalName = extractNameFromHealthLine(healthSentence)
                or extractMonsterName(lines[1])
                or taPackage.monsterDb.lookTarget
            local desc = table.concat(lines, " ")
            -- If the health status was split across two server lines, the first fragment
            -- (e.g. "The X seems to be in") got accumulated; truncate at last period to drop it.
            desc = desc:match("^(.*%.)") or desc
            upsertMonster(canonicalName, desc)
            taPackage.db.upsertMonster(canonicalName, desc)
            taPackage.lastAttackTarget = canonicalName
        end
        taPackage.monsterDb.state = "idle"
    else
        table.insert(taPackage.monsterDb.accumulatedLines, line)
    end
end, { type = "regex" })

-- =========================================================================
-- World map triggers
-- =========================================================================

-- Reverse of each movement direction, used to record the back-edge when we
-- discover a room by walking into it.
local REVERSE_DIR = {
    n = "s", s = "n", e = "w", w = "e",
    ne = "sw", sw = "ne", nw = "se", se = "nw",
    u = "d", d = "u",
    -- The great-lake ferry ("buy passage") is a symmetric teleport between the two
    -- towns' docks: crossing back is the same "passage", not a compass reverse.
    passage = "passage",
}

-- Grid displacement of each move, as { dx, dy, dz }: north is +y, east is +x,
-- up is +z. Dead-reckoning these from a room's stored coordinate gives the
-- coordinate of the room we walk into, which distinguishes identically-named
-- rooms by position and closes loops the topology alone misses. Coordinates are
-- area-local — only relative offsets matter, so the per-area origin is wherever
-- mapping first anchored (see handleRoomEntry).
local DIR_DELTA = {
    n = { 0, 1, 0 }, s = { 0, -1, 0 }, e = { 1, 0, 0 }, w = { -1, 0, 0 },
    ne = { 1, 1, 0 }, nw = { -1, 1, 0 }, se = { 1, -1, 0 }, sw = { -1, -1, 0 },
    u = { 0, 0, 1 }, d = { 0, 0, -1 },
}

-- Turn the phrase after "You're in/on/at ..." into a canonical room name by
-- dropping a leading article: "the tavern" -> "tavern", "a cave" -> "cave",
-- "an intersection" -> "intersection", "small cavern" -> "small cavern".
local function normalizeRoomName(phrase)
    return (phrase or ""):gsub("^the%s+", ""):gsub("^an?%s+", "")
end

-- Resolve the room we entered when there's no move to walk from (session start,
-- recall, teleport): stay in the room we already believe we're in, else the
-- unique room with this name, else discover a fresh one. Returns the room id and
-- whether it was newly discovered (provisional, i.e. a merge candidate).
local function resolveColdStart(name)
    if taPackage.currentRoomId and name == taPackage.currentRoom then
        return taPackage.currentRoomId, false
    end
    local ids = taPackage.db.roomIdsByName(name)
    if #ids == 1 then return ids[1], false end
    if #ids == 0 then return taPackage.db.discoverRoom(name, taPackage.currentAreaId), true end
    return ids[1], false
end

-- Topology-based room identity: when we arrive after moving `dir` from a known
-- room, the room is whatever that exit already points to; only when the exit's
-- destination is unknown do we mint a new room id and link both directions.
-- A newly-minted room is flagged provisional: the `Exits:` handler may later
-- fold it into an existing room once we know its exit-set (loop closure).
local function handleRoomEntry(matches)
    -- A `look <dir>` peek prints the neighbor's "You're in ..." brief, identical
    -- to an arrival. Suppress that one line so we don't mint a phantom room for a
    -- room we only glanced at (and don't fire the auto look/ex for it).
    if taPackage.suppressRoomEntry then
        taPackage.suppressRoomEntry = false
        return
    end

    local name = normalizeRoomName(matches[2])

    -- A `map-print-room-slug` probe just wants this brief's room name; capture it
    -- and stop, so the probe's bare return doesn't disturb the map (the paired
    -- `ex` resolves and prints in the Exits handler). Takes priority over mapping.
    if taPackage.slugProbe then
        taPackage.slugProbe.name = name
        return
    end

    -- A paced walk (`navigate-to`) advances one room at a time on these briefs.
    -- It hooks in here rather than owning its own room triggers so it inherits
    -- every phrasing of the arrival line -- "You're in/inside/on/at", the "You
    -- are ..." variants, and the verbless "You at ..." -- along with the two
    -- guards above, which stop a `look <dir>` peek or a `look` reply being
    -- counted as a move. (Miscounting arrivals is exactly how the arena's paced
    -- walk wedged in July 2026; see arenaJourneyOnMovement.) It sits ahead of
    -- the mapping gate below because a walk always runs with mapping off -- it
    -- suspends mapping for its duration precisely so it can't write to the map
    -- (see navStart). The hook is installed by the navigation section below.
    if taPackage.navOnRoomBrief then taPackage.navOnRoomBrief(name) end

    -- A kill with no gold found before we left records zero loot.
    -- (Loot bookkeeping is independent of mapping mode.)
    if taPackage.pendingLootCheck and taPackage.lastKilledMonster then
        taPackage.db.recordMonsterLoot(taPackage.lastKilledMonster, 0)
        taPackage.pendingLootCheck = nil
        taPackage.lastKilledMonster = nil
    end

    -- Mapping mode gates the whole room *graph*: when off, we don't discover,
    -- visit, link, or track position at all. The room *name* is not part of the
    -- graph, so it's tracked either way -- plain bookkeeping that non-mapping
    -- features read: hang-around-in-tavern's "are we standing in a bar?" check,
    -- and the monster-presence keys above. Gating the name too left currentRoom
    -- nil for the whole of any ordinary (non-mapping) session.
    -- It's set here rather than hoisted above this gate because the mapping path
    -- below calls resolveColdStart, which recognizes "we're still in the room we
    -- thought we were" by comparing the new name against the *previous*
    -- currentRoom -- so that value has to survive until then.
    if not taPackage.mapping then
        taPackage.prevRoom = taPackage.currentRoom
        taPackage.currentRoom = name
        return
    end

    -- The coordinate we expect to arrive at: the room we left plus the move's
    -- grid delta. nil when we have no prior coordinate to walk from (a cold
    -- start, or a prev room that was never anchored).
    local arriveCoord
    if taPackage.pendingDirection and taPackage.prevRoomId then
        local delta = DIR_DELTA[taPackage.pendingDirection]
        local base = taPackage.db.roomCoord(taPackage.prevRoomId)
        if delta and base then
            arriveCoord = { x = base.x + delta[1], y = base.y + delta[2], z = base.z + delta[3] }
        end
    end

    local roomId
    if taPackage.pendingDirection and taPackage.prevRoomId then
        local dir = taPackage.pendingDirection
        local dest = taPackage.db.exitDestination(taPackage.prevRoomId, dir)
        if dest and taPackage.db.roomName(dest) == name then
            roomId = dest                       -- known edge, confirmed by name
            taPackage.currentRoomProvisional = false
        elseif dest then
            -- The edge points at a room with a DIFFERENT name than we arrived in
            -- — a stale edge or a spurious room re-display (the game sometimes
            -- reprints the current room on a move). Don't trust it; re-resolve by
            -- name so we don't overwrite the wrong room.
            roomId, taPackage.currentRoomProvisional = resolveColdStart(name)
        else
            -- Unknown exit: mint a provisional room and link the edge. We do NOT
            -- identify the room by coordinate here -- that was exit-blind, and in
            -- this non-Euclidean world two distinct rooms can dead-reckon to the
            -- same coordinate, so a coordinate-only match glued unrelated rooms
            -- together (a {se,nw} room folded onto a 4-exit one). Identity is
            -- resolved in the Exits handler instead, which checks the exit-set:
            -- findRoomByFingerprint (exact coord + exit-set) closes grid-aligned
            -- loops, findLoopClosure (topology + return door) closes drifted ones,
            -- and a genuinely new room simply stays.
            roomId = taPackage.db.discoverRoom(name, taPackage.currentAreaId)
            taPackage.currentRoomProvisional = true
            taPackage.db.linkExit(taPackage.prevRoomId, dir, roomId)
            local back = REVERSE_DIR[dir]
            if back then taPackage.db.linkExit(roomId, back, taPackage.prevRoomId) end
        end
    else
        roomId, taPackage.currentRoomProvisional = resolveColdStart(name)
    end

    -- Anchor this room's coordinate. Adopt a stored coordinate when the room
    -- already has one (trust the persisted map over dead-reckoning, which drifts
    -- when a move is missed); otherwise stamp the coordinate we computed, or the
    -- origin for a cold anchor with nothing to walk from. taPackage.coord is the
    -- cursor the next move dead-reckons from.
    local stored = taPackage.db.roomCoord(roomId)
    if stored then
        taPackage.coord = stored
    else
        local c = arriveCoord or { x = 0, y = 0, z = 0 }
        taPackage.db.setRoomCoord(roomId, c.x, c.y, c.z)
        taPackage.coord = c
    end

    -- If we just passed through a locked door (the unlock message stashed the
    -- key/door before this brief arrived), tag the edge we crossed -- and its
    -- reverse, since the door blocks both ways -- so the map knows a key is
    -- needed here. Do this after the edges are linked above.
    if taPackage.pendingLock and taPackage.pendingDirection and taPackage.prevRoomId then
        local dir = taPackage.pendingDirection
        local lk = taPackage.pendingLock
        taPackage.db.setExitLock(taPackage.prevRoomId, dir, lk.key, lk.door)
        local back = REVERSE_DIR[dir]
        if back then taPackage.db.setExitLock(roomId, back, lk.key, lk.door) end
    end
    taPackage.pendingLock = nil

    echo("[mapdbg] entry '" .. tostring(name) .. "' roomId=" .. tostring(roomId)
        .. " (" .. type(roomId) .. ") provisional=" .. tostring(taPackage.currentRoomProvisional)
        .. " coord=(" .. taPackage.coord.x .. "," .. taPackage.coord.y .. "," .. taPackage.coord.z .. ")")

    -- Follow the room we entered into its area. If a session starts in one area
    -- (e.g. `map-here path-4` in second-town) and then walks across a frontier
    -- into a known room of another area (down into the sewers), adopt that area
    -- so rooms minted onward are filed where we actually are, not where the
    -- session happened to begin. A room just minted above already carries
    -- currentAreaId, so this is a no-op for it; a legacy row with no area (nil)
    -- leaves the current area untouched.
    local enteredArea = taPackage.db.roomArea(roomId)
    if enteredArea then taPackage.currentAreaId = enteredArea end

    taPackage.db.recordVisit(roomId)
    taPackage.prevRoomId = taPackage.currentRoomId
    taPackage.currentRoomId = roomId
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.currentRoom = name
    -- Remember how we got here for the Exits handler's loop-closure check: it
    -- runs after pendingDirection is cleared, and needs the direction walked to
    -- know which return door a closure candidate must still have open.
    taPackage.currentEntryDir = taPackage.pendingDirection
    taPackage.pendingDirection = nil

    -- Surface any notes on the room we just entered, so a warning ("pull lever
    -- here or a trap fires ahead") reaches us *before* we act -- a note we only
    -- ever see in the report is useless in the moment. Only runs while mapping,
    -- which is the sole time currentRoomId is trustworthy.
    for _, n in ipairs(taPackage.db.roomNotes(roomId)) do
        echo("[note] " .. n.note)
    end

    -- While mapping, capture the room: `look` for its description, then `ex`
    -- for its exits. The `ex` reply ("Exits: ...") both ends the look capture
    -- and drives loop closure. Neither reply is a room line, so no re-entry.
    send("look")
    send("ex")
end

-- One trigger per preposition (mutually exclusive prefixes, so no double-fire).
-- The "You're" contraction is always a move brief.
createTrigger("^You're in (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're inside (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're on (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're at (.+)\\.$", handleRoomEntry, { type = "regex" })
-- "outside" is the fifth preposition, and it went missing for a long time
-- because exactly one known room uses it -- "You're outside the town gates.",
-- between the first town's south plaza and the mountains. The cost was paid
-- twice. The mapper walked through it on 2026-07-13, couldn't read the name,
-- and left a south-plaza --sw--> mountains edge that swallows the room whole.
-- And a `navigate-to ruined-town` walk stepped into it on 2026-08-04 and simply
-- stopped: the arrival never registered, so the walk sat waiting for a brief
-- that had already gone past.
createTrigger("^You're outside (.+)\\.$", handleRoomEntry, { type = "regex" })

-- Some rooms print their move brief with "You are ..." instead of the "You're"
-- contraction (e.g. "You are inside the dungeon entrance.", "You are in a large
-- cavern."). That exact phrasing is ALSO the first line of every look
-- description, so it's ambiguous by wording. The tell: a look line arrives while
-- we're accumulating a description; a move brief arrives when we're idle. Only
-- treat "You are ..." as an arrival when we're not mid-look.
local function handleRoomEntryUnlessLooking(matches)
    if taPackage.monsterDb.state == "accumulating_room" then return end
    handleRoomEntry(matches)
end
createTrigger("^You are in (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are inside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are on (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are at (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })
createTrigger("^You are outside (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })

-- A few rooms have a grammatically broken move brief that drops the verb
-- entirely: "You at the bottom of a stairwell." (no "'re"/"are"). It's a real,
-- consistent game quirk, and without a matching trigger the arrival is missed —
-- the mapper stays in the room above, then mis-links everything you map next and
-- mints duplicates when you climb back. Treated like the "You are ..." forms
-- (idle-only, so a look line can't spoof it). Only "at" has been seen so far.
createTrigger("^You at (.+)\\.$", handleRoomEntryUnlessLooking, { type = "regex" })

local moveDirections = { "n", "s", "e", "w", "ne", "nw", "se", "sw", "u", "d" }
for _, dir in ipairs(moveDirections) do
    createAlias("^" .. dir .. "$", function()
        -- A real move: this arrival must not be suppressed, even if a prior
        -- `look <dir>` returned no room and left the flag armed.
        taPackage.suppressRoomEntry = nil
        taPackage.pendingDirection = dir
        taPackage.prevRoom = taPackage.currentRoom
        taPackage.prevRoomId = taPackage.currentRoomId
        send(dir)
    end, { type = "regex" })
end

-- Resolve and print what room a `map-print-room-slug` probe is standing in,
-- from the captured name + observed exit-set: the definitive slug when exactly
-- one known room matches, every candidate when several do (with coords to help
-- you pick), or nothing-matches. The output is what you'd pass to `map-here`.
local function printRoomSlugCandidates(name, dirs)
    local exits = table.concat(dirs, ",")
    if not name then
        echo("[map] couldn't read the room name — try map-print-room-slug again")
        return
    end
    local matches = taPackage.db.roomsMatchingFingerprint(name, dirs)
    if #matches == 0 then
        echo("[map] no known room matches '" .. name .. "' with exits " .. exits
            .. " (new room? use map-area to start mapping here)")
    elseif #matches == 1 then
        echo("[map] this is " .. matches[1].slug .. "  ->  map-here " .. matches[1].slug)
    else
        local parts = {}
        for _, m in ipairs(matches) do
            local coord = (m.x ~= nil) and (" (" .. m.x .. "," .. m.y .. "," .. m.z .. ")") or ""
            parts[#parts + 1] = m.slug .. coord
        end
        echo("[map] " .. #matches .. " candidates for '" .. name .. "' [" .. exits .. "]: "
            .. table.concat(parts, ", "))
    end
end

-- `ex` prints the current room's exits ("Exits: n,e,sw."). While mapping, use
-- them for loop closure: if we provisionally minted this room but it's really an
-- already-known one (same name + exit-set), fold the provisional into it. Then
-- seed each exit as a known edge so the map shows it before it's walked.
createTrigger("^Exits: (.+)\\.$", function(matches)
    local dirs = {}
    for dir in matches[2]:gmatch("[^,%s]+") do dirs[#dirs + 1] = dir end

    -- A room probe: identify (don't map), then stop. `map-print-room-slug` just
    -- prints the candidates; a probe that carries an onResolve callback wants
    -- them instead (navigate-to checks them against a route's starting room).
    if taPackage.slugProbe then
        local probe = taPackage.slugProbe
        taPackage.slugProbe = nil
        if probe.onResolve then
            probe.onResolve(probe.name, dirs)
        else
            printRoomSlugCandidates(probe.name, dirs)
        end
        return
    end

    -- Nothing to do (and nothing to debug-log) unless we're actively mapping;
    -- this guard sits before the [mapdbg] echo so a plain `ex` during normal
    -- play stays quiet.
    if not taPackage.mapping or not taPackage.currentRoomId then return end
    echo("[mapdbg] Exits trigger: mapping=" .. tostring(taPackage.mapping)
        .. " currentRoomId=" .. tostring(taPackage.currentRoomId)
        .. " (" .. type(taPackage.currentRoomId) .. ")")

    if taPackage.currentRoomProvisional then
        echo("[mapdbg] reconcile: room=" .. tostring(taPackage.currentRoom)
            .. " id=" .. tostring(taPackage.currentRoomId)
            .. " dirs=" .. table.concat(dirs, ","))
        local match = taPackage.db.findRoomByFingerprint(
            taPackage.currentRoom, dirs, taPackage.currentRoomId, taPackage.coord)
        echo("[mapdbg] findRoomByFingerprint -> type=" .. type(match)
            .. " val=" .. tostring(match))
        -- Coordinates drift across this world's non-Euclidean loops, so when the
        -- coordinate match misses, trust the door we walked through instead: the
        -- room we re-entered is the same-name, same-exit-set room whose exit back
        -- the way we came is still unexplored. Topology over 30-year-old grid math.
        if type(match) ~= "number" and taPackage.currentEntryDir then
            local back = REVERSE_DIR[taPackage.currentEntryDir]
            match = taPackage.db.findLoopClosure(
                taPackage.currentRoom, dirs, taPackage.currentRoomId, back)
            echo("[mapdbg] findLoopClosure back=" .. tostring(back)
                .. " -> type=" .. type(match) .. " val=" .. tostring(match))
        end
        -- Guard on a real numeric id: never concatenate/merge a js_null or nil.
        if type(match) == "number" then
            taPackage.db.mergeRoomInto(taPackage.currentRoomId, match)
            taPackage.currentRoomId = match
            -- Re-anchor dead-reckoning to the room we closed onto: its stored
            -- coordinate is consistent with its already-mapped neighbours, while
            -- the drifted provisional's was not. Without this the drift compounds
            -- into another duplicate on the next move.
            local snapped = taPackage.db.roomCoord(match)
            if snapped then taPackage.coord = snapped end
            echo("[map] linked into #" .. tostring(match) .. " (" .. tostring(taPackage.currentRoom) .. ")")
        end
        taPackage.currentRoomProvisional = false
    end

    for _, dir in ipairs(dirs) do
        taPackage.db.recordKnownExit(taPackage.currentRoomId, dir)
    end

    -- Guide exploration: flag which listed exits still lead somewhere unmapped.
    -- An exit is "mapped" once it has a walked destination; otherwise it's a stub
    -- we've never stepped through (including the ones we just seeded above, whose
    -- to_id is NULL). This is a [map] line, not [mapdbg] -- it's a real aid.
    local unexplored, mapped = {}, {}
    for _, dir in ipairs(dirs) do
        if taPackage.db.exitDestination(taPackage.currentRoomId, dir) then
            mapped[#mapped + 1] = dir
        else
            unexplored[#unexplored + 1] = dir
        end
    end
    if #unexplored > 0 then
        echo("[map] unexplored exits: " .. table.concat(unexplored, ", ")
            .. (#mapped > 0 and ("  (mapped: " .. table.concat(mapped, ", ") .. ")") or ""))
    else
        echo("[map] all exits mapped: " .. table.concat(mapped, ", "))
    end

    -- Remember where this character is now (settled room id, after any merge),
    -- so `just report` can mark "you are here". Needs the logged-in name.
    if taPackage.character and taPackage.character.name then
        taPackage.db.setPlayerLocation(taPackage.character.name, taPackage.currentRoomId)
    end
end, { type = "regex" })

-- A rejected move: clear the pending direction so the next room line doesn't
-- record a phantom exit from the room we never actually left.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Passing through a locked door prints this just before the destination brief.
-- Stash the key/door; handleRoomEntry tags the crossed edge (and its reverse)
-- once it has linked them. Both are recorded lowercase to match room/dir slugs.
createTrigger("^Your (.+) key unlocks the (.+) door and allows you to pass through\\.$", function(matches)
    taPackage.pendingLock = { key = matches[2], door = matches[3] }
end, { type = "regex" })

-- A locked door we lack the key for turns us back, like a failed move. Record
-- the exit as a locked door (key unknown) so the map shows it, then clear the
-- pending direction so the reprinted room isn't mistaken for an arrival.
createTrigger("^The locked (.+) door prevents your exit in that direction\\.$", function(matches)
    if taPackage.mapping and taPackage.currentRoomId and taPackage.pendingDirection then
        taPackage.db.setExitLock(taPackage.currentRoomId, taPackage.pendingDirection, nil, matches[2])
    end
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Moving too quickly makes the character trip instead of moving — no room
-- change happens, but the game then reprints the current room. Clear the
-- pending direction so that reprint is treated as a re-scan of the room we're
-- still in, not an arrival through the exit we tried to take.
createTrigger("^In your haste, you trip and fall!$", function()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Trying to move while still resting is rejected outright — no room change. Like
-- the other rejected moves, clear the pending direction so a stale one can't be
-- dead-reckoned onto the next arrival (which would mint a phantom room in the
-- wrong direction). Separate from the arena-mode retry trigger elsewhere.
createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function()
    taPackage.pendingDirection = nil
end, { type = "regex" })

-- Begin mapping from the room you're standing in. Clear any stale anchor so the
-- brief that follows is treated as a fresh arrival (not a walked edge), then a
-- bare return prints that brief, which handleRoomEntry captures (and auto-probes
-- its exits). Shared by map-area; map-here anchors precisely instead.
local function startMappingHere()
    taPackage.mapping = true
    taPackage.pendingDirection = nil
    taPackage.prevRoomId = nil
    taPackage.currentRoomId = nil
    taPackage.coord = nil
    send("")
end

-- Start mapping a (usually fresh) area from where you stand: `map-area caves`
-- or `map-area caves The Caves`. Ensures the area, tags it current so newly
-- discovered rooms inherit it, and begins mapping here — no separate command to
-- turn mapping on. To resume in an already-mapped area, use `map-here <slug>`
-- (which anchors at a known room); `map-area` cold-starts by name, so it's for
-- fresh areas or a uniquely-named entry room.
createAlias("^map-area (.+)$", function(matches)
    local arg = matches[2]
    local slug, name = arg:match("^(%S+)%s+(.+)$")
    if not slug then slug, name = arg:match("^(%S+)$"), nil end
    local areaId = taPackage.db.ensureArea(slug, name)
    -- If we're already anchored on a room (e.g. we ran `map-here <prev-area
    -- room>`, walked across a frontier into this fresh area, and stopped on the
    -- entry room), that entry room was discovered under the *previous* area's id
    -- — the frontier lived on a room of that area. Re-file the room we're
    -- standing in into the new area so the seam ends up split cleanly between
    -- the two areas. Do this before startMappingHere clears currentRoomId, so we
    -- move the room the session already knows we're in rather than re-resolving
    -- an ambiguous name.
    local anchored = taPackage.currentRoomId
    if anchored then
        taPackage.db.setRoomArea(anchored, areaId)
        echo("[map] moved current room into " .. slug)
    end
    taPackage.currentAreaId = areaId
    echo("[map] mapping " .. slug .. " from here")
    startMappingHere()
end, { type = "regex" })

-- Resume mapping at a known room: `map-here cave-11`. Use this in an
-- already-mapped area — especially an ambiguously-named room (every cave is
-- "cave", so map-area's cold-start-by-name can't tell them apart). Turns
-- mapping on and anchors currentRoomId/coord/area from the named room's stored
-- row, without reprinting or re-resolving, so the next move dead-reckons from
-- the right place. Use the unique slug (shown in the report / `map-list-areas`).
createAlias("^map-here (.+)$", function(matches)
    local slug = matches[2]:match("^%s*(.-)%s*$")
    local room = taPackage.db.roomBySlug(slug)
    if not room then
        echo("[map] no room with slug: " .. slug)
        return
    end
    taPackage.mapping = true
    taPackage.currentAreaId = room.area_id
    taPackage.currentRoomId = room.id
    taPackage.currentRoom = room.name
    taPackage.currentRoomProvisional = false
    taPackage.prevRoomId = nil
    taPackage.prevRoom = nil
    taPackage.pendingDirection = nil
    if room.x ~= nil then
        taPackage.coord = { x = room.x, y = room.y, z = room.z }
    else
        taPackage.coord = nil
    end
    -- Stamp location now so the report's "you are here" marker is right the
    -- moment you anchor, not only after the first move (map-here sends no ex).
    if taPackage.character and taPackage.character.name then
        taPackage.db.setPlayerLocation(taPackage.character.name, room.id)
    end
    echo("[map] anchored at " .. slug .. " (#" .. tostring(room.id) .. ")"
        .. (taPackage.coord
            and (" coord=(" .. taPackage.coord.x .. "," .. taPackage.coord.y
                 .. "," .. taPackage.coord.z .. ")")
            or ""))
end, { type = "regex" })

-- Identify the room you're standing in without committing to it: re-reads the
-- room (bare return -> name, `ex` -> exit-set), consults the DB, and prints the
-- matching slug — or all candidates when name+exits are ambiguous — so you know
-- what to pass to `map-here`. Read-only; the capture happens in handleRoomEntry
-- and the Exits handler (both check taPackage.slugProbe).
createAlias("^map-print-room-slug$", function()
    taPackage.slugProbe = { name = nil }
    send("")
    send("ex")
end, { type = "regex" })

-- List every area slug we've mapped, one per line.
createAlias("^map-list-areas$", function()
    local areas = taPackage.db.listAreas()
    if #areas == 0 then
        echo("[map] no areas mapped yet")
        return
    end
    for _, a in ipairs(areas) do
        echo(a.slug)
    end
end, { type = "regex" })

-- Wipe one area so it can be re-walked from scratch (e.g. after a messy first
-- pass): `map-reset-area first-dungeon`. Leaves other areas intact and keeps the
-- area row, then forgets the mapping anchor so a now-deleted room can't be
-- re-linked from stale state — run `map-area <slug>` afterward to start re-mapping.
createAlias("^map-reset-area (.+)$", function(matches)
    local slug = matches[2]:match("^%s*(.-)%s*$")
    local areaId = taPackage.db.areaIdBySlug(slug)
    if not areaId then
        echo("[map] no such area: " .. slug)
        return
    end
    local removed = taPackage.db.resetArea(areaId)
    taPackage.currentRoomId = nil
    taPackage.prevRoomId = nil
    taPackage.pendingDirection = nil
    taPackage.coord = nil
    echo("[map] reset area " .. slug .. " (" .. tostring(removed)
        .. " rooms removed). Run map-area " .. slug .. " to re-map it.")
end, { type = "regex" })

-- Attach a freeform note to a room: `map-add-note say komi here to open the
-- south door`. Two forms, disambiguated by the first token:
--   map-add-note <text>          -> note goes on the room you're standing in
--   map-add-note <slug> <text>   -> note goes on the named room (any room)
-- The by-slug form exists because a note often describes a *remote* effect --
-- a lever here disables a trap 20 rooms away -- so you want to annotate a room
-- you're not standing in. It also works when mapping is off (currentRoomId is
-- only trusted while mapping). The current-room form falls through when the
-- first word isn't a known room slug (real slugs are hyphenated, e.g.
-- `first-dungeon-12`, so a note starting with an ordinary word won't collide).
createAlias("^map-add-note (.+)$", function(matches)
    local rest = matches[2]:match("^%s*(.-)%s*$")
    if rest == "" then
        echo("[map] usage: map-add-note <text>   or   map-add-note <room-slug> <text>")
        return
    end
    local firstTok, remainder = rest:match("^(%S+)%s+(.+)$")
    local targetId, targetSlug, noteText
    if firstTok then
        local row = taPackage.db.roomBySlug(firstTok)
        if row then
            targetId, targetSlug, noteText = row.id, firstTok, remainder
        end
    end
    if not targetId then
        targetId = taPackage.mapping and taPackage.currentRoomId or nil
        noteText = rest
        if not targetId then
            echo("[map] not anchored on a room -- map first, or target one by slug:"
                .. " map-add-note <room-slug> " .. rest)
            return
        end
    end
    local id = taPackage.db.addRoomNote(targetId, noteText)
    echo("[map] note #" .. tostring(id) .. " added to " .. (targetSlug or "here") .. ": " .. noteText)
end, { type = "regex" })

-- List the notes on a room, with their ids (so you can prune with map-del-note).
-- Bare form lists the current room; `map-notes <slug>` lists a named room.
local function echoRoomNotes(roomId, label)
    local notes = taPackage.db.roomNotes(roomId)
    if #notes == 0 then
        echo("[map] no notes on " .. label)
        return
    end
    echo("[map] notes on " .. label .. ":")
    for _, n in ipairs(notes) do
        echo("  #" .. tostring(n.id) .. "  " .. n.note)
    end
end
createAlias("^map-notes$", function()
    local roomId = taPackage.mapping and taPackage.currentRoomId or nil
    if not roomId then
        echo("[map] not anchored on a room -- list one by slug: map-notes <room-slug>")
        return
    end
    echoRoomNotes(roomId, "here")
end, { type = "regex" })
createAlias("^map-notes (.+)$", function(matches)
    local slug = matches[2]:match("^%s*(.-)%s*$")
    local row = taPackage.db.roomBySlug(slug)
    if not row then
        echo("[map] no such room: " .. slug)
        return
    end
    echoRoomNotes(row.id, slug)
end, { type = "regex" })

-- Prune one note by its id (from map-notes): `map-del-note 7`.
createAlias("^map-del-note (\\d+)$", function(matches)
    local id = tonumber(matches[2])
    local removed = taPackage.db.deleteRoomNote(id)
    if removed and removed > 0 then
        echo("[map] deleted note #" .. tostring(id))
    else
        echo("[map] no note #" .. tostring(id))
    end
end, { type = "regex" })

-- Mapping mode. Off by default; while on, room lines are recorded, each arrival
-- auto-probes exits with `ex`, and provisional rooms are merged into known ones
-- by fingerprint. Turning it off leaves the graph untouched during normal play.
-- Mapping is turned ON by map-area (fresh area) or map-here (resume at a known
-- room); map-off stops it.
local function stopMapping()
    taPackage.mapping = false
end

createAlias("^map-off$", function()
    stopMapping()
    echo("[map] mapping OFF")
end, { type = "regex" })

-- Arm a one-shot ntfy watcher. The first server line containing <phrase> pushes
-- a single notification, then the trigger removes itself so it never fires
-- again. A literal trigger matches <phrase> anywhere in the line. When
-- andExit is set, we also leave the game afterwards.
local function armPhraseWatcher(aliasName, arg, andExit)
    -- Accept the phrase with or without surrounding double quotes.
    local phrase = arg:match('^"(.*)"$') or arg
    local triggerId
    triggerId = createTrigger(phrase, function()
        removeTrigger(triggerId)
        -- Name the character rather than saying "I": several characters can be
        -- watching at once, so the push has to say which one tripped it.
        sendNtfy(aliasName, "Heads up- " .. (taPackage.character.name or "?")
            .. " just saw: " .. phrase)
        echo("[watch] notified: " .. phrase)
        if andExit then
            echo("[watch] leaving the game (x).")
            taPackage.exitGameWithRetry()
        end
    end)
    echo("[watch] will message you once when I see: " .. phrase
        .. (andExit and " (then leaving the game)" or ""))
end

-- message-me-when-you-see "<phrase>" — notify and stay put.
createAlias("^message-me-when-you-see (.+)$", function(matches)
    armPhraseWatcher("message-me-when-you-see", matches[2], false)
end, { type = "regex" })

-- message-me-and-exit-when-you-see "<phrase>" — notify, then get out of the
-- game with "x" so the character is safe from damage by the time the push
-- reaches your phone. Notify *first*: the exit retry loop can take seconds when
-- we're rest-blocked, and the whole point is to hear about the phrase.
createAlias("^message-me-and-exit-when-you-see (.+)$", function(matches)
    armPhraseWatcher("message-me-and-exit-when-you-see", matches[2], true)
end, { type = "regex" })

-- wait-for-potions-to-wear-off-and-exit — the one phrase we wait on often
-- enough to deserve its own name: the line the game prints when a potion runs
-- out. Same behaviour as message-me-and-exit-when-you-see with that phrase,
-- just without having to remember the wording.
createAlias("^wait-for-potions-to-wear-off-and-exit$", function()
    armPhraseWatcher("wait-for-potions-to-wear-off-and-exit",
        "An odd tingling sensation washes over", true)
end, { type = "regex" })

-- train-and-exit-once-potions-wear-off — wait out the stat potions in the guild
-- hall, bank the level the instant they lapse, then leave the game.
--
-- What wait-for-potions-to-wear-off-and-exit leaves you holding: the hall refuses
-- a potion-tainted character ("Your mind and body must be whole and untainted
-- before you may train."), a rowan/hyssop potion takes 10-20 minutes of real time
-- to wear off, and being pushed the wear-off line still means logging back in to
-- buy the training. Waiting *in* the game isn't free either — hunger and thirst
-- keep ticking damage at an idle character — so this buys the training the moment
-- it becomes possible and leaves the game as soon as the hall has answered.
--
-- Both potions are normally up and their wear-off lines are identical, so the
-- first tingle can still leave us tainted. Rather than count them (the arena
-- loop's arenaPotionsActive; a hand-driven character has no reliable count) let
-- the hall arbitrate: on the taint refusal, go back to waiting for the next
-- tingle. The heads-up push is the existing "Leveled Up!" one on the "rigorous
-- ... training session" trigger further down, which this watch enables outside an
-- arena run.
local TRAIN_WATCH_ROOM = "guild hall"
-- How long to wait for the room brief our bare return asks for. It comes straight
-- back; this only has to outlast a hiccup.
local TRAIN_WATCH_CONFIRM_MS = 5000

-- Tear down every trigger the watch armed. Shared by its own exit paths and by
-- stop-train-and-exit / stop-all-scripts, so a stop can never leave something
-- behind still listening for a tingle we no longer care about.
local function stopTrainWatch()
    local watch = taPackage.trainWatch
    if not watch then return false end
    for _, id in ipairs(watch.triggers) do removeTrigger(id) end
    taPackage.trainWatch = nil
    return true
end

-- The hall has answered (either way) — nothing is left to wait for, so stop
-- taking hunger/thirst damage for no reason and get out.
local function trainWatchFinish(reason)
    stopTrainWatch()
    echo("[train] " .. reason .. " — leaving the game (x).")
    taPackage.exitGameWithRetry()
end

-- Arm the four lines this watch lives on. Literal (non-regex) triggers: each
-- phrase is a distinctive fragment of a longer message, and the success and
-- not-ready replies both wrap onto a second line, so matching a fragment
-- anywhere in the line is exactly what we want.
local function trainWatchArm(watch)
    local triggers = watch.triggers
    -- Tells the confirmation timeout below that a brief did arrive in time.
    watch.armed = true

    -- A potion lapsed. Ask the hall to train; its reply decides whether we are
    -- done or still tainted. Further tingles are ignored until it answers, so two
    -- potions expiring in the same breath can't buy training twice.
    triggers[#triggers + 1] = createTrigger("An odd tingling sensation washes over", function()
        if taPackage.trainWatch ~= watch or watch.awaitingVerdict then return end
        watch.awaitingVerdict = true
        echo("[train] A potion wore off — buying training.")
        send("buy training")
    end)

    -- Trained. Banking the level, charging the fee and pushing the "Leveled Up!"
    -- notification all belong to the training-success trigger further down (it
    -- runs first, being armed at load time); all that is left here is the exit.
    triggers[#triggers + 1] = createTrigger("After a rigorous mental and physical training session", function()
        if taPackage.trainWatch ~= watch then return end
        trainWatchFinish("Trained")
    end)

    -- Refused: the other potion is still up. Back to waiting for the next tingle.
    triggers[#triggers + 1] = createTrigger("whole and untainted before you may train", function()
        if taPackage.trainWatch ~= watch then return end
        watch.awaitingVerdict = false
        echo("[train] Still potion-tainted — waiting for the next potion to wear off.")
    end)

    -- No level was owed after all (the XP threshold we thought we had crossed
    -- wasn't). Nothing will ever come of waiting here, so leave.
    triggers[#triggers + 1] = createTrigger("You are not ready for any further training", function()
        if taPackage.trainWatch ~= watch then return end
        trainWatchFinish("No training owed")
    end)

    echo("[train] Waiting in the " .. TRAIN_WATCH_ROOM
        .. " for the potions to wear off; will buy training, then leave the game (x).")
end

createAlias("^train-and-exit-once-potions-wear-off$", function()
    if taPackage.trainWatch then
        echo("[train] Already waiting to train (stop-train-and-exit cancels it).")
        return
    end
    -- Claim the slot before the room check so a double-typed alias can't arm two
    -- watches during the confirmation window.
    local watch = { triggers = {} }
    taPackage.trainWatch = watch
    -- Don't commit to a 20-minute wait in the wrong room — confirm off a brief we
    -- asked for rather than any cached room, since the mapper's currentRoom is only
    -- maintained while mapping is on and this has to work in ordinary play. A bare
    -- return prints the room brief (a plain `look` prints the description instead).
    local roomTrigger
    roomTrigger = createTrigger("^You're in (.+)\\.$", function(matches)
        if taPackage.trainWatch ~= watch then return end
        -- One brief answers the question; drop the trigger so the long wait that
        -- follows isn't matching every room line the game prints.
        removeTrigger(roomTrigger)
        watch.triggers = {}
        local room = matches[2]
        if not room:find(TRAIN_WATCH_ROOM, 1, true) then
            taPackage.trainWatch = nil
            echo("[train] Not in a " .. TRAIN_WATCH_ROOM .. " (room: " .. room
                .. "). Walk into one first, then run train-and-exit-once-potions-wear-off.")
            return
        end
        trainWatchArm(watch)
    end, { type = "regex" })
    watch.triggers[1] = roomTrigger
    send("")
    -- No brief came back (not in the game yet, or the connection is wedged). Better
    -- to say so than to sit armed with no idea where we are standing.
    createTimer(TRAIN_WATCH_CONFIRM_MS, function()
        if taPackage.trainWatch ~= watch or watch.armed then return end
        stopTrainWatch()
        echo("[train] No room brief came back — not arming. Try again in the "
            .. TRAIN_WATCH_ROOM .. ".")
    end, { repeating = false })
end, { type = "regex" })

createAlias("^stop-train-and-exit$", function()
    if stopTrainWatch() then
        echo("[train] Stopped waiting to train.")
    else
        echo("[train] Not waiting to train.")
    end
end, { type = "regex" })

-- =========================================================================
-- Combat triggers
-- =========================================================================

createTrigger("^Your attack hit the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    taPackage.lastAttackTarget = monster
    outgoingBadge("HIT " .. damage)
    taPackage.db.recordPlayerAttack(
        taPackage.character.weapon or "weapon", monster, "hit", damage
    )
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
    local monster = taPackage.lastAttackTarget or "unknown"
    taPackage.db.recordPlayerAttack(
        taPackage.character.weapon or "weapon", monster, "miss", nil
    )
end, { type = "regex" })

createTrigger("^The (.+) dodged your attack!$", function(matches)
    local monster = matches[2]
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerAttack(
        taPackage.character.weapon or "weapon", monster, "dodge", nil
    )
end, { type = "regex" })

-- Forward declaration: the incoming-damage handlers below need to re-evaluate
-- the flee decision the moment HP drops, but checkFleeArena is defined much
-- later (alongside the other arena-state helpers). Declaring it here and
-- assigning to it later (see `function checkFleeArena()`, no `local`) lets the
-- damage triggers close over the eventual definition.
local checkFleeArena

-- All incoming-damage lines do the same three things: subtract the hit from our
-- vitality, badge "TOOK N", and record the attack. The generic "attacked you ...
-- for N damage!" phrasing covers ordinary swings, but many enemies deal damage
-- through special verbs that never say "attacked you" — a stone giant's boulder
-- (seen for 52), a cyclops's throw (22), a stygian dragon's bite (39) or tail
-- lash (35), a minotaur chieftain's charge (42), a caster's "discharged" spell.
-- Each needs its own phrasing but the handler is identical, so drive them all
-- from one list. Only the "you" variants carry a number; when a special lands on
-- another group member the game prints no damage ("hurled a boulder at
-- Pelayo!"), so there is nothing to subtract from our own vitality.
local incomingDamagePatterns = {
    "^The (.+) attacked you .+ for (\\d+) damage!$",
    "^The (.+) hurled a boulder at you for (\\d+) damage!$",
    "^The (.+) picks up and hurls you for (\\d+) damage!$",
    "^The (.+) breathed flames at you for (\\d+) damage!$",
    "^The (.+) discharged .+ at you for (\\d+) damage!$",
    "^The (.+) viciously bit you for (\\d+) damage!$",
    "^The (.+) lashed out with its tail for (\\d+) damage!$",
    "^The (.+) charged you for (\\d+) damage!$",
    "^The (.+) expelled a ball of fire at you for (\\d+) damage!$",
    "^The (.+) exhaled a blast of flame at you for (\\d+) damage!$",
}

for _, pattern in ipairs(incomingDamagePatterns) do
    createTrigger(pattern, function(matches)
        local monster = matches[2]
        local damage = tonumber(matches[3])
        local current, max = getVitality()
        if current then
            setVitality(current - damage, max)
        end
        incomingBadge("TOOK " .. damage)
        taPackage.db.recordMonsterAttack(monster, "hit", damage)
        -- React to the damage itself, not just to our own swings. Flee was
        -- otherwise only checked when one of our attacks resolved, so a burst of
        -- incoming damage during a gap in our attack cycle (e.g. a swing bounced
        -- on "physically exhausted" and is waiting out its 30s retry) could push
        -- us well below the flee threshold yet sit there taking hits until the
        -- next swing finally landed.
        checkFleeArena()
    end, { type = "regex" })
end

createTrigger("^The (.+) attacked you, but .+ glanced off your armor!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "glanced", nil)
end, { type = "regex" })

createTrigger("^The (.+)'s? .+ misses? you!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "miss", nil)
end, { type = "regex" })

createTrigger("^You barely dodge the (.+)'s attack!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "dodge", nil)
end, { type = "regex" })

-- Traps hurt us without ever printing a damage number, so we can't subtract the
-- hit directly. Stash our current HP and ask the server for a fresh status
-- ("st"); the Vitality trigger above recovers the loss and badges "TRAP <n>".
-- `trapType` also tags the current room as trapped (while mapping) so the map
-- remembers where the hazard is. Point additional trap-message triggers at
-- handleTrap as we discover them, passing their trap type.
local function handleTrap(trapType)
    if trapType and taPackage.mapping and taPackage.currentRoomId then
        taPackage.db.setRoomTrap(taPackage.currentRoomId, trapType)
    end
    taPackage.trapHpBefore = getVitality()
    send("st")
end

createTrigger("^A spiked trap catches your foot and pain shoots up your leg!$",
    function() handleTrap("spiked trap") end, { type = "regex" })

createTrigger("^Several crossbow bolts fire from holes in the walls, striking you!$",
    function() handleTrap("crossbow trap") end, { type = "regex" })

createTrigger("^Several large stones fall on you from above!$",
    function() handleTrap("falling rocks") end, { type = "regex" })

createTrigger("^A huge stone block slams down on you from above!$",
    function() handleTrap("falling block") end, { type = "regex" })

createTrigger("^A scything blade slices into your stomach!$",
    function() handleTrap("scything blade") end, { type = "regex" })

createTrigger("^A ball of flame explodes from an opening in the wall and engulfs you!$",
    function() handleTrap("flame trap") end, { type = "regex" })

-- A trap door drops us to the room directly below without a directional move.
-- Tag the room we fell from with the trap, and — crucially — prime a downward
-- move so the destination brief is dead-reckoned as z-1 (right floor, directly
-- below) and linked with a d/u edge. Without this the fall cold-starts the pit
-- at the origin (0,0,0), stranding it and everything after it on the wrong
-- floor. It deals no HP we track here.
createTrigger("^You just fell through a trap door in the floor!$", function()
    if taPackage.mapping and taPackage.currentRoomId then
        taPackage.db.setRoomTrap(taPackage.currentRoomId, "trap door")
        taPackage.prevRoom = taPackage.currentRoom
        taPackage.prevRoomId = taPackage.currentRoomId
        taPackage.pendingDirection = "d"
    end
end, { type = "regex" })

-- Advanced monsters cast area-effect spells that hit everyone nearby without
-- printing a damage number — just like a trap. Use the identical trick: stash
-- our HP, ask for a fresh status ("st"), and let the Vitality trigger above
-- recover the loss and badge "AOE <n>". The cast message word-wraps across two
-- physical lines (".. in the" / "area!"), so we match only the stable first
-- line, up through "at hostile people", and never anchor the end.
-- Point additional area-effect triggers at handleAreaEffect as we discover them.
local function handleAreaEffect()
    taPackage.aoeHpBefore = getVitality()
    send("st")
end

createTrigger("^The .+ just discharged .+ at hostile people",
    handleAreaEffect, { type = "regex" })

-- =========================================================================
-- Loot and kill triggers
-- =========================================================================

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    local name = matches[2]
    clearPresence(name)
    taPackage.lastKilledMonster = name
    taPackage.pendingLootCheck = true
end, { type = "regex" })

-- An area-of-effect spell hits every hostile monster at once, e.g. "The warlock
-- just discharged a storm of ice shards at hostile monsters in the area!". The
-- game word-wraps that onto two lines, breaking after "in the", so we match the
-- first line only. The AOE signature is "at hostile monsters in the" — do NOT
-- key on "discharged" alone: the common single-target cast ("... discharged a
-- small shard of ice at the huge rat!") uses the same verb. An AOE resolves its
-- damage across the whole room at once, so we `st` to read the resulting XP.
createTrigger("^.+ just discharged .+ at hostile monsters in the", function()
    send("st")
end, { type = "regex" })

-- =========================================================================
-- Service triggers
-- =========================================================================

createTrigger("^The barmaid brings you a drink for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    setGold((getGold() or 0) - cost)
    taPackage.db.recordService("drink", "tavern", cost)
end, { type = "regex" })

createTrigger("^The barmaid brings you a meal for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    setGold((getGold() or 0) - cost)
    taPackage.db.recordService("meal", "tavern", cost)
end, { type = "regex" })

-- =========================================================================
-- Stat change tracking
-- =========================================================================

createTrigger("^Level:\\s+(\\d+)$", function(matches)
    local newLevel = tonumber(matches[2])
    local oldLevel = taPackage.character.level
    if oldLevel and oldLevel ~= newLevel then
        taPackage.db.recordStatChange("Level", oldLevel, newLevel)
    end
    setLevel(newLevel)
end, { type = "regex" })

-- Milliseconds since the epoch. baud supplies nowMs precisely because Lua
-- can't: os.time only resolves to the second, which can't tell 1.0s from 1.9s,
-- and os.clock measures CPU rather than elapsed time. Fall back to whole
-- seconds if the script is reloaded into a baud too old to have it -- the
-- timings go coarse, but nothing breaks.
-- Defined up here rather than beside the arena timings that consume it because
-- the status bar (below) reckons the age of its XP marker against it too.
local function nowMillis()
    if nowMs then return nowMs() end
    return os.time() * 1000
end

-- Published for ta_nav.lua, as trimLine above.
taPackage.nowMillis = nowMillis

-- =========================================================================
-- Status bar
-- =========================================================================

local function vitalityColor(current, max)
    if not current or not max or max == 0 then return "white" end
    local pct = current / max
    if pct >= 0.66 then
        return "green"
    elseif pct >= 0.33 then
        return "yellow"
    else
        return "red"
    end
end

-- Format an integer with thousands separators (e.g. 1234567 -> "1,234,567").
-- Handles a leading minus sign and leaves non-numbers untouched.
local function commafy(value)
    if value == nil then return nil end
    local s = tostring(value)
    local sign, digits = s:match("^(%-?)(%d+)$")
    if not digits then return s end
    local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    formatted = formatted:gsub("^,", "")
    return sign .. formatted
end

-- How long the XP-change marker stays on the bar after the XP figure moves.
local XP_CHANGE_VISIBLE_MS = 3000
-- Orange: warm enough to pull the eye off the cyan XP figure it hangs beside,
-- and not already spoken for (red means untrained level, yellow means gold).
local XP_CHANGE_FG = "#ff8700"

-- XP still to go before the next level: the figure the bar shows. nil once
-- there is no next level to count down to. Global rather than local because the
-- main chunk is at Lua's 200-local ceiling.
function xpRemaining(xp, class)
    local nextLevelXp = xp and getXpForNextLevel(xp, class)
    if not nextLevelXp then return nil end
    return nextLevelXp - xp
end

-- The signed move in that figure, e.g. "-14,000" after gaining 14,000 XP —
-- nil once the marker has aged out, or when we can't tell (unknown class, at
-- max level, or a change that leaves the figure where it was). Reported as a
-- delta of the *displayed* number rather than of raw XP, so it always agrees
-- with the value it sits next to: training past a threshold pushes the count
-- back up, and the marker says "+" to match.
function xpChangeText(xp, class)
    local change = taPackage.xpChange
    if not change then return nil end
    if nowMillis() - change.at >= XP_CHANGE_VISIBLE_MS then return nil end
    local before = xpRemaining(change.from, class)
    local after = xpRemaining(xp, class)
    if not (before and after) then return nil end
    local delta = after - before
    if delta == 0 then return nil end
    return (delta > 0 and "+" or "") .. commafy(delta)
end

local function status()
    local charStatus = getCharacterStatus() or "?"
    local vitalityCurrent, vitalityMax = getVitality()
    local manaCurrent, manaMax = getMana()
    local xp = getExperience()
    local nextLevelXp = xp and getXpForNextLevel(xp, getClass())
    local gold = getGold() and commafy(getGold()) or "?"

    local charName = taPackage.character.name
    local charClass = getClass()
    local nameText = charName and charClass and (charName .. " [" .. charClass .. "]")
        or charName
        or "?"
    -- Followers show only name + class; the leader gets a bare "Leader" tag.
    -- We deliberately omit who we follow and the follower count to keep the bar
    -- compact. Leader and follower are mutually exclusive: if we're following
    -- someone we're a member, not a leader, so never show "Leader" then. This
    -- also keeps a stale followedBy (it persists across reloadScript) from
    -- mislabelling a follower as a leader.
    if not taPackage.followTarget
        and taPackage.followedBy and #taPackage.followedBy > 0 then
        nameText = nameText .. " Leader"
    end

    local segments = {
        { text = nameText, fg = "white" },
        { text = "HP:" },
        {
            text = vitalityCurrent and commafy(vitalityCurrent) or "?",
            fg = vitalityColor(vitalityCurrent, vitalityMax)
        },
        { text = vitalityMax and ("/ " .. commafy(vitalityMax)) or "", fg = "white" },
    }
    if manaMax and manaMax > 0 then
        table.insert(segments, { text = "MP:", fg = "green" })
        table.insert(segments, { text = manaCurrent and commafy(manaCurrent) or "?", fg = "cyan" })
        table.insert(segments, { text = "/ " .. commafy(manaMax), fg = "cyan" })
    end
    -- Only ever show the XP remaining to the next level as "(<xp remaining>)".
    -- "?" when XP is unknown, "(max)" at the top level where there's no next.
    local remainingText
    if not xp then
        remainingText = "?"
    elseif nextLevelXp then
        remainingText = "(" .. commafy(nextLevelXp - xp) .. ")"
    else
        remainingText = "(max)"
    end
    local tail = {
        { text = "XP:" },
        { text = remainingText, fg = "cyan" },
    }
    -- A red "^" hangs off the XP figure when we have earned a level but not yet
    -- trained for it. `glue` renders it flush ("(184,893)^") so it reads as a
    -- mark on the XP rather than a field of its own.
    if hasUntrainedLevel() then
        table.insert(tail, { text = "^", fg = "red", glue = true })
    end
    -- A field of its own rather than glued: it is a separate, temporary reading
    -- ("XP: (471,484) -14,000"), not a mark on the figure like the "^".
    local changeText = xpChangeText(xp, charClass)
    if changeText then
        table.insert(tail, { text = changeText, fg = XP_CHANGE_FG, bold = true })
    end
    local tailRest = {
        { text = "Status:" },
        { text = charStatus, fg = (charStatus == "Thirsty" or charStatus == "Hungry") and "red" or "white" },
        { text = "Gold:" },
        { text = gold,       fg = "yellow" },
    }
    for _, seg in ipairs(tail) do table.insert(segments, seg) end
    for _, seg in ipairs(tailRest) do table.insert(segments, seg) end
    return segments
end

setStatus(status)

-- Called from setExperience, the one chokepoint every XP reading flows through.
-- Only a real move counts: the arena polls `status` constantly, and seeding the
-- marker on an unchanged reading (or on the first reading of the session, where
-- there is nothing to compare against) would leave it flickering for no reason.
function recordXpChange(previous, current)
    if previous == nil or current == nil or previous == current then return end
    taPackage.xpChange = { from = previous, at = nowMillis() }
    -- baud only re-evaluates the status function when the server sends data, so
    -- three quiet seconds would leave an expired marker stuck on the bar. Handing
    -- setStatus the same function again forces a fresh evaluation, which is what
    -- makes the marker ephemeral rather than sticky. Armed a beat past the window
    -- so the evaluation lands after it has closed, never on the boundary.
    createTimer(XP_CHANGE_VISIBLE_MS + 100, function()
        setStatus(status)
    end, { repeating = false })
end

-- =========================================================================
-- Re-roll for good stats
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


-- =========================================================================
-- Ring gong and fight in arena
-- =========================================================================

local function arenaSend(cmd)
    taPackage.arenaLastCmd = cmd
    taPackage.arenaRetryGeneration = (taPackage.arenaRetryGeneration or 0) + 1
    send(cmd)
end

local function arenaDebugEcho(label)
    if taPackage.arenaDebug then
        echo("[T] " .. os.date("%H:%M:%S") .. " " .. label)
    end
end

-- The game takes a SINGLE word as a target and prefix-matches it, so a
-- two-word monster has to be addressed by its first word only: "female troll"
-- is targeted as "female". Passing the whole name is not merely ignored — the
-- command stops being recognised at all and the line is broadcast to the room as
-- speech instead ("-- Message sent --", and everyone else reads "From Kerhak:
-- look female troll"). That is noise at best, and in team mode it spams the
-- whole party, so every command that names the monster goes through here.
local function arenaTarget(name)
    return name:match("^(%S+)")
end

-- Melee: everyone swings each round with a physical attack, casters included.
-- Only swing while actually fighting. Once flee triggers (state "fleeing"),
-- every physical action resets the game's movement cooldown, so a stray swing
-- — e.g. a stale exhaustion-retry timer firing 30s late — keeps the escape
-- move from ever landing. Gating here makes those retries no-op until we're
-- back in combat, so the queued `w` gets a clean window. (See the death in
-- logs/session-2026-06-21T11-51-45.log, where post-flee swings stalled the run.)
local function arenaAttack()
    if taPackage.arenaState ~= "fighting" then return end
    local name = taPackage.arenaMonster
    if name then
        if taPackage.arenaAttackPending then return end
        taPackage.arenaAttackPending = true
        local target = arenaTarget(name)
        arenaDebugEcho("attack-sent")
        arenaSend("a " .. target)
    end
end

-- Casters take a second action each round on a separate exhaustion clock: a
-- Sorceror blasts the monster with toduza while still meleeing every round.
local function arenaCast()
    -- Like arenaAttack, casting is a combat action that resets the move clock;
    -- once we're fleeing it must cease until we're fighting again.
    if taPackage.arenaState ~= "fighting" then return end
    if getClass() ~= "Sorceror" then return end
    local name = taPackage.arenaMonster
    if not name then return end
    if taPackage.arenaCastPending then return end
    taPackage.arenaCastPending = true
    local target = arenaTarget(name)
    arenaDebugEcho("cast-sent")
    arenaSend("cast toduza " .. target)
end

-- Ringing the gong is itself a physical action. Right after a melee kill the
-- physical clock is spent, so the immediate ring is rejected with "still
-- physically exhausted" — the same retry treatment the swing gets keeps the
-- loop alive. The pending guard means a stale retry timer can't double-ring.
local ARENA_RING_RETRY_MS = 3000

-- Floor, not a reckoning. The gong recovers against the last accepted SWING —
-- logs/session-pelayo-2026-08-02T14-12-42.log shows all nine acceptances landing
-- 19.0-25.5s after one, while the time since the previous ring scattered over
-- 31-79s and predicted nothing. But unlike melee that window has no constant in
-- it: one ring was accepted at 18.6s while others were still refused at 22.2s,
-- and the spread does not track the size of the burst that ended the fight
-- (r=0.22). So there is nothing here to dead-reckon.
--
-- What the data does support is a hard floor. No ring has ever been accepted
-- below 19.0s, yet the pump used to start ringing the instant the monster died
-- and retry every 3s — 56 of that session's 67 rejections came before 18s, about
-- seven guaranteed-dead commands per kill. Holding until 18s removes them
-- without risking a late summon, and the existing 3s pump then covers the
-- variable 19-25.5s window in one to three probes, the same shape as the melee
-- tail poll.
local ARENA_RING_FLOOR_MS = 18000

-- Recovering from "still physically exhausted" is dead reckoning, not a search.
--
-- The game grants a burst of swings and then refuses every physical action until
-- a fixed wall-clock timer runs out. How many swings is a property of the
-- character (class, agility, level — see docs/shrine/AGILITY.md); how long the
-- recovery takes appears to be the same for everyone. So the burst size is
-- deliberately NOT modelled here: we swing until the game says "exhausted",
-- which uses whatever the character currently has and keeps working when a
-- level-up grants another attack. The rejected swing that ends a burst is not
-- waste — it is the signal that starts this clock.
--
-- Only the recovery is predicted, and the wait is timed from the last ACCEPTED
-- swing rather than from the rejection: the server's clock started when that
-- swing resolved, and the rejection reaches us a round-trip later, so timing
-- from the rejection would start us late on every single cycle.
--
-- This replaced a blind 2s poll of the whole window, which spent ~69% of every
-- attack command it sent on rejections (744 sent / ~228 resolved in
-- logs/session-pelayo-2026-08-01T13-06-47.log — median 10 consecutive
-- rejections per cooldown, max 20). The blind poll had in turn replaced a flat
-- 30s retry, because 30s was fine solo — the monster only ever attacks us, so
-- some combat line always re-drove the loop — but not in team mode, where a
-- monster busy with a teammate prints lines that name THEM ("...misses
-- Kerhak!"), so none of our re-arm triggers fire and the fallback became the
-- actual cadence. That cost Kerhak a 30s idle mid-fight while Teekywiki solo'd
-- a stone giant (18:59:05 -> 18:59:35 in
-- logs/session-kerhak-team-fight-2026-07-25T18-58-34.log). Dead reckoning is
-- immune to that: it depends on no incoming line at all.
--
-- Fitted to logs/session-pelayo-2026-08-02T09-47-30.log, where the reckoned
-- retry landed at 28s on all eight cooldowns and the tail poll then measured the
-- real recovery at 30/32/33/35/35/36/38s (median 35). The first estimate of 30s
-- was 5s short, so every cycle paid 2-5 tail polls to cover the gap.
--
-- Aiming at 33s rather than the 35s median is the deliberate trade: firing early
-- costs one rejected command and the tail poll picks it up, firing late wastes
-- damage outright. Against that observed spread, 33s means most cooldowns are
-- caught on the first or second probe, and the two fastest (30s, 32s) start
-- 3s and 1s late — under 2% of a ~35s cycle.
--
-- n=8, so treat this as a fit rather than a constant of the game. If a later log
-- shows the tail poll consistently firing several times, it is short again.
local ARENA_PHYSICAL_COOLDOWN_MS = 35000
local ARENA_COOLDOWN_MARGIN_MS = 2000

-- Tail poll. Once the estimate says we should be recovered (or we have no recent
-- swing to reckon from — a stale timestamp makes the computed wait negative and
-- lands here), fall back to asking. Only the last seconds of the window get
-- polled, so this costs about one extra command per cooldown rather than ten.
local ARENA_EXHAUSTED_RETRY_MS = 2000

-- Milliseconds since a recorded stamp, or nil if we never recorded one. Used
-- only by the tracing below, where "we have no idea" and "it was 0ms ago" have
-- to stay distinguishable.
local function arenaSince(stamp)
    if not stamp then return nil end
    return nowMillis() - stamp
end

local function arenaSinceLabel(stamp)
    local since = arenaSince(stamp)
    return since and (since .. "ms") or "never"
end

-- Ringing is measured, not yet reckoned. The melee cooldown turned out to be a
-- fixed timer that could be dead-reckoned from the last accepted swing, and the
-- gong is plainly on some cooldown too — 55 of the 64 rings sent in
-- logs/session-pelayo-2026-08-02T11-15-31.log bounced off "still physically
-- exhausted". But the two do NOT share a clock: in
-- logs/session-pelayo-2026-08-02T09-47-30.log a ring was accepted ~19-22s after
-- a killing blow that melee was still refusing at 35s. So this traces the gong's
-- own timings — every send, every rejection, and every acceptance, each carrying
-- how long it had been since the last accepted swing and the last accepted ring
-- — and nothing here changes behaviour until those numbers say what to reckon.
local function arenaRing()
    if taPackage.arenaRingPending then return end
    -- Below the floor the gong cannot possibly answer, so don't ask. The pump
    -- re-scans on its own timer either way (arenaScanRoom arms it before any of
    -- this runs), so declining here just skips the send and the next tick tries
    -- again — it cannot wedge the summon loop. Worst case we hold for the length
    -- of the floor, because arenaLastSwingAt only moves when a swing is accepted
    -- and we are not swinging while we ring.
    --
    -- In team mode a held tick has already counted itself in arenaRingAttempts,
    -- so the tick that finally rings takes the staggered path rather than the
    -- fast one. That is a sub-second delay on a ~18s wait, and the stagger is
    -- what stops two characters double-summoning, so it is the safe direction.
    local sinceSwing = arenaSince(taPackage.arenaLastSwingAt)
    if sinceSwing and sinceSwing < ARENA_RING_FLOOR_MS then
        arenaDebugEcho("ring-held  since-swing " .. sinceSwing .. "ms")
        return
    end
    taPackage.arenaRingPending = true
    arenaDebugEcho("ring-sent  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
        .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
    arenaSend("ring gong")
end

-- =========================================================================
-- Team mode: one monster, several characters
-- =========================================================================
-- Several characters share an arena and must summon exactly ONE monster between
-- them. Four clients that all see an empty room and all ring at once produce
-- four monsters, which is how a party gets killed.
--
-- The coordination runs entirely through the game, because the game already
-- provides both halves of it. Rings are broadcast to everyone in the arena
-- ("Castor just rang the great gong!"), which makes them a shared, serialized
-- lock; and the brief the probe prints names everyone standing here, which gives
-- every client the same roster to order itself against. So:
--
--   * each character waits (its position in the roster) x GAP before ringing
--   * seeing anyone else's ring cancels its pending ring (see the gong triggers)
--   * a spawn is adopted whoever rang it (see arenaAdoptSummon)
--
-- In the steady state only the first character in the order sends anything at
-- all; the rest never reach their timer. Nobody is designated the leader, which
-- matters because characters constantly walk out for potions, healing, drink and
-- training — a leader would take the whole team idle with it. Instead the
-- absentee simply stops appearing in the brief, and whoever is now first rings
-- on the very next probe. A roster of one is exactly the solo behaviour.
--
-- The gap wants to be comfortably longer than the round trip for a ring to be
-- echoed back to everyone, so that the runner-up has really seen the winner's
-- ring before its own timer fires.
local ARENA_TEAM_RING_GAP_MS = 2000

-- =========================================================================
-- Hold the gong while a team-mate is escaping
-- =========================================================================
-- Fleeing is decided instantly but takes time to carry out: checkFleeArena
-- flips us to "fleeing" the moment HP crosses the threshold, yet the character
-- is still standing in the arena until a move actually lands, and the move can
-- be refused for several seconds ("You cannot leave in the heat of battle!",
-- "Sorry, you'll have to rest a while before you can move.").
--
-- That opens a lethal window in team mode. Say a character flees at 401 HP after
-- a flame giant hit; a team-mate lands the killing blow a second later and,
-- being slot 0 on the first attempt of the cycle, rings immediately — well
-- inside the 2s retry cadence of the escape. The fresh summon then gets a free
-- round against someone with 31 HP who is still trying to walk out. Nothing in
-- the roster machinery prevents this: the fleeing character is still listed in
-- the brief, so its presence only orders the ring rather than suppressing it.
--
-- The fix uses the channel the team already coordinates over — the game itself.
-- An unrecognised command is broadcast to the room as speech, which everyone
-- else reads as "From <name>: <text>", so a plain say is a room-scoped broadcast
-- every client sees. A fleeing character announces arenaTeamHeal.NEED_MSG, and
-- anyone who hears it holds the gong until that character says
-- arenaTeamHeal.HEALED_MSG on its way back in.
--
-- Room-scoped is the whole point, and also the trap: the all-clear MUST be said
-- from the arena (arenaArrivedHome), never at the temple, which is four rooms
-- away and out of earshot of everyone who needs to hear it.
--
-- Gathered into one table rather than the half-dozen file-scope locals this
-- would naturally be: main.lua is a single Lua chunk and Lua caps a chunk at 200
-- locals, which it was already close enough to that adding them individually
-- overflowed it ("too many local variables"). One table costs one slot.
local arenaTeamHeal = {
    NEED_MSG = "I need healing",
    HEALED_MSG = "I am healed",
}

-- Entries are timestamps, not booleans, so the hold is a lease that expires
-- rather than a flag that can get stuck on. A character that dies mid-escape,
-- disconnects, or is stopped by hand never says the all-clear, and a plain
-- boolean would idle the whole team indefinitely waiting for it — a worse
-- failure than the death we're preventing, and a quieter one, because an idle
-- arena looks like a team waiting politely. The same reasoning already governs
-- the ring-yield trigger, which re-arms a pump tick rather than trusting that a
-- summon it stood down for will really arrive.
--
-- The lease has to outlast the whole episode on the strength of a single
-- announcement, because the escapee says this exactly once (see announceNeed).
-- The long pole is not the walk to the temple — 4 paced steps each way plus
-- "buy healing", call it 15s — but the wait to get out of the arena at all: the
-- heat-of-battle guard refuses every step until the monster is dead, so a slow
-- kill pins the escapee in the room for as long as the fight lasts.
--
-- 180s covers that with room to spare. Erring long is deliberate: a lease that
-- lapses while the character is still standing there hurt re-opens the exact
-- window this exists to close, whereas one that outlives a character who died
-- mid-escape only costs the team some idle time.
arenaTeamHeal.LEASE_SEC = 180

-- Name (lowercased) -> os.time() of the most recent "I need healing" heard.
function arenaTeamHeal.leases()
    taPackage.arenaTeamHealing = taPackage.arenaTeamHealing or {}
    return taPackage.arenaTeamHealing
end

-- Who, if anyone, is currently escaping. Drops expired leases as it goes so the
-- table can't grow without bound over a long session. Returns the name of a
-- live lease (for the debug echo), or nil when the gong is free.
function arenaTeamHeal.holder()
    local leases = arenaTeamHeal.leases()
    local now = os.time()
    local holder = nil
    for name, at in pairs(leases) do
        if now - at >= arenaTeamHeal.LEASE_SEC then
            leases[name] = nil
        else
            holder = holder or name
        end
    end
    return holder
end

-- Announce that we are escaping — once per flee, however long the escape takes.
-- The announcement flag doubles as the guard: it is set here and cleared only by
-- the all-clear, so every later call inside the same episode is a no-op, while a
-- second flee later in the session announces again as it should.
--
-- Deliberately NOT sent through arenaSend: that records arenaLastCmd for the
-- blocked-move retries, and stamping the announcement there would make the next
-- retry re-say the message instead of re-walking the step we're trying to escape
-- on. Team mode only — solo, this would just be talking to ourselves.
function arenaTeamHeal.announceNeed()
    if not taPackage.arenaTeam then return end
    if taPackage.arenaAnnouncedNeedsHealing then return end
    taPackage.arenaAnnouncedNeedsHealing = true
    send(arenaTeamHeal.NEED_MSG)
end

-- Release the hold, from inside the arena. Guarded on having actually announced
-- so the ordinary errand returns (bar, magic shop, guild hall) — which share
-- arenaArrivedHome with the heal return — stay silent.
function arenaTeamHeal.announceHealed()
    if not taPackage.arenaAnnouncedNeedsHealing then return end
    taPackage.arenaAnnouncedNeedsHealing = false
    if not taPackage.arenaTeam then return end
    send(arenaTeamHeal.HEALED_MSG)
end

-- Our place in the ring order: how many of the other characters here sort before
-- our name. Counting rather than sorting sidesteps the question of whether we
-- appear in our own roster (we don't — the game omits us from the brief) since
-- an equal name is not "before" us either way.
local function arenaTeamRingSlot()
    local me = taPackage.character.name
    -- Without a name we can't place ourselves, so take the front of the order and
    -- behave like solo. Ringing a beat early is recoverable; never ringing is not.
    if not me then return 0 end
    local ahead = 0
    for _, other in ipairs(taPackage.arenaTeamRoster or {}) do
        if other:lower() < me:lower() then ahead = ahead + 1 end
    end
    return ahead
end

-- Ring, but only after letting everyone ahead of us go first.
--
-- Slot 0 rings immediately, but only on its FIRST attempt of a summon cycle.
-- That fast path is what makes the common case cost nothing, and while our ring
-- lands it is also harmless. It stops being harmless once the ring is bouncing
-- off "still physically exhausted": we then re-ring blind every pump tick, with
-- no pending timer for an incoming ring to cancel, so the moment our physical
-- clock happens to recover we summon on top of whoever rang while we were
-- blocked. That double-summoned an ogress mage AND a stone giant onto the party
-- at 19:01:18 (logs/session-kerhak-team-fight-2026-07-25T18-58-34.log:462) —
-- Kerhak was correctly slot 0, but had been blocked for 12s, so Teekywiki's
-- turn came around and both rings landed a heartbeat apart.
--
-- On a retry the reason to hurry is gone, so take the same timer path as
-- everyone else and let the arenaRingGen guard call it off. A character that is
-- genuinely alone (empty roster) keeps the fast path on every attempt: there is
-- nobody to collide with, and the wait would just be dead time.
local function arenaTeamRing()
    -- Someone is escaping at low HP: don't summon a monster on top of them.
    -- Returning without ringing is all it takes — the scan pump that got us here
    -- has an outstanding re-scan timer (ARENA_RING_RETRY_MS, ~3s) which is not
    -- invalidated by declining, so we simply probe again in a moment and
    -- re-evaluate. Reusing the pump rather than adding a second timer also means
    -- each retry re-derives the roster, and keeps the ring generation the single
    -- thing that owns ring liveness.
    --
    -- Only the gong is held. A monster already in the room is still engaged
    -- normally — the probe's occupant trigger reaches arenaEngage without ever
    -- coming through here — so holding the gong never leaves the team standing
    -- idle next to something that is already hitting them.
    local holder = arenaTeamHeal.holder()
    if holder then
        arenaDebugEcho("team-ring-held-for-" .. holder)
        return
    end
    local slot = arenaTeamRingSlot()
    taPackage.arenaTeamSlot = slot
    arenaDebugEcho("team-ring-slot-" .. slot)
    local attempts = taPackage.arenaRingAttempts or 0
    taPackage.arenaRingAttempts = attempts + 1
    local alone = #(taPackage.arenaTeamRoster or {}) == 0
    if slot == 0 and (attempts == 0 or alone) then
        arenaRing()
        return
    end
    -- Guarded on the ring generation, which is what the observed-ring triggers
    -- bump to call this off when someone ahead of us rings first. Slot 0 has no
    -- stagger of its own, so give it one gap — still inside the pump's window
    -- (ARENA_RING_RETRY_MS) so the re-scan can't outrun our own turn.
    local gen = taPackage.arenaRingGen or 0
    createTimer(math.max(slot, 1) * ARENA_TEAM_RING_GAP_MS, function()
        if taPackage.arenaState ~= "ringing" then return end
        if (taPackage.arenaRingGen or 0) ~= gen then return end
        arenaDebugEcho("team-ring-turn")
        arenaRing()
    end, { repeating = false })
end

-- The arena brief lists occupants as "There is a hobgoblin, a huge rat, and a
-- female kobold here." Pull the first monster's name so we can engage it. The
-- leading word is an article ("a"/"an"/"the") or a count ("two huge rats"); a
-- count means a plural noun, which we reduce to the singular the death line
-- ("The huge rat falls...") and our attack target use.
local ARENA_ARTICLE_WORDS = {
    a = true, an = true, the = true,
    two = true, three = true, four = true, five = true, six = true,
}
-- Reduce a plural monster noun to its singular. Most plurals just add "s"
-- ("dragons" -> "dragon", "ogre mages" -> "ogre mage"), but some take an "-i"
-- plural instead ("affreeti" -> "affreet", "efreeti" -> "efreet"), so when
-- there's no trailing "s" fall back to stripping a trailing "i".
local function singularizeMonster(noun)
    if noun:match("s$") then
        return (noun:gsub("s$", ""))
    elseif noun:match("i$") then
        return (noun:gsub("i$", ""))
    end
    return noun
end
local function firstArenaMonster(contents)
    if not contents or contents == "nobody" then return nil end
    local first = (contents:match("^([^,]+)") or contents):match("^%s*(.-)%s*$")
    local article, rest = first:match("^(%S+)%s+(.+)$")
    if article and ARENA_ARTICLE_WORDS[article:lower()] then
        local a = article:lower()
        if a ~= "a" and a ~= "an" and a ~= "the" then
            rest = singularizeMonster(rest)
        end
        return rest
    end
    return first
end

-- Before ringing for a fresh monster, send a bare return to print the arena
-- brief and see who is already here. Sending "look" only re-prints the room
-- description (no occupants); an empty line is the only way to list them. The
-- arena is shared and a monster we lost track of — or one another player
-- summoned — may already be present. Ringing on top of it stacks a second
-- monster on us, the orphaned-monster trap that gets characters killed, so we
-- adopt whatever is here and only ring once the room is clear.
--
-- This is a SELF-HEALING PUMP, not a one-shot. Each scan arms a follow-up
-- timer keyed to arenaRingGen; if the scan doesn't resolve into a fight within
-- the window — brief lost, ring bounced on "physically exhausted", or the room
-- churned by the other player sharing it — the next tick simply scans again.
-- The loop can therefore never get wedged in "ringing" doing nothing (the
-- earlier deadlock: a dropped retry left the character idle, see
-- logs/session-pollux-2026-06-28T16-09-01.log). arenaEngage bumps arenaRingGen
-- the instant we lock onto a monster, which stops the pump.
--
-- In team mode the pump has to outlast our wait for a turn to ring, because
-- re-scanning bumps arenaRingGen and that is exactly what cancels a pending
-- ring. At the fixed 3s a character in slot 2 (4s of stagger) would be re-probed
-- before its turn ever came and would never ring at all — so widen the window by
-- our own stagger. The slot is the one the last probe worked out; on the very
-- first probe of a session it is 0, so a character deep in the order can lose
-- one cycle before the window catches up. That self-corrects immediately and
-- keeps the pump's anti-wedge guarantee intact.
local function arenaScanRoom()
    if taPackage.arenaState ~= "ringing" then return end
    local gen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaRingGen = gen
    taPackage.arenaProbePending = true
    taPackage.arenaRingPending = false
    -- Each probe re-learns who is in the arena from scratch, so a character that
    -- has walked out on an errand stops holding a slot in the ring order.
    taPackage.arenaTeamRoster = {}
    send("")
    local retryMs = ARENA_RING_RETRY_MS
        + (taPackage.arenaTeamSlot or 0) * ARENA_TEAM_RING_GAP_MS
    createTimer(retryMs, function()
        if taPackage.arenaState == "ringing" and (taPackage.arenaRingGen or 0) == gen then
            arenaScanRoom()
        end
    end, { repeating = false })
end

-- Lock onto a single monster and start swinging. Shared by the gate-spawn path
-- (a monster we just summoned) and the room-scan path (a monster already here).
local function arenaEngage(name)
    -- Halt the scan pump: any outstanding tick guards the prior arenaRingGen.
    taPackage.arenaRingGen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaMonster = name
    taPackage.arenaState = "fighting"
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    -- This summon cycle is over, so the next one starts fresh on the fast path.
    taPackage.arenaRingAttempts = 0
    -- First sighting of this monster: grab its description for the bestiary. The
    -- name we store comes from the game's own reply ("The female troll seems to
    -- be in good physical health."), not from what we typed, so addressing it by
    -- the single-word target still files it under its full name.
    if not taPackage.db.monsterHasDescription(name) then
        send("look " .. arenaTarget(name))
    end
    arenaAttack()
    arenaCast()
end

-- Return to combat after a trip out of the arena (heal or bar). Shared by both
-- arenas' "arrived back at the arena" paths: resume swinging at the monster we
-- left if it survived, otherwise scan the room and ring for a fresh one.
local function arenaResumeInCombat()
    if taPackage.arenaMonster then
        taPackage.arenaState = "fighting"
        taPackage.arenaAttackPending = false
        taPackage.arenaCastPending = false
        arenaAttack()
        arenaCast()
    else
        taPackage.arenaState = "ringing"
        taPackage.arenaRingPending = false
        arenaScanRoom()
    end
end

-- =========================================================================
-- Paced journey navigation
-- =========================================================================
-- Some destinations are several rooms away, and moving between them too fast
-- makes the character fall down. A "journey" walks such a route one step at a
-- time: an explicit list of directions plus the room that ends it. We send the
-- first step, then advance one step per room line we receive, pausing
-- ARENA_STEP_DELAY_MS between steps. Every leg in every arena is a journey:
-- temple, bar, magic shop, guild hall. All three arenas name rooms alike
-- ("arena", "temple"), so a journey is driven by its own step list and never by
-- matching a waypoint's name.
-- 1500ms, the same pace navigate-to settled on, and for the same reason. That
-- was tuned by measurement rather than guesswork: at 1000ms a paced walk tripped
-- 4 times in 60 moves (6.7%, against a 1.13% baseline over the 72,354 hand-typed
-- moves in the archived logs), 1200 and 1300 both still tripped, and 1500 has
-- since carried 250-odd scripted moves -- including a single 103-step walk --
-- without one. These journeys move the same character through the same game, so
-- there is no reason they should be paced faster than the pace we know works.
local ARENA_STEP_DELAY_MS = 1500
-- When a step is rejected because we moved too fast ("In your haste, you trip
-- and fall!"), no room line is printed, so the step-driven walk would stall
-- forever waiting for a room it never enters. Re-send the current step after a
-- longer pause than the normal pacing to both recover the walk and back off.
local ARENA_TRIP_RETRY_MS = 2000
-- Exposed so tests catch the pacing timer by name rather than by a literal
-- interval, which silently stops matching the moment the pace is retuned.
taPackage.arenaStepDelayMs = ARENA_STEP_DELAY_MS
local ARENA_ROOM = "arena"
-- Consecutive unrelieved thirst/hunger ticks before we give up and leave the
-- game. Each tick drains ~1 HP; a healthy loop rings the gong or buys a drink
-- between ticks (both reset the streak), so reaching this many in a row means
-- the errand loop is wedged. 20 is far above any normal bar round-trip yet bails
-- with a large HP margin (something-went-wrong.log still had ~200/318 after 20
-- minutes stuck).
local ARENA_PARCHED_LIMIT = 20
-- Per-profile navigation: each arena's temple, bar and (where it has one)
-- guild hall, reached by a fixed direction step-list walked one paced step at a
-- time. arenaNav() returns the active profile's config. All three arenas are in
-- here now, so every leg is paced and every leg has trip recovery.
--
-- A profile is the arena's number as a string, "1"/"2"/"3" — the same word the
-- aliases take, so there is one vocabulary for the arenas and not two.
--
-- Arena 2 has no training hall (checkTrainingNeeded gates on ARENA_HAS_TRAINING
-- below); arena 3 does, so it also carries a toTraining/fromTraining route and
-- a trainingRoom name.
local ARENA_NAV = {
    -- Arena 1 used to walk by room name instead: send the next
    -- direction the instant the arrival line lands. That paced it at the
    -- round-trip latency, 300-600ms, three to five times faster than the
    -- 1500ms we know avoids a trip -- and worse, the trip recovery below is
    -- guarded on `arenaJourney`, so these were the only moves in the script
    -- with nothing to catch a fall. A trip printed no room line, the state
    -- machine waited for one forever, and the run wedged.
    --
    -- Giving it step lists costs nothing and fixes both at once: the same
    -- paced walk, the same retry, the same code as the other two arenas. Every
    -- route here is checked against the mapped first town, room names included.
    --
    -- One deliberate behaviour change comes with it. Healing while also hungry
    -- used to cut the corner from the temple straight to the tavern; now it
    -- returns to the arena and sets out again, because arrivals are the single
    -- place errands get dispatched (see arenaArrivedHome). Two rooms longer,
    -- and the same as the other arenas do it.
    ["1"] = {
        arenaRoom    = ARENA_ROOM,
        templeRoom   = "temple",
        barRoom      = "tavern",
        trainingRoom = "guild hall",
        toTemple     = { "w", "w" },
        fromTemple   = { "e", "e" },
        toBar        = { "w", "ne" },
        fromBar      = { "sw", "e" },
        toTraining   = { "w", "n" },
        fromTraining = { "s", "e" },
    },
    ["2"] = {
        arenaRoom  = ARENA_ROOM,
        templeRoom = "temple",
        barRoom    = "inn",
        toTemple   = { "s", "s", "s", "s" },
        fromTemple = { "n", "n", "n", "n" },
        toBar      = { "s", "s", "w", "w", "sw", "sw" },
        fromBar    = { "ne", "ne", "e", "e", "n", "n" },
    },
    ["3"] = {
        arenaRoom    = ARENA_ROOM,
        templeRoom   = "temple",
        barRoom      = "tavern",
        trainingRoom = "guild hall",
        toTemple     = { "sw", "se", "ne", "e" },
        fromTemple   = { "w", "sw", "nw", "ne" },
        toBar        = { "sw", "nw" },
        fromBar      = { "se", "ne" },
        toTraining   = { "sw", "se", "ne", "n" },
        fromTraining = { "s", "sw", "nw", "ne" },
    },
}

-- Which profiles have a training hall to bank earned levels. Arena 2 has none,
-- so a level-up there just keeps fighting. Absent = false.
local ARENA_HAS_TRAINING = { ["1"] = true, ["3"] = true }

local function arenaNav()
    return ARENA_NAV[taPackage.arenaProfile]
end

-- Strength/agility potions (rowan, hyssop) from the magic shop. Both arenas
-- reach the same "magic shop" room by different routes. This is a reactive
-- round trip like healing: when a potion wears off we walk here, re-buy and
-- re-drink both, and walk back. The wear-off line is identical for each potion,
-- so we can't tell which lapsed — we always refresh both.
local SHOP_ROOM = "magic shop"
local ARENA_SHOP = {
    ["1"] = { to = { "w", "s", "s" },                from = { "n", "n", "e" } },
    ["2"] = { to = { "s", "s", "w", "w", "n", "n" }, from = { "s", "s", "e", "e", "n", "n" } },
    ["3"] = { to = { "sw", "se", "se", "se" },       from = { "nw", "nw", "nw", "ne" } },
}

-- Send the next queued direction. index counts steps already sent, so bumping
-- it first and indexing gives the step we haven't walked yet.
local function arenaJourneyStep()
    local j = taPackage.arenaJourney
    if not j then return end
    j.index = j.index + 1
    local dir = j.steps[j.index]
    if dir then arenaSend(dir) end
end

-- Re-send the current (not-yet-completed) step without advancing the index.
-- Used to recover from a rejected move: the step at j.index was sent but never
-- landed us in a new room, so we walk it again.
local function arenaJourneyResendStep()
    local j = taPackage.arenaJourney
    if not j then return end
    local dir = j.steps[j.index]
    if dir then arenaSend(dir) end
end

-- Pause before the next step so we don't move too fast and fall. The generation
-- guard drops a stale timer if the session stops or a new journey starts before
-- it fires.
local function arenaJourneyScheduleStep()
    local gen = taPackage.arenaJourneyGen or 0
    createTimer(ARENA_STEP_DELAY_MS, function()
        if taPackage.arenaState and (taPackage.arenaJourneyGen or 0) == gen then
            arenaJourneyStep()
        end
    end, { repeating = false })
end

-- Begin walking a leg: record the step list, the room that ends it, and the room
-- we are leaving from (fromRoom), bump the journey generation to invalidate any
-- in-flight step timer, and send the first step immediately (the pacing pause
-- only applies between steps). fromRoom lets the movement handler ignore the
-- room brief we're already standing in — see arenaJourneyOnMovement.
local function arenaJourneyStart(steps, arriveRoom, fromRoom)
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    taPackage.arenaJourney = { steps = steps, index = 0, arriveRoom = arriveRoom, fromRoom = fromRoom }
    arenaJourneyStep()
end

-- Head to the bar. Its confirmation lines differ from the first arena's tavern
-- ("The barmaid brings you a drink..."), but the buy commands are the same and
-- our navigation doesn't depend on those lines, so we just walk there.
local function departForBar()
    local nav = arenaNav()
    taPackage.arenaState = "tavern"
    echo("[arena] Heading to bar.")
    arenaJourneyStart(nav.toBar, nav.barRoom, nav.arenaRoom)
end

-- Forward declaration: arenaJourneyOnMovement chains to the tavern/bar when a
-- shop trip ends and food/drink is still owed, but departForTavern (which picks
-- the right route per arena) is defined further down.
local departForTavern

-- Forward declaration: the errand-service points below must not restock potions
-- while we owe a training trip (the hall refuses a potion-tainted character), but
-- checkTrainingNeeded is defined further down (it needs getLevel/getExperience).
-- Assigned later via `function checkTrainingNeeded()`.
local checkTrainingNeeded

-- Forward declaration: "am I too hurt to be in here?" and the walk-out that
-- answers it. Both are defined down in the flee block (they need the threshold
-- constants), but the errand-service points below have to ask before they
-- resume combat. A table rather than three separate `local function`s on
-- purpose: main.lua is within a couple of names of Lua's 200 top-level local
-- limit, and this way the whole idea costs one.
local arenaHeal = {}
-- Also hung off taPackage so the flee thresholds are readable from outside this
-- chunk. Tests assert against arenaHeal.FLOOR rather than a literal, so retuning
-- the number does not silently invalidate what they are checking.
taPackage.arenaHeal = arenaHeal

-- Head to the magic shop to restock the strength/agility potions. Both arenas
-- reach the same shop by different routes, chosen by profile. Always a journey,
-- so even the first arena walks it one paced step at a time.
local function departForShop()
    local nav = ARENA_SHOP[taPackage.arenaProfile]
    if not nav then return end
    taPackage.arenaState = "potions"
    echo("[arena] A potion wore off — heading to the magic shop.")
    arenaJourneyStart(nav.to, SHOP_ROOM, ARENA_ROOM)
end

-- Back in the arena at the end of an errand. Each errand (heal, food, potions)
-- is its own round trip that starts and ends here, so any still-owed errand is
-- launched now — shop before food — rather than resuming combat. Every arena
-- walks home the same way, so a potion that wore off mid-errand is serviced on
-- arrival whichever errand we were on. departForShop/Tavern pick the route.
local function arenaArrivedHome()
    -- The gold-farming loop's exit door. Once it has banked its level it is done
    -- with the arena and wants to cash out rather than ring again, and this is
    -- the moment to hand over: a confirmed arrival in a known room, with no
    -- journey in flight to race. Returning true means it has taken over.
    --
    -- Deliberately ahead of the hurt check below. Being low on HP is only
    -- dangerous while we intend to keep fighting; the walk this hands off to
    -- goes through town, where nothing attacks, and a temple detour would spend
    -- the gold we are about to hand over. Defined in ta_create.lua, and nil for
    -- an ordinary run, which leaves everything below exactly as it was.
    if taPackage.onArenaArrivedHome and taPackage.onArenaArrivedHome() then return end
    -- Walked home hurt: turn straight around for the temple, before anything
    -- else and above all before swinging. checkFleeArena only looks at HP while
    -- arenaState == "fighting", so damage taken during an errand goes unnoticed
    -- — a flame giantess's 167-damage breath landed while we were walking to the
    -- magic shop, and we came back at 273/440 with a third-arena floor of 400.
    -- Without this gate the errand dispatch below resumed combat, the first
    -- "a flame" put us in the heat of battle, and the flee that finally fired on
    -- the next combat line could no longer leave the room ("You cannot leave in
    -- the heat of battle!" x6, one giant's swing from death). Arriving hurt but
    -- un-engaged is the one moment we can still walk out for free.
    if arenaHeal.isLow() then
        arenaDebugEcho("arrived-home-low")
        arenaHeal.departForTemple()
        return
    end
    -- Back in the arena and back on our feet: release any gong hold we placed.
    -- This has to happen here rather than at the temple — speech only carries to
    -- the room you are standing in, and the team is here. It runs before the
    -- errand dispatch below because the hold is about being one hit from death,
    -- which is no longer true; if we immediately walk out again for food, that
    -- is an ordinary full-health errand the roster already handles.
    arenaTeamHeal.announceHealed()
    -- A level is owed: bank it before starting another fight.
    --
    -- Without this, the only place training is ever considered after a kill is
    -- the post-kill decision point, and that one asks checkFleeArena() FIRST --
    -- so any kill that left us low enough to flee skips the training check
    -- entirely. Arriving home from the temple then went straight back to
    -- combat, and the cycle kill -> flee -> heal -> resume -> ring closed with
    -- the XP already earned and nothing ever spending it.
    --
    -- Rare for a high-level character, which seldom flees. Near-permanent for a
    -- fresh one: 34 max HP against a flee floor of 25 means fleeing after 9
    -- damage, i.e. after almost every fight, so the escape hatch (a kill costing
    -- under 9 HP) essentially never comes up. Watched live at 1194 XP against a
    -- 1125 threshold, still level 1 and still fighting, in
    -- logs/session-garbageman-2026-08-15T20-17-58.log.
    --
    -- Placed after the hurt check above so we heal first and train on the next
    -- arrival, and before the errand dispatch so a level outranks a restock or a
    -- meal. arenaTryTrain itself still refuses while stat potions are active.
    -- Reached through taPackage because arenaTryTrain is a local defined further
    -- down the chunk; a field costs no local slot (see CLAUDE.md).
    if taPackage.arenaTryTrain and taPackage.arenaTryTrain() then return end
    -- Skip a restock while a level is owed: we are deliberately draining the stat
    -- potions so the training hall will accept us (checkTrainingNeeded stays true
    -- until we train). needsPotions is left set so the restock happens later, once
    -- we've trained and it flips false. Food/drink still get serviced.
    if taPackage.needsPotions and not checkTrainingNeeded() then
        departForShop()
    elseif taPackage.needsDrinks or taPackage.needsMeal then
        departForTavern()
    else
        arenaResumeInCombat()
    end
end

-- Can we walk out for an errand (thirst/hunger/potion) right now? Only from an
-- active fight or the ringing gap, and NEVER while a gong summon is still in
-- flight. Ringing the gong is a two-step handshake — "You just rang the great
-- gong!" then, a beat later, the monster materializes — and adoption of that
-- monster requires arenaState == "ringing" (see arenaAdoptOwnSummon). If an
-- errand departs in that gap, the state flips to "potions"/"tavern", the summon
-- is orphaned (never adopted, so we never swing at it), and we walk out into a
-- monster that answers our move with "You cannot leave in the heat of battle!"
-- — the run then wedges forever (see problem.log: a potion wore off between the
-- ring and a warlock's arrival, and the character stood there thirsty, taking
-- hits, until it was stopped by hand). Deferring here lets the summon land and
-- be fought; the errand is picked up from the next clear ring gap below.
local function arenaCanDepartNow()
    local st = taPackage.arenaState
    if st ~= "fighting" and st ~= "ringing" then return false end
    if taPackage.arenaRingPending or taPackage.arenaOwnSummonPending then return false end
    return true
end

-- At a clear-room ring decision, honor any errand deferred while a monster was
-- present (or while a summon was still in flight): the room is empty now, so it
-- is safe to walk out. Otherwise ring for a fresh monster. This is the single
-- service point that guarantees a deferred potion/food/drink run is eventually
-- made even when it was flagged mid-fight. Mirrors arenaArrivedHome, but the
-- no-errand case rings rather than resuming a (nonexistent) fight.
local function arenaRingOrErrand()
    -- Standing in a clear arena, hurt: heal before summoning anything. The room
    -- being empty is exactly the window in which walking out still works, and
    -- ringing here would spend it. Same blind spot as arenaArrivedHome — a hit
    -- taken while arenaState wasn't "fighting" never ran the flee check.
    if arenaHeal.isLow() then
        arenaDebugEcho("ring-gap-low")
        arenaHeal.departForTemple()
        return
    end
    -- As in arenaArrivedHome: don't restock potions while a level is owed — we
    -- are draining them on purpose so the training hall will accept us. Ring and
    -- keep fighting (which wears them down); the restock waits until after we train.
    if taPackage.needsPotions and not checkTrainingNeeded() then
        departForShop()
    elseif taPackage.needsDrinks or taPackage.needsMeal then
        departForTavern()
    elseif taPackage.arenaTeam then
        -- Someone has to summon, but only one of us: wait for our turn in the
        -- ring order rather than ringing on top of a team-mate.
        arenaTeamRing()
    else
        arenaRing()
    end
end

-- Advance the walk one room at a time. Called for every "You're ..." line while
-- a paced journey is active. Reaching the leg's destination room fires that
-- leg's action (heal, buy, or resume combat); any other room is an intermediate
-- step, so pace the next move.
local function arenaJourneyOnMovement(room)
    local j = taPackage.arenaJourney
    if not j then return end
    -- A room brief for the room we departed from is NOT a move. A journey leaves
    -- right after a kill, and the kill's trailing "You're in the arena." scan
    -- arrives just as we start walking; counting it as a step advanced the index
    -- past our true position, so one real south consumed two "s" steps and the
    -- next step ("w") fired a room too early → "no exit" and a wedged walk (see
    -- something-went-wrong.log). Departure rooms are distinctive ("arena", "inn",
    -- "temple", "magic shop") and a route never revisits its start, so ignoring
    -- them for the whole leg is safe — unlike the generic "path" rooms a leg may
    -- pass through several of in a row, which must each still count.
    if j.fromRoom and room == j.fromRoom then return end
    if room ~= j.arriveRoom then
        arenaJourneyScheduleStep()
        return
    end
    taPackage.arenaJourney = nil
    local st = taPackage.arenaState
    if st == "fleeing" then
        -- Arrived at the temple.
        taPackage.arenaState = "healing"
        arenaSend("buy healing")
    elseif st == "tavern" then
        -- Arrived at the bar.
        if taPackage.needsDrinks then
            send("buy drink")
            taPackage.needsDrinks = nil
        end
        if taPackage.needsMeal then
            send("buy meal")
            taPackage.needsMeal = nil
        end
        taPackage.arenaParchedStreak = 0
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromBar, nav.arenaRoom, nav.barRoom)
    elseif st == "training" then
        -- Arrived at the guild hall. Send the purchase and start walking home
        -- at once: its success or refusal is handled by their own triggers, so
        -- there is nothing to wait for. Banking the level, charging the fee and
        -- re-buying potions all happen in the success trigger.
        send("buy training")
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromTraining, nav.arenaRoom, nav.trainingRoom)
    elseif st == "potions" then
        -- Arrived at the magic shop. Re-buy and re-drink both potions — the
        -- wear-off line is identical for each, so we refresh both — then walk
        -- back. The route home is chosen by the same profile we walked out on.
        send("buy rowan")
        send("buy hyssop")
        send("drink rowan")
        send("drink hyssop")
        -- Both stat potions are now up again. Tracked so that when a level is
        -- owed we know how many wear-off lines to wait for before it is safe to
        -- train (see arenaTryTrain / the wear-off trigger).
        taPackage.arenaPotionsActive = 2
        taPackage.needsPotions = nil
        taPackage.arenaState = "returning"
        arenaJourneyStart(ARENA_SHOP[taPackage.arenaProfile].from, ARENA_ROOM, SHOP_ROOM)
    elseif st == "returning" then
        arenaArrivedHome()
    end
end

-- Assigns to the forward-declared local above (no `local` keyword) so
-- departForShop, defined earlier, can refuse to restock while a level is owed.
function checkTrainingNeeded()
    -- Only profiles with a training hall ever leave to train (the second arena
    -- has none). Short-circuiting here disables both the XP-trigger and
    -- death-handler training transitions at once, so a level-up in a
    -- hall-less arena just keeps fighting.
    if not ARENA_HAS_TRAINING[taPackage.arenaProfile] then return false end
    local xp  = getExperience()
    local cls = getClass()
    local lvl = getLevel()
    if not (xp and cls and lvl) then return false end
    local thresholds = xpThresholds[cls]
    if not thresholds then return false end
    local nextThreshold = thresholds[lvl + 1]
    return nextThreshold ~= nil and xp >= nextThreshold
end

-- Head to the training hall to bank an earned level — but only when it is safe.
-- The hall refuses anyone under a strength/agility potion ("Your mind and body
-- must be whole and untainted before you may train."), so once we have earned a
-- level we stop refreshing potions (see departForShop and the wear-off trigger)
-- and keep fighting until they lapse. arenaPotionsActive counts how many are
-- still up; only when it reaches 0 do we walk to the hall. Call at a safe
-- decision point (a clear ring gap or just after a kill); returns true once we
-- have set out to train, so the caller skips its normal ring.
local function arenaTryTrain()
    if not checkTrainingNeeded() then return false end
    if (taPackage.arenaPotionsActive or 0) > 0 then return false end
    echo("[arena] Leveling up — heading to training hall.")
    taPackage.arenaState = "training"
    -- Walk the fixed route to the guild hall. Arrival there
    -- (arenaJourneyOnMovement, st == "training") sends "buy training" and
    -- starts the walk home.
    local nav = arenaNav()
    arenaJourneyStart(nav.toTraining, nav.trainingRoom, nav.arenaRoom)
    return true
end
-- Exposed so arenaArrivedHome, defined earlier in this chunk, can call it: a
-- level owed has to be banked on arriving home too, not only at the post-kill
-- decision point (see the comment there).
taPackage.arenaTryTrain = arenaTryTrain

-- Flee at 75% of max HP, but never below an absolute floor. The percentage
-- alone is unsafe for low-HP characters: a level-2 Sorceror (31 max HP) at 60%
-- fled at 18, and a cave bear's worst observed round is 23 damage (two claws)
-- — so he could cross from "fine" to dead in one round.
--
-- 20, lowered from 25 by request, and the change is a deliberate trade rather
-- than a refinement. 25 was chosen to cover that 23-damage bear round with a
-- small margin, so the floor guaranteed surviving the round in which the flee
-- was decided. 20 no longer does: a bear's worst round kills from here, and the
-- flee is not instant either — it is refused while the physical cooldown runs,
-- and has been seen taking 5-7 retries at 2s with the monster still swinging
-- (logs/session-garbageman-2026-08-15T20-17-58.log, around 20:42-20:47).
--
-- What it buys is time, and quite a lot of it. A fresh half-ogre warrior has
-- ~34 max HP, so the 75% rule gives 25.5 and the old floor bound at 25: it fled
-- after 9 damage, i.e. after nearly every fight, and the gold-farming loop spent
-- 8 temple round trips in a single ~28-minute cycle walking w,w / e,e for a
-- 2-crown heal. At 20 the band between full and fleeing widens from 9 HP to 14,
-- which should cut those trips substantially.
--
-- The bet is that a level-1 character in the first arena meets a cave bear
-- rarely enough that the trips saved outweigh the deaths risked. If deaths start
-- showing up in the logs, this is the first number to put back.
--
-- Fields on arenaHeal rather than three more top-level locals: main.lua sits a
-- name or two under Lua's 200-local ceiling for the main chunk, and it is where
-- they belong anyway.
arenaHeal.FRACTION = 0.75
arenaHeal.FLOOR = 20
-- Per-profile overrides of the flee floor. The third arena's monsters hit far
-- harder than a cave bear, so keep a much larger absolute HP reserve there —
-- flee before dropping below this regardless of the 75% rule. Profiles absent
-- here use arenaHeal.FLOOR.
--
-- 400, lowered from 500: at 500 a character whose max HP is at or below the
-- floor can never be above it, so it flees on the first tick and the third
-- arena never gets started at all. 400 is what the current roster can actually
-- clear. Note this is now BELOW a flame giant's worst observed hit (380) plus
-- any margin: fleeing at 399 leaves 19 HP against that hit, so the floor no
-- longer guarantees surviving the round in which the flee is decided. It buys
-- entry to the arena, not safety inside it — the real protection there is
-- killing fast enough as a team that the round never comes.
arenaHeal.FLOOR_BY_PROFILE = { ["3"] = 400 }

-- The HP we must stay above to be in the arena at all. Split out of
-- checkFleeArena so the question can be asked from outside a fight — see
-- arenaHeal.isLow.
function arenaHeal.threshold()
    local maxHp = taPackage.character.vitalityMax
    local floor = arenaHeal.FLOOR_BY_PROFILE[taPackage.arenaProfile] or arenaHeal.FLOOR
    return maxHp and math.max(math.floor(maxHp * arenaHeal.FRACTION), floor) or floor
end

-- Are we below the flee threshold right now? Deliberately says no when vitality
-- is unknown: an unread HP is not evidence of being hurt, and answering yes
-- would send a fresh character straight to the temple before its first status.
function arenaHeal.isLow()
    local hp = taPackage.character.vitalityCurrent
    return hp ~= nil and hp < arenaHeal.threshold()
end

-- Set out for the temple. The action half of fleeing, callable on its own so a
-- character that walks back INTO the arena hurt can turn around without having
-- to swing first (which is what puts you in the heat of battle you then can't
-- leave). Assumes we are standing in the arena.
function arenaHeal.departForTemple()
    taPackage.arenaState = "fleeing"
    -- Tell the team before taking the first step, so the announcement is out
    -- even if the step is refused — the refusal is exactly the case this
    -- exists for. Announcing first also leaves arenaLastCmd pointing at the
    -- escape direction rather than the speech.
    arenaTeamHeal.announceNeed()
    local nav = arenaNav()
    if not nav then
        -- No profile means no route to walk. Say so rather than throwing
        -- from inside a trigger: the state change above has already stopped
        -- us swinging, which is the half of fleeing that keeps us alive.
        echo("[arena] Fleeing, but no arena profile is set — walk out by hand.")
        return
    end
    arenaJourneyStart(nav.toTemple, nav.templeRoom, nav.arenaRoom)
end

-- Assigns to the forward-declared local above (no `local` keyword) so the
-- incoming-damage triggers, defined earlier in the file, can call it.
function checkFleeArena()
    if taPackage.arenaState ~= "fighting" then return false end
    if not arenaHeal.isLow() then return false end
    arenaDebugEcho("flee-triggered")
    arenaHeal.departForTemple()
    return true
end

function departForTavern()
    departForBar()
end

-- How long to wait before asking for XP again.
--
-- XP is only knowable from a status block: a kill prints the gold it dropped and
-- nothing about experience. So a level earned between two polls is invisible
-- until the next one, and on a flat five-minute cadence that is up to five
-- minutes of fighting for XP that buys nothing -- the level is already earned,
-- and everything after it is waste. Averaged over a cycle that is ~2.5 minutes
-- lost against a 21-minute cycle, i.e. more than a tenth of the run, which is
-- larger than most of the things worth tuning here.
--
-- So poll on distance rather than on the clock. Far from the threshold a level
-- cannot possibly land in the next few minutes and asking is pure noise; close
-- to it, a single kill may cross the line. The bands are picked against what one
-- kill is actually worth in the first arena, where a cave bear went for 520 XP
-- in logs/session-garbageman-2026-08-15T19-45-33.log -- inside that, the very
-- next kill can finish the job, so ask often.
--
-- Costs about a dozen extra `status` sends per cycle, all of them in the half of
-- the run where the answer can change the plan.
local ARENA_XP_CHECK_FAR_MS = 300000
local ARENA_XP_CHECK_NEAR_MS = 60000
local ARENA_XP_CHECK_CLOSE_MS = 30000
local function arenaXpCheckDelay()
    local xp = getExperience()
    local cls = getClass()
    if not (xp and cls) then return ARENA_XP_CHECK_FAR_MS end
    local nextAt = getXpForNextLevel(xp, cls)
    -- Level 25, or a class with no table: nothing to count down to.
    if not nextAt then return ARENA_XP_CHECK_FAR_MS end
    local remaining = nextAt - xp
    if remaining <= 200 then return ARENA_XP_CHECK_CLOSE_MS end
    if remaining <= 600 then return ARENA_XP_CHECK_NEAR_MS end
    return ARENA_XP_CHECK_FAR_MS
end

local function scheduleArenaXpCheck()
    local gen = taPackage.arenaXpTimerGen or 0
    createTimer(arenaXpCheckDelay(), function()
        if (taPackage.arenaXpTimerGen or 0) ~= gen then return end
        taPackage.arenaXpCheckPending = true
        send("status")
        scheduleArenaXpCheck()
    end, { repeating = false })
end

-- Re-arm on load if a session is already running.
--
-- reloadScript() clears every pending timer (App.tsx calls
-- timerManager.clearTimers() before re-reading the scripts) while taPackage --
-- and so arenaState -- survives. This chain only ever re-arms from its own
-- callback, so a reload mid-session destroys the one pending timer and nothing
-- ever schedules another: XP polling stops for good, silently, in a session that
-- otherwise looks healthy. That is exactly what happened after the reload at
-- line 12186 of logs/session-garbageman-2026-08-15T20-17-58.log -- every later
-- `st` in that log was typed by hand.
--
-- Load-time rather than trigger-driven because there is no line to hang it on:
-- the symptom is the absence of traffic, not the presence of any. Any
-- self-rescheduling timer added here later needs the same treatment.
if taPackage.arenaState then
    echo("[arena] Script reloaded mid-session — re-arming the XP check.")
    scheduleArenaXpCheck()
end

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
    setExperience(matches[2])
    checkLevelUpNotification(tonumber(matches[2]))
    -- Follow-session XP accounting. `ta.follow` records the starting XP and
    -- `ta.unfollow` records the ending XP by sending `status` and waiting for the
    -- Experience line below; a pending flag tells us which capture this line is
    -- for. Kept independent of the arena flags so the two can't interfere.
    local followXp = tonumber(matches[2])
    if taPackage.followStartXpPending then
        taPackage.followStartXpPending = false
        taPackage.followSessionStartXp = followXp
        echo("[follow] Session started. XP: " .. followXp)
    elseif taPackage.followEndXpPending then
        taPackage.followEndXpPending = false
        local startXp = taPackage.followSessionStartXp
        if startXp then
            echo("[follow] Session over — gained " .. (followXp - startXp)
                .. " XP (total: " .. followXp .. ").")
        else
            echo("[follow] Session over — starting XP unknown (total: " .. followXp .. ").")
        end
        taPackage.followSessionStartXp = nil
    end
    -- Between monsters and enough XP to level: head to train, but only once our
    -- stat potions have lapsed (arenaTryTrain returns false while any is active,
    -- in which case we fall through and keep ringing/fighting so they wear off).
    if taPackage.arenaState == "ringing" and arenaTryTrain() then
        return
    end
    if not taPackage.arenaXpCheckPending then return end
    taPackage.arenaXpCheckPending = false
    local xp = tonumber(matches[2])
    local startXp = taPackage.arenaSessionStartXp
    local elapsed = os.time() - (taPackage.arenaSessionStartTime or os.time())
    local minutes = math.floor(elapsed / 60)
    local gained = startXp and (xp - startXp) or 0
    echo("[arena] " .. os.date("%H:%M:%S") .. " — " .. minutes .. " min, +"
        .. gained .. " XP (total: " .. xp .. ")")
    -- Phone notification so arena progress is visible off-screen. The XP echo
    -- above runs every 5 min, but a check-in every 5 min is too chatty for a
    -- phone, so throttle the ping to every 30 min. Fire-and-forget (no callback)
    -- — a failed ping must never disturb the fight loop.
    do
        local now = os.time()
        local lastNtfy = taPackage.arenaLastNtfyTime
        if not lastNtfy or (now - lastNtfy) >= 1800 then
            taPackage.arenaLastNtfyTime = now
            local hp = getVitality()
            local gold = getGold()
            local nextThreshold = getXpForNextLevel(xp, getClass())
            local lines = { "[" .. (taPackage.character.name or "?") .. "]" }
            if nextThreshold then
                lines[#lines + 1] = "- XP Until Level Up: "
                    .. formatWithCommas(nextThreshold - xp)
            end
            -- The raw XP total says little on a phone; the level does, and a "^"
            -- glued to it (as on the status bar) says this character has earned
            -- a level it hasn't trained for yet.
            local level = getLevel()
            lines[#lines + 1] = "- Lvl: " .. (level or "?")
                .. (hasUntrainedLevel() and "^" or "")
            lines[#lines + 1] = "- HP: " .. (hp or "?")
            local encPct = getEncumberancePercent()
            lines[#lines + 1] = "- Encumberance: " .. (encPct and (encPct .. "%") or "?")
            lines[#lines + 1] = "- Gold: " .. (gold and formatWithCommas(gold) or "?")
            local titles = { ["2"] = "2nd Arena Check-In", ["3"] = "3rd Arena Check-In" }
            local title = titles[taPackage.arenaProfile] or "Arena Check-In"
            sendNtfy(title, table.concat(lines, "\n"), true)
        end
    end
end, { type = "regex" })

-- Start an arena session. profile "1" is the original adjacent-rooms arena;
-- profiles "2" and "3" share this combat engine but walk their distant
-- temple/bar/shop one paced step at a time (see ARENA_NAV). Arena 3 also has a
-- training hall (reached by a paced route); arena 2 does not.
--
-- `team` turns on cooperative fighting: several characters share the arena and
-- coordinate so only one monster is ever summoned, and everybody swings at it.
-- It is a flag on the same session, not a second loop — every errand (thirst,
-- potions, flee-and-heal, training) stays per-character and untouched.
local function beginArenaSession(profile, debug, team)
    taPackage.arenaProfile = profile
    taPackage.arenaDebug = debug
    taPackage.arenaTeam = team
    taPackage.arenaTeamRoster = {}
    taPackage.arenaTeamSlot = 0
    -- Start deaf to any hold left over from a previous session: a stale lease
    -- would keep the gong held for a team-mate who finished healing long ago.
    taPackage.arenaTeamHealing = {}
    taPackage.arenaAnnouncedNeedsHealing = false
    taPackage.arenaSessionStartXp = taPackage.character.experience
    taPackage.arenaSessionStartTime = os.time()
    taPackage.arenaLastNtfyTime = nil
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
    taPackage.arenaCombatGen = (taPackage.arenaCombatGen or 0) + 1
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    taPackage.arenaJourney = nil
    taPackage.arenaXpCheckPending = false
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    taPackage.arenaOwnSummonPending = false
    taPackage.arenaProbePending = false
    taPackage.arenaParchedStreak = 0
    -- Unknown how many stat potions are up at session start; 0 self-corrects on
    -- the first wear-off/restock. Only matters for the train-when-clean gate.
    taPackage.arenaPotionsActive = 0
    taPackage.arenaState = "ringing"
    local startXpStr = taPackage.arenaSessionStartXp and tostring(taPackage.arenaSessionStartXp) or "unknown"
    -- Debug is the default now, so the echo flags the exception instead.
    local debugSuffix = debug and "" or " (quiet)"
    local teamSuffix = team and " (team mode)" or ""
    echo("[arena] Session started" .. teamSuffix .. debugSuffix .. ". XP: " .. startXpStr)
    scheduleArenaXpCheck()
    -- Scan the room before the first ring: another player may already have a
    -- monster in here, and we should clear it before summoning our own.
    arenaScanRoom()
end

-- The arenas are named by their number, and only by their number. The
-- spelled-out forms ("second", "third") used to be accepted alongside the
-- digits, which meant the same arena had two names in every alias, table key
-- and log line. One vocabulary is easier to type and easier to read.
local ARENA_PROFILES = { ["1"] = true, ["2"] = true, ["3"] = true }

local ARENA_ALIAS_USAGE = "usage: ring-gong-and-fight-in-arena <1|2|3> [quiet]"
local ARENA_TEAM_ALIAS_USAGE = "usage: team-fight-in-arena <1|2|3> [quiet]"

-- Parse the "<arena> [quiet]" tail of the ring-gong aliases. Order doesn't
-- matter and both words are optional; a bare alias means arena 1, which is what
-- it meant before the three per-arena aliases were folded into one.
--
-- The debug trace is ON by default: every real fight was being started with the
-- flag anyway, so the flag was pure ceremony. `quiet` turns it off; `debug` is
-- still accepted (as a no-op) so the old muscle memory keeps working.
-- Returns profile, debug — or nil plus the offending word.
local function parseArenaAliasArgs(rest)
    local profile, debug = "1", true
    for word in (rest or ""):gmatch("%S+") do
        local lowered = word:lower()
        if lowered == "debug" then
            debug = true
        elseif lowered == "quiet" then
            debug = false
        elseif ARENA_PROFILES[lowered] then
            profile = lowered
        else
            return nil, nil, word
        end
    end
    return profile, debug
end

-- Shared body of the solo and team aliases: same arguments, same class check,
-- same session — only the team flag differs.
local function startArenaFromAlias(rest, team, usage)
    local profile, debug, badWord = parseArenaAliasArgs(rest)
    if badWord then
        echo("[arena] Unknown argument '" .. badWord .. "' — " .. usage)
        return
    end
    if not getClass() then
        echo("[arena] Class unknown — run 'st' first so casters cast.")
        return
    end
    beginArenaSession(profile, debug, team)
end

local function handleArenaAlias(matches)
    startArenaFromAlias(matches[2], false, ARENA_ALIAS_USAGE)
end

createAlias("^ring-gong-and-fight-in-arena(.*)$", handleArenaAlias, { type = "regex" })

-- Short form: "rg 2", "rg 3 quiet". Same handler, same arguments.
createAlias("^rg(.*)$", handleArenaAlias, { type = "regex" })

-- Cooperative version: run this in every session that is fighting the same
-- arena together. The characters coordinate through the game itself — see the
-- roster/stagger machinery below — so no leader needs designating and no extra
-- arguments are needed beyond the usual arena selector.
--
-- Registered twice, long form and short ("tfia 2"), the way the solo alias has
-- "rg". A loop rather than a second named handler: the main chunk is within a
-- couple of names of Lua's 200-local ceiling, and the loop variable is scoped
-- to the loop instead of adding to it.
for _, teamAliasPattern in ipairs({ "^team-fight-in-arena(.*)$", "^tfia(.*)$" }) do
    createAlias(teamAliasPattern, function(matches)
        startArenaFromAlias(matches[2], true, ARENA_TEAM_ALIAS_USAGE)
    end, { type = "regex" })
end

local function stopArena()
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
    taPackage.arenaCombatGen = (taPackage.arenaCombatGen or 0) + 1
    taPackage.arenaXpCheckPending = false
    local startXp = taPackage.arenaSessionStartXp
    local currentXp = taPackage.character.experience
    local startTime = taPackage.arenaSessionStartTime
    if startXp and currentXp and startTime then
        local gained = currentXp - startXp
        local minutes = math.floor((os.time() - startTime) / 60)
        echo("[arena] Session over — +" .. gained .. " XP in " .. minutes .. " minutes.")
    end
    taPackage.arenaSessionStartXp = nil
    taPackage.arenaSessionStartTime = nil
    taPackage.arenaState = nil
    taPackage.arenaMonster = nil
    taPackage.arenaLastCmd = nil
    taPackage.arenaFleeTimerPending = false
    taPackage.arenaDebug = nil
    taPackage.arenaAttackPending = nil
    taPackage.arenaCastPending = nil
    taPackage.arenaRingPending = nil
    taPackage.arenaOwnSummonPending = nil
    taPackage.arenaProbePending = nil
    taPackage.arenaProfile = nil
    taPackage.arenaJourney = nil
    taPackage.arenaTeam = nil
    taPackage.arenaTeamRoster = nil
    taPackage.arenaTeamSlot = nil
    taPackage.arenaTeamHealing = nil
    taPackage.arenaAnnouncedNeedsHealing = nil
    taPackage.arenaParchedStreak = 0
    taPackage.needsPotions = nil
    taPackage.arenaPotionsActive = nil
    -- Cancel any in-flight exit retry loop (a manual stop or stop-all-scripts
    -- means halt everything). arenaEmergencyExit calls stopArena first and
    -- re-arms this afterward, so its own loop survives.
    taPackage.exitGamePending = false
    -- Bump the ring and journey generations so any in-flight pump tick no-ops.
    taPackage.arenaRingGen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    echo("[arena] Stopped.")
end
taPackage.stopArena = stopArena

-- Leave the game with "x", and keep re-sending it until the game confirms.
--
-- "x" is treated like a move, so if we're still physically exhausted from the
-- last swing the game rejects it ("Sorry, you'll have to rest a while before you
-- can move.") — and a single unanswered "x" leaves the character sitting in the
-- game taking damage, which is the exact fate every caller of this is trying to
-- avoid. So re-send "x" every 2s until the game confirms with "Exiting
-- Tele-Arena...". A generation guard cancels an older loop if a new exit (or a
-- restarted run) supersedes it.
local function exitGameWithRetry()
    local gen = (taPackage.exitGameGen or 0) + 1
    taPackage.exitGameGen = gen
    taPackage.exitGamePending = true
    local function tryExit()
        if not taPackage.exitGamePending or taPackage.exitGameGen ~= gen then return end
        send("x")
        createTimer(2000, tryExit, { repeating = false })
    end
    tryExit()
end
taPackage.exitGameWithRetry = exitGameWithRetry

-- =========================================================================
-- The nightly shutdown
-- =========================================================================
--
-- The BBS goes down every night for an "auto-cleanup", and warns first:
--
--     ***
--     Sorry to interrupt here, but the BBS will be shutting
--     down in 5 minutes for the nightly "auto-cleanup"
--     process.  Please finish up and log off... thank you!
--
-- repeated at 5, 4, 3, 2 and 1 minutes.
--
-- Being cut off mid-game is not free: carried gold does not survive it. On the
-- night of 2026-08-15 Kerhak was handed 10,617 gold across 13 handovers and
-- banked 5,500 of it, leaving ~5,100 on his person when the connection dropped
-- at the last warning -- and it was not there in the morning
-- (logs/session-kerhak-2026-08-15T23-39-59.log ends at line 1679, mid-warning,
-- with no exit). Leaving with "x" saves the character properly.
--
-- We answer the FIRST warning, five minutes out, because "x" is treated like a
-- move and gets refused while the physical cooldown runs -- exitGameWithRetry
-- re-sends every 2s until the game confirms, and five minutes is a comfortable
-- budget for that. Waiting for the 1-minute warning would not be.
--
-- Only the first line is matched: the second carries the countdown ("5 minutes"
-- / "1 minute") and so changes, while this one is identical every time. Fired
-- once per session -- the warning repeats five times and the retry loop is
-- already doing the work.
--
-- Not gated on any script being active. A clean exit is right whatever the
-- character was doing, including nothing.
createTrigger("^Sorry to interrupt here, but the BBS will be shutting$", function()
    if taPackage.shutdownExitSent then return end
    taPackage.shutdownExitSent = true
    echo("[shutdown] BBS closing for nightly maintenance — stopping everything"
        .. " and leaving the game (x) so the character is saved.")
    sendNtfy("Nightly shutdown",
        "The BBS is closing. Scripts stopped and " ..
        (taPackage.character.name or "the character") .. " is leaving the game"
        .. " so nothing carried is lost.")
    -- Stop first: a walk or a fight still issuing commands fights the exit, and
    -- whatever it was doing is about to be interrupted anyway. Through the alias
    -- so a script added later is covered without touching this.
    if runCommand then runCommand("stop-all-scripts") end
    exitGameWithRetry()
end, { type = "regex" })

-- Arena mode's last-resort escape hatch. A wedged navigation walk or an
-- unserviceable thirst/hunger loop would otherwise grind the character to death
-- (see something-went-wrong.log). Leaving the game with "x" preserves the
-- character and stops all damage; tear the normal arena state down first so no
-- stale combat timer re-arms, then keep only the exit retry loop alive.
local function arenaEmergencyExit(reason)
    echo("[arena] " .. reason .. " — leaving the game (x).")
    stopArena()
    exitGameWithRetry()
end

-- The game acknowledges a successful "x" with this line before dropping to the
-- BBS "<< hit return >>" prompt — the character is out of the game and safe from
-- damage. Clear the pending flag so exitGameWithRetry's retry loop stops.
createTrigger("^Exiting Tele-Arena\\.\\.\\.$", function()
    taPackage.exitGamePending = false
end, { type = "regex" })

-- =========================================================================
-- Death
-- =========================================================================
--
-- A general facility, not an arena or gold-farming one. Any script can ask
-- whether the character has just been killed:
--
--   taPackage.died     true from the killing blow until the next entry into
--                      the game. READ it; do not clear it -- clearing hides the
--                      death from every other reader.
--   taPackage.diedAt   millisecond clock reading of the killing blow, for
--                      anything that wants to reason about how long ago.
--
-- Every long-running script is stopped automatically when it fires (through the
-- stop-all-scripts alias, so a script added later is covered the moment it is
-- registered there). A script that needs to do something of its own about a
-- death -- refuse to restart a loop, say -- reads the flag at whatever point it
-- notices, rather than racing to hook the line itself.
--
-- The flag is cleared on "Entering Tele-Arena...", i.e. once a character is in
-- the game again, which ends the episode for every reader at the same moment.

-- This is the one line the game prints that means it, and it arrives just before
-- the revive:
--
--     The flame giant exhaled a blast of flame at you for 394 damage!
--     As the final blow strikes your body you fall unconscious.
--     You awaken after an unknown amount of time...
--     You're in the temple.
--
-- (logs/session-kerhak-2026-08-09T14-48-21.log, lines 3243-3246.)
--
-- Detecting it matters because a death is nearly invisible to a running script.
-- Carrying a soulstone you wake at the temple, alive and four rooms from where
-- every state machine believes you are standing; without one you land on the BBS
-- menu. Either way the script keeps issuing arena commands into a world that has
-- moved on, which is exactly what happened during several deaths last week --
-- the scripts "just kept running even though the character was dead".
--
-- The revive line alone cannot carry this: a suicide prints it too, and the
-- gold-farming loop deliberately hangs its restart off it. Only this line
-- separates the two, so it is what sets the flag that tells them apart.
--
-- Stopping everything is the right response even though the character may be
-- alive: whatever it was doing is void, its gear and gold are gone, and quietly
-- carrying on turns one bad round into an unattended hour of nonsense.
createTrigger("^As the final blow strikes your body you fall unconscious\\.$", function()
    taPackage.died = true
    taPackage.diedAt = nowMillis()
    -- echo, not cecho: a death has to be in the session log, since the whole
    -- problem is noticing it after the fact.
    echo("[death] KILLED — stopping every script. Gear and gold are gone; you"
        .. " wake at the temple with a soulstone, or at the BBS menu without one.")
    sendNtfy("Character killed",
        (taPackage.character.name or "The character") .. " was killed. All scripts"
        .. " stopped. Equipment and carried gold are lost.")
    -- Reuse the alias rather than reimplementing its teardown, so a script added
    -- later is covered here the moment it is added there.
    if runCommand then
        runCommand("stop-all-scripts")
    else
        cecho("yellow", "[death] this baud has no runCommand — type stop-all-scripts yourself")
    end
end, { type = "regex" })

-- The arena loop only stays alive while it can pay the temple for healing and
-- the shop for potions. If our gold ever falls below this floor, the next such
-- trip is one bad roll away from a "can't afford" wedge that grinds the
-- character to death, so bail out of the game now while the balance is still
-- positive. Assigns to the local forward-declared up by setGold so every gold
-- change is checked; a nil balance (not yet read) is left alone. Returns true
-- when it triggered the exit.
local ARENA_MIN_GOLD = 100
function checkArenaGoldFloor()
    if not taPackage.arenaState then return false end
    local gold = getGold()
    if gold and gold < ARENA_MIN_GOLD then
        arenaEmergencyExit("Gold below " .. ARENA_MIN_GOLD .. " (" .. gold
            .. ") — can't sustain healing/potions")
        return true
    end
    return false
end

-- Count consecutive thirst/hunger ticks that go unrelieved. A tick means the
-- game is draining 1 HP; if we rack up ARENA_PARCHED_LIMIT in a row without
-- ringing the gong or buying a drink/meal (both reset the streak), the errand
-- loop is wedged and standing here just dies slowly — bail out of the game
-- instead. Returns true when it triggered the exit so the caller stops
-- processing the tick.
local function arenaCheckParched()
    taPackage.arenaParchedStreak = (taPackage.arenaParchedStreak or 0) + 1
    if taPackage.arenaParchedStreak >= ARENA_PARCHED_LIMIT then
        arenaEmergencyExit("Thirsty/hungry " .. taPackage.arenaParchedStreak
            .. "x with no relief (navigation likely stuck)")
        return true
    end
    return false
end

-- One stop for every arena: stopArena() clears the profile along with the rest
-- of the session, so there was never anything per-arena about stopping.
createAlias("^stop-arena-fight$", function()
    stopArena()
end, { type = "regex" })

-- Our own gong ring is confirmed by this line; the monster we summoned arrives
-- on the very next "enters the arena" line. The arena is shared, so other
-- players' rings ("Castor just rang the great gong!") also spawn monsters — we
-- must only adopt the one that followed *our* ring. (See the cascade in
-- logs/session-pollux-2026-06-28T12-33-36.log, where Pollux latched onto
-- Castor's spawns and piled up monsters it couldn't see.)
createTrigger("^You just rang the great gong!$", function()
    -- The gong's acceptance instant, which is what a future reckoning would have
    -- to count from — the equivalent of arenaLastSwingAt for melee. Stamped
    -- before the state gate below so the measurement survives the paths that
    -- return early.
    arenaDebugEcho("ring-accepted  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
        .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
    taPackage.arenaLastRingAt = nowMillis()
    -- The fight loop is alive again — clear any accumulated thirst/hunger streak
    -- so a later dry spell starts counting fresh (a bar round-trip ends with a
    -- ring back in the arena, so this is what resets the streak between trips).
    taPackage.arenaParchedStreak = 0
    if taPackage.arenaState ~= "ringing" then return end
    taPackage.arenaOwnSummonPending = true
end, { type = "regex" })

-- A team-mate is escaping at low HP and wants the gong held (see
-- arenaTeamHealingHolder). We only ever hear other characters: the game shows
-- the speaker "-- Message sent --" rather than echoing their own line back, so
-- these can't be tripped by our own announcements.
--
-- (\\S+) rather than (.+) for the name is deliberate. Names are a single word,
-- and the loose form would also swallow the group-chat channel's
-- "From <leader> (to group): ..." lines, which carry remote commands and belong
-- to their own trigger further down.
createTrigger("^From (\\S+): " .. arenaTeamHeal.NEED_MSG .. "$", function(matches)
    if not taPackage.arenaTeam then return end
    arenaTeamHeal.leases()[matches[2]:lower()] = os.time()
    arenaDebugEcho("team-heal-hold-" .. matches[2])
end, { type = "regex" })

-- ...and they made it back. Clearing the lease early is the normal path; the
-- expiry in arenaTeamHealingHolder is only the backstop for an all-clear that
-- never comes.
createTrigger("^From (\\S+): " .. arenaTeamHeal.HEALED_MSG .. "$", function(matches)
    if not taPackage.arenaTeam then return end
    arenaTeamHeal.leases()[matches[2]:lower()] = nil
    arenaDebugEcho("team-heal-release-" .. matches[2])
end, { type = "regex" })

-- Somebody else in the arena rang. Solo, that is none of our business — the
-- trigger below adopts only the monster that followed our OWN ring. In team
-- mode it is the signal the whole design rests on: the game has just told every
-- client, in one serialized broadcast, that a summon is on its way, so anyone
-- still waiting for a turn must stand down or we get a second monster.
--
-- Bumping the ring generation is what calls off our pending ring (see
-- arenaTeamRing) and any in-flight scan. That leaves nothing armed, so re-arm
-- one pump tick: if the summon never arrives — the ringer bounced off "still
-- physically exhausted", or walked out — we go back to probing rather than
-- standing in the arena forever waiting for a monster that is not coming.
createTrigger("^(.+) just rang the great gong!$", function(matches)
    -- "You just rang the great gong!" is our own ring, owned by the trigger
    -- above; this pattern matches it too, so let that one keep it.
    if matches[2] == "You" then return end
    if not taPackage.arenaTeam then return end
    if taPackage.arenaState ~= "ringing" then return end
    arenaDebugEcho("team-ring-yielded-to-" .. matches[2])
    local gen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaRingGen = gen
    taPackage.arenaRingPending = false
    -- Abandon any brief still arriving. The ring can land in the middle of our
    -- own probe, and the floor line that ends that brief is what drives the ring
    -- decision — so leaving the probe live would walk us straight into ringing on
    -- top of the summon we just stood down for. The re-armed pump probes again in
    -- a moment, by which time the monster is here to be adopted.
    taPackage.arenaProbePending = false
    createTimer(ARENA_RING_RETRY_MS, function()
        if taPackage.arenaState == "ringing" and (taPackage.arenaRingGen or 0) == gen then
            arenaScanRoom()
        end
    end, { repeating = false })
end, { type = "regex" })

-- Adopt a freshly-spawned monster. Solo, only the one that followed *our* ring
-- (arenaOwnSummonPending): without that guard a monster summoned by another
-- player sharing the arena gets adopted and our real fight is forgotten.
--
-- Team mode wants exactly the opposite, and that is the point of it — one
-- monster in the arena and everybody swinging at it, whoever summoned it. So
-- there is no "was it ours" test: any spawn arriving while we are looking for
-- something to fight is ours to fight. Not tracking whose ring it was also means
-- a broadcast we somehow missed cannot leave us idle next to a live monster.
--
-- The arenas spawn with different flavor text — the first through a dungeon
-- gate, the second in a puff of smoke — but the adoption rule is identical.
local function arenaAdoptSummon(name)
    if taPackage.arenaState ~= "ringing" then return end
    if not taPackage.arenaTeam and not taPackage.arenaOwnSummonPending then return end
    taPackage.arenaOwnSummonPending = false
    arenaEngage(name)
end

createTrigger("^An? (.+) enters the arena through the dungeon gate!$", function(matches)
    arenaAdoptSummon(matches[2])
end, { type = "regex" })

-- Second arena: the summoned monster materializes instead of walking in. The
-- smoke's color varies, so match any word(s) before "smoke".
createTrigger("^An? (.+) appears in a puff of .+ smoke!$", function(matches)
    arenaAdoptSummon(matches[2])
end, { type = "regex" })

-- Response to the bare-return probe from arenaScanRoom: the arena brief's
-- occupant line. If a monster is already here, engage it instead of ringing —
-- ringing now would stack a second monster on us. An empty room prints
-- "There is nobody here." (no monster), so we ring.
createTrigger("^There is (.+) here\\.$", function(matches)
    if not taPackage.arenaProbePending then return end
    taPackage.arenaProbePending = false
    if taPackage.arenaState ~= "ringing" then return end
    local monster = firstArenaMonster(matches[2])
    if monster then
        arenaEngage(monster)
    else
        arenaRingOrErrand()
    end
end, { type = "regex" })

-- Team mode's roster: who else is standing in the arena right now. The brief the
-- probe already prints names them on their own line, between the monsters and
-- the floor line:
--
--     There is a stygian dragon here.        <- monsters (see the trigger above)
--     Tojolias and Teekywiki are here.       <- this line; we are never in it
--     There is nothing on the floor.         <- terminator (see the trigger below)
--
-- so a ring order can be derived from data we are already fetching, with no
-- designated leader and nothing to configure (see arenaTeamRing).
--
-- Two triggers rather than one with an "is|are" alternation: baud's patterns are
-- translated to Lua patterns for the tests, and Lua has no alternation. Being
-- anchored on " is here.$" / " are here.$" is also what keeps the brief's other
-- lines out of the roster — "There is nobody here." ends in "nobody here.", and
-- the monster line in "<monster> here.", so neither can match.
local function arenaCaptureRoster(blob)
    -- Only while a probe is outstanding: this is the arena brief we asked for,
    -- not a room we happen to be walking through.
    if not taPackage.arenaTeam then return end
    if not taPackage.arenaProbePending then return end
    -- "A", "A and B", "A, B, and C" — flatten the conjunction to a plain
    -- comma-separated list, then split. The Oxford comma leaves an empty field
    -- behind ("B, and C" -> "B, , C"), which the emptiness check drops.
    local roster = {}
    for name in (blob:gsub(" and ", ", ") .. ","):gmatch("%s*(.-)%s*,") do
        if name ~= "" then roster[#roster + 1] = name end
    end
    taPackage.arenaTeamRoster = roster
end

createTrigger("^(.+) is here\\.$", function(matches)
    arenaCaptureRoster(matches[2])
end, { type = "regex" })

createTrigger("^(.+) are here\\.$", function(matches)
    arenaCaptureRoster(matches[2])
end, { type = "regex" })

-- The "There is nobody here." occupant line only appears when the room is
-- *completely* empty. When another player is present, their "Pollux is here."
-- line takes the occupant slot and the "nobody" line is omitted — so the
-- occupant trigger above never fires and the probe would hang forever (both
-- characters deadlock; see logs/session-castor-2026-06-28T15-48-05.log). The
-- floor line always ends the brief, whoever is here, so use it as the
-- definitive terminator: if the probe is still pending when it arrives, no
-- monster was listed and the room is clear of monsters, so ring.
createTrigger("^There .+ on the floor\\.$", function()
    if not taPackage.arenaProbePending then return end
    taPackage.arenaProbePending = false
    if taPackage.arenaState ~= "ringing" then return end
    arenaRingOrErrand()
end, { type = "regex" })

-- Hit, miss and dodge all mean the same thing to the physical clock: the game
-- ACCEPTED a swing and spent a tick of the burst. Stamping the time here is what
-- lets the exhaustion handler below reckon the recovery from the right instant.
local function arenaSwingAccepted(label)
    taPackage.arenaAttackPending = false
    taPackage.arenaLastSwingAt = nowMillis()
    arenaDebugEcho(label)
    if not checkFleeArena() then arenaAttack() end
end

createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("our-hit")
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("our-miss")
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("monster-dodge")
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    -- Only react to the death of the monster we are actually fighting. The arena
    -- is shared, so another player's kill prints this same line; the name match
    -- is what tells our kill from theirs. This runs BEFORE any state gate on
    -- purpose: clearing the dead monster is correct in every state, and it must
    -- happen even when the kill lands after an errand has already flipped us out
    -- of "fighting". A thirst/hunger tick between our swing and its resolution
    -- calls departForTavern → state "tavern" while arenaMonster is still set; if
    -- the swing then kills the monster, an earlier state guard here dropped the
    -- death line, arenaMonster stayed set, and the errand's return path
    -- (arenaResumeInCombat) resumed swinging at a corpse forever — never ringing
    -- the gong (see something-went-wrong-focused.log).
    if matches[2] ~= taPackage.arenaMonster then return end
    taPackage.arenaMonster = nil
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    -- Follow-up actions (ring for a fresh monster / go train) only make sense
    -- while actively fighting. If the monster died during an errand trip, we
    -- just clear it here; arenaResumeInCombat will ring on arrival home.
    if taPackage.arenaState == "fighting" and not checkFleeArena() then
        -- Train if a level is owed and our potions have lapsed; otherwise ring
        -- for the next monster. While a level is owed but potions are still
        -- active, arenaTryTrain returns false, so we keep fighting — which both
        -- banks more XP and wears the potions down toward the safe-to-train point.
        if not arenaTryTrain() then
            taPackage.arenaState = "ringing"
            taPackage.arenaRingPending = false
            arenaScanRoom()
        end
    end
end, { type = "regex" })

-- Self-healing net for a lost target. If we ever end up swinging at a monster
-- that isn't here — a kill dropped in a race window, another player's move that
-- displaced it, or any stale arenaMonster — the game answers our attack with
-- "Sorry, you don't see "troll" nearby." Nothing else re-drives the loop after
-- that line (no monster hit/miss/death follows a whiffed attack), so without
-- this the run wedges: it keeps re-attacking a ghost and never rings. Treat it
-- as "the monster is gone": clear it and ring for a fresh one. See
-- something-went-wrong-focused.log.
createTrigger("^Sorry, you don't see \".+\" nearby\\.$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("target-gone")
    taPackage.arenaMonster = nil
    taPackage.arenaState = "ringing"
    taPackage.arenaRingPending = false
    arenaScanRoom()
end, { type = "regex" })

createTrigger("^The .+ attacked you .+ for \\d+ damage!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-hit")
    if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The .+ attacked you, but .+ glanced off your armor!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-glance")
    arenaAttack()
end, { type = "regex" })

createTrigger("^The .+'s? .+ misses? you!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-miss")
    arenaAttack()
end, { type = "regex" })

createTrigger("^You barely dodge the .+'s attack!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("player-dodge")
    arenaAttack()
end, { type = "regex" })

-- Every arena leg is a paced journey now, so a room line means one thing: a
-- step of the walk in progress. The room-name navigation that used to sit here
-- -- react to a named waypoint, send the next direction at once -- is gone with
-- the first arena's step lists, and with it the two faults it carried: no
-- pacing, and no trip recovery. A room line with no journey running is a no-op.
createTrigger("^You're in the (.+)\\.$", function(matches)
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- Paced routes pass through "You're on a path." rooms, which the "in the"
-- trigger above never matches. Feed them to the walk handler too so every step
-- advances. Only meaningful mid-journey; otherwise a no-op.
createTrigger("^You're on a (.+)\\.$", function(matches)
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- Paced routes also thread through generically-named rooms whose brief takes the
-- article "a"/"an" — the third arena's temple/bar/shop/training legs (and every
-- reverse) each hop through a chain of "You're in an underground plaza." rooms.
-- The "in the" trigger above only matches "the", so without this the paced walk
-- never counts those arrivals and wedges after its first step: a real flee
-- fired "sw", landed in "an underground plaza", and then just sat there because
-- the journey never advanced (see the 2026-07-18 third-arena flee log). Feed
-- them to the walk handler too; inert unless a paced journey is active, so the
-- first arena's name-based navigation is untouched.
createTrigger("^You're in an? (.+)\\.$", function(matches)
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- Moving between rooms too quickly makes the character trip and fall. No room
-- line follows, so the step-driven walk above would stall forever waiting to
-- enter a room it never does. Re-send the current step after a longer pause to
-- recover the walk (and back off the pace). The move genuinely failed, so no
-- room line is in flight — the resend cannot double-move us. The generation
-- guard drops the retry if the session stops or a new journey starts first.
createTrigger("^In your haste, you trip and fall!$", function()
    if not taPackage.arenaJourney then return end
    local gen = taPackage.arenaJourneyGen or 0
    createTimer(ARENA_TRIP_RETRY_MS, function()
        if taPackage.arenaState and (taPackage.arenaJourneyGen or 0) == gen then
            arenaJourneyResendStep()
        end
    end, { repeating = false })
end, { type = "regex" })

createTrigger("^You're thirsty\\.$", function()
    setCharacterStatus("Thirsty")
    if not taPackage.arenaState then return end
    if arenaCheckParched() then return end
    taPackage.needsDrinks = true
    if arenaCanDepartNow() then
        departForTavern()
    else
        echo("[arena] Thirsty — will buy drinks at next tavern visit.")
    end
end, { type = "regex" })

createTrigger("^You're hungry\\.$", function()
    setCharacterStatus("Hungry")
    if not taPackage.arenaState then return end
    if arenaCheckParched() then return end
    taPackage.needsMeal = true
    if arenaCanDepartNow() then
        departForTavern()
    else
        echo("[arena] Hungry — will buy a meal at next tavern visit.")
    end
end, { type = "regex" })

-- A strength/agility potion wearing off. The line is identical for rowan and
-- hyssop, so it fires once per potion — we can't tell which lapsed and refresh
-- both. Like thirst/hunger: leave for the shop now if we're fighting or
-- ringing, otherwise flag it and the arrival handler makes the trip on the way
-- back. A second wear-off line mid-trip just re-sets the flag (idempotent).
createTrigger("^An odd tingling sensation washes over you briefly!$", function()
    if not taPackage.arenaState then return end
    -- One of our two stat potions lapsed. Track it so we know when they are all
    -- gone: the training hall refuses us while any is active (see arenaTryTrain).
    local active = math.max((taPackage.arenaPotionsActive or 0) - 1, 0)
    taPackage.arenaPotionsActive = active
    if checkTrainingNeeded() then
        -- A level is owed. We are deliberately letting the potions wear off so
        -- the hall will accept us — do NOT restock. The ring/kill decision points
        -- send us to train once this count reaches 0.
        echo("[arena] Potion lapsed (" .. active
            .. " still active) — draining before training.")
        return
    end
    -- A gold-farming run never restocks, whatever put a potion in the character.
    -- Its arena session is a sprint to one level, not an open-ended grind, so a
    -- fresh potion can only push the finish line out: the training hall refuses
    -- a tainted character, and the taint measured 22m 24s
    -- (logs/session-garbageman-2026-08-15T21-52-26.log) -- comfortably longer
    -- than the whole fight it would be extending.
    --
    -- The loop no longer buys potions at all (see ta_create.lua for why), so
    -- this now guards the leftovers: a potion drunk by hand, or a session that
    -- was still carrying a round when the change landed.
    if taPackage.goldFarming then
        echo("[arena] Potion lapsed (" .. active
            .. " still active) — gold-farming run, not restocking.")
        return
    end
    taPackage.needsPotions = true
    if arenaCanDepartNow() then
        departForShop()
    else
        echo("[arena] A potion wore off — will restock at next shop visit.")
    end
end, { type = "regex" })

-- How long to wait for the character sheet we ask for after training before
-- pushing the level-up notification without the HP/MP figures. The sheet comes
-- straight back; this only has to outlast a hiccup.
local LEVEL_UP_SHEET_WAIT_MS = 5000

-- Push the held "Leveled Up!" notification, filling in the stat gains if the
-- character sheet we asked for has landed. Called from the Vitality trigger (the
-- last of the two lines we're waiting on) and from a timeout, whichever comes
-- first; whoever gets there clears the pending record so the other is a no-op.
--
-- Global rather than local because the Vitality trigger is registered ~3000
-- lines above this point and can't see a local declared down here. It only ever
-- runs after the chunk has finished loading, so the name is always bound by then.
function flushLevelUpNotification()
    local pending = taPackage.levelUpPush
    if not pending then return end
    taPackage.levelUpPush = nil

    -- "434" alone doesn't say how good the level was; "gain of 23" does. We can
    -- only show it if we knew the old maximum (we may never have polled `st`).
    local function gain(before, after, unit)
        if not before then return "" end
        return ", gain of " .. formatWithCommas(after - before) .. " " .. unit
    end

    local lines = { pending.headline }
    local hp = taPackage.character.vitalityMax
    if hp then
        lines[#lines + 1] = "- New HP: " .. formatWithCommas(hp) .. gain(pending.hpBefore, hp, "HP")
    end
    -- Only spell casters have a mana pool; for everyone else the sheet says
    -- "0 / 0" every level and the line would be noise.
    local mp = taPackage.character.manaMax
    if mp and mp > 0 then
        lines[#lines + 1] = "- New MP: " .. formatWithCommas(mp) .. gain(pending.mpBefore, mp, "MP")
    end
    lines[#lines + 1] = "- Training cost: " .. formatWithCommas(pending.cost) .. " gold"
    lines[#lines + 1] = "- Gold: " .. (pending.gold and formatWithCommas(pending.gold) or "?")
    sendNtfy("Leveled Up!", table.concat(lines, "\n"), true)
end

-- A fresh Vitality line arrived while a level-up push is held. Answered by the
-- Vitality trigger for *every* sheet, so ignore one whose maximum still reads
-- pre-level: that's an unrelated `st` (e.g. tavern mode's HP heartbeat) that was
-- already in flight when we trained, and flushing on it would report no gain.
-- The timeout still pushes if our own sheet somehow never shows up.
function noticeLevelUpStats()
    local pending = taPackage.levelUpPush
    if not pending then return end
    if pending.hpBefore and taPackage.character.vitalityMax == pending.hpBefore then return end
    flushLevelUpNotification()
end

-- Guild-hall confirmation that a training session succeeded (its reply to `buy
-- training`; the message runs three lines, we key on the first). Do the things
-- that only make sense once we've actually leveled:
--   * Bank the level locally. The game's own `Level:` line lags until the next
--     status poll, and a stale level would keep checkTrainingNeeded() true and
--     re-trigger a training trip on the next kill.
--   * Charge the fee. Training costs (next level x 5) gold — see help/TUTORIAL
--     ("level 2 costs 10 gold") — and the success line carries no crown amount to
--     parse, so we compute it from the level we just reached.
--   * Re-buy the stat potions we drained to be allowed to train — unless another
--     banked level is still owed, in which case keep draining and train again.
createTrigger("^After a rigorous mental and physical training session, you managed to blend$", function()
    -- Usually an arena run's doing, but the train-and-exit watch drives the same
    -- purchase by hand, and the level bank, the fee and the push are wanted either
    -- way — without this the hand-driven training would silently notify nobody.
    if not (taPackage.arenaState or taPackage.trainWatch) then return end
    local lvl = getLevel()
    if lvl then
        local newLevel = lvl + 1
        setLevel(newLevel)
        local cost = newLevel * 5
        setGold((getGold() or 0) - cost)
        taPackage.db.recordService("training", "guild", cost)
        echo("[arena] Trained to level " .. newLevel .. " (" .. cost .. " gold).")
        -- Off-screen heads-up that the drain-then-train actually completed. This
        -- fires on the confirmed level-up (distinct from checkLevelUpNotification's
        -- "Time to Level Up!", which fires earlier when the XP threshold is crossed).
        --
        -- A level always raises Vitality (and Mana for a caster), but the hall's
        -- message carries neither figure and our own maxima are whatever the last
        -- `st` said — i.e. pre-level. So hold the push, ask for a fresh sheet, and
        -- assemble it when the new Vitality line lands. Mana is printed just above
        -- Vitality on the sheet, so both are current by the time we flush.
        taPackage.levelUpPush = {
            headline = "[" .. (taPackage.character.name or "?") .. "] trained to level "
                .. newLevel .. "!",
            cost = cost,
            gold = getGold(),
            hpBefore = taPackage.character.vitalityMax,
            mpBefore = taPackage.character.manaMax,
        }
        send("st")
        createTimer(LEVEL_UP_SHEET_WAIT_MS, flushLevelUpNotification, { repeating = false })
    end
    -- Restocking is an arena-loop concern only: outside a run there is no errand
    -- trip to hang the flag on, and leaving it set would send the next run to the
    -- shop for no reason.
    if taPackage.arenaState and not checkTrainingNeeded() then
        taPackage.needsPotions = true
    end
end, { type = "regex" })

-- Backstop for a mistimed training trip. We normally reach the hall only once
-- arenaPotionsActive has drained to 0, but if that count was off (e.g. a potion
-- we didn't drink was still active) the hall refuses us with this line. We did
-- NOT level and were not charged (the success trigger above never fired), so just
-- force the drain count positive: the ring loop keeps fighting until the next
-- wear-off and then retries training.
createTrigger("^Your mind and body must be whole and untainted before you may train\\.$", function()
    if not taPackage.arenaState then return end
    taPackage.arenaPotionsActive = math.max(taPackage.arenaPotionsActive or 0, 1)
    echo("[arena] Training refused — still potion-tainted; fighting until it wears off.")
end, { type = "regex" })

createTrigger("^The priests heal all your wounds for \\d+ crowns\\.$", function(matches)
    if taPackage.arenaState ~= "healing" then return end
    -- Always walk back to the arena from the temple. If we are also hungry or
    -- thirsty, the arrival handler sets out for the bar as a separate round
    -- trip rather than routing temple->bar directly -- arriving home is the one
    -- place errands get dispatched, so every errand starts from there.
    local nav = arenaNav()
    taPackage.arenaState = "returning"
    arenaJourneyStart(nav.fromTemple, nav.arenaRoom, nav.templeRoom)
end, { type = "regex" })

-- =========================================================================
-- hang-around-in-tavern
--
-- A standalone "idle in a tavern" mode, independent of the arena scripts. It
-- parks the character in a bar and keeps it fed and watered: buy a meal when
-- hungry, a drink when thirsty. Two things end it, both by leaving the game
-- with "x": HP falling below half (something is hurting us faster than we can
-- recover — e.g. we ran out of money and hunger/thirst is grinding us down),
-- or a purchase failing for lack of money (the direct signal for the same).
-- =========================================================================

local TAVERN_HP_FRACTION = 0.5        -- exit if current HP drops below this share of max
local TAVERN_STATUS_POLL_MS = 600000 -- low-frequency HP heartbeat (10 min); see scheduleTavernPoll

local function isTavernRoom(room)
    if not room then return false end
    local r = room:lower()
    return r:find("tavern") ~= nil or r:find("bar") ~= nil
end

-- Leave the game and stop the mode. Bumping the generation invalidates any
-- poll timer still in flight so it can't re-arm after we've quit.
local function tavernExitGame(reason)
    echo("[tavern] " .. reason .. " — leaving the game.")
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    send("x")
end

-- Hunger/thirst damage is NOT silent: the game prints "You're hungry." /
-- "You're thirsty." on every 1-HP tick, and the triggers below react to each by
-- buying food/drink. The real "we're being ground down" case — out of money — is
-- caught directly by the "You can't afford ..." trigger, which exits at once. So
-- this poll isn't the primary safety mechanism; it's just an occasional HP
-- heartbeat (10 min) to catch anything unforeseen. The Vitality trigger below
-- reads the fresh line and decides whether to bail.
local function scheduleTavernPoll()
    local gen = taPackage.tavernModeGen
    createTimer(TAVERN_STATUS_POLL_MS, function()
        if not taPackage.tavernMode or taPackage.tavernModeGen ~= gen then return end
        send("st")
        scheduleTavernPoll()
    end, { repeating = false })
end

-- Stop tavern idle mode without leaving the game. Returns true if it was
-- running. Bumping the generation invalidates any poll timer in flight so it
-- can't re-arm. Shared by stop-hang-around-in-tavern and stop-all-scripts.
local function stopTavernMode()
    if not taPackage.tavernMode then return false end
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    return true
end

createAlias("^hang-around-in-tavern$", function()
    -- Judge the room from the name the last arrival brief left behind. Don't
    -- send a `look` first: send() is fire-and-forget, so its reply lands long
    -- after this function has returned, and a look's opening line is
    -- deliberately not treated as an arrival anyway (see
    -- handleRoomEntryUnlessLooking) -- it could never set currentRoom.
    local room = taPackage.currentRoom
    if not isTavernRoom(room) then
        echo("[tavern] Not in a tavern/bar (room: " .. (room or "unknown")
            .. "). Walk into one first, then run hang-around-in-tavern.")
        return
    end
    taPackage.tavernMode = true
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    echo("[tavern] Hanging around in the " .. room
        .. ". Buying meals/drinks as needed; will leave (x) if HP drops below 50% or money runs out.")
    send("st") -- prime HP tracking so the first poll isn't the first reading
    scheduleTavernPoll()
end, { type = "regex" })

createAlias("^stop-hang-around-in-tavern$", function()
    if stopTavernMode() then
        echo("[tavern] Stopped hanging around (still in the game).")
    else
        echo("[tavern] Not currently hanging around.")
    end
end, { type = "regex" })

createTrigger("^You're hungry\\.$", function()
    if not taPackage.tavernMode then return end
    send("buy meal")
end, { type = "regex" })

createTrigger("^You're thirsty\\.$", function()
    if not taPackage.tavernMode then return end
    send("buy drink")
end, { type = "regex" })

-- A purchase we asked for was refused for lack of funds. In tavern mode the only
-- things we buy are meals and drinks ("You can't afford drink.", "... a meal.");
-- in an arena run it's healing ("You can't afford healing.") and potions
-- ("... a rowan potion.", "... a hyssop potion."). Either way an affordability
-- failure is ours and means we're broke: quit at once before hunger/thirst or
-- the next unhealed fight grinds the character down.
createTrigger("^You can't afford (.+)\\.$", function(matches)
    if taPackage.tavernMode then
        tavernExitGame("Out of money (can't afford " .. matches[2] .. ")")
    elseif taPackage.arenaState then
        arenaEmergencyExit("Out of money (can't afford " .. matches[2] .. ")")
    end
end, { type = "regex" })

-- A fresh Vitality reading — from our poll, or any status check. If we've
-- dropped below half health while idling, leave the game.
createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    if not taPackage.tavernMode then return end
    local current = tonumber(matches[2])
    local max = tonumber(matches[3])
    if current and max and max > 0 and current < max * TAVERN_HP_FRACTION then
        tavernExitGame("HP below 50% (" .. current .. "/" .. max .. ")")
    end
end, { type = "regex" })

-- Any walk-out that gets blocked by a monster — fleeing to the temple, or an
-- errand run to the bar ("tavern") or magic shop ("potions") — retries the same
-- step until a between-attacks window opens. arenaCanDepartNow now stops us from
-- departing into an in-flight summon, so this is a backstop for the case where a
-- monster arrives after we've stepped out (e.g. another player's ring on the
-- shared gong). Omitting "potions" here is exactly what left problem.log wedged.
createTrigger("^You cannot leave in the heat of battle!$", function()
    local st = taPackage.arenaState
    if st ~= "fleeing" and st ~= "tavern" and st ~= "potions" then return end
    if taPackage.arenaFleeTimerPending then return end
    taPackage.arenaFleeTimerPending = true
    local gen = taPackage.arenaRetryGeneration or 0
    -- Retry the exact step that was blocked, not a hardcoded "w": the second
    -- arena's first step out is "s". arenaLastCmd is the blocked command.
    local cmd = taPackage.arenaLastCmd or "w"
    createTimer(2000, function()
        taPackage.arenaFleeTimerPending = false
        if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
            arenaSend(cmd)
        end
    end, { repeating = false })
end, { type = "regex" })

-- A paced journey only issues moves from a fixed route, so a "no exit" reply means
-- the walk has lost sync with the character's true position. No room line follows,
-- so the step index can never advance — the walk wedges forever (something-went-wrong
-- .log:1899, where the character then slowly died of thirst). This is unrecoverable
-- in-script; bail out of the game before thirst/hunger grinds us down. Scoped to an
-- active journey so a stray manual move never trips it.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    if not taPackage.arenaState or not taPackage.arenaJourney then return end
    arenaEmergencyExit("Navigation lost (no exit on a journey step)")
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function(matches)
    if not taPackage.arenaState then return end
    local cmd = taPackage.arenaLastCmd
    local gen = taPackage.arenaRetryGeneration or 0
    if cmd then
        -- In a flee we're taking hits every round, so poll for the rest clock to
        -- clear every 2s (matching the heat-of-battle retry) rather than waiting
        -- the full 30s a non-urgent errand walk can afford. Each retry that's
        -- still blocked re-emits this line, so the 2s cadence re-arms naturally.
        local delay = taPackage.arenaState == "fleeing" and 2000 or 30000
        -- Say so out loud. Thirty seconds of nothing is indistinguishable from a
        -- hang, and the only line printed anywhere near it is the melee retry's
        -- "melee-retry in NNNNNms" -- a stale attack left over from the swing
        -- that just landed, which reads exactly like "still fighting, ignoring
        -- the walk". That pair cost a real training trip: the first step of the
        -- walk to the hall was refused here, waited silently, and was stopped by
        -- hand about 15s in on the entirely reasonable assumption that it had
        -- wedged (logs/session-garbageman-2026-08-15T19-21-55.log, 1765-1786).
        -- Not debug-gated: the point is to be visible when nobody thought to
        -- turn debug on.
        echo("[arena] Move \"" .. cmd .. "\" refused (still resting) — retrying in "
            .. math.floor(delay / 1000) .. "s.")
        createTimer(delay, function()
            if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
                arenaSend(cmd)
            end
        end, { repeating = false })
    end
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function(matches)
    if not taPackage.arenaState then return end
    arenaDebugEcho("exhausted")
    -- An Acolyte does NOT self-heal here. Casting motu on ourselves mid-fight
    -- keeps us in the arena past the point where we should leave; instead we
    -- let checkFleeArena pull us out at the regular flee threshold and buy
    -- healing at the temple like every other class.
    -- A stable combat generation (not the per-send retry counter) keeps these
    -- timers alive even though the cast loop keeps firing arenaSend meanwhile.
    local gen = taPackage.arenaCombatGen or 0
    if taPackage.arenaState == "ringing" then
        -- The blocked physical action was the gong ring (the kill just spent the
        -- physical clock). Nothing to do here: the scan pump (arenaScanRoom) is
        -- already re-arming on its own timer and will re-scan and re-ring once
        -- the clock recovers. Scheduling our own retry here was the source of the
        -- deadlock — it shared flags with the pump and could drop the only
        -- outstanding retry. Let the pump own ring liveness.
        --
        -- Traced rather than acted on: paired with the ring-sent/ring-accepted
        -- lines, this is what will say whether the gong can be reckoned the way
        -- melee now is. See the comment on arenaRing.
        arenaDebugEcho("ring-exhausted  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
            .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
        return
    else
        -- Melee is on cooldown. Reckon the wait from the last accepted swing
        -- rather than polling the whole window; see ARENA_PHYSICAL_COOLDOWN_MS.
        -- Whichever is larger wins, so a missing or stale timestamp (nothing
        -- landed recently — we just got back from an errand, or the ring rather
        -- than a swing spent the clock) makes the remainder negative and leaves
        -- us on the tail poll, which is the old behaviour and always safe.
        taPackage.arenaAttackPending = false
        local delay = ARENA_EXHAUSTED_RETRY_MS
        local lastSwingAt = taPackage.arenaLastSwingAt
        if lastSwingAt then
            local remaining = ARENA_PHYSICAL_COOLDOWN_MS
                - (nowMillis() - lastSwingAt)
                - ARENA_COOLDOWN_MARGIN_MS
            if remaining > delay then delay = remaining end
        end
        arenaDebugEcho("melee-retry in " .. delay .. "ms")
        createTimer(delay, function()
            if taPackage.arenaState and (taPackage.arenaCombatGen or 0) == gen then
                arenaAttack()
            end
        end, { repeating = false })
    end
end, { type = "regex" })

createTrigger("^You are still too mentally exhausted from your last incantation!$", function(matches)
    if not taPackage.arenaState then return end
    taPackage.arenaCastPending = false
    arenaDebugEcho("mentally-exhausted")
    -- The spell is on cooldown; retry the cast once the mental clock recovers.
    local gen = taPackage.arenaCombatGen or 0
    createTimer(30000, function()
        if taPackage.arenaState and (taPackage.arenaCombatGen or 0) == gen then
            arenaCast()
        end
    end, { repeating = false })
end, { type = "regex" })

createOutboundTrigger("^cast kamotu ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
    taPackage.lastSpellCast = "kamotu"
end, { type = "regex" })

createTrigger("^You intoned the spell for (.+) which healed (\\d+) damage!$", function(matches)
    local target = matches[2]
    local amount = tonumber(matches[3])
    -- A landed heal frees the cast loop to respond to the next injury. The
    -- land message doesn't name the spell, so record whichever heal we last
    -- cast (motu = self, kamotu = group); both produce this same line.
    taPackage.castPending = false
    healingBadge("HEALED " .. string.upper(target) .. " FOR " .. amount)
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", target, "hit", amount, "heal")
    if target == taPackage.character.name then
        local current = taPackage.character.vitalityCurrent
        local max = taPackage.character.vitalityMax
        if current and amount then
            taPackage.character.vitalityCurrent = max and math.min(current + amount, max) or (current + amount)
        end
    end
end, { type = "regex" })

-- The area heals (motumaru, kamotumaru, gimotumaru, kusamotumaru) hit everyone
-- friendly in the room at once, so instead of a per-target "You intoned the
-- spell for X" line the server prints one line carrying the amount each person
-- got — us included. Nothing tells us our own new HP, so add the heal to our
-- tracked vitality directly (clamped at max) rather than paying for an "st"
-- round trip. The non-heal area spells (dobudanimaru, cure poison) print the
-- same sentence *without* the ", healing N damage!" tail, so they don't match.
createTrigger("^You discharged the spell at friendly people in the area, healing (\\d+) damage!$",
    function(matches)
        local amount = tonumber(matches[2])
        -- An area heal spends the cast round like any other, so free the cast
        -- loop; leaving castPending set would wedge it waiting on a targeted
        -- heal that this cast displaced.
        taPackage.castPending = false
        healingBadge("HEALED GROUP FOR " .. amount)
        taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", "group", "hit", amount, "heal")
        local current, max = getVitality()
        if current then
            setVitality(max and math.min(current + amount, max) or (current + amount), max)
        end
    end, { type = "regex" })

-- The receiving end of that same area heal tells us only that something good
-- happened — "Pelayo just discharged a very dark bluish mist at friendly people
-- in the area!" — with no amount and no new HP. Same trick as the trap and
-- hostile-AOE handlers: stash our HP, ask for a fresh "st", and let the Vitality
-- trigger recover the gain and badge it green. The mist's adjectives track the
-- spell tier ("bluish" / "dark bluish" / "very dark bluish"), and the non-heal
-- area spells reuse the sentence with their own mist ("thick greyish"), so match
-- on the "at friendly people" signature alone and let a zero gain go unbadged.
-- Don't anchor the end: a long enough caster+spell pair word-wraps the trailing
-- "in the area!" onto a second physical line.
createTrigger("^(.+) just discharged .+ at friendly people", function(matches)
    taPackage.groupHealCaster = matches[2]
    taPackage.groupHealHpBefore = getVitality()
    send("st")
end, { type = "regex" })

-- A party member healing us badges "HEALED BY <healer> FOR N" and adds the
-- amount back to our vitality. The heal comes in several tiers (minor, normal,
-- "very powerful") that differ only in the adjective, so drive them all from
-- one handler. The "very powerful" line is long enough that Tele-Arena's
-- server-side word-wrap pushes the trailing " damage!" onto the next physical
-- line, which arrives as a separate (ignored) line — so its pattern ends at the
-- number, while the shorter tiers still carry " damage!".
local function applyPartyHeal(matches)
    local healer = matches[2]
    local amount = tonumber(matches[3])
    healingBadge("HEALED BY " .. string.upper(healer) .. " FOR " .. amount)
    local current = taPackage.character.vitalityCurrent
    local max = taPackage.character.vitalityMax
    if current and amount then
        taPackage.character.vitalityCurrent = max and math.min(current + amount, max) or (current + amount)
    end
end

local partyHealPatterns = {
    "^(.+) just intoned a minor healing spell for you which healed (\\d+) damage!$",
    "^(.+) just intoned a healing spell for you which healed (\\d+) damage!$",
    "^(.+) just intoned a very powerful healing spell for you which healed (\\d+)$",
}

for _, pattern in ipairs(partyHealPatterns) do
    createTrigger(pattern, applyPartyHeal, { type = "regex" })
end

createOutboundTrigger("^cast komiza ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
    taPackage.lastSpellCast = "komiza"
end, { type = "regex" })

createOutboundTrigger("^cast toduza ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 2)
    end
    taPackage.lastSpellCast = "toduza"
end, { type = "regex" })

createTrigger("^You discharged the spell at the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local amount = tonumber(matches[3])
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "hit", amount, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-hit")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createTrigger("^You confuse the key syllables and the spell fails!$", function()
    local monster = taPackage.lastAttackTarget or "unknown"
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "fizzle", nil, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-fizzle")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createTrigger("^Your spell was negated by the (.+)'s magickal defenses!$", function(matches)
    local monster = matches[2]
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "resist", nil, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-resist")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createOutboundTrigger("^cast motu ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
    taPackage.lastSpellCast = "motu"
end, { type = "regex" })

-- =========================================================================
-- Spell-name translation aliases (Acolyte / High Priest)
-- =========================================================================
-- The spellbook uses opaque intoned names (motu, gitami, kusamotu, ...). These
-- aliases let you cast by plain English instead: `cast-greater-heal foo` sends
-- `cast gimotu foo`. Full list and translations: docs/shrine/SPELLS.md.
--
-- Targeted spells take a <target>. Area spells (translation contains "area")
-- hit everyone in the room and take no target, so their alias ends in `-area`
-- and sends the bare `cast <spell>`.

-- Translation alias -> intoned name, for spells that take a target.
local castTranslations = {
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

for alias, spell in pairs(castTranslations) do
    createAlias("^" .. alias .. " (.+)$", function(matches)
        send("cast " .. spell .. " " .. matches[2])
    end, { type = "regex" })
end

-- Area spells impact everyone in the room; no target argument.
local castAreaTranslations = {
    ["cast-minor-heal-area"]   = "motumaru",
    ["cast-heal-area"]         = "kamotumaru",
    ["cast-cure-poison-area"]  = "dobudanimaru",
    ["cast-greater-heal-area"] = "gimotumaru",
    ["cast-deific-heal-area"]  = "kusamotumaru",
}

for alias, spell in pairs(castAreaTranslations) do
    createAlias("^" .. alias .. "$", function()
        send("cast " .. spell)
    end, { type = "regex" })
end

-- =========================================================================
-- Kill a single target
-- =========================================================================

-- An Acolyte heals a group member once their health drops below this.
local HEAL_THRESHOLD = 90

-- Hard-coded toggle: when true, an Acolyte in the kill loop skips its automatic
-- in-combat healing (the exhaustion-driven group scan and the cast-clock heal)
-- and just melees for damage. Manually-typed `heal.allies` and the opt-in
-- `heal-allies-in-loop` are unaffected. Flip to false to restore automatic
-- battle healing. Lives on taPackage so it can also be flipped at runtime via
-- `/lua taPackage.acolyteAutoHealDisabled = false`.
if taPackage.acolyteAutoHealDisabled == nil then
    taPackage.acolyteAutoHealDisabled = true
end

-- Kill-loop debug tracing. Emits a timestamped line for each combat event and
-- decision when the loop is running in debug mode. The flag is set by `kill
-- <target> debug` directly, or inherited from a `ta.follow <name> debug` so the
-- follow's debug "follows through" into every kill it spawns (see followDebug).
local function killDebugEcho(label)
    if taPackage.killDebug or taPackage.followDebug then
        echo("[K] " .. os.date("%H:%M:%S") .. " " .. label)
    end
end

-- Melee: everyone swings each round, casters included.
local function killAttack()
    local target = taPackage.killTarget
    if not target then
        killDebugEcho("attack-skip: no target")
        return
    end
    if taPackage.killAttackPending then
        killDebugEcho("attack-skip: swing already pending")
        return
    end
    taPackage.killAttackPending = true
    local name = target:match("^(%S+)")
    killDebugEcho("attack-sent: a " .. name)
    send("a " .. name)
end

-- Casters take a second action each round, on a separate exhaustion clock:
-- Sorcerors blast the target, Acolytes heal whoever was most recently hurt.
local function castSpell()
    if taPackage.castPending then
        killDebugEcho("cast-skip: cast already pending")
        return
    end
    if not taPackage.killActive then
        killDebugEcho("cast-skip: kill loop not active")
        return
    end
    local class = getClass()
    if class == "Sorceror" then
        local target = taPackage.killTarget
        if not target then
            killDebugEcho("cast-skip: no target")
            return
        end
        taPackage.castPending = true
        local name = target:match("^(%S+)")
        killDebugEcho("cast-sent: toduza " .. name)
        send("cast toduza " .. name)
    elseif class == "Acolyte" then
        if taPackage.acolyteAutoHealDisabled then
            killDebugEcho("cast-skip: acolyte auto-heal disabled")
            return
        end
        local ally = taPackage.healTarget
        if not ally then
            killDebugEcho("cast-skip: no heal target")
            return
        end
        taPackage.castPending = true
        killDebugEcho("cast-sent: kamotu " .. ally)
        send("cast kamotu " .. ally)
    end
end

-- Acolyte group healing. We send `group`, accumulate each member's health as
-- the listing streams in, and once the listing ends heal the most-injured
-- member (lowest HE%) if anyone is below the threshold. Phases:
--   "want"    -- asked for the listing, waiting for the header
--   "reading" -- header seen, members are streaming in
-- The listing itself has no terminator line, so we chase it with a harmless
-- `ex` (exits). Its "Exits: ..." reply is guaranteed to arrive right after the
-- listing and is the first non-member line, which ends the reading phase — no
-- timing guesswork. Waiting for the header first means any spam arriving before
-- the listing doesn't cut the scan short.
local GROUP_HEAL_TERMINATOR = "ex"
-- context labels the scan's origin so the decision log distinguishes a typed
-- heal.allies, an automatic loop tick, and the kill-loop's exhaustion heal.
local function beginGroupHealScan(threshold, context)
    taPackage.groupHealPhase = "want"
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil
    taPackage.groupHealThreshold = threshold or HEAL_THRESHOLD
    taPackage.groupHealContext = context or "heal.allies"
    -- Tallied as the listing streams in (see the member-row trigger): total
    -- members, how many are hurt (below full), and how many are below the
    -- heal threshold. Drives the decision log in finalizeGroupHeal.
    taPackage.groupHealMembers = 0
    taPackage.groupHealHurt = 0
    taPackage.groupHealNeedy = 0
    send("group")
    send(GROUP_HEAL_TERMINATOR)
end

local function finalizeGroupHeal()
    taPackage.groupHealPhase = nil
    local name = taPackage.groupHealBestName
    local health = taPackage.groupHealBestHealth
    local threshold = taPackage.groupHealThreshold or HEAL_THRESHOLD
    local context = taPackage.groupHealContext or "heal.allies"
    local members = taPackage.groupHealMembers or 0
    local hurt = taPackage.groupHealHurt or 0
    local needy = taPackage.groupHealNeedy or 0
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil

    if members == 0 then
        echo(string.format("[heal] %s: no group members seen, taking no action.", context))
        return
    end
    if needy == 0 then
        if hurt == 0 then
            echo(string.format("[heal] %s: all %d allies at full health, taking no action.",
                context, members))
        else
            echo(string.format("[heal] %s: %d of %d allies hurt but all at or above %d%%, taking no action.",
                context, hurt, members, threshold))
        end
        return
    end
    if not name or not health then return end
    if taPackage.castPending then
        echo(string.format(
            "[heal] %s: %d of %d allies below %d%% (most injured %s at %d%%), but a cast is pending — skipping.",
            context, needy, members, threshold, name, health))
        return
    end
    echo(string.format("[heal] %s: %d of %d allies below %d%%, healing most injured %s at %d%%.",
        context, needy, members, threshold, name, health))
    taPackage.castPending = true
    taPackage.healTarget = name
    -- kamotu (regular heal, ~24 HP) by default — group members fighting real
    -- monsters take big hits and want a full top-off. In the arena, though,
    -- damage comes in small bites: kamotu's ~24 HP is overheal and costs more
    -- mana, so use motu (minor heal, ~4-8 HP), which matches the damage and
    -- stretches mana further.
    local spell = taPackage.arenaState and "motu" or "kamotu"
    send("cast " .. spell .. " " .. name)
end

local function startKill(target, debug)
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return false
    end
    if not getClass() then
        echo("[kill] Class unknown — run 'st' first so casters cast.")
        return false
    end
    taPackage.killTarget = target
    taPackage.killActive = true
    taPackage.killDebug = debug or false
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.healTarget = nil
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    local debugSuffix = (taPackage.killDebug or taPackage.followDebug) and " (debug)" or ""
    echo("[kill] Attacking " .. taPackage.killTarget .. "." .. debugSuffix)
    killDebugEcho("kill-start: target=" .. target)
    killAttack()
    castSpell()
    return true
end
taPackage.startKill = startKill

-- `kill <target>` melees (and casts) a single monster. An optional trailing
-- " debug" turns on the kill-loop trace for this fight.
local function handleKillAlias(matches)
    local rest = matches[2]
    local target, debug = rest, false
    local stripped = rest:match("^(.-) debug$")
    if stripped then
        target, debug = stripped, true
    end
    startKill(target, debug)
end

createAlias("^kill (.+)$", handleKillAlias, { type = "regex" })

-- Shorthand: `k <monster>` behaves exactly like `kill <monster>`.
createAlias("^k (.+)$", handleKillAlias, { type = "regex" })

local function stopKill()
    killDebugEcho("kill-stop")
    taPackage.killActive = false
    taPackage.killAllActive = false
    taPackage.killDebug = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.healTarget = nil
    taPackage.groupHealPhase = nil
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    taPackage.killAllGeneration = (taPackage.killAllGeneration or 0) + 1
    -- A route's arrival sweep is over too; drop its bookkeeping so a later
    -- hand-run sweep can't finish and report against it.
    taPackage.navSweep = nil
    echo("[kill] Stopped.")
end
taPackage.stopKill = stopKill

-- `kill-all` clears a room of monsters one at a time. It sends a bare return to
-- print the room brief, engages the first monster listed, and — once that
-- monster dies (see the death trigger below) — re-scans and engages the next,
-- repeating until the room holds no monster.
--
-- The occupant line names the monsters: "There is a warlock here." for one, or
-- "There are three warlocks here." / "There is a warlock, a goblin, and a rat
-- here." for several. firstArenaMonster picks the first and de-pluralises a
-- count word, so "three warlocks" -> "warlock". A player stands on their own
-- line ("Pelayo is here.") which never matches, so we only ever lock onto a
-- monster.
--
-- The scan is a self-timing probe: after sending the bare return it arms a
-- timer keyed to killAllGeneration. If no occupant line resolves the scan
-- within the window — an empty room prints "There is nobody here.", but a room
-- with players and no monster omits that line entirely — the timer fires and
-- ends the sweep so it can't hang. Locking onto a monster (or seeing "nobody")
-- bumps killAllGeneration, which cancels the pending timer.
local KILL_ALL_SCAN_MS = 2000

-- The room is clear. Both endings -- the scan timing out and the occupant line
-- reporting nobody -- go through here so anything waiting on the sweep hears
-- about it exactly once. A route that arrived and started this sweep uses the
-- hook to report what the room yielded (see the navigation section).
local function killAllDone()
    taPackage.killAllActive = false
    echo("[kill] No monster here — kill-all done.")
    if taPackage.navOnSweepDone then taPackage.navOnSweepDone() end
end

local function killAllScan()
    if not taPackage.killAllActive then return end
    local gen = (taPackage.killAllGeneration or 0) + 1
    taPackage.killAllGeneration = gen
    send("")
    createTimer(KILL_ALL_SCAN_MS, function()
        if taPackage.killAllActive and (taPackage.killAllGeneration or 0) == gen then
            killAllDone()
        end
    end, { repeating = false })
end
taPackage.killAllScan = killAllScan

createAlias("^kill-all$", function()
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return
    end
    taPackage.killAllActive = true
    killAllScan()
end, { type = "regex" })

-- Response to the kill-all probe: the room brief's occupant line. Engage the
-- first monster, or end the sweep when the room is clear ("nobody"). The \S+
-- matches either "is" or "are" so single and multi-monster briefs both hit.
createTrigger("^There \\S+ (.+) here\\.$", function(matches)
    if not taPackage.killAllActive then return end
    -- A scan is resolving: bump the generation to cancel its timeout.
    taPackage.killAllGeneration = (taPackage.killAllGeneration or 0) + 1
    local monster = firstArenaMonster(matches[2])
    if monster then
        if not startKill(monster) then
            taPackage.killAllActive = false
        end
    else
        killAllDone()
    end
end, { type = "regex" })

createAlias("^kill-stop$", function()
    stopKill()
end, { type = "regex" })

-- Typed equivalent of the conferred `heal.allies`: an Acolyte scans the group
-- and heals its most-injured member. Non-Acolytes have no group heal to cast.
createAlias("^heal\\.allies$", function()
    if getClass() == "Acolyte" then
        beginGroupHealScan()
    else
        echo("[heal] Only an Acolyte can heal the group.")
    end
end, { type = "regex" })

-- Hands-off group healing: every minute, scan the group and top off anyone
-- below 95%. A generation counter (bumped on start/stop) makes the rescheduled
-- one-shot timer self-cancel, mirroring scheduleArenaXpCheck.
local HEAL_LOOP_INTERVAL = 60000
local HEAL_LOOP_THRESHOLD = 95
local function scheduleHealAlliesLoop()
    local gen = taPackage.healLoopGen or 0
    createTimer(HEAL_LOOP_INTERVAL, function()
        if (taPackage.healLoopGen or 0) ~= gen then return end
        beginGroupHealScan(HEAL_LOOP_THRESHOLD, "loop tick")
        scheduleHealAlliesLoop()
    end, { repeating = false })
end

createAlias("^heal-allies-in-loop$", function()
    if getClass() ~= "Acolyte" then
        echo("[heal] Only an Acolyte can heal the group.")
        return
    end
    taPackage.healLoopGen = (taPackage.healLoopGen or 0) + 1
    taPackage.healLoopActive = true
    echo("[heal] Looping group heal every 60s (tops off below 95%), and scanning on any group member taking a hit.")
    beginGroupHealScan(HEAL_LOOP_THRESHOLD, "loop start")
    scheduleHealAlliesLoop()
end, { type = "regex" })

local function stopHealLoop()
    taPackage.healLoopGen = (taPackage.healLoopGen or 0) + 1
    taPackage.healLoopActive = false
    echo("[heal] Group heal loop stopped.")
end
taPackage.stopHealLoop = stopHealLoop

createAlias("^stop-heal-allies-in-loop$", function()
    stopHealLoop()
end, { type = "regex" })

-- =========================================================================
-- Navigate to a destination
-- =========================================================================
--
-- Its own chunk: main.lua was two names under Lua's 200-local ceiling for a
-- single function, and a file is a function. See ta_nav.lua's header for the
-- seam (everything crosses through taPackage). Loaded here, where the section
-- used to sit, so trigger and alias registration order is unchanged.
dofile(scriptDir .. "ta_nav.lua")

-- =========================================================================
-- Create a character
-- =========================================================================
--
-- Also its own chunk, for the same local-budget reason, and it needs nothing
-- from main.lua besides taPackage. See ta_create.lua's header. Loaded before
-- stop-all-scripts below, which reaches for the taPackage.stopCreateCharacter
-- it defines.
dofile(scriptDir .. "ta_create.lua")

-- =========================================================================
-- Banking
-- =========================================================================
--
-- The other end of the farm: the character receiving the gold has to put it
-- somewhere, or it eventually cannot receive any more. Loaded after
-- ta_create.lua because it borrows that chunk's paced walker.
dofile(scriptDir .. "ta_bank.lua")

-- Stops every long-running script at once. Each sub-stop is independent and
-- safe to call when its script isn't running (it just resets already-clear
-- state). We check each script's "running" flag first so we can report, per
-- script, whether we actually stopped it or it wasn't running.
--
-- When you add a new script, add it here too (see CLAUDE.md).
createAlias("^stop-all-scripts$", function()
    local scripts = {
        { name = "arena",                 running = taPackage.arenaState ~= nil,      stop = stopArena },
        { name = "heal loop",             running = taPackage.healLoopActive == true, stop = stopHealLoop },
        { name = "kill",                  running = taPackage.killActive == true,     stop = stopKill },
        { name = "hang-around-in-tavern", running = taPackage.tavernMode == true,     stop = stopTavernMode },
        { name = "mapping",               running = taPackage.mapping == true,        stop = stopMapping },
        { name = "navigate",              running = taPackage.navigate ~= nil,        stop = taPackage.stopNavigate },
        { name = "train-and-exit",        running = taPackage.trainWatch ~= nil,      stop = stopTrainWatch },
        { name = "gold-farming",          running = taPackage.createCharacterRunning(), stop = taPackage.stopCreateCharacter },
        { name = "banking",               running = taPackage.bankingRunning(),       stop = taPackage.stopBanking },
    }
    for _, s in ipairs(scripts) do
        if s.running then
            s.stop()
            echo("[all] Stopped " .. s.name .. ".")
        else
            echo("[all] " .. s.name .. " not running.")
        end
    end
end, { type = "regex" })

-- The 60s timer can leave an ally hurt for up to a minute between scans, which
-- is fatal against burst damage (a cave bear's worst round is ~23). So while
-- the loop is active, react to any group member taking a hit by scanning the
-- group right away and healing if it dropped someone below the threshold. The
-- in-progress guard collapses a monster's two claws in one round into a single
-- scan.
local function reactToGroupHit()
    if not taPackage.healLoopActive then return end
    if getClass() ~= "Acolyte" then return end
    if taPackage.groupHealPhase then return end
    beginGroupHealScan(HEAL_LOOP_THRESHOLD, "hit reaction")
end

-- The "with" in the pattern matches landed hits ("attacked Johnsonite with its
-- claws!", "attacked you ... for N damage!") while skipping glances and misses,
-- which deal no damage.
createTrigger("^The .+ attacked .+ with .+!$", reactToGroupHit, { type = "regex" })

-- Special attacks (a stone giant's boulder, a cyclops's throw) are the biggest
-- single hits we've seen, so the healer must react to them too. Unlike the
-- HP-tracking triggers above, these match any target, not just "you": when one
-- lands on an ally the game prints no number ("hurled a boulder at Pelayo!"),
-- but the ally still took a heavy hit and needs an immediate scan.
createTrigger("^The .+ hurled a boulder at .+!$", reactToGroupHit, { type = "regex" })
createTrigger("^The .+ picks up and hurls .+!$", reactToGroupHit, { type = "regex" })
createTrigger("^The .+ breathed flames at .+!$", reactToGroupHit, { type = "regex" })

createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("our melee landed")
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^Your attack missed!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("our melee missed")
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("monster dodged our melee")
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^You barely dodge the .+'s attack!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("we dodged the monster")
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

-- Caster spell-outcome continuation. The DB-recording copies of these lines
-- live in the spell section; these re-fire the cast loop independently of the
-- melee loop above.
createTrigger("^You discharged the spell at the .+ for \\d+ damage!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("our spell landed")
    taPackage.castPending = false
    castSpell()
end, { type = "regex" })

createTrigger("^You confuse the key syllables and the spell fails!$", function()
    -- Clear unconditionally: a heal (heal-allies-in-loop) can fizzle too, and
    -- if we only cleared inside a kill the blocked cast would wedge castPending
    -- forever. Only the kill loop's re-cast needs an active fight.
    taPackage.castPending = false
    if not taPackage.killActive then return end
    killDebugEcho("our spell fizzled")
    castSpell()
end, { type = "regex" })

createTrigger("^Your spell was negated by the .+'s magickal defenses!$", function()
    taPackage.castPending = false
    if not taPackage.killActive then return end
    killDebugEcho("our spell was resisted")
    castSpell()
end, { type = "regex" })

-- "Mana too low" aborts a cast with no result line. With no handler this
-- wedged castPending forever: heal-allies-in-loop ran Pelayo out of mana, then
-- every scan logged "a cast is pending — skipping" and never healed again.
-- Clears both the kill/heal guard and the arena guard, since either loop can
-- run dry. No retry — the next scan/round casts again once mana regenerates.
createTrigger("^Your mana is too low to cast that spell\\.$", function()
    taPackage.castPending = false
    taPackage.arenaCastPending = false
end, { type = "regex" })

-- The header (only when we asked for the listing) starts the reading phase;
-- a manually-typed `group` has no pending scan, so it's left alone.
createTrigger("^Your group currently consists of:$", function()
    if taPackage.groupHealPhase == "want" then
        taPackage.groupHealPhase = "reading"
    end
end, { type = "regex" })

-- While reading the listing, tally members and track the most-injured one.
createTrigger("^\\s+(\\S+).*HE:\\s*(\\d+)%", function(matches)
    if taPackage.groupHealPhase ~= "reading" then return end
    local health = tonumber(matches[3])
    if not health then return end
    local threshold = taPackage.groupHealThreshold or HEAL_THRESHOLD
    taPackage.groupHealMembers = (taPackage.groupHealMembers or 0) + 1
    if health < 100 then
        taPackage.groupHealHurt = (taPackage.groupHealHurt or 0) + 1
    end
    if health < threshold then
        taPackage.groupHealNeedy = (taPackage.groupHealNeedy or 0) + 1
    end
    if not taPackage.groupHealBestHealth or health < taPackage.groupHealBestHealth then
        taPackage.groupHealBestHealth = health
        taPackage.groupHealBestName = matches[2]
    end
end, { type = "regex" })

-- The listing has no end marker, so the first line that is neither the header
-- nor a member row ends the reading phase and triggers the heal. The `ex` we
-- sent after `group` guarantees such a line ("Exits: ...") even with no other
-- traffic.
createTrigger("^(.+)$", function(matches)
    if taPackage.groupHealPhase ~= "reading" then return end
    local line = matches[2]
    if line:match("^Your group currently consists of:$") then return end
    if line:match("^%s+%S+.*HE:%s*%d+%%") then return end
    finalizeGroupHeal()
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    if not taPackage.killActive then return end
    killDebugEcho("target dead: " .. matches[2] .. " — kill loop ending")
    taPackage.killActive = false
    taPackage.killDebug = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.healTarget = nil
    taPackage.groupHealPhase = nil
    echo("[kill] " .. matches[2] .. " is dead.")
    -- A kill-all sweep re-scans the room for the next monster; the scan ends
    -- the sweep on its own when nothing is left.
    if taPackage.killAllActive then
        killAllScan()
    end
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function()
    if not taPackage.killActive then return end
    killDebugEcho("physically exhausted — melee retry in 30s")
    taPackage.killAttackPending = false
    -- Out of melee for now; an Acolyte spends the lull checking the group so
    -- the next cast (on the mental clock) heals whoever needs it. Skipped when
    -- auto-heal is disabled — then the Acolyte just rides out the lull.
    if getClass() == "Acolyte" and not taPackage.acolyteAutoHealDisabled then
        beginGroupHealScan(nil, "exhaustion")
    end
    local gen = taPackage.killGeneration or 0
    createTimer(30000, function()
        if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
            killDebugEcho("melee retry firing after exhaustion")
            killAttack()
        end
    end, { repeating = false })
end, { type = "regex" })

createTrigger("^You are still too mentally exhausted from your last incantation!$", function()
    -- Clear the flag even out of combat (e.g. a confer heal.allies cast), so a
    -- blocked cast doesn't wedge future ones; only the retry needs a fight.
    taPackage.castPending = false
    if not taPackage.killActive then return end
    killDebugEcho("mentally exhausted — cast retry in 30s")
    local gen = taPackage.killGeneration or 0
    createTimer(30000, function()
        if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
            killDebugEcho("cast retry firing after exhaustion")
            castSpell()
        end
    end, { repeating = false })
end, { type = "regex" })

-- =========================================================================
-- Follow
-- =========================================================================

local dirShort = {
    north = "n",
    south = "s",
    east = "e",
    west = "w",
    northeast = "ne",
    northwest = "nw",
    southeast = "se",
    southwest = "sw",
    up = "u",
    down = "d",
}

-- `ta.follow <name>` joins and shadows a leader. An optional trailing " debug"
-- turns on tracing for the whole follow session: the join decisions below, plus
-- every kill the follow spawns (followDebug feeds killDebugEcho, so the debug
-- "follows through" without each kill having to be flagged individually).
createAlias("^ta\\.follow (.+)$", function(matches)
    local rest = matches[2]
    local name, debug = rest, false
    local stripped = rest:match("^(.-) debug$")
    if stripped then
        name, debug = stripped, true
    end
    taPackage.followTarget = name:lower()
    taPackage.followDebug = debug
    -- Joining someone else's group means we're no longer a leader; drop any
    -- (possibly stale) follower list so we don't keep showing the Leader tag.
    taPackage.followedBy = nil
    local debugSuffix = debug and " (debug mode)" or ""
    echo("[follow] Now following: " .. taPackage.followTarget .. debugSuffix)
    send("join " .. name)
    -- Begin a group session: capture our starting XP so `ta.unfollow` can report
    -- the gain. The Experience line from this status is consumed by the
    -- followStartXpPending branch of the Experience trigger.
    taPackage.followStartXpPending = true
    taPackage.followEndXpPending = false
    send("status")
end, { type = "regex" })

-- `ta.unfollow` ends the group session started by `ta.follow`: it leaves the
-- group, clears all follow state, then sends `status` so the Experience trigger
-- can report how much XP we gained over the session.
createAlias("^ta\\.unfollow$", function()
    send("leave")
    taPackage.followTarget = nil
    taPackage.followDebug = nil
    taPackage.followedBy = nil
    taPackage.followStartXpPending = false
    taPackage.followEndXpPending = true
    echo("[follow] Left the group.")
    send("status")
end, { type = "regex" })

createTrigger("^(.+) is asking to join your group\\.$", function(matches)
    -- Only the group leader can add members. When we're following someone we're
    -- a member, not the leader, yet the game shows this line to the whole group;
    -- a reflexive `add` from a follower just earns "Sorry, you are not the leader
    -- of a group." Leave it to the real leader.
    if taPackage.followTarget then return end
    local name = matches[2]
    if not taPackage.followedBy then taPackage.followedBy = {} end
    table.insert(taPackage.followedBy, name)
    send("add " .. name:lower())
    echo("[follow] " .. name .. " is now following you.")
end, { type = "regex" })

-- The leader can drive followers over group chat with `confer <command>`,
-- which everyone sees as "From <leader> (to group): <command>". Only an
-- allowlisted set of commands runs; anything else is ignored. The speaker
-- must be the leader we're following, so our own conferred lines won't match.
createTrigger("^From (.+) \\(to group\\): (.+)$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    local command = matches[3]
    local killMonster = command:match("^kill (.+)$")
    if killMonster then
        startKill(killMonster, taPackage.followDebug)
    elseif command == "heal.allies" then
        if getClass() == "Acolyte" then
            beginGroupHealScan()
        end
    end
end, { type = "regex" })

-- When the leader we're following engages a monster, join the fight on the same
-- target via the kill loop. The kill loop's death trigger stops us naturally if
-- someone else lands the killing blow first. The skip-while-already-killing
-- branch is logged in debug because it's the usual reason a follower fails to
-- join the leader in a new room: a stale killActive (from a monster we never saw
-- die) suppresses every later join until the loop is cleared.
local function followJoinKill(attacker, monster)
    if not taPackage.followTarget then return end
    if attacker:lower() ~= taPackage.followTarget then return end
    if taPackage.killActive then
        killDebugEcho("join-skip: already killing " .. tostring(taPackage.killTarget)
            .. " (leader engaged " .. monster .. ")")
        return
    end
    killDebugEcho("join: leader engaged " .. monster .. " — starting kill")
    startKill(monster, taPackage.followDebug)
end

createTrigger("^(.+) just attacked the (.+) with .+!$", function(matches)
    followJoinKill(matches[2], matches[3])
end, { type = "regex" })

-- A monster dodging the leader's first swing is the same signal to join in;
-- here the monster comes first and the leader is in the possessive form.
createTrigger("^The (.+) barely dodged (.+)'s .+!$", function(matches)
    followJoinKill(matches[3], matches[2])
end, { type = "regex" })

-- The leader swinging and missing still means they're engaging that monster.
createTrigger("^(.+)'s poorly executed attack misses the (.+)!$", function(matches)
    followJoinKill(matches[2], matches[3])
end, { type = "regex" })

-- When the leader buys a drink, the follower buys one too.
createTrigger("^The barmaid brings a drink over to (.+) in exchange for a few coins\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("b drink")
end, { type = "regex" })

-- When the leader buys a hot meal, the follower buys one too. The message
-- wraps across lines, so match only the opening clause that carries the name.
createTrigger("^The barmaid brings a hot meal over to (\\S+) in exchange", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("buy meal")
end, { type = "regex" })

-- When the leader gets healed at the temple, the follower buys healing too.
-- Match the opening clause only; the full message wraps across lines.
createTrigger("^The temple priests take (\\S+) into another chamber", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("buy healing")
end, { type = "regex" })

createTrigger("^(.+) has just gone to the (.+)\\.$", function(matches)
    if not taPackage.followTarget then return end
    local name = matches[2]:lower()
    if name ~= taPackage.followTarget then return end
    local direction = matches[3]:lower()
    local cmd = dirShort[direction]
    if cmd then send(cmd) end
end, { type = "regex" })

createTrigger("^(.+) has just gone downward\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("d")
end, { type = "regex" })

createTrigger("^(.+) has just gone upward\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("u")
end, { type = "regex" })

-- =========================================================================
-- Auto-login
-- =========================================================================
--
-- baud connects to the BBS, not to Tele-Arena: a login and two menus sit
-- between the two. `just run kerhak` exports TA_CHARACTER=kerhak (and passes
-- TA_PASSWORD through from the environment), so the script can answer the
-- whole sequence itself:
--
--     Username:                          ->  the character name
--     Password:                          ->  the password
--     (N)onstop, (Q)uit, or (C)ontinue?  ->  n   (printed twice, see below)
--     Make your selection (...):         ->  5   (Tele-Arena)
--     Entering Tele-Arena...             ->  we are in, stop answering
--
-- TA_INIT_CMD, if set, is what to run once we are in ("rg 2", say). It goes
-- through baud's runCommand, not send, so an alias actually executes; and it
-- waits for the entry character sheet to come back (see runLoginInitCmd).
--
-- TA_LOGIN_CMD is its earlier sibling, and the two are not interchangeable.
-- TA_INIT_CMD promises "you are in the game and your sheet is parsed"; the only
-- thing that can deliver that promise is the entry `st`/`i` reply, which only
-- exists on the path that prints "Entering Tele-Arena...". A DEAD character
-- never takes that path: picking 5 at the main menu drops it straight onto
--
--     1) Resurect Old Character for 0 Credits.
--     2) Create New Character
--     3) Exit
--     Select an option:
--
-- and stops there. No entry line, no `st`, no `i`, no gold reply -- so
-- TA_INIT_CMD can never fire, by construction. Both paths are visible in
-- logs/session-garbageman-2026-08-15T07-30-44.log: the first "5" (line 69)
-- enters the game, the second (line 153), after a suicide, hits this menu.
--
-- TA_LOGIN_CMD runs at the front door instead, right after the username goes
-- out, so it happens on both paths. That makes it the one that can arm
-- something which has to be LISTENING before the game exists --
-- TA_LOGIN_CMD="start-gold-farming" is the case it was added for. It is for
-- arming a script, not for sending text: at the username prompt there is no
-- game to send a command to.
--
-- Every answer is sent at most once per login, because a prompt appearing
-- twice does not mean the BBS is waiting twice. "N" means *nonstop*: it tells
-- the BBS to stop pausing, so the second (N)onstop prompt -- the one after the
-- who-list -- prints without blocking for a keystroke. Answering it too sent
-- an "n" that fell through to the main menu, which rejected it ("The option
-- you have selected, "N", is not in the above list") and redisplayed itself;
-- that redisplay drew a second "5" out of us, which the BBS still held in its
-- buffer when the game started and delivered into Tele-Arena as chat. Both
-- halves of that were visible in logs/session-tojolias-2026-08-11T22-49-54.log.
--
-- The answers are also gated on login.pending, since they are actively harmful
-- once we are in the game -- a stray "n" walks the character north. Only
-- "Entering Tele-Arena..." clears that gate, and only a fresh "Username:"
-- prompt (i.e. a reconnect) re-arms it and clears the sent-once record.
-- Nothing is sent at all unless TA_CHARACTER is set, so running baud by hand
-- still logs in by hand.
if taPackage.login == nil then
    -- Fresh script load. A reloadScript() mid-session keeps taPackage, and so
    -- keeps a cleared `pending`, rather than re-arming these answers under a
    -- character who is standing in the arena.
    taPackage.login = { pending = true, sent = {} }
end

-- A reload of a session that predates the sent-once record still has to find
-- one here.
taPackage.login.sent = taPackage.login.sent or {}

-- Re-read on every load so a reload picks up a changed environment. getenv is
-- guarded because baud only grew it recently: an older build (the VPS copy,
-- say) would otherwise fail to load this script at all.
if getenv then
    taPackage.login.character = getenv("TA_CHARACTER")
    taPackage.login.password = getenv("TA_PASSWORD")
    -- Optional: what to do once we are in the game. Usually an alias
    -- (TA_INIT_CMD="rg 2"), which is why it is run through runCommand rather
    -- than sent. See runLoginInitCmd below for when it fires.
    taPackage.login.initCmd = getenv("TA_INIT_CMD")
    -- Optional: what to run at the login prompt, before any of the menus. The
    -- only one of the two that reaches a dead character (see above).
    taPackage.login.loginCmd = getenv("TA_LOGIN_CMD")
end

-- Run TA_INIT_CMD, once, now that the entry `st`/`i` replies have been parsed.
--
-- Timing is the whole reason this is a separate step rather than two more lines
-- in the "Entering Tele-Arena..." handler: that handler fires `st` and `i`, and
-- their replies are still in flight when it returns. Anything depending on the
-- character sheet would be refused -- "rg 2" checks getClass() and bails with
-- "Class unknown - run 'st' first". The inventory's gold line is the last reply
-- of that pair, so by the time it lands the sheet is fully parsed.
-- Run one of the two login commands, naming it so the echo says which fired.
function loginRunCommand(varName, cmd)
    cecho("cyan", "[login] running " .. varName .. ": " .. cmd)
    if runCommand then
        runCommand(cmd)
    else
        -- Older baud (the VPS copy, say) has no runCommand, and send() cannot
        -- reach an alias -- it would put the literal text on the wire. A plain
        -- game command still works; say so rather than failing silently.
        cecho("yellow", "[login] this baud has no runCommand - sending as a raw command")
        send(cmd)
    end
end

function runLoginInitCmd()
    if not taPackage.login.initPending then return end
    taPackage.login.initPending = nil
    loginRunCommand("TA_INIT_CMD", taPackage.login.initCmd)
end

-- Answer `step` with `text`, unless we already answered it during this login.
function loginAnswer(step, text)
    if not (taPackage.login.pending and taPackage.login.character) then return end
    if taPackage.login.sent[step] then return end
    taPackage.login.sent[step] = true
    send(text)
end

createTrigger("^Username:\\s*$", function()
    taPackage.awaitingUsername = true
    -- A username prompt means we are at the front door again, whatever
    -- happened before it, so this is where a login starts over.
    taPackage.login.pending = true
    taPackage.login.sent = {}
    -- An init command armed by a previous login but never run (we dropped the
    -- connection before the sheet came back) belongs to that login, not this
    -- one. This login arms its own when it gets in.
    taPackage.login.initPending = nil
    if not taPackage.login.character then return end
    cecho("cyan", "[login] logging in as " .. taPackage.login.character)
    loginAnswer("username", taPackage.login.character)
end, { type = "regex" })

-- TA_LOGIN_CMD, on the same prompt but as a SECOND trigger so it runs after the
-- one above: the username has already gone out by then, which matters because
-- the outbound trigger at the bottom of this file reads the next thing we send
-- as the character's name. Registered here rather than folded into the handler
-- above so that ordering is a visible property of the file, not a comment.
--
-- Not gated on TA_CHARACTER -- arming a script is just as useful when you typed
-- the username yourself -- but it IS gated on login.pending and recorded in
-- login.sent, so a re-displayed prompt cannot run it twice.
createTrigger("^Username:\\s*$", function()
    local cmd = taPackage.login.loginCmd
    if not cmd then return end
    if taPackage.login.sent["logincmd"] then return end
    taPackage.login.sent["logincmd"] = true
    loginRunCommand("TA_LOGIN_CMD", cmd)
end, { type = "regex" })

createTrigger("^Password:\\s*$", function()
    if not (taPackage.login.pending and taPackage.login.character) then return end
    if not taPackage.login.password then
        cecho("yellow", "[login] TA_PASSWORD is not set - type the password yourself")
        return
    end
    loginAnswer("password", taPackage.login.password)
end, { type = "regex" })

createTrigger("^\\(N\\)onstop, \\(Q\\)uit, or \\(C\\)ontinue\\?", function()
    loginAnswer("nonstop", "n")
end, { type = "regex" })

createTrigger("^Make your selection", function()
    loginAnswer("menu", "5")
end, { type = "regex" })

createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    taPackage.login.pending = false
    -- Armed here, fired later by runLoginInitCmd. Not gated on TA_CHARACTER: an
    -- init command is just as useful when you logged in by hand.
    if taPackage.login.initCmd then taPackage.login.initPending = true end
end, { type = "regex" })

createOutboundTrigger("^(.+)$", function(matches)
    if not taPackage.awaitingUsername then return end
    taPackage.awaitingUsername = false
    local username = matches[2]
    taPackage.character.name = username:sub(1, 1):upper() .. username:sub(2)
end, { type = "regex" })

echo("Finishing reading main.lua")
