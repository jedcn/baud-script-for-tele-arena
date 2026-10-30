-- ta_follow.lua -- following another character: `ta.follow <name>`
--
-- As a follower: walk where the leader walks, run the commands the leader sends
-- over group chat (`confer <command>`), join the leader's fights, mirror the
-- leader's errands (a drink, a meal, the temple), and poll `status` so a follow
-- session can report the XP it earned. As a leader: note who has asked to join
-- our group (taPackage.followedBy).
--
-- Loaded by main.lua with dofile, where the Follow section used to sit, so
-- every trigger and alias is registered in the same order as before. A separate
-- chunk; the seam runs through taPackage:
--
--   in    taPackage.kill (ta_kill.lua) for joining a fight and for the
--         leader's `confer` commands, taPackage.character
--   out   taPackage.follow.startXpPoll / .stopXpPoll (stop-all-scripts) /
--         .scheduleXpPoll, and the state, which keeps its taPackage.follow*
--         names because it survives reloadScript(): followTarget, followedBy,
--         followDebug, followXpPollActive, ...

taPackage.follow = {}

-- =========================================================================
-- Follow
-- =========================================================================

local dirShort = {
    north = "n",
    south = "s",
    east = "e",
    west = "w",
    northeast = "ne",
    northwest = "nw",
    southeast = "se",
    southwest = "sw",
    up = "u",
    down = "d",
}

-- While following, send `status` and `i` every 5 minutes so the log keeps
-- capturing XP and gold.
-- Followers never type `st` themselves, so without this a session's only XP
-- readings were at `ta.follow` and (if anyone remembered) `ta.unfollow`. A
-- generation counter makes the rescheduled one-shot timer self-cancel, mirroring
-- scheduleArenaXpCheck. Fields on taPackage, not locals: main.lua's local budget
-- is tight (see CLAUDE.md).
taPackage.FOLLOW_XP_POLL_MS = 300000

function taPackage.follow.scheduleXpPoll()
    local gen = taPackage.followXpPollGen or 0
    createTimer(taPackage.FOLLOW_XP_POLL_MS, function()
        if (taPackage.followXpPollGen or 0) ~= gen then return end
        taPackage.followXpPollPending = true
        send("status")
        send("i")
        taPackage.follow.scheduleXpPoll()
    end, { repeating = false })
end

function taPackage.follow.startXpPoll()
    taPackage.followXpPollGen = (taPackage.followXpPollGen or 0) + 1
    taPackage.followXpPollActive = true
    taPackage.follow.scheduleXpPoll()
end

function taPackage.follow.stopXpPoll()
    taPackage.followXpPollGen = (taPackage.followXpPollGen or 0) + 1
    taPackage.followXpPollActive = false
    taPackage.followXpPollPending = false
end

-- reloadScript() clears pending timers but taPackage survives, so a reload
-- mid-follow would silently end the poll. Re-arm it on load.
if taPackage.followXpPollActive then
    taPackage.follow.startXpPoll()
end

-- `ta.follow <name>` joins and shadows a leader. An optional trailing " debug"
-- turns on tracing for the whole follow session: the join decisions below, plus
-- every kill the follow spawns (followDebug feeds killDebugEcho, so the debug
-- "follows through" without each kill having to be flagged individually).
createAlias("^ta\\.follow (.+)$", function(matches)
    local rest = matches[2]
    local name, debug = rest, false
    local stripped = rest:match("^(.-) debug$")
    if stripped then
        name, debug = stripped, true
    end
    taPackage.followTarget = name:lower()
    taPackage.followDebug = debug
    -- Joining someone else's group means we're no longer a leader; drop any
    -- (possibly stale) follower list so we don't keep showing the Leader tag.
    taPackage.followedBy = nil
    local debugSuffix = debug and " (debug mode)" or ""
    echo("[follow] Now following: " .. taPackage.followTarget .. debugSuffix)
    send("join " .. name)
    -- Begin a group session: capture our starting XP so `ta.unfollow` can report
    -- the gain. The Experience line from this status is consumed by the
    -- followStartXpPending branch of the Experience trigger.
    taPackage.followStartXpPending = true
    taPackage.followEndXpPending = false
    send("status")
    taPackage.follow.startXpPoll()
end, { type = "regex" })

