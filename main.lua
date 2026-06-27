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
    -- Fallback: baud data dir, which is a known writable absolute path
    return (os.getenv("HOME") or "") .. "/Library/Application Support/baud/"
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

function setMana(current, max)
    taPackage.character.manaCurrent = tonumber(current)
    taPackage.character.manaMax = tonumber(max)
end

function getMana()
    return taPackage.character.manaCurrent, taPackage.character.manaMax
end

function setExperience(value)
    taPackage.character.experience = tonumber(value)
end

function getExperience()
    return taPackage.character.experience
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

function setGold(value)
    taPackage.character.gold = tonumber(value)
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

-- Progress through the current level, from just-leveled (blue) to about-to-level
-- (red), walking across the color wheel through violet/magenta/pink in between.
--   1: first fifth   ( 0-20%)  blue
--   2: second fifth  (20-40%)  blue-violet
--   3: third fifth   (40-60%)  purple/magenta
--   4: fourth fifth  (60-80%)  pink-red
--   5: fifth fifth   (80-99%)  red
local xpProgressColors = { "#0000ff", "#4000bf", "#800080", "#bf0040", "#ff0000" }

local function xpColor(xp, class)
    if not xp then return "white" end
    local level = getLevelForXp(xp, class)
    local thresholds = xpThresholds[class or "Warrior"]
    if level >= 25 then return xpProgressColors[5] end
    local levelStart = thresholds[level]
    local levelEnd   = thresholds[level + 1]
    local progress   = (xp - levelStart) / (levelEnd - levelStart)
    local idx        = math.min(5, math.floor(progress * 5) + 1)
    return xpProgressColors[idx]
end

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

-- On entering the arena, pull our character sheet (st) and inventory (i) so the
-- script's tracked state is populated right away instead of waiting for the
-- first manual status check.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    send("st")
    send("i")
end, { type = "regex" })

