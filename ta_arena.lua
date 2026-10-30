-- ta_arena.lua -- ring the gong and fight: the arena loop, end to end
--
-- Ringing the gong, the fight, errands to the bar, shop and temple, training
-- and promotion, team mode, and starting and stopping a session (`rg`, `tfia`).
--
-- Loaded by main.lua with dofile, at the spot this code used to sit, and it in
-- turn loads ta_leave_game.lua at the spot THAT code used to sit, between the
-- arena loop and the combat triggers. Every trigger is therefore registered in
-- exactly the order it was when all of this lived in main.lua. Several of them
-- share lines with each other and with main.lua's (catch-alls, room briefs,
-- thirst), so that order is kept rather than reasoned about.
--
-- Like ta_nav.lua, a separate chunk that cannot see main.lua's locals; the seam
-- runs through taPackage:
--
--   in    taPackage.utils.nowMillis, taPackage.healingBadge (main.lua);
--         taPackage.arenaEmergencyExit (ta_leave_game.lua)
--   out   taPackage.stopArena, taPackage.checkFleeArena (main.lua's damage
--         triggers), taPackage.firstArenaMonster (`kill`), and the arena state
--         and helpers the other files already read: taPackage.arenaState,
--         arenaHeal, arenaTryTrain, arenaWalkHomeFirst, ...

local nowMillis = taPackage.utils.nowMillis
local healingBadge = taPackage.healingBadge

-- Damage triggers want the flee decision the moment HP drops, but checkFleeArena
-- is defined with the other arena-state helpers well below its first callers.
-- Declared here, assigned there (`function checkFleeArena()`, no `local`).
local checkFleeArena


-- =========================================================================
-- Ring gong and fight in arena
-- =========================================================================

local function arenaSend(cmd)
    taPackage.arenaLastCmd = cmd
    taPackage.arenaRetryGeneration = (taPackage.arenaRetryGeneration or 0) + 1
    send(cmd)
end

local function arenaDebugEcho(label)
    if taPackage.arenaDebug then
        echo("[T] " .. os.date("%H:%M:%S") .. " " .. label)
    end
end

