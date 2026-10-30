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
--
-- Do not move this out of main.lua (see ta_utils.lua's header): its answer
-- depends on which chunk defines it, and the monster database's path with it.
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
end

dofile(scriptDir .. "ta_utils.lua")

taPackage.db = dofile(scriptDir .. "ta_db.lua")

dofile(scriptDir .. "ta_character.lua")

dofile(scriptDir .. "ta_xp.lua")

-- =========================================================================
-- Triggers
-- =========================================================================

dofile(scriptDir .. "ta_badges.lua")

-- On entering the arena, pull our character sheet (st) and inventory (i) so the
-- script's tracked state is populated right away instead of waiting for the
-- first manual status check. TA_INIT_CMD rides on the tail of this: the `i`
-- reply's gold line is what tells autoLogin.runInitCmd the sheet has landed, so
-- dropping the `i` here would strand it.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    -- A character is in the game again, so whatever death preceded this is over
    -- as far as every reader of taPackage.died is concerned. Cleared here, in
    -- one place, rather than by whichever script happened to look first.
    taPackage.died = nil
    taPackage.diedAt = nil
    -- In the game rather than at the BBS, where "x" means something else. See
    -- the hand-typed "x" retry.
    taPackage.inGame = true
    send("st")
    send("i")
end, { type = "regex" })

createTrigger("^Status:\\s+(\\S+)$", function(matches)
    taPackage.character.setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Mana:\\s+(\\d+) / (\\d+)$", function(matches)
    taPackage.character.setMana(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Encumberance:\\s+(\\d+) / (\\d+)$", function(matches)
    taPackage.character.setEncumberance(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    -- A trap hurt us without printing a damage number; the trap handler stashed
    -- our HP and fired "st", so this fresh Vitality line lets us recover the hit
    -- as the drop from the stashed value.
    local trapBefore = taPackage.trapHpBefore
    if trapBefore then
        taPackage.trapHpBefore = nil
        local lost = trapBefore - tonumber(matches[2])
        if lost > 0 then taPackage.badges.incoming("TRAP " .. lost) end
    end
    -- Same trick for an area-effect spell: the caster's handler stashed our HP
    -- and fired "st", so this fresh Vitality line recovers the hit and badges it.
    local aoeBefore = taPackage.aoeHpBefore
    if aoeBefore then
        taPackage.aoeHpBefore = nil
        local lost = aoeBefore - tonumber(matches[2])
        if lost > 0 then taPackage.badges.incoming("AOE " .. lost) end
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
            taPackage.badges.healing("HEALED BY " .. string.upper(taPackage.groupHealCaster or "?")
                .. " FOR " .. gained)
        end
    end
    taPackage.character.setVitality(matches[2], matches[3])
    -- A held level-up notification is waiting on exactly this line for the new
    -- HP/MP maxima. Defined with the training trigger far below, so it only
    -- exists once the chunk has loaded (always true by the time a line arrives).
    if taPackage.noticeLevelUpStats then taPackage.noticeLevelUpStats() end
    -- A re-roll judges every fresh sheet (ta_reroll.lua).
    taPackage.reroll.checkStats()
end, { type = "regex" })

createTrigger("^Class:\\s+(.+)$", function(matches)
    taPackage.character.setClass(matches[2])
end, { type = "regex" })

createTrigger("^Weapon:\\s+(.+)$", function(matches)
    taPackage.character.setWeapon(matches[2])
end, { type = "regex" })

-- "Armor:" alone, not "Armor Rating:", which the colon right after the word
-- keeps out. farm-for-gold reads it to tell whether the robes are on.
createTrigger("^Armor:\\s+(.+)$", function(matches)
    taPackage.character.setArmor(matches[2])
end, { type = "regex" })

createTrigger("^Physique:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getPhysique()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Physique", oldVal, newVal)
    end
    taPackage.character.setPhysique(newVal)
end, { type = "regex" })

createTrigger("^Stamina:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getStamina()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Stamina", oldVal, newVal)
    end
    taPackage.character.setStamina(newVal)
end, { type = "regex" })

createTrigger("^Agility:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getAgility()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Agility", oldVal, newVal)
    end
    taPackage.character.setAgility(newVal)
end, { type = "regex" })

createTrigger("^Charisma:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getCharisma()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Charisma", oldVal, newVal)
    end
    taPackage.character.setCharisma(newVal)
end, { type = "regex" })

createTrigger("^Intellect:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getIntellect()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Intellect", oldVal, newVal)
    end
    taPackage.character.setIntellect(newVal)
end, { type = "regex" })

createTrigger("^Knowledge:\\s+(\\d+)$", function(matches)
    local newVal = tonumber(matches[2])
    local oldVal = taPackage.character.getKnowledge()
    if oldVal and oldVal ~= newVal and not taPackage.reRollSuppressStats then
        taPackage.db.recordStatChange("Knowledge", oldVal, newVal)
    end
    taPackage.character.setKnowledge(newVal)
end, { type = "regex" })

createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
    taPackage.character.setGold(matches[2])
    -- A held level-up notification is waiting on this line to measure the
    -- training fee. Defined with the training trigger far below.
    if taPackage.noticeLevelUpGold then taPackage.noticeLevelUpGold() end
    -- Likewise a held promotion notification, measuring its fee.
    if taPackage.noticePromotionGold then taPackage.noticePromotionGold() end
    -- The last reply of the `st`/`i` pair the entry trigger fires, so this is
    -- the moment the character sheet is fully parsed and an init command can
    -- safely run. It is a no-op on every other inventory check.
    taPackage.autoLogin.runInitCmd()
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
    taPackage.pushPendingDir("passage")
    send("i")
end, { type = "regex" })

-- In a group -- following someone, or leading followers -- loot found on a
-- corpse is split with the group via `share`. A field, not a local: main.lua's
-- local budget is tight (see CLAUDE.md).
function taPackage.inGroup()
    local leading = taPackage.followedBy and #taPackage.followedBy > 0
    return taPackage.followTarget ~= nil or leading == true
