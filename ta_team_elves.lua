-- ta_team_elves.lua -- `team-fight-elves`: a group clears elven champions and
-- elven warriors
--
-- Run from a High Priest leading a group, in a room on the Elven Valley ring
-- where elves stand: champions in trios at the corners and the middle of the
-- north side, warriors in pairs along the sides. The group fights everything
-- here, champions first, then chases down each elf that fled, then comes back.
-- It succeeds when it is back in this room and no elf is left in it.
--
-- Elves leave a room only when close to death or when chasing one of our
-- characters, so a departure during a fight is always a flee. Leaving turns our
-- backs on the healthy ones, which then follow, so the room is finished first
-- and the flee directions wait in a queue.
--
-- Loaded by main.lua after ta_kill.lua's loop triggers, so a death has already
-- ended the kill loop by the time our trigger sees it. A separate chunk; the
-- seam runs through taPackage:
--
--   in    taPackage.kill.start / .stop, taPackage.character, taPackage.arenaState,
--         taPackage.killActive, taPackage.navStepDelayMs / .navTripRetryMs /
--         .navFloor (ta_nav.lua: navigate-to's pace and trip recovery)
--         taPackage.utils.sendNtfy; followers answering `confer report-xp`
--         (ta_follow.lua) and `confer exit-game`; taPackage.exitGameWithRetry
--         (ta_leave_game.lua)
--   out   taPackage.teamElves.running / .stop (stop-all-scripts)
--
-- `team-fight-elves-in-loop` keeps going: after each room it walks on round the
-- ring, keeping its heading, until a room with an elf in it, and fights there
-- the same way. It runs until `team-fight-elves-in-loop-stop`, which also takes
-- every character out of the game.
--
-- Each time the loop leaves the REPORT_CORNER, the leader pushes an "Elven
-- Valley Update" to ntfy: when, how long the circuit took, and everyone's XP
-- gain over it, which the followers send back over group chat.
--
-- `run` is a local on purpose: a reloadScript() cannot carry the poll timer over,
-- so a run should not survive one either.

taPackage.teamElves = {}

local TAG = "[elves] "
-- What the script fights, in the order it attacks them: champions first, as
-- they hit harder (100-140 a blow in the logs, warriors 90-105). Each is the
-- word `kill` takes and the noun the game uses after "elven".
local KINDS = { "champion", "warrior" }
local POLL_MS = 3000                -- `group` is the only view of health and Ready
local ARRIVAL_SETTLE_MS = 1000      -- followers land a beat after the leader; a
                                    -- `kill` conferred sooner finds nothing nearby
local WALK_LOST_TICKS = 3           -- polls with no arrival before giving up
local HEAL_BELOW_PERCENT = 85
local HEAL_COOLDOWN_MS = 24000      -- the shortest gap between heals in the logs
                                    -- was 25s; asking sooner is only refused
local MAX_CHASE_ROOMS = 10          -- the longest chase in the logs was 8
local MAX_CHASE_FIGHT = 2           -- away from home, fight up to this many; the
                                    -- group beat five at once on 2026-11-07, but
                                    -- a full trio found on a chase hurt it badly

local REPORT_CORNER = "SE"
local REPORT_WAIT_MS = 15000        -- how long to wait for the followers' XP

-- The ring's corners are the only rooms on it with these two exits.
local CORNERS = { ["e,s"] = "NW", ["s,w"] = "NE", ["n,w"] = "SE", ["e,n"] = "SW" }

local SHORT_DIRECTION = {
    north = "n", south = "s", east = "e", west = "w",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw",
}
local OPPOSITE = {
    n = "s", s = "n", e = "w", w = "e",
    ne = "sw", sw = "ne", nw = "se", se = "nw",
}
local COUNT_WORDS = {
    two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
}

-- What a phase means:
--   "fight"   engaged, or about to be; every poll re-reads the room
--   "muster"  stood down, polling `group` until everyone is Ready
--   "walk"    a move is out, waiting for the room to print
--   "tripped" the move was refused by a fall; waiting to look at the floor
--   "tripcheck" looking at the floor for anything the fall shook loose
-- With `run.travel` set, the run is a loop's leg between rooms of elves: no
-- home yet, so moves are not recorded, and the first elf seen makes home.
local run = nil

-- When we last walked into a room, and what lay on its floor. Moves are paced
-- from the arrival as navigate-to paces them: at the loop's old pace, about one
-- move every 0.7s, Pelayo tripped three times in four minutes and left a
-- heartstone and a coil of rope on the ring (session-pelayo-2026-11-07T16-53-41).
local lastArrivalAt = nil
local floorHere = nil

-- When the last group heal landed, whoever cast it. Outside `run` so that a heal
-- typed by hand, or cast just before a run started, still counts.
local lastHealAt = nil

-- "three elven champions, and four elven warriors", "an elven warrior": how
-- many of each kind, and in all. A plural with a count word we don't know is
-- still at least two.
function taPackage.teamElves.countElves(contents)
    local counts = { total = 0 }
    for _, kind in ipairs(KINDS) do counts[kind] = 0 end
    for word, kind, plural in (contents:lower() .. " "):gmatch("(%S+) elven (%a-)(s?)[,%s]") do
        if counts[kind] then
            local n = plural == "" and 1 or COUNT_WORDS[word] or 2
            counts[kind] = counts[kind] + n
            counts.total = counts.total + n
        end
    end
    return counts
end

local NO_ELVES = taPackage.teamElves.countElves("")

local function targetFor(counts)
    for _, kind in ipairs(KINDS) do
        if counts[kind] > 0 then return kind end
    end
    return nil
end

-- Which way the ring continues. Straight on if we can, which also carries us
-- through the junction at the top of the spur; otherwise this is a corner, and
-- the only way on is the exit we did not come in by. Nil if that isn't one exit.
function taPackage.teamElves.ringNext(exits, heading)
    local onward = {}
    for _, exit in ipairs(exits) do
        if exit == heading then return heading end
        if exit ~= OPPOSITE[heading] then table.insert(onward, exit) end
    end
    if #onward == 1 then return onward[1] end
    return nil
end

-- An XP reading for everyone, so the logs hold exact numbers for a run
-- instead of whatever the followers' 5-minute poll happened to catch.
local function markXp()
    send("status")
    send("confer status")
end

-- Where the loop goes next. On along the ring if `ringNext` can tell; else, as at
-- the start or the top of the spur, the first of n, e, s, w that isn't back.
function taPackage.teamElves.loopNext(exits, heading)
    if heading then
        local direction = taPackage.teamElves.ringNext(exits, heading)
        if direction then return direction end
    end
    for _, direction in ipairs({ "n", "e", "s", "w" }) do
        if direction ~= OPPOSITE[heading] then
            for _, exit in ipairs(exits) do
                if exit == direction then return direction end
            end
        end
    end
    return nil
end

-- Which corner these exits make, if any: "NW", "NE", "SE" or "SW".
function taPackage.teamElves.cornerOf(exits)
    local sorted = {}
    for _, exit in ipairs(exits) do table.insert(sorted, exit) end
    table.sort(sorted)
    return CORNERS[table.concat(sorted, ",")]
end

-- The corner report being gathered: our own XP from `status`, the followers'
-- from their `xp-is` replies.
local pendingReport = nil

-- Millions to one place, cut rather than rounded, without the leading zero:
-- 1153000 -> "1.1M", 382000 -> ".3M".
local function formatGain(xp)
    local tenths = math.floor(xp / 100000)
    local text = string.format("%d.%dM", tenths // 10, tenths % 10)
    return (text:gsub("^0%.", "."))
end

local function sendReport(report)
    if report.sent then return end
    report.sent = true
    if pendingReport == report then pendingReport = nil end
    local lines = { "- reached " .. REPORT_CORNER .. " corner at " .. os.date("%H:%M") }
    local previous = report.previous
    if not previous then
        lines[#lines + 1] = "- first time round: timing the circuit from here"
    else
        local minutes = math.floor((report.at - previous.at) / 60000 + 0.5)
        lines[#lines + 1] = "- last circuit took " .. minutes .. " minutes"
        lines[#lines + 1] = "- XP gains:"
        local names = {}
        for name in pairs(report.xp) do table.insert(names, name) end
        for name in pairs(previous.xp) do
            if not report.xp[name] then table.insert(names, name) end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local now, before = report.xp[name], previous.xp[name]
            lines[#lines + 1] = "  - " .. name .. " "
                .. ((now and before) and formatGain(now - before) or "?")
        end
    end
    taPackage.utils.sendNtfy("Elven Valley Update", table.concat(lines, "\n"), true)
end

local function recordXp(name, xp)
    local report = pendingReport
    if not report then return end
    report.xp[name:lower()] = xp
    local have = 0
    for _ in pairs(report.xp) do have = have + 1 end
    if report.expected and have >= report.expected then sendReport(report) end
end

-- Asks everyone for their XP; the report goes out once all have answered, or
-- after REPORT_WAIT_MS with "?" for whoever didn't.
local function cornerReport(loop)
    local report = {
        at = taPackage.utils.nowMillis(),
        xp = {},
        previous = loop.lastCorner,
        expected = loop.members,
    }
    loop.lastCorner = report
    pendingReport = report
    send("status")
    send("confer report-xp")
    createTimer(REPORT_WAIT_MS, function() sendReport(report) end, { repeating = false })
end

local function newRun(loop)
    return {
        phase = "fight",
        path = {},        -- moves out from the starting room
        flees = {},       -- directions elves left the starting room in
        kills = 0,
        abandoned = 0,
        elves = NO_ELVES, -- what the latest occupant line said
        engaged = false,
        loop = loop,      -- { heading, kills } while looping, else nil
        travel = false,
    }
end

local tick

local function begin(newRunState)
    run = newRunState
    local thisRun = run
    createTimer(POLL_MS, function() tick(thisRun) end, { repeating = false })
end

local probeGroup

-- A loop's next leg: wait for everyone to be Ready, then walk on.
local function travel(loop)
    local leg = newRun(loop)
    leg.travel = true
    leg.phase = "muster"
    begin(leg)
    probeGroup()
end

local function finish(message)
    local loop = run.loop
    if loop then
        loop.kills = loop.kills + run.kills
        message = message .. string.format(" %d this loop. Moving on.", loop.kills)
    end
    run = nil
    echo(TAG .. message)
    markXp()
    if loop then travel(loop) end
end

local function standDown()
    if not run.engaged then return end
    run.engaged = false
    send("confer kill-stop")
    taPackage.kill.stop()
end

local function stop()
    if not run then return end
    run.loop = nil
    standDown()
    finish("Stopped.")
end
taPackage.teamElves.stop = stop

function taPackage.teamElves.running()
    return run ~= nil
end

local function isHome()
    return #run.path == 0
end

-- A bare return prints the room; the occupant line lands in the trigger below
-- and the floor line, which every room prints, acts on it.
local function scanRoom()
    send("")
end

-- The listing has no end of its own, so `ex` closes it, as in ta_kill.lua's heal
-- scan. Its reply also gives us the exits a chase needs.
function probeGroup()
    run.rows = nil
    send("group")
    send("ex")
end

local function muster()
    standDown()
    run.phase = "muster"
    probeGroup()
end

local function engage(counts)
    if taPackage.killActive then return end
    local target = targetFor(counts)
    run.engaged = true
    send("confer kill " .. target)
    if not taPackage.kill.start(target) then
        run.loop = nil
        finish("Could not start the kill loop.")
    end
end

local function sendMove(direction)
    run.phase = "walk"
    run.pendingMove = direction
    run.walkTicks = 0
    send(direction)
end

-- No sooner than navigate-to's pace after the last arrival. Anything that
-- changes the phase while we wait (an elf catching us) calls the move off.
local function move(direction)
    local waited = lastArrivalAt and taPackage.utils.nowMillis() - lastArrivalAt
    local pace = taPackage.navStepDelayMs
    if not waited or waited >= pace then
        sendMove(direction)
        return
    end
    if run.paced then return end
    local token, phase = {}, run.phase
    run.paced = token
    createTimer(pace - waited, function()
        if not run or run.paced ~= token then return end
        run.paced = nil
        if run.phase == phase then sendMove(direction) end
    end, { repeating = false })
end

-- Whatever stopped us walking, the room decides what is next: fight what's here,
-- or carry on once it is clear. Giving up instead left the group standing still
-- while three champions that had followed it hit them for nearly two minutes
-- (logs/session-pelayo-2026-11-07T14-58-23.log, 15:01:57).
local function backToFighting()
    run.travel = false
    run.pendingMove = nil
    run.phase = "fight"
    scanRoom()
end

local function abandonChase(reason)
    echo(TAG .. reason .. " Going back.")
    run.chase = nil
    run.abandoned = run.abandoned + 1
end

-- The room we are in holds no elf, so what is next?
local function roomClear()
    if run.chase or not isHome() then
        muster()
    elseif #run.flees > 0 then
        run.chase = table.remove(run.flees, 1)
        run.chaseFresh = true
        echo(TAG .. "Room clear. Chasing the one that went " .. run.chase .. ".")
        muster()
    elseif run.loop and run.kills == 0 and run.abandoned == 0 then
        -- Nothing was fought here, so there is nothing to report.
        standDown()
        local loop = run.loop
        run = nil
        travel(loop)
    elseif run.abandoned > 0 then
        standDown()
        finish(string.format("Back and the room is clear: %d killed, %d chase(s) given up.",
            run.kills, run.abandoned))
    else
        standDown()
        finish(string.format("All elves dead: %d killed.", run.kills))
    end
end

-- Everyone is Ready: take the next step, along the ring or back home.
local function stepOnward(exits)
    if run.travel then
        local direction = taPackage.teamElves.loopNext(exits, run.loop.heading)
        if not direction then
            run.loop = nil
            finish("Can't tell which way the ring goes from here; stopping the loop.")
            return
        end
        -- Once per visit: a fight with an elf that caught us here comes
        -- back through this step.
        if taPackage.teamElves.cornerOf(exits) == REPORT_CORNER then
            if not run.loop.atReportCorner then
                run.loop.atReportCorner = true
                cornerReport(run.loop)
            end
        else
            run.loop.atReportCorner = nil
        end
        run.loop.heading = direction
        move(direction)
        return
    end
    if run.chase and #run.path >= MAX_CHASE_ROOMS then
        abandonChase("Nothing within " .. MAX_CHASE_ROOMS .. " rooms.")
    end
    if run.chase then
        local direction = run.chase
        if run.chaseFresh then
            run.chaseFresh = false
        else
            direction = taPackage.teamElves.ringNext(exits, run.chase)
        end
        if direction then
            run.chase = direction
            move(direction)
            return
        end
        abandonChase("Can't tell which way the ring goes.")
    end
    if isHome() then
        roomClear()
    else
        move(OPPOSITE[run.path[#run.path]])
    end
end

-- Moves are recorded when the room prints, so a refused one leaves no trace. A
-- step back the way we came shortens the path home instead of lengthening it.
local function recordMove(direction)
    if run.path[#run.path] == OPPOSITE[direction] then
        table.remove(run.path)
    else
        table.insert(run.path, direction)
    end
end

local function arrive(count)
    lastArrivalAt = taPackage.utils.nowMillis()
    if run.travel then
        run.pendingMove = nil
        if count == 0 then
            muster()
            return
        end
        -- The first room with an elf becomes home, whatever the count.
        run.travel = false
        echo(TAG .. "Fighting the elves here.")
        markXp()
    else
        recordMove(run.pendingMove)
        run.pendingMove = nil
    end
    if count == 0 then
        if run.chase or not isHome() then
            muster()
        else
            roomClear()
        end
    elseif count <= MAX_CHASE_FIGHT or isHome() then
        -- Few enough to take on here, or home with company: home is where a
        -- big fight belongs.
        run.chase = nil
        run.phase = "fight"
        local thisRun = run
        createTimer(ARRIVAL_SETTLE_MS, function()
            if run == thisRun then scanRoom() end
        end, { repeating = false })
    else
        -- Too many at once can kill the group. Any that chase us will reach
        -- home a few at a time, and walking on is the way to make that happen.
        if run.chase then
            abandonChase(count .. " elves here is too many at once.")
        end
        muster()
    end
end

function tick(thisRun)
    if run ~= thisRun then return end
    if run.phase == "tripped" or run.phase == "tripcheck" then
        -- The trip's own timer carries on from here.
    elseif run.phase == "fight" then
        probeGroup()
        scanRoom()
    elseif run.phase == "muster" then
        probeGroup()
    else
        run.walkTicks = run.walkTicks + 1
        if run.walkTicks >= WALK_LOST_TICKS then
            echo(TAG .. "Never reached the next room. Checking this one.")
            backToFighting()
        end
    end
    createTimer(POLL_MS, function() tick(thisRun) end, { repeating = false })
end

local function healRecovered()
    return not lastHealAt
        or taPackage.utils.nowMillis() - lastHealAt >= HEAL_COOLDOWN_MS
end

-- The group listing closed. Heal first in any phase, then see if we can move.
local function readGroup(exits)
    local rows = run.rows
    run.rows = nil
    local allReady = true
    local hurt = false
    for _, row in ipairs(rows) do
        if row.health < HEAL_BELOW_PERCENT then hurt = true end
        if row.state ~= "Ready" then allReady = false end
    end
    if hurt and healRecovered() then
        -- Not a step as well: a cast leaves the caster too tired to move, and the
        -- game refuses it. The next polls wait for Ready again, and a move
        -- already waiting on the pace is called off for the same reason.
        run.paced = nil
        send("cast kusamotumaru")
        return
    end
    if run.loop then run.loop.members = #rows end
    if run.phase == "muster" and allReady then stepOnward(exits) end
end

local function canStart()
    if run then
        echo(TAG .. "Already running.")
        return false
    end
    if taPackage.arenaState then
        echo(TAG .. "Cannot start — arena session is active.")
        return false
    end
    if not taPackage.character.isClass("Acolyte") then
        echo(TAG .. "This needs a High Priest to lead; run 'st' if that's you.")
        return false
    end
    return true
end

createAlias("^team-fight-elves$", function()
    if not canStart() then return end
    begin(newRun(nil))
    echo(TAG .. "Fighting the elves here.")
    markXp()
    scanRoom()
end, { type = "regex" })

-- Starts by fighting whatever is here; an empty room just sets it walking.
createAlias("^team-fight-elves-in-loop$", function()
    if not canStart() then return end
    begin(newRun({ heading = nil, kills = 0 }))
    echo(TAG .. "Looping round the ring until team-fight-elves-in-loop-stop.")
    markXp()
    scanRoom()
end, { type = "regex" })

createAlias("^stop-team-fight-elves$", stop, { type = "regex" })

-- The end of a session: everyone stops and leaves the game. The followers are
-- told first and forget their leader before they go, so the "no longer a
-- member" line that follows doesn't read as the leader having been lost
-- (ta_follow.lua), and nobody gets a notification for an exit asked for.
createAlias("^team-fight-elves-in-loop-stop$", function()
    if runCommand then runCommand("stop-all-scripts") else stop() end
    echo(TAG .. "Everyone is leaving the game.")
    send("confer exit-game")
    taPackage.exitGameWithRetry()
end, { type = "regex" })

createTrigger("^There \\S+ (.+) here\\.$", function(matches)
    if not run then return end
    run.elves = taPackage.teamElves.countElves(matches[2])
end, { type = "regex" })

-- Picks up what the fall shook loose, then tries the move again, unless
-- an elf has come to us meanwhile.
local function afterTrip(count, items)
    local dropped = taPackage.navFloor.newItems(run.tripFloor or {}, items)
    if #dropped > 0 then
        echo(TAG .. "The fall shook loose the " .. table.concat(dropped, ", the ")
            .. ". Picking it back up.")
        taPackage.navFloor.pickUp(dropped)
    end
    floorHere = items
    if count > 0 then
        backToFighting()
        return
    end
    -- Back to waiting on the move, so a wait cut short by an arrival still
    -- counts as the step having gone nowhere.
    local direction = run.pendingMove
    run.phase = "walk"
    lastArrivalAt = taPackage.utils.nowMillis()
    move(direction)
end

-- The end of every room. A room with players and no monster has no occupant line
-- at all, which is why the count is reset here rather than trusted to be fresh.
createTrigger("^There (.+) on the floor\\.$", function(matches)
    if not run then return end
    local phrase = matches[2]:match("^is (.+) lying$") or matches[2]:match("^are (.+) lying$")
    local items = phrase and taPackage.navFloor.parse(phrase) or {}
    local elves = run.elves
    run.elves = NO_ELVES
    if run.phase == "tripcheck" then
        afterTrip(elves.total, items)
        return
    end
    floorHere = items
    if run.phase == "walk" then
        arrive(elves.total)
    elseif run.phase == "fight" then
        if elves.total > 0 then engage(elves) else roomClear() end
    end
end, { type = "regex" })

local function fled(matches)
    if not run or run.phase ~= "fight" then return end
    local direction = SHORT_DIRECTION[matches[2]]
    if not direction then return end
    if isHome() then
        table.insert(run.flees, direction)
    else
        run.chase = direction
        run.chaseFresh = true
    end
end

-- While we stand waiting to move, an arrival has caught us: turn and fight. In a
-- fight at home, one that came back is one fewer to go looking for.
local function arrived(matches)
    if not run then return end
    if run.phase == "muster" then
        backToFighting()
        return
    end
    if run.phase ~= "fight" or not isHome() then return end
    local direction = SHORT_DIRECTION[matches[2]]
    for i, flee in ipairs(run.flees) do
        if flee == direction then
            table.remove(run.flees, i)
            return
        end
    end
end

-- Our target walked out: the kill loop has nothing to swing at and would sit
-- there still marked active, so clear it for the next scan to start a new one.
local function targetGone()
    if not run or run.phase ~= "fight" then return end
    taPackage.kill.stop()
    scanRoom()
end

-- One trigger per kind rather than an alternation, which the specs' regex
-- translation can't express.
for _, kind in ipairs(KINDS) do
    createTrigger("^The elven " .. kind .. " has just gone to the (\\w+)\\.$", fled, { type = "regex" })
    createTrigger("^An elven " .. kind .. " has just arrived from the (\\w+)\\.$", arrived, { type = "regex" })
    createTrigger("^Sorry, you don't see \"" .. kind .. "\" nearby\\.$", targetGone, { type = "regex" })
end

local IS_KIND = {}
for _, kind in ipairs(KINDS) do IS_KIND["elven " .. kind] = true end

-- Any death ends every kill loop in the room, whoever else is left in it.
createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    if not run then return end
    if IS_KIND[matches[2]] then run.kills = run.kills + 1 end
    if run.phase == "fight" then scanRoom() end
end, { type = "regex" })

-- The move was refused and nothing prints. As navigate-to does: wait out the
-- fall, look at the floor, pick up whatever the fall dropped, then go again.
createTrigger("^In your haste, you trip and fall!$", function()
    if not run or run.phase ~= "walk" then return end
    run.phase = "tripped"
    run.tripFloor = floorHere
    local thisRun = run
    createTimer(taPackage.navTripRetryMs, function()
        if run ~= thisRun or run.phase ~= "tripped" then return end
        run.phase = "tripcheck"
        run.elves = NO_ELVES
        scanRoom()
    end, { repeating = false })
end, { type = "regex" })

for _, refusal in ipairs({
    "^You cannot leave in the heat of battle!$",
    "^Sorry, you'll have to rest a while before you can move\\.$",
}) do
    createTrigger(refusal, function()
        if run and run.phase == "walk" then backToFighting() end
    end, { type = "regex" })
end

-- Timed from the heal landing, so a cast the game refused starts no wait.
createTrigger("^You discharged the spell at friendly people in the area", function()
    lastHealAt = taPackage.utils.nowMillis()
end, { type = "regex" })

createTrigger("^Your group currently consists of:$", function()
    if run then run.rows = {} end
end, { type = "regex" })

createTrigger("^\\s+(\\S+).*HE:\\s*(\\d+)% ST:(\\w+)", function(matches)
    if not run or not run.rows then return end
    table.insert(run.rows, { health = tonumber(matches[3]), state = matches[4] })
end, { type = "regex" })

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
    if not pendingReport then return end
    recordXp(taPackage.character.getName() or "leader", tonumber(matches[2]))
end, { type = "regex" })

createTrigger("^From (\\S+) \\(to group\\): xp-is (\\d+)$", function(matches)
    recordXp(matches[2], tonumber(matches[3]))
end, { type = "regex" })

createTrigger("^Exits: (.+)\\.$", function(matches)
    if not run or not run.rows then return end
    local exits = {}
    for exit in matches[2]:gmatch("[^,%s]+") do table.insert(exits, exit) end
    readGroup(exits)
end, { type = "regex" })
