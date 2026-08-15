--
-- Character creation: `start-gold-farming` answers the BBS's create-a-character
-- questions, then hands off to the fast-mode Half-Ogre Warrior re-roll.
--
-- Loaded by main.lua with dofile, in its own file for the reason CLAUDE.md
-- gives: Lua allows at most 200 local variables active at once in a single
-- function, and a file IS a function, so every top-level `local` in main.lua
-- draws from one budget. A separate chunk gets its own 200. This section is a
-- natural cut -- it needs nothing from main.lua at all.
--
-- The seam, through taPackage (locals are not visible across chunks):
--
--   in    (nothing)
--   out   taPackage.creating, taPackage.stopCreateCharacter
--
-- =========================================================================
-- Create a character
-- =========================================================================
--
-- Making a fresh character is a fixed sequence of BBS prompts, every answer of
-- which is known in advance. Transcribed from
-- logs/session-garbageman-2026-08-15T07-30-44.log (lines 129-298), which is a
-- hand-driven run of exactly this:
--
--     << hit return >>            ->  CR    (back at the BBS after `suicide`)
--     Command :                   ->  5     (auto-login already answers this)
--     Select an option:           ->  2     Create New Character
--     << hit return >>            ->  CR    x4, paging through the intro text
--     Select a race:              ->  6     Half-Ogre
--     Select a complexion:        ->  1
--     Select an eye color:        ->  1
--     Select a hair color:        ->  1
--     Select a hair style:        ->  1
--     Select a hair length:       ->  1
--     Select a class:             ->  1     Warrior
--     Entering Tele-Arena...            we are in; start the re-roll
--
-- Two things shape the implementation:
--
-- It is keyed off the prompt's own wording, not an ordered step list, so it
-- cannot desync. The post-death menu only appears when there is an old
-- character to resurrect, and the intro is however many pages the BBS feels
-- like sending; a counter would drift on either, while "answer whatever is in
-- front of me" does not.
--
-- And every answer is gated on taPackage.creating, because these lines are
-- actively harmful outside of creation. "<< hit return >>" also prints after a
-- normal `x` out of the game, and a bare `1` sent into the arena is a real
-- command. Nothing fires until the alias arms it, and "Entering Tele-Arena..."
-- disarms it again.

-- Which number answers which prompt. The noun is the capture from "Select a
-- <noun>:" / "Select an <noun>:"; anything not named here gets "1", which is a
-- valid choice on every one of these menus.
--
-- "option" is the one place where the blanket "1" would be wrong: 1 on the
-- post-death menu resurrects the old character rather than making a new one.
local CREATE_ANSWERS = {
    race = "6",   -- Half-Ogre
    class = "1",  -- Warrior
    option = "2", -- Create New Character (not "1", Resurect Old Character)
}

-- Shared teardown, so `stop-gold-farming` and `stop-all-scripts` disarm the
-- same state. Also clears the pending re-roll handoff: a stop between
-- "Entering Tele-Arena..." and the inventory reply means we no longer want it.
local function stopCreateCharacter()
    taPackage.creating = false
    taPackage.createRerollPending = nil
end
taPackage.stopCreateCharacter = stopCreateCharacter

createAlias("^start-gold-farming$", function()
    -- Refuse to re-arm in the one window where doing so is provably wrong: a
    -- character has just been created and its re-roll is one line away from
    -- starting. TA_INIT_CMD="start-gold-farming" lands exactly here -- it fires
    -- off the inventory reply, and main.lua's gold trigger is registered before
    -- this file's, so an unguarded arm would (a) leave prompt-answering live
    -- in-game, where a bare "1" or "6" is a real command, and (b) clear the
    -- handoff flag the very next trigger was about to read, silently costing us
    -- the re-roll. TA_LOGIN_CMD is the variable that actually reaches a dead
    -- character; say so rather than just declining.
    if taPackage.createRerollPending then
        cecho("yellow", "[create] A character was just created and the re-roll is about to"
            .. " start — not re-arming. (Use TA_LOGIN_CMD, not TA_INIT_CMD, to run this"
            .. " on login: TA_INIT_CMD cannot fire for a dead character.)")
        return
    end
    taPackage.creating = true
    cecho("cyan", "[create] Answering the character-creation prompts — Half-Ogre Warrior,"
        .. " then re-roll-half-ogre-warrior-fast-mode. Type stop-gold-farming to abort.")
end, { type = "regex" })

createAlias("^stop-gold-farming$", function()
    stopCreateCharacter()
    echo("[create] Stopped.")
end, { type = "regex" })

-- The intro text pages on this prompt; a bare carriage return turns the page.
-- send("") is exactly that: baud's TelnetConnection.send writes `data .. "\r\n"`,
-- so an empty string puts a lone newline on the wire.
createTrigger("^<< hit return >>\\s*$", function()
    if not taPackage.creating then return end
    send("")
end, { type = "regex" })

-- One trigger for the whole "Select a ...:" family, dispatching on the captured
-- noun -- deliberately not one trigger per prompt. baud fires EVERY trigger
-- whose pattern matches a line, so a generic "^Select a" sitting alongside a
-- specific "^Select a race" would answer that one prompt twice, and the spare
-- digit would sit in the BBS's input buffer until the game started and then
-- arrive in the arena as chat. (Auto-login has the same bug written up at
-- length in main.lua, from logs/session-tojolias-2026-08-11T22-49-54.log.)
--
-- `an?` rather than `(a|an)`: the test harness converts these regexes to Lua
-- patterns, which have no alternation, but do read `?` as "optional".
createTrigger("^Select an? (.+):\\s*$", function(matches)
    if not taPackage.creating then return end
    local prompt = matches[2]
    send(CREATE_ANSWERS[prompt] or "1")
end, { type = "regex" })

-- We are in the game, so stop answering prompts. The re-roll is only *armed*
-- here, not run -- see runCreateReroll for why it has to wait.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    if not taPackage.creating then return end
    taPackage.creating = false
    taPackage.createRerollPending = true
end, { type = "regex" })

-- Start the re-roll, once, now that the entry character sheet has landed.
--
-- The timing is the reason this isn't two more lines in the handler above.
-- main.lua's "Entering Tele-Arena..." trigger fires `st` and `i`, and their
-- replies are still in flight when it returns. The `st` reply ends with a
-- "Vitality:" line, and that is the very line the re-roll counts a roll on --
-- so arming the re-roll any earlier would score the new character's opening
-- stats as roll #1 against a matcher that had not been chosen yet. The
-- inventory's gold line is the last reply of the `st`/`i` pair, so by the time
-- it arrives the sheet is fully parsed and the next "Vitality:" will be one we
-- asked for. Same reasoning, and the same landing spot, as runLoginInitCmd.
createTrigger("^You are carrying (\\d+) gold crowns", function()
    if not taPackage.createRerollPending then return end
    taPackage.createRerollPending = nil
    cecho("cyan", "[create] Character created — starting re-roll-half-ogre-warrior-fast-mode.")
    if runCommand then
        -- runCommand, not send: send puts the literal text on the wire, where
        -- an alias name means nothing.
        runCommand("re-roll-half-ogre-warrior-fast-mode")
    else
        -- Older baud (the VPS copy, say) has no runCommand and so cannot reach
        -- an alias at all. Say so rather than silently sending the alias name
        -- to the server as chat.
        cecho("yellow", "[create] this baud has no runCommand — run"
            .. " re-roll-half-ogre-warrior-fast-mode yourself")
    end
end, { type = "regex" })
