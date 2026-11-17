-- ta_subchief.lua -- hit-subchief-and-let-him-heal
--
-- XP for no risk, worked out by hand with Pelayo on 2026-11-15
-- (logs/session-pelayo-2026-11-15T20-13-02.log). The orc subchief can't hurt
-- a High Priest in chain mail: 13 minutes in the room with him and every swing
-- he took glanced off or missed. XP follows damage (~285 XP a point here), and
-- he heals back to "good physical health" within about 15-30 seconds of our
-- leaving the room. So: hit him, step out, let him heal, come back, again.
--
-- Hit until he is past lightly wounded, and no further, because too much
-- sends him running. Two hits (40 + 44) left him "sorely wounded" and he fled;
-- no single hit (28 to 63) ever did. A second swing only follows a hit that
-- left him lightly wounded or wounded (SWING_AGAIN). A fled subchief is still findable --
-- `l sub` from the next room answers "The orc subchief is to the south!" --
-- but chasing him is the chaos we are avoiding.
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
--   in    taPackage.exitGamePending (ta_leave_game.lua), taPackage.inGroup
--         (main.lua), taPackage.utils.sendNtfy
--   out   taPackage.subchief.stop / .running (stop-all-scripts, the guard)

taPackage.subchief = {}

local TAG = "[subchief] "
local TARGET = "sub"
local WAIT_MS = 20000       -- next door while he heals; healthy after 14-31s on 11-15, and
                            -- 30s was too short only once in 100 rounds on 11-17
local RETRY_MS = 3000       -- between refused moves and between missed swings

-- What he can be left at and still take another swing. Hits run 28-63, and in
-- the 2026-11-15 log 84 damage in all left him "sorely wounded" and he fled,
-- while 63 and 88 left him "moderately". Lightly wounded (one 28) plus the
-- worst hit is 91, so even this risks a flee now and then; "wounded" (40-55)
-- plus a big hit would be past 84 most times.
--
-- That fear didn't hold up. Over 100 rounds on 2026-11-17 the 24 two-hit
-- rounds (67-86 damage) sent him running none of the times, and earned ~50%
-- more XP than a one-hit round in the same ~63s. So "wounded" gets a second
-- swing too. Moderately wounded or worse still means leave.
local SWING_AGAIN = { ["lightly wounded"] = true, ["wounded"] = true }

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

-- Every step change bumps the generation, so a timer armed in one step dies if
-- the loop has moved on by the time it fires. Without that, a 30s wait timer
-- left over from an earlier round fired while we were trying to leave his
-- room, sent a look, and started a second chain of moves on top of the first;
-- the extra `e` hit a wall and stopped the loop
-- (logs/session-pelayo-2026-11-17T01-25-47.log, 02:12:34).
local function setState(state)
    S.state = state
    S.gen = S.gen + 1
end

-- Run fn after ms unless the loop has changed step (or stopped) since, or the
-- guard is taking us out of the game.
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
    setState("looking")
    send("ex")
    send("l " .. TARGET)
end

local function move(dir, state)
    setState(state)
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
    setState("swinging")
    send("a " .. TARGET)
end

createAlias("^hit-subchief-and-let-him-heal$", function()
    stop()
    S.gen = S.gen + 1
    S.exits = {}
    S.hits, S.damage, S.startedAt = 0, 0, os.time()
    echo(TAG .. "Hitting the subchief until he is moderately wounded, then waiting " .. (WAIT_MS / 1000)
        .. "s next door while he heals. stop-hit-subchief to stop.")
    S.roundHits, S.roundDamage = 0, 0
    S.xpStart, S.xpLast, S.xpStartMs = nil, nil, nil
    S.awaitingSt = true
    send("st") -- the baseline the first round's XP is measured from
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
    if again then
        swing()
    else
        -- A status at every departure puts an Experience reading in the log
        -- per round, so the XP each round earned is one subtraction away.
        S.awaitingSt = true
        send("st")
        leave()
    end
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
    S.roundHits = S.roundHits + 1
    S.roundDamage = S.roundDamage + tonumber(m[2])
    S.lastHit = m[2]
    setState("checking")
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
        setState("waiting")
        later(WAIT_MS, look)
    elseif S.state == "returning" then
        look()
    end
end, { type = "regex" })

-- The `st` we sent: the first sets the baseline, each later one closes a
-- round. Printing XP per round and per hour here means a run is measured as
-- it goes, with no `st` typed by hand and no log to wait for. Only our own
-- `st` counts, so one typed mid-round doesn't split a round in two.
local function commas(n) return taPackage.utils.formatWithCommas(n) end

createTrigger("^Experience:\\s+(\\d+)$", function(m)
    if not running() or not S.awaitingSt then return end
    S.awaitingSt = false
    local xp = tonumber(m[2])
    if not S.xpStart then
        S.xpStart, S.xpLast, S.xpStartMs = xp, xp, nowMs()
        return
    end
    local round, total = xp - S.xpLast, xp - S.xpStart
    S.xpLast = xp
    local ms = nowMs() - S.xpStartMs
    -- Under a minute a rate is one round scaled up 60-fold; not worth printing.
    local rate = ms >= 60000
        and commas(math.floor(total / (ms / 3600000))) .. " XP/hr"
        or "rate after a minute"
    echo(TAG .. "Round: +" .. commas(round) .. " XP from " .. S.roundHits .. " hit"
        .. (S.roundHits == 1 and "" or "s") .. " (" .. S.roundDamage .. " damage). Total +"
        .. commas(total) .. " XP in " .. math.floor(ms / 60000) .. "m, " .. rate .. ".")
    S.roundHits, S.roundDamage = 0, 0
end, { type = "regex" })

-- Thirst. Solo, nothing else drinks for us -- the arena's trigger only does in
-- a group -- and thirst costs a point of HP a tick, too slowly for the guard to
-- notice for a long time. So drink from the waterskin. In a group the arena's
-- trigger already sends it, and two drinks would waste one.
createTrigger("^You're thirsty\\.$", function()
    if not running() or taPackage.inGroup() then return end
    S.drinkPending = true
    send("drink water")
end, { type = "regex" })

createTrigger("^The water quenches your thirst\\.$", function()
    S.drinkPending = false
end, { type = "regex" })

-- Nothing to drink from: "The waterskin is empty!" (seen 2026-11-16, with a
-- waterskin(1) still in the pack) or, with no waterskin at all, "Sorry, but
-- you don't seem to have one." Stop rather than keep looping thirsty, and say
-- so where it'll be seen.
local function outOfWater()
    if not S.drinkPending then return end
    S.drinkPending = false
    if not running() then return end
    stop()
    echo(TAG .. "Thirsty with no water, so stopping. " .. summary() .. ".")
    taPackage.utils.sendNtfy("Out of water",
        (taPackage.character.getName() or "The character")
        .. " is thirsty with no water; hit-subchief-and-let-him-heal stopped.")
end
createTrigger("^The waterskin is empty!$", outOfWater, { type = "regex" })
createTrigger("^Sorry, but you don't seem to have one\\.$", outOfWater, { type = "regex" })
