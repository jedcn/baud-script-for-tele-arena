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

local xpProgressColors = { "white", "cyan", "green", "yellow", "red" }

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

createTrigger("^Status:\\s+(\\S+)$", function(matches)
    setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Mana:\\s+(\\d+) / (\\d+)$", function(matches)
    setMana(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    setVitality(matches[2], matches[3])
    if not taPackage.reRolling then return end

    local intellect       = taPackage.character.intellect or 0
    local knowledge       = taPackage.character.knowledge or 0
    local physique        = taPackage.character.physique or 0
    local stamina         = taPackage.character.stamina or 0
    local agility         = taPackage.character.agility or 0
    local charisma        = taPackage.character.charisma or 0

    taPackage.reRollCount = (taPackage.reRollCount or 0) + 1
    local n               = taPackage.reRollCount

    -- Elf Sorceror: exact floors on Int/Kno/Sta, combined Phy+Cha deficit <= 5, Agi ignored
    local hardFloors      = { intellect = 22, knowledge = 25, stamina = 15 }
    local softThreshold   = 5
    local floorsOk        = intellect >= hardFloors.intellect
        and knowledge >= hardFloors.knowledge
        and stamina >= hardFloors.stamina
    local deficit         = math.max(0, 15 - physique) + math.max(0, 21 - charisma)

    if not taPackage.reRollBestDeficit or deficit < taPackage.reRollBestDeficit then
        taPackage.reRollBestDeficit = deficit
    end
    local best = taPackage.reRollBestDeficit

    local summary = "Int=" .. intellect .. " Kno=" .. knowledge .. " Phy=" .. physique
        .. " Sta=" .. stamina .. " Agi=" .. agility .. " Cha=" .. charisma
        .. " (deficit=" .. deficit .. " best=" .. best .. ")"

    if floorsOk and deficit <= softThreshold then
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

function getKnownMonsters()
    local names = {}
    for name in pairs(taPackage.monsterDb.monsters) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        echo(name)
    end
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
    if taPackage.followTarget then
        local ft = taPackage.followTarget
        nameText = nameText .. " Following " .. ft:sub(1, 1):upper() .. ft:sub(2)
    end
    if taPackage.followedBy and #taPackage.followedBy > 0 then
        nameText = nameText .. " Leader (" .. #taPackage.followedBy .. ")"
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

local function arenaAttack()
    local name = taPackage.arenaMonster
    if name then
        if taPackage.arenaAttackPending then return end
        taPackage.arenaAttackPending = true
        local target = name:match("^(%S+)")
        if getClass() == "Sorceror" then
            arenaDebugEcho("cast-sent")
            arenaSend("cast komiza " .. target)
        else
            arenaDebugEcho("attack-sent")
            arenaSend("a " .. target)
        end
    end
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

local function checkFleeArena()
    if taPackage.arenaState ~= "fighting" then return false end
    local hp = taPackage.character.vitalityCurrent
    local maxHp = taPackage.character.vitalityMax
    local fleeThreshold = maxHp and math.floor(maxHp * 0.6) or 50
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
    taPackage.arenaXpCheckPending = false
    taPackage.arenaState = "ringing"
    local startXpStr = taPackage.arenaSessionStartXp and tostring(taPackage.arenaSessionStartXp) or "unknown"
    local debugSuffix = taPackage.arenaDebug and " (debug mode)" or ""
    echo("[arena] Session started" .. debugSuffix .. ". XP: " .. startXpStr)
    scheduleArenaXpCheck()
    arenaSend("ring gong")
end, { type = "regex" })

createAlias("^stop-ring-gong-and-fight-in-arena$", function()
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
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
    echo("[arena] Stopped.")
end, { type = "regex" })

createTrigger("^An? (.+) enters the arena through the dungeon gate!$", function(matches)
    if taPackage.arenaState ~= "ringing" then return end
    taPackage.arenaMonster = matches[2]
    taPackage.arenaState = "fighting"
    if not taPackage.db.monsterHasDescription(taPackage.arenaMonster) then
        send("look " .. taPackage.arenaMonster)
    end
    arenaAttack()
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
    if taPackage.arenaState == "fighting" and not checkFleeArena() then
        if checkTrainingNeeded() then
            echo("[arena] Leveling up — heading to training hall.")
            taPackage.arenaState = "training"
            taPackage.arenaTrainingPhase = 1
            arenaSend("w")
        else
            taPackage.arenaState = "ringing"
            arenaSend("ring gong")
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
                arenaAttack()
            else
                taPackage.arenaState = "ringing"
                arenaSend("ring gong")
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
    taPackage.arenaAttackPending = false
    arenaDebugEcho("exhausted")
    if taPackage.character.name == "Pelayo" then
        send("cast motu pelayo")
    end
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

createTrigger("^You are still too mentally exhausted from your last incantation!$", function(matches)
    if not taPackage.arenaState then return end
    taPackage.arenaAttackPending = false
    arenaDebugEcho("mentally-exhausted")
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

createOutboundTrigger("^cast kamotu ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
end, { type = "regex" })

createTrigger("^You intoned the spell for (.+) which healed (\\d+) damage!$", function(matches)
    local target = matches[2]
    local amount = tonumber(matches[3])
    taPackage.db.recordPlayerSpell("motu", target, "hit", amount)
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

createAlias("^cast\\.heal$", function()
    local name = taPackage.character.name
    if name then
        send("cast kamotu " .. name:lower())
    end
end, { type = "regex" })

createAlias("^cast\\.heal (.+)$", function(matches)
    send("cast kamotu " .. matches[2])
end, { type = "regex" })

createAlias("^cast\\.ice.dart (.+)$", function(matches)
    send("cast komiza " .. matches[2])
end, { type = "regex" })

createOutboundTrigger("^cast komiza ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
    taPackage.lastSpellCast = "komiza"
end, { type = "regex" })

createTrigger("^You discharged the spell at the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local amount = tonumber(matches[3])
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "hit", amount)
    if taPackage.arenaState == "fighting" then
        taPackage.arenaAttackPending = false
        arenaDebugEcho("our-spell-hit")
        if not checkFleeArena() then arenaAttack() end
    end
end, { type = "regex" })

createTrigger("^You confuse the key syllables and the spell fails!$", function()
    local monster = taPackage.lastAttackTarget or "unknown"
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "fizzle", nil)
    if taPackage.arenaState == "fighting" then
        taPackage.arenaAttackPending = false
        arenaDebugEcho("our-spell-fizzle")
        if not checkFleeArena() then arenaAttack() end
    end
end, { type = "regex" })

createTrigger("^Your spell was negated by the (.+)'s magickal defenses!$", function(matches)
    local monster = matches[2]
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "resist", nil)
    if taPackage.arenaState == "fighting" then
        taPackage.arenaAttackPending = false
        arenaDebugEcho("our-spell-resist")
        if not checkFleeArena() then arenaAttack() end
    end
end, { type = "regex" })

createOutboundTrigger("^cast motu ", function()
    local current = taPackage.character.manaCurrent
    if current then
        taPackage.character.manaCurrent = math.max(0, current - 1)
    end
end, { type = "regex" })

createAlias("^cast\\.minor\\.heal$", function()
    local name = taPackage.character.name
    if name then
        send("cast motu " .. name:lower())
    end
end, { type = "regex" })

createAlias("^cast\\.minor\\.heal (.+)$", function(matches)
    send("cast motu " .. matches[2])
end, { type = "regex" })

-- =========================================================================
-- Kill a single target
-- =========================================================================

local function killAttack()
    local target = taPackage.killTarget
    if target then
        if taPackage.killAttackPending then return end
        taPackage.killAttackPending = true
        local name = target:match("^(%S+)")
        if getClass() == "Sorceror" then
            send("cast komiza " .. name)
        else
            send("a " .. name)
        end
    end
end

local function startKill(target)
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
    taPackage.killAttackPending = false
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    echo("[kill] Attacking " .. taPackage.killTarget .. ".")
    killAttack()
    return true
end
taPackage.startKill = startKill

createAlias("^kill (.+)$", function(matches)
    startKill(matches[2])
end, { type = "regex" })

createAlias("^kill-stop$", function()
    taPackage.killActive = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    echo("[kill] Stopped.")
end, { type = "regex" })

createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^Your attack missed!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^You barely dodge the .+'s attack!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

-- Sorceror spell-outcome continuation. The DB-recording copies of these
-- lines live in the spell section; these re-fire the kill loop the same way
-- the melee triggers above do.
createTrigger("^You discharged the spell at the .+ for \\d+ damage!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^You confuse the key syllables and the spell fails!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^Your spell was negated by the .+'s magickal defenses!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    killAttack()
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    if not taPackage.killActive then return end
    taPackage.killActive = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    echo("[kill] " .. matches[2] .. " is dead.")
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    local gen = taPackage.killGeneration or 0
    createTimer(30000, function()
        if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
            killAttack()
        end
    end, { repeating = false })
end, { type = "regex" })

createTrigger("^You are still too mentally exhausted from your last incantation!$", function()
    if not taPackage.killActive then return end
    taPackage.killAttackPending = false
    local gen = taPackage.killGeneration or 0
    createTimer(30000, function()
        if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
            killAttack()
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

createAlias("^ta\\.follow (.+)$", function(matches)
    taPackage.followTarget = matches[2]:lower()
    echo("[follow] Now following: " .. taPackage.followTarget)
    send("join " .. matches[2])
end, { type = "regex" })

createAlias("^ta\\.follow-stop$", function()
    taPackage.followTarget = nil
    echo("[follow] Stopped following.")
end, { type = "regex" })

createTrigger("^(.+) is asking to join your group\\.$", function(matches)
    local name = matches[2]
    if not taPackage.followedBy then taPackage.followedBy = {} end
    table.insert(taPackage.followedBy, name)
    send("add " .. name:lower())
    echo("[follow] " .. name .. " is now following you.")
end, { type = "regex" })

-- When the leader we're following attacks a monster, join the fight on the
-- same target via the kill loop. The kill loop's death trigger stops us
-- naturally if someone else lands the killing blow first.
createTrigger("^(.+) just attacked the (.+) with .+!$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    if taPackage.killActive then return end
    startKill(matches[3])
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
