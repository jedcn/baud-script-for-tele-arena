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
--   checking  sent `l sub` after the hit, to see what it left him at. Still
--             only lightly wounded: swing again. Anything worse: leave.
--   leaving   sent the move out. The game refuses it for a while after a
--             swing ("heat of battle", "rest a while"): 27 to 43 seconds in the
--             log, never the same twice, so retry every few seconds instead of
--             guessing a figure.
--   waiting   one room away, for WAIT_MS, then `looking` again from there:
--             "is to the <dir>!" says the way back.
--   returning sent the move back; arriving starts `looking` again.
--
-- The way back is asked, never worked out by reversing the way out. On
-- 2026-11-15 the subchief fled into a room you leave by ne but get back to by
-- s, so a reversed sw would have walked into a wall.
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

-- What he can be left at and still take another swing. Hits run 28-63, and in
-- the 2026-11-15 log 84 damage in all left him "sorely wounded" and he fled,
-- while 63 and 88 left him "moderately". Lightly wounded (one 28) plus the
-- worst hit is 91, so even this risks a flee now and then; "wounded" (40-55)
-- plus a big hit would be past 84 most times.
local SWING_AGAIN = { ["lightly wounded"] = true }

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

-- Step out of his room by the first exit `ex` listed.
local function leave()
    local dir = S.exits[1]
    if not dir then
        stop()
        echo(TAG .. "No exit to leave by, so stopping. " .. summary() .. ".")
        return
    end
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
--
-- "...is lightly wounded." / "...to be moderately wounded." / "...to be
-- wounded." -- the word before "wounded", unless that word is just the verb.
local function condition(line)
    if line:find("physical health%.$") then return "in good physical health" end
    local word = line:match("(%a+) wounded%.$")
    if not word or word == "be" or word == "is" then return "wounded" end
    return word .. " wounded"
end

-- After a hit: say what it left him at, then go -- or swing again if that
-- was only a scratch.
local function reportHitAndLeave(state)
    local again = SWING_AGAIN[state]
    echo(TAG .. "Hit " .. S.hits .. " for " .. S.lastHit .. ", leaving him "
        .. state .. (again and "; swinging again" or "") .. ". " .. summary() .. ".")
    if again then swing() else leave() end
end

-- Both anchored to the whole line: baud hands a callback only the text its
-- regex matched, so an unanchored "wounded\\.$" sees "wounded." and never the
-- "lightly" in front of it (2026-11-16, logs/session-pelayo-2026-11-16T03-42-22.log).
createTrigger("^.*physical health\\.$", function(m)
    if S.state == "looking" then
        swing()
    elseif S.state == "checking" then
        reportHitAndLeave(condition(m[1]))
    end
end, { type = "regex" })

createTrigger("^.*wounded\\.$", function(m)
    if S.state == "looking" then
        echo(TAG .. "Not healed yet (" .. condition(m[1]) .. "); giving him longer.")
        leave()
    elseif S.state == "checking" then
        reportHitAndLeave(condition(m[1]))
    end
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
    elseif S.state == "checking" then
        -- Fled (or died) from the hit. Leave anyway; the next look finds him.
        reportHitAndLeave("gone from the room")
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
    S.lastHit = m[2]
    S.state = "checking"
    send("l " .. TARGET)
end, { type = "regex" })

local function swingAgain()
    if S.state ~= "swinging" then return end
    later(RETRY_MS, swing)
end
createTrigger("^Your attack missed!$", swingAgain, { type = "regex" })
createTrigger("^The orc subchief dodged your attack!$", swingAgain, { type = "regex" })
-- A swing too soon after the last one is refused, not missed; without this
-- the loop sat in the room doing nothing (2026-11-16, 03:5x).
createTrigger("^You are still physically exhausted from your previous activities!$",
    swingAgain, { type = "regex" })

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
        later(WAIT_MS, look)
    elseif S.state == "returning" then
        look()
    end
end, { type = "regex" })
