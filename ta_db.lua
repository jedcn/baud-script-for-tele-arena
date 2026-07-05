local TaDb = {}

-- Per-write debug logging is off by default so normal sessions stay quiet.
-- Set TaDb.debug = true to surface the [DB->...] traces.
TaDb.debug = false

local function dbLog(msg)
    if TaDb.debug then
        echo(msg)
    end
end

local db = dbOpen("tele-arena.db")

-- WAL mode lets multiple sessions read concurrently while one writes.
-- busy_timeout tells SQLite to retry for up to 5s before giving up on a lock.
db:execute("PRAGMA journal_mode = WAL")
db:execute("PRAGMA busy_timeout = 5000")

-- Schema-introspection helpers (used by the migrations below and reused for
-- the player_spells column check further down).
local function tableExists(tbl)
    local row = db:queryOne(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", tbl)
    return row ~= nil
end

local function tableHasColumn(tbl, col)
    local rows = db:query("PRAGMA table_info(" .. tbl .. ")")
    for _, row in ipairs(rows or {}) do
        if row.name == col then return true end
    end
    return false
end

-- Room-graph migration. The original rooms/room_exits schema keyed rooms by
-- display name, so identically-named rooms (every "cave") collapsed into one
-- row and their exits overwrote each other. The new schema keys rooms by an
-- auto-incrementing integer id and resolves identity from the walk graph. When
-- the old name-keyed tables are detected (rooms exists but has no `id` column),
-- rename them aside so nothing is lost, then create the fresh id-keyed tables.
-- Guarded so it's a no-op once migrated, and idempotent across reloadScript().
if tableExists("rooms") and not tableHasColumn("rooms", "id") then
    pcall(function() db:execute("ALTER TABLE rooms RENAME TO rooms_legacy") end)
    if tableExists("room_exits") then
        pcall(function() db:execute("ALTER TABLE room_exits RENAME TO room_exits_legacy") end)
    end
end

db:execute([[CREATE TABLE IF NOT EXISTS areas (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL
)]])

db:execute([[CREATE TABLE IF NOT EXISTS rooms (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  slug          TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  description   TEXT,
  area_id       INTEGER REFERENCES areas(id),
  first_visited TEXT,
  visits        INTEGER NOT NULL DEFAULT 0
)]])

db:execute([[CREATE TABLE IF NOT EXISTS room_exits (
  from_id    INTEGER NOT NULL REFERENCES rooms(id),
  direction  TEXT NOT NULL,
  to_id      INTEGER REFERENCES rooms(id),
  PRIMARY KEY (from_id, direction)
)]])

db:execute([[CREATE TABLE IF NOT EXISTS monsters (
  name        TEXT PRIMARY KEY,
  description TEXT,
  first_seen  TEXT,
  encounters  INTEGER NOT NULL DEFAULT 0
)]])

db:execute([[CREATE TABLE IF NOT EXISTS denizens (
  name        TEXT NOT NULL,
  location    TEXT NOT NULL,
  description TEXT,
  first_seen  TEXT,
  PRIMARY KEY (name, location)
)]])

db:execute([[CREATE TABLE IF NOT EXISTS shop_items (
  name       TEXT NOT NULL,
  shop       TEXT NOT NULL,
  price      INTEGER,
  min_level  INTEGER,
  first_seen TEXT,
  PRIMARY KEY (name, shop)
)]])

db:execute([[CREATE TABLE IF NOT EXISTS services (
  name       TEXT NOT NULL,
  location   TEXT NOT NULL,
  cost       INTEGER,
  first_used TEXT,
  uses       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (name, location)
)]])

db:execute([[CREATE TABLE IF NOT EXISTS stat_changes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  stat        TEXT NOT NULL,
  from_value  INTEGER NOT NULL,
  to_value    INTEGER NOT NULL,
  recorded_at TEXT NOT NULL
)]])

