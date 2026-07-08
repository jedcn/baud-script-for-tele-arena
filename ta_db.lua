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
  visits        INTEGER NOT NULL DEFAULT 0,
  x             INTEGER,
  y             INTEGER,
  z             INTEGER,
  trap          TEXT
)]])

-- Migration: rooms predates the x/y/z coordinate columns. Coordinates are
-- dead-reckoned from movement deltas (see main.lua) and let identically-named
-- rooms (every "cave") be told apart by position, which the name+exit-set
-- fingerprint can't do. `trap` records a hazard sprung in the room (e.g.
-- "spiked trap", "trap door"). Add the columns if missing; idempotent.
for _, colDef in ipairs({ { "x", "INTEGER" }, { "y", "INTEGER" }, { "z", "INTEGER" }, { "trap", "TEXT" } }) do
    if not tableHasColumn("rooms", colDef[1]) then
        pcall(function() db:execute("ALTER TABLE rooms ADD COLUMN " .. colDef[1] .. " " .. colDef[2]) end)
    end
end

db:execute([[CREATE TABLE IF NOT EXISTS room_exits (
  from_id    INTEGER NOT NULL REFERENCES rooms(id),
  direction  TEXT NOT NULL,
  to_id      INTEGER REFERENCES rooms(id),
  lock_key   TEXT,
  lock_door  TEXT,
  PRIMARY KEY (from_id, direction)
)]])

-- Migration: room_exits predates the lock columns. A locked exit records the
-- door's material (lock_door, e.g. "bronze") and the key that opens it
-- (lock_key, e.g. "bronze") when known -- a blocked exit we lack the key for
-- has lock_door set and lock_key NULL. Add the columns if missing; idempotent.
for _, col in ipairs({ "lock_key", "lock_door" }) do
    if not tableHasColumn("room_exits", col) then
        pcall(function() db:execute("ALTER TABLE room_exits ADD COLUMN " .. col .. " TEXT") end)
    end
end

