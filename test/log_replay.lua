-- Replay a raw session log through the mapper's triggers, against a real
-- SQLite database, and hand the test the graph that came out.
--
-- Why a log and not hand-written lines: the interesting mapper failures are not
-- in any single trigger, they are in what a few hundred arrivals do to each
-- other. A room is minted, a later arrival matches it on name + exit-set, the
-- merge fills a NULL stub, and the damage shows up twenty rooms downstream. No
-- unit test of a trigger sees that; a walk does. And a log is a real walk, so
-- the fixture costs nothing to author and cannot drift from what the game says.
--
-- The contract: `replay(path)` leaves the database holding whatever the mapper
-- built, and the returned table reads it back as rooms, exits and stubs.

local helper = require("test.test_helper")
local SqliteDb = dofile("test/sqlite_db.lua")

local M = {}

-- ANSI has to come off the WHOLE buffer, not line by line: the BBS splits
-- escape sequences across a newline, so a per-line strip leaves `;37;46m` as
-- visible text and invents a line break mid-sentence (CLAUDE.md, "Session
-- logs"). Backspaces are removed as literal \008, never as a regex \b.
local function clean(buf)
    buf = buf:gsub("\27%[[%d;]*[A-Za-z]", "")
    buf = buf:gsub("\27%][^\7]*\7", "")
    buf = buf:gsub("\r", "")
    buf = buf:gsub("[^\n]\8", "")
    return buf
end

-- A log is a transcript of the terminal, so it holds four kinds of line, and
-- each one took a different path in the live session:
--
--   `$ foo`     a command an alias consumed. baud writes these since
--               TextLogger.logAlias; before that they were lost, which is what
--               `opts.setup` exists to paper over for older logs.
--   `> foo`     a command that went to the server. It still has to take the
--               ALIAS path here, which matters more than it looks: every
--               direction is an alias (main.lua:1543), and it is that alias
--               which queues the move via pushPendingDir and then sends it.
--               Feed these to triggers instead and the mapper never learns a
--               direction was sent, so every arrival is a cold start and
--               nothing links.
--   `[map] ...` the script's own echo() output. Went nowhere -- feeding it back
--               would let the script trigger on itself.
--   everything else, including the BBS's echo of a command we sent. That echo
--               IS a server line, and main.lua depends on it: the `^look$`
--               trigger is how description capture starts.
local function classify(line)
    local alias = line:match("^%$%s*(.-)%s*$")
    if alias then return "alias", alias end
    local input = line:match("^>%s*(.-)%s*$")
    if input then return "input", input end
    if line:match("^%[%w") then return "echo" end
    return "server", line
end

-- Feed a log through the triggers. Loads main.lua fresh over a fresh database,
-- so each replay is independent.
--
-- `opts.setup` is a list of commands to run before the log. It is only needed
-- for logs written BEFORE baud learned to record aliases (TextLogger.logAlias,
-- which writes them as `$ ...`). In an older log an alias left nothing behind
-- but its echo output, so nothing says mapping was ever turned on, let alone
-- into which Area -- the test has to supply that. Newer logs carry the alias
-- lines themselves and need no setup.
--
-- `opts.stopAfter`, if set, stops feeding once that many server lines have gone
-- through, for tests that want the graph mid-walk.
function M.replay(path, opts)
    opts = opts or {}
    helper.resetAll()
    local db = SqliteDb.install()
    dofile("main.lua")
    for _, cmd in ipairs(opts.setup or {}) do
        helper.simulateAlias(cmd)
    end

    local f = assert(io.open(path, "r"), "no such log: " .. path)
    local buf = clean(f:read("a"))
    f:close()

    local fed, typed, aliased = 0, 0, 0
    for line in (buf .. "\n"):gmatch("([^\n]*)\n") do
        if opts.stopAfter and fed >= opts.stopAfter then break end
        local kind, text = classify(line)
        if kind == "server" then
            helper.simulateLine(text)
            fed = fed + 1
        elseif kind == "input" and text ~= "" then
            -- The path typed input takes: first matching alias, else sent as
            -- text. Outbound triggers see it too (that is how `push stone`
            -- declares the position lost).
            helper.simulateOutbound(text)
            runCommand(text)
            typed = typed + 1
        elseif kind == "alias" and text ~= "" then
            -- Same path, but the log has already told us no alias let it
            -- through to the server, so this is the one line kind that needs no
            -- guessing about what ran.
            runCommand(text)
            aliased = aliased + 1
        end
    end

    local g = { db = db, linesFed = fed, linesTyped = typed, aliasesRun = aliased }

    -- Every room, with its exit-set and description, keyed by id.
    function g.rooms()
        local out = {}
        for _, r in ipairs(db.rows(
            "SELECT id, slug, name, description, x, y, z, visits FROM rooms ORDER BY id")) do
            r.exits = {}
            for _, e in ipairs(db.rows(
                "SELECT direction, to_id FROM room_exits WHERE from_id = " .. r.id
                .. " ORDER BY direction")) do
                r.exits[e.direction] = e.to_id or false  -- false = an unwalked Stub
            end
            out[#out + 1] = r
        end
        return out
    end

    function g.roomCount()
        return db.one("SELECT COUNT(*) AS n FROM rooms").n
    end

    -- "n,e,s" for a room id, so a test can state an exit-set the way `ex` does.
    function g.exitSet(id)
        local dirs = {}
        for _, e in ipairs(db.rows(
            "SELECT direction FROM room_exits WHERE from_id = " .. id
            .. " ORDER BY direction")) do
            dirs[#dirs + 1] = e.direction
        end
        table.sort(dirs)
        return table.concat(dirs, ",")
    end

    -- Unwalked exits: the frontier, as "<id> <dir>" strings.
    function g.stubs()
        local out = {}
        for _, e in ipairs(db.rows(
            "SELECT from_id, direction FROM room_exits WHERE to_id IS NULL"
            .. " ORDER BY from_id, direction")) do
            out[#out + 1] = e.from_id .. " " .. e.direction
        end
        return out
    end

    -- Every edge lacking its reverse. A non-empty list is a defect: `A --se--> B`
    -- obliges `B --nw--> A`.
    function g.oneWayEdges()
        local REV = { n = "s", s = "n", e = "w", w = "e",
                      ne = "sw", sw = "ne", nw = "se", se = "nw", u = "d", d = "u" }
        local out = {}
        for _, e in ipairs(db.rows(
            "SELECT from_id, direction, to_id FROM room_exits"
            .. " WHERE to_id IS NOT NULL ORDER BY from_id, direction")) do
            local back = REV[e.direction]
            local row = db.one("SELECT to_id FROM room_exits WHERE from_id = "
                .. e.to_id .. " AND direction = '" .. back .. "'")
            if not row or row.to_id ~= e.from_id then
                out[#out + 1] = e.from_id .. " --" .. e.direction .. "--> " .. e.to_id
            end
        end
        return out
    end

    -- Rooms sharing a description, which is how conflation shows itself: two
    -- corridors that really do read alike are fine, two rooms that ARE one are
    -- not. Returns groups of ids.
    function g.duplicateDescriptions()
        local byDesc = {}
        for _, r in ipairs(g.rooms()) do
            if r.description then
                byDesc[r.description] = byDesc[r.description] or {}
                table.insert(byDesc[r.description], r.id)
            end
        end
        local out = {}
        for _, ids in pairs(byDesc) do
            if #ids > 1 then out[#out + 1] = ids end
        end
        return out
    end

    -- The `[map] ...` lines the run produced, in order. Useful for asserting
    -- that a closure did or did not happen.
    function g.mapEchoes()
        local out = {}
        for _, e in ipairs(helper.echoCalls) do
            if type(e) == "string" and e:match("^%[map%]") then out[#out + 1] = e end
        end
        return out
    end

    function g.echoesMatching(pattern)
        local out = {}
        for _, e in ipairs(helper.echoCalls) do
            if type(e) == "string" and e:find(pattern) then out[#out + 1] = e end
        end
        return out
    end

    return g
end

-- Directions in the order the log sent them, read back from the log itself, so
-- a test can state the walk it expects without transcribing it twice.
function M.movesIn(path)
    local DIRS = { n = true, s = true, e = true, w = true, ne = true, nw = true,
                   se = true, sw = true, u = true, d = true }
    local f = assert(io.open(path, "r"))
    local buf = f:read("a"); f:close()
    local out = {}
    for line in (buf .. "\n"):gmatch("([^\n]*)\n") do
        local cmd = line:match("^>%s*(%S+)%s*$")
        if cmd and DIRS[cmd] then out[#out + 1] = cmd end
    end
    return out
end

return M
