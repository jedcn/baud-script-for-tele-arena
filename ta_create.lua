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
-- The magic-shop detour is two moves off the route we already walk. The gear is
-- staged outside the town gates, one "sw" below the south plaza, and the shop is
-- one "s" below the same plaza -- which follows from ARENA_SHOP["1"].to being
-- { "w", "s", "s" } out of the arena (arena -> north plaza -> south plaza ->
-- magic shop) and the gear walk's own briefs confirming south plaza --sw--> gate.
--
-- The four shop commands are copied from what the arena's own restock sends on
-- arriving there (main.lua, arenaJourneyOnMovement, st == "potions"), so they
-- are known to work in that room.
--
-- Why potions are worth a detour at all: they add +5 to +20 to physique and
-- agility, which is damage and hit rate -- and hit rate is the binding
-- constraint, at 37% overall and 22.7% against a cave bear in
-- logs/session-garbageman-2026-08-15T19-45-33.log. A round costs ~24 gold
-- against an ~800 gold harvest, about 3%, so it only has to save ~45 seconds of
-- a ~25 minute cycle to pay for itself. The one thing that could cost real time
-- is the 10-minute training taint, and at a 25-minute baseline that floor is
-- nowhere near binding.
--
-- `rg 1` carries an `after` hook rather than being followed by another step,
-- because beginArenaSession sets arenaPotionsActive = 0: telling the arena about
-- the potions any earlier would be overwritten, and it would then walk to the
-- guild hall while still tainted, be refused, and waste the trip.
local CREATE_STEPS = {
    "re-roll-stop",
    "s",
    "sw",
    "get robes",
    "equip robes",
    "get warhammer",
    "equip warhammer",
    "ne",              -- south plaza
    "s",               -- magic shop
    "buy rowan",
    "buy hyssop",
    "drink rowan",
    "drink hyssop",
    "n",               -- south plaza
    "n",               -- north plaza
    "e",               -- arena
    {
        cmd = "rg 1",
        after = function()
            -- Both potions are up. The arena counts them down on the wear-off
            -- line and refuses to train until the count reaches 0, which is what
            -- keeps us from walking to a hall that would turn us away.
            taPackage.arenaPotionsActive = 2
        end,
    },
}

