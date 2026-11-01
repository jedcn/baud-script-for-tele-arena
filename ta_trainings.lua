-- ta_trainings.lua -- how the six attributes move when a character trains
--
-- The guild hall's success line starts a record: the class and attributes we
-- hold right then are the "before" (the hall refuses a potion-tainted
-- character, so they are base stats). We ask for a fresh sheet, and when its
-- last attribute line (Charisma) arrives the "after" is complete and the row
-- goes to the trainings table. Every training gets a row, even one where no
-- stat moved, so the rows answer "how often does a stat rise on a level".
--
-- `buy promotion` answers with the same success line, so promotions are
-- filed too; class_before and class_after tell them apart.
--
-- Loaded by main.lua with dofile, after the attribute triggers: its Charisma
-- trigger must run after main.lua's has stored the new value.
--
--   in    taPackage.character (the sheet), taPackage.db.recordTraining
--   out   taPackage.trainingPending (survives reloadScript(), like the rest
--         of taPackage)

local function readAttributes()
    local c = taPackage.character
    return {
        intellect = c.getIntellect(), knowledge = c.getKnowledge(),
        physique = c.getPhysique(), stamina = c.getStamina(),
        agility = c.getAgility(), charisma = c.getCharisma(),
    }
end

-- Not gated on an arena run: a hand-typed `buy training` counts the same.
createTrigger("^After a rigorous mental and physical training session, you managed to blend$", function()
    taPackage.trainingPending = {
        character = taPackage.character.getName(),
        class_before = taPackage.character.getClass(),
        before = readAttributes(),
    }
    send("st")
end, { type = "regex" })

-- Charisma is the last attribute on the sheet, and the sheet answers the `st`
-- above; the game replies in order, so any sheet after the success line was
-- read after the training.
createTrigger("^Charisma:\\s+(\\d+)$", function()
    local pending = taPackage.trainingPending
    if not pending then return end
    taPackage.trainingPending = nil
    pending.class_after = taPackage.character.getClass()
    pending.level = taPackage.character.getLevel()
    pending.after = readAttributes()
    taPackage.db.recordTraining(pending)
end, { type = "regex" })
