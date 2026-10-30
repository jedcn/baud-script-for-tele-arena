-- ta_leave_game.lua -- getting out of the game safely
--
-- The one "x with retries" every script leaves through, and the four reasons to
-- leave without being asked: the BBS's nightly shutdown, an abandoned character
-- being ground down by thirst or poison, nothing sent for fifteen minutes, and
-- death. Tavern mode, navigation and gold farming use these, not only the arena.
--
-- Loaded by ta_arena.lua, in the middle, because that is where this code sat
-- inside main.lua: after the arena loop and before the combat triggers. Keeping
-- the spot keeps every trigger's registration order, including the two
-- catch-alls here (the abandonment counter and the idle watchdog's stamp).
--
-- A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.utils.nowMillis, taPackage.utils.trimLine (main.lua);
--         taPackage.stopArena (ta_arena.lua, defined before this file loads)
--   out   taPackage.exitGameWithRetry, taPackage.arenaEmergencyExit,
--         taPackage.checkIdle, taPackage.inGame, ...

local nowMillis = taPackage.utils.nowMillis
local trimLine = taPackage.utils.trimLine
local stopArena = taPackage.stopArena


-- =========================================================================
-- Leaving the game
-- =========================================================================

-- Leave the game with "x", and keep re-sending it until the game confirms.
--
-- "x" is treated like a move, so if we're still physically exhausted from the
-- last swing the game rejects it ("Sorry, you'll have to rest a while before you
-- can move.") — and a single unanswered "x" leaves the character sitting in the
-- game taking damage, which is the exact fate every caller of this is trying to
-- avoid. So re-send "x" every 2s until the game confirms with "Exiting
-- Tele-Arena...". A generation guard cancels an older loop if a new exit (or a
-- restarted run) supersedes it.
--
-- `firstDelayMs` holds back the first "x" -- for a caller whose own "x" is
-- already on the wire, where an immediate second one would land at the BBS
-- prompt if the first had worked.
local function exitGameWithRetry(firstDelayMs)
    local gen = (taPackage.exitGameGen or 0) + 1
    taPackage.exitGameGen = gen
    taPackage.exitGamePending = true
    local function tryExit()
        if not taPackage.exitGamePending or taPackage.exitGameGen ~= gen then return end
        -- Known to be out of the game already (the exit line, or the BBS menu,
        -- said so): nothing left to save, and at the menu "x" is the BBS's own
        -- log-off, whose "Are you sure (Y/N...)?" the next "x" does not answer.
        -- Re-sending it there looped ~340 times in
        -- session-pollux-2026-10-10T23-28-55.log. Unknown (nil) still sends.
        if taPackage.inGame == false then
            taPackage.exitGamePending = false
            return
        end
        send("x")
        createTimer(2000, tryExit, { repeating = false })
    end
    if firstDelayMs then
        createTimer(firstDelayMs, tryExit, { repeating = false })
    else
        tryExit()
    end
end
taPackage.exitGameWithRetry = exitGameWithRetry

-- =========================================================================
-- The nightly shutdown
-- =========================================================================
--
-- The BBS goes down every night for an "auto-cleanup", and warns first:
--
--     ***
--     Sorry to interrupt here, but the BBS will be shutting
--     down in 5 minutes for the nightly "auto-cleanup"
--     process.  Please finish up and log off... thank you!
--
-- repeated at 5, 4, 3, 2 and 1 minutes.
--
-- Being cut off mid-game is not free: carried gold does not survive it. On the
-- night of 2026-08-15 Kerhak was handed 10,617 gold across 13 handovers and
-- banked 5,500 of it, leaving ~5,100 on his person when the connection dropped
-- at the last warning -- and it was not there in the morning
-- (logs/session-kerhak-2026-08-15T23-39-59.log ends at line 1679, mid-warning,
-- with no exit). Leaving with "x" saves the character properly.
--
-- We answer the FIRST warning, five minutes out, because "x" is treated like a
-- move and gets refused while the physical cooldown runs -- exitGameWithRetry
-- re-sends every 2s until the game confirms, and five minutes is a comfortable
-- budget for that. Waiting for the 1-minute warning would not be.
--
-- Only the first line is matched: the second carries the countdown ("5 minutes"
-- / "1 minute") and so changes, while this one is identical every time. Fired
-- once per session -- the warning repeats five times and the retry loop is
-- already doing the work.
--
-- Not gated on any script being active. A clean exit is right whatever the
-- character was doing, including nothing.
createTrigger("^Sorry to interrupt here, but the BBS will be shutting$", function()
    if taPackage.shutdownExitSent then return end
    taPackage.shutdownExitSent = true
    if taPackage.inGame == false then
        echo("[shutdown] BBS closing for nightly maintenance — stopping everything;"
            .. " already out of the game, so nothing to save.")
    else
        echo("[shutdown] BBS closing for nightly maintenance — stopping everything"
            .. " and leaving the game (x) so the character is saved.")
    end
    taPackage.utils.sendNtfy("Nightly shutdown",
        "The BBS is closing. Scripts stopped and " ..
        (taPackage.character.getName() or "the character") .. " is leaving the game"
        .. " so nothing carried is lost.")
    -- Stop first: a walk or a fight still issuing commands fights the exit, and
    -- whatever it was doing is about to be interrupted anyway. Through the alias
    -- so a script added later is covered without touching this.
    if runCommand then runCommand("stop-all-scripts") end
    exitGameWithRetry()
end, { type = "regex" })

-- Arena mode's last-resort escape hatch. A wedged navigation walk or an
-- unserviceable thirst/hunger loop would otherwise grind the character to death
-- (see something-went-wrong.log). Leaving the game with "x" preserves the
-- character and stops all damage; tear the normal arena state down first so no
-- stale combat timer re-arms, then keep only the exit retry loop alive.
local function arenaEmergencyExit(reason)
    echo("[arena] " .. reason .. " — leaving the game (x).")
    stopArena(reason)
    exitGameWithRetry()
end
-- Published for arenaSolo, which is defined further up the file (it has to be
-- visible to beginArenaSession) and so cannot close over this.
taPackage.arenaEmergencyExit = arenaEmergencyExit

-- The game acknowledges a successful "x" with this line before dropping to the
-- BBS "<< hit return >>" prompt — the character is out of the game and safe from
-- damage. Clear the pending flag so exitGameWithRetry's retry loop stops.
--
-- And end any arena session still running: out of the game, its walk and its
-- timers can only talk to the BBS menu. Every scripted exit stops the session
-- first, so this is for an "x" nobody planned on -- one typed during a flee in
-- session-pollux-2026-10-10T23-28-55.log left the walk's next step and five
-- hours of `status` polls going to the menu.
createTrigger("^Exiting Tele-Arena\\.\\.\\.$", function()
    taPackage.exitGamePending = false
    taPackage.inGame = false
    if taPackage.arenaState then
        echo("[arena] Left the game — stopping the arena session.")
        stopArena("Left the game")
    end
end, { type = "regex" })

-- The BBS main menu means we are not in the game, however we got here. The
-- "Exiting Tele-Arena..." line covers a clean exit; this covers a dropped
-- connection, which leaves the flag set until the next login reaches the menu.
createTrigger("^Make your selection", function()
    taPackage.inGame = false
end, { type = "regex" })

-- A hand-typed "x" gets the same retry a script's exit does. "x" counts as a
-- move, so it is refused while the physical cooldown runs ("Sorry, you'll have
-- to rest a while before you can move.") -- and a refused "x" looks, to someone
-- about to walk away, exactly like a prompt that worked. That is how tojolias
-- died in session-tojolias-2026-09-22T22-49-21.log: "x" at line 376, refused,
-- "x" again, refused, `st`, and nothing more; 53 minutes later 1,978 damage from
-- a teammate's summons and a last thirst tick had killed a 2,050 HP knight.
--
-- The typed "x" is already sent, so the loop starts with a follow-up 2s later,
-- which "Exiting Tele-Arena..." cancels if the first one worked.
--
-- Only in the game: at the BBS "x" is the menu's exit, and a loop re-sending it
-- there would never see the "Exiting Tele-Arena..." that ends it. The pending
-- check is what stops exitGameWithRetry's own "x" (which baud runs through
-- outbound triggers too) from restarting the loop every 2s.
createOutboundTrigger("^x$", function()
    if not taPackage.inGame or taPackage.exitGamePending then return end
    exitGameWithRetry(2000)
end, { type = "regex" })


-- =========================================================================
-- Abandonment
-- =========================================================================
--
-- A thirst tick is the only thing the game prints for a character nobody is
-- driving: one line, roughly a minute apart, 1 HP each, forever. Three of them
-- in a row with *nothing else* on the wire means no script is walking, no
-- monster is swinging and nobody is typing -- the character has been left
-- logged in and is being ground down for no reason. Leave the game instead:
-- "x" saves the character properly, including whatever gold it is carrying,
-- which a dropped connection does not.
--
-- "Nothing else in between" is the whole of it, and is what separates this from
-- arena mode's own parched streak (ARENA_PARCHED_LIMIT, 20). That one counts
-- thirst ticks a running errand loop failed to relieve, and expects other
-- traffic between them; this one counts silence. Any other game line at all --
-- a room brief, a hit, a shout, the echo of a command we or the user sent --
-- means something is happening, and the count starts over. Blank lines and the
-- bare "> " prompt are not traffic and leave the count alone (the ticks arrive
-- separated by blank lines, see the run of seven in
-- session-2026-06-14T16-00-59.log:2084).
--
-- Hunger ticks are neutral: neither counted nor cleared. They are the same
-- "nobody is home" evidence as thirst, so letting one reset the streak would
-- keep a character alive-and-abandoned indefinitely. Thirst outnumbers hunger
-- about 50:1 in the logs, but interleaving does happen.
--
-- Poison ticks count exactly like thirst. "You're poisoned!" repeats once per
-- tick for as long as the poison lasts, in the same blank-line-separated shape,
-- and a character left standing in it is being ground down just the same: in
-- session-tojolias-2026-09-13T20-35-17.log:1085 a navigate-to arrived at town-2
-- with no cure left and eighteen poison ticks followed with nothing in between.
-- The two share one streak, since a mix of them is no less abandoned.
local ABANDONED_TICK_LIMIT = 3
local ABANDONED_TICKS = {
    ["You're thirsty."] = "thirst",
    ["You're poisoned!"] = "poison",
}

createTrigger("^(.+)$", function(matches)
    local line = trimLine(matches[2])
    if line == "" or line == ">" then return end
    if line == "You're hungry." then return end
    local tick = ABANDONED_TICKS[line]
    if not tick then
        taPackage.abandonedTickStreak = 0
        return
    end

    local streak = (taPackage.abandonedTickStreak or 0) + 1
    taPackage.abandonedTickStreak = streak
    -- Which kind of tick the run is made of, for the message: one name if it's
    -- all one kind, "thirst/poison" once they mix.
    if streak == 1 then
        taPackage.abandonedTickKind = tick
    elseif taPackage.abandonedTickKind ~= tick then
        taPackage.abandonedTickKind = "thirst/poison"
    end
    if streak < ABANDONED_TICK_LIMIT then return end

    -- Clear before leaving. exitGameWithRetry re-sends "x" every 2s until the
    -- game confirms, so the exit is already covered; without this reset a
    -- refusal ("Sorry, you'll have to rest a while...") followed by one more
    -- tick would fire the whole thing again from a streak of one.
    taPackage.abandonedTickStreak = 0
    local kind = taPackage.abandonedTickKind
    echo("[abandoned] " .. streak .. " " .. kind .. " ticks with nothing in between"
        .. " — leaving the game (x).")
    taPackage.utils.sendNtfy("Abandoned", (taPackage.character.getName() or "The character")
        .. " saw " .. streak .. " " .. kind .. " ticks with no other activity"
        .. " and left the game with x.")
    -- Same order as the nightly shutdown: stop everything first so a wedged
    -- walk or fight isn't still issuing commands into the exit, and do it
    -- through the alias so a script added later is covered without touching
    -- this.
    if runCommand then runCommand("stop-all-scripts") end
    exitGameWithRetry()
end, { type = "regex" })

-- =========================================================================
-- Idle exit
-- =========================================================================
--
-- The backstop for when the check above can't see anything. Its "nothing in
-- between" test counts silence, and a character left in a busy arena never
-- gets any: in session-tojolias-2026-09-22T22-49-21.log all 37 thirst ticks
-- were separated by a teammate's fighting, and the monsters he summoned did
-- 1,978 damage to the bystander while it sat there. Thirst only landed the
-- last point. So this watches the other direction: if nothing has been SENT
-- for IDLE_EXIT_MS -- no typed command, no script command -- nobody is driving,
-- and we leave, whatever is doing the damage.
--
-- Every command reaches the outbound trigger below, whether a script sent it
-- or it was typed (baud runs outbound triggers on send() too). A typed alias
-- that sends nothing does not, which doesn't matter: nearly every alias sends
-- something, and a 15-minute window only needs one command.
--
-- 15 minutes because the quietest script that is working as intended is tavern
-- mode, whose only traffic is a `st` every 10 minutes (TAVERN_STATUS_POLL_MS).
-- A shorter limit needs a more frequent heartbeat there. The arena makes a
-- short one worth having: at 15 minutes tojolias had lost about 1,500 of
-- 2,050 HP.
--
-- Armed on entering the game and checked every minute, and ended by
-- taPackage.inGame going false. It is not a script: stop-all-scripts
-- deliberately leaves it running, since "stop everything and walk away" is
-- exactly what it is for.
taPackage.IDLE_EXIT_MS = 15 * 60 * 1000
taPackage.IDLE_CHECK_MS = 60 * 1000

-- `drink water` is the thirst trigger's reflex, not anyone driving: counting
-- it would let every thirst tick keep an abandoned character in the game.
createOutboundTrigger("^(.*)$", function(matches)
    if matches[2] == "drink water" then return end
    taPackage.lastSentAt = nowMillis()
end, { type = "regex" })

function taPackage.checkIdle(gen)
    if not taPackage.inGame or taPackage.idleWatchGen ~= gen then return end
    local idle = nowMillis() - (taPackage.lastSentAt or nowMillis())
    if idle >= taPackage.IDLE_EXIT_MS and not taPackage.exitGamePending then
        local minutes = math.floor(idle / 60000)
        echo("[idle] No commands sent for " .. minutes .. " minutes"
            .. " — leaving the game (x).")
        taPackage.utils.sendNtfy("Idle", (taPackage.character.getName() or "The character")
            .. " sent no commands for " .. minutes .. " minutes"
            .. " and left the game with x.")
        -- Same order as the abandonment check above.
        if runCommand then runCommand("stop-all-scripts") end
        exitGameWithRetry()
    end
    createTimer(taPackage.IDLE_CHECK_MS, function() taPackage.checkIdle(gen) end,
        { repeating = false })
end

createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    taPackage.lastSentAt = nowMillis()
    taPackage.idleWatchGen = (taPackage.idleWatchGen or 0) + 1
    local gen = taPackage.idleWatchGen
    createTimer(taPackage.IDLE_CHECK_MS, function() taPackage.checkIdle(gen) end,
        { repeating = false })
end, { type = "regex" })

