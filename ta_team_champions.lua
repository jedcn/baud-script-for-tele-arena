-- ta_team_champions.lua -- `team-fight-champions`: a group clears elven champions
--
-- Run from a High Priest leading a group, in the room on the Elven Valley ring
-- where the champions stand. The group fights everything here, then chases down
-- each champion that fled, then comes back. It succeeds when it is back in this
-- room and no champion is left in it.
--
-- Champions leave a room only when close to death or when chasing one of our
-- characters, so a departure during a fight is always a flee. Leaving turns our
-- backs on the healthy ones, which then follow, so the room is finished first
-- and the flee directions wait in a queue.
--
-- Loaded by main.lua after ta_kill.lua's loop triggers, so a death has already
-- ended the kill loop by the time our trigger sees it. A separate chunk; the
-- seam runs through taPackage:
--
--   in    taPackage.kill.start / .stop, taPackage.character, taPackage.arenaState,
--         taPackage.killActive
--   out   taPackage.teamChampions.running / .stop (stop-all-scripts)
--
-- `team-fight-champions-in-loop` keeps going: after each room it walks on round
-- the ring, keeping its heading, until a room with a champion in it, and fights
-- there the same way. It runs until `team-fight-champions-in-loop-stop`.
--
-- `run` is a local on purpose: a reloadScript() cannot carry the poll timer over,
-- so a run should not survive one either.

taPackage.teamChampions = {}

local TAG = "[champions] "
local TARGET = "champion"
local POLL_MS = 3000                -- `group` is the only view of health and Ready
local ARRIVAL_SETTLE_MS = 1000      -- followers land a beat after the leader; a
                                    -- `kill` conferred sooner finds nothing nearby
local WALK_LOST_TICKS = 3           -- polls with no arrival before giving up
local HEAL_BELOW_PERCENT = 85
local HEAL_COOLDOWN_MS = 24000      -- the shortest gap between heals in the logs
                                    -- was 25s; asking sooner is only refused
local MAX_CHASE_ROOMS = 10          -- the longest chase in the logs was 8

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
-- With `run.travel` set, the run is a loop's leg between champion rooms: no
-- home yet, so moves are not recorded, and the first champion seen makes home.
local run = nil

-- When the last group heal landed, whoever cast it. Outside `run` so that a heal
-- typed by hand, or cast just before a run started, still counts.
local lastHealAt = nil

-- "three elven champions", "two elven champions, and an elven warrior", "an
-- elven champion". A plural with a count word we don't know is still at least two.
function taPackage.teamChampions.countChampions(contents)
    local total = 0
    for word, noun in contents:lower():gmatch("(%S+) elven (champions?)") do
        total = total + (noun == "champion" and 1 or COUNT_WORDS[word] or 2)
    end
    return total
end

-- Which way the ring continues. Straight on if we can, which also carries us
-- through the junction at the top of the spur; otherwise this is a corner, and
-- the only way on is the exit we did not come in by. Nil if that isn't one exit.
function taPackage.teamChampions.ringNext(exits, heading)
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
function taPackage.teamChampions.loopNext(exits, heading)
    if heading then
        local direction = taPackage.teamChampions.ringNext(exits, heading)
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