end

function taPackage.shareLootWithGroup(found)
    if taPackage.inGroup() then
        send("share " .. found)
    end
end

createTrigger("^You found (\\d+) gold crowns while searching the (.+)'s corpse\\.$", function(matches)
    local found = tonumber(matches[2])
    local monster = matches[3]
    taPackage.character.setGold((taPackage.character.getGold() or 0) + found)
    taPackage.shareLootWithGroup(found)
    taPackage.db.recordMonsterLoot(monster, found)
    if taPackage.lastKilledMonster == monster then
        taPackage.pendingLootCheck = nil
        taPackage.lastKilledMonster = nil
    end
end, { type = "regex" })

createTrigger("^You found (\\d+) gold crowns while searching the area\\.$", function(matches)
    local found = tonumber(matches[2])
    local monster = taPackage.lastKilledMonster or "unknown"
    taPackage.character.setGold((taPackage.character.getGold() or 0) + found)
    taPackage.shareLootWithGroup(found)
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
    taPackage.character.setGold((taPackage.character.getGold() or 0) - amount)
end, { type = "regex" })

createTrigger("^(.+) just gave you (\\d+) gold coins\\.$", function(matches)
    local amount = tonumber(matches[3])
    taPackage.character.setGold((taPackage.character.getGold() or 0) + amount)
end, { type = "regex" })

-- A groupmate's `share` (see shareLootWithGroup) hands each of us a cut. The
-- BBS hard-wraps at 78 columns, even mid-number ("...your share was 1" / "6
-- gold."), so an unfinished tail is held and completed by the next line. The
-- continuation trigger is registered first so it doesn't consume the very line
-- that stashed the tail.
function taPackage.creditGroupShare(tail)
    local share = tail:match("^(%d+)%s*gold%.$")
    if share then
        taPackage.character.setGold((taPackage.character.getGold() or 0) + tonumber(share))
        return true
    end
    return false
end

createTrigger("^(.*)$", function(matches)
    local pending = taPackage.pendingShareTail
    if not pending then return end
    taPackage.pendingShareTail = nil
    taPackage.creditGroupShare(pending .. matches[2]:match("^%s*(.-)%s*$"))
end, { type = "regex" })

createTrigger("^.+ just shared \\d+ gold with the group, your share was(.*)$", function(matches)
    local tail = matches[2]:match("^%s*(.-)%s*$")
    if not taPackage.creditGroupShare(tail) then
        taPackage.pendingShareTail = tail
    end
end, { type = "regex" })

-- Sharing our own loot leaves us one share plus the remainder: the game hands
-- every other member `each` (2908 at 484 a share left Teekywiki 488). The line
-- doesn't name the group size, but floor(total / each) recovers it whenever
-- each >= group size -- true for any loot worth sharing.
createTrigger("^You shared (\\d+) gold with the group, each share was (\\d+) gold\\.$", function(matches)
    local total = tonumber(matches[2])
    local each = tonumber(matches[3])
    if each == 0 then return end
    local others = math.floor(total / each) - 1
    taPackage.character.setGold((taPackage.character.getGold() or 0) - each * others)
end, { type = "regex" })

createTrigger("^You deposited (\\d+) gold in your account\\.$", function(matches)
    local amount = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) - amount)
end, { type = "regex" })

createTrigger("^You withdrew (\\d+) gold from your account\\.$", function(matches)
    local amount = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) + amount)
end, { type = "regex" })

createTrigger("^Ok, you bought .+ for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) - cost)
end, { type = "regex" })

createTrigger("^The priests heal all your wounds for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) - cost)
    local _, max = taPackage.character.getVitality()
    if max then
        taPackage.character.setVitality(max, max)
    end
    taPackage.db.recordService("healing", "temple", cost)
end, { type = "regex" })

-- `buy restoring` at the temple. Sold as a cure for stats a monster drained, but
-- it is symmetric — it clamps every stat back to base, so it also strips a rowan
-- or hyssop potion, which is what we buy it for (see arenaTryTrain). "it's" is
-- the game's own typo; the line is matched as printed.
createTrigger("^The priests restore your body and mind to it's former state for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) - cost)
    taPackage.db.recordService("restoring", "temple", cost)
end, { type = "regex" })

-- =========================================================================
-- Look capture
-- =========================================================================
--
-- `look <monster>` files its description in the monster database
-- (ta_monsters.lua); a bare `look` files the room's description on the map.
-- Both are read by one catch-all trigger below, steered by
-- taPackage.monsterDb.state: the room half is handled here, and every other
-- line goes to taPackage.monsters.onLookLine. The mapper itself (position
-- tracking and the room graph) is in ta_map.lua, loaded below.

-- Computed here rather than in ta_monsters.lua: see absoluteScriptDir.
taPackage.monsterDbPath = absoluteScriptDir() .. "monsters.lua"
dofile(scriptDir .. "ta_monsters.lua")

