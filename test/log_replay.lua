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
-- `opts.rewrite` substitutes command text as the log is replayed, keyed by the
-- exact line. It exists for one reason, and it is not a convenience: a room's
-- slug is a function of MINT ORDER, so `map-here stonework-corridor-20` only
-- names the room the log meant against the database that log produced. Fixing
-- the mapper so an earlier session mints two rooms it had been losing renumbered
-- every later slug by one, and the resumption's anchor silently moved to the room
-- before the one it wanted. Stating the substitution in the fixture keeps the
-- replay honest about the walk while naming the right room.
--
-- `opts.seed` is a list of SQL statements run against the fresh database before
-- the first log, for rows a walk needs that no log in the chain builds. The one
-- case it exists for is a walk that crosses a Seam: Stoneworks level 2 opens with
-- `map-here stonework-corridor-45`, a level 1 room, and replaying the ten level 1
-- logs that eventually mint it would triple the suite's runtime to assert nothing
-- about level 2. What level 1 actually contributes is two things, and the seed
-- states both: the room the stairs come down from, and the SLUGS level 1 has
-- already taken -- because a slug is the lowest free `-N`, so the logs'
-- `map-here` lines only name the right room if the numbering starts where it
-- really did. Seed rows are inert: they carry no coordinates and (bar the Seam)
-- no exits, and area-scoped matching means level 2 never mistakes one for a room
-- it walked.
--
-- `opts.stopAfter`, if set, stops feeding once that many server lines have gone
-- through, for tests that want the graph mid-walk.
function M.replay(path, opts)
    return M.replayChain({ path }, opts)
end