-- The other end of the run. `rg 1` fights until the character has earned a
-- level and banks it at the guild hall -- that whole trip is the arena script's
-- own (checkTrainingNeeded, arenaTryTrain, toTraining = { "w", "n" }, "buy
-- training"), and we deliberately don't reimplement a step of it. We only take
-- over afterwards, back in the arena, where the arena script would otherwise
-- ring the gong and fight on forever.
--
-- From the arena: "w" to the north plaza, "ne" to the tavern where Kerhak is
-- waiting, hand over the takings, then back out through the plazas to the gate
-- where the gear was staged and drop it for the next character.
--
-- The `i` is a step with a reply we have to read: the amount to hand over is
-- whatever the inventory says we are carrying, so the pump parks there and the
-- gold line resumes it (see the awaiting-gold trigger below). Giving is the one
-- thing here that cannot be a fixed string.
--
-- These directions retrace the arena's own routes in reverse and the creation
-- walk's outbound leg, which is a useful cross-check: "w"/"ne" is exactly
-- ARENA_NAV["1"].toBar, and "sw"/"s"/"sw" is the tavern back to the north
-- plaza, then the creation walk's "s"/"sw" to the gate.
-- The last two steps close the loop. Once the gear is on the floor and the gold
-- is in Kerhak's pocket this character has nothing left worth keeping, so it
-- gets thrown away and the whole run starts over on a fresh one.
--
-- The second `i` is a gate, not a formality. Everything of value has to be out
-- of our hands BEFORE the suicide, because a suicide takes whatever is still
-- being carried with it. Reading a hard zero back from the game is the only
-- proof we have that the handover actually happened -- the give could have been
-- refused, or partly landed -- and if the number is anything else we stop rather
-- than throw the difference away. That is the same call as the missing-Kerhak
-- stop below: never destroy something we cannot get back.
local CASH_OUT_STEPS = {
    "w",
    "ne",
    { cmd = "i", await = "gold" },
    "sw",
    "s",
    "sw",
    "unequip robes",
    "drop robes",
    "unequip warhammer",
    "drop warhammer",
    { cmd = "i", await = "zero-gold" },
    "suicide",
}

-- How long to wait for the inventory reply before giving up on the handover and
-- walking on. Without this an `i` that draws no gold line -- the one step here
-- whose continuation depends on the server saying something -- would park the
-- walk in the tavern indefinitely. Generous, because the only cost of waiting is
-- a few seconds and the cost of walking on early is that the takings stay in the
-- wrong character's pocket.
local CASH_OUT_GOLD_WAIT_MS = 10000

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
    taPackage.goldFarming = nil
    taPackage.createRerollPending = nil
    taPackage.createRerollArmed = nil
    taPackage.createCashOutArmed = nil
    taPackage.createRestarting = nil
    taPackage.createAnsweredClass = nil
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
        or taPackage.goldFarming == true
        or taPackage.createRerollPending == true
        or taPackage.createRerollArmed == true
        or taPackage.createWalk ~= nil
end

-- Registered under both word orders, like the continue- pair below. "gold
-- farming" and "farming gold" are equally natural English and the wrong one
-- silently doing nothing is a genuinely expensive failure here: it looks
-- exactly like a script that loaded but did not arm, which is a confusing thing
-- to debug from a log (and TA_LOGIN_CMD's confirmation is a cecho, so it never
-- reaches the log either).
for _, startAlias in ipairs({ "^start-gold-farming$", "^start-farming-gold$" }) do
createAlias(startAlias, function()
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
    -- Marks the whole round trip as ours, not just the prompt-answering phase.
    -- The cash-out reads it much later to tell a `rg 1` this loop started from
    -- one somebody ran by hand -- only the former should end in a walk to the
    -- tavern and a pile of gear on the floor.
    taPackage.goldFarming = true
    -- echo, not cecho: cecho never reaches the session log, and "did this arm?"
    -- is the first question asked of every run that goes wrong.
    echo("[create] Answering the character-creation prompts — Half-Ogre Warrior,"
        .. " then re-roll-half-ogre-warrior-fast-mode. Type stop-gold-farming to abort.")
end, { type = "regex" })
end

for _, stopAlias in ipairs({ "^stop-gold-farming$", "^stop-farming-gold$" }) do
createAlias(stopAlias, function()
    stopCreateCharacter()
    echo("[create] Stopped.")
end, { type = "regex" })
end

-- Pick a run back up after a disconnect, from the arena.
--
-- The arena is where a run spends nearly all of its time, so it is overwhelmingly
-- the phase a dropped connection lands in -- and the expensive one to lose, since
-- everything before it is a couple of minutes and the XP since is not. Log back
-- in, walk to the arena, run this.
--
-- There is very little to restore, which is the point: the loop is driven by
-- triggers reading taPackage flags, not by a position in a script. The only
-- thing the arena phase needs is `goldFarming`, which is what tells the training
-- confirmation to arm the cash-out. Everything else is cleared, because a
-- reload (rather than a reconnect) keeps taPackage and could otherwise leave a
-- half-finished walk or an armed cash-out from before the drop.
--
-- Earlier phases deliberately have no resume: they are minutes of work, and
-- re-running start-gold-farming from the top is both simpler and safer than
-- trying to rejoin a half-created character.
local function continueGoldFarmingFromArena()
    -- The room brief is how we know where we are standing; if one has been seen
    -- and it is not the arena, this would ring a gong at nothing. An unknown
    -- room (no brief since connecting) is not an error -- just say so and go.
    local room = taPackage.currentRoom
    if room and room ~= "arena" then
        echo("[create] Not resuming — you are in \"" .. room .. "\", not the arena."
            .. " Walk there first, then run this again.")
        return
    end
    if not runCommand then
        echo("[create] this baud has no runCommand — start the arena with `rg 1` yourself.")
        return
    end
    -- Anything left over from before the drop belongs to the interrupted run.
    stopCreateCharacter()
    taPackage.goldFarming = true
    if not room then
        echo("[create] No room brief seen yet — taking your word that this is the arena.")
    end
    echo("[create] Resuming the gold-farming loop from the arena: fighting until"
        .. " there is a level to train, then cashing out as usual.")
    runCommand("rg 1")
end

-- Registered under both word orders. The start/stop pair reads
-- "gold-farming", the name you reach for reads "farming-gold", and having the
-- wrong one silently do nothing is a poor trade for three lines.
createAlias("^continue-farming-gold-from-arena$", continueGoldFarmingFromArena,
    { type = "regex" })
createAlias("^continue-gold-farming-from-arena$", continueGoldFarmingFromArena,
    { type = "regex" })

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
    -- Class is the last question the game asks, so answering it is the point
    -- past which a NEW character definitely exists. The entry handler below
    -- refuses to re-roll without it.
    if prompt == "class" then taPackage.createAnsweredClass = true end
end, { type = "regex" })