db:execute([[CREATE TABLE IF NOT EXISTS player_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  weapon      TEXT NOT NULL,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,
  damage      INTEGER,
  recorded_at TEXT NOT NULL
)]])

db:execute([[CREATE TABLE IF NOT EXISTS monster_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,
  damage      INTEGER,
  recorded_at TEXT NOT NULL
)]])

db:execute([[CREATE TABLE IF NOT EXISTS monster_loot (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  gold        INTEGER NOT NULL DEFAULT 0,
  recorded_at TEXT NOT NULL
)]])

db:execute([[CREATE TABLE IF NOT EXISTS item_drops (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  item        TEXT NOT NULL,
  recorded_at TEXT NOT NULL
)]])

-- Append-only log of every spell we cast. `kind` ('offense' | 'heal') groups
-- spells by what they do, so queries can aggregate without hardcoding spell
-- names and a new spell of a known kind is captured correctly from day one.
-- NOTE: `amount` is interpreted per kind — damage dealt for 'offense', HP
-- restored for 'heal' — so always filter by `kind` (or `spell`) before
-- aggregating `amount`, or you'll average unlike things together. When a
-- genuinely new kind appears (e.g. a stat buff whose effect isn't a single
-- integer), that's the signal to revisit this shape rather than overload
-- `amount` further.
-- kind is last to match what the migration below produces for pre-existing
-- DBs (ALTER ... ADD COLUMN appends), so fresh and migrated schemas are
-- identical. All access is by column name, so the position is cosmetic.
db:execute([[CREATE TABLE IF NOT EXISTS player_spells (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  spell       TEXT NOT NULL,
  target      TEXT,
  outcome     TEXT NOT NULL,
  amount      INTEGER,
  recorded_at TEXT NOT NULL,
  kind        TEXT
)]])