-- Replay several logs in order against ONE database, which is what a resumed
-- mapping session needs. `map-here stonework-corridor-20` only resolves if that
-- room is already there, so a log that picks up where an earlier one stopped
-- cannot be replayed alone -- against an empty database it fails, mapping never
-- turns on, and nothing is built.
--
-- Between logs the SCRIPT state is reset and main.lua reloaded, while the
-- database is kept. That models what really happened: each session was a fresh
-- baud with a fresh taPackage, re-anchoring itself from a database that outlived
-- the previous one. Carrying taPackage across instead would leave mapping still
-- switched on, so the next session's login brief would be processed as a mapping
-- arrival -- which is not what the game did.
function M.replayChain(paths, opts)
    opts = opts or {}
    helper.resetAll()
    local db = SqliteDb.install()

    local fed, typed, aliased = 0, 0, 0
    for i, path in ipairs(paths) do
        if i > 1 then
            helper.resetAll()
            -- resetAll clears taPackage; dofile reopens the SAME database file,
            -- because SqliteDb.install left dbOpen pointing at it.
            dofile("main.lua")
        else
            dofile("main.lua")
        end
        -- Seeded after main.lua, which is what creates the schema, and before
        -- setup, which may name a seeded room.
        if i == 1 then
            for _, sql in ipairs(opts.seed or {}) do db.exec(sql) end
        end
        for _, cmd in ipairs((opts.setup or {})[i] or {}) do
            helper.simulateAlias(cmd)
        end

        local f = assert(io.open(path, "r"), "no such log: " .. path)
        local buf = clean(f:read("a"))
        f:close()

        -- Does this log record aliases? It changes what a `> ` line means, and
        -- getting it wrong runs every move twice.
        --
        -- In a log that HAS `$ ` lines, a typed `nw` appears as BOTH `$ nw` (the
        -- alias matched) and `> nw` (the send that same alias then made). They
        -- are one keystroke, not two. Replaying both queues two pending
        -- directions per move, so the next arrival is matched against the wrong
        -- one and the graph comes apart -- 29 rooms and 16 stubs where the live
        -- session built 27 and 3. So here `> ` means "already sent": outbound
        -- triggers only, never the alias path.
        --
        -- In an older log aliases were not recorded at all, so `> nw` is the
        -- only trace of the move and has to run as a command.
        local records = buf:find("\n%$ ") ~= nil or buf:find("^%$ ") ~= nil

        for line in (buf .. "\n"):gmatch("([^\n]*)\n") do
            if opts.stopAfter and fed >= opts.stopAfter then break end
            local kind, text = classify(line)
            if kind == "server" then
                helper.simulateLine(text)
                fed = fed + 1
            elseif kind == "input" and text ~= "" then
                -- Outbound triggers see everything sent (that is how
                -- `push stone` declares the position lost).
                helper.simulateOutbound(text)
                if not records then
                    runCommand(text)
                    typed = typed + 1
                end
            elseif kind == "alias" and text ~= "" then
                runCommand((opts.rewrite or {})[text] or text)
                aliased = aliased + 1
            end
        end
    end

    local g = { db = db, linesFed = fed, linesTyped = typed, aliasesRun = aliased }

    -- Every room, with its exit-set and description, keyed by id.
    function g.rooms()
        local out = {}
        for _, r in ipairs(db.rows(
            "SELECT id, slug, name, description, x, y, z, visits, trap FROM rooms"
            .. " ORDER BY id")) do
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
        -- `passage` is its own reverse, matching verify.ts:16. It is the ferry
        -- edge between the two towns' docks -- a Teleport deliberately recorded
        -- as an edge, under a direction name that carries no grid delta. Leave it
        -- out and every replay crossing the great lake reports two false defects.
        local REV = { n = "s", s = "n", e = "w", w = "e",
                      ne = "sw", sw = "ne", nw = "se", se = "nw", u = "d", d = "u",
                      passage = "passage" }
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

    -- Rooms whose recorded exit-set disagrees with their own Description.
    --
    -- A room states its exits in prose, in one of two rigid forms, which makes the
    -- Description an independent check on the edges we recorded -- and the only
    -- check that catches CONFLATION, where two rooms were merged into one and the
    -- survivor ends up wearing both sets of exits. The 2026-09 desert damage reads
    -- exactly like that: `desert` says "except to the south and northeast" and
    -- carries five edges.
    --
    --   corridors   "The corridor runs to the north and southeast." Both verbs
    --               matter: matching only "runs" silently skips every "continues"
    --               room and reports them as fine.
    --   the desert  "Huge black outcroppings of rock block travel in all directions
    --               except to the south and northeast."
    --
    -- Chambers are deliberately not read. Their prose is free, and the form it
    -- does use is a claim about VISIBILITY rather than about exits ("The northern
    -- portion of this chamber is obscured by a strange mist. The only visible exit
    -- is east." -- where north is real but not visible), so reading it would report
    -- a true edge as a defect. Assert those by hand.
    --
    -- `u`/`d` are excluded on both sides: stairs get a sentence of their own
    -- ("There is a stone staircase here leading downward") and never appear among
    -- the directions.
    local WORD = { north = "n", south = "s", east = "e", west = "w",
                   northeast = "ne", northwest = "nw",
                   southeast = "se", southwest = "sw" }

    -- The directions a description names, as a sorted "n,se" string, or nil where
    -- it uses no form we trust.
    local function proseDirs(description)
        if not description then return nil end
        local said = description:match("corridor runs to the ([^.]+)%.")
            or description:match("corridor continues to the ([^.]+)%.")
            or description:match("block travel in all directions except to the ([^.]+)%.")
        if not said then return nil end
        local dirs, seen = {}, {}
        for word in said:gmatch("%a+") do
            local dir = WORD[word]
            if dir and not seen[dir] then
                seen[dir] = true
                dirs[#dirs + 1] = dir
            end
        end
        if #dirs == 0 then return nil end
        table.sort(dirs)
        return table.concat(dirs, ",")
    end
    g.proseDirs = proseDirs

    function g.proseMismatches()
        local bad = {}
        for _, r in ipairs(g.rooms()) do
            local said = proseDirs(r.description)
            if said then
                local got = {}
                for dir in pairs(r.exits) do
                    if dir ~= "u" and dir ~= "d" then got[#got + 1] = dir end
                end
                table.sort(got)
                got = table.concat(got, ",")
                if said ~= got then
                    bad[#bad + 1] = r.id .. " " .. r.slug
                        .. ": prose says " .. said .. ", edges say " .. got
                end
            end
        end
        return bad
    end

    -- How many rooms g.proseMismatches() actually examined, so a test can notice
    -- the check silently covering nothing.
    function g.prosesChecked()
        local n = 0
        for _, r in ipairs(g.rooms()) do
            if proseDirs(r.description) then n = n + 1 end
        end
        return n
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

    -- Moves sent and not yet paired with an arrival, after the last log. Should
    -- be empty at the end of any well-behaved session: a direction left in the
    -- queue gets paired with whatever room is entered next, however much later,
    -- and written into the graph as an edge that was never walked.
    function g.pendingDirs()
        local out = {}
        for _, d in ipairs(taPackage and taPackage.pendingDirs or {}) do
            out[#out + 1] = d
        end
        return out
    end

    -- The `[map] ...` lines the run produced, in order. Useful for asserting
    -- that a closure did or did not happen. In a chain these are the LAST log's
    -- echoes only: the script state is reset between logs, which is what lets a
    -- test say "this session made no closure" without the earlier ones' noise.
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
-- Read from the `$ ` lines where the log has them. A direction IS an alias, so
-- in a log that records aliases those lines are exactly the moves, and reading
-- `> ` instead picks up login-menu answers -- the `n` that chooses a menu item
-- before the game even starts reads as a move north.
function M.movesIn(path)
    local DIRS = { n = true, s = true, e = true, w = true, ne = true, nw = true,
                   se = true, sw = true, u = true, d = true }
    local f = assert(io.open(path, "r"))
    local buf = f:read("a"); f:close()
    local prefix = (buf:find("\n%$ ") or buf:find("^%$ ")) and "^%$" or "^>"
    local out = {}
    for line in (buf .. "\n"):gmatch("([^\n]*)\n") do
        local cmd = line:match(prefix .. "%s*(%S+)%s*$")
        if cmd and DIRS[cmd] then out[#out + 1] = cmd end
    end
    return out
end

return M
