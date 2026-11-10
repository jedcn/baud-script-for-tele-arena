-- ta_guard.lua -- flee when we are hurt and no script is minding us
--
-- Every fighting script looks after its own HP: the arena flees at its
-- threshold, team-fight-elves heals the group. Nothing did when no script was
-- running. On 2026-11-09 Pelayo finished a navigate-live back into the Elven
-- Valley, nobody started the loop, and two elven champions took him from full
-- (1718) to dead in eight minutes while he sent nothing at all; Castor and
-- Pollux stood beside him taking hits too
-- (logs/session-pelayo-2026-11-09T09-48-20.log, 09:58-10:05).
--
-- So: every hit that lands while no script is running and leaves us under half
-- our max vitality starts a flee: we step back the way we came in, or, not
-- knowing it, out of the first exit `ex` lists. No heal first, by request: a
-- cast tires us and the step is refused until it wears off, which is time spent
-- standing in the room being hit. A refused step (tired, held in combat,
-- tripped) is tried again every 2s. An elf that chases us in hits us again, and
-- that hit starts the next flee, so we keep going until they stop following.
--
-- A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.allScripts (main.lua: what stop-all-scripts stops),
--         taPackage.character, taPackage.lastArrivalDir and the
--         taPackage.guard.onArrival call (ta_map.lua), taPackage.shiftPendingDir
--   out   taPackage.guard.onHit (main.lua's incoming-damage triggers),
--         taPackage.guard.onArrival, .fleeing / .stop (stop-all-scripts)
--
-- `flee` is a local on purpose: a reload ends a flee, as it ends every script.

taPackage.guard = {}

local TAG = "[guard] "
local FRACTION = 0.5        -- flee below half our max vitality
local RETRY_MS = 2000       -- the arena's and navigate-to's retry for a held move
local MAX_TRIES = 15        -- 30s of refusals, then leave it to whoever is watching

-- Running, but not in charge of what the character does: the follow XP poll
-- only sends `status`, and TA_INIT_CMD only waits for the next login.
local NOT_IN_CHARGE = { ["follow XP poll"] = true, ["TA_INIT_CMD"] = true, ["guard"] = true }

local REVERSE = {
    n = "s", s = "n", e = "w", w = "e",
    ne = "sw", sw = "ne", nw = "se", se = "nw",
    u = "d", d = "u",
}

-- nil, or the flee in progress:
--   dir       the way we are trying to leave; nil while `ex` is out
--   tries     steps sent so far
--   stepping  a step is out, and its arrival or refusal hasn't come back yet
local flee = nil

function taPackage.guard.threshold()
    local _, max = taPackage.character.getVitality()
    return max and math.floor(max * FRACTION)
end

local function scriptInCharge()
    for _, s in ipairs(taPackage.allScripts()) do
        if s.running and not NOT_IN_CHARGE[s.name] then return s.name end
    end
    return nil
end

local function step()
    if not flee then return end
    if flee.tries >= MAX_TRIES then
        echo(TAG .. "Still here after " .. MAX_TRIES .. " tries. Giving up; get out by hand.")
        flee = nil
        return
    end
    flee.tries = flee.tries + 1
    if flee.dir then
        flee.stepping = true
        -- Through the direction alias, so the move is queued for `where`
        -- and the arrival reaches onArrival.
        if runCommand then runCommand(flee.dir) else send(flee.dir) end
    else
        send("ex")
    end
end

local function retryLater()
    local thisFlee = flee
    createTimer(RETRY_MS, function()
        if flee == thisFlee then step() end
    end, { repeating = false })
end

function taPackage.guard.onHit()
    if flee then return end
    local hp = taPackage.character.getVitality()
    local threshold = taPackage.guard.threshold()
    -- Unknown vitality is not evidence of being hurt.
    if not hp or not threshold or hp >= threshold then return end
    if scriptInCharge() then return end
    flee = { dir = REVERSE[taPackage.lastArrivalDir or ""], tries = 0 }
    echo(TAG .. "Down to " .. hp .. " HP (under " .. threshold
        .. ") and no script is running. Getting out.")
    step()
end

function taPackage.guard.onArrival()
    if not flee or not flee.stepping then return end
    echo(TAG .. "Out, went " .. flee.dir .. ".")
    flee = nil
end

function taPackage.guard.fleeing()
    return flee ~= nil
end

function taPackage.guard.stop()
    flee = nil
end

for _, refusal in ipairs({
    "^Sorry, you'll have to rest a while before you can move\\.$",
    "^You cannot leave in the heat of battle!$",
    "^In your haste, you trip and fall!$",
}) do
    createTrigger(refusal, function(matches)
        if not flee or not flee.stepping then return end
        flee.stepping = false
        -- The mapper takes the other two off the arrival queue. Nothing
        -- does this one, and its step will never arrive.
        if matches[1]:match("^You cannot leave") then taPackage.shiftPendingDir() end
        retryLater()
    end, { type = "regex" })
end

-- The way we came in isn't there (a one-way exit, or a direction left over
-- from before a relog). Ask for the exits instead.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    if not flee or not flee.stepping then return end
    flee.stepping = false
    flee.dir = nil
    step()
end, { type = "regex" })

createTrigger("^Exits: (.+)\\.$", function(matches)
    if not flee or flee.dir then return end
    flee.dir = matches[2]:match("^([^,]+)")
    step()
end, { type = "regex" })
