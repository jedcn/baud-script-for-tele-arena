-- ta_kill.lua -- fighting one monster, or every monster in a room
--
-- `kill <monster>` / `k <monster>` melees (and, for a caster, casts at) one
-- target until it dies; `kill-all` / `ka` clears the room one monster at a time;
-- `kill-stop` ends either. heal-most-injured-party-member rides on the same
-- loop's group scan.
--
-- Loaded by main.lua with dofile, where the kill section used to sit. Its loop
-- triggers are registered later, by taPackage.kill.registerLoopTriggers, at the
-- spot they always were. A separate chunk; the seam runs through taPackage:
--
--   in    taPackage.character, taPackage.utils, taPackage.followedBy, ...
--   out   taPackage.kill.start / .stop / .killAllScan (ta_nav.lua, Follow,
--         stop-all-scripts), .debugEcho (Follow), .healMostInjuredPartyMember,
--         .registerLoopTriggers, and the state: taPackage.killActive,
--         killTarget, killAllActive, ...

taPackage.kill = {}


-- =========================================================================
-- Kill a single target
-- =========================================================================

-- Kill-loop debug tracing. Emits a timestamped line for each combat event and
-- decision when the loop is running in debug mode. The flag is set by `kill
-- <target> debug` directly, or inherited from a `ta.follow <name> debug` so the
-- follow's debug "follows through" into every kill it spawns (see followDebug).
local function killDebugEcho(label)
    if taPackage.killDebug or taPackage.followDebug then
        echo("[K] " .. os.date("%H:%M:%S") .. " " .. label)
    end
end
taPackage.kill.debugEcho = killDebugEcho

-- Melee: everyone swings each round, casters included.
local function killAttack()
    local target = taPackage.killTarget
    if not target then
        killDebugEcho("attack-skip: no target")
        return
    end
    if taPackage.killAttackPending then
        killDebugEcho("attack-skip: swing already pending")
        return
    end
    taPackage.killAttackPending = true
    local name = target:match("^(%S+)")
    killDebugEcho("attack-sent: a " .. name)
    send("a " .. name)
end

-- Casters take a second action each round, on a separate exhaustion clock:
-- Sorcerors blast the target. An Acolyte only melees in the kill loop; its
-- healing is heal-most-injured-party-member.
local function castSpell()
    if taPackage.castPending then
        killDebugEcho("cast-skip: cast already pending")
        return
    end
    if not taPackage.killActive then
        killDebugEcho("cast-skip: kill loop not active")
        return
    end
    if taPackage.character.isClass("Sorceror") then
        local target = taPackage.killTarget
        if not target then
            killDebugEcho("cast-skip: no target")
            return
        end
        taPackage.castPending = true
        local name = target:match("^(%S+)")
        killDebugEcho("cast-sent: toduza " .. name)
        send("cast toduza " .. name)
    end
end

-- Group healing (heal-most-injured-party-member). We send `group`, accumulate
-- each member's health as the listing streams in, and once the listing ends
-- cast kusamotu on the most-injured member (lowest HE%), if anyone is hurt.
-- Phases:
--   "want"    -- asked for the listing, waiting for the header
--   "reading" -- header seen, members are streaming in
-- The listing itself has no terminator line, so we chase it with a harmless
-- `ex` (exits). Its "Exits: ..." reply is guaranteed to arrive right after the
-- listing and is the first non-member line, which ends the reading phase — no
-- timing guesswork. Waiting for the header first means any spam arriving before
-- the listing doesn't cut the scan short.
local GROUP_HEAL_TERMINATOR = "ex"
local function beginGroupHealScan()
    taPackage.groupHealPhase = "want"
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil
    -- Tallied as the listing streams in (see the member-row trigger): total
    -- members and how many are hurt (below full). Drives the decision log in
    -- finalizeGroupHeal.
    taPackage.groupHealMembers = 0
    taPackage.groupHealHurt = 0
    send("group")
    send(GROUP_HEAL_TERMINATOR)
end

local function finalizeGroupHeal()
    taPackage.groupHealPhase = nil
    local name = taPackage.groupHealBestName
    local health = taPackage.groupHealBestHealth
    local members = taPackage.groupHealMembers or 0
    local hurt = taPackage.groupHealHurt or 0
    taPackage.groupHealBestName = nil
    taPackage.groupHealBestHealth = nil

    if members == 0 then
        echo("[heal] No group members seen, taking no action.")
        return
    end
    if hurt == 0 then
        echo(string.format("[heal] All %d allies at full health, taking no action.", members))
        return
    end
    if not name or not health then return end
    if taPackage.castPending then
        echo(string.format(
            "[heal] %d of %d allies hurt (most injured %s at %d%%), but a cast is pending — skipping.",
            hurt, members, name, health))
        return
    end
    echo(string.format("[heal] %d of %d allies hurt, healing most injured %s at %d%%.",
        hurt, members, name, health))
    taPackage.castPending = true
    send("cast kusamotu " .. string.lower(name))
