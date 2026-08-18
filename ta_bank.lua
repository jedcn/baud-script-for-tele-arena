--
-- Banking: the receiving character walks its takings to the vaults.
--
-- Loaded by main.lua with dofile, after ta_create.lua, whose paced walker it
-- borrows. The seam, through taPackage:
--
--   in    taPackage.startPacedWalk, taPackage.createWalk (ta_create.lua)
--   out   taPackage.banking, taPackage.stopBanking, taPackage.bankingRunning
--
-- =========================================================================
-- Deposit what the farm hands over
-- =========================================================================
--
-- Gold has weight, and a character that only ever receives it eventually cannot
-- receive any more. That is not a theory: overnight on 2026-08-16 Kerhak took 13
-- gifts totalling 10,617 gold, reached 1323/1450 encumbrance, and the next
-- handover was refused outright --
--
--     > give kerhak 822 gold
--     Sorry, Kerhak can't carry that much more gold.
--
-- -- which stopped the farm dead with 822 gold stranded in a character that was
-- about to be thrown away (logs/session-garbageman-2026-08-16T02-29-07.log,
-- line 32560). Seven cycles had run cleanly before that; the eighth failed for
-- want of somewhere to put the money.
--
-- So: on receiving gold, walk to the vaults, deposit it, walk back. The round
-- trip is six moves and takes well under a minute, against a ~25 minute farming
-- cycle, so the receiver is back in the tavern long before the next handover is
-- due. That margin is the whole design -- if depositing were slow, being away
-- when the farmer arrives would trade one failure mode for another.
--
-- Deposit only what was handed over, and never the whole purse. The receiver is
-- also running tavern mode, which buys its own meals and drinks -- and a
-- purchase it can't afford makes it leave the game at once (the "You can't
-- afford" trigger in main.lua). Depositing everything carried is what emptied
-- the character that has to keep paying to sit there: the next "You're
-- thirsty." bought nothing, and the mode quit. Shedding the farm's weight was
-- ending the idle it exists to sustain.
--
-- Two guards, because they answer different questions.
--
-- What we owe the vaults: handovers are tallied in bankPending, and that is the
-- most we will ever deposit. Money the character had before the farm started
-- giving is its own and stays in its pocket. The confirmation line is what
-- draws the tally down, so an amount that didn't land is retried next trip.
--
-- What we must keep: BANK_KEEP stays in hand no matter what the tally says. It
-- covers the case the tally can't see -- a float handed over by hand is a
-- "just gave you N gold coins." like any other, so the tally counts the seed
-- money as takings and would bank it. The floor is what actually makes the
-- promise "it can eat all night"; the tally only stops it banking more than the
-- farm gave.
--
-- Sizing: a drink is 1 crown and a meal 2 (1809 drinks and 280 meals across the
-- logs, no other price ever seen), so 1000 kept is thousands of servings --
-- vastly more than an overnight run needs, and still a rounding error against
-- the ~825 that arrives every ~25 minutes.
local BANK_KEEP = 1000

-- `deposit` wants a number and the tally can outrun the purse (meals and drinks
-- are bought out of the same pocket the gifts land in), so the amount has to be
-- read back from the game -- which is what the `i` step parks for.
local BANK_STEPS = {
    "sw",              -- north plaza
    "n",               -- guild hall
    "d",               -- town vaults
    { cmd = "i", await = "bank-gold" },
    "u",               -- guild hall
    "s",               -- north plaza
    "ne",              -- tavern
}

local function stopBanking()
    taPackage.banking = false
    taPackage.bankPending = 0
    if taPackage.createWalk and taPackage.createWalk.label == "bank" then
        taPackage.stopPacedWalk()
    end
end
taPackage.stopBanking = stopBanking

function taPackage.bankingRunning()
    return taPackage.banking == true
end

-- Arm it. A function rather than only an alias body because
-- hang-around-in-tavern-and-deposit-gold arms banking as part of starting:
-- idling in the tavern is exactly the situation gold arrives in, and the two
-- being separate switches is why this went eight months unused.
local function startBanking()
    taPackage.banking = true
    taPackage.bankPending = 0
    -- echo, not cecho: cecho never reaches the session log, and "was banking
    -- even armed?" is the first question asked of a run that filled up anyway.
    echo("[bank] Banking armed — will deposit at the vaults whenever gold arrives."
        .. " Type stop-banking to halt.")
end
taPackage.startBanking = startBanking

createAlias("^start-banking$", startBanking, { type = "regex" })

createAlias("^stop-banking$", function()
    stopBanking()
    echo("[bank] Stopped.")
end, { type = "regex" })

-- Somebody handed us gold. Not gated on who: the farm is the only thing that
-- does this today, but a deposit is the right answer to gold from any source.
--
-- Guarded against starting a second trip while one is in flight. Two handovers
-- in quick succession would otherwise restart the walk from step 1 halfway to
-- the vaults, and the second trip would begin from the wrong room.
createTrigger("^(\\S+) just gave you (\\d+) gold coins\\.$", function(matches)
    if not taPackage.banking then return end
    taPackage.bankPending = (taPackage.bankPending or 0) + (tonumber(matches[3]) or 0)
    if taPackage.createWalk then
        echo("[bank] Received " .. matches[3] .. " gold from " .. matches[2]
            .. " while already out — it will go in on the next trip.")
        return
    end
    echo("[bank] " .. matches[2] .. " handed over " .. matches[3]
        .. " gold — taking it to the vaults.")
    taPackage.startPacedWalk(BANK_STEPS, "bank", "Deposited — back in the tavern.")
end, { type = "regex" })

-- The inventory reply the vaults trip parks on. Its own token, because
-- ta_create.lua's walk parks on "gold"/"zero-gold" and each file answers only
-- the tokens it uses.
createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
    local walk = taPackage.createWalk
    if not (walk and walk.awaiting == "bank-gold") then return end
    walk.awaiting = nil
    local carried = tonumber(matches[2]) or 0
    local pending = taPackage.bankPending or 0
    local amount = math.min(pending, math.max(carried - BANK_KEEP, 0))
    if amount > 0 then
        if amount < pending then
            echo("[bank] Handovers total " .. pending .. " gold, carrying "
                .. carried .. " — depositing " .. amount .. " and keeping "
                .. (carried - amount) .. " for meals and drinks.")
        end
        send("deposit " .. amount)
    elseif pending > 0 then
        echo("[bank] Carrying " .. carried .. " gold, at or under the "
            .. BANK_KEEP .. " kept for meals and drinks — nothing to deposit.")
    else
        echo("[bank] Nothing to deposit.")
    end
    taPackage.resumePacedWalk()
end, { type = "regex" })

-- Confirmation, purely so the log says the money actually landed. A deposit
-- that silently failed would look exactly like one that worked, and the failure
-- only shows up much later as a refused handover.
createTrigger("^You deposited (\\d+) gold in your account\\.$", function(matches)
    if not taPackage.banking then return end
    local amount = tonumber(matches[2]) or 0
    -- Draw the tally down on the confirmation, not when the command is sent:
    -- gold that never landed stays owed and goes in on the next trip.
    taPackage.bankPending = math.max((taPackage.bankPending or 0) - amount, 0)
    echo("[bank] Deposited " .. matches[2] .. " gold.")
end, { type = "regex" })
