--
-- Gold farming: `farm-for-gold` makes a throwaway Half-Ogre Warrior, levels it
-- once in the first arena, hands its gold to whoever waits in the tavern, and
-- retires it to start over -- picking up from wherever a disconnect or a death
-- left the last one.
--
-- Loaded by main.lua with dofile, in its own file for the reason CLAUDE.md
-- gives: Lua allows at most 200 local variables active at once in a single
-- function, and a file IS a function, so every top-level `local` in main.lua
-- draws from one budget. A separate chunk gets its own 200. This section is a
-- natural cut -- it needs nothing from main.lua at all.
--
-- The seam, through taPackage (locals are not visible across chunks):
--
--   in    taPackage.reroll.builds, taPackage.character, taPackage.currentRoom
--   out   taPackage.creating, taPackage.stopCreateCharacter,
--         taPackage.onRerollAccepted, taPackage.onArenaArrivedHome,
--         taPackage.onFarmingDeath
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
--
-- Creating is only one way into the game, though. The same alias, run from
-- TA_LOGIN_CMD, also meets a character that is still alive -- dropped by the
-- BBS mid-walk, mid-fight or mid-handover -- and a fresh character is just the
-- earliest of those cases. So nothing here follows a script from the top:
-- every entry into the game reads the character sheet and the room, and plans
-- the rest of the run from there (see farmAssess below).

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

-- The walks below are hand-verified; every direction in them is one the user
-- walked themselves.
--
-- Every step goes through runCommand, not send, so each takes the path typed
-- input takes. That is load-bearing three times over: "re-roll-stop" and "rg 1"
-- are aliases and would otherwise go out as literal text, and the bare
-- directions hit main.lua's movement aliases, which set pendingDirection so the
-- mapper dead-reckons the walk the same way it would a hand-typed one.
-- STAT POTIONS ARE BACK, AND THAT TOO IS A MEASURED DECISION -- please read
-- this before taking them out again.
--
-- Rowan and hyssop were first tried on 2026-08-15
-- (logs/session-garbageman-2026-08-15T21-52-26.log) and then removed. They work,
-- spectacularly, on the thing they claim to affect: +6 physique and +12 agility
-- took the hit rate from 37.0% to 63.8%, and the character reached the 1125 XP it
-- needed in about 7 minutes instead of 21-27.
--
-- And the cycle did not get shorter. It came in at ~26 minutes against a 25-31
-- minute baseline, and delivered 785 gold against 793-833 without them, because
-- the training hall refuses a potion-tainted character and the taint measured
-- 22m 24s from a known drink time (21:54:02 -> tingles at 22:16:26, both potions
-- lapsing in the same second, so a joint drink is one shared window and halving
-- the dose would not shorten it). The fight was over at minute 7 and the next 15
-- minutes were spent waiting to be allowed to bank the level. So the speedup
-- landed on a phase that was not the bottleneck, and out they came -- with a note
-- saying "worth revisiting only if the training taint stops being the binding
-- constraint".
--
-- It has. Not because the arena changed, but because the taint turned out to be
-- purchasable. The temple's `buy restoring` clamps every stat back to base, which
-- strips rowan and hyssop along with anything a monster drained: 25 crowns took
-- Phy 35 -> 30 and Agi 27 -> 15, exactly the rolled numbers, and the hall trained
-- the character on the next breath
-- (logs/session-garbageman-2026-08-29T08-16-38.log, driven by hand). A 22-minute
-- wait became a 25-crown errand to a room the arena already walks to, so the
-- 15 dead minutes come off the cycle and the 7-minute fight is left standing.
--
-- The 7 minutes is the part to hold loosely. That same 2026-08-29 run had both
-- potions up and still took 14 minutes to earn its level -- the hit rate was right
-- where the potions promise (28 hits / 44 swings, 63.6%), but it drew four
-- hobgoblins and needed 314 damage. Monster draw swings the fight time by 2x on
-- its own, so treat the next few cycles as the measurement, not as confirmation.
--
-- The bill: 16 + 15 crowns of potions and 25 for the restoring, 56 against a
-- harvest that is mostly the character's STARTING purse (~800). ~7%. Corpses drop
-- 2-4 gold, so fighting faster cannot earn more per cycle -- only finish sooner,
-- which is now allowed. If the measured cycle does not come in well under 25
-- minutes, this is not paying for itself and should come out again.
--
-- Where the run picks up is decided afresh every time a character enters the
-- game, from what the entry `st`/`i` say and the room it is standing in:
--
--   level 2 or more         it has trained: cash out from here
--   stats short of the roll re-roll (a fresh character always lands here)
--   no robes or warhammer   walk to the gate, take or buy them
--   never fought, no potion buy the potions on the way to the arena
--   otherwise               walk to the arena and fight
--
-- A level earned but not yet trained needs nothing of its own: rg 1 trains it
-- at the first decision point, buying restoring first if the potions are up.
--
-- Two details in the routes below are load-bearing:
--
--   the magic shop is "s" from the south plaza, and "n"/"n" leads back to the
--   north plaza. Same rooms the arena's own ARENA_SHOP["1"] route uses from
--   the other direction.
--
--   "arena-potions-drunk" AFTER "rg 1", not before. Starting a session zeroes
--   arenaPotionsActive (see beginArenaSession), so anything drunk beforehand is
--   invisible to the training gate and the first level owed would walk to the
--   hall, be refused, and only self-correct from there. Reporting it costs one
--   command and skips that bounce.

