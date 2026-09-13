-- A `dbOpen` backed by REAL SQLite, for tests that need to assert on the graph
-- the mapper built rather than on the SQL it issued.
--
-- test_helper's own dbOpen is a call recorder: it answers every query from
-- M.mockDbRows, which is right for "did this alias issue that statement" and
-- useless for "after walking this log, is the room graph correct". The mapper's
-- behaviour depends on what the database answers -- findLoopClosure asks for
-- same-name rooms and their exit-sets, discoverRoom probes for slug collisions,
-- mergeRoomInto relies on INSERT OR IGNORE against a composite primary key --
-- so a test about the graph needs a store that really stores.
--
-- Real SQLite rather than a hand-written fake, for three reasons: ta_db.lua
-- creates its own schema with CREATE TABLE IF NOT EXISTS, so we inherit the
-- production schema for free and cannot drift from it; it introspects itself
-- through sqlite_master and PRAGMA table_info, which a fake would have to
-- imitate; and the semantics that matter most here (INSERT OR IGNORE on
-- (from_id, direction), COALESCE, correlated subqueries) are exactly the ones a
-- fake gets subtly wrong while still passing its own tests.
--
-- The binding is the `sqlite3` CLI, not a LuaRocks C extension: there is no
-- SQLite binding for the Lua 5.5 this repo runs, and `sqlite3` is already a
-- hard requirement (every DB-cleanup recipe in CLAUDE.md and `just db-snapshot`
-- shell out to it). Cost: one process per statement. A 25-room walk is ~400
-- statements, which is seconds, not minutes.

local M = {}

local SEP = "<|>"        -- column separator; no room text contains it
local NULLV = "<<NULL>>" -- distinguishes SQL NULL from the empty string