-- The game takes a SINGLE word as a target and prefix-matches it, so a
-- two-word monster has to be addressed by its first word only: "female troll"
-- is targeted as "female". Passing the whole name is not merely ignored — the
-- command stops being recognised at all and the line is broadcast to the room as
-- speech instead ("-- Message sent --", and everyone else reads "From Kerhak:
-- look female troll"). That is noise at best, and in team mode it spams the
-- whole party, so every command that names the monster goes through here.
local function arenaTarget(name)
    return name:match("^(%S+)")
end

-- Melee: everyone swings each round with a physical attack, casters included.
-- Only swing while actually fighting. Once flee triggers (state "fleeing"),
-- every physical action resets the game's movement cooldown, so a stray swing
-- — e.g. a stale exhaustion-retry timer firing 30s late — keeps the escape
-- move from ever landing. Gating here makes those retries no-op until we're
-- back in combat, so the queued `w` gets a clean window. (See the death in
-- logs/session-2026-06-21T11-51-45.log, where post-flee swings stalled the run.)
local function arenaAttack()
    if taPackage.arenaState ~= "fighting" then return end
    -- A support-only character is here to be hit, not to hit: see
    -- arenaTeamHeal.holdingBack. Gated here rather than at the call sites
    -- because there are a dozen of them (every re-drive trigger, the engage
    -- path, the exhaustion re-arm) and they must all fall silent together.
    if taPackage.arenaTeamHeal.holdingBack() then
        arenaDebugEcho("support-hold")
        return
    end
    local name = taPackage.arenaMonster
    if name then
        if taPackage.arenaAttackPending then return end
        taPackage.arenaAttackPending = true
        local target = arenaTarget(name)
        arenaDebugEcho("attack-sent")
        arenaSend("a " .. target)
    end
end

-- Casters take a second action each round on a separate exhaustion clock: a
-- Sorceror blasts the monster with toduza while still meleeing every round.
local function arenaCast()
    -- Like arenaAttack, casting is a combat action that resets the move clock;
    -- once we're fleeing it must cease until we're fighting again.
    if taPackage.arenaState ~= "fighting" then return end
    -- Casting is attacking: a Sorceror support gives away XP with toduza just
    -- as surely as with its sword, so it holds on the same rule.
    if taPackage.arenaTeamHeal.holdingBack() then return end
    if not taPackage.character.isClass("Sorceror") then return end
    local name = taPackage.arenaMonster
    if not name then return end
    if taPackage.arenaCastPending then return end
    taPackage.arenaCastPending = true
    local target = arenaTarget(name)
    arenaDebugEcho("cast-sent")
    arenaSend("cast toduza " .. target)
end

-- Ringing the gong is itself a physical action. Right after a melee kill the
-- physical clock is spent, so the immediate ring is rejected with "still
-- physically exhausted" — the same retry treatment the swing gets keeps the
-- loop alive. The pending guard means a stale retry timer can't double-ring.
local ARENA_RING_RETRY_MS = 3000

-- Floor, not a reckoning. The gong recovers against the last accepted SWING —
-- logs/session-pelayo-2026-08-02T14-12-42.log shows all nine acceptances landing
-- 19.0-25.5s after one, while the time since the previous ring scattered over
-- 31-79s and predicted nothing. But unlike melee that window has no constant in
-- it: one ring was accepted at 18.6s while others were still refused at 22.2s,
-- and the spread does not track the size of the burst that ended the fight
-- (r=0.22). So there is nothing here to dead-reckon.
--
-- What the data does support is a hard floor. No ring has ever been accepted
-- below 19.0s, yet the pump used to start ringing the instant the monster died
-- and retry every 3s — 56 of that session's 67 rejections came before 18s, about
-- seven guaranteed-dead commands per kill. Holding until 18s removes them
-- without risking a late summon, and the existing 3s pump then covers the
-- variable 19-25.5s window in one to three probes, the same shape as the melee
-- tail poll.
local ARENA_RING_FLOOR_MS = 18000

-- Recovering from "still physically exhausted" is dead reckoning, not a search.
--
-- The game grants a burst of swings and then refuses every physical action until
-- a fixed wall-clock timer runs out. How many swings is a property of the
-- character (class, agility, level — see docs/shrine/AGILITY.md); how long the
-- recovery takes appears to be the same for everyone. So the burst size is
-- deliberately NOT modelled here: we swing until the game says "exhausted",
-- which uses whatever the character currently has and keeps working when a
-- level-up grants another attack. The rejected swing that ends a burst is not
-- waste — it is the signal that starts this clock.
--
-- Only the recovery is predicted, and the wait is timed from the last ACCEPTED
-- swing rather than from the rejection: the server's clock started when that
-- swing resolved, and the rejection reaches us a round-trip later, so timing
-- from the rejection would start us late on every single cycle.
--
-- This replaced a blind 2s poll of the whole window, which spent ~69% of every
-- attack command it sent on rejections (744 sent / ~228 resolved in
-- logs/session-pelayo-2026-08-01T13-06-47.log — median 10 consecutive
-- rejections per cooldown, max 20). The blind poll had in turn replaced a flat
-- 30s retry, because 30s was fine solo — the monster only ever attacks us, so
-- some combat line always re-drove the loop — but not in team mode, where a
-- monster busy with a teammate prints lines that name THEM ("...misses
-- Kerhak!"), so none of our re-arm triggers fire and the fallback became the
-- actual cadence. That cost Kerhak a 30s idle mid-fight while Teekywiki solo'd
-- a stone giant (18:59:05 -> 18:59:35 in
-- logs/session-kerhak-team-fight-2026-07-25T18-58-34.log). Dead reckoning is
-- immune to that: it depends on no incoming line at all.
--
-- Fitted to logs/session-pelayo-2026-08-02T09-47-30.log, where the reckoned
-- retry landed at 28s on all eight cooldowns and the tail poll then measured the
-- real recovery at 30/32/33/35/35/36/38s (median 35). The first estimate of 30s
-- was 5s short, so every cycle paid 2-5 tail polls to cover the gap.
--
-- Aiming at 33s rather than the 35s median is the deliberate trade: firing early
-- costs one rejected command and the tail poll picks it up, firing late wastes
-- damage outright. Against that observed spread, 33s means most cooldowns are
-- caught on the first or second probe, and the two fastest (30s, 32s) start
-- 3s and 1s late — under 2% of a ~35s cycle.
--
-- n=8, so treat this as a fit rather than a constant of the game. If a later log
-- shows the tail poll consistently firing several times, it is short again.
local ARENA_PHYSICAL_COOLDOWN_MS = 35000
local ARENA_COOLDOWN_MARGIN_MS = 2000

-- Tail poll. Once the estimate says we should be recovered (or we have no recent
-- swing to reckon from — a stale timestamp makes the computed wait negative and
-- lands here), fall back to asking. Only the last seconds of the window get
-- polled, so this costs about one extra command per cooldown rather than ten.
local ARENA_EXHAUSTED_RETRY_MS = 2000

-- Milliseconds since a recorded stamp, or nil if we never recorded one. Used
-- only by the tracing below, where "we have no idea" and "it was 0ms ago" have
-- to stay distinguishable.
local function arenaSince(stamp)
    if not stamp then return nil end
    return nowMillis() - stamp
end

local function arenaSinceLabel(stamp)
    local since = arenaSince(stamp)
    return since and (since .. "ms") or "never"
end

-- Ringing is measured, not yet reckoned. The melee cooldown turned out to be a
-- fixed timer that could be dead-reckoned from the last accepted swing, and the
-- gong is plainly on some cooldown too — 55 of the 64 rings sent in
-- logs/session-pelayo-2026-08-02T11-15-31.log bounced off "still physically
-- exhausted". But the two do NOT share a clock: in
-- logs/session-pelayo-2026-08-02T09-47-30.log a ring was accepted ~19-22s after
-- a killing blow that melee was still refusing at 35s. So this traces the gong's
-- own timings — every send, every rejection, and every acceptance, each carrying
-- how long it had been since the last accepted swing and the last accepted ring
-- — and nothing here changes behaviour until those numbers say what to reckon.
local function arenaRing()
    if taPackage.arenaRingPending then return end
    -- Below the floor the gong cannot possibly answer, so don't ask. The pump
    -- re-scans on its own timer either way (arenaScanRoom arms it before any of
    -- this runs), so declining here just skips the send and the next tick tries
    -- again — it cannot wedge the summon loop. Worst case we hold for the length
    -- of the floor, because arenaLastSwingAt only moves when a swing is accepted
    -- and we are not swinging while we ring.
    --
    -- In team mode there is no fast path for a held tick to lose: every ring in
    -- company goes through the stagger (see arenaTeamRing), so holding here
    -- costs nothing beyond the hold itself.
    local sinceSwing = arenaSince(taPackage.arenaLastSwingAt)
    if sinceSwing and sinceSwing < ARENA_RING_FLOOR_MS then
        arenaDebugEcho("ring-held  since-swing " .. sinceSwing .. "ms")
        return
    end
    taPackage.arenaRingPending = true
    arenaDebugEcho("ring-sent  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
        .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
    arenaSend("ring gong")
end

-- =========================================================================
-- Team mode: one monster, several characters
-- =========================================================================
-- Several characters share an arena and must summon exactly ONE monster between
-- them. Four clients that all see an empty room and all ring at once produce
-- four monsters, which is how a party gets killed.
--
-- The coordination runs entirely through the game, because the game already
-- provides both halves of it. Rings are broadcast to everyone in the arena
-- ("Castor just rang the great gong!"), which makes them a shared, serialized
-- lock; and the brief the probe prints names everyone standing here, which gives
-- every client the same roster to order itself against. So:
--
--   * each character waits (its position in the roster) x GAP before ringing
--   * seeing anyone else's ring cancels its pending ring (see the gong triggers)
--   * a spawn is adopted whoever rang it (see arenaAdoptSummon)
--
-- In the steady state only the first character in the order sends anything at
-- all; the rest never reach their timer. Nobody is designated the leader, which
-- matters because characters constantly walk out for potions, healing, drink and
-- training — a leader would take the whole team idle with it. Instead the
-- absentee simply stops appearing in the brief, and whoever is now first rings
-- on the very next probe. A roster of one is exactly the solo behaviour.
--
-- The gap wants to be comfortably longer than the round trip for a ring to be
-- echoed back to everyone, so that the runner-up has really seen the winner's
-- ring before its own timer fires.
local ARENA_TEAM_RING_GAP_MS = 2000

-- =========================================================================
-- Hold the gong while a team-mate is escaping
-- =========================================================================
-- Fleeing is decided instantly but takes time to carry out: checkFleeArena
-- flips us to "fleeing" the moment HP crosses the threshold, yet the character
-- is still standing in the arena until a move actually lands, and the move can
-- be refused for several seconds ("You cannot leave in the heat of battle!",
-- "Sorry, you'll have to rest a while before you can move.").
--
-- That opens a lethal window in team mode. Say a character flees at 401 HP after
-- a flame giant hit; a team-mate lands the killing blow a second later and,
-- being slot 0 on the first attempt of the cycle, rings immediately — well
-- inside the 2s retry cadence of the escape. The fresh summon then gets a free
-- round against someone with 31 HP who is still trying to walk out. Nothing in
-- the roster machinery prevents this: the fleeing character is still listed in
-- the brief, so its presence only orders the ring rather than suppressing it.
--
-- The fix uses the channel the team already coordinates over — the game itself.
-- An unrecognised command is broadcast to the room as speech, which everyone
-- else reads as "From <name>: <text>", so a plain say is a room-scoped broadcast
-- every client sees. A fleeing character announces arenaTeamHeal.NEED_MSG, and
-- anyone who hears it holds the gong until that character says
-- arenaTeamHeal.HEALED_MSG on its way back in.
--
-- Room-scoped is the whole point, and also the trap: the all-clear MUST be said
-- from the arena (arenaArrivedHome), never at the temple, which is four rooms
-- away and out of earshot of everyone who needs to hear it.
--
-- Gathered into one table rather than the half-dozen file-scope locals this
-- would naturally be: main.lua is a single Lua chunk and Lua caps a chunk at 200
-- locals, which it was already close enough to that adding them individually
-- overflowed it ("too many local variables"). One table costs one slot.
local arenaTeamHeal = {
    NEED_MSG = "I need healing",
    HEALED_MSG = "I am healed",
}

-- Published so arenaAttack and arenaCast can reach it. They are defined further
-- UP the file than this table, so the local above is not in scope for them and
-- the bare name would compile to a nil global. Going through taPackage is the
-- same forward-reference dodge taPackage.arenaTryTrain and
-- taPackage.arenaEmergencyExit already use, and it costs no local slot.
taPackage.arenaTeamHeal = arenaTeamHeal

-- Entries are timestamps, not booleans, so the hold is a lease that expires
-- rather than a flag that can get stuck on. A character that dies mid-escape,
-- disconnects, or is stopped by hand never says the all-clear, and a plain
-- boolean would idle the whole team indefinitely waiting for it — a worse
-- failure than the death we're preventing, and a quieter one, because an idle
-- arena looks like a team waiting politely. The same reasoning already governs
-- the ring-yield trigger, which re-arms a pump tick rather than trusting that a
-- summon it stood down for will really arrive.
--
-- The lease has to outlast the whole episode on the strength of a single
-- announcement, because the escapee says this exactly once (see announceNeed).
-- The long pole is not the walk to the temple — 4 paced steps each way plus
-- "buy healing", call it 15s — but the wait to get out of the arena at all: the
-- heat-of-battle guard refuses every step until the monster is dead, so a slow
-- kill pins the escapee in the room for as long as the fight lasts.
--
-- 180s covers that with room to spare. Erring long is deliberate: a lease that
-- lapses while the character is still standing there hurt re-opens the exact
-- window this exists to close, whereas one that outlives a character who died
-- mid-escape only costs the team some idle time.
arenaTeamHeal.LEASE_SEC = 180

-- Name (lowercased) -> os.time() of the most recent "I need healing" heard.
function arenaTeamHeal.leases()
    taPackage.arenaTeamHealing = taPackage.arenaTeamHealing or {}
    return taPackage.arenaTeamHealing
end

-- Who, if anyone, is currently escaping. Drops expired leases as it goes so the
-- table can't grow without bound over a long session. Returns the name of a
-- live lease (for the debug echo), or nil when the gong is free.
function arenaTeamHeal.holder()
    local leases = arenaTeamHeal.leases()
    local now = os.time()
    local holder = nil
    for name, at in pairs(leases) do
        if now - at >= arenaTeamHeal.LEASE_SEC then
            leases[name] = nil
        else
            holder = holder or name
        end
    end
    return holder
end

-- Should a support-only character keep its sword down right now?
--
-- `support-only` (see parseArenaAliasArgs) is for the team shape where two
-- characters stand in the arena purely as extra bodies for the monster to split
-- its attacks across, so all the XP goes to the third. XP here is awarded by
-- damage share, so the only way to give it away is to not swing.
--
-- The exception is the emergency this whole section exists for. The heat-of-
-- battle guard refuses every movement command until the monster is dead, so a
-- team-mate below its flee threshold is pinned in the room taking full rounds
-- until someone kills the thing. That is worth every point of XP it costs, and
-- the announcement that opens the hold is exactly the signal that says so — so
-- the assist rides the same lease the gong hold does, and inherits its expiry
-- for free. A support that never hears the all-clear (the announcer died, or
-- dropped its connection) stands back down after LEASE_SEC rather than swinging
-- for the rest of the session.
function arenaTeamHeal.holdingBack()
    if not taPackage.arenaSupportOnly then return false end
    return arenaTeamHeal.holder() == nil
end

-- How long everyone else keeps off the gong after hearing an all-clear.
--
-- The all-clear un-freezes every held client at once, which makes it the one
-- instant in a cycle where all of them are guaranteed to reach a ring decision
-- together — and the ring order separates them by ARENA_TEAM_RING_GAP_MS, which
-- is about what a gong broadcast takes to come back round. That is how close the
-- 17:32:38 double-summon ran: Teekywiki said "I am healed" at 17:32:35, its own
-- ring landed at 17:32:37, and Kerhak's came at 17:32:38 off the very tick that
-- released the hold.
--
-- The character that just announced is standing in the arena at full HP and is
-- the one the next summon is for, so give it the first ring outright instead of
-- racing it for one. It never hears its own announcement — the game echoes our
-- own speech as "-- Message sent --", not "From <us>: ..." — so it is exempt for
-- free, and needs no special case here.
--
-- Reckoned in milliseconds off nowMillis rather than os.time, whose one-second
-- resolution would make a "4 second" grace anywhere from 3.0 to 4.0 — no way to
-- size a window whose whole job is to cover a sub-second race.
--
-- Declining is safe for the same reason the gong hold is: the pump that got us
-- here has an outstanding re-scan, so we just re-decide in a moment. If the
-- returning character never rings after all — it died on the way back, or was
-- stopped by hand — the grace lapses and the ordinary order takes over.
arenaTeamHeal.GRACE_MS = 4000

function arenaTeamHeal.beginGrace()
    taPackage.arenaRingGrace = nowMillis() + arenaTeamHeal.GRACE_MS
end

function arenaTeamHeal.inGrace()
    local expiry = taPackage.arenaRingGrace
    return expiry ~= nil and nowMillis() < expiry
end

-- Announce that we are escaping — once per flee, however long the escape takes.
-- The announcement flag doubles as the guard: it is set here and cleared only by
-- the all-clear, so every later call inside the same episode is a no-op, while a
-- second flee later in the session announces again as it should.
--
-- Deliberately NOT sent through arenaSend: that records arenaLastCmd for the
-- blocked-move retries, and stamping the announcement there would make the next
-- retry re-say the message instead of re-walking the step we're trying to escape
-- on. Team mode only — solo, this would just be talking to ourselves.
function arenaTeamHeal.announceNeed()
    if not taPackage.arenaTeam then return end
    if taPackage.arenaAnnouncedNeedsHealing then return end
    taPackage.arenaAnnouncedNeedsHealing = true
    send(arenaTeamHeal.NEED_MSG)
end

-- Release the hold, from inside the arena. Guarded on having actually announced
-- so the ordinary errand returns (bar, magic shop, guild hall) — which share
-- arenaArrivedHome with the heal return — stay silent.
function arenaTeamHeal.announceHealed()
    if not taPackage.arenaAnnouncedNeedsHealing then return end
    taPackage.arenaAnnouncedNeedsHealing = false
    if not taPackage.arenaTeam then return end
    send(arenaTeamHeal.HEALED_MSG)
end

-- =========================================================================
-- Leaving when the team is gone (`tfia <n> exit-if-solo`)
-- =========================================================================
--
-- A team can be built out of characters that could not each survive the arena
-- alone: two who can solo a stone giant carry a third who cannot. That is the
-- point of team mode, and it is also its failure mode — if the two strong
-- characters drop their connections, wander off on a potion errand and get
-- lost, or die, the weak one keeps swinging at something that will kill it, and
-- nothing in the engine notices.
--
-- `exit-if-solo` is the answer: having been alone in the arena for EXIT_MS,
-- leave the game with "x". Being wrong is nearly free — the character is saved
-- and safe, it has only stopped earning — while being right saves it outright,
-- so this leans deliberately towards leaving.
--
-- Everything lives on one table rather than as file-scope locals: main.lua's
-- main chunk is close to Lua's 200-local ceiling (see CLAUDE.md), and a table
-- field costs no slot. Same shape as arenaTeamHeal above.
local arenaSolo = {}

-- Alone this long and we leave. One minute, as asked for. Be aware that an
-- arena-3 errand is a paced walk of ~10 rooms each way (ARENA_STEP_DELAY_MS)
-- plus the purchase, so a team-mate buying potions is legitimately out of the
-- arena for something close to this and will occasionally trip it. Raise it
-- here if the false exits become more annoying than the risk they cover.
arenaSolo.EXIT_MS = 60000

-- How often we look. Deliberately slow: between fights the scan pump is already
-- refreshing the roster every ~3s and this only reads it, and during a fight
-- each tick costs one bare return. At 20s the worst case is one poll of
-- lateness on a 60s threshold.
arenaSolo.POLL_MS = 20000

-- Published so the tests drive the timer and the threshold by name rather than
-- by literal, the way arenaStepDelayMs already is.
taPackage.arenaSolo = arenaSolo

function arenaSolo.minutesLabel()
    local minutes = arenaSolo.EXIT_MS / 60000
    -- "1 minute" reads better than "1.0 minutes", and a threshold under a
    -- minute should not claim to be "0 minutes".
    if minutes == math.floor(minutes) then
        minutes = math.floor(minutes)
        return minutes .. (minutes == 1 and " minute" or " minutes")
    end
    return string.format("%.1f minutes", minutes)
end

-- Somebody else is demonstrably here. Any signal at all may call this; only
-- arenaSolo.poll below is ever allowed to conclude the opposite. Keeping the
-- evidence one-directional per source is what makes this safe to feed from
-- several unrelated triggers: a missed signal costs a slower detection, never a
-- wrong one.
function arenaSolo.sawCompany()
    if not taPackage.arenaExitIfSolo then return end
    if not taPackage.arenaSoloSince then return end
    arenaDebugEcho("solo-clock-reset")
    taPackage.arenaSoloSince = nil
end

-- One settled observation of the arena's population. `count` is how many other
-- players the brief listed.
function arenaSolo.observe(count)
    if not taPackage.arenaExitIfSolo then return end
    if count > 0 then
        arenaSolo.sawCompany()
        return
    end
    if not taPackage.arenaSoloSince then
        taPackage.arenaSoloSince = nowMillis()
        arenaDebugEcho("solo-clock-started")
        return
    end
    local alone = nowMillis() - taPackage.arenaSoloSince
    if alone < arenaSolo.EXIT_MS then
        arenaDebugEcho("solo-alone-" .. alone .. "ms")
        return
    end
    local reason = "Alone in the arena for " .. arenaSolo.minutesLabel()
        .. " — too weak to fight solo"
    taPackage.utils.sendNtfy("Left the arena alone",
        (taPackage.character.getName() or "The character") .. " was alone in arena "
        .. (taPackage.arenaProfile or "?") .. " for " .. arenaSolo.minutesLabel()
        .. " and has left the game.")
    -- Looked up on taPackage rather than closed over: arenaEmergencyExit is
    -- defined further down the file, past beginArenaSession, which has to be
    -- able to see this table.
    taPackage.arenaEmergencyExit(reason)
end

-- The heartbeat. There is no repeating timer and no cancel API in this script —
-- recurrence is re-arming from the callback, cancellation is a generation bump
-- (see arenaScanRoom and scheduleArenaXpCheck) — so this follows suit.
--
-- Re-arming happens first and unconditionally, before any of the state gates
-- below. An errand or a lull must not be able to end the chain: the whole run
-- would then be silently unprotected for the rest of its life, in a session
-- that otherwise looks healthy.
function arenaSolo.poll()
    local gen = taPackage.arenaSoloGen or 0
    createTimer(arenaSolo.POLL_MS, function()
        if (taPackage.arenaSoloGen or 0) ~= gen then return end
        if not taPackage.arenaExitIfSolo then return end
        arenaSolo.poll()
        arenaSolo.tick()
    end, { repeating = false })
end

function arenaSolo.tick()
    local st = taPackage.arenaState
    -- Out on our own errand: we cannot see the arena from the magic shop, and
    -- must not bank solitude while we are the ones who are absent. A journey is
    -- checked as well as the state because the walk home runs as "returning"
    -- and the last steps of it are still nowhere near the arena.
    if (st ~= "fighting" and st ~= "ringing") or taPackage.arenaJourney then
        if taPackage.arenaSoloSince then
            arenaDebugEcho("solo-clock-paused-away")
            taPackage.arenaSoloSince = nil
        end
        return
    end
    if st == "ringing" then
        -- The scan pump probes every ~3s in this state, so the roster is fresh
        -- and asking again would only add traffic. But skip a tick that lands
        -- while a probe is in flight: arenaScanRoom empties the roster as it
        -- sends, so we would be reading a blank that means "not answered yet",
        -- not "nobody here".
        if taPackage.arenaProbePending then
            arenaDebugEcho("solo-tick-skipped-mid-probe")
            return
        end
        arenaSolo.observe(#(taPackage.arenaTeamRoster or {}))
        return
    end
    -- Fighting. The scan pump stopped the moment we engaged, so nothing is
    -- refreshing the roster — and this is exactly the state in which being left
    -- alone is fatal. Ask for the brief ourselves. Our own pending flag, not
    -- arenaProbePending, so the ring machinery (which gates on that one) stays
    -- dormant and cannot engage a monster or ring a gong off the back of it.
    taPackage.arenaSoloProbePending = true
    taPackage.arenaTeamRoster = {}
    arenaDebugEcho("solo-probe-sent")
    send("")
end

-- Start (or restart) the heartbeat, invalidating any earlier one.
function arenaSolo.arm()
    taPackage.arenaSoloGen = (taPackage.arenaSoloGen or 0) + 1
    if not taPackage.arenaExitIfSolo then return end
    arenaSolo.poll()
end

-- Our place in the ring order: how many of the other characters here sort before
-- our name. Counting rather than sorting sidesteps the question of whether we
-- appear in our own roster (we don't — the game omits us from the brief) since
-- an equal name is not "before" us either way.
local function arenaTeamRingSlot()
    local me = taPackage.character.getName()
    -- Without a name we can't place ourselves, so take the front of the order and
    -- behave like solo. Ringing a beat early is recoverable; never ringing is not.
    if not me then return 0 end
    local ahead = 0
    for _, other in ipairs(taPackage.arenaTeamRoster or {}) do
        if other:lower() < me:lower() then ahead = ahead + 1 end
    end
    return ahead
end

-- Ring, but only after letting everyone ahead of us go first.
--
-- In company EVERY character takes the timer path, slot 0 included. Slot 0 used
-- to ring immediately on the first attempt of a summon cycle, and that fast path
-- is what killed Teekywiki at 17:32:38 in
-- logs/session-teekywiki-2026-08-28T16-10-31.log:11175. Kerhak had been holding
-- the gong for 19s while Teekywiki healed; the hold returned before the attempt
-- counter was touched, so the tick that followed the all-clear still looked like
-- the first of the cycle and rang with no stagger at all. It landed one second
-- behind Teekywiki's own staggered ring — inside the round trip of the gong
-- broadcast, so the yield arrived after the send was already on the wire. Two
-- monsters, 516 damage in one exchange against a 476 HP pool, and the 376k XP
-- the session had earned went with the corpse.
--
-- Counting the held ticks more honestly would not have saved it. What the fast
-- path loses to is a network race, not a bookkeeping error: a ring already sent
-- has nothing left to cancel, and only a pending timer does — which is exactly
-- what arenaRingGen calls off when someone else's ring is heard. So in company
-- we always arm one. It costs whoever is first in the order one gap (~2s) per
-- summon cycle, against ~90s cycles.
--
-- A character genuinely alone (empty roster) still rings immediately: there is
-- nobody to collide with, and the wait would just be dead time.
--
-- The stagger is (slot + 1) gaps, not max(slot, 1), which put slots 0 and 1 on
-- the SAME 2s schedule — the exact pairing (Kerhak 0, Teekywiki 1) that
-- collided, and useless as a tie-break the moment both tick together. Each slot
-- now gets its own instant, and every one of them still lands a full gap inside
-- that slot's own pump re-scan (ARENA_RING_RETRY_MS + slot gaps, arenaScanRoom),
-- so the re-scan can never outrun our turn.
local function arenaTeamRing()
    -- Someone is escaping at low HP: don't summon a monster on top of them.
    -- Returning without ringing is all it takes — the scan pump that got us here
    -- has an outstanding re-scan timer (ARENA_RING_RETRY_MS, ~3s) which is not
    -- invalidated by declining, so we simply probe again in a moment and
    -- re-evaluate. Reusing the pump rather than adding a second timer also means
    -- each retry re-derives the roster, and keeps the ring generation the single
    -- thing that owns ring liveness.
    --
    -- Only the gong is held. A monster already in the room is still engaged
    -- normally — the probe's occupant trigger reaches arenaEngage without ever
    -- coming through here — so holding the gong never leaves the team standing
    -- idle next to something that is already hitting them.
    local holder = arenaTeamHeal.holder()
    if holder then
        arenaDebugEcho("team-ring-held-for-" .. holder)
        return
    end
    -- Somebody has just called the all-clear on a heal trip and has first claim
    -- on the gong: see arenaTeamHeal.beginGrace.
    if arenaTeamHeal.inGrace() then
        arenaDebugEcho("team-ring-grace")
        return
    end
    local slot = arenaTeamRingSlot()
    taPackage.arenaTeamSlot = slot
    arenaDebugEcho("team-ring-slot-" .. slot)
    if #(taPackage.arenaTeamRoster or {}) == 0 then
        arenaRing()
        return
    end
    -- Guarded on the ring generation, which is what the observed-ring triggers
    -- bump to call this off when someone ahead of us rings first.
    local gen = taPackage.arenaRingGen or 0
    createTimer((slot + 1) * ARENA_TEAM_RING_GAP_MS, function()
        if taPackage.arenaState ~= "ringing" then return end
        if (taPackage.arenaRingGen or 0) ~= gen then return end
        arenaDebugEcho("team-ring-turn")
        arenaRing()
    end, { repeating = false })
end

-- The arena brief lists occupants as "There is a hobgoblin, a huge rat, and a
-- female kobold here." Pull the first monster's name so we can engage it. The
-- leading word is an article ("a"/"an"/"the") or a count ("two huge rats"); a
-- count means a plural noun, which we reduce to the singular the death line
-- ("The huge rat falls...") and our attack target use.
local ARENA_ARTICLE_WORDS = {
    a = true, an = true, the = true,
    two = true, three = true, four = true, five = true, six = true,
}
-- Reduce a plural monster noun to its singular -- the form the death line
-- ("The ogress falls to the ground lifeless!") and our attack target both use.
-- Sending the plural back gets `Sorry, you don't see "ogresse" nearby.` and the
-- kill scan then retries it forever (logs/session-tojolias-2026-09-13T19-09-40.log
-- line 422, on "There are two ogresses here."), so the rules below are driven by
-- the names actually in the monsters table rather than by English at large:
--
--   -women/-men  "lizard men" -> "lizard man", "swordswomen" -> "swordswoman"
--   -ves         "wolves" -> "wolf"
--   -es          only after a sibilant, where the plural needs the extra vowel:
--                "ogresses" -> "ogress", "foxes" -> "fox". Stripping "es"
--                unconditionally would give "ogre mages" -> "ogre mag".
--   -s           the common case: "dragons" -> "dragon"
--   -i           "affreeti" -> "affreet", "efreeti" -> "efreet"
--
-- A noun whose SINGULAR already ends in "s" is returned untouched, because every
-- rule above damages it: "ogress" and "ice giantess" end in "ss", and "cyclops"
-- is its own plural.
local function singularizeMonster(noun)
    if noun:match("women$") then
        return (noun:gsub("women$", "woman"))
    elseif noun:match("men$") then
        return (noun:gsub("men$", "man"))
    elseif noun:match("ss$") or noun:match("cyclops$") then
        return noun
    elseif noun:match("ves$") then
        return (noun:gsub("ves$", "f"))
    elseif noun:match("[sxz]es$") or noun:match("[cs]hes$") then
        return (noun:gsub("es$", ""))
    elseif noun:match("s$") then
        return (noun:gsub("s$", ""))
    elseif noun:match("i$") then
        return (noun:gsub("i$", ""))
    end
    return noun
end
local function firstArenaMonster(contents)
    if not contents or contents == "nobody" then return nil end
    local first = (contents:match("^([^,]+)") or contents):match("^%s*(.-)%s*$")
    local article, rest = first:match("^(%S+)%s+(.+)$")
    if article and ARENA_ARTICLE_WORDS[article:lower()] then
        local a = article:lower()
        if a ~= "a" and a ~= "an" and a ~= "the" then
            rest = singularizeMonster(rest)
        end
        return rest
    end
    return first
end
taPackage.firstArenaMonster = firstArenaMonster

-- Before ringing for a fresh monster, send a bare return to print the arena
-- brief and see who is already here. Sending "look" only re-prints the room
-- description (no occupants); an empty line is the only way to list them. The
-- arena is shared and a monster we lost track of — or one another player
-- summoned — may already be present. Ringing on top of it stacks a second
-- monster on us, the orphaned-monster trap that gets characters killed, so we
-- adopt whatever is here and only ring once the room is clear.
--
-- This is a SELF-HEALING PUMP, not a one-shot. Each scan arms a follow-up
-- timer keyed to arenaRingGen; if the scan doesn't resolve into a fight within
-- the window — brief lost, ring bounced on "physically exhausted", or the room
-- churned by the other player sharing it — the next tick simply scans again.
-- The loop can therefore never get wedged in "ringing" doing nothing (the
-- earlier deadlock: a dropped retry left the character idle, see
-- logs/session-pollux-2026-06-28T16-09-01.log). arenaEngage bumps arenaRingGen
-- the instant we lock onto a monster, which stops the pump.
--
-- In team mode the pump has to outlast our wait for a turn to ring, because
-- re-scanning bumps arenaRingGen and that is exactly what cancels a pending
-- ring. At the fixed 3s a character in slot 2 (4s of stagger) would be re-probed
-- before its turn ever came and would never ring at all — so widen the window by
-- our own stagger. The slot is the one the last probe worked out; on the very
-- first probe of a session it is 0, so a character deep in the order can lose
-- one cycle before the window catches up. That self-corrects immediately and
-- keeps the pump's anti-wedge guarantee intact.
local function arenaScanRoom()
    if taPackage.arenaState ~= "ringing" then return end
    local gen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaRingGen = gen
    taPackage.arenaProbePending = true
    taPackage.arenaRingPending = false
    -- Each probe re-learns who is in the arena from scratch, so a character that
    -- has walked out on an errand stops holding a slot in the ring order.
    taPackage.arenaTeamRoster = {}
    send("")
    local retryMs = ARENA_RING_RETRY_MS
        + (taPackage.arenaTeamSlot or 0) * ARENA_TEAM_RING_GAP_MS
    createTimer(retryMs, function()
        if taPackage.arenaState == "ringing" and (taPackage.arenaRingGen or 0) == gen then
            arenaScanRoom()
        end
    end, { repeating = false })
end

-- Lock onto a single monster and start swinging. Shared by the gate-spawn path
-- (a monster we just summoned) and the room-scan path (a monster already here).
local function arenaEngage(name)
    -- Halt the scan pump: any outstanding tick guards the prior arenaRingGen.
    taPackage.arenaRingGen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaMonster = name
    taPackage.arenaState = "fighting"
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    -- First sighting of this monster: grab its description for the bestiary. The
    -- name we store comes from the game's own reply ("The female troll seems to
    -- be in good physical health."), not from what we typed, so addressing it by
    -- the single-word target still files it under its full name.
    if not taPackage.db.monsterHasDescription(name) then
        send("look " .. arenaTarget(name))
    end
    arenaAttack()
    arenaCast()
end

-- Return to combat after a trip out of the arena (heal or bar). Shared by both
-- arenas' "arrived back at the arena" paths: resume swinging at the monster we
-- left if it survived, otherwise scan the room and ring for a fresh one.
local function arenaResumeInCombat()
    if taPackage.arenaMonster then
        taPackage.arenaState = "fighting"
        taPackage.arenaAttackPending = false
        taPackage.arenaCastPending = false
        arenaAttack()
        arenaCast()
    else
        taPackage.arenaState = "ringing"
        taPackage.arenaRingPending = false
        arenaScanRoom()
    end
end

-- =========================================================================
-- Arena routes and the paced journey walker
-- =========================================================================
-- Some destinations are several rooms away, and moving between them too fast
-- makes the character fall down. A "journey" walks such a route one step at a
-- time: an explicit list of directions plus the room that ends it. We send the
-- first step, then advance one step per room line we receive, pausing
-- ARENA_STEP_DELAY_MS between steps. Every leg in every arena is a journey:
-- temple, bar, magic shop, guild hall. All three arenas name rooms alike
-- ("arena", "temple"), so a journey is driven by its own step list and never by
-- matching a waypoint's name.
-- 1500ms, the same pace navigate-to settled on, and for the same reason. That
-- was tuned by measurement rather than guesswork: at 1000ms a paced walk tripped
-- 4 times in 60 moves (6.7%, against a 1.13% baseline over the 72,354 hand-typed
-- moves in the archived logs), 1200 and 1300 both still tripped, and 1500 has
-- since carried 250-odd scripted moves -- including a single 103-step walk --
-- without one. These journeys move the same character through the same game, so
-- there is no reason they should be paced faster than the pace we know works.
local ARENA_STEP_DELAY_MS = 1500
-- When a step is rejected because we moved too fast ("In your haste, you trip
-- and fall!"), no room line is printed, so the step-driven walk would stall
-- forever waiting for a room it never enters. Re-send the current step after a
-- longer pause than the normal pacing to both recover the walk and back off.
local ARENA_TRIP_RETRY_MS = 2000
-- Exposed so tests catch the pacing timer by name rather than by a literal
-- interval, which silently stops matching the moment the pace is retuned.
taPackage.arenaStepDelayMs = ARENA_STEP_DELAY_MS
local ARENA_ROOM = "arena"
-- Consecutive unrelieved thirst/hunger ticks before we give up and leave the
-- game. Each tick drains ~1 HP; a healthy loop rings the gong or buys a drink
-- between ticks (both reset the streak), so reaching this many in a row means
-- the errand loop is wedged. 20 is far above any normal bar round-trip yet bails
-- with a large HP margin (something-went-wrong.log still had ~200/318 after 20
-- minutes stuck).
local ARENA_PARCHED_LIMIT = 20
-- Per-profile navigation: each arena's temple, bar and (where it has one)
-- guild hall, reached by a fixed direction step-list walked one paced step at a
-- time. arenaNav() returns the active profile's config. All three arenas are in
-- here now, so every leg is paced and every leg has trip recovery.
--
-- A profile is the arena's number as a string, "1"/"2"/"3" — the same word the
-- aliases take, so there is one vocabulary for the arenas and not two.
--
-- Every arena trains now, so every profile carries a toTraining/fromTraining
-- route and a trainingRoom name. Arena 2's is the long one: the second town has
-- no guild hall, so it crosses the great lake to the first town's (see
-- trainingTripGold there).
local ARENA_NAV = {
    -- Arena 1 used to walk by room name instead: send the next
    -- direction the instant the arrival line lands. That paced it at the
    -- round-trip latency, 300-600ms, three to five times faster than the
    -- 1500ms we know avoids a trip -- and worse, the trip recovery below is
    -- guarded on `arenaJourney`, so these were the only moves in the script
    -- with nothing to catch a fall. A trip printed no room line, the state
    -- machine waited for one forever, and the run wedged.
    --
    -- Giving it step lists costs nothing and fixes both at once: the same
    -- paced walk, the same retry, the same code as the other two arenas. Every
    -- route here is checked against the mapped first town, room names included.
    --
    -- One deliberate behaviour change comes with it. Healing while also hungry
    -- used to cut the corner from the temple straight to the tavern; now it
    -- returns to the arena and sets out again, because arrivals are the single
    -- place errands get dispatched (see arenaArrivedHome). Two rooms longer,
    -- and the same as the other arenas do it.
    ["1"] = {
        arenaRoom    = ARENA_ROOM,
        templeRoom   = "temple",
        barRoom      = "tavern",
        trainingRoom = "guild hall",
        toTemple     = { "w", "w" },
        fromTemple   = { "e", "e" },
        toBar        = { "w", "ne" },
        fromBar      = { "sw", "e" },
        toTraining   = { "w", "n" },
        fromTraining = { "s", "e" },
    },
    ["2"] = {
        arenaRoom  = ARENA_ROOM,
        templeRoom = "temple",
        barRoom    = "inn",
        toTemple   = { "s", "s", "s", "s" },
        fromTemple = { "n", "n", "n", "n" },
        toBar      = { "s", "s", "w", "w", "sw", "sw" },
        fromBar    = { "ne", "ne", "e", "e", "n", "n" },
        -- The second town has no guild hall. The nearest is the first town's,
        -- one room south of its docks: eight rooms down to this town's docks,
        -- the ferry, then "s". Read off the mapped graph (arena-1 -> docks-1 ->
        -- passage -> docks -> guild-hall). The ferry lands at once with an
        -- ordinary "You're on the docks." brief, so it is just another step.
        trainingRoom = "guild hall",
        toTraining   = { "s", "s", "w", "w", "s", "s", "se", "se", "buy passage", "s" },
        fromTraining = { "n", "buy passage", "nw", "nw", "n", "n", "e", "e", "n", "n" },
        -- Passage is 100 crowns each way, plus the hall's own fee. Only leave to
        -- train holding this much over ARENA_MIN_GOLD (see checkTrainingNeeded):
        -- a ferry we can't pay for strands the walk on the wrong shore.
        trainingTripGold = 500,
    },
    ["3"] = {
        arenaRoom    = ARENA_ROOM,
        templeRoom   = "temple",
        barRoom      = "tavern",
        trainingRoom = "guild hall",
        toTemple     = { "sw", "se", "ne", "e" },
        fromTemple   = { "w", "sw", "nw", "ne" },
        toBar        = { "sw", "nw" },
        fromBar      = { "se", "ne" },
        toTraining   = { "sw", "se", "ne", "n" },
        fromTraining = { "s", "sw", "nw", "ne" },
        -- Routes home from the town's in-between rooms, for a session started
        -- out there (taPackage.arenaWalkHomeFirst). The errand rooms need none
        -- of their own: their from* legs above already lead home. The four
        -- plazas share one name, so they are told apart by `ex`, whose exit
        -- sets all differ. Read off the mapped graph (underground-plaza..-3).
        homeFrom = {
            ["town square"] = { "nw", "ne" },
            ["underground plaza"] = {
                byExits = true,
                ["ne,nw,se"]    = { "ne" },              -- beside the arena
                ["ne,nw,se,sw"] = { "ne", "nw", "ne" },  -- the armor/weapon shops'
                ["e,n,sw"]      = { "sw", "nw", "ne" },  -- the temple's and hall's
                ["nw,se"]       = { "nw", "nw", "ne" },  -- the magic shop's
            },
        },
    },
}

-- Below this the arena loop can't keep paying for healing and potions, and
-- checkArenaGoldFloor exits the game. Up here so the training gate can keep a
-- training trip from spending us under it.
local ARENA_MIN_GOLD = 50

-- What `buy restoring` charges ("...to it's former state for 25 crowns."). A
-- tainted character pays it before a training trip, so the trip's gold gate has
-- to count it.
local ARENA_RESTORING_GOLD = 25

-- What `buy promotion` costs: pelayo was refused at 900 crowns and promoted at
-- exactly 1000, leaving 0 (archived session-pelayo-2026-08-29T20-04-53.log).
local ARENA_PROMOTION_GOLD = 1000


local function arenaNav()
    return ARENA_NAV[taPackage.arenaProfile]
end

-- Strength/agility potions (rowan, hyssop) from the magic shop. Both arenas
-- reach the same "magic shop" room by different routes. This is a reactive
-- round trip like healing: when a potion wears off we walk here, re-buy and
-- re-drink both, and walk back. The wear-off line is identical for each potion,
-- so we can't tell which lapsed — we always refresh both.
local SHOP_ROOM = "magic shop"
local ARENA_SHOP = {
    ["1"] = { to = { "w", "s", "s" },                from = { "n", "n", "e" } },
    ["2"] = { to = { "s", "s", "w", "w", "n", "n" }, from = { "s", "s", "e", "e", "n", "n" } },
    ["3"] = { to = { "sw", "se", "se", "se" },       from = { "nw", "nw", "nw", "ne" } },
}

-- Send the next queued direction. index counts steps already sent, so bumping
-- it first and indexing gives the step we haven't walked yet.
local function arenaJourneyStep()
    local j = taPackage.arenaJourney
    if not j then return end
    j.index = j.index + 1
    local dir = j.steps[j.index]
    if dir then arenaSend(dir) end
end

-- Re-send the current (not-yet-completed) step without advancing the index.
-- Used to recover from a rejected move: the step at j.index was sent but never
-- landed us in a new room, so we walk it again.
local function arenaJourneyResendStep()
    local j = taPackage.arenaJourney
    if not j then return end
    local dir = j.steps[j.index]
    if dir then arenaSend(dir) end
end

-- Pause before the next step so we don't move too fast and fall. The generation
-- guard drops a stale timer if the session stops or a new journey starts before
-- it fires.
local function arenaJourneyScheduleStep()
    local gen = taPackage.arenaJourneyGen or 0
    createTimer(ARENA_STEP_DELAY_MS, function()
        if taPackage.arenaState and (taPackage.arenaJourneyGen or 0) == gen then
            arenaJourneyStep()
        end
    end, { repeating = false })
end

-- Begin walking a leg: record the step list, the room that ends it, and the room
-- we are leaving from (fromRoom), bump the journey generation to invalidate any
-- in-flight step timer, and send the first step immediately (the pacing pause
-- only applies between steps). fromRoom lets the movement handler ignore the
-- room brief we're already standing in — see arenaJourneyOnMovement.
local function arenaJourneyStart(steps, arriveRoom, fromRoom)
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    taPackage.arenaJourney = { steps = steps, index = 0, arriveRoom = arriveRoom, fromRoom = fromRoom }
    arenaJourneyStep()
end

-- =========================================================================
-- Arena errands: the bar, the shop and coming home
-- =========================================================================

-- Head to the bar. Its confirmation lines differ from the first arena's tavern
-- ("The barmaid brings you a drink..."), but the buy commands are the same and
-- our navigation doesn't depend on those lines, so we just walk there.
local function departForBar()
    local nav = arenaNav()
    taPackage.arenaState = "tavern"
    echo("[arena] Heading to bar.")
    arenaJourneyStart(nav.toBar, nav.barRoom, nav.arenaRoom)
end

-- Forward declaration: arenaJourneyOnMovement chains to the tavern/bar when a
-- shop trip ends and food/drink is still owed, but departForTavern (which picks
-- the right route per arena) is defined further down.
local departForTavern

-- Forward declaration: the errand-service points below must not restock potions
-- while we owe a training trip (the hall refuses a potion-tainted character), but
-- checkTrainingNeeded is defined further down (it needs getLevel/getExperience).
-- Assigned later via `function checkTrainingNeeded()`.
local checkTrainingNeeded

-- Forward declaration: "am I too hurt to be in here?" and the walk-out that
-- answers it. Both are defined down in the flee block (they need the threshold
-- constants), but the errand-service points below have to ask before they
-- resume combat. A table rather than three separate `local function`s on
-- purpose: main.lua is within a couple of names of Lua's 200 top-level local
-- limit, and this way the whole idea costs one.
local arenaHeal = {}
-- Also hung off taPackage so the flee thresholds are readable from outside this
-- chunk. Tests assert against arenaHeal.FLOOR rather than a literal, so retuning
-- the number does not silently invalidate what they are checking.
taPackage.arenaHeal = arenaHeal

-- Head to the magic shop to restock the strength/agility potions. Both arenas
-- reach the same shop by different routes, chosen by profile. Always a journey,
-- so even the first arena walks it one paced step at a time.
--
-- The echo says what we are doing, not why: a potion wearing off is only one
-- reason to be here. Training and promotion both dispel the pair, and saying
-- "a potion wore off" after a promotion sent the log reader looking for a
-- wear-off that never happened (session-pollux-2026-10-10T10-50-07.log). A
-- real wear-off has the game's own line right above this one.
local function departForShop()
    local nav = ARENA_SHOP[taPackage.arenaProfile]
    if not nav then return end
    taPackage.arenaState = "potions"
    echo("[arena] Restocking stat potions — heading to the magic shop.")
    arenaJourneyStart(nav.to, SHOP_ROOM, ARENA_ROOM)
end

-- Back in the arena at the end of an errand. Each errand (heal, food, potions)
-- is its own round trip that starts and ends here, so any still-owed errand is
-- launched now — shop before food — rather than resuming combat. Every arena
-- walks home the same way, so a potion that wore off mid-errand is serviced on
-- arrival whichever errand we were on. departForShop/Tavern pick the route.
local function arenaArrivedHome()
    -- The gold-farming loop's exit door. Once it has banked its level it is done
    -- with the arena and wants to cash out rather than ring again, and this is
    -- the moment to hand over: a confirmed arrival in a known room, with no
    -- journey in flight to race. Returning true means it has taken over.
    --
    -- Deliberately ahead of the hurt check below. Being low on HP is only
    -- dangerous while we intend to keep fighting; the walk this hands off to
    -- goes through town, where nothing attacks, and a temple detour would spend
    -- the gold we are about to hand over. Defined in ta_create.lua, and nil for
    -- an ordinary run, which leaves everything below exactly as it was.
    if taPackage.onArenaArrivedHome and taPackage.onArenaArrivedHome() then return end
    -- Walked home hurt: turn straight around for the temple, before anything
    -- else and above all before swinging. checkFleeArena only looks at HP while
    -- arenaState == "fighting", so damage taken during an errand goes unnoticed
    -- — a flame giantess's 167-damage breath landed while we were walking to the
    -- magic shop, and we came back at 273/440 with a third-arena floor of 400.
    -- Without this gate the errand dispatch below resumed combat, the first
    -- "a flame" put us in the heat of battle, and the flee that finally fired on
    -- the next combat line could no longer leave the room ("You cannot leave in
    -- the heat of battle!" x6, one giant's swing from death). Arriving hurt but
    -- un-engaged is the one moment we can still walk out for free.
    if arenaHeal.isLow() then
        arenaDebugEcho("arrived-home-low")
        arenaHeal.departForTemple()
        return
    end
    -- Back in the arena and back on our feet: release any gong hold we placed.
    -- This has to happen here rather than at the temple — speech only carries to
    -- the room you are standing in, and the team is here. It runs before the
    -- errand dispatch below because the hold is about being one hit from death,
    -- which is no longer true; if we immediately walk out again for food, that
    -- is an ordinary full-health errand the roster already handles.
    arenaTeamHeal.announceHealed()
    -- Home, and no longer hurt (the check above would have turned us round), so
    -- this is the safe boundary a pending `stop-after-next` has been waiting for.
    -- Ahead of the training trip below because a stop is a stop: being told to
    -- finish up and then walking a full round trip to the guild hall is exactly
    -- the surprise this guard prevents, and for a gold-farming run that trip
    -- would go on to cash out and start a whole new character.
    --
    -- Behind onArenaArrivedHome above, which is the opposite case: a cash-out
    -- already armed means the run trained before it was ever asked to stop, so
    -- the round genuinely is over and finishing it beats parking mid-handover.
    if taPackage.arenaStopIfArmed("home and healed") then return end
    -- A level is owed: bank it before starting another fight.
    --
    -- Without this, the only place training is ever considered after a kill is
    -- the post-kill decision point, and that one asks checkFleeArena() FIRST --
    -- so any kill that left us low enough to flee skips the training check
    -- entirely. Arriving home from the temple then went straight back to
    -- combat, and the cycle kill -> flee -> heal -> resume -> ring closed with
    -- the XP already earned and nothing ever spending it.
    --
    -- Rare for a high-level character, which seldom flees. Near-permanent for a
    -- fresh one: 34 max HP against a flee floor of 25 means fleeing after 9
    -- damage, i.e. after almost every fight, so the escape hatch (a kill costing
    -- under 9 HP) essentially never comes up. Watched live at 1194 XP against a
    -- 1125 threshold, still level 1 and still fighting, in
    -- logs/session-garbageman-2026-08-15T20-17-58.log.
    --
    -- Placed after the hurt check above so we heal first and train on the next
    -- arrival, and before the errand dispatch so a level outranks a restock or a
    -- meal. arenaTryTrain itself still refuses while stat potions are active.
    -- Reached through taPackage because arenaTryTrain is a local defined further
    -- down the chunk; a field costs no local slot (see CLAUDE.md).
    if taPackage.arenaTryTrain and taPackage.arenaTryTrain() then return end
    -- Skip a restock while a level is owed: we are about to have the stat potions
    -- dispelled at the temple so the training hall will accept us, and buying a
    -- fresh pair first would only put the taint straight back (checkTrainingNeeded
    -- stays true until we train). needsPotions is left set so the restock happens
    -- later, once we've trained and it flips false. Food/drink still get serviced.
    if taPackage.needsPotions and not checkTrainingNeeded() then
        departForShop()
    elseif taPackage.needsDrinks or taPackage.needsMeal then
        departForTavern()
    else
        arenaResumeInCombat()
    end
end

-- Can we walk out for an errand (thirst/hunger/potion) right now? Only from an
-- active fight or the ringing gap, and NEVER while a gong summon is still in
-- flight. Ringing the gong is a two-step handshake — "You just rang the great
-- gong!" then, a beat later, the monster materializes — and adoption of that
-- monster requires arenaState == "ringing" (see arenaAdoptOwnSummon). If an
-- errand departs in that gap, the state flips to "potions"/"tavern", the summon
-- is orphaned (never adopted, so we never swing at it), and we walk out into a
-- monster that answers our move with "You cannot leave in the heat of battle!"
-- — the run then wedges forever (see problem.log: a potion wore off between the
-- ring and a warlock's arrival, and the character stood there thirsty, taking
-- hits, until it was stopped by hand). Deferring here lets the summon land and
-- be fought; the errand is picked up from the next clear ring gap below.
local function arenaCanDepartNow()
    local st = taPackage.arenaState
    if st ~= "fighting" and st ~= "ringing" then return false end
    if taPackage.arenaRingPending or taPackage.arenaOwnSummonPending then return false end
    return true
end

-- At a clear-room ring decision, honor any errand deferred while a monster was
-- present (or while a summon was still in flight): the room is empty now, so it
-- is safe to walk out. Otherwise ring for a fresh monster. This is the single
-- service point that guarantees a deferred potion/food/drink run is eventually
-- made even when it was flagged mid-fight. Mirrors arenaArrivedHome, but the
-- no-errand case rings rather than resuming a (nonexistent) fight.
local function arenaRingOrErrand()
    -- Standing in a clear arena, hurt: heal before summoning anything. The room
    -- being empty is exactly the window in which walking out still works, and
    -- ringing here would spend it. Same blind spot as arenaArrivedHome — a hit
    -- taken while arenaState wasn't "fighting" never ran the flee check.
    if arenaHeal.isLow() then
        arenaDebugEcho("ring-gap-low")
        arenaHeal.departForTemple()
        return
    end
    -- The boundary `stop-after-next` waits for when the flag was armed anywhere
    -- other than mid-fight: an errand trip that has walked home, a support-only
    -- character that never held an arenaMonster to see die, or the scan pump
    -- coming round again.
    --
    -- BELOW the hurt check on purpose. Stopping while hurt would park the
    -- character in a shared arena with no script left to flee it, which is the
    -- one state this whole feature exists to avoid -- the difference between
    -- "stop when it is safe to" and stop-all-scripts. Above the errand dispatch,
    -- though: a stop the user asked for does outrank a restock or a meal, which
    -- can wait for whatever they do next.
    if taPackage.arenaStopIfArmed("back at a clear ring gap") then return end
    -- As in arenaArrivedHome: don't restock potions while a level is owed — the
    -- pair we already have is about to be dispelled at the temple so the hall will
    -- accept us, and a fresh pair would just re-taint us. The restock waits until
    -- after we train.
    if taPackage.needsPotions and not checkTrainingNeeded() then
        departForShop()
    elseif taPackage.needsDrinks or taPackage.needsMeal then
        departForTavern()
    elseif taPackage.arenaTeam then
        -- Someone has to summon, but only one of us: wait for our turn in the
        -- ring order rather than ringing on top of a team-mate.
        arenaTeamRing()
    else
        arenaRing()
    end
end

-- =========================================================================
-- Advancing a journey, one room at a time
-- =========================================================================

-- Advance the walk one room at a time. Called for every "You're ..." line while
-- a paced journey is active. Reaching the leg's destination room fires that
-- leg's action (heal, buy, or resume combat); any other room is an intermediate
-- step, so pace the next move.
local function arenaJourneyOnMovement(room)
    local j = taPackage.arenaJourney
    if not j then return end
    -- A room brief for the room we departed from is NOT a move. A journey leaves
    -- right after a kill, and the kill's trailing "You're in the arena." scan
    -- arrives just as we start walking; counting it as a step advanced the index
    -- past our true position, so one real south consumed two "s" steps and the
    -- next step ("w") fired a room too early → "no exit" and a wedged walk (see
    -- something-went-wrong.log). Departure rooms are distinctive ("arena", "inn",
    -- "temple", "magic shop") and a route never revisits its start, so ignoring
    -- them for the whole leg is safe — unlike the generic "path" rooms a leg may
    -- pass through several of in a row, which must each still count.
    if j.fromRoom and room == j.fromRoom then return end
    if room ~= j.arriveRoom then
        arenaJourneyScheduleStep()
        return
    end
    taPackage.arenaJourney = nil
    local st = taPackage.arenaState
    if st == "fleeing" then
        -- Arrived at the temple.
        taPackage.arenaState = "healing"
        arenaSend("buy healing")
    elseif st == "tavern" then
        -- Arrived at the bar.
        if taPackage.needsDrinks then
            send("buy drink")
            taPackage.needsDrinks = nil
        end
        if taPackage.needsMeal then
            send("buy meal")
            taPackage.needsMeal = nil
        end
        taPackage.arenaParchedStreak = 0
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromBar, nav.arenaRoom, nav.barRoom)
    elseif st == "training" then
        -- Arrived at the guild hall. Send the purchase and start walking home
        -- at once: its success or refusal is handled by their own triggers, so
        -- there is nothing to wait for. Banking the level, charging the fee and
        -- re-buying potions all happen in the success trigger. The `i` first
        -- reads our gold, so the success trigger can measure the fee.
        send("i")
        send("buy training")
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromTraining, nav.arenaRoom, nav.trainingRoom)
    elseif st == "promoting" then
        -- Same shape as "buy training": the `i` reads our gold so the
        -- promotion trigger can measure the fee, and the walk home starts at
        -- once. The new class, the potion restock and the push all hang off the
        -- hall's reply.
        send("i")
        send("buy promotion")
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromTraining, nav.arenaRoom, nav.trainingRoom)
    elseif st == "restoring" then
        -- Arrived at the temple to have the potion taint dispelled. Send the
        -- purchase and start walking home at once, like "buy training": the
        -- success line has its own trigger (it zeroes arenaPotionsActive), and
        -- if the buy fails the count stays up and arenaRestoreTried stops us
        -- coming back. Arriving home re-runs arenaTryTrain, which now finds a
        -- clean character and walks to the hall.
        arenaSend("buy restoring")
        taPackage.arenaState = "returning"
        local nav = arenaNav()
        arenaJourneyStart(nav.fromTemple, nav.arenaRoom, nav.templeRoom)
    elseif st == "potions" then
        -- Arrived at the magic shop. Re-buy and re-drink both potions — the
        -- wear-off line is identical for each, so we refresh both — then walk
        -- back. The route home is chosen by the same profile we walked out on.
        send("buy rowan")
        send("buy hyssop")
        send("drink rowan")
        send("drink hyssop")
        -- Both stat potions are now up again. Tracked so that when a level is
        -- owed we know how many wear-off lines to wait for before it is safe to
        -- train (see arenaTryTrain / the wear-off trigger).
        taPackage.arenaPotionsActive = 2
        -- A fresh pair of potions earns a fresh restore attempt: whatever made
        -- the last one fail (an empty purse, most likely) may not hold now.
        taPackage.arenaRestoreTried = nil
        taPackage.needsPotions = nil
        taPackage.arenaState = "returning"
        arenaJourneyStart(ARENA_SHOP[taPackage.arenaProfile].from, ARENA_ROOM, SHOP_ROOM)
    elseif st == "returning" then
        arenaArrivedHome()
    end
end

-- =========================================================================
-- Arena training and promotion
-- =========================================================================

-- A promotion is owed once a base class has trained to 25, the top of its
-- ladder (the status bar's "(max)"). The class name is the whole of the state:
-- promoting renames it (Warrior -> Knight), and a Knight has no PROMOTED_CLASS
-- entry, so this goes false by itself the moment the hall says yes.
-- arenaPromotionRefused is the loop-stopper for a hall that says no for a reason
-- we did not foresee (see the "not ready for a promotion" trigger).
function taPackage.checkPromotionNeeded()
    if taPackage.arenaPromotionRefused then return false end
    if not taPackage.PROMOTED_CLASS[taPackage.character.getClass() or ""] then return false end
    local lvl = taPackage.character.getLevel()
    return lvl ~= nil and lvl >= 25
end

-- Assigns to the forward-declared local above (no `local` keyword) so
-- departForShop, defined earlier, can refuse to restock while a level is owed.
function checkTrainingNeeded()
    -- Only a profile with a route to a guild hall can leave to train.
    local nav = arenaNav()
    if not (nav and nav.toTraining) then return false end
    -- A promotion owed counts as a trip owed: the same hall, the same restore
    -- first, and the same hold on restocking potions until it is done. Its gold
    -- is checked by arenaTryTrain, which leaves the game when it is short rather
    -- than fighting on at level 25, where XP no longer buys anything.
    if taPackage.checkPromotionNeeded() then return true end
    local xp  = taPackage.character.getExperience()
    local cls = taPackage.character.getClass()
    local lvl = taPackage.character.getLevel()
    if not (xp and cls and lvl) then return false end
    local thresholds = taPackage.xp.thresholds[cls]
    if not thresholds then return false end
    local nextThreshold = thresholds[lvl + 1]
    if not (nextThreshold ~= nil and xp >= nextThreshold) then return false end
    -- A trip that costs real money (arena 2's ferry) waits until we can pay for
    -- it and still stay above the arena's gold floor -- including the restore,
    -- when that comes first, or we would come home from the temple too poor to
    -- go on and fight with our potions dispelled. Gating here rather than in
    -- arenaTryTrain means a level we can't yet afford is not "owed": potions
    -- are restocked as usual instead of drained, and the trip is taken at the
    -- first decision point after the purse fills.
    if nav.trainingTripGold then
        local need = nav.trainingTripGold + ARENA_MIN_GOLD
        if (taPackage.arenaPotionsActive or 0) > 0 then
            need = need + ARENA_RESTORING_GOLD
        end
        local gold = taPackage.character.getGold()
        if not gold or gold < need then return false end
    end
    return true
end

-- Head to the training hall to bank an earned level — but only when it is safe.
-- The hall refuses anyone under a strength/agility potion ("Your mind and body
-- must be whole and untainted before you may train."), and arenaPotionsActive
-- counts how many are still up.
--
-- The taint can be BOUGHT OFF rather than waited out. The temple's `buy
-- restoring` -- advertised for stats a monster drained -- is symmetric: it
-- clamps every stat back to its base value, in both directions. 25 crowns took
-- Phy 35 -> 30 and Agi 27 -> 15, exactly the rolled numbers, and the hall
-- accepted the character on the next breath
-- (logs/session-garbageman-2026-08-29T08-16-38.log, done by hand). That matters
-- because the taint measured 22m 24s and was the binding constraint on the
-- whole gold-farming cycle; see ta_create.lua.
--
-- So on a level owed while tainted we detour to the temple first. The walk home
-- from there is the ordinary fromTemple leg, and arriving home re-enters this
-- function with the count at 0 -- no temple->guild-hall route to add for three
-- arenas, and arrivals stay the single place errands are dispatched.
--
-- arenaRestoreTried is the loop-stopper. If the buy fails (no gold, and the
-- refusal wording is unknown to us) the count is never zeroed, so without it we
-- would walk to the temple, fail, come home, and set out again forever. One
-- attempt per set of potions; after that we fall back to the old behaviour of
-- fighting on until they lapse on their own.
--
-- Call at a safe decision point (a clear ring gap or just after a kill); returns
-- true once we have set out -- to the temple or the hall -- so the caller skips
-- its normal ring.
local function arenaTryTrain()
    if not checkTrainingNeeded() then return false end
    if (taPackage.arenaPotionsActive or 0) > 0 then
        if taPackage.arenaRestoreTried then return false end
        taPackage.arenaRestoreTried = true
        echo("[arena] Level owed but potion-tainted — buying restoring at the temple.")
        taPackage.arenaState = "restoring"
        local nav = arenaNav()
        arenaJourneyStart(nav.toTemple, nav.templeRoom, nav.arenaRoom)
        return true
    end
    -- Promotion. The hall does not actually refuse a tainted character for this
    -- (docs/promotion-observed-acolyte-to-high-priest.md), but it builds the
    -- new class from base stats either way, so the restore above costs nothing
    -- that matters and keeps one path for both trips.
    --
    -- Checked here, after the restore, rather than in checkTrainingNeeded: short
    -- of gold is not "nothing owed, fight on" as it is for a level. At 25 the XP
    -- buys nothing, so a run that cannot promote has nothing left to fight for,
    -- and says so and leaves. ARENA_MIN_GOLD on top so the fee cannot drop us
    -- straight through the gold floor on the way home, plus the ferry where the
    -- hall is across the lake.
    if taPackage.checkPromotionNeeded() then
        local nav = arenaNav()
        local need = ARENA_PROMOTION_GOLD + ARENA_MIN_GOLD + (nav.trainingTripGold or 0)
        local gold = taPackage.character.getGold()
        if not gold then return false end
        if gold < need then
            local name = taPackage.character.getName() or "?"
            taPackage.utils.sendNtfy("Short of gold for promotion",
                name .. " is a level 25 " .. taPackage.character.getClass() .. " and needs "
                    .. taPackage.utils.formatWithCommas(need) .. " gold to buy promotion, but has "
                    .. taPackage.utils.formatWithCommas(gold) .. ". Leaving the game.")
            taPackage.arenaEmergencyExit("Short of gold for promotion ("
                .. gold .. " of " .. need .. ")")
            return true
        end
        echo("[arena] Level 25 — heading to the guild hall to buy promotion.")
        taPackage.arenaState = "promoting"
        arenaJourneyStart(nav.toTraining, nav.trainingRoom, nav.arenaRoom)
        return true
    end
    echo("[arena] Leveling up — heading to training hall.")
    taPackage.arenaState = "training"
    -- Walk the fixed route to the guild hall. Arrival there
    -- (arenaJourneyOnMovement, st == "training") sends "buy training" and
    -- starts the walk home.
    local nav = arenaNav()
    arenaJourneyStart(nav.toTraining, nav.trainingRoom, nav.arenaRoom)
    return true
end
-- Exposed so arenaArrivedHome, defined earlier in this chunk, can call it: a
-- level owed has to be banked on arriving home too, not only at the post-kill
-- decision point (see the comment there).
taPackage.arenaTryTrain = arenaTryTrain

-- =========================================================================
-- Arena healing and fleeing
-- =========================================================================

-- Flee at 75% of max HP, but never below an absolute floor. The percentage
-- alone is unsafe for low-HP characters: a level-2 Sorceror (31 max HP) at 60%
-- fled at 18, and a cave bear's worst observed round is 23 damage (two claws)
-- — so he could cross from "fine" to dead in one round.
--
-- 20, lowered from 25 by request, and the change is a deliberate trade rather
-- than a refinement. 25 was chosen to cover that 23-damage bear round with a
-- small margin, so the floor guaranteed surviving the round in which the flee
-- was decided. 20 no longer does: a bear's worst round kills from here, and the
-- flee is not instant either — it is refused while the physical cooldown runs,
-- and has been seen taking 5-7 retries at 2s with the monster still swinging
-- (logs/session-garbageman-2026-08-15T20-17-58.log, around 20:42-20:47).
--
-- What it buys is time, and quite a lot of it. A fresh half-ogre warrior has
-- ~34 max HP, so the 75% rule gives 25.5 and the old floor bound at 25: it fled
-- after 9 damage, i.e. after nearly every fight, and the gold-farming loop spent
-- 8 temple round trips in a single ~28-minute cycle walking w,w / e,e for a
-- 2-crown heal. At 20 the band between full and fleeing widens from 9 HP to 14,
-- which should cut those trips substantially.
--
-- The bet is that a level-1 character in the first arena meets a cave bear
-- rarely enough that the trips saved outweigh the deaths risked. If deaths start
-- showing up in the logs, this is the first number to put back.
--
-- Fields on arenaHeal rather than three more top-level locals: main.lua sits a
-- name or two under Lua's 200-local ceiling for the main chunk, and it is where
-- they belong anyway.
arenaHeal.FRACTION = 0.75
arenaHeal.FLOOR = 20
-- Per-profile overrides of the flee floor. The third arena's monsters hit far
-- harder than a cave bear, so keep a much larger absolute HP reserve there —
-- flee before dropping below this regardless of the 75% rule. Profiles absent
-- here use arenaHeal.FLOOR.
--
-- The third arena's entry here now only applies when max vitality is unknown:
-- with a max to band on, the step function below takes over entirely.
--
-- 400, lowered from 500: at 500 a character whose max HP is at or below the
-- floor can never be above it, so it flees on the first tick and the third
-- arena never gets started at all. 400 is what the current roster can actually
-- clear. Note this is now BELOW a flame giant's worst observed hit (380) plus
-- any margin: fleeing at 399 leaves 19 HP against that hit, so the floor no
-- longer guarantees surviving the round in which the flee is decided. It buys
-- entry to the arena, not safety inside it — the real protection there is
-- killing fast enough as a team that the round never comes.
arenaHeal.FLOOR_BY_PROFILE = { ["3"] = 400 }

-- The third arena no longer uses the percentage-plus-floor rule at all. Its
-- threshold is a step function of MAX vitality, by request:
--
--   under 500 max  -> threshold is max itself, i.e. flee the moment anything
--                     lands, even for 1 damage. Such a character has no margin
--                     here: a flame giant's worst observed hit is 380, so two
--                     rounds kill from full, and the only safe amount of damage
--                     to absorb is none.
--   500..600 max   -> flee below 500.
--   600..800 max   -> flee below 600.
--   over 800 max   -> flee below 75% of max, i.e. the ordinary percentage rule.
--
-- The upper bands keep a reserve larger than that 380 hit, which the old 400
-- floor did not. The cost is temple trips, and for the smallest characters it is
-- a trip per fight — that is the intended trade: they are here to be carried by
-- a team, not to trade rounds with giants.
--
-- Note 600 max falls in the middle band (flee below 500), matching "between 500
-- and 600" reading inclusively at its top.
--
-- The percentage takes back over above 800 because a flat 600 stops scaling
-- there: 800 is exactly where 75% equals 600, so below it the flat band is the
-- more cautious of the two and above it the flat band is the more reckless. A
-- 998-max Knight held to 600 rides 148 HP further down than the same character
-- would anywhere else in the game. The bands exist to protect characters too
-- small to have a percentage worth taking, not to make large ones fight longer,
-- so hand them back to the percentage the moment it is the stricter answer. The
-- two agree exactly at 800, so the seam is continuous.
arenaHeal.THIRD_ARENA_LOW_MAX = 500
arenaHeal.THIRD_ARENA_HIGH_MAX = 600
arenaHeal.THIRD_ARENA_PCT_MAX = 800
function arenaHeal.thirdArenaThreshold(maxHp)
    if maxHp < arenaHeal.THIRD_ARENA_LOW_MAX then return maxHp end
    if maxHp <= arenaHeal.THIRD_ARENA_HIGH_MAX then return arenaHeal.THIRD_ARENA_LOW_MAX end
    if maxHp <= arenaHeal.THIRD_ARENA_PCT_MAX then return arenaHeal.THIRD_ARENA_HIGH_MAX end
    return math.floor(maxHp * arenaHeal.FRACTION)
end

-- The HP we must stay above to be in the arena at all. Split out of
-- checkFleeArena so the question can be asked from outside a fight — see
-- arenaHeal.isLow.
function arenaHeal.threshold()
    local _, maxHp = taPackage.character.getVitality()
    -- Max vitality unknown falls through to the floor below, as before: the
    -- bands are a function of it and have nothing to say without it.
    if maxHp and taPackage.arenaProfile == "3" then
        return arenaHeal.thirdArenaThreshold(maxHp)
    end
    local floor = arenaHeal.FLOOR_BY_PROFILE[taPackage.arenaProfile] or arenaHeal.FLOOR
    return maxHp and math.max(math.floor(maxHp * arenaHeal.FRACTION), floor) or floor
end

-- Are we below the flee threshold right now? Deliberately says no when vitality
-- is unknown: an unread HP is not evidence of being hurt, and answering yes
-- would send a fresh character straight to the temple before its first status.
function arenaHeal.isLow()
    local hp = taPackage.character.getVitality()
    return hp ~= nil and hp < arenaHeal.threshold()
end

-- Set out for the temple. The action half of fleeing, callable on its own so a
-- character that walks back INTO the arena hurt can turn around without having
-- to swing first (which is what puts you in the heat of battle you then can't
-- leave). Assumes we are standing in the arena.
function arenaHeal.departForTemple()
    taPackage.arenaState = "fleeing"
    -- Tell the team before taking the first step, so the announcement is out
    -- even if the step is refused — the refusal is exactly the case this
    -- exists for. Announcing first also leaves arenaLastCmd pointing at the
    -- escape direction rather than the speech.
    arenaTeamHeal.announceNeed()
    local nav = arenaNav()
    if not nav then
        -- No profile means no route to walk. Say so rather than throwing
        -- from inside a trigger: the state change above has already stopped
        -- us swinging, which is the half of fleeing that keeps us alive.
        echo("[arena] Fleeing, but no arena profile is set — walk out by hand.")
        return
    end
    arenaJourneyStart(nav.toTemple, nav.templeRoom, nav.arenaRoom)
end

-- Assigns to the forward-declared local above (no `local` keyword) so the
-- incoming-damage triggers, defined earlier in the file, can call it.
function checkFleeArena()
    if taPackage.arenaState ~= "fighting" then return false end
    if not arenaHeal.isLow() then return false end
    arenaDebugEcho("flee-triggered")
    arenaHeal.departForTemple()
    return true
end
taPackage.checkFleeArena = checkFleeArena

function departForTavern()
    departForBar()
end

-- =========================================================================
-- Arena XP polling
-- =========================================================================

-- How long to wait before asking for XP again.
--
-- XP is only knowable from a status block: a kill prints the gold it dropped and
-- nothing about experience. So a level earned between two polls is invisible
-- until the next one, and on a flat five-minute cadence that is up to five
-- minutes of fighting for XP that buys nothing -- the level is already earned,
-- and everything after it is waste. Averaged over a cycle that is ~2.5 minutes
-- lost against a 21-minute cycle, i.e. more than a tenth of the run, which is
-- larger than most of the things worth tuning here.
--
-- So poll on distance rather than on the clock. Far from the threshold a level
-- cannot possibly land in the next few minutes and asking is pure noise; close
-- to it, a single kill may cross the line. The bands are picked against what one
-- kill is actually worth in the first arena, where a cave bear went for 520 XP
-- in logs/session-garbageman-2026-08-15T19-45-33.log -- inside that, the very
-- next kill can finish the job, so ask often.
--
-- Costs about a dozen extra `status` sends per cycle, all of them in the half of
-- the run where the answer can change the plan.
local ARENA_XP_CHECK_FAR_MS = 300000
local ARENA_XP_CHECK_NEAR_MS = 60000
local ARENA_XP_CHECK_CLOSE_MS = 30000
local function arenaXpCheckDelay()
    local xp = taPackage.character.getExperience()
    local cls = taPackage.character.getClass()
    if not (xp and cls) then return ARENA_XP_CHECK_FAR_MS end
    local nextAt = taPackage.xp.getXpForNextLevel(xp, cls)
    -- Top of the ladder (25, or 105 once promoted), or a class with no table:
    -- nothing to count down to.
    if not nextAt then return ARENA_XP_CHECK_FAR_MS end
    local remaining = nextAt - xp
    if remaining <= 200 then return ARENA_XP_CHECK_CLOSE_MS end
    if remaining <= 600 then return ARENA_XP_CHECK_NEAR_MS end
    return ARENA_XP_CHECK_FAR_MS
end

local function scheduleArenaXpCheck()
    local gen = taPackage.arenaXpTimerGen or 0
    createTimer(arenaXpCheckDelay(), function()
        if (taPackage.arenaXpTimerGen or 0) ~= gen then return end
        taPackage.arenaXpCheckPending = true
        send("status")
        scheduleArenaXpCheck()
    end, { repeating = false })
end

-- Re-arm on load if a session is already running.
--
-- reloadScript() clears every pending timer (App.tsx calls
-- timerManager.clearTimers() before re-reading the scripts) while taPackage --
-- and so arenaState -- survives. This chain only ever re-arms from its own
-- callback, so a reload mid-session destroys the one pending timer and nothing
-- ever schedules another: XP polling stops for good, silently, in a session that
-- otherwise looks healthy. That is exactly what happened after the reload at
-- line 12186 of logs/session-garbageman-2026-08-15T20-17-58.log -- every later
-- `st` in that log was typed by hand.
--
-- Load-time rather than trigger-driven because there is no line to hang it on:
-- the symptom is the absence of traffic, not the presence of any. Any
-- self-rescheduling timer added here later needs the same treatment.
if taPackage.arenaState then
    echo("[arena] Script reloaded mid-session — re-arming the XP check.")
    scheduleArenaXpCheck()
    -- Same trap, same treatment: the solo heartbeat only ever re-arms from its
    -- own callback, so a reload would leave an exit-if-solo run believing it
    -- was protected while nothing was watching. arm() is a no-op when the flag
    -- is off, so this is safe to call for every reloaded session.
    arenaSolo.arm()
end

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
    taPackage.character.setExperience(matches[2])
    taPackage.xp.checkLevelUpNotification(tonumber(matches[2]))
    -- Follow-session XP accounting. `ta.follow` records the starting XP and
    -- `ta.unfollow` records the ending XP by sending `status` and waiting for the
    -- Experience line below; a pending flag tells us which capture this line is
    -- for. Kept independent of the arena flags so the two can't interfere.
    local followXp = tonumber(matches[2])
    if taPackage.followStartXpPending then
        taPackage.followStartXpPending = false
        taPackage.followSessionStartXp = followXp
        echo("[follow] Session started. XP: " .. followXp)
    elseif taPackage.followEndXpPending then
        taPackage.followEndXpPending = false
        local startXp = taPackage.followSessionStartXp
        if startXp then
            echo("[follow] Session over — gained " .. (followXp - startXp)
                .. " XP (total: " .. followXp .. ").")
        else
            echo("[follow] Session over — starting XP unknown (total: " .. followXp .. ").")
        end
        taPackage.followSessionStartXp = nil
    elseif taPackage.followXpPollPending then
        taPackage.followXpPollPending = false
        local startXp = taPackage.followSessionStartXp
        if startXp then
            echo("[follow] XP check — gained " .. (followXp - startXp)
                .. " XP so far (total: " .. followXp .. ").")
        end
    end
    -- Between monsters and enough XP to level: head to train, but only once our
    -- stat potions have lapsed (arenaTryTrain returns false while any is active,
    -- in which case we fall through and keep ringing/fighting so they wear off).
    --
    -- "ringing" alone was not enough of a gate. This line arrives from the
    -- 5-minute XP status poll, which can land anywhere -- including inside the
    -- gong's two-step handshake, where the state is still "ringing" but a monster
    -- is already on its way. On 2026-09-03 it did exactly that: the poll came
    -- back with a level owed in the same beat the ring was accepted, so the
    -- restore detour walked out while the summon was still in flight. The
    -- giantess that materialized was never adopted (adoption needs state
    -- "ringing"), the walk jammed on "You cannot leave in the heat of battle!",
    -- and teekywiki stood there taking hits for five minutes until it was stopped
    -- by hand (archived session-teekywiki-2026-09-03T12-57-00.log, 6777-6874).
    -- arenaCanDepartNow adds the two pending-summon checks the errand walks have
    -- always had; keep the "ringing" test as well, since it also permits
    -- "fighting" and a level must never pull us out mid-fight. Deferring costs
    -- nothing: the summon lands, we fight it, and the post-kill decision point
    -- calls arenaTryTrain again.
    if taPackage.arenaState == "ringing" and arenaCanDepartNow()
        and arenaTryTrain() then
        return
    end
    if not taPackage.arenaXpCheckPending then return end
    taPackage.arenaXpCheckPending = false
    local xp = tonumber(matches[2])
    local startXp = taPackage.arenaSessionStartXp
    local elapsed = os.time() - (taPackage.arenaSessionStartTime or os.time())
    local minutes = math.floor(elapsed / 60)
    local gained = startXp and (xp - startXp) or 0
    echo("[arena] " .. os.date("%H:%M:%S") .. " — " .. minutes .. " min, +"
        .. gained .. " XP (total: " .. xp .. ")")
    -- Phone notification so arena progress is visible off-screen. The XP echo
    -- above runs every 5 min, but a check-in every 5 min is too chatty for a
    -- phone, so throttle the ping to every 2 hours. Fire-and-forget (no callback)
    -- — a failed ping must never disturb the fight loop.
    --
    -- Silent during a gold-farming run, for the same reason the level pushes are
    -- (see checkLevelUpNotification): that character is levelled and thrown
    -- away, so neither its XP nor the gold it is carrying on the way there is
    -- news. A round runs for hours, which is a check-in every 2 hours about a
    -- character nobody is watching. The push worth waking up for in that loop is
    -- the handover ("Gave N gold to ...", ta_create), and it still fires. The
    -- echo above runs either way, so the run stays readable on screen.
    if taPackage.goldFarming then return end
    do
        local now = os.time()
        local lastNtfy = taPackage.arenaLastNtfyTime
        if not lastNtfy or (now - lastNtfy) >= 7200 then
            taPackage.arenaLastNtfyTime = now
            local hp = taPackage.character.getVitality()
            local gold = taPackage.character.getGold()
            local nextThreshold = taPackage.xp.getXpForNextLevel(xp, taPackage.character.getClass())
            local lines = { "[" .. (taPackage.character.getName() or "?") .. "]" }
            if nextThreshold then
                lines[#lines + 1] = "- XP Until Level Up: "
                    .. taPackage.utils.formatWithCommas(nextThreshold - xp)
            end
            -- The raw XP total says little on a phone; the level does, and a "^"
            -- glued to it (as on the status bar) says this character has earned
            -- a level it hasn't trained for yet.
            local level = taPackage.character.getLevel()
            lines[#lines + 1] = "- Lvl: " .. (level or "?")
                .. (taPackage.character.hasUntrainedLevel() and "^" or "")
            lines[#lines + 1] = "- HP: " .. (hp or "?")
            local encPct = taPackage.character.getEncumberancePercent()
            lines[#lines + 1] = "- Encumberance: " .. (encPct and (encPct .. "%") or "?")
            lines[#lines + 1] = "- Gold: " .. (gold and taPackage.utils.formatWithCommas(gold) or "?")
            local titles = { ["2"] = "2nd Arena Check-In", ["3"] = "3rd Arena Check-In" }
            local title = titles[taPackage.arenaProfile] or "Arena Check-In"
            taPackage.utils.sendNtfy(title, table.concat(lines, "\n"), true)
        end
    end
end, { type = "regex" })

-- =========================================================================
-- Starting away from the arena: the walk home
-- =========================================================================

-- A session started outside the arena walks home before anything else. Every
-- route the loop knows sets out from the arena, so starting anywhere else rang
-- the gong in a plaza, or (starting hurt) sent the temple route's "sw" from a
-- room with no sw and left the game -- nine keep-going reconnects in a row from
-- session-pollux-2026-10-11T08-03-19.log on, pollux saved one step from home.
--
-- arenaLastRoom is the last room brief seen, which at a TA_INIT_CMD start is
-- the entry brief. Unknown (nil) is treated as the arena, as it always was.
-- The walk home is an ordinary "returning" leg, so arriving runs
-- arenaArrivedHome: hurt goes to the temple, a level owed goes to the hall.
-- Returns true if it has taken over the start (walking, probing or stopped).
function taPackage.arenaWalkHomeFirst()
    local nav = arenaNav()
    local room = taPackage.arenaLastRoom
    if not room or room == nav.arenaRoom then return false end
    local route
    if room == nav.templeRoom then route = nav.fromTemple
    elseif room == nav.barRoom then route = nav.fromBar
    elseif room == nav.trainingRoom then route = nav.fromTraining
    elseif room == SHOP_ROOM then route = ARENA_SHOP[taPackage.arenaProfile].from
    else route = nav.homeFrom and nav.homeFrom[room] end
    if route and route.byExits then
        -- The answer lands in the "Exits:" trigger below.
        taPackage.arenaLocatePending = { room = room, routes = route }
        send("ex")
        return true
    end
    if not route then
        taPackage.arenaNoRouteHome(room)
        return true
    end
    taPackage.arenaState = "returning"
    arenaJourneyStart(route, nav.arenaRoom, room)
    return true
end

function taPackage.arenaNoRouteHome(room)
    echo("[arena] Not in the arena (in the " .. room .. ") and no route home from"
        .. " there — walk to the arena and start again.")
    taPackage.stopArena("Not in the arena (in the " .. room .. ") and no route home")
end

-- The `ex` arenaWalkHomeFirst asked for. Plazas share a name, so the exit set
-- picks the route; sorted, so the key does not depend on the game's order.
-- No `fromRoom` on this leg: the walk passes through other plazas, and those
-- arrivals must count as steps rather than be ignored as the room we left.
createTrigger("^Exits: (.+)\\.$", function(matches)
    local pending = taPackage.arenaLocatePending
    if not pending then return end
    taPackage.arenaLocatePending = nil
    if not taPackage.arenaState then return end
    local dirs = {}
    for dir in matches[2]:gmatch("[^,%s]+") do dirs[#dirs + 1] = dir end
    table.sort(dirs)
    local route = pending.routes[table.concat(dirs, ",")]
    if not route then
        taPackage.arenaNoRouteHome(pending.room .. " with exits " .. matches[2])
        return
    end
    taPackage.arenaState = "returning"
    arenaJourneyStart(route, arenaNav().arenaRoom, nil)
end, { type = "regex" })

-- =========================================================================
-- Starting an arena session (rg, tfia)
-- =========================================================================

-- Start an arena session. profile "1" is the original adjacent-rooms arena;
-- profiles "2" and "3" share this combat engine but walk their distant
-- temple/bar/shop one paced step at a time (see ARENA_NAV). Arena 3 also has a
-- training hall (reached by a paced route); arena 2 does not.
--
-- `team` turns on cooperative fighting: several characters share the arena and
-- coordinate so only one monster is ever summoned, and everybody swings at it.
-- It is a flag on the same session, not a second loop — every errand (thirst,
-- potions, flee-and-heal, training) stays per-character and untouched.
local function beginArenaSession(profile, debug, team, exitIfSolo, supportOnly)
    taPackage.arenaProfile = profile
    taPackage.arenaDebug = debug
    taPackage.arenaTeam = team
    taPackage.arenaTeamRoster = {}
    taPackage.arenaTeamSlot = 0
    -- Solitude is unknown until the first observation, not "none so far": a
    -- stamp of now would start the clock against a team that is standing right
    -- here, and the first poll would be reading a roster nobody has filled in.
    taPackage.arenaExitIfSolo = exitIfSolo or false
    -- Hold our swings for the character we are here to feed (arenaAttack).
    taPackage.arenaSupportOnly = supportOnly or false
    taPackage.arenaSoloSince = nil
    taPackage.arenaSoloProbePending = false
    -- Start deaf to any hold left over from a previous session: a stale lease
    -- would keep the gong held for a team-mate who finished healing long ago.
    taPackage.arenaTeamHealing = {}
    taPackage.arenaAnnouncedNeedsHealing = false
    taPackage.arenaSessionStartXp = taPackage.character.getExperience()
    taPackage.arenaSessionStartTime = os.time()
    taPackage.arenaLastNtfyTime = nil
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
    taPackage.arenaCombatGen = (taPackage.arenaCombatGen or 0) + 1
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    taPackage.arenaJourney = nil
    taPackage.arenaXpCheckPending = false
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    taPackage.arenaRingPending = false
    taPackage.arenaOwnSummonPending = false
    taPackage.arenaProbePending = false
    taPackage.arenaParchedStreak = 0
    -- Unknown how many stat potions are up at session start; 0 self-corrects on
    -- the first wear-off/restock. Only matters for the train-when-clean gate.
    taPackage.arenaPotionsActive = 0
    taPackage.arenaRestoreTried = nil
    taPackage.arenaPromotionRefused = nil
    -- A fresh session is never already winding down. stopArena clears this too,
    -- but a session can be started without one in between (a reload, or an `rg`
    -- typed over a run that was armed), and inheriting it would stop the new run
    -- after its first monster for no reason the user could see.
    taPackage.arenaStopAfterNext = nil
    taPackage.arenaState = "ringing"
    local startXpStr = taPackage.arenaSessionStartXp and tostring(taPackage.arenaSessionStartXp) or "unknown"
    -- Debug is the default now, so the echo flags the exception instead.
    local debugSuffix = debug and "" or " (quiet)"
    local teamSuffix = team and " (team mode)" or ""
    local soloSuffix = exitIfSolo
        and (" (exit after " .. arenaSolo.minutesLabel() .. " alone)") or ""
    local supportSuffix = supportOnly and " (support only)" or ""
    echo("[arena] Session started" .. teamSuffix .. supportSuffix .. soloSuffix
        .. debugSuffix .. ". XP: " .. startXpStr)
    scheduleArenaXpCheck()
    arenaSolo.arm()
    taPackage.arenaLocatePending = nil
    if taPackage.arenaWalkHomeFirst() then return end
    -- Starting hurt: walk out before doing anything else, exactly as
    -- arenaArrivedHome does. A session usually starts from a standing start in
    -- an empty arena, but not always -- the case this exists for is a character
    -- the BBS dropped mid-flee, reconnecting with TA_INIT_CMD="tfia 3". The
    -- entry `st` has already landed by then (that is what autoLogin.runInitCmd
    -- waits for), so the HP is known; it was simply never consulted. Without this the
    -- scan below finds whatever monster is still standing in the arena, engages
    -- it, and the first swing is what puts us in the heat of battle -- so the
    -- flee that checkFleeArena fires one line later cannot leave the room. In
    -- the third arena that is a 400-damage round spent for nothing.
    if arenaHeal.isLow() then
        arenaDebugEcho("session-start-low")
        echo("[arena] Starting hurt — heading to the temple before fighting.")
        arenaHeal.departForTemple()
        return
    end
    -- Scan the room before the first ring: another player may already have a
    -- monster in here, and we should clear it before summoning our own.
    arenaScanRoom()
end

-- The arenas are named by their number, and only by their number. The
-- spelled-out forms ("second", "third") used to be accepted alongside the
-- digits, which meant the same arena had two names in every alias, table key
-- and log line. One vocabulary is easier to type and easier to read.
local ARENA_PROFILES = { ["1"] = true, ["2"] = true, ["3"] = true }

local ARENA_ALIAS_USAGE = "usage: ring-gong-and-fight-in-arena <1|2|3> [quiet]"
local ARENA_TEAM_ALIAS_USAGE =
    "usage: team-fight-in-arena <1|2|3> [quiet] [exit-if-solo] [support-only]"

-- Parse the "<arena> [quiet] [exit-if-solo]" tail of the ring-gong aliases.
-- Order doesn't matter and every word is optional; a bare alias means arena 1,
-- which is what it meant before the three per-arena aliases were folded into
-- one.
--
-- The debug trace is ON by default: every real fight was being started with the
-- flag anyway, so the flag was pure ceremony. `quiet` turns it off; `debug` is
-- still accepted (as a no-op) so the old muscle memory keeps working.
--
-- Returns an options table — or nil plus the offending word. A table rather
-- than the positional (profile, debug) it used to return: the failure case was
-- already spending a third slot on the bad word, so every new option pushed the
-- callers further into counting nils.
--
-- `exit-if-solo` carries no number even though the threshold it arms is one
-- (arenaSolo.EXIT_MS). It can't: a bare digit here is the arena selector, so
-- "tfia 3 exit-if-solo 2" would quietly start arena 2.
local function parseArenaAliasArgs(rest)
    local opts = { profile = "1", debug = true, exitIfSolo = false, supportOnly = false }
    for word in (rest or ""):gmatch("%S+") do
        local lowered = word:lower()
        if lowered == "debug" then
            opts.debug = true
        elseif lowered == "quiet" then
            opts.debug = false
        elseif lowered == "exit-if-solo" then
            opts.exitIfSolo = true
        elseif lowered == "support-only" then
            opts.supportOnly = true
        elseif ARENA_PROFILES[lowered] then
            opts.profile = lowered
        else
            return nil, word
        end
    end
    return opts
end

-- Shared body of the solo and team aliases: same arguments, same class check,
-- same session — only the team flag differs.
local function startArenaFromAlias(rest, team, usage)
    local opts, badWord = parseArenaAliasArgs(rest)
    if badWord then
        echo("[arena] Unknown argument '" .. badWord .. "' — " .. usage)
        return
    end
    if not taPackage.character.getClass() then
        echo("[arena] Class unknown — run 'st' first so casters cast.")
        return
    end
    -- `exit-if-solo` means "leave if my team disappears", so it is meaningless
    -- on the solo aliases — a solo run is alone by definition and would exit
    -- one threshold after starting. Say so rather than accepting the word and
    -- doing nothing with it, which would look like it had worked.
    if opts.exitIfSolo and not team then
        echo("[arena] exit-if-solo only applies to team mode (tfia) — ignoring it.")
        opts.exitIfSolo = false
    end
    -- Same reasoning for support-only: there is nobody to support alone, so the
    -- character would stand in the arena and never swing at anything.
    if opts.supportOnly and not team then
        echo("[arena] support-only only applies to team mode (tfia) — ignoring it.")
        opts.supportOnly = false
    end
    beginArenaSession(opts.profile, opts.debug, team, opts.exitIfSolo, opts.supportOnly)
end

local function handleArenaAlias(matches)
    startArenaFromAlias(matches[2], false, ARENA_ALIAS_USAGE)
end

createAlias("^ring-gong-and-fight-in-arena(.*)$", handleArenaAlias, { type = "regex" })

-- Short form: "rg 2", "rg 3 quiet". Same handler, same arguments.
createAlias("^rg(.*)$", handleArenaAlias, { type = "regex" })

-- arena-potions-drunk — tell a running arena session that two stat potions are
-- up that it didn't buy. Starting a session zeroes arenaPotionsActive (we can't
-- know what the character walked in carrying), so potions drunk before `rg` are
-- invisible to the training gate: the first level owed walks to the hall, gets
-- refused, and only then self-corrects. The gold-farming create script drinks
-- exactly here — buy and drink at the shop, then `rg 1` — so it calls this
-- straight after, and the first training trip goes to the temple instead of
-- bouncing off the guild hall (see ta_create.lua's CREATE_STEPS).
createAlias("^arena-potions-drunk$", function()
    if not taPackage.arenaState then
        echo("[arena] Not running — nothing to tell about the potions.")
        return
    end
    taPackage.arenaPotionsActive = 2
    taPackage.arenaRestoreTried = nil
    echo("[arena] Noted 2 stat potions active — will buy restoring before training.")
end, { type = "regex" })

-- Cooperative version: run this in every session that is fighting the same
-- arena together. The characters coordinate through the game itself — see the
-- roster/stagger machinery below — so no leader needs designating and no extra
-- arguments are needed beyond the usual arena selector.
--
-- Registered twice, long form and short ("tfia 2"), the way the solo alias has
-- "rg". A loop rather than a second named handler: the main chunk is within a
-- couple of names of Lua's 200-local ceiling, and the loop variable is scoped
-- to the loop instead of adding to it.
for _, teamAliasPattern in ipairs({ "^team-fight-in-arena(.*)$", "^tfia(.*)$" }) do
    createAlias(teamAliasPattern, function(matches)
        startArenaFromAlias(matches[2], true, ARENA_TEAM_ALIAS_USAGE)
    end, { type = "regex" })
end

-- =========================================================================
-- Stopping an arena session
-- =========================================================================

-- `reason` says why, for the push below; `opts.quiet` skips the push, for a
-- caller that stops the arena only to hand over to something that reports for
-- itself (the gold-farming cash-out).
local function stopArena(reason, opts)
    local wasRunning = taPackage.arenaState ~= nil
    local profile = taPackage.arenaProfile
    taPackage.arenaXpTimerGen = (taPackage.arenaXpTimerGen or 0) + 1
    taPackage.arenaCombatGen = (taPackage.arenaCombatGen or 0) + 1
    taPackage.arenaXpCheckPending = false
    local startXp = taPackage.arenaSessionStartXp
    local currentXp = taPackage.character.getExperience()
    local startTime = taPackage.arenaSessionStartTime
    local summary
    if startXp and currentXp and startTime then
        local gained = currentXp - startXp
        local minutes = math.floor((os.time() - startTime) / 60)
        echo("[arena] Session over — +" .. gained .. " XP in " .. minutes .. " minutes.")
        summary = "+" .. taPackage.utils.formatWithCommas(gained) .. " XP in " .. minutes .. " minutes"
    end
    -- Say so off-screen. A run nobody is watching (keep-going on the VPS) can
    -- end for a dozen reasons, and the overnight pollux run of 2026-10-10
    -- stopped at 02:24 without a word to anyone.
    if wasRunning and not (opts and opts.quiet) then
        local hp, hpMax = taPackage.character.getVitality()
        local gold = taPackage.character.getGold()
        taPackage.utils.sendNtfy("Arena stopped", table.concat({
            "[" .. (taPackage.character.getName() or "?") .. "] arena "
                .. (profile or "?") .. " session stopped",
            "- Why: " .. (reason or "stopped"),
            "- Ran: " .. (summary or "?"),
            "- HP: " .. (hp or "?") .. (hpMax and (" / " .. hpMax) or ""),
            "- Gold: " .. (gold and taPackage.utils.formatWithCommas(gold) or "?"),
        }, "\n"), true)
    end
    taPackage.arenaSessionStartXp = nil
    taPackage.arenaSessionStartTime = nil
    taPackage.arenaState = nil
    taPackage.arenaMonster = nil
    taPackage.arenaLastCmd = nil
    taPackage.arenaFleeTimerPending = false
    taPackage.arenaDebug = nil
    taPackage.arenaAttackPending = nil
    taPackage.arenaCastPending = nil
    taPackage.arenaRingPending = nil
    taPackage.arenaOwnSummonPending = nil
    taPackage.arenaProbePending = nil
    taPackage.arenaProfile = nil
    taPackage.arenaJourney = nil
    taPackage.arenaLocatePending = nil
    taPackage.arenaTeam = nil
    taPackage.arenaTeamRoster = nil
    taPackage.arenaTeamSlot = nil
    taPackage.arenaTeamHealing = nil
    taPackage.arenaAnnouncedNeedsHealing = nil
    taPackage.arenaSupportOnly = nil
    -- Bump the generation before clearing the flag: the pending tick reads the
    -- flag too, but the generation is what makes an already-queued callback a
    -- no-op even if a new session arms a fresh one in the same breath.
    taPackage.arenaSoloGen = (taPackage.arenaSoloGen or 0) + 1
    taPackage.arenaExitIfSolo = nil
    taPackage.arenaSoloSince = nil
    taPackage.arenaSoloProbePending = nil
    taPackage.arenaParchedStreak = 0
    taPackage.needsPotions = nil
    taPackage.arenaPotionsActive = nil
    taPackage.arenaRestoreTried = nil
    taPackage.arenaPromotionRefused = nil
    -- Cancel any in-flight exit retry loop (a manual stop or stop-all-scripts
    -- means halt everything). arenaEmergencyExit calls stopArena first and
    -- re-arms this afterward, so its own loop survives.
    taPackage.exitGamePending = false
    -- Bump the ring and journey generations so any in-flight pump tick no-ops.
    taPackage.arenaRingGen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaJourneyGen = (taPackage.arenaJourneyGen or 0) + 1
    -- A pending "stop after this monster" is moot once we have stopped outright,
    -- and leaving it set would arm the NEXT session against its will. Clearing it
    -- here is also what disarms it from stop-arena-fight, stop-all-scripts, the
    -- death handler and arenaEmergencyExit -- every one of them routes through
    -- this teardown, so none needs to know the flag exists.
    taPackage.arenaStopAfterNext = nil
    echo("[arena] Stopped.")
end
taPackage.stopArena = stopArena

-- The deferred stop `stop-after-next` arms. Called at the two boundaries where
-- the loop decides what to do next -- the kill, and the clear-room ring gap --
-- and returns true when it has stopped, so the caller can return. Same contract
-- as taPackage.onArenaArrivedHome: true means "taken over, do nothing further".
--
-- A taPackage field rather than a local for the same reason arenaTryTrain is
-- one: arenaRingOrErrand is defined ~700 lines above this point and cannot see a
-- local declared here. A field also costs no slot against the 200-local ceiling.
function taPackage.arenaStopIfArmed(reason)
    if not taPackage.arenaStopAfterNext then return false end
    -- Cleared before stopArena rather than by it, so the echo below reads as this
    -- function's doing and a re-entrant call cannot double-report.
    taPackage.arenaStopAfterNext = nil
    echo("[arena] stop-after-next: " .. reason .. " -- stopping.")
    -- A gold-farming run rides on this same arena session, and stopping at the
    -- kill rather than at the ring is the whole point of it: the run must not
    -- walk off to train and cash out after we were asked to stop. stopArena
    -- alone would leave goldFarming set and half the loop live -- the training
    -- confirmation would still arm the cash-out -- so bring its flags down too.
    -- The character is left standing in the arena with its gold and an untrained
    -- level; farm-for-gold picks the run back up.
    if taPackage.goldFarming and taPackage.stopCreateCharacter then
        taPackage.stopCreateCharacter()
        echo("[create] Gold-farming run disarmed -- resume with farm-for-gold.")
    end
    stopArena("stop-after-next: " .. reason)
    return true
end

dofile(SCRIPT_DIR .. "ta_leave_game.lua")
-- Defined in ta_leave_game.lua, just loaded, and used by the safety exits below.
local arenaEmergencyExit = taPackage.arenaEmergencyExit

-- =========================================================================
-- Arena safety exits: the gold floor and unrelieved thirst
-- =========================================================================

-- The arena loop only stays alive while it can pay the temple for healing and
-- the shop for potions. If our gold ever falls below this floor (ARENA_MIN_GOLD,
-- declared up with ARENA_NAV so the training gate can count it), the next such
-- trip is one bad roll away from a "can't afford" wedge that grinds the
-- character to death, so bail out of the game now while the balance is still
-- positive. Published on taPackage for setGold (ta_character.lua) so every
-- gold change is checked; a nil balance (not yet read) is left alone. Returns
-- true when it triggered the exit.
function taPackage.checkArenaGoldFloor()
    if not taPackage.arenaState then return false end
    local gold = taPackage.character.getGold()
    if gold and gold < ARENA_MIN_GOLD then
        arenaEmergencyExit("Gold below " .. ARENA_MIN_GOLD .. " (" .. gold
            .. ") — can't sustain healing/potions")
        return true
    end
    return false
end

-- Count consecutive thirst/hunger ticks that go unrelieved. A tick means the
-- game is draining 1 HP; if we rack up ARENA_PARCHED_LIMIT in a row without
-- ringing the gong or buying a drink/meal (both reset the streak), the errand
-- loop is wedged and standing here just dies slowly — bail out of the game
-- instead. Returns true when it triggered the exit so the caller stops
-- processing the tick.
local function arenaCheckParched()
    taPackage.arenaParchedStreak = (taPackage.arenaParchedStreak or 0) + 1
    if taPackage.arenaParchedStreak >= ARENA_PARCHED_LIMIT then
        arenaEmergencyExit("Thirsty/hungry " .. taPackage.arenaParchedStreak
            .. "x with no relief (navigation likely stuck)")
        return true
    end
    return false
end

-- =========================================================================
-- Stopping the arena by hand
-- =========================================================================

-- One stop for every arena: stopArena() clears the profile along with the rest
-- of the session, so there was never anything per-arena about stopping.
createAlias("^stop-arena-fight$", function()
    stopArena("stop-arena-fight")
end, { type = "regex" })

-- The graceful counterpart to stop-arena-fight: finish what is in front of us,
-- then stop. Arms a flag that taPackage.arenaStopIfArmed honors at the next
-- decision point, rather than tearing the session down mid-swing and leaving the
-- character standing next to a live monster with nothing driving it.
--
-- One alias covers every repeating script that rings the gong, because they are
-- all the same loop: `rg` and `tfia` are this engine directly, and every
-- farm-for-gold walk that ends in a fight ends by running `rg 1`.
--
-- There is no cancel by design. stop-arena-fight and stop-all-scripts remain the
-- escape hatch -- they stop now rather than resuming -- which is said in the
-- echo so nobody has to go looking.
createAlias("^stop-after-next$", function()
    if not taPackage.arenaState then
        echo("[arena] Not running -- nothing to stop after.")
        return
    end
    taPackage.arenaStopAfterNext = true
    -- Nothing in flight means nothing to finish, so honor the flag right away
    -- rather than ringing one more gong purely to have something to stop after.
    -- The in-flight test mirrors arenaCanDepartNow: a gong already rung, with its
    -- summon still on the way, IS a monster -- it just has not arrived yet, and
    -- stopping in that gap would orphan it in the room with us.
    if taPackage.arenaState == "ringing"
        and not taPackage.arenaMonster
        and not taPackage.arenaRingPending
        and not taPackage.arenaOwnSummonPending then
        taPackage.arenaStopIfArmed("nothing in progress")
        return
    end
    -- echo, not cecho: a cecho never reaches the session log, and "did this arm?"
    -- is the first question asked of a run that went wrong.
    echo("[arena] Armed -- finishing this monster, then stopping (healing first"
        .. " if it ends hurt). There is no cancel; stop-arena-fight or"
        .. " stop-all-scripts to stop right now.")
end, { type = "regex" })

-- =========================================================================
-- The gong
-- =========================================================================

-- Our own gong ring is confirmed by this line; the monster we summoned arrives
-- on the very next "enters the arena" line. The arena is shared, so other
-- players' rings ("Castor just rang the great gong!") also spawn monsters — we
-- must only adopt the one that followed *our* ring. (See the cascade in
-- logs/session-pollux-2026-06-28T12-33-36.log, where Pollux latched onto
-- Castor's spawns and piled up monsters it couldn't see.)
createTrigger("^You just rang the great gong!$", function()
    -- The gong's acceptance instant, which is what a future reckoning would have
    -- to count from — the equivalent of arenaLastSwingAt for melee. Stamped
    -- before the state gate below so the measurement survives the paths that
    -- return early.
    arenaDebugEcho("ring-accepted  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
        .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
    taPackage.arenaLastRingAt = nowMillis()
    -- The fight loop is alive again — clear any accumulated thirst/hunger streak
    -- so a later dry spell starts counting fresh (a bar round-trip ends with a
    -- ring back in the arena, so this is what resets the streak between trips).
    taPackage.arenaParchedStreak = 0
    if taPackage.arenaState ~= "ringing" then return end
    taPackage.arenaOwnSummonPending = true
end, { type = "regex" })

-- A team-mate is escaping at low HP and wants the gong held (see
-- arenaTeamHealingHolder). We only ever hear other characters: the game shows
-- the speaker "-- Message sent --" rather than echoing their own line back, so
-- these can't be tripped by our own announcements.
--
-- (\\S+) rather than (.+) for the name is deliberate. Names are a single word,
-- and the loose form would also swallow the group-chat channel's
-- "From <leader> (to group): ..." lines, which carry remote commands and belong
-- to their own trigger further down.
createTrigger("^From (\\S+): " .. arenaTeamHeal.NEED_MSG .. "$", function(matches)
    if not taPackage.arenaTeam then return end
    -- A team-mate is alive and talking, so we are demonstrably not the last one
    -- left. They are on their way OUT of the arena, which is exactly the errand
    -- absence the solo clock must not punish us for.
    arenaSolo.sawCompany()
    arenaTeamHeal.leases()[matches[2]:lower()] = os.time()
    arenaDebugEcho("team-heal-hold-" .. matches[2])
    -- A support-only character has been standing here not swinging, so nothing
    -- is driving its combat loop: arenaSwingAccepted only fires off our OWN
    -- hits, and the only other re-drives are the incoming-attack triggers, which
    -- fire when the monster picks US. If it happens to be beating on the
    -- character that just called for help, no swing would ever start. So open
    -- the burst from here rather than waiting to be hit — the whole point is to
    -- kill the monster before a pinned team-mate takes another round. Once the
    -- first swing lands the ordinary loop takes over again.
    if taPackage.arenaSupportOnly and taPackage.arenaState == "fighting" then
        arenaDebugEcho("support-assist")
        arenaAttack()
        arenaCast()
    end
end, { type = "regex" })

-- ...and they made it back. Clearing the lease early is the normal path; the
-- expiry in arenaTeamHealingHolder is only the backstop for an all-clear that
-- never comes.
createTrigger("^From (\\S+): " .. arenaTeamHeal.HEALED_MSG .. "$", function(matches)
    if not taPackage.arenaTeam then return end
    arenaSolo.sawCompany()
    arenaTeamHeal.leases()[matches[2]:lower()] = nil
    -- Everyone who was holding comes off the hold on this same line, so stand
    -- off the gong for a beat and let the character that just got healed take
    -- the summon it came back for.
    arenaTeamHeal.beginGrace()
    arenaDebugEcho("team-heal-release-" .. matches[2])
end, { type = "regex" })

-- Somebody else in the arena rang. Solo, that is none of our business — the
-- trigger below adopts only the monster that followed our OWN ring. In team
-- mode it is the signal the whole design rests on: the game has just told every
-- client, in one serialized broadcast, that a summon is on its way, so anyone
-- still waiting for a turn must stand down or we get a second monster.
--
-- Bumping the ring generation is what calls off our pending ring (see
-- arenaTeamRing) and any in-flight scan. That leaves nothing armed, so re-arm
-- one pump tick: if the summon never arrives — the ringer bounced off "still
-- physically exhausted", or walked out — we go back to probing rather than
-- standing in the arena forever waiting for a monster that is not coming.
createTrigger("^(.+) just rang the great gong!$", function(matches)
    -- "You just rang the great gong!" is our own ring, owned by the trigger
    -- above; this pattern matches it too, so let that one keep it.
    if matches[2] == "You" then return end
    if not taPackage.arenaTeam then return end
    -- Somebody is standing at the gong, so we have company. Noted before the
    -- state gate below: mid-fight this trigger has nothing else to do and
    -- returns, and mid-fight is precisely when the solo clock is running with
    -- no scan pump to correct it.
    arenaSolo.sawCompany()
    if taPackage.arenaState ~= "ringing" then return end
    arenaDebugEcho("team-ring-yielded-to-" .. matches[2])
    local gen = (taPackage.arenaRingGen or 0) + 1
    taPackage.arenaRingGen = gen
    taPackage.arenaRingPending = false
    -- Abandon any brief still arriving. The ring can land in the middle of our
    -- own probe, and the floor line that ends that brief is what drives the ring
    -- decision — so leaving the probe live would walk us straight into ringing on
    -- top of the summon we just stood down for. The re-armed pump probes again in
    -- a moment, by which time the monster is here to be adopted.
    taPackage.arenaProbePending = false
    createTimer(ARENA_RING_RETRY_MS, function()
        if taPackage.arenaState == "ringing" and (taPackage.arenaRingGen or 0) == gen then
            arenaScanRoom()
        end
    end, { repeating = false })
end, { type = "regex" })

-- =========================================================================
-- The monster: summons, the room roster and the floor line
-- =========================================================================

-- Adopt a freshly-spawned monster. Solo, only the one that followed *our* ring
-- (arenaOwnSummonPending): without that guard a monster summoned by another
-- player sharing the arena gets adopted and our real fight is forgotten.
--
-- Team mode wants exactly the opposite, and that is the point of it — one
-- monster in the arena and everybody swinging at it, whoever summoned it. So
-- there is no "was it ours" test: any spawn arriving while we are looking for
-- something to fight is ours to fight. Not tracking whose ring it was also means
-- a broadcast we somehow missed cannot leave us idle next to a live monster.
--
-- The arenas spawn with different flavor text — the first through a dungeon
-- gate, the second in a puff of smoke — but the adoption rule is identical.
local function arenaAdoptSummon(name)
    if taPackage.arenaState ~= "ringing" then return end
    if not taPackage.arenaTeam and not taPackage.arenaOwnSummonPending then return end
    taPackage.arenaOwnSummonPending = false
    arenaEngage(name)
end

createTrigger("^An? (.+) enters the arena through the dungeon gate!$", function(matches)
    arenaAdoptSummon(matches[2])
end, { type = "regex" })

-- Second arena: the summoned monster materializes instead of walking in. The
-- smoke's color varies, so match any word(s) before "smoke".
createTrigger("^An? (.+) appears in a puff of .+ smoke!$", function(matches)
    arenaAdoptSummon(matches[2])
end, { type = "regex" })

-- Response to the bare-return probe from arenaScanRoom: the arena brief's
-- occupant line. If a monster is already here, engage it instead of ringing —
-- ringing now would stack a second monster on us. An empty room prints
-- "There is nobody here." (no monster), so we ring.
createTrigger("^There is (.+) here\\.$", function(matches)
    if not taPackage.arenaProbePending then return end
    taPackage.arenaProbePending = false
    if taPackage.arenaState ~= "ringing" then return end
    local monster = firstArenaMonster(matches[2])
    if monster then
        arenaEngage(monster)
    else
        arenaRingOrErrand()
    end
end, { type = "regex" })

-- Team mode's roster: who else is standing in the arena right now. The brief the
-- probe already prints names them on their own line, between the monsters and
-- the floor line:
--
--     There is a stygian dragon here.        <- monsters (see the trigger above)
--     Tojolias and Teekywiki are here.       <- this line; we are never in it
--     There is nothing on the floor.         <- terminator (see the trigger below)
--
-- so a ring order can be derived from data we are already fetching, with no
-- designated leader and nothing to configure (see arenaTeamRing).
--
-- Two triggers rather than one with an "is|are" alternation: baud's patterns are
-- translated to Lua patterns for the tests, and Lua has no alternation. Being
-- anchored on " is here.$" / " are here.$" is also what keeps the brief's other
-- lines out of the roster — "There is nobody here." ends in "nobody here.", and
-- the monster line in "<monster> here.", so neither can match.
local function arenaCaptureRoster(blob)
    -- Only while a probe is outstanding: this is the arena brief we asked for,
    -- not a room we happen to be walking through.
    if not taPackage.arenaTeam then return end
    -- Either probe will do. The solo heartbeat asks for the same brief mid-fight
    -- (arenaSolo.tick), and a fight-time roster is strictly fresher than the one
    -- the last ring gap left behind. arenaScanRoom still owns clearing this on
    -- its way out, so the ring slot cannot go stale off the back of it.
    if not (taPackage.arenaProbePending or taPackage.arenaSoloProbePending) then return end
    -- "A", "A and B", "A, B, and C" — flatten the conjunction to a plain
    -- comma-separated list, then split. The Oxford comma leaves an empty field
    -- behind ("B, and C" -> "B, , C"), which the emptiness check drops.
    local roster = {}
    for name in (blob:gsub(" and ", ", ") .. ","):gmatch("%s*(.-)%s*,") do
        if name ~= "" then roster[#roster + 1] = name end
    end
    taPackage.arenaTeamRoster = roster
end

createTrigger("^(.+) is here\\.$", function(matches)
    arenaCaptureRoster(matches[2])
end, { type = "regex" })

createTrigger("^(.+) are here\\.$", function(matches)
    arenaCaptureRoster(matches[2])
end, { type = "regex" })

-- The "There is nobody here." occupant line only appears when the room is
-- *completely* empty. When another player is present, their "Pollux is here."
-- line takes the occupant slot and the "nobody" line is omitted — so the
-- occupant trigger above never fires and the probe would hang forever (both
-- characters deadlock; see logs/session-castor-2026-06-28T15-48-05.log). The
-- floor line always ends the brief, whoever is here, so use it as the
-- definitive terminator: if the probe is still pending when it arrives, no
-- monster was listed and the room is clear of monsters, so ring.
createTrigger("^There .+ on the floor\\.$", function()
    -- The solo heartbeat's mid-fight brief ends here too, and this is the only
    -- line that always does: when nobody else is in the arena no roster line is
    -- printed at all, so "no names seen" is only knowable once the brief is
    -- over. Handled before the ring probe below and independently of it — the
    -- two can legitimately be outstanding at the same time.
    if taPackage.arenaSoloProbePending then
        taPackage.arenaSoloProbePending = false
        arenaSolo.observe(#(taPackage.arenaTeamRoster or {}))
    end
    if not taPackage.arenaProbePending then return end
    taPackage.arenaProbePending = false
    if taPackage.arenaState ~= "ringing" then return end
    arenaRingOrErrand()
end, { type = "regex" })

-- =========================================================================
-- Fighting: our swings, the kill and attacks on us
-- =========================================================================

-- Hit, miss and dodge all mean the same thing to the physical clock: the game
-- ACCEPTED a swing and spent a tick of the burst. Stamping the time here is what
-- lets the exhaustion handler below reckon the recovery from the right instant.
local function arenaSwingAccepted(label)
    taPackage.arenaAttackPending = false
    taPackage.arenaLastSwingAt = nowMillis()
    arenaDebugEcho(label)
    if not checkFleeArena() then arenaAttack() end
end

createTrigger("^Your .+ hit the .+ for \\d+ damage!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("our-hit")
end, { type = "regex" })

createTrigger("^Your attack missed!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("our-miss")
end, { type = "regex" })

createTrigger("^The .+ dodged your attack!$", function(matches)
    if taPackage.arenaState ~= "fighting" then return end
    arenaSwingAccepted("monster-dodge")
end, { type = "regex" })

createTrigger("^The (.+) falls to the ground lifeless!$", function(matches)
    -- Only react to the death of the monster we are actually fighting. The arena
    -- is shared, so another player's kill prints this same line; the name match
    -- is what tells our kill from theirs. This runs BEFORE any state gate on
    -- purpose: clearing the dead monster is correct in every state, and it must
    -- happen even when the kill lands after an errand has already flipped us out
    -- of "fighting". A thirst/hunger tick between our swing and its resolution
    -- calls departForTavern → state "tavern" while arenaMonster is still set; if
    -- the swing then kills the monster, an earlier state guard here dropped the
    -- death line, arenaMonster stayed set, and the errand's return path
    -- (arenaResumeInCombat) resumed swinging at a corpse forever — never ringing
    -- the gong (see something-went-wrong-focused.log).
    if matches[2] ~= taPackage.arenaMonster then return end
    taPackage.arenaMonster = nil
    taPackage.arenaAttackPending = false
    taPackage.arenaCastPending = false
    -- Follow-up actions (ring for a fresh monster / go train) only make sense
    -- while actively fighting. If the monster died during an errand trip, we
    -- just clear it here; arenaResumeInCombat will ring on arrival home.
    if taPackage.arenaState ~= "fighting" then return end
    -- Fleeing outranks a pending `stop-after-next`, and the order here is the
    -- whole point of the feature. Stopping the moment the kill lands would leave
    -- a hurt character standing in a shared arena with nothing left to flee it --
    -- the next player's summon kills it. So a kill that leaves us low still walks
    -- to the temple and heals; the stop is taken when we get home in one piece
    -- (arenaArrivedHome), which is where the flag is honored instead.
    if checkFleeArena() then return end
    -- `stop-after-next` armed, and we are unhurt: this death is the thing it was
    -- waiting for. Ahead of arenaTryTrain because being told to finish up and
    -- then walking a round trip to the guild hall is a surprise, and for a
    -- gold-farming run that trip would go on to cash out and start a whole new
    -- character.
    --
    -- This is also the team-mode case: the death line is a room-wide broadcast,
    -- so a monster a team-mate killed prints exactly this and reaches here
    -- through the same name match. There is no "who landed the blow" to test.
    if taPackage.arenaStopIfArmed("the monster is down") then return end
    -- Train if a level is owed and our potions have lapsed; otherwise ring
    -- for the next monster. While a level is owed but potions are still
    -- active, arenaTryTrain returns false, so we keep fighting — which both
    -- banks more XP and wears the potions down toward the safe-to-train point.
    if not arenaTryTrain() then
        taPackage.arenaState = "ringing"
        taPackage.arenaRingPending = false
        arenaScanRoom()
    end
end, { type = "regex" })

-- Self-healing net for a lost target. If we ever end up swinging at a monster
-- that isn't here — a kill dropped in a race window, another player's move that
-- displaced it, or any stale arenaMonster — the game answers our attack with
-- "Sorry, you don't see "troll" nearby." Nothing else re-drives the loop after
-- that line (no monster hit/miss/death follows a whiffed attack), so without
-- this the run wedges: it keeps re-attacking a ghost and never rings. Treat it
-- as "the monster is gone": clear it and ring for a fresh one. See
-- something-went-wrong-focused.log.
createTrigger("^Sorry, you don't see \".+\" nearby\\.$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("target-gone")
    taPackage.arenaMonster = nil
    taPackage.arenaState = "ringing"
    taPackage.arenaRingPending = false
    arenaScanRoom()
end, { type = "regex" })

createTrigger("^The .+ attacked you .+ for \\d+ damage!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-hit")
    if not checkFleeArena() then arenaAttack() end
end, { type = "regex" })

createTrigger("^The .+ attacked you, but .+ glanced off your armor!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-glance")
    arenaAttack()
end, { type = "regex" })

createTrigger("^The .+'s? .+ misses? you!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("monster-miss")
    arenaAttack()
end, { type = "regex" })

createTrigger("^You barely dodge the .+'s attack!$", function()
    if taPackage.arenaState ~= "fighting" then return end
    arenaDebugEcho("player-dodge")
    arenaAttack()
end, { type = "regex" })

-- =========================================================================
-- Arena room briefs: the steps of a journey
-- =========================================================================

-- Every arena leg is a paced journey now, so a room line means one thing: a
-- step of the walk in progress. These four also remember the room the brief
-- named (arenaLastRoom), journey or not, so a session started anywhere knows
-- where it is standing (taPackage.arenaWalkHomeFirst). The room-name navigation that used to sit here
-- -- react to a named waypoint, send the next direction at once -- is gone with
-- the first arena's step lists, and with it the two faults it carried: no
-- pacing, and no trip recovery. A room line with no journey running is a no-op.
createTrigger("^You're in the (.+)\\.$", function(matches)
    taPackage.arenaLastRoom = matches[2]
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- Paced routes pass through "You're on a path." rooms, which the "in the"
-- trigger above never matches. Feed them to the walk handler too so every step
-- advances. Only meaningful mid-journey; otherwise a no-op.
createTrigger("^You're on a (.+)\\.$", function(matches)
    taPackage.arenaLastRoom = matches[2]
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- The second arena's training route crosses the great lake, and both docks
-- brief as "You're on the docks." -- "the", which the "on a" trigger above
-- doesn't match. Without this the walk stalls on the near shore.
createTrigger("^You're on the (.+)\\.$", function(matches)
    taPackage.arenaLastRoom = matches[2]
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- Paced routes also thread through generically-named rooms whose brief takes the
-- article "a"/"an" — the third arena's temple/bar/shop/training legs (and every
-- reverse) each hop through a chain of "You're in an underground plaza." rooms.
-- The "in the" trigger above only matches "the", so without this the paced walk
-- never counts those arrivals and wedges after its first step: a real flee
-- fired "sw", landed in "an underground plaza", and then just sat there because
-- the journey never advanced (see the 2026-07-18 third-arena flee log). Feed
-- them to the walk handler too; inert unless a paced journey is active, so the
-- first arena's name-based navigation is untouched.
createTrigger("^You're in an? (.+)\\.$", function(matches)
    taPackage.arenaLastRoom = matches[2]
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(matches[2])
end, { type = "regex" })

-- The same briefs, glued to the end of a logon/logoff broadcast, which carries
-- no line break of its own:
--
--     Pelayo logs OFF.  [08-OCT-26/22:22:30] Users Online: 2: You're in an underground plaza.
--
-- The anchored triggers above never see that arrival, and the walk home from
-- the temple stalled on it (session-pollux-2026-10-10T23-28-55.log). Peel the
-- article off by hand: the four forms above, one trigger.
createTrigger("Users Online: \\d+: You're (.+)$", function(matches)
    local rest = matches[2]:gsub("%.$", "")
    local room = rest:match("^in the (.+)$") or rest:match("^in an? (.+)$")
        or rest:match("^on the (.+)$") or rest:match("^on an? (.+)$")
    if not room then return end
    taPackage.arenaLastRoom = room
    if not taPackage.arenaJourney then return end
    arenaJourneyOnMovement(room)
end, { type = "regex" })

-- Moving between rooms too quickly makes the character trip and fall. No room
-- line follows, so the step-driven walk above would stall forever waiting to
-- enter a room it never does. Re-send the current step after a longer pause to
-- recover the walk (and back off the pace). The move genuinely failed, so no
-- room line is in flight — the resend cannot double-move us. The generation
-- guard drops the retry if the session stops or a new journey starts first.
createTrigger("^In your haste, you trip and fall!$", function()
    if not taPackage.arenaJourney then return end
    local gen = taPackage.arenaJourneyGen or 0
    createTimer(ARENA_TRIP_RETRY_MS, function()
        if taPackage.arenaState and (taPackage.arenaJourneyGen or 0) == gen then
            arenaJourneyResendStep()
        end
    end, { repeating = false })
end, { type = "regex" })

-- =========================================================================
-- Thirst, hunger and potions in the arena
-- =========================================================================

-- In a group (see inGroup), drink from the waterskin the moment thirst bites.
-- Without one the game just refuses.
createTrigger("^You're thirsty\\.$", function()
    if taPackage.inGroup() then send("drink water") end
    taPackage.character.setCharacterStatus("Thirsty")
    if not taPackage.arenaState then return end
    if arenaCheckParched() then return end
    taPackage.needsDrinks = true
    if arenaCanDepartNow() then
        departForTavern()
    else
        echo("[arena] Thirsty — will buy drinks at next tavern visit.")
    end
end, { type = "regex" })

createTrigger("^You're hungry\\.$", function()
    taPackage.character.setCharacterStatus("Hungry")
    if not taPackage.arenaState then return end
    if arenaCheckParched() then return end
    taPackage.needsMeal = true
    if arenaCanDepartNow() then
        departForTavern()
    else
        echo("[arena] Hungry — will buy a meal at next tavern visit.")
    end
end, { type = "regex" })

-- A strength/agility potion wearing off. The line is identical for rowan and
-- hyssop, so it fires once per potion — we can't tell which lapsed and refresh
-- both. Like thirst/hunger: leave for the shop now if we're fighting or
-- ringing, otherwise flag it and the arrival handler makes the trip on the way
-- back. A second wear-off line mid-trip just re-sets the flag (idempotent).
createTrigger("^An odd tingling sensation washes over you briefly!$", function()
    if not taPackage.arenaState then return end
    -- One of our two stat potions lapsed. Track it so we know when they are all
    -- gone: the training hall refuses us while any is active (see arenaTryTrain).
    local active = math.max((taPackage.arenaPotionsActive or 0) - 1, 0)
    taPackage.arenaPotionsActive = active
    if checkTrainingNeeded() then
        -- A level is owed. We are deliberately letting the potions wear off so
        -- the hall will accept us — do NOT restock. The ring/kill decision points
        -- send us to train once this count reaches 0.
        echo("[arena] Potion lapsed (" .. active
            .. " still active) — draining before training.")
        return
    end
    -- A gold-farming run never restocks, whatever put a potion in the character.
    -- Its arena session is a sprint to one level, not an open-ended grind, so a
    -- fresh potion can only push the finish line out: the training hall refuses
    -- a tainted character, and the taint measured 22m 24s
    -- (logs/session-garbageman-2026-08-15T21-52-26.log) -- comfortably longer
    -- than the whole fight it would be extending.
    --
    -- The loop no longer buys potions at all (see ta_create.lua for why), so
    -- this now guards the leftovers: a potion drunk by hand, or a session that
    -- was still carrying a round when the change landed.
    if taPackage.goldFarming then
        echo("[arena] Potion lapsed (" .. active
            .. " still active) — gold-farming run, not restocking.")
        return
    end
    taPackage.needsPotions = true
    if arenaCanDepartNow() then
        departForShop()
    else
        echo("[arena] A potion wore off — will restock at next shop visit.")
    end
end, { type = "regex" })

-- =========================================================================
-- Training and promotion results, and their notifications
-- =========================================================================

-- How long to wait for the character sheet and inventory we ask for after training before
-- pushing the level-up notification without the HP/MP figures. The sheet comes
-- straight back; this only has to outlast a hiccup.
local LEVEL_UP_SHEET_WAIT_MS = 5000

-- Push the held "Leveled Up!" notification, filling in the stat gains and the
-- fee if the character sheet and inventory we asked for have landed. Called once
-- both have (noticeLevelUpStats / taPackage.noticeLevelUpGold) or from a
-- timeout, whichever comes first; whoever gets there clears the pending record
-- so the other is a no-op.
--
-- On taPackage rather than local because the Vitality trigger is registered
-- ~3000 lines above this point and can't see a local declared down here. It only
-- ever runs after the chunk has finished loading, so the field is set by then.
function taPackage.flushLevelUpNotification()
    local pending = taPackage.levelUpPush
    if not pending then return end
    taPackage.levelUpPush = nil

    -- The other half of the level-up silence during a gold-farming run; see
    -- checkLevelUpNotification for why. Held here rather than at the point the
    -- push is armed, so the fresh `st` that fills in the new HP/MP is still
    -- asked for and the tracked maxima stay current.
    if taPackage.goldFarming then return end

    -- "434" alone doesn't say how good the level was; "gain of 23" does. We can
    -- only show it if we knew the old maximum (we may never have polled `st`).
    local function gain(before, after, unit)
        if not before then return "" end
        return ", gain of " .. taPackage.utils.formatWithCommas(after - before) .. " " .. unit
    end

    local lines = { pending.headline }
    local _, hp = taPackage.character.getVitality()
    if hp then
        lines[#lines + 1] = "- New HP: " .. taPackage.utils.formatWithCommas(hp) .. gain(pending.hpBefore, hp, "HP")
    end
    -- Only spell casters have a mana pool; for everyone else the sheet says
    -- "0 / 0" every level and the line would be noise.
    local _, mp = taPackage.character.getMana()
    if mp and mp > 0 then
        lines[#lines + 1] = "- New MP: " .. taPackage.utils.formatWithCommas(mp) .. gain(pending.mpBefore, mp, "MP")
    end
    lines[#lines + 1] = "- Training cost: " .. (pending.cost and taPackage.utils.formatWithCommas(pending.cost) or "?") .. " gold"
    lines[#lines + 1] = "- Gold: " .. (pending.goldAfter and taPackage.utils.formatWithCommas(pending.goldAfter) or "?")
    taPackage.utils.sendNtfy("Leveled Up!", table.concat(lines, "\n"), true)
end

-- A fresh Vitality line arrived while a level-up push is held. Answered by the
-- Vitality trigger for *every* sheet, so ignore one whose maximum still reads
-- pre-level: that's an unrelated `st` (e.g. tavern mode's HP heartbeat) that was
-- already in flight when we trained, and flushing on it would report no gain.
-- The timeout still pushes if our own sheet somehow never shows up.
function taPackage.noticeLevelUpStats()
    local pending = taPackage.levelUpPush
    if not pending then return end
    if pending.hpBefore and select(2, taPackage.character.getVitality()) == pending.hpBefore then return end
    pending.statsLanded = true
    if pending.goldAfter then taPackage.flushLevelUpNotification() end
end

-- The inventory we asked for after training has landed: the fee is the gold we
-- read just before `buy training` minus the gold we have now. Any `i` answered
-- after the hall's success line was answered after the purchase, so unlike the
-- sheet there is no stale reply to screen out. Done here rather than in the
-- flush so a gold-farming run, which pushes nothing, still records the fee.
function taPackage.noticeLevelUpGold()
    local pending = taPackage.levelUpPush
    if not pending or pending.goldAfter then return end
    pending.goldAfter = taPackage.character.getGold()
    if pending.goldBefore then
        pending.cost = pending.goldBefore - pending.goldAfter
        taPackage.db.recordService("training", "guild", pending.cost)
        echo("[arena] Training cost " .. pending.cost .. " gold.")
    end
    if pending.statsLanded then taPackage.flushLevelUpNotification() end
end

-- Guild-hall confirmation that a training session succeeded (its reply to `buy
-- training`; the message runs three lines, we key on the first). Do the things
-- that only make sense once we've actually leveled:
--   * Bank the level locally. The game's own `Level:` line lags until the next
--     status poll, and a stale level would keep checkTrainingNeeded() true and
--     re-trigger a training trip on the next kill.
--   * Measure the fee. The success line carries no crown amount, so both
--     callers send `i` just before `buy training` and we send another now; the
--     fee is the difference (taPackage.noticeLevelUpGold). The tutorial says it
--     is (next level x 5) gold, but that is the game's word, not a measurement.
--   * Re-buy the stat potions we drained to be allowed to train — unless another
--     banked level is still owed, in which case keep draining and train again.
createTrigger("^After a rigorous mental and physical training session, you managed to blend$", function()
    if not taPackage.arenaState then return end
    local lvl = taPackage.character.getLevel()
    -- `buy promotion` answers with this very line too, and only its third line
    -- says which it was. At the top of a ladder there is no level to train to,
    -- so here it can only be a promotion: leave it to the bestowal trigger below
    -- rather than bank a level 26 that does not exist.
    local thresholds = taPackage.xp.thresholds[taPackage.character.getClass() or ""]
    if lvl and thresholds and not thresholds[lvl + 1] then return end
    if lvl then
        local newLevel = lvl + 1
        taPackage.character.setLevel(newLevel)
        echo("[arena] Trained to level " .. newLevel .. ".")
        -- Off-screen heads-up that the drain-then-train actually completed. This
        -- fires on the confirmed level-up (distinct from checkLevelUpNotification's
        -- "Time to Level Up!", which fires earlier when the XP threshold is crossed).
        --
        -- A level always raises Vitality (and Mana for a caster), but the hall's
        -- message carries neither figure and our own maxima are whatever the last
        -- `st` said — i.e. pre-level. So hold the push, ask for a fresh sheet, and
        -- assemble it when the new Vitality line lands. Mana is printed just above
        -- Vitality on the sheet, so both are current by the time we flush. The
        -- `i` after it measures the fee against the gold read before the buy.
        taPackage.levelUpPush = {
            headline = "[" .. (taPackage.character.getName() or "?") .. "] trained to level "
                .. newLevel .. "!",
            goldBefore = taPackage.character.getGold(),
            hpBefore = select(2, taPackage.character.getVitality()),
            mpBefore = select(2, taPackage.character.getMana()),
        }
        send("st")
        send("i")
        createTimer(LEVEL_UP_SHEET_WAIT_MS, taPackage.flushLevelUpNotification, { repeating = false })
    end
    -- Restocking is an arena-loop concern only: outside a run there is no errand
    -- trip to hang the flag on, and leaving it set would send the next run to the
    -- shop for no reason.
    if taPackage.arenaState and not checkTrainingNeeded() then
        taPackage.needsPotions = true
    end
end, { type = "regex" })

-- Push the held "Promoted!" notification. Called when the inventory we asked for
-- lands (taPackage.noticePromotionGold) or from a timeout, whichever is first;
-- whoever gets there clears the pending record so the other is a no-op.
function taPackage.flushPromotionNotification()
    local pending = taPackage.promotionPush
    if not pending then return end
    taPackage.promotionPush = nil
    taPackage.utils.sendNtfy("Promoted!", table.concat({
        "[" .. (taPackage.character.getName() or "?") .. "] bought promotion!",
        "- Old class: " .. (pending.oldClass or "?"),
        "- New class: " .. pending.newClass,
        "- Promotion cost: " .. (pending.cost and taPackage.utils.formatWithCommas(pending.cost) or "?") .. " gold",
        "- Gold: " .. (pending.goldAfter and taPackage.utils.formatWithCommas(pending.goldAfter) or "?"),
    }, "\n"), true)
end

-- The inventory after the promotion: the fee is the gold read just before `buy
-- promotion` minus the gold now, measured the same way as the training fee.
function taPackage.noticePromotionGold()
    local pending = taPackage.promotionPush
    if not pending then return end
    pending.goldAfter = taPackage.character.getGold()
    if pending.goldBefore then
        pending.cost = pending.goldBefore - pending.goldAfter
        taPackage.db.recordService("promotion", "guild", pending.cost)
        echo("[arena] Promotion cost " .. pending.cost .. " gold.")
    end
    taPackage.flushPromotionNotification()
end

-- The third line of the hall's reply to `buy promotion`, and the only one that
-- differs from training's: "previously known. The guild bestows upon you the
-- title of knight!" (archived session-tojolias-2026-08-20T19-44-24.log). This is
-- the one moment a character's class changes, so everything keyed on it is
-- brought across here rather than left for the next `st`:
--   * The class, which the status bar shows and every XP table is looked up by.
--     The title is lower case; the class line and ta_xp.lua are title case.
--   * Level 1 and 0 XP, the bottom of the new 105-level ladder. Clearing
--     xpChange after setExperience drops the "XP moved" marker it just armed,
--     which would flash the old XP measured against the new ladder.
--   * earnedLevel, or the level-up push would stay silent until the new ladder
--     passed 25.
-- Not gated on an arena run: a hand-typed promotion changes the class just the
-- same, and the push is wanted either way.
createTrigger("The guild bestows upon you the title of (.+)!$", function(matches)
    local oldClass = taPackage.character.getClass()
    local newClass = matches[2]:gsub("(%a)(%a*)", function(first, rest)
        return first:upper() .. rest
    end)
    taPackage.character.setClass(newClass)
    taPackage.character.setLevel(1)
    taPackage.character.setExperience(0)
    taPackage.xpChange = nil
    taPackage.character.setEarnedLevel(1)
    echo("[arena] Promoted: " .. (oldClass or "?") .. " -> " .. newClass .. ".")
    taPackage.promotionPush = { oldClass = oldClass, newClass = newClass, goldBefore = taPackage.character.getGold() }
    send("st")
    send("i")
    createTimer(LEVEL_UP_SHEET_WAIT_MS, taPackage.flushPromotionNotification, { repeating = false })
    -- The stat potions were dispelled for the trip; restock them on the way home
    -- and fight on as the new class.
    if taPackage.arenaState then taPackage.needsPotions = true end
end, { type = "regex" })

-- The hall's refusal: "You are not ready for a promotion, you must first achieve
-- greater power, and gain wider knowledge of your abilities." Seen only below 25,
-- which checkPromotionNeeded already rules out, so reaching it means a rule we
-- do not know. Stop asking for the rest of the run (or every trip home would
-- walk back to the hall) and say so, since the run is now grinding XP that buys
-- nothing.
createTrigger("^You are not ready for a promotion", function()
    if not taPackage.arenaState then return end
    taPackage.arenaPromotionRefused = true
    echo("[arena] Promotion refused — fighting on without it.")
    taPackage.utils.sendNtfy("Promotion refused", (taPackage.character.getName() or "?")
        .. " was told it is not ready for a promotion. Fighting on without it.")
end, { type = "regex" })

-- =========================================================================
-- The temple: restoring and healing
-- =========================================================================

-- The taint is gone: every stat is back at base, so the hall will take us. Zero
-- the count outright rather than decrementing it — restoring does not care how
-- many potions were up, and this is the one line that proves the buy landed. The
-- gold and the service record are handled by this line's other trigger, way up
-- with the character-sheet accounting.
createTrigger("^The priests restore your body and mind to it's former state for \\d+ crowns\\.$", function()
    if not taPackage.arenaState then return end
    taPackage.arenaPotionsActive = 0
    echo("[arena] Potion taint bought off — training hall will accept us now.")
end, { type = "regex" })

-- Backstop for a mistimed training trip. We normally reach the hall only once
-- arenaPotionsActive has drained to 0, but if that count was off (e.g. a potion
-- we didn't drink was still active) the hall refuses us with this line. We did
-- NOT level and were not charged (the success trigger above never fired), so just
-- force the drain count positive: the ring loop keeps fighting until the next
-- wear-off and then retries training.
--
-- That count going positive is also what routes us to the temple on the next
-- decision point (arenaTryTrain), so a character whose potions we never knew
-- about — one that drank before `rg` started, say — self-corrects into a
-- restore trip rather than fighting out a 22-minute taint.
createTrigger("^Your mind and body must be whole and untainted before you may train\\.$", function()
    if not taPackage.arenaState then return end
    taPackage.arenaPotionsActive = math.max(taPackage.arenaPotionsActive or 0, 1)
    echo("[arena] Training refused — still potion-tainted; fighting until it wears off.")
end, { type = "regex" })

createTrigger("^The priests heal all your wounds for \\d+ crowns\\.$", function(matches)
    if taPackage.arenaState ~= "healing" then return end
    -- Always walk back to the arena from the temple. If we are also hungry or
    -- thirsty, the arrival handler sets out for the bar as a separate round
    -- trip rather than routing temple->bar directly -- arriving home is the one
    -- place errands get dispatched, so every errand starts from there.
    local nav = arenaNav()
    taPackage.arenaState = "returning"
    arenaJourneyStart(nav.fromTemple, nav.arenaRoom, nav.templeRoom)
end, { type = "regex" })

-- =========================================================================
-- Blocked moves, exhaustion and spell results
-- =========================================================================
--
-- Mostly the arena's: a walk-out a monster blocks, a swing or cast refused for
-- exhaustion, a spell that lands or fizzles. The mana and vitality bookkeeping
-- for our own casts and heals sits here too, and runs in or out of the arena.

-- Any walk-out that gets blocked by a monster — fleeing to the temple, an errand
-- run to the bar ("tavern") or magic shop ("potions"), or a level being banked
-- via the temple ("restoring") or the guild hall ("training", "promoting") — retries the same
-- step until a between-attacks window opens. arenaCanDepartNow now stops us from
-- departing into an in-flight summon, so this is a backstop for the case where a
-- monster arrives after we've stepped out (e.g. another player's ring on the
-- shared gong).
--
-- Every state that walks out of the arena has to be listed here, and every
-- omission has cost a session. Omitting "potions" is what left problem.log
-- wedged; omitting "restoring"/"training" is what left teekywiki standing in
-- front of a flame giantess for five minutes on 2026-09-03 (archived
-- session-teekywiki-2026-09-03T12-57-00.log, 6777-6874) — nothing re-armed the
-- move, and a detour state does not swing either, so it was a dead stop.
createTrigger("^You cannot leave in the heat of battle!$", function()
    local st = taPackage.arenaState
    if st ~= "fleeing" and st ~= "tavern" and st ~= "potions"
        and st ~= "restoring" and st ~= "training" and st ~= "promoting" then return end
    if taPackage.arenaFleeTimerPending then return end
    taPackage.arenaFleeTimerPending = true
    local gen = taPackage.arenaRetryGeneration or 0
    -- Retry the exact step that was blocked, not a hardcoded "w": the second
    -- arena's first step out is "s". arenaLastCmd is the blocked command.
    local cmd = taPackage.arenaLastCmd or "w"
    createTimer(2000, function()
        taPackage.arenaFleeTimerPending = false
        if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
            arenaSend(cmd)
        end
    end, { repeating = false })
end, { type = "regex" })

-- A paced journey only issues moves from a fixed route, so a "no exit" reply means
-- the walk has lost sync with the character's true position. No room line follows,
-- so the step index can never advance — the walk wedges forever (something-went-wrong
-- .log:1899, where the character then slowly died of thirst). This is unrecoverable
-- in-script; bail out of the game before thirst/hunger grinds us down. Scoped to an
-- active journey so a stray manual move never trips it.
createTrigger("^Sorry, there's no exit in that direction\\.$", function()
    if not taPackage.arenaState or not taPackage.arenaJourney then return end
    arenaEmergencyExit("Navigation lost (no exit on a journey step)")
end, { type = "regex" })

createTrigger("^Sorry, you'll have to rest a while before you can move\\.$", function(matches)
    if not taPackage.arenaState then return end
    local cmd = taPackage.arenaLastCmd
    local gen = taPackage.arenaRetryGeneration or 0
    if cmd then
        -- In a flee we're taking hits every round, so poll for the rest clock to
        -- clear every 2s (matching the heat-of-battle retry) rather than waiting
        -- the full 30s a non-urgent errand walk can afford. Each retry that's
        -- still blocked re-emits this line, so the 2s cadence re-arms naturally.
        local delay = taPackage.arenaState == "fleeing" and 2000 or 30000
        -- Say so out loud. Thirty seconds of nothing is indistinguishable from a
        -- hang, and the only line printed anywhere near it is the melee retry's
        -- "melee-retry in NNNNNms" -- a stale attack left over from the swing
        -- that just landed, which reads exactly like "still fighting, ignoring
        -- the walk". That pair cost a real training trip: the first step of the
        -- walk to the hall was refused here, waited silently, and was stopped by
        -- hand about 15s in on the entirely reasonable assumption that it had
        -- wedged (logs/session-garbageman-2026-08-15T19-21-55.log, 1765-1786).
        -- Not debug-gated: the point is to be visible when nobody thought to
        -- turn debug on.
        echo("[arena] Move \"" .. cmd .. "\" refused (still resting) — retrying in "
            .. math.floor(delay / 1000) .. "s.")
        createTimer(delay, function()
            if taPackage.arenaState and (taPackage.arenaRetryGeneration or 0) == gen then
                arenaSend(cmd)
            end
        end, { repeating = false })
    end
end, { type = "regex" })

createTrigger("^You are still physically exhausted from your previous activities!$", function(matches)
    if not taPackage.arenaState then return end
    arenaDebugEcho("exhausted")
    -- An Acolyte does NOT self-heal here. Casting motu on ourselves mid-fight
    -- keeps us in the arena past the point where we should leave; instead we
    -- let checkFleeArena pull us out at the regular flee threshold and buy
    -- healing at the temple like every other class.
    -- A stable combat generation (not the per-send retry counter) keeps these
    -- timers alive even though the cast loop keeps firing arenaSend meanwhile.
    local gen = taPackage.arenaCombatGen or 0
    if taPackage.arenaState == "ringing" then
        -- The blocked physical action was the gong ring (the kill just spent the
        -- physical clock). Nothing to do here: the scan pump (arenaScanRoom) is
        -- already re-arming on its own timer and will re-scan and re-ring once
        -- the clock recovers. Scheduling our own retry here was the source of the
        -- deadlock — it shared flags with the pump and could drop the only
        -- outstanding retry. Let the pump own ring liveness.
        --
        -- Traced rather than acted on: paired with the ring-sent/ring-accepted
        -- lines, this is what will say whether the gong can be reckoned the way
        -- melee now is. See the comment on arenaRing.
        arenaDebugEcho("ring-exhausted  since-swing " .. arenaSinceLabel(taPackage.arenaLastSwingAt)
            .. "  since-ring " .. arenaSinceLabel(taPackage.arenaLastRingAt))
        return
    else
        -- Melee is on cooldown. Reckon the wait from the last accepted swing
        -- rather than polling the whole window; see ARENA_PHYSICAL_COOLDOWN_MS.
        -- Whichever is larger wins, so a missing or stale timestamp (nothing
        -- landed recently — we just got back from an errand, or the ring rather
        -- than a swing spent the clock) makes the remainder negative and leaves
        -- us on the tail poll, which is the old behaviour and always safe.
        taPackage.arenaAttackPending = false
        local delay = ARENA_EXHAUSTED_RETRY_MS
        local lastSwingAt = taPackage.arenaLastSwingAt
        if lastSwingAt then
            local remaining = ARENA_PHYSICAL_COOLDOWN_MS
                - (nowMillis() - lastSwingAt)
                - ARENA_COOLDOWN_MARGIN_MS
            if remaining > delay then delay = remaining end
        end
        arenaDebugEcho("melee-retry in " .. delay .. "ms")
        createTimer(delay, function()
            if taPackage.arenaState and (taPackage.arenaCombatGen or 0) == gen then
                arenaAttack()
            end
        end, { repeating = false })
    end
end, { type = "regex" })

createTrigger("^You are still too mentally exhausted from your last incantation!$", function(matches)
    if not taPackage.arenaState then return end
    taPackage.arenaCastPending = false
    arenaDebugEcho("mentally-exhausted")
    -- The spell is on cooldown; retry the cast once the mental clock recovers.
    local gen = taPackage.arenaCombatGen or 0
    createTimer(30000, function()
        if taPackage.arenaState and (taPackage.arenaCombatGen or 0) == gen then
            arenaCast()
        end
    end, { repeating = false })
end, { type = "regex" })

createOutboundTrigger("^cast kamotu ", function()
    local current, max = taPackage.character.getMana()
    if current then
        taPackage.character.setMana(math.max(0, current - 1), max)
    end
    taPackage.lastSpellCast = "kamotu"
end, { type = "regex" })

createTrigger("^You intoned the spell for (.+) which healed (\\d+) damage!$", function(matches)
    local target = matches[2]
    local amount = tonumber(matches[3])
    -- A landed heal frees the cast loop to respond to the next injury. The
    -- land message doesn't name the spell, so record whichever heal we last
    -- cast (motu = self, kamotu = group); both produce this same line.
    taPackage.castPending = false
    healingBadge("HEALED " .. string.upper(target) .. " FOR " .. amount)
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", target, "hit", amount, "heal")
    if target == taPackage.character.getName() then
        local current, max = taPackage.character.getVitality()
        if current and amount then
            local healed = current + amount
            taPackage.character.setVitality(max and math.min(healed, max) or healed, max)
        end
    end
end, { type = "regex" })

-- The area heals (motumaru, kamotumaru, gimotumaru, kusamotumaru) hit everyone
-- friendly in the room at once, so instead of a per-target "You intoned the
-- spell for X" line the server prints one line carrying the amount each person
-- got — us included. Nothing tells us our own new HP, so add the heal to our
-- tracked vitality directly (clamped at max) rather than paying for an "st"
-- round trip. The non-heal area spells (dobudanimaru, cure poison) print the
-- same sentence *without* the ", healing N damage!" tail, so they don't match.
createTrigger("^You discharged the spell at friendly people in the area, healing (\\d+) damage!$",
    function(matches)
        local amount = tonumber(matches[2])
        -- An area heal spends the cast round like any other, so free the cast
        -- loop; leaving castPending set would wedge it waiting on a targeted
        -- heal that this cast displaced.
        taPackage.castPending = false
        healingBadge("HEALED GROUP FOR " .. amount)
        taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", "group", "hit", amount, "heal")
        local current, max = taPackage.character.getVitality()
        if current then
            local healed = current + amount
            taPackage.character.setVitality(max and math.min(healed, max) or healed, max)
        end
    end, { type = "regex" })

-- The receiving end of that same area heal tells us only that something good
-- happened — "Pelayo just discharged a very dark bluish mist at friendly people
-- in the area!" — with no amount and no new HP. Same trick as the trap and
-- hostile-AOE handlers: stash our HP, ask for a fresh "st", and let the Vitality
-- trigger recover the gain and badge it green. The mist's adjectives track the
-- spell tier ("bluish" / "dark bluish" / "very dark bluish"), and the non-heal
-- area spells reuse the sentence with their own mist ("thick greyish"), so match
-- on the "at friendly people" signature alone and let a zero gain go unbadged.
-- Don't anchor the end: a long enough caster+spell pair word-wraps the trailing
-- "in the area!" onto a second physical line.
createTrigger("^(.+) just discharged .+ at friendly people", function(matches)
    taPackage.groupHealCaster = matches[2]
    taPackage.groupHealHpBefore = taPackage.character.getVitality()
    send("st")
end, { type = "regex" })

-- A party member healing us badges "HEALED BY <healer> FOR N" and adds the
-- amount back to our vitality. The heal comes in a growing list of tiers that
-- differ only in how the spell is described — "a minor healing spell", "a
-- healing spell", "a greater healing spell", "a very powerful healing spell",
-- "a healing spell fit for a God" — so match the frame and wildcard the
-- description. Spelling the tiers out meant each new one the priest learned
-- went unbadged until someone noticed.
--
-- The end is deliberately unanchored. Tele-Arena word-wraps at 78 columns, so
-- whether the trailing " damage!" lands on this physical line or the next one
-- depends on the caster's name length and the size of the number: at 75 and 77
-- characters "greater" and a two-letter caster fit, at 82 "very powerful" and
-- "fit for a God" wrap. Stopping at the number matches either way.
local function applyPartyHeal(matches)
    local healer = matches[2]
    local amount = tonumber(matches[3])
    healingBadge("HEALED BY " .. string.upper(healer) .. " FOR " .. amount)
    local current, max = taPackage.character.getVitality()
    if current and amount then
        local healed = current + amount
        taPackage.character.setVitality(max and math.min(healed, max) or healed, max)
    end
end

createTrigger("^(.+) just intoned .+ for you which healed (\\d+)", applyPartyHeal,
    { type = "regex" })

createOutboundTrigger("^cast komiza ", function()
    local current, max = taPackage.character.getMana()
    if current then
        taPackage.character.setMana(math.max(0, current - 1), max)
    end
    taPackage.lastSpellCast = "komiza"
end, { type = "regex" })

createOutboundTrigger("^cast toduza ", function()
    local current, max = taPackage.character.getMana()
    if current then
        taPackage.character.setMana(math.max(0, current - 2), max)
    end
    taPackage.lastSpellCast = "toduza"
end, { type = "regex" })

createTrigger("^You discharged the spell at the (.+) for (\\d+) damage!$", function(matches)
    local monster = matches[2]
    local amount = tonumber(matches[3])
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "hit", amount, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-hit")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createTrigger("^You confuse the key syllables and the spell fails!$", function()
    local monster = taPackage.lastAttackTarget or "unknown"
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "fizzle", nil, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-fizzle")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createTrigger("^Your spell was negated by the (.+)'s magickal defenses!$", function(matches)
    local monster = matches[2]
    taPackage.lastAttackTarget = monster
    taPackage.db.recordPlayerSpell(taPackage.lastSpellCast or "unknown", monster, "resist", nil, "offense")
    if taPackage.arenaState == "fighting" then
        taPackage.arenaCastPending = false
        arenaDebugEcho("our-spell-resist")
        if not checkFleeArena() then arenaCast() end
    end
end, { type = "regex" })

createOutboundTrigger("^cast motu ", function()
    local current, max = taPackage.character.getMana()
    if current then
        taPackage.character.setMana(math.max(0, current - 1), max)
    end
    taPackage.lastSpellCast = "motu"
end, { type = "regex" })