-- `ta.unfollow` ends the group session started by `ta.follow`: it leaves the
-- group, clears all follow state, then sends `status` so the Experience trigger
-- can report how much XP we gained over the session.
createAlias("^ta\\.unfollow$", function()
    send("leave")
    taPackage.followTarget = nil
    taPackage.followDebug = nil
    taPackage.followedBy = nil
    taPackage.followStartXpPending = false
    taPackage.followEndXpPending = true
    taPackage.follow.stopXpPoll()
    echo("[follow] Left the group.")
    send("status")
end, { type = "regex" })

createTrigger("^(.+) is asking to join your group\\.$", function(matches)
    -- Only the group leader can add members. When we're following someone we're
    -- a member, not the leader, yet the game shows this line to the whole group;
    -- a reflexive `add` from a follower just earns "Sorry, you are not the leader
    -- of a group." Leave it to the real leader.
    if taPackage.followTarget then return end
    local name = matches[2]
    if not taPackage.followedBy then taPackage.followedBy = {} end
    table.insert(taPackage.followedBy, name)
    send("add " .. name:lower())
    echo("[follow] " .. name .. " is now following you.")
end, { type = "regex" })

-- The leader can drive followers over group chat with `confer <command>`,
-- which everyone sees as "From <leader> (to group): <command>". Only an
-- allowlisted set of commands runs; anything else is ignored. The speaker
-- must be the leader we're following, so our own conferred lines won't match.
createTrigger("^From (.+) \\(to group\\): (.+)$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    local command = matches[3]
    local killMonster = command:match("^kill (.+)$")
    if killMonster then
        taPackage.kill.start(killMonster, taPackage.followDebug)
    elseif command == "kill-stop" then
        taPackage.kill.stop()
    elseif command == "heal-most-injured-party-member" then
        if taPackage.character.isClass("Acolyte") then
            taPackage.kill.healMostInjuredPartyMember()
        end
    end
end, { type = "regex" })

-- When the leader we're following engages a monster, join the fight on the same
-- target via the kill loop. The kill loop's death trigger stops us naturally if
-- someone else lands the killing blow first. The skip-while-already-killing
-- branch is logged in debug because it's the usual reason a follower fails to
-- join the leader in a new room: a stale killActive (from a monster we never saw
-- die) suppresses every later join until the loop is cleared.
local function followJoinKill(attacker, monster)
    if not taPackage.followTarget then return end
    if attacker:lower() ~= taPackage.followTarget then return end
    if taPackage.killActive then
        taPackage.kill.debugEcho("join-skip: already killing " .. tostring(taPackage.killTarget)
            .. " (leader engaged " .. monster .. ")")
        return
    end
    taPackage.kill.debugEcho("join: leader engaged " .. monster .. " — starting kill")
    taPackage.kill.start(monster, taPackage.followDebug)
end

createTrigger("^(.+) just attacked the (.+) with .+!$", function(matches)
    followJoinKill(matches[2], matches[3])
end, { type = "regex" })

-- A monster dodging the leader's first swing is the same signal to join in;
-- here the monster comes first and the leader is in the possessive form.
createTrigger("^The (.+) barely dodged (.+)'s .+!$", function(matches)
    followJoinKill(matches[3], matches[2])
end, { type = "regex" })

-- The leader swinging and missing still means they're engaging that monster.
createTrigger("^(.+)'s poorly executed attack misses the (.+)!$", function(matches)
    followJoinKill(matches[2], matches[3])
end, { type = "regex" })

-- When the leader buys a drink, the follower buys one too.
createTrigger("^The barmaid brings a drink over to (.+) in exchange for a few coins\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("b drink")
end, { type = "regex" })

-- When the leader buys a hot meal, the follower buys one too. The message
-- wraps across lines, so match only the opening clause that carries the name.
createTrigger("^The barmaid brings a hot meal over to (\\S+) in exchange", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("buy meal")
end, { type = "regex" })

-- When the leader gets healed at the temple, the follower buys healing too.
-- Match the opening clause only; the full message wraps across lines.
createTrigger("^The temple priests take (\\S+) into another chamber", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("buy healing")
end, { type = "regex" })

createTrigger("^(.+) has just gone to the (.+)\\.$", function(matches)
    if not taPackage.followTarget then return end
    local name = matches[2]:lower()
    if name ~= taPackage.followTarget then return end
    local direction = matches[3]:lower()
    local cmd = dirShort[direction]
    if cmd then send(cmd) end
end, { type = "regex" })

createTrigger("^(.+) has just gone downward\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("d")
end, { type = "regex" })

createTrigger("^(.+) has just gone upward\\.$", function(matches)
    if not taPackage.followTarget then return end
    if matches[2]:lower() ~= taPackage.followTarget then return end
    send("u")
end, { type = "regex" })