-- We are in the game, so stop answering prompts.
--
-- Whether a re-roll is armed turns on whether we actually created anything.
-- Entering the game and creating a character are NOT the same event: a live
-- character goes from the main menu straight to this line, with no resurrect
-- menu and none of the questions above. That is what a reconnect looks like,
-- and if TA_LOGIN_CMD is still set (it is a launch variable, so it fires again
-- on every reconnect) an unguarded arm would start a re-roll on a character
-- that is already several levels in -- spraying `reroll` at a character we
-- meant to keep. Answering the class question is the proof that this entry
-- followed a creation, so that is what gates it.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    if not taPackage.creating then return end
    taPackage.creating = false
    if not taPackage.createAnsweredClass then
        echo("[create] Entered the game without creating anything (a live"
            .. " character), so not re-rolling. Use continue-farming-gold-from-arena"
            .. " to pick a run back up.")
        return
    end
    taPackage.createAnsweredClass = nil
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

-- Schedule the next step of the running walk, honouring the generation guard so
-- a walk that has been stopped (or restarted) leaves no live timer behind.
local function createWalkSchedule(delay)
    local gen = taPackage.createWalkGen
    createTimer(delay, function()
        if taPackage.createWalkGen ~= gen then return end
        taPackage.createWalkPump()
    end, { repeating = false })
end

-- One step, then pace the next. Driven by the clock rather than by arrival
-- briefs: these lists are half non-movement (a `get` prints no room line), so
-- there is no single event that means "that one landed" for every step in them.
-- The trip/refusal triggers below cover the case the clock cannot see.
--
-- A step is either a plain command string, or `{ cmd = ..., await = "gold" }`
-- for the one step whose follow-up depends on what the server says back. An
-- awaiting step does NOT schedule the next one -- whatever it is waiting for
-- does that, or the timeout does.
--
-- A taPackage field rather than a local: createWalkSchedule above is defined
-- first and has to call it, and a forward-declared local would cost a slot in a
-- file that exists to avoid spending them.
function taPackage.createWalkPump()
    local walk = taPackage.createWalk
    if not walk then return end

    local step = walk.steps[walk.index]
    if not step then
        cecho("cyan", "[create] " .. walk.doneMsg)
        createWalkStop()
        return
    end
    walk.index = walk.index + 1

    local cmd = type(step) == "table" and step.cmd or step
    echo("[" .. walk.label .. "] step " .. (walk.index - 1) .. "/" .. #walk.steps
        .. ": " .. cmd)
    runCommand(cmd)

    -- A step may carry work that has to happen right after its command goes out
    -- and not a moment earlier (see `rg 1` above, which zeroes the potion count
    -- as it starts).
    if type(step) == "table" and step.after then step.after() end

    if type(step) == "table" and step.await then
        walk.awaiting = step.await
        -- Nothing may hang forever on a reply that never comes.
        local gen = taPackage.createWalkGen
        createTimer(CASH_OUT_GOLD_WAIT_MS, function()
            if taPackage.createWalkGen ~= gen then return end
            local w = taPackage.createWalk
            if not (w and w.awaiting) then return end
            w.awaiting = nil
            cecho("yellow", "[" .. w.label .. "] no reply to `" .. cmd
                .. "` — carrying on without it.")
            taPackage.createWalkPump()
        end, { repeating = false })
        return
    end

    createWalkSchedule(CREATE_STEP_DELAY_MS)
end

-- Start a walk. Replaces whatever was running; the generation bump makes the
-- old one's in-flight timer inert.
local function createWalkStart(steps, label, doneMsg)
    taPackage.createWalk = { steps = steps, index = 1, label = label, doneMsg = doneMsg }
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
    taPackage.createWalkPump()
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
    createWalkStart(CREATE_STEPS, "create", "Kitted out and in the arena — rg 1 has the wheel.")
end

-- Training succeeded. The arena script is already walking us home from the guild
-- hall; let it finish that (it confirms arrival by room brief and handles its own
-- trips) and take over at the door, in onArenaArrivedHome below. Arming a flag
-- here rather than acting now is what keeps us out of a race with a journey that
-- is mid-stride.
--
-- Registered as our own trigger on the same line main.lua keys the level-banking
-- off, rather than folded into that handler: this concern is the gold-farming
-- loop's, not the arena's, and it must not fire for an ordinary `rg 1` that
-- somebody started by hand.
createTrigger("^After a rigorous mental and physical training session, you managed to blend$",
    function()
        if not taPackage.goldFarming then return end
        if not taPackage.arenaState then return end
        taPackage.createCashOutArmed = true
        cecho("cyan", "[create] Trained — cashing out as soon as we are back in the arena.")
    end, { type = "regex" })