-- Last known room per character, so `just report` can mark "you are here". A
-- character maps into the shared DB under its own name; last-known (not live)
-- is the intended semantics — it persists where a character logged off.
db:execute([[CREATE TABLE IF NOT EXISTS player_location (
  player     TEXT PRIMARY KEY,
  room_id    INTEGER REFERENCES rooms(id),
  updated_at TEXT
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

-- room_id is last to match what the migration below produces for pre-existing
-- DBs (ALTER ... ADD COLUMN appends), so fresh and migrated schemas are
-- identical. It records where the item was found (notably keys for locked
-- doors), NULL when we weren't mapping and so don't reliably know the room.
db:execute([[CREATE TABLE IF NOT EXISTS item_drops (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  item        TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  room_id     INTEGER REFERENCES rooms(id)
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

-- Migration: item_drops predates the `room_id` column (where the item was
-- found). Add it if missing; historical rows keep NULL. Added without the
-- REFERENCES clause the fresh schema carries, since SQLite ADD COLUMN rejects it
-- -- the column is otherwise identical and foreign keys aren't enforced here.
if not tableHasColumn("item_drops", "room_id") then
    pcall(function()
        db:execute("ALTER TABLE item_drops ADD COLUMN room_id INTEGER")
    end)
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

-- Every known area as { slug = , name = } rows, in discovery order.
function TaDb.listAreas()
    return db:query("SELECT slug, name FROM areas ORDER BY id") or {}
end

-- The area id for a slug, or nil if there's no such area.
function TaDb.areaIdBySlug(slug)
    local row = db:queryOne("SELECT id FROM areas WHERE slug = ?", slug)
    return row and row.id
end

-- Move a single room into a different area, preserving all its exits (including
-- the seam back to its old area). Used when a frontier walk crosses into a fresh
-- area: the entry room is discovered under the *previous* area's id (the
-- frontier lives on a room of that area), so `map-area <new>` re-files the room
-- you're standing in here. Returns true if a row was updated.
function TaDb.setRoomArea(roomId, areaId)
    local changes = db:execute("UPDATE rooms SET area_id = ? WHERE id = ?", areaId, roomId)
    dbLog("[DB\xE2\x86\x92rooms] moved room #" .. tostring(roomId)
        .. " -> area #" .. tostring(areaId))
    return changes and changes > 0
end

-- Wipe an area's rooms and exits so it can be re-walked from scratch, leaving
-- every other area intact. Edges from OTHER areas that pointed into this one are
-- reverted to unexplored stubs (to_id = NULL) so they don't dangle at a deleted
-- room. The area row itself is kept, so the slug survives for re-mapping.
-- Returns the number of rooms removed.
function TaDb.resetArea(areaId)
    db:execute(
        "UPDATE room_exits SET to_id = NULL WHERE to_id IN (SELECT id FROM rooms WHERE area_id = ?)",
        areaId)
    db:execute(
        "DELETE FROM room_exits WHERE from_id IN (SELECT id FROM rooms WHERE area_id = ?)",
        areaId)
    local removed = db:execute("DELETE FROM rooms WHERE area_id = ?", areaId)
    dbLog("[DB\xE2\x86\x92rooms] reset area #" .. tostring(areaId)
        .. " (" .. tostring(removed) .. " rooms)")
    return removed
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

-- Tag an exit as a locked door. `key` is the key that opens it (nil when we
-- only know the door blocked us), `door` its material. The exit may not have
-- been walked yet (a door we were turned away from), so ensure a stub row
-- exists first, then set the lock columns without disturbing to_id.
function TaDb.setExitLock(fromId, dir, key, door)
    db:execute(
        "INSERT OR IGNORE INTO room_exits (from_id, direction, to_id) VALUES (?, ?, NULL)",
        fromId, dir
    )
    db:execute(
        "UPDATE room_exits SET lock_key = ?, lock_door = ? WHERE from_id = ? AND direction = ?",
        key, door, fromId, dir
    )
    dbLog("[DB\xE2\x86\x92room_exits] lock #" .. tostring(fromId) .. " " .. dir
        .. " door=" .. tostring(door) .. " key=" .. tostring(key))
end

function TaDb.recordVisit(roomId)
    db:execute("UPDATE rooms SET visits = visits + 1 WHERE id = ?", roomId)
end

-- Remember which room a character is standing in (for the report's "you are
-- here" marker). Upsert keyed by character name.
function TaDb.setPlayerLocation(player, roomId)
    db:execute(
        "INSERT INTO player_location (player, room_id, updated_at) VALUES (?, ?, ?) "
        .. "ON CONFLICT(player) DO UPDATE SET room_id = excluded.room_id, updated_at = excluded.updated_at",
        player, roomId, now()
    )
    dbLog("[DB\xE2\x86\x92player_location] " .. tostring(player) .. " @ #" .. tostring(roomId))
end

function TaDb.setRoomDescription(roomId, description)
    db:execute("UPDATE rooms SET description = ? WHERE id = ?", description, roomId)
    dbLog("[DB\xE2\x86\x92rooms] desc: #" .. tostring(roomId))
end

-- The dead-reckoned coordinate stamped on a room, as { x, y, z }, or nil when
-- the room has no coordinate yet (x IS NULL). Coordinates are area-local: only
-- their relative offsets matter, so the origin per area is wherever mapping
-- first anchored.
function TaDb.roomCoord(roomId)
    local row = db:queryOne("SELECT x, y, z FROM rooms WHERE id = ?", roomId)
    if not row or row.x == nil then return nil end
    return { x = row.x, y = row.y, z = row.z }
end

function TaDb.setRoomCoord(roomId, x, y, z)
    db:execute("UPDATE rooms SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, roomId)
    dbLog("[DB\xE2\x86\x92rooms] coord: #" .. tostring(roomId)
        .. " (" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ")")
end

-- Record that a hazard (trap type string) sprang in this room. Last write wins;
-- a room has one trap in practice, and re-tagging on a repeat visit is a no-op.
function TaDb.setRoomTrap(roomId, trap)
    db:execute("UPDATE rooms SET trap = ? WHERE id = ?", trap, roomId)
    dbLog("[DB\xE2\x86\x92rooms] trap: #" .. tostring(roomId) .. " " .. tostring(trap))
end

-- Coordinate-based identity: the one room in `areaId` with this display name
-- sitting at exactly (x, y, z), excluding `excludeId`. Returns its id, or nil
-- when nothing matches or more than one does (ambiguous — don't guess). This is
-- a stronger signal than the name+exit-set fingerprint: two "cave" rooms at
-- different coordinates are provably distinct, and one we return to by a
-- different path lands on its original coordinate and closes the loop.
function TaDb.findRoomAtCoord(areaId, name, x, y, z, excludeId)
    local rows = db:query(
        "SELECT id FROM rooms WHERE area_id = ? AND name = ? AND x = ? AND y = ? AND z = ? AND id <> ?",
        areaId, name, x, y, z, excludeId or -1) or {}
    if #rows ~= 1 then return nil end
    return rows[1].id
end

-- Every known room whose display name AND exit-set match (name, dirs), as a
-- list of { id, slug, x, y, z }. Unlike findRoomByFingerprint (which returns a
-- single unambiguous match or nil), this returns ALL candidates — used by
-- `map-print-room-slug` to show what room you might be standing in.
function TaDb.roomsMatchingFingerprint(name, dirs)
    local want, wantCount = {}, 0
    for _, dir in ipairs(dirs) do
        if not want[dir] then want[dir] = true; wantCount = wantCount + 1 end
    end
    local out = {}
    local rows = db:query("SELECT id, slug, x, y, z FROM rooms WHERE name = ?", name) or {}
    for _, row in ipairs(rows) do
        local have = TaDb.roomExitDirections(row.id)
        local haveCount, ok = 0, true
        for dir in pairs(have) do
            haveCount = haveCount + 1
            if not want[dir] then ok = false; break end
        end
        if ok and haveCount == wantCount then
            out[#out + 1] = { id = row.id, slug = row.slug, x = row.x, y = row.y, z = row.z }
        end
    end
    return out
end

-- All room ids sharing a display name; used to resolve a cold-start room
-- (no prior room to walk from) when the name is unambiguous.
function TaDb.roomIdsByName(name)
    local rows = db:query("SELECT id FROM rooms WHERE name = ?", name) or {}
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = row.id end
    return ids
end

-- The display name recorded for a room id (nil if the room is gone).
function TaDb.roomName(roomId)
    local row = db:queryOne("SELECT name FROM rooms WHERE id = ?", roomId)
    return row and row.name
end

-- The full row for a room by its (unique) slug, or nil. Used by `map-here` to
-- re-anchor at a known room when the name alone is ambiguous.
function TaDb.roomBySlug(slug)
    return db:queryOne("SELECT id, name, area_id, x, y, z FROM rooms WHERE slug = ?", slug)
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
--
-- `coord` (optional { x, y, z }) is a hard guard against over-merging: a
-- candidate whose stored coordinate disagrees with `coord` is a provably
-- different room, so it's skipped even if its name and exit-set match. This is
-- what keeps two distinct caves that share a fingerprint from collapsing once
-- coordinates are known; when `coord` is nil (nothing to dead-reckon from) the
-- guard is inert and we fall back to name+exit-set alone.
function TaDb.findRoomByFingerprint(name, dirs, excludeId, coord)
    local want, wantCount = {}, 0
    for _, dir in ipairs(dirs) do
        if not want[dir] then want[dir] = true; wantCount = wantCount + 1 end
    end
    local match
    for _, id in ipairs(TaDb.roomIdsByName(name)) do
        if id ~= excludeId then
            local cand = coord and TaDb.roomCoord(id)
            if cand and (cand.x ~= coord.x or cand.y ~= coord.y or cand.z ~= coord.z) then
                -- Different coordinate: provably not this room. Skip.
                goto continue
            end
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
        ::continue::
    end
    return match
end

-- Topological loop closure, for when coordinates have drifted too far to trust
-- (this world's rooms never really sat on a grid). Among same-name rooms whose
-- exit-set exactly matches the one we just observed, the room we re-entered is
-- the one whose exit back the way we came (`back` = reverse of the direction we
-- walked) still exists but is unexplored: we walked through that door from the
-- far side, so it must be here and not yet lead anywhere. An already-walked
-- `back` commits that room to a different neighbour, so it can't be this one.
-- Returns the unique such room, or nil if there's none or more than one.
function TaDb.findLoopClosure(name, dirs, excludeId, back)
    if not back then return nil end
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
            -- Same exit-set, and the return door exists but is still unwalked
            -- (a real numeric to_id means it already leads somewhere else).
            if ok and haveCount == wantCount and have[back]
                and type(TaDb.exitDestination(id, back)) ~= "number" then
                if match then return nil end  -- ambiguous: >1 candidate
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
--
-- A merge must never create a SELF-LOOP (a room exit pointing at itself). The
-- common case that would: the provisional room's reverse back-edge points at
-- `intoId` (e.g. we walked intoId --dir--> provisional, so provisional has a
-- back-edge to intoId). Naively repointing turns that into intoId --> intoId.
-- Those spurious self-loops corrupt exitDestination and silently swallow real
-- rooms, so we drop the edge back to an unexplored stub instead.
function TaDb.mergeRoomInto(fromId, intoId)
    -- Move outgoing edges, but never one that would point intoId at itself.
    local outgoing = db:query(
        "SELECT direction, to_id FROM room_exits WHERE from_id = ?", fromId) or {}
    for _, row in ipairs(outgoing) do
        local dest = row.to_id
        if dest == fromId then dest = intoId end
        if dest ~= intoId then
            db:execute(
                "INSERT OR IGNORE INTO room_exits (from_id, direction, to_id) VALUES (?, ?, ?)",
                intoId, row.direction, dest
            )
            -- If intoId already had this exit as an unexplored stub, fill it with
            -- the destination the provisional walked (the IGNORE above kept the
            -- stub). This is what completes a loop closure: the room we folded in
            -- knew where its back-edge went, but intoId's matching exit was still
            -- an open frontier. Only ever upgrade a NULL stub; never clobber an
            -- exit that already leads somewhere real.
            if type(dest) == "number" then
                db:execute(
                    "UPDATE room_exits SET to_id = ? WHERE from_id = ? AND direction = ? AND to_id IS NULL",
                    dest, intoId, row.direction
                )
            end
        end
    end
    db:execute("DELETE FROM room_exits WHERE from_id = ?", fromId)
    -- An inbound edge FROM intoId to the provisional (intoId --dir--> fromId)
    -- would repoint to a self-loop; reset it to an unexplored stub instead.
    db:execute("UPDATE room_exits SET to_id = NULL WHERE from_id = ? AND to_id = ?", intoId, fromId)
    -- Repoint the remaining inbound edges (to_id isn't part of the PK).
    db:execute("UPDATE room_exits SET to_id = ? WHERE to_id = ?", intoId, fromId)
    db:execute(
        "UPDATE rooms SET visits = visits + COALESCE((SELECT visits FROM rooms WHERE id = ?), 0) WHERE id = ?",
        fromId, intoId
    )
    -- Keep the provisional room's description if the target hasn't got one yet
    -- (the description is captured on arrival, before this merge runs).
    db:execute(
        "UPDATE rooms SET description = COALESCE(description, (SELECT description FROM rooms WHERE id = ?)) WHERE id = ?",
        fromId, intoId
    )
    -- Likewise carry the provisional's dead-reckoned coordinate when the target
    -- has none, so coordinate identity can recognize this room on a later visit.
    db:execute(
        "UPDATE rooms SET x = COALESCE(x, (SELECT x FROM rooms WHERE id = ?)),"
        .. " y = COALESCE(y, (SELECT y FROM rooms WHERE id = ?)),"
        .. " z = COALESCE(z, (SELECT z FROM rooms WHERE id = ?)) WHERE id = ?",
        fromId, fromId, fromId, intoId
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

-- roomId is where the item was found (nil when unknown -> NULL), letting the
-- map answer "where do I find the ruby key" -- valuable for the keys that open
-- locked doors.
function TaDb.recordItemDrop(monster, item, roomId)
    db:execute(
        "INSERT INTO item_drops (monster, item, recorded_at, room_id) VALUES (?, ?, ?, ?)",
        monster, item, now(), roomId
    )
    dbLog("[DB\xE2\x86\x92item_drops] " .. monster .. " dropped: " .. item
        .. " @ room #" .. tostring(roomId))
end

return TaDb