-- Open a room-description capture, remembering WHICH ROOM it is a description
-- of. The room is fixed here, at the `look`, and not at the `Exits:` line that
-- ends the capture -- those can be fifty rooms apart. On 2026-09-18 a capture
-- opened in the Complex of Natural Caverns and wrote its prose onto
-- deep-forest-13, because deep-forest-13 was what `currentRoomId` still held
-- (logs/session-pelayo-2026-09-18T14-37-39.log). A description is about the
-- place you were standing when you looked; nothing later can change that.
--
-- taPackage fields rather than locals: ta_nav.lua is a separate chunk with its
-- own 200-local budget and navSend has to be able to call the abandon.
--
-- Only while mapping. With mapping off, currentRoomId is wherever mapping last
-- stopped -- after the Exits handler's "is this the room we think?" check turns
-- it off, that is precisely the room we are NOT in -- so the capture still runs
-- (it is what keeps the look's own room lines from reading as arrivals) but
-- files nothing.
function taPackage.startRoomDescCapture()
    taPackage.monsterDb.state = "accumulating_room"
    taPackage.monsterDb.accumulatedLines = {}
    taPackage.monsterDb.descRoomId = taPackage.mapping and taPackage.currentRoomId or nil
    taPackage.monsterDb.descRoomProvisional = taPackage.currentRoomProvisional
end

-- The exits the map has for `roomId` that the game's `ex` (`dirs`) leaves out,
-- sorted. `ex` lists every exit a room has, sealed ones and u/d too, so any at
-- all means `roomId` is not the room we are standing in -- or the map gave it an
-- exit it does not have. Shared by the Exits handler, which stops mapping on it,
-- and the description capture, which the same `Exits:` line ends first and so
-- has to refuse on its own.
function taPackage.exitsMissingFrom(roomId, dirs)
    local listed = {}
    for _, dir in ipairs(dirs) do listed[dir] = true end
    local missing = {}
    for dir in pairs(taPackage.db.roomExitDirections(roomId)) do
        if not listed[dir] then missing[#missing + 1] = dir end
    end
    table.sort(missing)
    return missing
end

-- Drop a capture without writing it. Every move calls this -- typed or sent by a
-- walk -- because once you have moved, the next `Exits:` describes somewhere
-- else, so there is no honest room left to file the half-read description under.
--
-- It also re-arms the room-entry triggers, which `accumulating_room` suppresses
-- (a room line during a look is the look talking, not an arrival). That makes a
-- capture that never ends worse than a lost description: it quietly stops the
-- mapper seeing arrivals at all, for the rest of the session.
function taPackage.abandonRoomDescCapture()
    if taPackage.monsterDb.state ~= "accumulating_room" then return end
    taPackage.monsterDb.state = "idle"
    taPackage.monsterDb.accumulatedLines = {}
    taPackage.monsterDb.descRoomId = nil
end

-- Bare "look" or "l" (no target) = room description
createTrigger("^look$", function()
    taPackage.startRoomDescCapture()
end, { type = "regex" })

createTrigger("^l$", function()
    taPackage.startRoomDescCapture()
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

-- Lines that arrive inside a look but are not part of it: something that
-- HAPPENED while the description was being read. A room with four characters and
-- a minotaur in it prints a lot of them, and eighteen of the caverns rooms
-- walked on 2026-09-18 have them welded into their prose.
--
-- Each shape is checked against the whole line and against the real
-- descriptions already in the database, because a look wraps at 78 columns and a
-- continuation line can start anywhere:
--   * ends in "!" -- every combat line, dodge and spell does; of 1000-odd stored
--     descriptions exactly one contains an "!", and that one is the corrupted
--     deep-forest-13.
--   * the arrival and departure broadcasts.
--   * the brief's own occupant and floor lines, anchored the way the arena
--     roster anchors them (" is here." / " are here." / "... on the floor."),
--     which is what keeps prose ending in "...took place here." out of this.
local function isRoomDescNoise(line)
    return line:match("!$")
        or line:match(" has just arrived")
        or line:match(" just left")
        or line:match(" is here%.$")
        or line:match(" are here%.$")
        -- The monster line and "There is nobody here." need their own shape: both
        -- end in "<something> here." rather than " is here.", which is exactly
        -- why the arena roster's two triggers cannot match them either.
        or line:match("^There is .+ here%.$")
        or line:match("^There .+ on the floor%.$")
end

-- A look is a paragraph, not a transcript. The longest real description in the
-- database is a little over 60 lines unwrapped; well past that, the `Exits:`
-- that should have closed this capture is not coming, and the useful thing is to
-- let go rather than keep swallowing -- an open capture blinds the room-entry
-- triggers (see abandonRoomDescCapture).
local ROOM_DESC_MAX_LINES = 80

local function cleanRoomDesc(desc)
    -- Strip "look " or "l " prefix if the echo got accumulated
    desc = desc:gsub("^look%s+", ""):gsub("^l%s+", "")
    -- Strip trailing single direction word (e.g. " e", " sw", " d")
    desc = desc:gsub("%s+[nsewud][sewn]?$", "")
    return desc
end

createTrigger("^(.+)$", function(matches)
    local line = taPackage.utils.trimLine(matches[2])

    if taPackage.monsterDb.state == "accumulating_room" then
        -- Skip our own echoed commands (look starts the capture, ex ends it).
        if line == "look" or line == "l" or line == "ex" then return end
        if isRoomDescTerminator(line) then
            local lines = taPackage.monsterDb.accumulatedLines
            local roomId = taPackage.monsterDb.descRoomId
            -- A room we believed we knew, whose `ex` contradicts the map, is some
            -- other room: its description is not this one's. (A room minted on
            -- this move holds only an assumed back-link, so it is exempt, as it
            -- is in the Exits handler.)
            local exitList = line:match("^Exits: (.+)%.$")
            if roomId and exitList and not taPackage.monsterDb.descRoomProvisional then
                local dirs = {}
                for dir in exitList:gmatch("[^,%s]+") do dirs[#dirs + 1] = dir end
                if #taPackage.exitsMissingFrom(roomId, dirs) > 0 then roomId = nil end
            end
            if #lines > 0 and roomId then
                local desc = cleanRoomDesc(table.concat(lines, " "))
                if #desc > 0 then
                    taPackage.db.setRoomDescription(roomId, desc)
                end
            end
            taPackage.abandonRoomDescCapture()
        elseif isRoomDescNoise(line) then
            -- Dropped, but the capture stays open: the look's own prose is still
            -- coming, and the `Exits:` that ends it has not arrived.
            return
        elseif #taPackage.monsterDb.accumulatedLines >= ROOM_DESC_MAX_LINES then
            taPackage.abandonRoomDescCapture()
        else
            table.insert(taPackage.monsterDb.accumulatedLines, line)
        end
        return
    end

    taPackage.monsters.onLookLine(line)
end, { type = "regex" })

dofile(scriptDir .. "ta_map.lua")

-- =========================================================================
-- Shop shortcuts
-- =========================================================================

-- buy-potions — the manual version of the arena's potion round trip: buy and
-- drink both stat potions (rowan for strength, hyssop for agility) while you're
-- standing in the magic shop. Each is drunk right after it's bought so a
-- refusal (no gold, out of stock) is easy to pair with the potion it belongs to.
createAlias("^buy-potions$", function()
    send("buy rowan")
    send("drink rowan")
    send("buy hyssop")
    send("drink hyssop")
end, { type = "regex" })

-- buy-tavern — the manual version of the tavern stop: a meal and a drink while
-- you're standing in a tavern, to top off hunger and thirst.
createAlias("^buy-tavern$", function()
    send("buy meal")
    send("buy drink")
end, { type = "regex" })

-- =========================================================================
-- Combat triggers
-- =========================================================================

-- Rogues land a "skillful attack" alongside the ordinary one, so the verb phrase
-- is captured rather than spelled out: "Your attack hit …" and "Your skillful
-- attack hit …" are the only two forms in the logs, and both are our melee. The
-- arena and kill-loop triggers below already use the same wildcard shape.
createTrigger("^Your (.+) hit the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[3]
    local damage = tonumber(matches[4])
    taPackage.lastAttackTarget = monster
    taPackage.badges.outgoing("HIT " .. damage)
    taPackage.db.recordPlayerAttack(
        taPackage.character.getWeapon() or "weapon", monster, "hit", damage
    )
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
    local monster = taPackage.lastAttackTarget or "unknown"
    taPackage.db.recordPlayerAttack(
        taPackage.character.getWeapon() or "weapon", monster, "miss", nil
    )
end, { type = "regex" })

createTrigger("^The (.+) dodged your attack!$", function(matches)
    local monster = matches[2]
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerAttack(
        taPackage.character.getWeapon() or "weapon", monster, "dodge", nil
    )
end, { type = "regex" })

-- All incoming-damage lines do the same three things: subtract the hit from our
-- vitality, badge "TOOK N", and record the attack. The generic "attacked you ...
-- for N damage!" phrasing covers ordinary swings, but many enemies deal damage
-- through special verbs that never say "attacked you" — a stone giant's boulder
-- (seen for 52), a cyclops's throw (22), a stygian dragon's bite (39) or tail
-- lash (35), a minotaur chieftain's charge (42), a caster's "discharged" spell,
-- a giant's breath ("exhaled a blast of flame", or "of frost" from an ice
-- giantess for 60).
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
    "^The (.+) exhaled a blast of .+ at you for (\\d+) damage!$",
}

for _, pattern in ipairs(incomingDamagePatterns) do
    createTrigger(pattern, function(matches)
        local monster = matches[2]
        local damage = tonumber(matches[3])
        local current, max = taPackage.character.getVitality()
        if current then
            taPackage.character.setVitality(current - damage, max)
        end
        taPackage.badges.incoming("TOOK " .. damage)
        taPackage.db.recordMonsterAttack(monster, "hit", damage)
        -- React to the damage itself, not just to our own swings. Flee was
        -- otherwise only checked when one of our attacks resolved, so a burst of
        -- incoming damage during a gap in our attack cycle (e.g. a swing bounced
        -- on "physically exhausted" and is waiting out its 30s retry) could push
        -- us well below the flee threshold yet sit there taking hits until the
        -- next swing finally landed.
        taPackage.checkFleeArena()
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
    taPackage.trapHpBefore = taPackage.character.getVitality()
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
--
-- The move is queued mapping or not, like being thrown out of a room: `where`
-- follows the same queue, and a navigate walk suspends mapping. Unqueued, the
-- pit's brief moved the tracker nowhere and the climb out walked it off the map.
createTrigger("^You just fell through a trap door in the floor!$", function()
    if taPackage.mapping and taPackage.currentRoomId then
        taPackage.db.setRoomTrap(taPackage.currentRoomId, "trap door")
    end
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.prevRoomId = taPackage.currentRoomId
    -- The fall is the next arrival, so it goes to the FRONT of the queue --
    -- ahead of anything typed but not yet resolved.
    table.insert(taPackage.pendingDirs, 1, "d")
end, { type = "regex" })

-- Being hurled out of a room (a female cyclops picks you up and throws you) is a
-- move: the game names the direction, and the next brief is the room that way.
-- Unqueued, that arrival fell back on its name alone, and with 170-odd rooms
-- called "stonework corridor" it landed the walk on third town's #1022 and
-- wrote Stoneworks Level 4's description onto it (2026-09-27,
-- logs/session-teekywiki-2026-09-27T18-16-45.log). Like the trap-door fall, it
-- goes to the FRONT of the queue, ahead of anything typed but not yet resolved;
-- and like any move it ends a look still being read. Mapping or not, since
-- `where` follows the same queue.
taPackage.compassWords = {
    north = "n", south = "s", east = "e", west = "w",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw",
    up = "u", down = "d",
}
createTrigger("^You tumble (.+), out of the room!$", function(matches)
    local dir = taPackage.compassWords[matches[2]]
    if not dir then return end
    taPackage.suppressRoomEntry = nil
    taPackage.abandonRoomDescCapture()
    taPackage.prevRoom = taPackage.currentRoom
    taPackage.prevRoomId = taPackage.currentRoomId
    table.insert(taPackage.pendingDirs, 1, dir)
end, { type = "regex" })

-- Advanced monsters cast area-effect spells that hit everyone nearby without
-- printing a damage number — just like a trap. Use the identical trick: stash
-- our HP, ask for a fresh status ("st"), and let the Vitality trigger above
-- recover the loss and badge "AOE <n>". The cast message word-wraps across two
-- physical lines (".. in the" / "area!"), so we match only the stable first
-- line, up through "at hostile people", and never anchor the end.
-- Point additional area-effect triggers at handleAreaEffect as we discover them.
local function handleAreaEffect()
    taPackage.aoeHpBefore = taPackage.character.getVitality()
    send("st")
end

createTrigger("^The .+ just discharged .+ at hostile people",
    handleAreaEffect, { type = "regex" })

-- =========================================================================
-- Loot and kill triggers
-- =========================================================================

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    local name = matches[2]
    taPackage.monsters.clearPresence(name)
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
    taPackage.character.setGold((taPackage.character.getGold() or 0) - cost)
    taPackage.db.recordService("drink", "tavern", cost)
end, { type = "regex" })

