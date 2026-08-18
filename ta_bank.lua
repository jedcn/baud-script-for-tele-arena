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
-- So: on receiving gold, walk to the vaults, deposit everything carried, walk
-- back. The round trip is six moves and takes well under a minute, against a
-- ~25 minute farming cycle, so the receiver is back in the tavern long before
-- the next handover is due. That margin is the whole design -- if depositing
-- were slow, being away when the farmer arrives would trade one failure mode
-- for another.
--
-- Deposit everything rather than just what arrived: the point is to shed weight,
-- and whatever was already in hand weighs the same as the new gold. The amount
-- has to be read back from the game (`deposit` wants a number), which is why
-- there is an `i` step that parks for the reply.
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
    local amount = tonumber(matches[2]) or 0
    if amount > 0 then
        send("deposit " .. amount)
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
    echo("[bank] Deposited " .. matches[2] .. " gold.")
end, { type = "regex" })