-- The way to the north plaza from every room a farming character passes
-- through. The north plaza is the hub: the arena is "e" of it, the tavern
-- "ne", the south plaza "s", and the gate and the three shops hang off the
-- south plaza. Checked against the arena's own routes (toTemple w,w; toBar
-- w,ne; toTraining w,n) and the gear walk the user wrote down. A room not in
-- here stops the run: there is no guessing a way home from it.
local TO_NORTH_PLAZA = {
    ["north plaza"] = {},
    ["arena"]       = { "w" },
    ["temple"]      = { "e" },
    ["tavern"]      = { "sw" },
    ["guild hall"]  = { "s" },
    ["south plaza"] = { "n" },
    ["town gates"]  = { "ne", "n" },
    ["armor shop"]  = { "e", "n" },
    ["weapon shop"] = { "w", "n" },
    ["magic shop"]  = { "n", "n" },
}

-- The highest agility a Half-Ogre rolls. Hyssop adds 12, so anything above this
-- on a level-1 farming character means the potions are up -- the only way to
-- tell after a reconnect, when nothing remembers drinking them.
local HALF_OGRE_MAX_AGILITY = 17

local function appendSteps(steps, list)
    for _, step in ipairs(list) do steps[#steps + 1] = step end
    return steps
end

-- From the gate to the south plaza, fitting whatever `need` says is missing:
-- picked up if `floor` says it is lying here, bought otherwise. Robes from the
-- armor shop one room west of the south plaza, the warhammer from the weapon
-- shop one room east, each an out-and-back so the walk on from the south plaza
-- is the same whatever was bought. Buying costs gold the run exists to
-- harvest, so it is only ever done for a piece that is missing.
local function gearSteps(need, floor)
    local steps = {}
    if need.robes and floor.robes then appendSteps(steps, { "get robes", "equip robes" }) end
    if need.warhammer and floor.warhammer then
        appendSteps(steps, { "get warhammer", "equip warhammer" })
    end
    steps[#steps + 1] = "ne"
    if need.robes and not floor.robes then
        appendSteps(steps, { "w", "buy robes", "equip robes", "e" })
    end
    if need.warhammer and not floor.warhammer then
        appendSteps(steps, { "e", "buy warhammer", "equip warhammer", "w" })
    end
    return steps
end

-- What to do with a character that is in the game and in a room we know, as a
-- walk: { steps, label, doneMsg }, plus `need`/`afterGear` when it goes by the
-- gate, so the floor line can rebuild the rest of it. The re-roll is decided
-- before this is called (see farmAssess); everything here assumes a good roll.
local function farmPlan(room)
    local steps = appendSteps({}, TO_NORTH_PLAZA[room])

    if (taPackage.character.getLevel() or 1) >= 2 then
        return {
            steps = appendSteps(steps, taPackage.cashOutFromNorthPlaza),
            label = "cash-out",
            doneMsg = "Gear dropped and the suicide sent — waiting for the BBS to start the next one.",
        }
    end

    local potionsUp = (taPackage.character.getAgility() or 0) > HALF_OGRE_MAX_AGILITY
    -- Only for a character that has not fought yet. One that has is part-way
    -- to its level, and a farming run never restocks (main.lua's potion
    -- wear-off handler says why): a fresh taint only pushes training back.
    local buyPotions = not potionsUp and (taPackage.character.getExperience() or 0) == 0
    local fight = { "rg 1" }
    if buyPotions or potionsUp then fight[#fight + 1] = "arena-potions-drunk" end
    local fromSouthPlaza = {}
    if buyPotions then appendSteps(fromSouthPlaza, { "s", "buy-potions", "n" }) end
    appendSteps(fromSouthPlaza, { "n", "e" })
    appendSteps(fromSouthPlaza, fight)

    local done = "Kitted out and in the arena — rg 1 has the wheel."
    local need = {
        robes = taPackage.character.getArmor() ~= "Robes",
        warhammer = taPackage.character.getWeapon() ~= "Warhammer",
    }
    if need.robes or need.warhammer then
        appendSteps(steps, { "s", { cmd = "sw", await = "gear" } })
        -- Until the floor line says otherwise, assume the gear is lying there:
        -- if the brief never comes, picking it up is what the walk always did.
        appendSteps(steps, gearSteps(need, { robes = true, warhammer = true }))
        appendSteps(steps, fromSouthPlaza)
        return { steps = steps, label = "create", doneMsg = done,
                 need = need, afterGear = fromSouthPlaza }
    end
    if buyPotions then
        appendSteps(steps, { "s" })
        return { steps = appendSteps(steps, fromSouthPlaza), label = "create", doneMsg = done }
    end
    if room == "arena" then
        return { steps = fight, label = "create", doneMsg = done }
    end
    appendSteps(steps, { "e" })
    return { steps = appendSteps(steps, fight), label = "create", doneMsg = done }
end

-- The other end of the run. `rg 1` fights until the character has earned a
-- level and banks it at the guild hall -- that whole trip is the arena script's
-- own (checkTrainingNeeded, arenaTryTrain, toTraining = { "w", "n" }, "buy
-- training"), and we deliberately don't reimplement a step of it. We only take
-- over afterwards, back in the arena, where the arena script would otherwise
-- ring the gong and fight on forever.
--
-- From the arena: "w" to the north plaza, "ne" to the tavern where the receiving
-- character is waiting, hand over the takings, then back out through the plazas
-- to the gate where the gear was staged and drop it for the next character.
--
-- Two steps here have a reply we have to read, so the pump parks on each and the
-- reply resumes it. Neither the recipient nor the amount can be a fixed string:
--
--   "ne"  the arrival prints the tavern's room brief, and the occupant line in
--         it ("Kerhak is here.") is who the gold goes to. Read rather than
--         configured, so any character can do the receiving -- see the
--         awaiting-recipient triggers below.
--   "i"   the amount to hand over is whatever the inventory says we are
--         carrying (see the awaiting-gold trigger below).
--
-- These directions retrace the arena's own routes in reverse and the creation
-- walk's outbound leg, which is a useful cross-check: "w"/"ne" is exactly
-- ARENA_NAV["1"].toBar, and "sw"/"s"/"sw" is the tavern back to the north
-- plaza, then the creation walk's "s"/"sw" to the gate.
-- The last two steps close the loop. Once the gear is on the floor and the gold
-- is in the receiver's pocket this character has nothing left worth keeping, so
-- it gets thrown away and the whole run starts over on a fresh one.
--
-- The second `i` is a gate, not a formality. Everything of value has to be out
-- of our hands BEFORE the suicide, because a suicide takes whatever is still
-- being carried with it. Reading a hard zero back from the game is the only
-- proof we have that the handover actually happened -- the give could have been
-- refused, or partly landed -- and if the number is anything else we stop rather
-- than throw the difference away. That is the same call as the no-recipient
-- stop below: never destroy something we cannot get back.
local CASH_OUT_FROM_NORTH_PLAZA = {
    { cmd = "ne", await = "recipient" },
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
-- farmPlan is defined above this table, so it reaches it through taPackage.
taPackage.cashOutFromNorthPlaza = CASH_OUT_FROM_NORTH_PLAZA
local CASH_OUT_STEPS = appendSteps({ "w" }, CASH_OUT_FROM_NORTH_PLAZA)

-- How long to wait for a reply a parked step depends on -- the tavern's room
-- brief, or the inventory's gold line -- before giving up and walking on.
-- Without this a step whose continuation depends on the server saying something
-- would park the walk in the tavern indefinitely. Generous, because the only
-- cost of waiting is a few seconds and the cost of walking on early is that the
-- takings stay in the wrong character's pocket. (Walking on from a missed brief
-- does not hand the gold to a guess: the give below stops instead when it never
-- learned who is here.)
local CASH_OUT_REPLY_WAIT_MS = 10000

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
taPackage.stopPacedWalk = createWalkStop

-- Shared teardown, so `stop-gold-farming` and `stop-all-scripts` disarm the
-- same state. Also clears a pending assessment (a stop between "Entering
-- Tele-Arena..." and the inventory reply means we no longer want it) and halts
-- a walk in progress, so one stop covers the whole gold-farming flow.
local function stopCreateCharacter()
    taPackage.creating = false
    taPackage.goldFarming = nil
    taPackage.farmAssessPending = nil
    taPackage.createRerollArmed = nil
    taPackage.createCashOutArmed = nil
    taPackage.createRestarting = nil
    createWalkStop()
end
taPackage.stopCreateCharacter = stopCreateCharacter

-- Is any part of the gold-farming flow live? It runs in phases and only the
-- first sets `creating`, so asking about that flag alone would have
-- stop-all-scripts report "not running" while a walk was mid-stride. Kept here,
-- next to the teardown, so the two can't drift apart.
--
--   creating            answering the BBS creation prompts
--   farmAssessPending   in the game, waiting on the sheet to plan the run
--   createRerollArmed   re-rolling, and this run owns the result
--   createWalk          walking: to the arena, or out to cash in
function taPackage.createCharacterRunning()
    return taPackage.creating == true
        or taPackage.goldFarming == true
        or taPackage.farmAssessPending == true
        or taPackage.createRerollArmed == true
        or taPackage.createWalk ~= nil
end

-- The one way to farm, from anywhere: the BBS login prompt, the resurrect menu,
-- or a character standing in the game. Meant to be TA_LOGIN_CMD, so it is
-- listening before the BBS asks anything -- a dead character's next login goes
-- straight to the create-a-character questions, and only an alias armed at the
-- username prompt is there to answer them. Every way back into the game after
-- that ends in the same assessment, so a disconnect at any point is recovered
-- by logging in again with the same command.
--
-- Typed in the game it re-reads the sheet and replans from where it stands,
-- which is how a run is resumed by hand.
local function farmForGold()
    -- Anything left from before belongs to an interrupted run; the assessment
    -- decides afresh.
    stopCreateCharacter()
    -- Marks the whole round trip as ours, not just the prompt-answering phase.
    -- The cash-out reads it much later to tell a `rg 1` this loop started from
    -- one somebody ran by hand -- only the former should end in a walk to the
    -- tavern and a pile of gear on the floor.
    taPackage.goldFarming = true
    if taPackage.inGame then
        taPackage.farmAssessPending = true
        send("st")
        send("i")
        echo("[farm] Farming for gold — reading the character sheet to see where the run is up to.")
        return
    end
    taPackage.creating = true
    -- echo, not cecho: cecho never reaches the session log, and "did this arm?"
    -- is the first question asked of every run that goes wrong.
    echo("[farm] Farming for gold — creating a Half-Ogre Warrior if the BBS asks,"
        .. " picking up where this one left off if not. Type stop-gold-farming to abort.")
end
createAlias("^farm-for-gold$", farmForGold, { type = "regex" })

-- Registered under every word order. "gold farming", "farming gold" and the
-- start alias's own words are all natural to reach for, and the wrong one
-- silently doing nothing looks exactly like a script that loaded but did not
-- arm.
for _, stopAlias in ipairs({ "^stop-gold-farming$", "^stop-farming-gold$", "^stop-farm-for-gold$" }) do
createAlias(stopAlias, function()
    stopCreateCharacter()
    echo("[create] Stopped.")
end, { type = "regex" })
end

-- The intro text pages on this prompt; a bare carriage return turns the page.
-- send("") is exactly that: baud's TelnetConnection.send writes `data .. "\r\n"`,
-- so an empty string puts a lone newline on the wire.
createTrigger("^<< hit return >>\\s*$", function()
    if not (taPackage.creating or taPackage.createRestarting) then return end
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

-- We are in the game, so stop answering prompts and plan the run.
--
-- Not the plan itself, yet. main.lua's handler for this same line fires `st`
-- and `i`, and their replies are still in flight when it returns; the plan
-- reads level, stats, gear and room off them. The inventory's gold line is the
-- last reply of the pair, so the assessment waits for that (see the gold
-- trigger after farmAssess below). Same reasoning, and the same landing spot,
-- as autoLogin.runInitCmd.
--
-- A fresh character and a live one take the same path: one that was just
-- created simply has a short roll and a dagger, and the plan says so.
createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    taPackage.creating = false
    if not taPackage.goldFarming then return end
    -- Whatever was in flight belongs to the connection that dropped.
    createWalkStop()
    taPackage.createRerollArmed = nil
    taPackage.createCashOutArmed = nil
    taPackage.farmAssessPending = true
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

-- For a chunk that parked a walk on its own `await` token and has dealt with the
-- reply: carry on at the normal pace.
function taPackage.resumePacedWalk()
    createWalkSchedule(CREATE_STEP_DELAY_MS)
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

    if type(step) == "table" and step.await then
        walk.awaiting = step.await
        -- Nothing may hang forever on a reply that never comes.
        local gen = taPackage.createWalkGen
        createTimer(CASH_OUT_REPLY_WAIT_MS, function()
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
-- Exposed for other chunks: a paced step list with trip/refusal recovery and an
-- optional park-on-a-reply step is general machinery, not a creation detail.
-- ta_bank.lua walks Kerhak to the vaults with it. Only one walk runs at a time
-- (a character is in one place), so a single taPackage.createWalk is enough --
-- but a step that parks must use its own `await` token, since each file only
-- answers its own (see the inventory trigger below).
--
-- `extra` is copied onto the walk before its first step, for a walk whose
-- handlers need more than the steps (the gear walk's `need`/`afterGear`).
local function createWalkStart(steps, label, doneMsg, extra)
    local walk = { steps = steps, index = 1, label = label, doneMsg = doneMsg }
    for k, v in pairs(extra or {}) do walk[k] = v end
    taPackage.createWalk = walk
    taPackage.createWalkGen = (taPackage.createWalkGen or 0) + 1
    taPackage.createWalkPump()
end
taPackage.startPacedWalk = createWalkStart

-- Decide what this character still has to do, and start doing it. Called with
-- the sheet and the room freshly read: on entering the game, after farm-for-gold
-- is typed in it, and once a re-roll lands. `prefix` goes ahead of the walk's
-- own steps (the re-roll's stop, so it comes first and visibly so).
local function farmAssess(prefix)
    if not taPackage.goldFarming then return end
    if not runCommand then
        -- Older baud (the VPS copy, say) cannot reach an alias at all. Say so
        -- rather than silently sending alias names to the server as chat.
        cecho("yellow", "[farm] this baud has no runCommand — farm-for-gold cannot drive it")
        return
    end
    -- An arena session from before would keep ringing and walking underneath
    -- whatever we decide; every plan that fights starts a fresh one.
    if taPackage.arenaState and taPackage.stopArena then
        taPackage.stopArena(nil, { quiet = true })
    end

    -- A roll short of the build gets re-rolled before anything is spent on it.
    -- Only at level 1, and only with no potions up: a potion-boosted sheet is
    -- not the roll, and a character that has trained is cashing out anyway.
    local potionsUp = (taPackage.character.getAgility() or 0) > HALF_OGRE_MAX_AGILITY
    if (taPackage.character.getLevel() or 1) < 2 and not potionsUp then
        local ch = taPackage.character
        local stats = {
            intellect = ch.getIntellect() or 0,
            knowledge = ch.getKnowledge() or 0,
            physique  = ch.getPhysique() or 0,
            stamina   = ch.getStamina() or 0,
            agility   = ch.getAgility() or 0,
            charisma  = ch.getCharisma() or 0,
        }
        local good = taPackage.reroll.builds.halfOgreWarriorFast(stats)
        if not good then
            echo("[farm] Stats short of the roll — starting re-roll-half-ogre-warrior-fast-mode.")
            -- Only a re-roll WE started may end in a walk to the arena. A
            -- hand-run re-roll-half-ogre-warrior-* is someone watching numbers go
            -- by, and having it suddenly march the character off and ring a gong
            -- would be a nasty surprise. Read by onRerollAccepted below.
            taPackage.createRerollArmed = true
            runCommand("re-roll-half-ogre-warrior-fast-mode")
            return
        end
    end

    -- After the re-roll, which stands still: only a walk needs to know the way.
    local room = taPackage.currentRoom
    if not (room and TO_NORTH_PLAZA[room]) then
        -- The re-roll's stop still has to go out, or it rolls on unattended.
        for _, cmd in ipairs(prefix or {}) do runCommand(cmd) end
        stopCreateCharacter()
        -- echo, not cecho: a run that stopped has to leave the reason in the log.
        echo("[farm] STOPPED — no route from \"" .. tostring(room) .. "\". Walk to the"
            .. " arena and run farm-for-gold again.")
        taPackage.utils.sendNtfy("Gold farming stopped", "No route from \"" .. tostring(room)
            .. "\" — the character is parked there.")
        return
    end

    local plan = farmPlan(room)
    local steps = appendSteps(appendSteps({}, prefix or {}), plan.steps)
    echo("[farm] Level " .. tostring(taPackage.character.getLevel()) .. ", " .. tostring(taPackage.character.getWeapon()) .. "/"
        .. tostring(taPackage.character.getArmor()) .. ", in the " .. room .. " — " .. plan.label .. " walk.")
    createWalkStart(steps, plan.label, plan.doneMsg,
        { need = plan.need, afterGear = plan.afterGear })
end

-- The plan waits for the entry sheet to land; see "Entering Tele-Arena..." above.
createTrigger("^You are carrying (\\d+) gold crowns", function()
    if not taPackage.farmAssessPending then return end
    taPackage.farmAssessPending = nil
    farmAssess()
end, { type = "regex" })

-- The re-roll has accepted a set of stats. main.lua calls this from the
-- Vitality trigger's accepted branch if it is defined; nothing else does.
--
-- "re-roll-stop" leads deliberately. Accepting a roll does not stop the
-- re-roller -- it bumps the generation so the pending timer no-ops, but leaves
-- taPackage.reRolling true, which is why the "Done after N rolls" message tells
-- you to stop it by hand. Left running, every status block from here on
-- (including the ones `rg 1` pulls) would be fed back through the matcher.
function taPackage.onRerollAccepted()
    if not taPackage.createRerollArmed then return end
    taPackage.createRerollArmed = nil
    cecho("cyan", "[create] Stats accepted — stopping the re-roll and carrying on.")
    farmAssess({ "re-roll-stop" })
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
    cecho("cyan", "[create] Handing the takings to whoever is in the tavern, then"
        .. " dropping the gear.")
    -- We are done with the arena: stop it before walking, or its own errand
    -- dispatch and ring pump would keep issuing commands underneath us.
    if taPackage.stopArena then taPackage.stopArena(nil, { quiet = true }) end
    createWalkStart(CASH_OUT_STEPS, "cash-out",
        "Gear dropped and the suicide sent — waiting for the BBS to start the next one.")
    return true
end

-- Who is standing in the tavern, off the brief that walking in prints. This is
-- what makes the receiving character interchangeable: the run hands its takings
-- to whoever is waiting there, rather than to a name compiled into this file.
--
-- The brief is three lines and only the middle one is about players:
--
--     There is a barkeep, and a barmaid here.   <- the room's NPCs
--     Kerhak is here.                           <- this line; we are never in it
--     There is nothing on the floor.            <- terminator, always printed
--
-- Anchoring on " is here." / " are here." is what keeps the other two out: the
-- NPC line ends in "barmaid here." and an empty room's "There is nobody here."
-- in "nobody here.", so neither can match. Two triggers rather than one with an
-- alternation because the test harness translates these patterns to Lua ones,
-- which have no alternation. (Same lines, same reasoning, as the arena's team
-- roster in main.lua -- but read on our own await token, so the two are
-- independent.)
local function cashOutNoteOccupants(matches)
    local walk = taPackage.createWalk
    if not (walk and walk.awaiting == "recipient") then return end
    -- "A", "A and B", "A, B, and C" -> a plain list. Flattening " and " to a
    -- comma leaves an empty field behind on the Oxford comma, which the
    -- emptiness check drops.
    local names = {}
    for name in (matches[2]:gsub(" and ", ", ") .. ","):gmatch("%s*(.-)%s*,") do
        if name ~= "" then names[#names + 1] = name end
    end
    walk.occupants = names
end

createTrigger("^(.+) is here\\.$", cashOutNoteOccupants, { type = "regex" })
createTrigger("^(.+) are here\\.$", cashOutNoteOccupants, { type = "regex" })

-- The floor line ends every room brief, whoever is in the room, so it is the
-- only safe terminator: the occupant line above is omitted entirely when the
-- tavern is empty of players, and waiting on a line that never comes would park
-- the walk there until the timeout (main.lua documents the same trap for the
-- arena probe).
--
-- One occupant is the whole design and anything else stops the run. Nobody there
-- is the old missing-recipient failure: the gold has to end up somewhere that
-- survives this character being replaced, so there is nothing to walk on to.
-- More than one is worse, because a guess would be a live command sending a few
-- hundred gold to whoever happened to be sitting in a public bar. Both stops
-- leave the character dressed, holding the takings, standing where the problem
-- is.
createTrigger("^There .+ on the floor\\.$", function()
    local walk = taPackage.createWalk
    if not (walk and walk.awaiting == "recipient") then return end
    walk.awaiting = nil
    local here = walk.occupants or {}
    walk.occupants = nil

    if #here == 0 then
        stopCreateCharacter()
        -- echo, not cecho: cecho never reaches the session log, and a run that
        -- stopped for a reason has to leave that reason in the log.
        echo("[cash-out] STOPPED — nobody is in the tavern to take the gold. Still"
            .. " carrying it, still wearing the gear; restart once somebody is"
            .. " waiting there.")
        taPackage.utils.sendNtfy("Gold farming stopped",
            "Nobody in the tavern to hand the takings to. The character is parked"
            .. " there with its gold and gear intact.")
        return
    end

    if #here > 1 then
        local who = table.concat(here, ", ")
        stopCreateCharacter()
        echo("[cash-out] STOPPED — more than one character is in the tavern (" .. who
            .. "), so there is no telling which one the gold is for. Still carrying"
            .. " it, still wearing the gear.")
        taPackage.utils.sendNtfy("Gold farming stopped",
            "More than one character in the tavern (" .. who .. ") — nothing was"
            .. " handed over.")
        return
    end

    walk.recipient = here[1]
    echo("[cash-out] " .. here[1] .. " is in the tavern — handing the takings over.")
    createWalkSchedule(CREATE_STEP_DELAY_MS)
end, { type = "regex" })

-- The gate's floor line, read on the gear walk's "gear" await. The steps still
-- to come are rebuilt from what is actually lying here: picked up if it is,
-- bought on the way if it is not. The walk assumed it was all here, so nothing
-- changes when it is.
createTrigger("^There .+ on the floor\\.$", function(matches)
    local walk = taPackage.createWalk
    if not (walk and walk.awaiting == "gear") then return end
    walk.awaiting = nil
    local line = matches[1]
    local floor = {
        robes = line:find("robes", 1, true) ~= nil,
        warhammer = line:find("warhammer", 1, true) ~= nil,
    }
    local need = walk.need
    local missing = {}
    if need.robes and not floor.robes then missing[#missing + 1] = "robes" end
    if need.warhammer and not floor.warhammer then missing[#missing + 1] = "warhammer" end
    if #missing > 0 then
        local steps = {}
        for i = 1, walk.index - 1 do steps[i] = walk.steps[i] end
        appendSteps(steps, gearSteps(need, floor))
        walk.steps = appendSteps(steps, walk.afterGear)
        -- echo, not cecho, so a run's gold going on gear shows up in the log.
        echo("[create] No " .. table.concat(missing, " or ")
            .. " at the gate — buying on the way to the arena.")
    end
    createWalkSchedule(CREATE_STEP_DELAY_MS)
end, { type = "regex" })

-- The inventory reply the cash-out parks on. Reading the amount from the reply
-- rather than from our own tracked gold is deliberate: the arena spends on
-- healing, food and training as it goes, so the tracked figure is only ever as
-- fresh as the last line that happened to mention gold.
createTrigger("^You are carrying (\\d+) gold crowns", function(matches)
    local walk = taPackage.createWalk
    if not walk then return end
    local awaiting = walk.awaiting
    -- Only the two tokens this file's own steps use. Another script sharing the
    -- paced walker parks on its own token and handles its own reply, so being
    -- strict here is what keeps them from stealing each other's inventory line.
    if not (awaiting == "gold" or awaiting == "zero-gold") then return end
    walk.awaiting = nil
    local amount = tonumber(matches[2]) or 0

    if awaiting == "gold" then
        if amount > 0 then
            -- No recipient means the tavern brief never arrived and the step
            -- above walked on from its timeout. Naming a guess here would be a
            -- live give of the whole harvest, so stop exactly as the empty-room
            -- case does.
            if not walk.recipient then
                stopCreateCharacter()
                echo("[cash-out] STOPPED — no room brief came back in the tavern, so"
                    .. " there is no knowing who to give the " .. amount .. " gold to."
                    .. " Still carrying it, still wearing the gear.")
                taPackage.utils.sendNtfy("Gold farming stopped",
                    "No room brief in the tavern, so the recipient is unknown."
                    .. " Nothing was handed over.")
                return
            end
            runCommand("give " .. walk.recipient .. " " .. amount .. " gold")
            -- Remembered rather than announced here. The give is a command we
            -- sent, not a handover the game has confirmed -- it can be refused
            -- (see the two stops below) or land only partly. The zero-gold gate
            -- six steps later is the proof, so that is where the notification
            -- goes out, using this figure.
            walk.handedOver = amount
            walk.handedTo = walk.recipient
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
            .. " handover to " .. (walk.handedTo or "the tavern")
            .. ", so not going through with the suicide. Hand it over yourself,"
            .. " then restart.")
        taPackage.utils.sendNtfy("Farming", "Encountered a problem. Exited game.")
        -- Leave the game rather than stand here. The gear is already on the
        -- floor, so this character has nothing to do but starve: hunger and
        -- thirst tick 1 HP each and there is no errand loop left running to feed
        -- it, so waiting to be noticed costs the gold this stop just saved.
        -- Exiting parks it at the BBS holding the takings, still alive, until
        -- the handover can be finished by hand. Same reasoning (and the same
        -- retrying "x") as arenaEmergencyExit in main.lua.
        taPackage.exitGameWithRetry()
        return
    end
    -- A hard zero: the handover landed in full, which is the only proof we get.
    -- Report the harvest for the cycle now, not when the give was sent.
    if walk.handedOver then
        taPackage.utils.sendNtfy("Farming", "Gave " .. walk.handedOver .. " gold to "
            .. (walk.handedTo or "the tavern"))
        walk.handedOver = nil
    end
    createWalkSchedule(CREATE_STEP_DELAY_MS)
end, { type = "regex" })

-- The handover found nobody to hand to. The receiver is the entire point of the
-- run -- the gold has to end up somewhere that survives this character being
-- replaced -- so this is a full stop, not something to walk on from. Carrying on
-- would drop the gear and leave the takings in the pocket of a character we are
-- about to throw away.
--
-- Still worth keeping now that the recipient is read from the room brief a step
-- earlier: the brief is a snapshot, and the receiver can walk out of the tavern
-- (ta_bank.lua takes them to the vaults) between it and the give.
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

-- A death prints the same line, and is now treated the same way. It used to
-- stop the loop, because the next character would reach a bare gate; the gear
-- walk buys what is missing now, so a death costs one character's gear and
-- takings and the run goes on. main.lua's death trigger stops every script and
-- hands the farm back through onFarmingDeath below, so goldFarming is set again
-- by the time this line arrives.
--
-- Only createRestarting is armed here, not `creating`. A death survived with a
-- soulstone prints this line and wakes in the temple, still in the game
-- (logs/session-kerhak-2026-08-09T14-48-21.log, lines 3244-3246), where a live
-- prompt-answerer would send "1"s and "6"s as commands. createRestarting only
-- answers the BBS's own "<< hit return >>" and Command prompt, and the Command
-- prompt is what turns `creating` back on, once we are certainly at the BBS.
createTrigger("^You awaken after an unknown amount of time\\.\\.\\.$", function()
    if not taPackage.goldFarming then return end
    createWalkStop()
    taPackage.creating = false
    taPackage.createRestarting = true
    if taPackage.died then
        echo("[create] Character died — starting the next one; it will buy new gear.")
    else
        echo("[create] Character retired — starting the next one.")
    end
end, { type = "regex" })

-- A farming character died. Everything it was doing has already been stopped
-- (main.lua's death trigger runs stop-all-scripts first); this only keeps the
-- run itself alive so the awakening above starts the next character.
function taPackage.onFarmingDeath()
    taPackage.goldFarming = true
end

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
    -- Certainly at the BBS now, so the creation prompts may be answered again.
    taPackage.creating = true
    send("5")
end, { type = "regex" })

-- The recipient is full. Gold has weight, and a character that only ever
-- receives it runs out of room: overnight on 2026-08-16 Kerhak reached 1323/1450
-- encumbrance after 13 handovers and refused the fourteenth
-- (logs/session-garbageman-2026-08-16T02-29-07.log line 32560).
--
-- Stop here rather than walking on. The zero-gold gate before the suicide caught
-- this last time and saved the 822 gold, but only at the end of the walk -- by
-- which point the gear was already on the floor and the failure was six steps
-- old. Stopping at the refusal itself keeps the character dressed and standing
-- where the problem is, and says plainly what to fix.
--
-- ta_bank.lua is the actual answer to this (the receiver deposits at the vaults
-- so it never fills up); this remains the backstop for when that is not running.
createTrigger("^Sorry, (\\S+) can't carry that much more gold\\.$", function(matches)
    local walk = taPackage.createWalk
    if not (walk and walk.label == "cash-out") then return end
    local who = matches[2]
    stopCreateCharacter()
    echo("[cash-out] STOPPED — " .. who .. " cannot carry any more gold. Still"
        .. " carrying the takings and still wearing the gear. Have " .. who
        .. " bank what they hold (start-banking), then restart.")
    taPackage.utils.sendNtfy("Gold farming stopped",
        who .. " is too encumbered to accept the handover. Nothing was lost --"
        .. " the character is parked with its gold and gear.")
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
    taPackage.utils.sendNtfy("Gold farming stopped",
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
    --
    -- The recipient and gear awaits are the exceptions, because what they wait
    -- for is a MOVE's own room brief: a refused "ne" never arrives in the tavern
    -- (nor a refused "sw" at the gate), so no brief is coming and the refusal is
    -- unmistakably ours. Left to the timeout the walk would `i` in the plaza and
    -- reach the give with nobody to give to, which stops a run that only needed
    -- the step retried -- or `get robes` in the wrong room.
    if walk.awaiting then
        if walk.awaiting ~= "recipient" and walk.awaiting ~= "gear" then return end
        walk.awaiting = nil
        walk.occupants = nil
    end
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
