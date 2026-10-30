-- ta_monsters.lua -- the monster database, and which monsters we have met
--
-- `look <monster>` collects the description that follows and files it under
-- the monster's name, in monsters.lua and in the SQLite database. Alongside it,
-- each monster seen in a room counts as an encounter, at most once an hour per
-- room.
--
-- Loaded by main.lua with dofile, where the `look <target>` triggers used to
-- sit. A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.monsterStorePath (main.lua: only main.lua's absoluteScriptDir
--         gives the right directory), taPackage.db (ta_db.lua),
--         taPackage.currentRoom
--   out   taPackage.monsters.getEntry, .getLookState, .onLookLine (main.lua's
--         catch-all look trigger), .clearPresence (the kill trigger),
--         taPackage.monsterStore, and taPackage.lookCapture, which the
--         room-description capture in main.lua and ta_map.lua shares

taPackage.monsters = {}

if not taPackage.roomPresence then
    taPackage.roomPresence = {}
end

-- Two tables that outlive reloadScript():
--
--   monsterStore  the monster database itself: loaded from monsters.lua once per
--                 baud session, and saved back on every change
--   lookCapture   the `look` being read right now. Shared with the room-
--                 description capture in main.lua, which reads it too: `state`
--                 is "idle", "accumulating" (a monster) or "accumulating_room"
--
-- They were one table, taPackage.monsterDb, which named only half of what it
-- held. A session loaded before the split is carried over from it.
if taPackage.monsterDb then
    local old = taPackage.monsterDb
    taPackage.monsterStore = taPackage.monsterStore
        or { monsters = old.monsters, db = old.db, dbPath = old.dbPath }
    taPackage.lookCapture = taPackage.lookCapture or {
        state = old.state or "idle",
        lookTarget = old.lookTarget,
        accumulatedLines = old.accumulatedLines or {},
        descRoomId = old.descRoomId,
        descRoomProvisional = old.descRoomProvisional,
    }
    taPackage.monsterDb = nil
end

if not taPackage.monsterStore then
    local Db = dofile(SCRIPT_DIR .. "db.lua")
    local dbPath = taPackage.monsterStorePath
    taPackage.monsterStore = {
        monsters = Db.load(dbPath),
        db = Db,
        dbPath = dbPath,
    }
end

if not taPackage.lookCapture then
    taPackage.lookCapture = {
        state = "idle",
        lookTarget = nil,
        accumulatedLines = {},
    }
end

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
    local db = taPackage.monsterStore.monsters
    local today = os.date("%Y-%m-%d")
    if db[name] then
        db[name].description = description
        db[name].encounters = db[name].encounters + 1
    else
        db[name] = { description = description, firstSeen = today, encounters = 1 }
    end
    pcall(taPackage.monsterStore.db.save, taPackage.monsterStore.dbPath, db)
end

function taPackage.monsters.getEntry(name)
    return taPackage.monsterStore.monsters[name]
end

function taPackage.monsters.getLookState()
    return taPackage.lookCapture.state
end

local function startLook(target)
    taPackage.lookCapture.state = "accumulating"
    taPackage.lookCapture.lookTarget = target
    taPackage.lookCapture.accumulatedLines = {}
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
taPackage.monsters.clearPresence = clearPresence

local function recordEncounter(name)
    local entry = taPackage.monsterStore.monsters[name]
    if entry then
        entry.encounters = entry.encounters + 1
        pcall(taPackage.monsterStore.db.save, taPackage.monsterStore.dbPath, taPackage.monsterStore.monsters)
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

local function isRoomLine(line)
    return string.match(line, "^You're in ")
        or string.match(line, "^You are in ")
        or string.match(line, "^You are inside ")
        or string.match(line, "^You are outside ")
end

-- The `look <monster>` half of main.lua's catch-all look trigger, which hands
-- over every line once it has ruled out a room-description capture. Collects
-- the description until the monster's health sentence ends it, then files it.
function taPackage.monsters.onLookLine(line)
    if taPackage.lookCapture.state ~= "accumulating" then return end
    if string.match(line, "^l .") or string.match(line, "^look .") then return end
    if isRoomLine(line) or string.match(line, "^There is ") then
        taPackage.lookCapture.state = "idle"
        taPackage.lookCapture.accumulatedLines = {}
        return
    end
    if isHealthLine(line) then
        local lines = taPackage.lookCapture.accumulatedLines
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
                or taPackage.lookCapture.lookTarget
            local desc = table.concat(lines, " ")
            -- If the health status was split across two server lines, the first fragment
            -- (e.g. "The X seems to be in") got accumulated; truncate at last period to drop it.
            desc = desc:match("^(.*%.)") or desc
            upsertMonster(canonicalName, desc)
            taPackage.db.upsertMonster(canonicalName, desc)
            taPackage.lastAttackTarget = canonicalName
        end
        taPackage.lookCapture.state = "idle"
    else
        table.insert(taPackage.lookCapture.accumulatedLines, line)
    end
end