local function newRun(loop)
    return {
        phase = "fight",
        path = {},        -- moves out from the starting room
        flees = {},       -- directions champions left the starting room in
        kills = 0,
        abandoned = 0,
        champions = 0,    -- what the latest occupant line said
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
taPackage.teamChampions.stop = stop

function taPackage.teamChampions.running()
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

local function engage()
    if taPackage.killActive then return end
    run.engaged = true
    send("confer kill " .. TARGET)
    if not taPackage.kill.start(TARGET) then
        run.loop = nil
        finish("Could not start the kill loop.")
    end
end

local function move(direction)
    run.phase = "walk"
    run.pendingMove = direction
    run.walkTicks = 0
    send(direction)
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

-- The room we are in holds no champion, so what is next?
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
        finish(string.format("All champions dead: %d killed.", run.kills))
    end
end

-- Everyone is Ready: take the next step, along the ring or back home.
local function stepOnward(exits)
    if run.travel then
        local direction = taPackage.teamChampions.loopNext(exits, run.loop.heading)
        if not direction then
            run.loop = nil
            finish("Can't tell which way the ring goes from here; stopping the loop.")
            return
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
            direction = taPackage.teamChampions.ringNext(exits, run.chase)
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
    if run.travel then
        run.pendingMove = nil
        if count == 0 then
            muster()
            return
        end
        -- The first room with a champion becomes home, whatever the count:
        -- three is what stands there, and fewer is easier.
        run.travel = false
        echo(TAG .. "Fighting the champions here.")
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
    elseif count == 1 or isHome() then
        -- Found one, or home with company: home is where a fight belongs.
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
            abandonChase(count .. " champions here is too many at once.")
        end
        muster()
    end
end

function tick(thisRun)
    if run ~= thisRun then return end
    if run.phase == "fight" then
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
        -- game refuses it. The next polls wait for Ready again.
        send("cast kusamotumaru")
        return
    end
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

createAlias("^team-fight-champions$", function()
    if not canStart() then return end
    begin(newRun(nil))
    echo(TAG .. "Fighting the champions here.")
    markXp()
    scanRoom()
end, { type = "regex" })

-- Starts by fighting whatever is here; an empty room just sets it walking.
createAlias("^team-fight-champions-in-loop$", function()
    if not canStart() then return end
    begin(newRun({ heading = nil, kills = 0 }))
    echo(TAG .. "Looping round the ring until team-fight-champions-in-loop-stop.")
    markXp()
    scanRoom()
end, { type = "regex" })

createAlias("^stop-team-fight-champions$", stop, { type = "regex" })
createAlias("^team-fight-champions-in-loop-stop$", stop, { type = "regex" })

createTrigger("^There \\S+ (.+) here\\.$", function(matches)
    if not run then return end
    run.champions = taPackage.teamChampions.countChampions(matches[2])
end, { type = "regex" })

-- The end of every room. A room with players and no monster has no occupant line
-- at all, which is why the count is reset here rather than trusted to be fresh.
createTrigger("^There .+ on the floor\\.$", function()
    if not run then return end
    local count = run.champions
    run.champions = 0
    if run.phase == "walk" then
        arrive(count)
    elseif run.phase == "fight" then
        if count > 0 then engage() else roomClear() end
    end
end, { type = "regex" })

createTrigger("^The elven champion has just gone to the (\\w+)\\.$", function(matches)
    if not run or run.phase ~= "fight" then return end
    local direction = SHORT_DIRECTION[matches[2]]
    if not direction then return end
    if isHome() then
        table.insert(run.flees, direction)
    else
        run.chase = direction
        run.chaseFresh = true
    end
end, { type = "regex" })

-- While we stand waiting to move, an arrival has caught us: turn and fight. In a
-- fight at home, one that came back is one fewer to go looking for.
createTrigger("^An elven champion has just arrived from the (\\w+)\\.$", function(matches)
    if not run then return end
    if run.phase == "muster" then
        backToFighting()
        return
    end
    if run.phase ~= "fight" or not isHome() then return end
    local direction = SHORT_DIRECTION[matches[2]]
    for i, fled in ipairs(run.flees) do
        if fled == direction then
            table.remove(run.flees, i)
            return
        end
    end
end, { type = "regex" })

-- Any death ends every kill loop in the room, whoever else is left in it.
createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    if not run then return end
    if matches[2] == "elven champion" then run.kills = run.kills + 1 end
    if run.phase == "fight" then scanRoom() end
end, { type = "regex" })

-- Our target walked out: the kill loop has nothing to swing at and would sit
-- there still marked active, so clear it for the next scan to start a new one.
createTrigger("^Sorry, you don't see \"champion\" nearby\\.$", function()
    if not run or run.phase ~= "fight" then return end
    taPackage.kill.stop()
    scanRoom()
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

createTrigger("^Exits: (.+)\\.$", function(matches)
    if not run or not run.rows then return end
    local exits = {}
    for exit in matches[2]:gmatch("[^,%s]+") do table.insert(exits, exit) end
    readGroup(exits)
end, { type = "regex" })
