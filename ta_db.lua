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

db:execute([[CREATE TABLE IF NOT EXISTS rooms (
  name          TEXT PRIMARY KEY,
  description   TEXT,
  first_visited TEXT,
  visits        INTEGER NOT NULL DEFAULT 0
)]])

db:execute([[CREATE TABLE IF NOT EXISTS room_exits (
  from_room  TEXT NOT NULL REFERENCES rooms(name),
  direction  TEXT NOT NULL,
  to_room    TEXT REFERENCES rooms(name),
  PRIMARY KEY (from_room, direction)
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
-- ADD COLUMN IF NOT EXISTS).
local function tableHasColumn(tbl, col)
    local rows = db:query("PRAGMA table_info(" .. tbl .. ")")
    for _, row in ipairs(rows or {}) do
        if row.name == col then return true end
    end
    return false
end

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

function TaDb.visitRoom(name, description)
    db:execute(
      "INSERT OR IGNORE INTO rooms (name, description, first_visited, visits) VALUES (?, ?, ?, 0)",
      name, description or "", now()
    )
    db:execute("UPDATE rooms SET visits = visits + 1 WHERE name = ?", name)
    dbLog("[DB\xE2\x86\x92rooms] " .. name)
end

function TaDb.recordExit(fromRoom, direction, toRoom)
    db:execute(
        "INSERT OR REPLACE INTO room_exits (from_room, direction, to_room) VALUES (?, ?, ?)",
        fromRoom, direction, toRoom or ""
    )
    dbLog("[DB\xE2\x86\x92room_exits] " .. fromRoom .. " --" .. direction .. "--> " .. (toRoom or "?"))
end

function TaDb.upsertRoomDescription(name, description)
    db:execute("UPDATE rooms SET description = ? WHERE name = ?", description, name)
    dbLog("[DB\xE2\x86\x92rooms] desc: " .. name)
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