-- Back in the arena after the training trip. main.lua's arenaArrivedHome calls
-- this before it does anything else; returning true means "we have taken over,
-- stop here" and suppresses the ring that would otherwise start another fight.
function taPackage.onArenaArrivedHome()
    if not taPackage.createCashOutArmed then return false end
    taPackage.createCashOutArmed = nil
    cecho("cyan", "[create] Handing the takings to Kerhak and dropping the gear.")
    -- We are done with the arena: stop it before walking, or its own errand
    -- dispatch and ring pump would keep issuing commands underneath us.
    if taPackage.stopArena then taPackage.stopArena() end
    createWalkStart(CASH_OUT_STEPS, "cash-out",
        "Gear dropped and the suicide sent — waiting for the BBS to start the next one.")
    return true
end

-- The inventory reply the cash-out parks on. Reading the amount from the reply
-- rather than from our own tracked gold is deliberate: the arena spends on
-- healing, food and training as it goes, so the tracked figure is only ever as
-- fresh as the last line that happened to mention gold.
createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
    local walk = taPackage.createWalk
    if not walk then return end
    local awaiting = walk.awaiting
    if not awaiting then return end
    walk.awaiting = nil
    local amount = tonumber(matches[2]) or 0

    if awaiting == "gold" then
        if amount > 0 then
            runCommand("give kerhak " .. amount .. " gold")
        else
            cecho("yellow", "[cash-out] Carrying no gold — nothing to hand over.")
        end
        createWalkSchedule(CREATE_STEP_DELAY_MS)
        return
    end

    -- The gate in front of the suicide. A suicide takes whatever is still being
    -- carried with it, so anything other than a hard zero here means the
    -- handover did not fully land and going on would destroy the difference.
    -- Stop instead, leaving the character standing there still holding it.
    if amount > 0 then
        stopCreateCharacter()
        echo("[cash-out] STOPPED — still carrying " .. amount .. " gold after the"
            .. " handover, so not going through with the suicide. Hand it to Kerhak"
            .. " yourself, then restart.")
        sendNtfy("Gold farming stopped",
            "Still carrying " .. amount .. " gold after handing over to Kerhak."
            .. " Stopped before the suicide so nothing is lost.")
        return
    end
    createWalkSchedule(CREATE_STEP_DELAY_MS)
end, { type = "regex" })

-- The handover found nobody to hand to. Kerhak is the entire point of the run --
-- the gold has to end up somewhere that survives this character being replaced --
-- so this is a full stop, not something to walk on from. Carrying on would drop
-- the gear and leave the takings in the pocket of a character we are about to
-- throw away.
--
-- Stopping also freezes the character in the tavern still holding the gold and
-- wearing the gear, which is the state you want to walk into: nothing has been
-- discarded, so the handover can be finished by hand.
--
-- The gate on a running cash-out walk is doing real work. This line is one of
-- the most common in the whole game -- it is what a whiffed attack prints when
-- the monster is already dead ("Sorry, you don't see \"flame\" nearby.", 44
-- times across the logs; "troll" 90, "stone" 106) -- so an ungated trigger would
-- halt the loop on almost every arena fight. During a cash-out the only command
-- that names anything is the give.
-- =========================================================================
-- Round and round: the suicide, and starting over
-- =========================================================================
--
-- The suicide worked and we are back at the BBS. From here the run repeats
-- itself, and almost all of it is already handled: arming `creating` again puts
-- the prompt-answering triggers at the top of this file back in charge, and they
-- take it from the resurrect menu all the way to a new character in the game.
--
-- Exactly one gap sits between here and there, and it is the reason this pair of
-- triggers exists rather than a couple more steps on the walk. The BBS prints
-- three things back to back -- the death lines, a full-screen menu redraw, then
-- its command prompt -- and how long that takes is the BBS's business, not ours.
-- Blind-timing a "5" into the middle of a screen redraw is exactly the kind of
-- buffered-keystroke bug main.lua's auto-login comment describes at length, so
-- both halves wait to be asked instead.
--
-- "You awaken" rather than "you take your own life": both print, but the second
-- one is the game confirming we are actually out and back at the BBS.
createTrigger("^You awaken after an unknown amount of time\\.\\.\\.$", function()
    -- A death prints this line too, and must not be mistaken for our own
    -- suicide. Restarting after one would send a fresh character to a gate with
    -- no gear on it (equipment is lost on death and costs ~150 gold to replace),
    -- and the harvest it was carrying never reached Kerhak -- so the loop would
    -- keep turning, quietly producing less each time.
    --
    -- taPackage.died is main.lua's, not ours: it is set by the death trigger
    -- there and cleared on the next entry into the game, so any script can read
    -- it during this window. Read, never cleared here -- clearing it would hide
    -- the death from anything else that asks.
    if taPackage.died then
        echo("[create] That was a death, not a retirement — not starting another"
            .. " character. Re-stage the robes and warhammer at the gate first.")
        return
    end
    if not taPackage.goldFarming then return end
    createWalkStop()
    -- Puts the creation triggers back in charge for the next character.
    taPackage.creating = true
    -- ...and this arms the one answer they do not cover, below.
    taPackage.createRestarting = true
    echo("[create] Character retired — starting the next one.")
end, { type = "regex" })