createTrigger("^The barmaid brings you a meal for (\\d+) crowns\\.$", function(matches)
    local cost = tonumber(matches[2])
    taPackage.character.setGold((taPackage.character.getGold() or 0) - cost)
    taPackage.db.recordService("meal", "tavern", cost)
end, { type = "regex" })

-- =========================================================================
-- Stat change tracking
-- =========================================================================

createTrigger("^Level:\\s+(\\d+)$", function(matches)
    local newLevel = tonumber(matches[2])
    local oldLevel = taPackage.character.getLevel()
    if oldLevel and oldLevel ~= newLevel then
        taPackage.db.recordStatChange("Level", oldLevel, newLevel)
    end
    taPackage.character.setLevel(newLevel)
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

-- How long the XP-change marker stays on the bar after the XP figure moves.
local XP_CHANGE_VISIBLE_MS = 3000
-- Orange: warm enough to pull the eye off the cyan XP figure it hangs beside,
-- and not already spoken for (red means untrained level, yellow means gold).
local XP_CHANGE_FG = "#ff8700"

-- The signed move in that figure, e.g. "-14,000" after gaining 14,000 XP —
-- nil once the marker has aged out, or when we can't tell (unknown class, at
-- max level, or a change that leaves the figure where it was). Reported as a
-- delta of the *displayed* number rather than of raw XP, so it always agrees
-- with the value it sits next to: training past a threshold pushes the count
-- back up, and the marker says "+" to match.
local function xpChangeText(xp, class)
    local change = taPackage.xpChange
    if not change then return nil end
    if taPackage.utils.nowMillis() - change.at >= XP_CHANGE_VISIBLE_MS then return nil end
    local before = taPackage.xp.xpRemaining(change.from, class)
    local after = taPackage.xp.xpRemaining(xp, class)
    if not (before and after) then return nil end
    local delta = after - before
    if delta == 0 then return nil end
    return (delta > 0 and "+" or "") .. taPackage.utils.formatWithCommas(delta)
