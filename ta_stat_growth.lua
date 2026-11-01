-- ta_stat_growth.lua -- how the six attributes move when a character trains
-- or donates gold at a temple
--
-- Both work the same way. The game's reply starts a record: the class and
-- attributes we hold right then are the "before". We ask for a fresh sheet,
-- and when its last attribute line (Charisma) arrives the "after" is complete
-- and the row is filed. Every event gets a row, even one where no stat moved,
-- so the rows answer "how often does a stat rise".
--
--   trainings  The guild hall's success line. The hall refuses a potion-
--              tainted character, so "before" is base stats. `buy promotion`
--              answers with the same line, so promotions are filed too;
--              class_before and class_after tell them apart.
--   donations  "The priests gladly accept your donation." The reply is the
--              same whatever the donation did (13 donations on 2026-11-01
--              all read alike), and it names no amount, so the amount is
--              read off the command as it goes out.
--
-- Loaded by main.lua with dofile, after the attribute triggers: its Charisma
-- trigger must run after main.lua's has stored the new value.
--
--   in    taPackage.character (the sheet), taPackage.db.recordTraining and
--         taPackage.db.recordDonation
--   out   taPackage.statGrowthPending and taPackage.donationAmount (survive
--         reloadScript(), like the rest of taPackage)

local function readAttributes()
    local c = taPackage.character
    return {
        intellect = c.getIntellect(), knowledge = c.getKnowledge(),
        physique = c.getPhysique(), stamina = c.getStamina(),
        agility = c.getAgility(), charisma = c.getCharisma(),
    }
end

-- Start a record and ask for the sheet that finishes it. A second event
-- before that sheet arrives replaces the first, which is then never filed:
-- the sheet can't say which of the two moved what.
local function startRecord(record)
    record.character = taPackage.character.getName()
    record.before = readAttributes()
    taPackage.statGrowthPending = record
    send("st")
end

-- Not gated on an arena run: a hand-typed `buy training` counts the same.
createTrigger("^After a rigorous mental and physical training session, you managed to blend$", function()
    startRecord({ kind = "training", class_before = taPackage.character.getClass() })
end, { type = "regex" })

-- `donate 100 gold` or `donate 100 g`. Not the temple help's `d 100 g`: the
-- game takes that `d` for drop and answers "Sorry, littering is not permitted
-- here." (session-tojolias-2026-11-01T11-10-52.log), so it gives nothing --
-- and the amount it left here was once filed against the next real donation.
local function noteDonationAmount(matches)
    taPackage.donationAmount = tonumber(matches[2])
end
createOutboundTrigger("^donate (\\d+) gold$", noteDonationAmount, { type = "regex" })
createOutboundTrigger("^donate (\\d+) g$", noteDonationAmount, { type = "regex" })

-- The priests take exactly what was offered (twelve donations on 2026-11-01
-- came to 1,200 and carried gold fell 2,103 -> 903), so take it off the
-- tracked gold here, as the tavern and temple triggers in main.lua do for
-- their fees, rather than leave it stale until the next `i`.
createTrigger("^The priests gladly accept your donation\\.$", function()
    local amount = taPackage.donationAmount
    taPackage.donationAmount = nil
    if amount then
        taPackage.character.setGold((taPackage.character.getGold() or 0) - amount)
    end
    startRecord({ kind = "donation", amount = amount, pleased = 0 })
end, { type = "regex" })

-- The game's word that a donation worked. It comes after the priests' reply
-- and before the sheet we asked for (session-tojolias-2026-11-01T11-52-31.log,
-- the 12th donation of that session, Intellect 15 -> 16).
createTrigger("^The Gods seem pleased by your donation\\.\\.\\.$", function()
    local pending = taPackage.statGrowthPending
    if pending and pending.kind == "donation" then pending.pleased = 1 end
end, { type = "regex" })

-- Charisma is the last attribute on the sheet, and the sheet answers the `st`
-- sent above; the game replies in order, so any sheet after the event's line
-- was read after the event.
createTrigger("^Charisma:\\s+(\\d+)$", function()
    local pending = taPackage.statGrowthPending
    if not pending then return end
    taPackage.statGrowthPending = nil
    local c = taPackage.character
    pending.level = c.getLevel()
    pending.after = readAttributes()
    if pending.kind == "training" then
        pending.class_after = c.getClass()
        taPackage.db.recordTraining(pending)
    else
        pending.class = c.getClass()
        taPackage.db.recordDonation(pending)
    end
end, { type = "regex" })