-- The BBS main-menu prompt, which is where "5" re-enters Tele-Arena. Matched
-- loosely and not anchored, because after a death the menu is redrawn as a
-- full-screen box and the prompt arrives as its status bar: triggers see the
-- ANSI-stripped text, which is
--
--     ■ 07:30:00 ■ 15-AUG-26 ■ Command ■ :
--
-- Keying off "Command" and the colon skips the clock and date, which change
-- every time, and the box-drawing characters, which are the part most likely to
-- differ between terminal profiles.
--
-- NOT anchored at end of line, and that is the whole point. baud's ANSI strip
-- removes SGR colour codes ONLY:
--
--     text.replace(/\x1B\[[0-9;]*m/g, '')     -- ANSIParser.ts:312
--
-- The BBS ends this prompt with a cursor-left, "\x1B[1D", which is a CSI
-- sequence but not an SGR one, so it survives into the text triggers are handed:
--
--     "█ 20:11:28 █ 15-AUG-26 █ Command █ : \x1B[1D"
--
-- A "\\s*$" anchor therefore never matches, and the first live run of the loop
-- sat at the BBS forever with the character already dead
-- (logs/session-garbageman-2026-08-15T19-45-33.log, line 4084). The earlier
-- "checked against the real bytes" was checked against a hand-rolled strip that
-- removed every CSI sequence, which is not what baud does -- so verify against
-- an SGR-only strip, or the log line itself, never a tidied copy.
--
-- Gated on createRestarting, which the trigger above sets and this one clears,
-- so it answers once per death and is inert the rest of the time -- including
-- during the ordinary login, where main.lua's own menu answer already handles
-- this and must not be doubled up on. That gate is also what makes the loose,
-- unanchored pattern safe.
createTrigger("Command .+ :", function()
    if not taPackage.createRestarting then return end
    taPackage.createRestarting = nil
    send("5")
end, { type = "regex" })

createTrigger("^Sorry, you don't see \"(.+)\" nearby\\.$", function(matches)
    local walk = taPackage.createWalk
    if not (walk and walk.label == "cash-out") then return end
    local who = matches[2]
    -- Clears the walk as well as the loop's flags, so nothing re-arms.
    stopCreateCharacter()
    -- echo, not cecho: cecho renders in the terminal but is never written to the
    -- session log (baud's App.tsx logs from echo only), and a run that stopped
    -- for a reason has to leave that reason in the log.
    echo("[cash-out] STOPPED — \"" .. who .. "\" is not here to take the gold."
        .. " Still carrying it, still wearing the gear; hand it over and restart when"
        .. " " .. who .. " is in the tavern.")
    sendNtfy("Gold farming stopped",
        "No " .. who .. " in the tavern to hand the takings to. The character is"
        .. " parked there with its gold and gear intact.")
end, { type = "regex" })

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
    -- Parked on a reply, so the step in flight is not a move and this refusal
    -- belongs to something else. Rewinding here would re-run the step before it
    -- and lose the reply we are waiting on.
    if walk.awaiting then return end
    walk.index = walk.index - 1
    -- Cancels the normal pacing timer already in flight, so the retry below is
    -- the only one left standing.
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
    echo("[" .. walk.label .. "] " .. why .. " — retrying step " .. walk.index
        .. " in " .. delay .. "ms")
    createWalkSchedule(delay)
end

createTrigger("^In your haste, you trip and fall!$", function()
    createWalkRetryStep("tripped", CREATE_TRIP_RETRY_MS)
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function()
    createWalkRetryStep("still resting", CREATE_REST_RETRY_MS)
end, { type = "regex" })