end

local function startKill(target, debug)
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return false
    end
    if not taPackage.character.getClass() then
        echo("[kill] Class unknown — run 'st' first so casters cast.")
        return false
    end
    taPackage.killTarget = target
    taPackage.killActive = true
    taPackage.killDebug = debug or false
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    local debugSuffix = (taPackage.killDebug or taPackage.followDebug) and " (debug)" or ""
    echo("[kill] Attacking " .. taPackage.killTarget .. "." .. debugSuffix)
    killDebugEcho("kill-start: target=" .. target)
    killAttack()
    castSpell()
    return true
end
taPackage.kill.start = startKill

-- `kill <target>` melees (and casts) a single monster. An optional trailing
-- " debug" turns on the kill-loop trace for this fight.
local function handleKillAlias(matches)
    local rest = matches[2]
    local target, debug = rest, false
    local stripped = rest:match("^(.-) debug$")
    if stripped then
        target, debug = stripped, true
    end
    startKill(target, debug)
end

createAlias("^kill (.+)$", handleKillAlias, { type = "regex" })

-- Shorthand: `k <monster>` behaves exactly like `kill <monster>`.
createAlias("^k (.+)$", handleKillAlias, { type = "regex" })

local function stopKill()
    killDebugEcho("kill-stop")
    taPackage.killActive = false
    taPackage.killAllActive = false
    taPackage.killDebug = false
    taPackage.killTarget = nil
    taPackage.killAttackPending = false
    taPackage.castPending = false
    taPackage.groupHealPhase = nil
    taPackage.killGeneration = (taPackage.killGeneration or 0) + 1
    taPackage.killAllGeneration = (taPackage.killAllGeneration or 0) + 1
    -- A route's arrival sweep is over too; drop its bookkeeping so a later
    -- hand-run sweep can't finish and report against it.
    taPackage.navSweep = nil
    echo("[kill] Stopped.")
end
taPackage.kill.stop = stopKill

-- `kill-all` clears a room of monsters one at a time. It sends a bare return to
-- print the room brief, engages the first monster listed, and — once that
-- monster dies (see the death trigger below) — re-scans and engages the next,
-- repeating until the room holds no monster.
--
-- The occupant line names the monsters: "There is a warlock here." for one, or
-- "There are three warlocks here." / "There is a warlock, a goblin, and a rat
-- here." for several. firstArenaMonster picks the first and de-pluralises a
-- count word, so "three warlocks" -> "warlock". A player stands on their own
-- line ("Pelayo is here.") which never matches, so we only ever lock onto a
-- monster.
--
-- The scan is a self-timing probe: after sending the bare return it arms a
-- timer keyed to killAllGeneration. If no occupant line resolves the scan
-- within the window — an empty room prints "There is nobody here.", but a room
-- with players and no monster omits that line entirely — the timer fires and
-- ends the sweep so it can't hang. Locking onto a monster (or seeing "nobody")
-- bumps killAllGeneration, which cancels the pending timer.
local KILL_ALL_SCAN_MS = 2000

-- The room is clear. Both endings -- the scan timing out and the occupant line
-- reporting nobody -- go through here so anything waiting on the sweep hears
-- about it exactly once. A route that arrived and started this sweep uses the
-- hook to report what the room yielded (see the navigation section).
local function killAllDone()
    taPackage.killAllActive = false
    echo("[kill] No monster here — kill-all done.")
    if taPackage.navOnSweepDone then taPackage.navOnSweepDone() end
end

local function killAllScan()
    if not taPackage.killAllActive then return end
    local gen = (taPackage.killAllGeneration or 0) + 1
    taPackage.killAllGeneration = gen
    send("")
    createTimer(KILL_ALL_SCAN_MS, function()
        if taPackage.killAllActive and (taPackage.killAllGeneration or 0) == gen then
            killAllDone()
        end
    end, { repeating = false })
end
taPackage.kill.killAllScan = killAllScan

local function handleKillAllAlias()
    if taPackage.arenaState then
        echo("[kill] Cannot start — arena session is active.")
        return
    end
    taPackage.killAllActive = true
    killAllScan()
end

