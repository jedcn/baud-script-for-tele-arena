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

if not taPackage.db then
  taPackage.db = dofile(scriptDir .. "ta_db.lua")
end

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

-- =========================================================================
-- XP tables by class (from "help Exp1" and "help Exp2")
-- =========================================================================

local xpThresholds = {
  Warrior = {
    [1]=0,        [2]=1125,     [3]=3240,     [4]=8025,     [5]=17890,
    [6]=36000,    [7]=66300,    [8]=113400,   [9]=182600,   [10]=280200,
    [11]=413000,  [12]=588700,  [13]=815600,  [14]=1102800, [15]=1460100,
    [16]=1898300, [17]=2428600, [18]=3063100, [19]=3814700, [20]=4696900,
    [21]=5724000, [22]=6911200, [23]=8274200, [24]=9829700, [25]=11594700,
  },
  Archer = {
    [1]=0,        [2]=1125,     [3]=3240,     [4]=8025,     [5]=17890,
    [6]=36000,    [7]=66300,    [8]=113400,   [9]=182600,   [10]=280200,
    [11]=413000,  [12]=588700,  [13]=815600,  [14]=1102800, [15]=1460100,
    [16]=1898300, [17]=2428600, [18]=3063100, [19]=3814700, [20]=4696900,
    [21]=5724000, [22]=6911200, [23]=8274200, [24]=9829700, [25]=11594700,
  },
  Hunter = {
    [1]=0,        [2]=1125,     [3]=3240,     [4]=8025,     [5]=17890,
    [6]=36000,    [7]=66300,    [8]=113400,   [9]=182600,   [10]=280200,
    [11]=413000,  [12]=588700,  [13]=815600,  [14]=1102800, [15]=1460100,
    [16]=1898300, [17]=2428600, [18]=3063100, [19]=3814700, [20]=4696900,
    [21]=5724000, [22]=6911200, [23]=8274200, [24]=9829700, [25]=11594700,
  },
  Rogue = {
    [1]=0,        [2]=1120,     [3]=3200,     [4]=7860,     [5]=17440,
    [6]=35000,    [7]=64400,    [8]=109900,   [9]=177000,   [10]=271500,
    [11]=400000,  [12]=570100,  [13]=789600,  [14]=1067600, [15]=1413500,
    [16]=1837500, [17]=2350800, [18]=2964800, [19]=3692200, [20]=4546000,
    [21]=5540000, [22]=6689000, [23]=8008000, [24]=9513300, [25]=11221500,
  },
  Acolyte = {
    [1]=0,        [2]=1150,     [3]=3490,     [4]=9025,     [5]=20640,
    [6]=42200,    [7]=78200,    [8]=134300,   [9]=216900,   [10]=333500,
    [11]=492000,  [12]=701800,  [13]=972800,  [14]=1315900, [15]=1742800,
    [16]=2266200, [17]=2899600, [18]=3657600, [19]=4555300, [20]=5609100,
    [21]=6836000, [22]=8254100, [23]=9882100, [24]=11739900,[25]=13848000,
  },
  Sorceror = {
    [1]=0,        [2]=1180,     [3]=3800,     [4]=10290,    [5]=24160,
    [6]=50000,    [7]=93500,    [8]=161400,   [9]=261500,   [10]=402700,
    [11]=595000,  [12]=849600,  [13]=1178400, [14]=1594900, [15]=2113200,
    [16]=2748800, [17]=3518100, [18]=4438700, [19]=5529300, [20]=6809500,
    [21]=8300000, [22]=10022900,[23]=12001000,[24]=14258400,[25]=16820200,
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

createTrigger("^Status:\\s+(\\S+)$", function(matches)
  setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
  setVitality(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
  setExperience(matches[2])
end, { type = "regex" })

createTrigger("^Class:\\s+(\\S+)$", function(matches)
  setClass(matches[2])
end, { type = "regex" })

createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
  setGold(matches[2])
end, { type = "regex" })

createTrigger("^You found (\\d+) gold crowns while searching", function(matches)
  local found = tonumber(matches[2])
  setGold((getGold() or 0) + found)
  if taPackage.pendingLootCheck and taPackage.lastKilledMonster then
    taPackage.db.recordMonsterLoot(taPackage.lastKilledMonster, found)
    taPackage.pendingLootCheck = nil
    taPackage.lastKilledMonster = nil
  end
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
      or string.find(line, "in good health") ~= nil
      or string.find(line, "falls to the ground lifeless") ~= nil
end

local function extractMonsterName(firstLine)
  return string.match(firstLine, "^The (.+) is ") or string.match(firstLine, "^The (.+) has ")
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

createTrigger("^l (.+)$", function(matches)
  taPackage.monsterDb.state = "accumulating"
  taPackage.monsterDb.lookTarget = matches[2]
  taPackage.monsterDb.accumulatedLines = {}
end, { type = "regex" })

local function recordEncounter(name)
  local entry = taPackage.monsterDb.monsters[name]
  if entry then
    entry.encounters = entry.encounters + 1
    pcall(taPackage.monsterDb.db.save, taPackage.monsterDb.dbPath, taPackage.monsterDb.monsters)
  end
end

createTrigger("^There is a (.+) here\\.$", function(matches)
  local name = matches[2]
  recordEncounter(name)
  taPackage.db.recordMonsterSeen(name)
end, { type = "regex" })

createTrigger("^An? (.+) enters ", function(matches)
  local name = matches[2]
  recordEncounter(name)
  taPackage.db.recordMonsterSeen(name)
end, { type = "regex" })

createTrigger("^(.+)$", function(matches)
  if taPackage.monsterDb.state ~= "accumulating" then return end
  local line = matches[2]
  if string.match(line, "^l .") then return end
  if string.match(line, "^You're in the") or string.match(line, "^There is ") then
    taPackage.monsterDb.state = "idle"
    taPackage.monsterDb.accumulatedLines = {}
    return
  end
  if isHealthLine(line) then
    local lines = taPackage.monsterDb.accumulatedLines
    if #lines > 0 then
      local canonicalName = extractMonsterName(lines[1]) or taPackage.monsterDb.lookTarget
      local desc = table.concat(lines, " ")
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

createTrigger("^You're in the (.+)\\.$", function(matches)
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
end, { type = "regex" })

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

createTrigger("^The (.+)'s .+ glanced off your armor!$", function(matches)
  taPackage.db.recordMonsterAttack(matches[2], "glanced", nil)
end, { type = "regex" })

createTrigger("^The (.+)'s? .+ misses? you!$", function(matches)
  taPackage.db.recordMonsterAttack(matches[2], "miss", nil)
end, { type = "regex" })

-- =========================================================================
-- Loot and kill triggers
-- =========================================================================

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
  taPackage.lastKilledMonster = matches[2]
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
  if pct >= 0.66 then return "green"
  elseif pct >= 0.33 then return "yellow"
  else return "red"
  end
end

local function status()
  local charStatus = getCharacterStatus() or "?"
  local vitalityCurrent, vitalityMax = getVitality()
  local vitalityText = (vitalityCurrent and vitalityMax)
    and (vitalityCurrent .. "/" .. vitalityMax)
    or "?"
  local xp = getExperience()
  local nextLevelXp = xp and getXpForNextLevel(xp, getClass())
  local gold = getGold() and tostring(getGold()) or "?"

  local segments = {
    { text = "HP" },
    { text = vitalityCurrent and tostring(vitalityCurrent) or "?",
      fg = vitalityColor(vitalityCurrent, vitalityMax) },
    { text = vitalityMax and ("/ " .. tostring(vitalityMax)) or "", fg = "white" },
    { text = "XP" },
    { text = xp and tostring(xp) or "?", fg = xpColor(xp, getClass()) },
    { text = xp and ("/ " .. (nextLevelXp and tostring(nextLevelXp) or "max")) or "",
      fg = "white" },
    { text = "Status" },
    { text = charStatus, fg = "white" },
    { text = "Gold" },
    { text = gold, fg = "white" },
  }
  return segments
end

setStatus(status)

echo("Finishing reading main.lua")