-- =========================================================================
-- Death
-- =========================================================================
--
-- A general facility, not an arena or gold-farming one. Any script can ask
-- whether the character has just been killed:
--
--   taPackage.died     true from the killing blow until the next entry into
--                      the game. READ it; do not clear it -- clearing hides the
--                      death from every other reader.
--   taPackage.diedAt   millisecond clock reading of the killing blow, for
--                      anything that wants to reason about how long ago.
--
-- Every long-running script is stopped automatically when it fires (through the
-- stop-all-scripts alias, so a script added later is covered the moment it is
-- registered there). A script that needs to do something of its own about a
-- death -- refuse to restart a loop, say -- reads the flag at whatever point it
-- notices, rather than racing to hook the line itself.
--
-- The flag is cleared on "Entering Tele-Arena...", i.e. once a character is in
-- the game again, which ends the episode for every reader at the same moment.

-- This is the one line the game prints that means it, and it arrives just before
-- the revive:
--
--     The flame giant exhaled a blast of flame at you for 394 damage!
--     As the final blow strikes your body you fall unconscious.
--     You awaken after an unknown amount of time...
--     You're in the temple.
--
-- (logs/session-kerhak-2026-08-09T14-48-21.log, lines 3243-3246.)
--
-- Detecting it matters because a death is nearly invisible to a running script.
-- Carrying a soulstone you wake at the temple, alive and four rooms from where
-- every state machine believes you are standing; without one you land on the BBS
-- menu. Either way the script keeps issuing arena commands into a world that has
-- moved on, which is exactly what happened during several deaths last week --
-- the scripts "just kept running even though the character was dead".
--
-- The revive line alone cannot carry this: a suicide prints it too, and the
-- gold-farming loop deliberately hangs its restart off it. Only this line
-- separates the two, so it is what sets the flag that tells them apart.
--
-- Stopping everything is the right response even though the character may be
-- alive: whatever it was doing is void, its gear and gold are gone, and quietly
-- carrying on turns one bad round into an unattended hour of nonsense.
createTrigger("^As the final blow strikes your body you fall unconscious\\.$", function()
    taPackage.died = true
    taPackage.diedAt = nowMillis()
    -- echo, not cecho: a death has to be in the session log, since the whole
    -- problem is noticing it after the fact.
    echo("[death] KILLED — stopping every script. Gear and gold are gone; you"
        .. " wake at the temple with a soulstone, or at the BBS menu without one.")
    taPackage.utils.sendNtfy("Character killed",
        (taPackage.character.getName() or "The character") .. " was killed. All scripts"
        .. " stopped. Equipment and carried gold are lost.")
    -- Read before the stop below clears it.
    local farming = taPackage.goldFarming
    -- Reuse the alias rather than reimplementing its teardown, so a script added
    -- later is covered here the moment it is added there.
    if runCommand then
        runCommand("stop-all-scripts")
    else
        cecho("yellow", "[death] this baud has no runCommand — type stop-all-scripts yourself")
    end
    -- The one exception. A farming character is disposable: dying costs its
    -- gear and its takings, and the next one buys new gear on the way out
    -- (ta_create.lua). So everything it was doing stops as above, but the run
    -- itself carries on into the next character rather than leaving an
    -- unattended session sitting at the BBS.
    if farming and taPackage.onFarmingDeath then taPackage.onFarmingDeath() end
end, { type = "regex" })