createAlias("^kill-all$", handleKillAllAlias, { type = "regex" })

-- Shorthand: `ka` behaves exactly like `kill-all`.
createAlias("^ka$", handleKillAllAlias, { type = "regex" })

-- Response to the kill-all probe: the room brief's occupant line. Engage the
-- first monster, or end the sweep when the room is clear ("nobody"). The \S+
-- matches either "is" or "are" so single and multi-monster briefs both hit.
createTrigger("^There \\S+ (.+) here\\.$", function(matches)
    if not taPackage.killAllActive then return end
    -- A scan is resolving: bump the generation to cancel its timeout.
    taPackage.killAllGeneration = (taPackage.killAllGeneration or 0) + 1
    local monster = taPackage.firstArenaMonster(matches[2])
    if monster then
        if not startKill(monster) then
            taPackage.killAllActive = false
        end
    else
        killAllDone()
    end
end, { type = "regex" })

-- A leader's kill-stop also stands the group down: a follower's kill loop
-- swings at whatever matches the target's first word, so when the monster we
-- were fighting leaves the room it keeps hitting the next one. Conferring lets
-- the leader pick the moment to move on and have everyone stop with them.
-- Only a leader confers -- followers only obey their leader, so a follower's
-- confer would reach nobody who acts on it.
-- `skill` and `sk` are shorthand.
for _, killStopPattern in ipairs({ "^kill-stop$", "^skill$", "^sk$" }) do
    createAlias(killStopPattern, function()
        stopKill()
        if not taPackage.followTarget
            and taPackage.followedBy and #taPackage.followedBy > 0 then
            send("confer kill-stop")
        end
    end, { type = "regex" })
end

-- A Leader sends its Followers after a monster and joins in: `confer-kill
-- warrior` confers `kill warrior`, which each Follower runs as its own kill
-- (see the "(to group)" trigger), then starts the Leader's own kill loop.
-- `ckill <monster>` and `ck <monster>` are shorthand.
for _, conferKillPattern in ipairs({ "^confer-kill (.+)$", "^ckill (.+)$", "^ck (.+)$" }) do
    createAlias(conferKillPattern, function(matches)
        send("confer kill " .. matches[2])
        startKill(matches[2])
    end, { type = "regex" })
end

-- Deific heal (kusamotu) on whoever has the lowest HE% in the group listing.
-- Threshold 100 so anyone short of full counts; at full health it does nothing.
-- A healer does it here. Anyone else confers the alias's own name, and a
-- healer following us answers it with the same scan (the "(to group)" trigger),
-- so one alias works whether or not the leader can heal.
function taPackage.kill.healMostInjuredPartyMember()
    beginGroupHealScan()
end

createAlias("^heal-most-injured-party-member$", function()
    if taPackage.character.isClass("Acolyte") then
        taPackage.kill.healMostInjuredPartyMember()
    else
        send("confer heal-most-injured-party-member")
    end
end, { type = "regex" })