end

local function status()
    local charStatus = taPackage.character.getCharacterStatus() or "?"
    local vitalityCurrent, vitalityMax = taPackage.character.getVitality()
    local manaCurrent, manaMax = taPackage.character.getMana()
    local xp = taPackage.character.getExperience()
    local nextLevelXp = xp and taPackage.xp.getXpForNextLevel(xp, taPackage.character.getClass())
    local gold = taPackage.character.getGold() and taPackage.utils.formatWithCommas(taPackage.character.getGold()) or "?"

    local charName = taPackage.character.getName()
    local charClass = taPackage.character.getClass()
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
            text = vitalityCurrent and taPackage.utils.formatWithCommas(vitalityCurrent) or "?",
            fg = vitalityColor(vitalityCurrent, vitalityMax)
        },
        { text = vitalityMax and ("/ " .. taPackage.utils.formatWithCommas(vitalityMax)) or "", fg = "white" },
    }
    if manaMax and manaMax > 0 then
        table.insert(segments, { text = "MP:", fg = "green" })
        table.insert(segments, { text = manaCurrent and taPackage.utils.formatWithCommas(manaCurrent) or "?", fg = "cyan" })
        table.insert(segments, { text = "/ " .. taPackage.utils.formatWithCommas(manaMax), fg = "cyan" })
    end
    -- Only ever show the XP remaining to the next level as "(<xp remaining>)".
    -- "?" when XP is unknown, "(max)" at the top level where there's no next.
    local remainingText
    if not xp then
        remainingText = "?"
    elseif nextLevelXp then
        remainingText = "(" .. taPackage.utils.formatWithCommas(nextLevelXp - xp) .. ")"
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
    if taPackage.character.hasUntrainedLevel() then
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
function taPackage.recordXpChange(previous, current)
    if previous == nil or current == nil or previous == current then return end
    taPackage.xpChange = { from = previous, at = taPackage.utils.nowMillis() }
    -- baud only re-evaluates the status function when the server sends data, so
    -- three quiet seconds would leave an expired marker stuck on the bar. Handing
    -- setStatus the same function again forces a fresh evaluation, which is what
    -- makes the marker ephemeral rather than sticky. Armed a beat past the window
    -- so the evaluation lands after it has closed, never on the boundary.
    createTimer(XP_CHANGE_VISIBLE_MS + 100, function()
        setStatus(status)
    end, { repeating = false })
end

dofile(scriptDir .. "ta_reroll.lua")

dofile(scriptDir .. "ta_arena.lua")

-- =========================================================================
-- hang-around-in-tavern-and-deposit-gold
--
-- A standalone "idle in a tavern" mode, independent of the arena scripts. It
-- parks the character in a bar and keeps it fed and watered: buy a meal when
-- hungry, a drink when thirsty. Two things end it, both by leaving the game
-- with "x": HP falling below half (something is hurting us faster than we can
-- recover — e.g. we ran out of money and hunger/thirst is grinding us down),
-- or a purchase failing for lack of money (the direct signal for the same).
--
-- It also arms banking (ta_bank.lua), which is where the name's second half
-- comes from. The character sitting in the tavern is the one the gold farm
-- hands its takings to, so "idling here" and "deposit what arrives" are the
-- same job; keeping them as two switches meant banking was never once armed in
-- a real session. Stopping the mode disarms banking again, so the pair goes
-- down together.
-- =========================================================================

