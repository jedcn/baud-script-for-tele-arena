-- ta_tavern.lua -- hang-around-in-tavern-and-deposit-gold
--
-- A standalone "idle in a tavern" mode, independent of the arena scripts. It
-- parks the character in a bar and keeps it fed and watered: buy a meal when
-- hungry, a drink when thirsty. Two things end it, both by leaving the game
-- with "x": HP falling below half (something is hurting us faster than we can
-- recover — e.g. we ran out of money and hunger/thirst is grinding us down),
-- or a purchase failing for lack of money (the direct signal for the same).
--
-- It also arms banking (ta_bank.lua), which is where the name's second half
-- comes from. The character sitting in the tavern is the one the gold farm
-- hands its takings to, so "idling here" and "deposit what arrives" are the
-- same job; keeping them as two switches meant banking was never once armed in
-- a real session. Stopping the mode disarms banking again, so the pair goes
-- down together.
--
-- Loaded by main.lua with dofile, where the section used to sit, so every
-- trigger and alias is registered in the same order as before. A separate
-- chunk; the seam runs through taPackage:
--
--   in    taPackage.startBanking / .stopBanking (ta_bank.lua, loaded later but
--         only called at run time), taPackage.currentRoom,
--         taPackage.arenaEmergencyExit (the shared can't-afford trigger)
--   out   taPackage.tavern.stop (stop-all-scripts), and the state, which keeps
--         its names because it survives reloadScript(): tavernMode,
--         tavernModeGen, tavernStartTime, tavernGoldReceived

taPackage.tavern = {}

local TAVERN_HP_FRACTION = 0.5        -- exit if current HP drops below this share of max
local TAVERN_STATUS_POLL_MS = 600000 -- low-frequency HP heartbeat (10 min); see scheduleTavernPoll

-- Session accounting. The whole point of parking a character here is the gold
-- the farm hands it, and until now a run said nothing about how that was going:
-- the only evidence was counting "[bank] Deposited ..." lines in the log after
-- the fact. So keep two numbers from the moment the mode is armed — when it
-- started, and how much gold has arrived since — and report them as a rate,
-- which is the figure that actually answers "is this round worth leaving up?".
--
-- Both live on taPackage rather than in locals so they survive reloadScript()
-- mid-run; a reload that reset the clock would silently inflate the rate.
local function tavernSummary()
    local elapsed = os.time() - (taPackage.tavernStartTime or os.time())
    if elapsed < 0 then elapsed = 0 end
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local uptime = hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m")
    local gold = taPackage.tavernGoldReceived or 0
    -- Under a minute there is no meaningful rate — dividing by a fraction of a
    -- minute turns the first handover into a fantasy figure ("49,320 gold/min").
    local rate = elapsed >= 60
        and string.format("%.1f", gold / (elapsed / 60)) .. " gold/min"
        or "rate n/a yet"
    return "up " .. uptime .. ", " .. taPackage.utils.formatWithCommas(gold) .. " gold received ("
        .. rate .. ")"
end

local function isTavernRoom(room)
    if not room then return false end
    local r = room:lower()
    return r:find("tavern") ~= nil or r:find("bar") ~= nil
end

-- Leave the game and stop the mode. Bumping the generation invalidates any
-- poll timer still in flight so it can't re-arm after we've quit.
local function tavernExitGame(reason)
    echo("[tavern] " .. reason .. " — leaving the game. Session: " .. tavernSummary() .. ".")
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    -- Disarm banking on the way out. We're about to be logged out, and a
    -- deposit trip that fires after that would walk a character who isn't
    -- there — or worse, resume mid-route on the next login.
    taPackage.stopBanking()
    send("x")
end

-- Hunger/thirst damage is NOT silent: the game prints "You're hungry." /
-- "You're thirsty." on every 1-HP tick, and the triggers below react to each by
-- buying food/drink. The real "we're being ground down" case — out of money — is
-- caught directly by the "You can't afford ..." trigger, which exits at once. So
-- this poll isn't the primary safety mechanism; it's just an occasional HP
-- heartbeat (10 min) to catch anything unforeseen. The Vitality trigger below
-- reads the fresh line and decides whether to bail.
local function scheduleTavernPoll()
    local gen = taPackage.tavernModeGen
    createTimer(TAVERN_STATUS_POLL_MS, function()
        if not taPackage.tavernMode or taPackage.tavernModeGen ~= gen then return end
        -- Ride the heartbeat for the check-in too, so an idle run says where it
        -- is every 10 minutes instead of only when gold happens to land.
        echo("[tavern] " .. os.date("%H:%M:%S") .. " — " .. tavernSummary() .. ".")
        send("st")
        scheduleTavernPoll()
    end, { repeating = false })
end

-- Stop tavern idle mode without leaving the game. Returns true if it was
-- running. Bumping the generation invalidates any poll timer in flight so it
-- can't re-arm. Shared by stop-hang-around-in-tavern-and-deposit-gold and
-- stop-all-scripts.
--
-- Banking goes down with it, including a deposit trip already in flight —
-- stopping the mode should leave nothing walking. Someone who armed banking on
-- its own with start-banking and then idled in a tavern loses it here too;
-- that's the cost of one switch for both, and start-banking re-arms it.
local function stopTavernMode()
    if not taPackage.tavernMode then return false end
    taPackage.tavernMode = false
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    taPackage.stopBanking()
    return true
end
taPackage.tavern.stop = stopTavernMode

createAlias("^hang-around-in-tavern-and-deposit-gold$", function()
    -- Judge the room from the name the last arrival brief left behind. Don't
    -- send a `look` first: send() is fire-and-forget, so its reply lands long
    -- after this function has returned, and a look's opening line is
    -- deliberately not treated as an arrival anyway (see
    -- handleRoomEntryUnlessLooking) -- it could never set currentRoom.
    local room = taPackage.currentRoom
    if not isTavernRoom(room) then
        echo("[tavern] Not in a tavern/bar (room: " .. (room or "unknown")
            .. "). Walk into one first, then run"
            .. " hang-around-in-tavern-and-deposit-gold.")
        return
    end
    taPackage.tavernMode = true
    taPackage.tavernModeGen = (taPackage.tavernModeGen or 0) + 1
    taPackage.tavernStartTime = os.time()
    taPackage.tavernGoldReceived = 0
    echo("[tavern] Hanging around in the " .. room
        .. ". Buying meals/drinks as needed; will leave (x) if HP drops below 50% or money runs out.")
    -- Arm banking too. ta_bank.lua's route home ends "ne" into the first town's
    -- tavern, so a deposit trip started from any other bar walks back to the
    -- wrong room -- but that is ta_bank's route to fix, and arming it here is
    -- what the alias name promises.
    taPackage.startBanking()
    send("st") -- prime HP tracking so the first poll isn't the first reading
    scheduleTavernPoll()
end, { type = "regex" })

createAlias("^stop-hang-around-in-tavern-and-deposit-gold$", function()
    -- Read the summary before stopping: stopTavernMode leaves the numbers
    -- alone, but the reading belongs to the run that just ended, so take it
    -- first and say it in the same breath as "stopped".
    local summary = tavernSummary()
    if stopTavernMode() then
        echo("[tavern] Stopped hanging around, banking disarmed (still in the game). Session: "
            .. summary .. ".")
    else
        echo("[tavern] Not currently hanging around.")
    end
end, { type = "regex" })

createTrigger("^You're hungry\\.$", function()
    if not taPackage.tavernMode then return end
    send("buy meal")
end, { type = "regex" })

createTrigger("^You're thirsty\\.$", function()
    if not taPackage.tavernMode then return end
    send("buy drink")
end, { type = "regex" })

-- Gold landed. ta_bank.lua has its own trigger on this line (it starts the
-- deposit trip); this one only keeps score, so it stays here with the rest of
-- the tavern session and counts every handover — including one that arrives
-- while we're already walking to the vaults, which ta_bank declines to bank but
-- which is money we were nonetheless given.
createTrigger("^(\\S+) just gave you (\\d+) gold coins\\.$", function(matches)
    if not taPackage.tavernMode then return end
    taPackage.tavernGoldReceived = (taPackage.tavernGoldReceived or 0)
        + (tonumber(matches[3]) or 0)
    echo("[tavern] +" .. matches[3] .. " gold from " .. matches[2] .. " — "
        .. tavernSummary() .. ".")
end, { type = "regex" })

-- A purchase we asked for was refused for lack of funds. In tavern mode the only
-- things we buy are meals and drinks ("You can't afford drink.", "... a meal.");
-- in an arena run it's healing ("You can't afford healing.") and potions
-- ("... a rowan potion.", "... a hyssop potion."). Either way an affordability
-- failure is ours and means we're broke: quit at once before hunger/thirst or
-- the next unhealed fight grinds the character down.
createTrigger("^You can't afford (.+)\\.$", function(matches)
    if taPackage.tavernMode then
        tavernExitGame("Out of money (can't afford " .. matches[2] .. ")")
    elseif taPackage.arenaState then
        taPackage.arenaEmergencyExit("Out of money (can't afford " .. matches[2] .. ")")
    end
end, { type = "regex" })

-- A fresh Vitality reading — from our poll, or any status check. If we've
-- dropped below half health while idling, leave the game.
createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
    if not taPackage.tavernMode then return end
    local current = tonumber(matches[2])
    local max = tonumber(matches[3])
    if current and max and max > 0 and current < max * TAVERN_HP_FRACTION then
        tavernExitGame("HP below 50% (" .. current .. "/" .. max .. ")")
    end
end, { type = "regex" })