-- =========================================================================
-- Kill loop triggers
-- =========================================================================
--
-- The game's replies that drive the kill loop above: our swings and casts
-- landing or not, the group scan for heal-most-injured-party-member, the kill
-- itself, and exhaustion.
--
-- Wrapped in a function rather than registered as this file loads, because
-- they have always been registered later than the rest of the kill code: after
-- ta_nav.lua, ta_create.lua and ta_bank.lua. The group scan below is a
-- catch-all, so it sees every line those files' triggers do (and ta_nav.lua has
-- a catch-all of its own). main.lua calls this at that spot, so the order is
-- unchanged.
function taPackage.kill.registerLoopTriggers()
    createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("our melee landed")
        taPackage.killAttackPending = false
        killAttack()
    end, { type = "regex" })

    createTrigger("^Your attack missed!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("our melee missed")
        taPackage.killAttackPending = false
        killAttack()
    end, { type = "regex" })

    createTrigger("^The .+ dodged your attack!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("monster dodged our melee")
        taPackage.killAttackPending = false
        killAttack()
    end, { type = "regex" })

    createTrigger("^You barely dodge the .+'s attack!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("we dodged the monster")
        taPackage.killAttackPending = false
        killAttack()
    end, { type = "regex" })

    -- Caster spell-outcome continuation. The DB-recording copies of these lines
    -- live in the spell section; these re-fire the cast loop independently of the
    -- melee loop above.
    createTrigger("^You discharged the spell at the .+ for \\d+ damage!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("our spell landed")
        taPackage.castPending = false
        castSpell()
    end, { type = "regex" })

    createTrigger("^You confuse the key syllables and the spell fails!$", function()
        -- Clear unconditionally: a heal (heal-most-injured-party-member) can fizzle too, and
        -- if we only cleared inside a kill the blocked cast would wedge castPending
        -- forever. Only the kill loop's re-cast needs an active fight.
        taPackage.castPending = false
        if not taPackage.killActive then return end
        killDebugEcho("our spell fizzled")
        castSpell()
    end, { type = "regex" })

    createTrigger("^Your spell was negated by the .+'s magickal defenses!$", function()
        taPackage.castPending = false
        if not taPackage.killActive then return end
        killDebugEcho("our spell was resisted")
        castSpell()
    end, { type = "regex" })

    -- "Mana too low" aborts a cast with no result line. With no handler this
    -- wedged castPending forever: heal-allies-in-loop ran Pelayo out of mana, then
    -- every scan logged "a cast is pending — skipping" and never healed again.
    -- Clears both the kill/heal guard and the arena guard, since either loop can
    -- run dry. No retry — the next scan/round casts again once mana regenerates.
    createTrigger("^Your mana is too low to cast that spell\\.$", function()
        taPackage.castPending = false
        taPackage.arenaCastPending = false
    end, { type = "regex" })

    -- The header (only when we asked for the listing) starts the reading phase;
    -- a manually-typed `group` has no pending scan, so it's left alone.
    createTrigger("^Your group currently consists of:$", function()
        if taPackage.groupHealPhase == "want" then
            taPackage.groupHealPhase = "reading"
        end
    end, { type = "regex" })

    -- While reading the listing, tally members and track the most-injured one.
    createTrigger("^\\s+(\\S+).*HE:\\s*(\\d+)%", function(matches)
        if taPackage.groupHealPhase ~= "reading" then return end
        local health = tonumber(matches[3])
        if not health then return end
        taPackage.groupHealMembers = (taPackage.groupHealMembers or 0) + 1
        if health < 100 then
            taPackage.groupHealHurt = (taPackage.groupHealHurt or 0) + 1
        end
        if not taPackage.groupHealBestHealth or health < taPackage.groupHealBestHealth then
            taPackage.groupHealBestHealth = health
            taPackage.groupHealBestName = matches[2]
        end
    end, { type = "regex" })

    -- The listing has no end marker, so the first line that is neither the header
    -- nor a member row ends the reading phase and triggers the heal. The `ex` we
    -- sent after `group` guarantees such a line ("Exits: ...") even with no other
    -- traffic.
    createTrigger("^(.+)$", function(matches)
        if taPackage.groupHealPhase ~= "reading" then return end
        local line = matches[2]
        if line:match("^Your group currently consists of:$") then return end
        if line:match("^%s+%S+.*HE:%s*%d+%%") then return end
        finalizeGroupHeal()
    end, { type = "regex" })

    createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
        if not taPackage.killActive then return end
        killDebugEcho("target dead: " .. matches[2] .. " — kill loop ending")
        taPackage.killActive = false
        taPackage.killDebug = false
        taPackage.killTarget = nil
        taPackage.killAttackPending = false
        taPackage.castPending = false
        taPackage.groupHealPhase = nil
        echo("[kill] " .. matches[2] .. " is dead.")
        -- A kill-all sweep re-scans the room for the next monster; the scan ends
        -- the sweep on its own when nothing is left.
        if taPackage.killAllActive then
            killAllScan()
        end
    end, { type = "regex" })

    createTrigger("^You are still physically exhausted from your previous activities!$", function()
        if not taPackage.killActive then return end
        killDebugEcho("physically exhausted — melee retry in 30s")
        taPackage.killAttackPending = false
        local gen = taPackage.killGeneration or 0
        createTimer(30000, function()
            if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
                killDebugEcho("melee retry firing after exhaustion")
                killAttack()
            end
        end, { repeating = false })
    end, { type = "regex" })

    createTrigger("^You are still too mentally exhausted from your last incantation!$", function()
        -- Clear the flag even out of combat (e.g. a heal-most-injured-party-member cast), so a
        -- blocked cast doesn't wedge future ones; only the retry needs a fight.
        taPackage.castPending = false
        if not taPackage.killActive then return end
        killDebugEcho("mentally exhausted — cast retry in 30s")
        local gen = taPackage.killGeneration or 0
        createTimer(30000, function()
            if taPackage.killActive and (taPackage.killGeneration or 0) == gen then
                killDebugEcho("cast retry firing after exhaustion")
                castSpell()
            end
        end, { repeating = false })
    end, { type = "regex" })
end