local TAVERN_HP_FRACTION = 0.5        -- exit if current HP drops below this share of max
local TAVERN_STATUS_POLL_MS = 600000 -- low-frequency HP heartbeat (10 min); see scheduleTavernPoll

-- Session accounting. The whole point of parking a character here is the gold
-- the farm hands it, and until now a run said nothing about how that was going:
-- the only evidence was counting "[bank] Deposited ..." lines in the log after
-- the fact. So keep two numbers from the moment the mode is armed — when it
-- started, and how much gold has arrived since — and report them as a rate,
-- which is the figure that actually answers "is this round worth leaving up?".
--
-- Both live on taPackage rather than in locals so they survive reloadScript()
-- mid-run; a reload that reset the clock would silently inflate the rate.
local function tavernSummary()
    local elapsed = os.time() - (taPackage.tavernStartTime or os.time())
    if elapsed < 0 then elapsed = 0 end
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local uptime = hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m")
    local gold = taPackage.tavernGoldReceived or 0
    -- Under a minute there is no meaningful rate — dividing by a fraction of a
    -- minute turns the first handover into a fantasy figure ("49,320 gold/min").
    local rate = elapsed >= 60
        and string.format("%.1f", gold / (elapsed / 60)) .. " gold/min"
        or "rate n/a yet"
    return "up " .. uptime .. ", " .. taPackage.utils.formatWithCommas(gold) .. " gold received ("
        .. rate .. ")"
end

local function isTavernRoom(room)
    if not room then return false end
    local r = room:lower()
    return r:find("tavern") ~= nil or r:find("bar") ~= nil
end

-- Leave the game and stop the mode. Bumping the generation invalidates any
-- poll timer still in flight so it can't re-arm after we've quit.
local function tavernExitGame(reason)
    echo("[tavern] " .. reason .. " — leaving the game. Session: " .. tavernSummary() .. ".")
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    -- Disarm banking on the way out. We're about to be logged out, and a
    -- deposit trip that fires after that would walk a character who isn't
    -- there — or worse, resume mid-route on the next login.
    taPackage.stopBanking()
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
        -- Ride the heartbeat for the check-in too, so an idle run says where it
        -- is every 10 minutes instead of only when gold happens to land.
        echo("[tavern] " .. os.date("%H:%M:%S") .. " — " .. tavernSummary() .. ".")
        send("st")
        scheduleTavernPoll()
    end, { repeating = false })
end

-- Stop tavern idle mode without leaving the game. Returns true if it was
-- running. Bumping the generation invalidates any poll timer in flight so it
-- can't re-arm. Shared by stop-hang-around-in-tavern-and-deposit-gold and
-- stop-all-scripts.
--
-- Banking goes down with it, including a deposit trip already in flight —
-- stopping the mode should leave nothing walking. Someone who armed banking on
-- its own with start-banking and then idled in a tavern loses it here too;
-- that's the cost of one switch for both, and start-banking re-arms it.
local function stopTavernMode()
    if not taPackage.tavernMode then return false end
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    taPackage.stopBanking()
    return true
end

createAlias("^hang-around-in-tavern-and-deposit-gold$", function()
    -- Judge the room from the name the last arrival brief left behind. Don't
    -- send a `look` first: send() is fire-and-forget, so its reply lands long
    -- after this function has returned, and a look's opening line is
    -- deliberately not treated as an arrival anyway (see
    -- handleRoomEntryUnlessLooking) -- it could never set currentRoom.
    local room = taPackage.currentRoom
    if not isTavernRoom(room) then
        echo("[tavern] Not in a tavern/bar (room: " .. (room or "unknown")
            .. "). Walk into one first, then run"
            .. " hang-around-in-tavern-and-deposit-gold.")
        return
    end
    taPackage.tavernMode = true
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    taPackage.tavernStartTime = os.time()
    taPackage.tavernGoldReceived = 0
    echo("[tavern] Hanging around in the " .. room
        .. ". Buying meals/drinks as needed; will leave (x) if HP drops below 50% or money runs out.")
    -- Arm banking too. ta_bank.lua's route home ends "ne" into the first town's
    -- tavern, so a deposit trip started from any other bar walks back to the
    -- wrong room -- but that is ta_bank's route to fix, and arming it here is
    -- what the alias name promises.
    taPackage.startBanking()
    send("st") -- prime HP tracking so the first poll isn't the first reading
    scheduleTavernPoll()
end, { type = "regex" })

