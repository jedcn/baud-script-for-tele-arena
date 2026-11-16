-- ta_subchief.lua -- hit-subchief-once-and-let-him-heal
--
-- XP for no risk, worked out by hand with Pelayo on 2026-11-15
-- (logs/session-pelayo-2026-11-15T20-13-02.log). The orc subchief can't hurt
-- a High Priest in chain mail: 13 minutes in the room with him and every swing
-- he took glanced off or missed. XP follows damage (~285 XP a point here), and
-- he heals back to "good physical health" within about 15-30 seconds of our
-- leaving the room. So: hit him once, step out, let him heal, come back, again.
--
-- Once, because twice can send him running. Two hits (40 + 44) left him
-- "sorely wounded" and he fled; no single hit (28 to 63) ever did. A fled
-- subchief is still findable -- `l sub` from the next room answers "The orc
-- subchief is to the south!" -- but chasing him is the chaos we are avoiding.
--
-- The cycle, one state at a time:
--
--   looking   sent `ex` and `l sub`; his health sentence decides. Healthy:
--             swing. Wounded: step out and wait some more. "is to the <dir>!"
--             means he moved next door, so walk there and look again.
--   swinging  sent `a sub`. A hit ends the swinging; a miss or a dodge did no
--             damage, so swing again.
--   leaving   sent the move out. The game refuses it for a while after a
--             swing ("heat of battle", "rest a while"): 27 to 43 seconds in the
--             log, never the same twice, so retry every few seconds instead of
--             guessing a figure.
--   waiting   one room away, for WAIT_MS, then the reverse move back.
--   returning sent the move back; arriving starts `looking` again.
--
-- HP is the guard's job (ta_guard.lua): this script is listed there as not in
-- charge of HP, so a hit that leaves us under half still takes us out of the
-- game, and the loop stops when it sees the exit pending.
--
-- A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.exitGamePending (ta_leave_game.lua)
--   out   taPackage.subchief.stop / .running (stop-all-scripts, the guard)

taPackage.subchief = {}

local TAG = "[subchief] "
local TARGET = "sub"
local WAIT_MS = 30000       -- next door while he heals; he was healthy after 14-31s
local RETRY_MS = 3000       -- between refused moves and between missed swings

local REVERSE = {
    n = "s", s = "n", e = "w", w = "e",
    ne = "sw", sw = "ne", nw = "se", se = "nw",
    u = "d", d = "u",
}

-- "The orc subchief is to the south!" names the way in full.
local ABBREV = {
    north = "n", south = "s", east = "e", west = "w",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw",
}

-- Reset on every load: a reload ends this loop like every other one.
local S = { state = nil, gen = 0 }

local function running() return S.state ~= nil end
taPackage.subchief.running = running

local function stop()
    if not running() then return false end
    S.state = nil
    S.gen = S.gen + 1
    return true
end
taPackage.subchief.stop = stop

local function summary()
    local minutes = math.floor((os.time() - S.startedAt) / 60)
    return S.hits .. " hits, " .. S.damage .. " damage in " .. minutes .. "m"
end

-- Run fn after ms unless the loop was stopped (or restarted) in the meantime,
-- or the guard is taking us out of the game.
local function later(ms, fn)
    local gen = S.gen
    createTimer(ms, function()
        if S.gen ~= gen or not running() then return end
        if taPackage.exitGamePending then
            stop()
            echo(TAG .. "Leaving the game, so stopping. " .. summary() .. ".")
            return
        end
        fn()
    end, { repeating = false })
end

local function look()
    S.state = "looking"
    send("ex")
    send("l " .. TARGET)
end

local function move(dir, state)
    S.state = state
    S.moveDir = dir
    send(dir)
end

-- Step out of his room. Back the way we came when we know it, since that exit
-- is proven walkable; otherwise the first exit `ex` listed.
local function leave()
    local dir = (S.cameFrom and REVERSE[S.cameFrom]) or S.exits[1]
    if not dir then
        stop()
        echo(TAG .. "No exit to leave by, so stopping. " .. summary() .. ".")
        return
    end
    S.leftBy = dir
    move(dir, "leaving")