-- Migration: player_spells predates the `kind` column. Add it if missing and
-- backfill the known spells so historical rows stay queryable by kind. The
-- PRAGMA check keeps this idempotent across reloads (SQLite has no
-- ADD COLUMN IF NOT EXISTS). tableHasColumn is defined near the top of this
-- module (it's also used by the room-graph migration).
if not tableHasColumn("player_spells", "kind") then
    -- pcall guards the rare false-negative: if the column already exists but
    -- the PRAGMA check missed it, a reload must not crash on a duplicate
    -- column. The backfill UPDATEs are idempotent, so they're safe to re-run.
    pcall(function()
        db:execute("ALTER TABLE player_spells ADD COLUMN kind TEXT")
    end)
    db:execute("UPDATE player_spells SET kind = 'heal' WHERE spell IN ('motu', 'kamotu')")
    db:execute("UPDATE player_spells SET kind = 'offense' WHERE spell = 'komiza'")
end

local function now()
    return os.date("%Y-%m-%dT%H:%M:%S")
end

-- =========================================================================
-- Room graph
--
-- Rooms are identified by an integer id, not their display name, so that
-- identically-named rooms (every "cave") stay distinct. Identity is resolved
-- topologically by the caller in main.lua: a new room is discovered only when
-- you step through an exit whose destination isn't known yet.
-- =========================================================================

-- Turn a display name into a URL-ish slug: "north plaza" -> "north-plaza".
local function baseSlug(name)
    local s = (name or ""):lower()
    s = s:gsub("[^%w]+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    if s == "" then s = "room" end
    return s
end

-- Return a collision-free slug for `name`: the base slug if unused, else the
-- base with the lowest free "-N" suffix (cave, cave-1, cave-2, ...).
function TaDb.slugForName(name)
    local base = baseSlug(name)
    if not db:queryOne("SELECT 1 AS n FROM rooms WHERE slug = ?", base) then
        return base
    end
    local i = 1
    while db:queryOne("SELECT 1 AS n FROM rooms WHERE slug = ?", base .. "-" .. i) do
        i = i + 1
    end
    return base .. "-" .. i
end

-- Ensure an area row exists; return its id. Idempotent.
function TaDb.ensureArea(slug, name)
    local changes = db:execute("INSERT OR IGNORE INTO areas (slug, name) VALUES (?, ?)", slug, name or slug)
    local row = db:queryOne("SELECT id FROM areas WHERE slug = ?", slug)
    local id = row and row.id
    echo("[mapdbg] ensureArea slug=" .. tostring(slug) .. " INSERT changes=" .. tostring(changes)
        .. " -> id=" .. tostring(id) .. " (" .. type(id) .. ")")
    return id
end

-- Insert a newly discovered room (visits starts at 0; the caller records the
-- visit) and return its id.
function TaDb.discoverRoom(name, areaId)
    local slug = TaDb.slugForName(name)
    local changes = db:execute(
        "INSERT INTO rooms (slug, name, description, area_id, first_visited, visits) VALUES (?, ?, NULL, ?, ?, 0)",
        slug, name, areaId, now()
    )
    local row = db:queryOne("SELECT id FROM rooms WHERE slug = ?", slug)
    local id = row and row.id
    echo("[mapdbg] discoverRoom slug=" .. tostring(slug) .. " INSERT changes=" .. tostring(changes)
        .. " -> id=" .. tostring(id) .. " (" .. type(id) .. ")")
    dbLog("[DB\xE2\x86\x92rooms] discovered #" .. tostring(id) .. " " .. slug)
    return id
end

-- The recorded destination of an exit, or nil if the exit is unknown or its
-- destination is still unexplored (a NULL to_id stub from `ex`).
function TaDb.exitDestination(fromId, dir)
    local row = db:queryOne(
        "SELECT to_id FROM room_exits WHERE from_id = ? AND direction = ?", fromId, dir)
    return row and row.to_id
end

-- Record a confirmed edge with a concrete destination (a walked exit).
function TaDb.linkExit(fromId, dir, toId)
    db:execute(
        "INSERT OR REPLACE INTO room_exits (from_id, direction, to_id) VALUES (?, ?, ?)",
        fromId, dir, toId
    )
    dbLog("[DB\xE2\x86\x92room_exits] #" .. tostring(fromId) .. " --" .. dir .. "--> #" .. tostring(toId))
end

-- Seed a known-but-unexplored exit (destination NULL) from the `ex` command.
-- INSERT OR IGNORE so it never clobbers an already-known destination.
function TaDb.recordKnownExit(fromId, dir)
    db:execute(
        "INSERT OR IGNORE INTO room_exits (from_id, direction, to_id) VALUES (?, ?, NULL)",
        fromId, dir
    )
end

function TaDb.recordVisit(roomId)
    db:execute("UPDATE rooms SET visits = visits + 1 WHERE id = ?", roomId)
end

function TaDb.setRoomDescription(roomId, description)
    db:execute("UPDATE rooms SET description = ? WHERE id = ?", description, roomId)
    dbLog("[DB\xE2\x86\x92rooms] desc: #" .. tostring(roomId))
end

-- All room ids sharing a display name; used to resolve a cold-start room
-- (no prior room to walk from) when the name is unambiguous.
function TaDb.roomIdsByName(name)
    local rows = db:query("SELECT id FROM rooms WHERE name = ?", name) or {}
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = row.id end
    return ids
end

-- The set of exit directions recorded for a room (walked edges + `ex` stubs),
-- as a { [dir] = true } table. This is the room's exit-set "fingerprint".
function TaDb.roomExitDirections(roomId)
    local rows = db:query("SELECT direction FROM room_exits WHERE from_id = ?", roomId) or {}
    local set = {}
    for _, row in ipairs(rows) do set[row.direction] = true end
    return set
end

-- Loop closure: find the one existing room that IS this room — same display
-- name and the same exit-set (`dirs`, a list of directions) — excluding
-- `excludeId` (the room we currently think we're in). Returns that room's id,
-- or nil when there's no match or more than one (ambiguous, e.g. identical
-- caves — left for a manual assert rather than guessed).
function TaDb.findRoomByFingerprint(name, dirs, excludeId)
    local want, wantCount = {}, 0
    for _, dir in ipairs(dirs) do
        if not want[dir] then want[dir] = true; wantCount = wantCount + 1 end
    end
    local match
    for _, id in ipairs(TaDb.roomIdsByName(name)) do
        if id ~= excludeId then
            local have = TaDb.roomExitDirections(id)
            local haveCount, ok = 0, true
            for dir in pairs(have) do
                haveCount = haveCount + 1
                if not want[dir] then ok = false; break end
            end
            if ok and haveCount == wantCount then
                if match then return nil end  -- ambiguous: >1 match
                match = id
            end
        end
    end
    return match
end

-- Fold a provisional room into an existing one (loop closure): repoint every
-- edge that pointed at `fromId` to `intoId`, move `fromId`'s outgoing edges onto
-- `intoId` (without clobbering ones it already has), carry the visit count, then
-- delete the provisional room.
function TaDb.mergeRoomInto(fromId, intoId)
    -- Move outgoing edges first (before inbound repointing can create self-loops).
    local outgoing = db:query(
        "SELECT direction, to_id FROM room_exits WHERE from_id = ?", fromId) or {}
    for _, row in ipairs(outgoing) do
        local dest = row.to_id
        if dest == fromId then dest = intoId end  -- self-loop guard
        db:execute(
            "INSERT OR IGNORE INTO room_exits (from_id, direction, to_id) VALUES (?, ?, ?)",
            intoId, row.direction, dest
        )
    end
    db:execute("DELETE FROM room_exits WHERE from_id = ?", fromId)
    -- Repoint inbound edges (to_id isn't part of the PK, so this can't conflict).
    db:execute("UPDATE room_exits SET to_id = ? WHERE to_id = ?", intoId, fromId)
    db:execute(
        "UPDATE rooms SET visits = visits + COALESCE((SELECT visits FROM rooms WHERE id = ?), 0) WHERE id = ?",
        fromId, intoId
    )
    db:execute("DELETE FROM rooms WHERE id = ?", fromId)
    dbLog("[DB\xE2\x86\x92rooms] merged #" .. tostring(fromId) .. " into #" .. tostring(intoId))
end

function TaDb.upsertMonster(name, description)
    db:execute(
        "INSERT OR IGNORE INTO monsters (name, description, first_seen, encounters) VALUES (?, ?, ?, 0)",
        name, description, now()
    )
    db:execute(
        "UPDATE monsters SET description = ?, encounters = encounters + 1 WHERE name = ?",
        description, name
    )
    dbLog("[DB\xE2\x86\x92monsters] " .. name)
end

function TaDb.recordMonsterSeen(name)
    local changed = db:execute("UPDATE monsters SET encounters = encounters + 1 WHERE name = ?", name)
    if changed and changed > 0 then
        dbLog("[DB\xE2\x86\x92monsters] seen: " .. name)
    end
end

function TaDb.monsterHasDescription(name)
    local row = db:queryOne("SELECT description FROM monsters WHERE name = ?", name)
    return row ~= nil and row.description ~= nil and row.description ~= ""
end

function TaDb.upsertDenizen(name, location, description)
    db:execute(
        "INSERT OR IGNORE INTO denizens (name, location, description, first_seen) VALUES (?, ?, ?, ?)",
        name, location, description or "", now()
    )
    db:execute(
        "UPDATE denizens SET description = ? WHERE name = ? AND location = ?",
        description or "", name, location
    )
    dbLog("[DB\xE2\x86\x92denizens] " .. name .. " @ " .. location)
end

function TaDb.recordShopItem(name, shop, price)
    db:execute(
        "INSERT OR IGNORE INTO shop_items (name, shop, price, first_seen) VALUES (?, ?, ?, ?)",
        name, shop, price, now()
    )
    db:execute("UPDATE shop_items SET price = ? WHERE name = ? AND shop = ?", price, name, shop)
    dbLog("[DB\xE2\x86\x92shop_items] " .. shop .. ": " .. name .. " " .. price .. "gp")
end

function TaDb.recordMinLevel(name, shop, level)
    db:execute("UPDATE shop_items SET min_level = ? WHERE name = ? AND shop = ?", level, name, shop)
    dbLog("[DB\xE2\x86\x92shop_items] min_level updated: " .. name .. " @ " .. shop .. " >= level " .. level)
end

function TaDb.recordService(name, location, cost)
    db:execute(
        "INSERT OR IGNORE INTO services (name, location, cost, first_used, uses) VALUES (?, ?, ?, ?, 0)",
        name, location, cost, now()
    )
    db:execute(
        "UPDATE services SET cost = ?, uses = uses + 1 WHERE name = ? AND location = ?",
        cost, name, location
    )
    dbLog("[DB\xE2\x86\x92services] " .. location .. ": " .. name .. " " .. cost .. "gp")
end

function TaDb.recordStatChange(stat, fromVal, toVal)
    db:execute(
        "INSERT INTO stat_changes (stat, from_value, to_value, recorded_at) VALUES (?, ?, ?, ?)",
        stat, fromVal, toVal, now()
    )
    dbLog("[DB\xE2\x86\x92stat_changes] " .. stat .. ": " .. fromVal .. " \xE2\x86\x92 " .. toVal)
end

function TaDb.recordPlayerAttack(weapon, monster, outcome, damage)
    db:execute(
        "INSERT INTO player_attacks (weapon, monster, outcome, damage, recorded_at) VALUES (?, ?, ?, ?, ?)",
        weapon, monster, outcome, damage or 0, now()
    )
end

function TaDb.recordMonsterAttack(monster, outcome, damage)
    db:execute(
        "INSERT INTO monster_attacks (monster, outcome, damage, recorded_at) VALUES (?, ?, ?, ?)",
        monster, outcome, damage or 0, now()
    )
    if outcome == "hit" then
        dbLog("[DB\xE2\x86\x92monster_attacks] " .. monster .. " HIT you: " .. (damage or 0) .. " dmg")
    elseif outcome == "miss" then
        dbLog("[DB\xE2\x86\x92monster_attacks] " .. monster .. " MISS")
    else
        dbLog("[DB\xE2\x86\x92monster_attacks] " .. monster .. " " .. outcome:upper())
    end
end

function TaDb.recordMonsterLoot(monster, gold)
    db:execute(
        "INSERT INTO monster_loot (monster, gold, recorded_at) VALUES (?, ?, ?)",
        monster, gold, now()
    )
    dbLog("[DB\xE2\x86\x92monster_loot] " .. monster .. ": " .. gold .. " gold")
end

function TaDb.recordPlayerSpell(spell, target, outcome, amount, kind)
    db:execute(
        "INSERT INTO player_spells (spell, target, outcome, amount, recorded_at, kind) VALUES (?, ?, ?, ?, ?, ?)",
        spell, target or "", outcome, amount, now(), kind
    )
    local msg = "[DB\xE2\x86\x92player_spells] " .. spell .. " \xE2\x86\x92 " .. (target or "?") .. " [" .. outcome .. "]"
    if type(amount) == "number" then msg = msg .. " " .. amount end
    dbLog(msg)
end

function TaDb.recordItemDrop(monster, item)
    db:execute(
        "INSERT INTO item_drops (monster, item, recorded_at) VALUES (?, ?, ?)",
        monster, item, now()
    )
    dbLog("[DB\xE2\x86\x92item_drops] " .. monster .. " dropped: " .. item)
end

return TaDb
