--
-- The character: everything the script knows about the character it is
-- playing, and the accessors that read and change it.
--
-- Loaded by main.lua with dofile, so that "things about the character" live in
-- one file. Like ta_nav.lua, it is a separate chunk and cannot see main.lua's
-- locals; the seam runs through taPackage:
--
--   in    taPackage.xp (ta_xp.lua); taPackage.recordXpChange,
--         taPackage.checkArenaGoldFloor (main.lua)
--   out   taPackage.character (the accessors), taPackage._character (the
--         data), taPackage.PROMOTED_CLASS
--
-- Everything "in" is only touched when an accessor is called, never while this
-- file loads, so it is fine that main.lua defines most of it further down.
--

-- The character's state lives in _character; the underscore means "go through
-- the accessors on taPackage.character". The data survives reloadScript() along
-- with taPackage, while the accessors are rebuilt on every load. The
-- `or taPackage.character` adopts a session's state from before the split, when
-- the data itself was taPackage.character.
taPackage._character = taPackage._character or taPackage.character or {}
taPackage.character = {}

function taPackage.character.setCharacterStatus(value)
    taPackage._character.status = value
end

function taPackage.character.getCharacterStatus()
    return taPackage._character.status
end

function taPackage.character.setVitality(current, max)
    taPackage._character.vitalityCurrent = tonumber(current)
    taPackage._character.vitalityMax = tonumber(max)
end

function taPackage.character.getVitality()
    return taPackage._character.vitalityCurrent, taPackage._character.vitalityMax
end

-- Encumberance is the game's carried-weight gauge, printed on the "st" sheet as
-- "current / max" (e.g. 1000 / 1000 = fully loaded). Stored like Vitality/Mana.
function taPackage.character.setEncumberance(current, max)
    taPackage._character.encumberanceCurrent = tonumber(current)
    taPackage._character.encumberanceMax = tonumber(max)
end

function taPackage.character.getEncumberance()
    return taPackage._character.encumberanceCurrent, taPackage._character.encumberanceMax
end

-- Encumberance as a whole-number percentage of max (0-100+), or nil if either
-- value is missing or max is 0. Display-only helper for notifications.
function taPackage.character.getEncumberancePercent()
    local current, max = taPackage.character.getEncumberance()
    if not current or not max or max == 0 then return nil end
    return math.floor((current / max) * 100 + 0.5)
end

function taPackage.character.setMana(current, max)
    taPackage._character.manaCurrent = tonumber(current)
    taPackage._character.manaMax = tonumber(max)
end

function taPackage.character.getMana()
    return taPackage._character.manaCurrent, taPackage._character.manaMax
end

function taPackage.character.setExperience(value)
    local previous = taPackage._character.experience
    local current = tonumber(value)
    taPackage._character.experience = current
    -- The status bar flashes how far the XP figure just moved, and this is the
    -- one place that knows a move happened. recordXpChange is defined with the
    -- status bar in main.lua, after this file loads, so it only exists once the
    -- script has finished loading -- always true by the time a trigger calls us.
    if taPackage.recordXpChange then taPackage.recordXpChange(previous, current) end
end

function taPackage.character.getExperience()
    return taPackage._character.experience
end

function taPackage.character.setClass(value)
    taPackage._character.class = value
end

function taPackage.character.getClass()
    return taPackage._character.class
end

-- What each base class becomes when it buys promotion at level 25
-- (docs/shrine/PROMOTIONS.md). A class with an entry here can still promote;
-- the promoted names have none, so they are done.
taPackage.PROMOTED_CLASS = {
    Warrior   = "Knight",
    Hunter    = "Beast Master",
    Archer    = "Master Archer",
    Rogue     = "Blackguard",
    Acolyte   = "High Priest",
    Druid     = "Arch Druid",
    Sorceror  = "Arch Magus",
    Necrolyte = "Necromancer",
}

-- Is the character this base class, before or after promotion? Promotion
-- renames the class but keeps the spellbook, so an Arch Magus still casts
-- toduza and a High Priest still heals the group -- anything keyed on what a
-- class can do asks this, not taPackage.character.getClass() == "Sorceror".
function taPackage.character.isClass(base)
    local cls = taPackage.character.getClass()
    return cls ~= nil and (cls == base or cls == taPackage.PROMOTED_CLASS[base])
end

function taPackage.character.setLevel(value)
    taPackage._character.level = tonumber(value)
end

function taPackage.character.getLevel()
    return taPackage._character.level
end

function taPackage.character.setGold(value)
    taPackage._character.gold = tonumber(value)
    -- Every gold change flows through here, so the arena's "below the minimum to
    -- keep going" safety exit hangs off it. checkArenaGoldFloor is defined with
    -- the other arena helpers in main.lua.
    if taPackage.checkArenaGoldFloor then taPackage.checkArenaGoldFloor() end
end

function taPackage.character.getGold()
    return taPackage._character.gold
end

function taPackage.character.setPhysique(value)
    taPackage._character.physique = tonumber(value)
end

function taPackage.character.getPhysique()
    return taPackage._character.physique
end

function taPackage.character.setStamina(value)
    taPackage._character.stamina = tonumber(value)
end

function taPackage.character.getStamina()
    return taPackage._character.stamina
end

function taPackage.character.setAgility(value)
    taPackage._character.agility = tonumber(value)
end

function taPackage.character.getAgility()
    return taPackage._character.agility
end

function taPackage.character.setCharisma(value)
    taPackage._character.charisma = tonumber(value)
end

function taPackage.character.getCharisma()
    return taPackage._character.charisma
end

function taPackage.character.setIntellect(value)
    taPackage._character.intellect = tonumber(value)
end

function taPackage.character.getIntellect()
    return taPackage._character.intellect
end

function taPackage.character.setKnowledge(value)
    taPackage._character.knowledge = tonumber(value)
end

function taPackage.character.getKnowledge()
    return taPackage._character.knowledge
end

function taPackage.character.setName(value)
    taPackage._character.name = value
end

function taPackage.character.getName()
    return taPackage._character.name
end

function taPackage.character.setWeapon(value)
    taPackage._character.weapon = value
end

function taPackage.character.getWeapon()
    return taPackage._character.weapon
end

function taPackage.character.setArmor(value)
    taPackage._character.armor = value
end

function taPackage.character.getArmor()
    return taPackage._character.armor
end

-- The level the character's XP has earned, which can run ahead of the level
-- it has trained to (getLevel). checkLevelUpNotification keeps it.
function taPackage.character.setEarnedLevel(value)
    taPackage._character.earnedLevel = value
end

function taPackage.character.getEarnedLevel()
    return taPackage._character.earnedLevel
end

-- True when we have banked enough XP for a level we haven't trained for yet:
-- the level our XP earns us has outrun the level the game reports. Training is
-- a manual trip to a guild hall (and some arenas have none), so that gap can
-- stay open for a long time — the status bar flags it with a "^".
-- Deliberately independent of checkTrainingNeeded, which additionally gates on
-- the arena profile: the mark is about the character, not about whether the
-- arena script is about to act on it.
function taPackage.character.hasUntrainedLevel()
    local xp, class, level = taPackage.character.getExperience(), taPackage.character.getClass(), taPackage.character.getLevel()
    -- Any unknown, or a class we have no XP table for, means we can't tell.
    -- The xpThresholds check keeps the comparison below off a nil level.
    if not (xp and class and level and taPackage.xp.thresholds[class]) then return false end
    return taPackage.xp.getLevelForXp(xp, class) > level
end
