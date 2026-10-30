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
-- Character sheet triggers
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

-- =========================================================================
-- Gold accounting
-- =========================================================================
--
-- Every line that moves our gold: what we carry, find, share, give, receive,
-- bank and spend. All of it goes through taPackage.character.setGold.

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
-- taPackage.lookCapture.state: the room half is handled here, and every other
-- line goes to taPackage.monsters.onLookLine. The mapper itself (position
-- tracking and the room graph) is in ta_map.lua, loaded below.

-- Computed here rather than in ta_monsters.lua: see absoluteScriptDir.
taPackage.monsterStorePath = absoluteScriptDir() .. "monsters.lua"
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
    taPackage.lookCapture.state = "accumulating_room"
    taPackage.lookCapture.accumulatedLines = {}
    taPackage.lookCapture.descRoomId = taPackage.mapping and taPackage.currentRoomId or nil
    taPackage.lookCapture.descRoomProvisional = taPackage.currentRoomProvisional
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
    if taPackage.lookCapture.state ~= "accumulating_room" then return end
    taPackage.lookCapture.state = "idle"
    taPackage.lookCapture.accumulatedLines = {}
    taPackage.lookCapture.descRoomId = nil
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

    if taPackage.lookCapture.state == "accumulating_room" then
        -- Skip our own echoed commands (look starts the capture, ex ends it).
        if line == "look" or line == "l" or line == "ex" then return end
        if isRoomDescTerminator(line) then
            local lines = taPackage.lookCapture.accumulatedLines
            local roomId = taPackage.lookCapture.descRoomId
            -- A room we believed we knew, whose `ex` contradicts the map, is some
            -- other room: its description is not this one's. (A room minted on
            -- this move holds only an assumed back-link, so it is exempt, as it
            -- is in the Exits handler.)
            local exitList = line:match("^Exits: (.+)%.$")
            if roomId and exitList and not taPackage.lookCapture.descRoomProvisional then
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
        elseif #taPackage.lookCapture.accumulatedLines >= ROOM_DESC_MAX_LINES then
            taPackage.abandonRoomDescCapture()
        else
            table.insert(taPackage.lookCapture.accumulatedLines, line)
        end
        return
    end

    taPackage.monsters.onLookLine(line)
end, { type = "regex" })

-- =========================================================================
-- Mapping
-- =========================================================================
--
-- Position tracking and the room graph: ta_map.lua. Loaded here, where the
-- section used to sit, so trigger order is unchanged.
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

-- =========================================================================
-- Re-roll for good stats
-- =========================================================================
--
-- ta_reroll.lua, loaded where its aliases used to sit.
dofile(scriptDir .. "ta_reroll.lua")

-- =========================================================================
-- Ring gong and fight in arena
-- =========================================================================
--
-- The arena loop: ta_arena.lua, which loads ta_leave_game.lua partway
-- through. Loaded here, where the section used to sit, so trigger and alias
-- registration order is unchanged.
dofile(scriptDir .. "ta_arena.lua")

-- =========================================================================
-- hang-around-in-tavern-and-deposit-gold
-- =========================================================================
--
-- Tavern mode: ta_tavern.lua. Loaded here, where the section used to sit, so
-- trigger and alias registration order is unchanged.
dofile(scriptDir .. "ta_tavern.lua")

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
--
-- kill / k, kill-all / ka, kill-stop and heal-most-injured-party-member:
-- ta_kill.lua. Loaded here, where the section used to sit, so alias and
-- trigger registration order is unchanged.
dofile(scriptDir .. "ta_kill.lua")

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

-- =========================================================================
-- Stopping everything
-- =========================================================================
-- Stops every long-running script at once. Each sub-stop is independent and
-- safe to call when its script isn't running (it just resets already-clear
-- state). We check each script's "running" flag first so we can report, per
-- script, whether we actually stopped it or it wasn't running.
--
-- When you add a new script, add it here too (see CLAUDE.md).
createAlias("^stop-all-scripts$", function()
    local scripts = {
        { name = "arena",                 running = taPackage.arenaState ~= nil,      stop = function() taPackage.stopArena("stop-all-scripts") end },
        { name = "kill",                  running = taPackage.killActive == true,     stop = taPackage.kill.stop },
        -- Every `running` flag is read when this table is built, before any
        -- stop runs -- which is what keeps the report honest now that stopping
        -- the tavern also disarms banking two rows below.
        { name = "hang-around-in-tavern-and-deposit-gold", running = taPackage.tavernMode == true, stop = taPackage.tavern.stop },
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
        { name = "follow XP poll",        running = taPackage.followXpPollActive == true, stop = taPackage.follow.stopXpPoll },
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

-- =========================================================================
-- Kill loop triggers
-- =========================================================================
--
-- Registered here, where they always were: after ta_nav.lua, ta_create.lua and
-- ta_bank.lua, whose triggers see the same lines as the loop's catch-all group
-- scan. The triggers themselves are in ta_kill.lua.
taPackage.kill.registerLoopTriggers()

-- =========================================================================
-- Follow
-- =========================================================================
--
-- ta.follow / ta.unfollow: ta_follow.lua. Loaded here, where the section used
-- to sit, so trigger and alias registration order is unchanged.
dofile(scriptDir .. "ta_follow.lua")

-- =========================================================================
-- Auto-login
-- =========================================================================
--
-- Answering the BBS login and menus: ta_auto_login.lua. Loaded last, where
-- the section used to sit: its two "Username:" triggers fire in order, and its
-- catch-all outbound trigger is registered after everything else.
dofile(scriptDir .. "ta_auto_login.lua")

echo("Finishing reading main.lua")
