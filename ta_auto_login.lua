-- ta_auto_login.lua -- answering the BBS login and menus for you
--
-- Loaded by main.lua with dofile, as the last thing it does: these triggers
-- (two on the same "Username:" line, and a catch-all outbound one) depend on
-- being registered after everything else in main.lua, exactly where this
-- section used to sit. Like ta_nav.lua it is a separate chunk and cannot see
-- main.lua's locals; the seam runs through taPackage:
--
--   in    taPackage.character, taPackage.inGame (main.lua)
--   out   taPackage.autoLogin (the functions), taPackage.login (the state),
--         taPackage.awaitingUsername
--
--
-- baud connects to the BBS, not to Tele-Arena: a login and two menus sit
-- between the two. `just run kerhak` exports TA_CHARACTER=kerhak (and passes
-- TA_PASSWORD through from the environment), so the script can answer the
-- whole sequence itself:
--
--     Username:                          ->  the character name
--     Password:                          ->  the password
--     (N)onstop, (Q)uit, or (C)ontinue?  ->  n   (printed twice, see below)
--     Make your selection (...):         ->  5   (Tele-Arena)
--     Entering Tele-Arena...             ->  we are in, stop answering
--
-- TA_INIT_CMD, if set, is what to run once we are in ("rg 2", say). It goes
-- through baud's runCommand, not send, so an alias actually executes; and it
-- waits for the entry character sheet to come back (see
-- taPackage.autoLogin.runInitCmd).
--
-- TA_LOGIN_CMD is its earlier sibling, and the two are not interchangeable.
-- TA_INIT_CMD promises "you are in the game and your sheet is parsed"; the only
-- thing that can deliver that promise is the entry `st`/`i` reply, which only
-- exists on the path that prints "Entering Tele-Arena...". A DEAD character
-- never takes that path: picking 5 at the main menu drops it straight onto
--
--     1) Resurect Old Character for 0 Credits.
--     2) Create New Character
--     3) Exit
--     Select an option:
--
-- and stops there. No entry line, no `st`, no `i`, no gold reply -- so
-- TA_INIT_CMD can never fire, by construction. Both paths are visible in
-- logs/session-garbageman-2026-08-15T07-30-44.log: the first "5" (line 69)
-- enters the game, the second (line 153), after a suicide, hits this menu.
--
-- TA_LOGIN_CMD runs at the front door instead, right after the username goes
-- out, so it happens on both paths. That makes it the one that can arm
-- something which has to be LISTENING before the game exists --
-- TA_LOGIN_CMD="farm-for-gold" is the case it was added for. It is for
-- arming a script, not for sending text: at the username prompt there is no
-- game to send a command to.
--
-- Every answer is sent at most once per login, because a prompt appearing
-- twice does not mean the BBS is waiting twice. "N" means *nonstop*: it tells
-- the BBS to stop pausing, so the second (N)onstop prompt -- the one after the
-- who-list -- prints without blocking for a keystroke. Answering it too sent
-- an "n" that fell through to the main menu, which rejected it ("The option
-- you have selected, "N", is not in the above list") and redisplayed itself;
-- that redisplay drew a second "5" out of us, which the BBS still held in its
-- buffer when the game started and delivered into Tele-Arena as chat. Both
-- halves of that were visible in logs/session-tojolias-2026-08-11T22-49-54.log.
--
-- The answers are also gated on login.pending, since they are actively harmful
-- once we are in the game -- a stray "n" walks the character north. Only
-- "Entering Tele-Arena..." clears that gate, and only a fresh "Username:"
-- prompt (i.e. a reconnect) re-arms it and clears the sent-once record.
-- Nothing is sent at all unless TA_CHARACTER is set, so running baud by hand
-- still logs in by hand.
taPackage.autoLogin = {}

if taPackage.login == nil then
    -- Fresh script load. A reloadScript() mid-session keeps taPackage, and so
    -- keeps a cleared `pending`, rather than re-arming these answers under a
    -- character who is standing in the arena.
    taPackage.login = { pending = true, sent = {} }
end

-- A reload of a session that predates the sent-once record still has to find
-- one here.
taPackage.login.sent = taPackage.login.sent or {}

-- Re-read on every load so a reload picks up a changed environment. getenv is
-- guarded because baud only grew it recently: an older build (the VPS copy,
-- say) would otherwise fail to load this script at all.
if getenv then
    taPackage.login.character = getenv("TA_CHARACTER")
    taPackage.login.password = getenv("TA_PASSWORD")
    -- Optional: what to do once we are in the game. Usually an alias
    -- (TA_INIT_CMD="rg 2"), which is why it is run through runCommand rather
    -- than sent. See taPackage.autoLogin.runInitCmd below for when it fires.
    taPackage.login.initCmd = getenv("TA_INIT_CMD")
    -- Optional: what to run at the login prompt, before any of the menus. The
    -- only one of the two that reaches a dead character (see above).
    taPackage.login.loginCmd = getenv("TA_LOGIN_CMD")
end

-- Run TA_INIT_CMD, once, now that the entry `st`/`i` replies have been parsed.
--
-- Timing is the whole reason this is a separate step rather than two more lines
-- in the "Entering Tele-Arena..." handler: that handler fires `st` and `i`, and
-- their replies are still in flight when it returns. Anything depending on the
-- character sheet would be refused -- "rg 2" checks taPackage.character.getClass() and bails with
-- "Class unknown - run 'st' first". The inventory's gold line is the last reply
-- of that pair, so by the time it lands the sheet is fully parsed.
-- Run one of the two login commands, naming it so the echo says which fired.
function taPackage.autoLogin.runCommand(varName, cmd)
    cecho("cyan", "[login] running " .. varName .. ": " .. cmd)
    if runCommand then
        runCommand(cmd)
    else
        -- Older baud (the VPS copy, say) has no runCommand, and send() cannot
        -- reach an alias -- it would put the literal text on the wire. A plain
        -- game command still works; say so rather than failing silently.
        cecho("yellow", "[login] this baud has no runCommand - sending as a raw command")
        send(cmd)
    end
end

function taPackage.autoLogin.runInitCmd()
    if not taPackage.login.initPending then return end
    taPackage.login.initPending = nil
    taPackage.autoLogin.runCommand("TA_INIT_CMD", taPackage.login.initCmd)
end

-- Disarm TA_INIT_CMD for the rest of this load: both the run already armed by
-- "Entering Tele-Arena..." and the one every later reconnect would arm. A
-- reloadScript() re-reads the environment, and so re-arms it.
function taPackage.autoLogin.disarmInitCmd()
    taPackage.login.initPending = nil
    taPackage.login.initCmd = nil
end

-- Answer `step` with `text`, unless we already answered it during this login.
function taPackage.autoLogin.answer(step, text)
    if not (taPackage.login.pending and taPackage.login.character) then return end
    if taPackage.login.sent[step] then return end
    taPackage.login.sent[step] = true
    send(text)
end

createTrigger("^Username:\\s*$", function()
    taPackage.awaitingUsername = true
    -- At the front door we are certainly not in the game, whatever a dropped
    -- connection left this saying. farm-for-gold, run from TA_LOGIN_CMD on the
    -- next line, reads it to decide between arming the creation prompts and
    -- sending `st` -- which at this prompt would go out as a password.
    taPackage.inGame = false
    -- A username prompt means we are at the front door again, whatever
    -- happened before it, so this is where a login starts over.
    taPackage.login.pending = true
    taPackage.login.sent = {}
    -- An init command armed by a previous login but never run (we dropped the
    -- connection before the sheet came back) belongs to that login, not this
    -- one. This login arms its own when it gets in.
    taPackage.login.initPending = nil
    if not taPackage.login.character then return end
    cecho("cyan", "[login] logging in as " .. taPackage.login.character)
    taPackage.autoLogin.answer("username", taPackage.login.character)
end, { type = "regex" })

-- TA_LOGIN_CMD, on the same prompt but as a SECOND trigger so it runs after the
-- one above: the username has already gone out by then, which matters because
-- the outbound trigger at the bottom of this file reads the next thing we send
-- as the character's name. Registered here rather than folded into the handler
-- above so that ordering is a visible property of the file, not a comment.
--
-- Not gated on TA_CHARACTER -- arming a script is just as useful when you typed
-- the username yourself -- but it IS gated on login.pending and recorded in
-- login.sent, so a re-displayed prompt cannot run it twice.
createTrigger("^Username:\\s*$", function()
    local cmd = taPackage.login.loginCmd
    if not cmd then return end
    if taPackage.login.sent["logincmd"] then return end
    taPackage.login.sent["logincmd"] = true
    taPackage.autoLogin.runCommand("TA_LOGIN_CMD", cmd)
end, { type = "regex" })

createTrigger("^Password:\\s*$", function()
    if not (taPackage.login.pending and taPackage.login.character) then return end
    if not taPackage.login.password then
        cecho("yellow", "[login] TA_PASSWORD is not set - type the password yourself")
        return
    end
    taPackage.autoLogin.answer("password", taPackage.login.password)
end, { type = "regex" })

createTrigger("^\\(N\\)onstop, \\(Q\\)uit, or \\(C\\)ontinue\\?", function()
    taPackage.autoLogin.answer("nonstop", "n")
end, { type = "regex" })

createTrigger("^Make your selection", function()
    taPackage.autoLogin.answer("menu", "5")
end, { type = "regex" })

createTrigger("^Entering Tele-Arena\\.\\.\\.$", function()
    taPackage.login.pending = false
    -- Armed here, fired later by taPackage.autoLogin.runInitCmd. Not gated on
    -- TA_CHARACTER: an init command is just as useful when you logged in by
    -- hand.
    if taPackage.login.initCmd then taPackage.login.initPending = true end
end, { type = "regex" })

createOutboundTrigger("^(.+)$", function(matches)
    if not taPackage.awaitingUsername then return end
    taPackage.awaitingUsername = false
    local username = matches[2]
    taPackage.character.setName(username:sub(1, 1):upper() .. username:sub(2))
end, { type = "regex" })