end

local function swing()
    S.state = "swinging"
    send("a " .. TARGET)
end

createAlias("^hit-subchief-once-and-let-him-heal$", function()
    stop()
    S.gen = S.gen + 1
    S.exits = {}
    S.cameFrom = nil
    S.hits, S.damage, S.startedAt = 0, 0, os.time()
    echo(TAG .. "Hitting the subchief once, then waiting " .. (WAIT_MS / 1000)
        .. "s next door while he heals. stop-hit-subchief to stop.")
    look()
end, { type = "regex" })

createAlias("^stop-hit-subchief$", function()
    if stop() then
        echo(TAG .. "Stopped. " .. summary() .. ".")
    else
        echo(TAG .. "Not running.")
    end
end, { type = "regex" })

createTrigger("^Exits: (.+)\\.$", function(m)
    if S.state ~= "looking" then return end
    S.exits = {}
    for dir in m[2]:gmatch("[^,%s]+") do S.exits[#S.exits + 1] = dir end
end, { type = "regex" })

-- His health sentence. The BBS wraps the look at 78 columns, so the sentence
-- usually arrives split ("...seems" / "to be in good physical health."); both
-- halves we test for are on its last line.
createTrigger("physical health\\.$", function()
    if S.state ~= "looking" then return end
    swing()
end, { type = "regex" })

createTrigger("wounded\\.$", function()
    if S.state ~= "looking" then return end
    echo(TAG .. "Not healed yet; giving him longer.")
    leave()
end, { type = "regex" })

-- Looked from a room he isn't in, and he is next door.
createTrigger("^The orc subchief is to the (\\w+)!$", function(m)
    if S.state ~= "looking" then return end
    local dir = ABBREV[m[2]]
    if not dir then
        stop()
        echo(TAG .. "He is to the " .. m[2] .. ", which I can't walk, so stopping. "
            .. summary() .. ".")
        return
    end
    move(dir, "returning")
end, { type = "regex" })

createTrigger("^Sorry, you don't see \"" .. TARGET .. "\" nearby\\.$", function()
    if S.state == "swinging" then
        -- He walked off between the look and the swing; find him again.
        look()
    elseif S.state == "looking" then
        stop()
        echo(TAG .. "Can't find the subchief here or next door, so stopping. "
            .. summary() .. ".")
    end
end, { type = "regex" })

createTrigger("^Your attack hit the orc subchief for (\\d+) damage!$", function(m)
    if S.state ~= "swinging" then return end
    S.hits = S.hits + 1
    S.damage = S.damage + tonumber(m[2])
    echo(TAG .. "Hit " .. S.hits .. " for " .. m[2] .. ". " .. summary() .. ".")
    leave()
end, { type = "regex" })

local function swingAgain()
    if S.state ~= "swinging" then return end
    later(RETRY_MS, swing)
end
createTrigger("^Your attack missed!$", swingAgain, { type = "regex" })
createTrigger("^The orc subchief dodged your attack!$", swingAgain, { type = "regex" })

local function retryMove()
    if S.state ~= "leaving" and S.state ~= "returning" then return end
    local dir, state = S.moveDir, S.state
    later(RETRY_MS, function() move(dir, state) end)
end
createTrigger("^You cannot leave in the heat of battle!$", retryMove, { type = "regex" })
createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", retryMove, { type = "regex" })

createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    if S.state ~= "leaving" and S.state ~= "returning" then return end
    stop()
    echo(TAG .. "No exit " .. S.moveDir .. " here, so stopping. " .. summary() .. ".")
end, { type = "regex" })

createTrigger("^You're in ", function()
    if S.state == "leaving" then
        S.state = "waiting"
        later(WAIT_MS, function() move(REVERSE[S.leftBy], "returning") end)
    elseif S.state == "returning" then
        S.cameFrom = S.moveDir
        look()
    end
end, { type = "regex" })
