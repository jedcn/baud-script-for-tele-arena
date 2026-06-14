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

createTrigger("^Weapon:\\s+(.+)$", function(matches)
  taPackage.character.weapon = matches[2]
end, { type = "regex" })

createTrigger("^Physique:\\s+(\\d+)$", function(matches)
  setPhysique(matches[2])
end, { type = "regex" })

createTrigger("^Stamina:\\s+(\\d+)$", function(matches)
  setStamina(matches[2])
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
  for _, verb in ipairs({" is ", " has ", " resembles ", " appears "}) do
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
  for _, sep in ipairs({". The ", ". It "}) do
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

createTrigger("^(.+)$", function(matches)
  if taPackage.monsterDb.state ~= "accumulating" then return end
  local line = matches[2]
  if string.match(line, "^l .") or string.match(line, "^look .") then return end
  if string.match(line, "^You're in the") or string.match(line, "^There is ") then
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

createTrigger("^The (.+) attacked you, but .+ glanced off your armor!$", function(matches)
  taPackage.db.recordMonsterAttack(matches[2], "glanced", nil)
end, { type = "regex" })

createTrigger("^The (.+)'s? .+ misses? you!$", function(matches)
  taPackage.db.recordMonsterAttack(matches[2], "miss", nil)
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

-- =========================================================================
-- Re-roll for good stats
-- =========================================================================

createAlias("^re-roll-for-good-stats$", function()
  taPackage.reRolling = true
  send("status")
end, { type = "regex" })

createTrigger("^Encumberance:\\s+(\\d+) / (\\d+)$", function(matches)
  if not taPackage.reRolling then return end
  local physique = taPackage.character.physique or 0
  local stamina  = taPackage.character.stamina  or 0
  if physique >= 29 and stamina >= 29 then
    taPackage.reRolling = false
    echo("[re-roll] Done! Physique=" .. physique .. ", Stamina=" .. stamina)
  else
    echo("[re-roll] Physique=" .. physique .. ", Stamina=" .. stamina .. " — re-rolling...")
    send("reroll")
  end
end, { type = "regex" })

-- =========================================================================
-- Ring gong and fight in arena
-- =========================================================================

local function arenaSend(cmd)
  taPackage.arenaLastCmd = cmd
  send(cmd)
end

local function arenaAttack()
  local name = taPackage.arenaMonster
  if name then
    arenaSend("a " .. name:match("^(%S+)"))
  end
end

local function checkFleeArena()
  if taPackage.arenaState ~= "fighting" then return false end
  local hp = taPackage.character.vitalityCurrent
  if hp and hp < 20 then
    taPackage.arenaState = "fleeing"
    arenaSend("w")
    return true
  end
  return false
end

createAlias("^ring-gong-and-fight-in-arena$", function()
  taPackage.arenaState = "ringing"
  arenaSend("ring gong")
end, { type = "regex" })

createTrigger("^An? (.+) enters the arena through the dungeon gate!$", function(matches)
  if taPackage.arenaState ~= "ringing" then return end
  taPackage.arenaMonster = matches[2]
  taPackage.arenaState = "fighting"
  arenaAttack()
end, { type = "regex" })

createTrigger("^Your attack hit the .+ for \\d+ damage!$", function(matches)
  if taPackage.arenaState ~= "fighting" then return end
  if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
  if taPackage.arenaState ~= "fighting" then return end
  if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function(matches)
  if taPackage.arenaState ~= "fighting" then return end
  if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
  if taPackage.arenaState ~= "fighting" then return end
  taPackage.arenaMonster = nil
  if not checkFleeArena() then
    taPackage.arenaState = "ringing"
    arenaSend("ring gong")
  end
end, { type = "regex" })

createTrigger("^The .+ attacked you .+ for \\d+ damage!$", function(matches)
  checkFleeArena()
end, { type = "regex" })

createTrigger("^You're in the (.+)\\.$", function(matches)
  local room = matches[2]
  if taPackage.arenaState == "fleeing" then
    if room == "north plaza" then
      arenaSend("w")
    elseif room == "temple" then
      taPackage.arenaState = "healing"
      arenaSend("buy healing")
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

createTrigger("^The priests heal all your wounds for \\d+ crowns\\.$", function(matches)
  if taPackage.arenaState ~= "healing" then return end
  taPackage.arenaState = "returning"
  arenaSend("e")
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function(matches)
  if not taPackage.arenaState then return end
  local cmd = taPackage.arenaLastCmd
  if cmd then
    createTimer(15000, function() arenaSend(cmd) end, { type = "once" })
  end
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function(matches)
  if not taPackage.arenaState then return end
  local cmd = taPackage.arenaLastCmd
  if cmd then
    createTimer(15000, function() arenaSend(cmd) end, { type = "once" })
  end
end, { type = "regex" })

echo("Finishing reading main.lua")
