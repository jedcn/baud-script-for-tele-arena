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

-- What to do once the re-roll finally lands a good set of stats: stop the
-- re-roll, kit the new character out from the gear staged on the floor, walk to
-- the arena and start fighting. Hand-verified; every direction here is one the
-- user walked themselves.
--
-- "re-roll-stop" leads deliberately. Accepting a roll does not stop the
-- re-roller -- it bumps the generation so the pending timer no-ops, but leaves
-- taPackage.reRolling true, which is why the "Done after N rolls" message tells
-- you to stop it by hand. Left running, every status block from here on
-- (including the ones `rg 1` pulls) would be fed back through the matcher.
-- Putting the stop first in the same ordered list is what makes "before
-- anything else" a visible property rather than a promise in a comment.
--
-- Every step goes through runCommand, not send, so each takes the path typed
-- input takes. That is load-bearing three times over: "re-roll-stop" and "rg 1"
-- are aliases and would otherwise go out as literal text, and the bare
-- directions hit main.lua's movement aliases, which set pendingDirection so the
-- mapper dead-reckons the walk the same way it would a hand-typed one.
local CREATE_STEPS = {
    "re-roll-stop",
    "s",
    "sw",
    "get robes",
    "equip robes",
    "get warhammer",
    "equip warhammer",
    "ne",
    "n",
    "e",
    "rg 1",
}

-- Reuse the arena's pace rather than picking a new number. It was tuned by
-- measurement (see ARENA_STEP_DELAY_MS in main.lua): 1000/1200/1300ms all
-- tripped a paced walk, 1500 has carried 250-odd scripted moves without one.
-- Same character, same game, so there is no reason to move faster here. The
-- non-movement steps do not need pacing at all, but pacing them uniformly costs
-- six seconds once per character and keeps this a plain list.
local CREATE_STEP_DELAY_MS = taPackage.arenaStepDelayMs or 1500
-- A move can be refused for two quite different reasons, and they want quite
-- different waits. Tripping means we moved too soon after the last move: a
-- couple of seconds clears it, which is what the arena's own trip retry uses.
local CREATE_TRIP_RETRY_MS = 2000
-- Being told to rest means the physical cooldown is running, and that is tens of
-- seconds, not two. It bites here every single time: the walk starts the instant
-- the re-roll stops, and by then the character has just sent ~76 rerolls
-- back to back, which leaves the clock fully charged. Retrying at the trip's 2s
-- spent 13 commands and ~26s grinding through it in
-- logs/session-garbageman-2026-08-15T14-17-19.log (lines 1845-1919). 30s is what
-- main.lua already waits on this same line for a non-urgent errand walk, and
-- this is one; the 2s cadence there is reserved for fleeing, where we are taking
-- hits every round and cannot afford to wait.
local CREATE_REST_RETRY_MS = 30000

-- Bumped on every stop and every retry, so an in-flight pacing timer belonging
-- to a walk we have moved on from lands as a no-op. The script has no timer
-- cancellation, so this is how every other paced thing here does it.
local function createWalkStop()
    taPackage.createWalk = nil
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
end

-- Shared teardown, so `stop-gold-farming` and `stop-all-scripts` disarm the
-- same state. Also clears the pending re-roll handoff (a stop between "Entering
-- Tele-Arena..." and the inventory reply means we no longer want it) and halts
-- a walk in progress, so one stop covers the whole gold-farming flow.
local function stopCreateCharacter()
    taPackage.creating = false
    taPackage.createRerollPending = nil
    taPackage.createRerollArmed = nil
    createWalkStop()
end
taPackage.stopCreateCharacter = stopCreateCharacter

-- Is any part of the gold-farming flow live? It runs in four phases and only
-- the first sets `creating`, so asking about that flag alone would have
-- stop-all-scripts report "not running" while a walk was mid-stride. Kept here,
-- next to the teardown, so the two can't drift apart.
--
--   creating            answering the BBS creation prompts
--   createRerollPending created, waiting on the sheet to start the re-roll
--   createRerollArmed   re-rolling, and this run owns the result
--   createWalk          gearing up and walking to the arena
function taPackage.createCharacterRunning()
    return taPackage.creating == true
        or taPackage.createRerollPending == true
        or taPackage.createRerollArmed == true
        or taPackage.createWalk ~= nil
end

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
        -- Only a re-roll WE started may end in a walk to the arena. A hand-run
        -- re-roll-half-ogre-warrior-* is someone watching numbers go by, and
        -- having it suddenly march the character off and ring a gong would be a
        -- nasty surprise. Armed here, read by onRerollAccepted below.
        taPackage.createRerollArmed = true
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

-- One step, then pace the next. Driven by the clock rather than by arrival
-- briefs: the list is half non-movement (a `get` prints no room line), so there
-- is no single event that means "that one landed" for every step in it. The
-- trip/refusal triggers below are what cover the case the clock cannot see.
local function createWalkPump()
    local walk = taPackage.createWalk
    if not walk then return end

    local step = CREATE_STEPS[walk.index]
    if not step then
        cecho("cyan", "[create] Kitted out and in the arena — rg 1 has the wheel.")
        createWalkStop()
        return
    end
    walk.index = walk.index + 1

    echo("[create] step " .. (walk.index - 1) .. "/" .. #CREATE_STEPS .. ": " .. step)
    runCommand(step)

    local gen = taPackage.createWalkGen
    createTimer(CREATE_STEP_DELAY_MS, function()
        if taPackage.createWalkGen ~= gen then return end
        createWalkPump()
    end, { repeating = false })
end

-- The re-roll has accepted a set of stats. main.lua calls this from the
-- Vitality trigger's accepted branch if it is defined; nothing else does.
function taPackage.onRerollAccepted()
    if not taPackage.createRerollArmed then return end
    taPackage.createRerollArmed = nil
    if not runCommand then
        cecho("yellow", "[create] this baud has no runCommand — run re-roll-stop"
            .. " and gear up yourself")
        return
    end
    cecho("cyan", "[create] Stats accepted — stopping the re-roll, gearing up,"
        .. " and heading for the arena.")
    taPackage.createWalk = { index = 1 }
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
    createWalkPump()
end

-- A move that did not happen. Both lines mean the same thing for the walk -- the
-- character is still in the room it was in -- and neither prints a room brief,
-- so the clock-driven pump above would blithely carry on and run the rest of the
-- list from one room too far back. Rewind a step and retry. Bumping the
-- generation cancels the normal pacing timer already in flight, so the retry
-- cannot double up with it.
--
-- `why` and `delay` differ per refusal (see the constants above); a retry that
-- is itself refused re-emits the same line, so each cadence re-arms naturally
-- for as long as it needs to.
local function createWalkRetryStep(why, delay)
    local walk = taPackage.createWalk
    if not walk then return end
    walk.index = walk.index - 1
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
    local gen = taPackage.createWalkGen
    echo("[create] " .. why .. " — retrying step " .. walk.index .. " in " .. delay .. "ms")
    createTimer(delay, function()
        if taPackage.createWalkGen ~= gen then return end
        createWalkPump()
    end, { repeating = false })
end

createTrigger("^In your haste, you trip and fall!$", function()
    createWalkRetryStep("tripped", CREATE_TRIP_RETRY_MS)
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function()
    createWalkRetryStep("still resting", CREATE_REST_RETRY_MS)
end, { type = "regex" })
