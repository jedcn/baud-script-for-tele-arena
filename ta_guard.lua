-- ta_guard.lua -- leave the game when we are hurt and no script is minding us
--
-- Every fighting script looks after its own HP: the arena flees at its
-- threshold, team-fight-elves heals the group. Nothing did when no script was
-- running. On 2026-11-09 Pelayo finished a navigate-live back into the Elven
-- Valley, nobody started the loop, and two elven champions took him from full
-- (1718) to dead in eight minutes while he sent nothing at all; Castor and
-- Pollux stood beside him taking hits too
-- (logs/session-pelayo-2026-11-09T09-48-20.log, 09:58-10:05).
--
-- So: a hit that lands while no script is running and leaves us under half our
-- max vitality takes us out of the game, with the same `x`-until-it-takes that
-- every other emergency exit uses (taPackage.exitGameWithRetry). Leaving the
-- game, not the room, by request: a monster can follow us out of a room, but
-- not out of the game.
--
-- A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.allScripts (main.lua: what stop-all-scripts stops),
--         taPackage.character, taPackage.exitGameWithRetry / .exitGamePending
--         (ta_leave_game.lua)
--   out   taPackage.guard.onHit (main.lua's incoming-damage triggers)

taPackage.guard = {}

local TAG = "[guard] "
local FRACTION = 0.5        -- leave below half our max vitality

-- Running, but not in charge of what the character does: the follow XP poll
-- only sends `status`, and TA_INIT_CMD only waits for the next login.
local NOT_IN_CHARGE = { ["follow XP poll"] = true, ["TA_INIT_CMD"] = true }

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

function taPackage.guard.onHit()
    -- Already on the way out; the retry loop is doing the work.
    if taPackage.exitGamePending then return end
    local hp = taPackage.character.getVitality()
    local threshold = taPackage.guard.threshold()
    -- Unknown vitality is not evidence of being hurt.
    if not hp or not threshold or hp >= threshold then return end
    if scriptInCharge() then return end
    echo(TAG .. "Down to " .. hp .. " HP (under " .. threshold
        .. ") and no script is running. Leaving the game.")
    taPackage.exitGameWithRetry()
end