createTrigger("^Status:\\s+(\\S+)$", function(matches)
    setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Mana:\\s+(\\d+) / (\\d+)$", function(matches)
    setMana(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    setVitality(matches[2], matches[3])
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

createTrigger("^While searching the area, you notice (.+), which you add to your possessions\\.$", function(matches)
    local item = matches[2]
    local monster = taPackage.lastKilledMonster or "unknown"
    taPackage.db.recordItemDrop(monster, item)
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

local function isRoomLine(line)
    return string.match(line, "^You're in ")
        or string.match(line, "^You are in ")
        or string.match(line, "^You are inside ")
end

local function isRoomDescTerminator(line)
    return string.match(line, "^Sorry,")
        or isRoomLine(line)
        or string.match(line, "^There is ")
        or string.match(line, "^An? .+ enters ")
        or string.match(line, DIRECTION_PATTERN)
        or isHealthLine(line)
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
        if line == "look" or line == "l" then return end
        if isRoomDescTerminator(line) then
            local lines = taPackage.monsterDb.accumulatedLines
            if #lines > 0 and taPackage.currentRoom then
                local desc = cleanRoomDesc(table.concat(lines, " "))
                if #desc > 0 then
                    taPackage.db.upsertRoomDescription(taPackage.currentRoom, desc)
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

local function handleRoomEntry(matches)
    local newRoom = matches[2]
    if taPackage.pendingLootCheck and taPackage.lastKilledMonster then
        taPackage.db.recordMonsterLoot(taPackage.lastKilledMonster, 0)
        taPackage.pendingLootCheck = nil
        taPackage.lastKilledMonster = nil
    end
    if taPackage.pendingDirection and taPackage.prevRoom then
        taPackage.db.recordExit(taPackage.prevRoom, taPackage.pendingDirection, newRoom)
    end
    taPackage.db.visitRoom(newRoom)
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.currentRoom = newRoom
    taPackage.pendingDirection = nil
end

createTrigger("^You're in the (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You are in the (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're in an? (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You are in an? (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're inside the (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You are inside the (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You're inside an? (.+)\\.$", handleRoomEntry, { type = "regex" })
createTrigger("^You are inside an? (.+)\\.$", handleRoomEntry, { type = "regex" })

local moveDirections = { "n", "s", "e", "w", "ne", "nw", "se", "sw" }
for _, dir in ipairs(moveDirections) do
    createAlias("^" .. dir .. "$", function()
        taPackage.pendingDirection = dir
        taPackage.prevRoom = taPackage.currentRoom
        send(dir)
    end, { type = "regex" })
end

-- =========================================================================
-- Combat triggers
-- =========================================================================

createTrigger("^Your attack hit the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    taPackage.lastAttackTarget = monster
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

createTrigger("^The (.+) attacked you .+ for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    local current, max = getVitality()
    if current then
        setVitality(current - damage, max)
    end
    taPackage.db.recordMonsterAttack(monster, "hit", damage)
end, { type = "regex" })

-- Special attacks don't use the "attacked you ... for N damage!" phrasing, so
-- the generic incoming-damage trigger above misses them and our HP drifts high
-- against some of the hardest hits in the game (a stone giant's boulder has been
-- seen for 52, a cyclops's throw for 22). Catch each special verb explicitly and
-- apply the damage the same way. Only the "you" variants carry a number; when
-- these land on another group member the game prints no damage ("hurled a
-- boulder at Pelayo!"), so there is nothing to subtract from our own vitality.
createTrigger("^The (.+) hurled a boulder at you for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    local current, max = getVitality()
    if current then
        setVitality(current - damage, max)
    end
    taPackage.db.recordMonsterAttack(monster, "hit", damage)
end, { type = "regex" })

createTrigger("^The (.+) picks up and hurls you for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    local current, max = getVitality()
    if current then
        setVitality(current - damage, max)
    end
    taPackage.db.recordMonsterAttack(monster, "hit", damage)
end, { type = "regex" })

createTrigger("^The (.+) breathed flames at you for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local damage = tonumber(matches[3])
    local current, max = getVitality()
    if current then
        setVitality(current - damage, max)
    end
    taPackage.db.recordMonsterAttack(monster, "hit", damage)
end, { type = "regex" })

createTrigger("^The (.+) attacked you, but .+ glanced off your armor!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "glanced", nil)
end, { type = "regex" })

createTrigger("^The (.+)'s? .+ misses? you!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "miss", nil)
end, { type = "regex" })

createTrigger("^You barely dodge the (.+)'s attack!$", function(matches)
    taPackage.db.recordMonsterAttack(matches[2], "dodge", nil)
end, { type = "regex" })

-- =========================================================================
-- Loot and kill triggers
-- =========================================================================

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    local name = matches[2]
    clearPresence(name)
    taPackage.lastKilledMonster = name
    taPackage.pendingLootCheck = true
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

local function status()
    local charStatus = getCharacterStatus() or "?"
    local vitalityCurrent, vitalityMax = getVitality()
    local manaCurrent, manaMax = getMana()
    local xp = getExperience()
    local nextLevelXp = xp and getXpForNextLevel(xp, getClass())
    local gold = getGold() and tostring(getGold()) or "?"

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
            text = vitalityCurrent and tostring(vitalityCurrent) or "?",
            fg = vitalityColor(vitalityCurrent, vitalityMax)
        },
        { text = vitalityMax and ("/ " .. tostring(vitalityMax)) or "", fg = "white" },
    }
    if manaMax and manaMax > 0 then
        table.insert(segments, { text = "MP:", fg = "green" })
        table.insert(segments, { text = manaCurrent and tostring(manaCurrent) or "?", fg = "cyan" })
        table.insert(segments, { text = "/ " .. tostring(manaMax), fg = "cyan" })
    end
    local tail = {
        { text = "XP:" },
        { text = xp and tostring(xp) or "?", fg = xpColor(xp, getClass()) },
        {
            text = xp and ("/ " .. (nextLevelXp and tostring(nextLevelXp) or "max")) or "",
            fg = "white"
        },
        { text = "Status:" },
        { text = charStatus, fg = (charStatus == "Thirsty" or charStatus == "Hungry") and "red" or "white" },
        { text = "Gold:" },
        { text = gold,       fg = "yellow" },
    }
    for _, seg in ipairs(tail) do table.insert(segments, seg) end
    return segments
end

setStatus(status)

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
        local target = name:match("^(%S+)")
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
    local target = name:match("^(%S+)")
    arenaDebugEcho("cast-sent")
    arenaSend("cast toduza " .. target)
end

-- Ringing the gong is itself a physical action. Right after a melee kill the
-- physical clock is spent, so the immediate ring is rejected with "still
-- physically exhausted" — the same retry treatment the swing gets keeps the
-- loop alive. The pending guard means a stale retry timer can't double-ring.
local ARENA_RING_RETRY_MS = 3000
local function arenaRing()
    if taPackage.arenaRingPending then return end
    taPackage.arenaRingPending = true
    arenaSend("ring gong")
end

local function checkTrainingNeeded()
    local xp  = getExperience()
    local cls = getClass()
    local lvl = getLevel()
    if not (xp and cls and lvl) then return false end
    local thresholds = xpThresholds[cls]
    if not thresholds then return false end
    local nextThreshold = thresholds[lvl + 1]
    return nextThreshold ~= nil and xp >= nextThreshold
end

-- Flee at 75% of max HP, but never below an absolute floor. The percentage
-- alone is unsafe for low-HP characters: a level-2 Sorceror (31 max HP) at 60%
-- fled at 18, and a cave bear's worst observed round is 23 damage (two claws)
-- — so he could cross from "fine" to dead in one round. The floor guarantees
-- enough headroom to survive the round in which the flee is decided. 25 covers
-- a cave bear's worst round (23) with a small margin.
local FLEE_HP_FRACTION = 0.75
local FLEE_HP_FLOOR = 25
local function checkFleeArena()
    if taPackage.arenaState ~= "fighting" then return false end
    local hp = taPackage.character.vitalityCurrent
    local maxHp = taPackage.character.vitalityMax
    local fleeThreshold = maxHp and math.max(math.floor(maxHp * FLEE_HP_FRACTION), FLEE_HP_FLOOR) or FLEE_HP_FLOOR
    if hp and hp < fleeThreshold then
        arenaDebugEcho("flee-triggered")
        taPackage.arenaState = "fleeing"
        arenaSend("w")
        return true
    end
    return false
end

local function departForTavern()
    taPackage.arenaState = "tavern"
    echo("[arena] Heading to tavern.")
    arenaSend("w")
end

local function scheduleArenaXpCheck()
    local gen = taPackage.arenaXpTimerGen or 0
    createTimer(300000, function()
        if (taPackage.arenaXpTimerGen or 0) ~= gen then return end
        taPackage.arenaXpCheckPending = true
        send("status")
        scheduleArenaXpCheck()
    end, { repeating = false })
end

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
    setExperience(matches[2])
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
    if taPackage.arenaState == "ringing" and checkTrainingNeeded() then
        echo("[arena] Leveling up — heading to training hall.")
        taPackage.arenaState = "training"
        taPackage.arenaTrainingPhase = 1
        arenaSend("w")
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
end, { type = "regex" })

createAlias("^ring-gong-and-fight-in-arena(.*)$", function(matches)
    if not getClass() then
        echo("[arena] Class unknown — run 'st' first so casters cast.")
        return
    end
    taPackage.arenaDebug = matches[2] == " debug"
    taPackage.arenaSessionStartXp = taPackage.character.experience
    taPackage.arenaSessionStartTime = os.time()
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
    taPackage.arenaCombatGen = (taPackage.arenaCombatGen or 0) + 1
    taPackage.arenaXpCheckPending = false
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    taPackage.arenaRingRetryScheduled = false
    taPackage.arenaState = "ringing"
    local startXpStr = taPackage.arenaSessionStartXp and tostring(taPackage.arenaSessionStartXp) or "unknown"
    local debugSuffix = taPackage.arenaDebug and " (debug mode)" or ""
    echo("[arena] Session started" .. debugSuffix .. ". XP: " .. startXpStr)
    scheduleArenaXpCheck()
    arenaRing()
end, { type = "regex" })

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
    taPackage.arenaRingRetryScheduled = nil
    echo("[arena] Stopped.")
end
taPackage.stopArena = stopArena

createAlias("^stop-ring-gong-and-fight-in-arena$", function()
    stopArena()
end, { type = "regex" })

createTrigger("^An? (.+) enters the arena through the dungeon gate!$", function(matches)
    if taPackage.arenaState ~= "ringing" then return end
    taPackage.arenaMonster = matches[2]
    taPackage.arenaState = "fighting"
    if not taPackage.db.monsterHasDescription(taPackage.arenaMonster) then
        send("look " .. taPackage.arenaMonster)
    end
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    arenaAttack()
    arenaCast()
end, { type = "regex" })

createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    taPackage.arenaAttackPending = false
    arenaDebugEcho("our-hit")
    if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    taPackage.arenaAttackPending = false
    arenaDebugEcho("our-miss")
    if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    taPackage.arenaAttackPending = false
    arenaDebugEcho("monster-dodge")
    if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    if taPackage.arenaState ~= "fighting" and taPackage.arenaState ~= "fleeing" then return end
    taPackage.arenaMonster = nil
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    if taPackage.arenaState == "fighting" and not checkFleeArena() then
        if checkTrainingNeeded() then
            echo("[arena] Leveling up — heading to training hall.")
            taPackage.arenaState = "training"
            taPackage.arenaTrainingPhase = 1
            arenaSend("w")
        else
            taPackage.arenaState = "ringing"
            taPackage.arenaRingPending = false
            arenaRing()
        end
    end
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

createTrigger("^You're in the (.+)\\.$", function(matches)
    local room = matches[2]
    if taPackage.arenaState == "training" then
        local phase = taPackage.arenaTrainingPhase or 1
        if phase == 1 and room == "north plaza" then
            taPackage.arenaTrainingPhase = 2
            arenaSend("n")
        elseif phase == 2 then
            send("buy training")
            arenaSend("s")
            taPackage.arenaState = "returning"
            taPackage.arenaTrainingPhase = nil
        end
    elseif taPackage.arenaState == "fleeing" then
        if room == "north plaza" then
            arenaSend("w")
        elseif room == "temple" then
            taPackage.arenaState = "healing"
            arenaSend("buy healing")
        end
    elseif taPackage.arenaState == "tavern" then
        if room == "north plaza" then
            arenaSend("ne")
        elseif room == "tavern" then
            if taPackage.needsDrinks then
                for _ = 1, 3 do send("buy drink") end
                taPackage.needsDrinks = nil
            end
            if taPackage.needsMeal then
                for _ = 1, 3 do send("buy meal") end
                taPackage.needsMeal = nil
            end
            taPackage.arenaState = "returning"
            arenaSend("sw")
        end
    elseif taPackage.arenaState == "returning" then
        if room == "north plaza" then
            arenaSend("e")
        elseif room == "arena" then
            if taPackage.arenaMonster then
                taPackage.arenaState = "fighting"
                taPackage.arenaAttackPending = false
                taPackage.arenaCastPending = false
                arenaAttack()
                arenaCast()
            else
                taPackage.arenaState = "ringing"
                taPackage.arenaRingPending = false
                arenaRing()
            end
        end
    end
end, { type = "regex" })

createTrigger("^You're thirsty\\.$", function()
    setCharacterStatus("Thirsty")
    if not taPackage.arenaState then return end
    taPackage.needsDrinks = true
    if taPackage.arenaState == "fighting" or taPackage.arenaState == "ringing" then
        departForTavern()
    else
        echo("[arena] Thirsty — will buy drinks at next tavern visit.")
    end
end, { type = "regex" })

createTrigger("^You're hungry\\.$", function()
    setCharacterStatus("Hungry")
    if not taPackage.arenaState then return end
    taPackage.needsMeal = true
    if taPackage.arenaState == "fighting" or taPackage.arenaState == "ringing" then
        departForTavern()
    else
        echo("[arena] Hungry — will buy a meal at next tavern visit.")
    end
end, { type = "regex" })

createTrigger("^The priests heal all your wounds for \\d+ crowns\\.$", function(matches)
    if taPackage.arenaState ~= "healing" then return end
    if taPackage.needsDrinks or taPackage.needsMeal then
        taPackage.arenaState = "tavern"
        echo("[arena] Heading to tavern.")
    else
        taPackage.arenaState = "returning"
    end
    arenaSend("e")
end, { type = "regex" })

createTrigger("^You cannot leave in the heat of battle!$", function()
    if taPackage.arenaState ~= "fleeing" and taPackage.arenaState ~= "tavern" then return end
    if taPackage.arenaFleeTimerPending then return end
    taPackage.arenaFleeTimerPending = true
    local gen = taPackage.arenaRetryGeneration or 0
    createTimer(2000, function()
        taPackage.arenaFleeTimerPending = false
        if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
            arenaSend("w")
        end
    end, { repeating = false })
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function(matches)
    if not taPackage.arenaState then return end
    local cmd = taPackage.arenaLastCmd
    local gen = taPackage.arenaRetryGeneration or 0
    if cmd then
        createTimer(30000, function()
            if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
                arenaSend(cmd)
            end
        end, { repeating = false })
    end
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function(matches)
    if not taPackage.arenaState then return end
    arenaDebugEcho("exhausted")
    if taPackage.character.name == "Pelayo" then
        send("cast motu pelayo")
    end
    -- A stable combat generation (not the per-send retry counter) keeps these
    -- timers alive even though the cast loop keeps firing arenaSend meanwhile.
    local gen = taPackage.arenaCombatGen or 0
    if taPackage.arenaState == "ringing" then
        -- The blocked physical action was the gong ring (the kill just spent
        -- the physical clock). Retry the ring, not a swing — there's no monster
        -- to swing at, so retrying arenaAttack would silently stall the loop.
        --
        -- A kill bounces two physical actions in the same instant — the trailing
        -- melee swing and the fresh gong — so this handler fires twice back to
        -- back. The arenaRingPending guard already stops a real double-ring, but
        -- without this dedupe each bounce still churns its own retry timer. Keep
        -- at most one retry outstanding; the callback clears the flag when it
        -- fires so the next bounce can re-arm.
        if taPackage.arenaRingRetryScheduled then return end
        taPackage.arenaRingRetryScheduled = true
        taPackage.arenaRingPending = false
        createTimer(ARENA_RING_RETRY_MS, function()
            taPackage.arenaRingRetryScheduled = false
            if taPackage.arenaState == "ringing" and (taPackage.arenaCombatGen or 0) == gen then
                arenaRing()
            end
        end, { repeating = false })
    else
        -- Melee is on cooldown; retry the swing once the physical clock recovers.
        taPackage.arenaAttackPending = false
        createTimer(30000, function()
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
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", target, "hit", amount, "heal")
    if target == taPackage.character.name then
        local current = taPackage.character.vitalityCurrent
        local max = taPackage.character.vitalityMax
        if current and amount then
            taPackage.character.vitalityCurrent = max and math.min(current + amount, max) or (current + amount)
        end
    end
end, { type = "regex" })

createTrigger("^(.+) just intoned a minor healing spell for you which healed (\\d+) damage!$", function(matches)
    local amount = tonumber(matches[3])
    local current = taPackage.character.vitalityCurrent
    local max = taPackage.character.vitalityMax
    if current and amount then
        taPackage.character.vitalityCurrent = max and math.min(current + amount, max) or (current + amount)
    end
end, { type = "regex" })

createTrigger("^(.+) just intoned a healing spell for you which healed (\\d+) damage!$", function(matches)
    local amount = tonumber(matches[3])
    local current = taPackage.character.vitalityCurrent
    local max = taPackage.character.vitalityMax
    if current and amount then
        taPackage.character.vitalityCurrent = max and math.min(current + amount, max) or (current + amount)
    end
end, { type = "regex" })

createAlias("^cast\\.ice.dart (.+)$", function(matches)
    send("cast komiza " .. matches[2])
end, { type = "regex" })

createAlias("^cast\\.fire.dart (.+)$", function(matches)
    send("cast toduza " .. matches[2])
end, { type = "regex" })

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

-- Heal spells, weakest to strongest: motu (Minor Heal, 1 MP) via
-- cast.minor.heal and kamotu (Heal, 2 MP) via cast.heal. Each has a self form
-- (no arg → the caster) and a targeted form. Gimotu (Greater Heal, 4 MP,
-- level 8) will join this family as cast.greater.heal once we can learn it.
createAlias("^cast\\.minor\\.heal$", function()
    local name = taPackage.character.name
    if name then
        send("cast motu " .. name:lower())
    end
end, { type = "regex" })

createAlias("^cast\\.minor\\.heal (.+)$", function(matches)
    send("cast motu " .. matches[2])
end, { type = "regex" })

createAlias("^cast\\.heal$", function()
    local name = taPackage.character.name
    if name then
        send("cast kamotu " .. name:lower())
    end
end, { type = "regex" })

createAlias("^cast\\.heal (.+)$", function(matches)
    send("cast kamotu " .. matches[2])
end, { type = "regex" })

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
createAlias("^kill (.+)$", function(matches)
    local rest = matches[2]
    local target, debug = rest, false
    local stripped = rest:match("^(.-) debug$")
    if stripped then
        target, debug = stripped, true
    end
    startKill(target, debug)
end, { type = "regex" })

local function stopKill()
    killDebugEcho("kill-stop")
    taPackage.killActive = false
    taPackage.killDebug = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.healTarget = nil
    taPackage.groupHealPhase = nil
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    echo("[kill] Stopped.")
end
taPackage.stopKill = stopKill

createAlias("^stop-kill$", function()
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

-- Stops every long-running script at once. Each sub-stop is independent and
-- safe to call when its script isn't running (it just resets already-clear
-- state), so this is a no-op for whatever wasn't active.
createAlias("^stop-all-scripts$", function()
    echo("[all] Stopping all scripts.")
    stopArena()
    stopHealLoop()
    stopKill()
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

createTrigger("^Username:\\s*$", function()
    taPackage.awaitingUsername = true
end, { type = "regex" })

createOutboundTrigger("^(.+)$", function(matches)
    if not taPackage.awaitingUsername then return end
    taPackage.awaitingUsername = false
    local username = matches[2]
    taPackage.character.name = username:sub(1, 1):upper() .. username:sub(2)
end, { type = "regex" })

echo("Finishing reading main.lua")