createAlias("^stop-hang-around-in-tavern-and-deposit-gold$", function()
    -- Read the summary before stopping: stopTavernMode leaves the numbers
    -- alone, but the reading belongs to the run that just ended, so take it
    -- first and say it in the same breath as "stopped".
    local summary = tavernSummary()
    if stopTavernMode() then
        echo("[tavern] Stopped hanging around, banking disarmed (still in the game). Session: "
            .. summary .. ".")
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

-- Gold landed. ta_bank.lua has its own trigger on this line (it starts the
-- deposit trip); this one only keeps score, so it stays here with the rest of
-- the tavern session and counts every handover — including one that arrives
-- while we're already walking to the vaults, which ta_bank declines to bank but
-- which is money we were nonetheless given.
createTrigger("^(\\S+) just gave you (\\d+) gold coins\\.$", function(matches)
    if not taPackage.tavernMode then return end
    taPackage.tavernGoldReceived = (taPackage.tavernGoldReceived or 0)
        + (tonumber(matches[3]) or 0)
    echo("[tavern] +" .. matches[3] .. " gold from " .. matches[2] .. " — "
        .. tavernSummary() .. ".")
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
        taPackage.arenaEmergencyExit("Out of money (can't afford " .. matches[2] .. ")")
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

-- =========================================================================
-- Group heal (High Priest)
-- =========================================================================
-- `group-heal` and `gh` cast kusamotumaru, the deific heal that hits everyone
-- in the room, so it takes no target. Spell list: docs/shrine/SPELLS.md.
for _, groupHealPattern in ipairs({ "^group-heal$", "^gh$" }) do
    createAlias(groupHealPattern, function()
        send("cast kusamotumaru")
    end, { type = "regex" })
end

-- =========================================================================
-- Kill a single target
-- =========================================================================

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
-- Sorcerors blast the target. An Acolyte only melees in the kill loop; its
-- healing is heal-most-injured-party-member.
local function castSpell()
    if taPackage.castPending then
        killDebugEcho("cast-skip: cast already pending")
        return
    end
    if not taPackage.killActive then
        killDebugEcho("cast-skip: kill loop not active")
        return
    end
    if taPackage.character.isClass("Sorceror") then
        local target = taPackage.killTarget
        if not target then
            killDebugEcho("cast-skip: no target")
            return
        end
        taPackage.castPending = true
        local name = target:match("^(%S+)")
        killDebugEcho("cast-sent: toduza " .. name)
        send("cast toduza " .. name)
    end
end

-- Group healing (heal-most-injured-party-member). We send `group`, accumulate
-- each member's health as the listing streams in, and once the listing ends
-- cast kusamotu on the most-injured member (lowest HE%), if anyone is hurt.
-- Phases:
--   "want"    -- asked for the listing, waiting for the header
--   "reading" -- header seen, members are streaming in
-- The listing itself has no terminator line, so we chase it with a harmless
-- `ex` (exits). Its "Exits: ..." reply is guaranteed to arrive right after the
-- listing and is the first non-member line, which ends the reading phase — no
-- timing guesswork. Waiting for the header first means any spam arriving before
-- the listing doesn't cut the scan short.
local GROUP_HEAL_TERMINATOR = "ex"
local function beginGroupHealScan()
    taPackage.groupHealPhase = "want"
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil
    -- Tallied as the listing streams in (see the member-row trigger): total
    -- members and how many are hurt (below full). Drives the decision log in
    -- finalizeGroupHeal.
    taPackage.groupHealMembers = 0
    taPackage.groupHealHurt = 0
    send("group")
    send(GROUP_HEAL_TERMINATOR)
end

local function finalizeGroupHeal()
    taPackage.groupHealPhase = nil
    local name = taPackage.groupHealBestName
    local health = taPackage.groupHealBestHealth
    local members = taPackage.groupHealMembers or 0
    local hurt = taPackage.groupHealHurt or 0
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil

    if members == 0 then
        echo("[heal] No group members seen, taking no action.")
        return
    end
    if hurt == 0 then
        echo(string.format("[heal] All %d allies at full health, taking no action.", members))
        return
    end
    if not name or not health then return end
    if taPackage.castPending then
        echo(string.format(
            "[heal] %d of %d allies hurt (most injured %s at %d%%), but a cast is pending — skipping.",
            hurt, members, name, health))
        return
    end
    echo(string.format("[heal] %d of %d allies hurt, healing most injured %s at %d%%.",
        hurt, members, name, health))
    taPackage.castPending = true
    send("cast kusamotu " .. string.lower(name))
end

local function startKill(target, debug)
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return false
    end
    if not taPackage.character.getClass() then
        echo("[kill] Class unknown — run 'st' first so casters cast.")
        return false
    end
    taPackage.killTarget = target
    taPackage.killActive = true
    taPackage.killDebug = debug or false
    taPackage.killAttackPending = false
    taPackage.castPending = false
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

local function handleKillAllAlias()
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return
    end
    taPackage.killAllActive = true
    killAllScan()
end

createAlias("^kill-all$", handleKillAllAlias, { type = "regex" })

-- Shorthand: `ka` behaves exactly like `kill-all`.
createAlias("^ka$", handleKillAllAlias, { type = "regex" })

-- Response to the kill-all probe: the room brief's occupant line. Engage the
-- first monster, or end the sweep when the room is clear ("nobody"). The \S+
-- matches either "is" or "are" so single and multi-monster briefs both hit.
createTrigger("^There \\S+ (.+) here\\.$", function(matches)
    if not taPackage.killAllActive then return end
    -- A scan is resolving: bump the generation to cancel its timeout.
    taPackage.killAllGeneration = (taPackage.killAllGeneration or 0) + 1
    local monster = taPackage.firstArenaMonster(matches[2])
    if monster then
        if not startKill(monster) then
            taPackage.killAllActive = false
        end
    else
        killAllDone()
    end
end, { type = "regex" })

-- A leader's kill-stop also stands the group down: a follower's kill loop
-- swings at whatever matches the target's first word, so when the monster we
-- were fighting leaves the room it keeps hitting the next one. Conferring lets
-- the leader pick the moment to move on and have everyone stop with them.
-- Only a leader confers -- followers only obey their leader, so a follower's
-- confer would reach nobody who acts on it.
-- `skill` and `sk` are shorthand.
for _, killStopPattern in ipairs({ "^kill-stop$", "^skill$", "^sk$" }) do
    createAlias(killStopPattern, function()
        stopKill()
        if not taPackage.followTarget
            and taPackage.followedBy and #taPackage.followedBy > 0 then
            send("confer kill-stop")
        end
    end, { type = "regex" })
end

-- A Leader sends its Followers after a monster and joins in: `confer-kill
-- warrior` confers `kill warrior`, which each Follower runs as its own kill
-- (see the "(to group)" trigger), then starts the Leader's own kill loop.
-- `ckill <monster>` and `ck <monster>` are shorthand.
for _, conferKillPattern in ipairs({ "^confer-kill (.+)$", "^ckill (.+)$", "^ck (.+)$" }) do
    createAlias(conferKillPattern, function(matches)
        send("confer kill " .. matches[2])
        startKill(matches[2])
    end, { type = "regex" })
end

-- Deific heal (kusamotu) on whoever has the lowest HE% in the group listing.
-- Threshold 100 so anyone short of full counts; at full health it does nothing.
-- A healer does it here. Anyone else confers the alias's own name, and a
-- healer following us answers it with the same scan (the "(to group)" trigger),
-- so one alias works whether or not the leader can heal.
function taPackage.healMostInjuredPartyMember()
    beginGroupHealScan()
end

createAlias("^heal-most-injured-party-member$", function()
    if taPackage.character.isClass("Acolyte") then
        taPackage.healMostInjuredPartyMember()
    else
        send("confer heal-most-injured-party-member")
    end
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
        { name = "arena",                 running = taPackage.arenaState ~= nil,      stop = function() taPackage.stopArena("stop-all-scripts") end },
        { name = "kill",                  running = taPackage.killActive == true,     stop = stopKill },
        -- Every `running` flag is read when this table is built, before any
        -- stop runs -- which is what keeps the report honest now that stopping
        -- the tavern also disarms banking two rows below.
        { name = "hang-around-in-tavern-and-deposit-gold", running = taPackage.tavernMode == true, stop = stopTavernMode },
        { name = "mapping",               running = taPackage.mapping == true,        stop = taPackage.stopMapping },
        -- The manual door: stopping everything by hand disarms `and-exit` too,
        -- so a walk that was going to leave the game doesn't do it anyway. That
        -- flag outlives the walk by a beat at either end (armed while the start
        -- probe is out, still set while the exit counts down), which is why it
        -- is part of "running" here -- otherwise stop-all-scripts would skip the
        -- stop in exactly the window where disarming matters.
        { name = "navigate",              running = taPackage.navigate ~= nil
                                                    or taPackage.navExitWhenDone ~= nil
                                                    or taPackage.navExiting ~= nil,   stop = taPackage.stopNavigateManual },
        -- Ahead of gold-farming, which starts one: stopping the farm only drops
        -- its claim on the result (createRerollArmed), and the re-roll itself
        -- kept rolling.
        { name = "re-roll",               running = taPackage.reRolling == true,      stop = taPackage.reroll.stop },
        { name = "gold-farming",          running = taPackage.createCharacterRunning(), stop = taPackage.stopCreateCharacter },
        { name = "banking",               running = taPackage.bankingRunning(),       stop = taPackage.stopBanking },
        -- Stops only the 5-minute status poll; the character stays in the group.
        { name = "follow XP poll",        running = taPackage.followXpPollActive == true, stop = taPackage.stopFollowXpPoll },
        -- Not a loop of its own but what starts one: baud reconnects on a
        -- drop, and every fresh login re-runs TA_INIT_CMD ("tfia 3"), so an
        -- arena stopped here would otherwise be back on the next reconnect.
        { name = "TA_INIT_CMD",           running = taPackage.login.initCmd ~= nil,   stop = taPackage.autoLogin.disarmInitCmd },
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
    -- Clear unconditionally: a heal (heal-most-injured-party-member) can fizzle too, and
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
    taPackage.groupHealMembers = (taPackage.groupHealMembers or 0) + 1
    if health < 100 then
        taPackage.groupHealHurt = (taPackage.groupHealHurt or 0) + 1
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
    local gen = taPackage.killGeneration or 0
    createTimer(30000, function()
        if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
            killDebugEcho("melee retry firing after exhaustion")
            killAttack()
        end
    end, { repeating = false })
end, { type = "regex" })

createTrigger("^You are still too mentally exhausted from your last incantation!$", function()
    -- Clear the flag even out of combat (e.g. a heal-most-injured-party-member cast), so a
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

-- While following, send `status` and `i` every 5 minutes so the log keeps
-- capturing XP and gold.
-- Followers never type `st` themselves, so without this a session's only XP
-- readings were at `ta.follow` and (if anyone remembered) `ta.unfollow`. A
-- generation counter makes the rescheduled one-shot timer self-cancel, mirroring
-- scheduleArenaXpCheck. Fields on taPackage, not locals: main.lua's local budget
-- is tight (see CLAUDE.md).
taPackage.FOLLOW_XP_POLL_MS = 300000

function taPackage.scheduleFollowXpPoll()
    local gen = taPackage.followXpPollGen or 0
    createTimer(taPackage.FOLLOW_XP_POLL_MS, function()
        if (taPackage.followXpPollGen or 0) ~= gen then return end
        taPackage.followXpPollPending = true
        send("status")
        send("i")
        taPackage.scheduleFollowXpPoll()
    end, { repeating = false })
end

function taPackage.startFollowXpPoll()
    taPackage.followXpPollGen = (taPackage.followXpPollGen or 0) + 1
    taPackage.followXpPollActive = true
    taPackage.scheduleFollowXpPoll()
end

function taPackage.stopFollowXpPoll()
    taPackage.followXpPollGen = (taPackage.followXpPollGen or 0) + 1
    taPackage.followXpPollActive = false
    taPackage.followXpPollPending = false
end

-- reloadScript() clears pending timers but taPackage survives, so a reload
-- mid-follow would silently end the poll. Re-arm it on load.
if taPackage.followXpPollActive then
    taPackage.startFollowXpPoll()
end

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
    taPackage.startFollowXpPoll()
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
    taPackage.stopFollowXpPoll()
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
    elseif command == "kill-stop" then
        stopKill()
    elseif command == "heal-most-injured-party-member" then
        if taPackage.character.isClass("Acolyte") then
            taPackage.healMostInjuredPartyMember()
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

dofile(scriptDir .. "ta_auto_login.lua")

echo("Finishing reading main.lua")