-- SQLite's own literal escaping: double an embedded single quote, and that is
-- the whole of it. Room descriptions carry apostrophes ("You're") and double
-- quotes (the cryptic message on 1087's west wall), so this has to be right.
local function quote(v)
    if v == nil then return "NULL" end
    if type(v) == "boolean" then return v and "1" or "0" end
    if type(v) == "number" then
        if math.type(v) == "integer" then return tostring(v) end
        return string.format("%.17g", v)
    end
    return "'" .. tostring(v):gsub("'", "''") .. "'"
end

-- Replace each ? with the next parameter, skipping any ? that sits inside a
-- string literal. ta_db.lua has no such case today; the scan is here so that
-- adding one later fails loudly somewhere else rather than binding silently to
-- the wrong position.
local function bind(sql, params)
    local out, i, n, inStr = {}, 1, #sql, false
    local p = 0
    while i <= n do
        local ch = sql:sub(i, i)
        if ch == "'" then
            inStr = not inStr
            out[#out + 1] = ch
        elseif ch == "?" and not inStr then
            p = p + 1
            out[#out + 1] = quote(params[p])
        else
            out[#out + 1] = ch
        end
        i = i + 1
    end
    return table.concat(out)
end

-- The CLI returns every column as text. ids, coordinates and visit counts all
-- flow into `type(x) == "number"` guards in main.lua, so an all-digits field is
-- converted back. No slug, name or description in this world is all digits.
local function coerce(s)
    if s == NULLV then return nil end
    if s:match("^%-?%d+$") then return math.tointeger(tonumber(s)) or tonumber(s) end
    return s
end

local function tmpname(tag)
    return os.tmpname() .. "-" .. tag
end

-- Run `script` (a full set of dot-commands plus SQL) and return its stdout.
-- Piped through a file rather than the shell so no SQL is ever quoted twice.
local function runScript(dbPath, script)
    local cmdPath = tmpname("cmd.sql")
    local f = assert(io.open(cmdPath, "w"))
    f:write(script)
    f:close()
    local pipe = assert(io.popen("sqlite3 " .. dbPath .. " < " .. cmdPath .. " 2>&1", "r"))
    local out = pipe:read("a")
    pipe:close()
    os.remove(cmdPath)
    return out
end

local function makeDb(dbPath, state)
    local api = {}

    function api:execute(sql, ...)
        local stmt = bind(sql, { ... })
        -- changes() and last_insert_rowid() are per-connection, and this binding
        -- opens a connection per statement -- so both are read inside the same
        -- process as the write that set them, and cached for the queryOne below.
        local out = runScript(dbPath,
            ".headers off\n.mode list\n" .. stmt .. ";\n"
            .. "SELECT 'CHANGES'||changes()||'ROWID'||last_insert_rowid();\n")
        local changes, rowid = out:match("CHANGES(%-?%d+)ROWID(%-?%d+)")
        if not changes then
            error("sqlite3 failed for: " .. stmt .. "\n" .. out)
        end
        -- A failed statement still lets the trailing SELECT run, so the CHANGES
        -- line matches and the error would pass unnoticed -- which is how a
        -- UNIQUE violation looked like a success. Anything sqlite3 printed
        -- besides that line is a complaint, and a silent failure in a test
        -- helper is worse than a loud one.
        local noise = out:gsub("CHANGES%-?%d+ROWID%-?%d+%s*", "")
        if noise:find("Error", 1, true) or noise:find("error", 1, true) then
            error("sqlite3 rejected: " .. stmt .. "\n" .. noise)
        end
        state.lastRowid = math.tointeger(tonumber(rowid))
        return math.tointeger(tonumber(changes))
    end

    function api:query(sql, ...)
        -- last_insert_rowid() cannot survive a new connection, so serve it from
        -- what the preceding execute recorded. This is the one place the binding
        -- is not literally SQLite; discoverRoom depends on it.
        if sql:find("last_insert_rowid", 1, true) then
            return { { id = state.lastRowid } }
        end
        local stmt = bind(sql, { ... })
        local out = runScript(dbPath,
            ".headers on\n.mode list\n.separator \"" .. SEP .. "\"\n"
            .. ".nullvalue " .. NULLV .. "\n" .. stmt .. ";\n")
        local lines = {}
        for line in out:gmatch("([^\n]*)\n?") do
            if line ~= "" then lines[#lines + 1] = line end
        end
        if #lines == 0 then return {} end
        if out:find("^Error") or out:find("\nError") then
            error("sqlite3 failed for: " .. stmt .. "\n" .. out)
        end
        local cols = {}
        for col in (lines[1] .. SEP):gmatch("(.-)" .. SEP:gsub("%p", "%%%0")) do
            cols[#cols + 1] = col
        end
        local rows = {}
        for i = 2, #lines do
            local vals, row = {}, {}
            for v in (lines[i] .. SEP):gmatch("(.-)" .. SEP:gsub("%p", "%%%0")) do
                vals[#vals + 1] = v
            end
            for c = 1, #cols do row[cols[c]] = coerce(vals[c] or NULLV) end
            rows[#rows + 1] = row
        end
        return rows
    end

    function api:queryOne(sql, ...)
        local rows = api:query(sql, ...)
        return rows[1]
    end

    api.path = dbPath
    return api
end

-- Install a real-SQLite dbOpen over a fresh temp database. Returns a handle for
-- the test to inspect and tear down. Call BEFORE dofile("main.lua"), because
-- ta_db.lua calls dbOpen at load time.
function M.install()
    local dbPath = tmpname("ta.db")
    os.remove(dbPath)
    local state = { lastRowid = 0 }
    local handle = { path = dbPath }

    dbOpen = function(_name) return makeDb(dbPath, state) end

    -- Straight SELECT access for assertions, outside the mapper's own handle.
    function handle.rows(sql)
        return makeDb(dbPath, state):query(sql)
    end
    function handle.one(sql)
        return makeDb(dbPath, state):queryOne(sql)
    end
    -- Writes, for tests about what the SCHEMA can hold rather than about a Lua
    -- API. The devices table is populated by hand in SQL, so its tests are too.
    function handle.exec(sql)
        return makeDb(dbPath, state):execute(sql)
    end
    function handle.remove()
        for _, suffix in ipairs({ "", "-wal", "-shm" }) do
            os.remove(dbPath .. suffix)
        end
    end
    return handle
end

return M
