-- test_helper.lua
-- Mock Baud framework functions for testing triggers

SCRIPT_DIR = "./"

local M = {}

M.triggers = {}
M.aliases = {}
M.outboundTriggers = {}
M.sendCalls = {}
M.runCommandCalls = {}
M.echoCalls = {}
M.cechoBgCalls = {}
M.httpPostCalls = {}
M.httpRequestCalls = {}
M.dbCalls = {}
M.timers = {}
M.mockDbOneRow = nil
M.mockDbRows = {}
M.mockExecuteReturn = nil

local function makeDb(name)
  return {
    path = "/mock/" .. name,
    execute = function(self, sql, ...)
      table.insert(M.dbCalls, { method = "execute", db = name, sql = sql, params = { ... } })
      return M.mockExecuteReturn or 0
    end,
    query = function(self, sql, ...)
      local params = { ... }
      table.insert(M.dbCalls, { method = "query", db = name, sql = sql, params = params })
      -- mockDbRows may be a static array (returned for every query) or a
      -- function(sql, params) for tests that need different rows per query
      -- (e.g. roomIdsByName vs roomExitDirections in one call).
      if type(M.mockDbRows) == "function" then
        return M.mockDbRows(sql, params)
      end
      return M.mockDbRows or {}
    end,
    queryOne = function(self, sql, ...)
      local params = { ... }
      table.insert(M.dbCalls, { method = "queryOne", db = name, sql = sql, params = params })
      -- mockDbOneRow may be a static row (returned for every queryOne) or a
      -- function(sql, params) for tests that need different rows per query
      -- (e.g. slug-collision probes vs. a following SELECT id).
      if type(M.mockDbOneRow) == "function" then
        return M.mockDbOneRow(sql, params)
      end
      return M.mockDbOneRow
    end,
  }
end

function dbOpen(name)
  return makeDb(name)
end

local function regexToLuaPattern(pattern)
    local luaPattern = pattern

    local hasStart = pattern:sub(1, 1) == "^"
    local hasEnd = pattern:sub(-1) == "$"

    if hasStart then luaPattern = luaPattern:sub(2) end
    if hasEnd then luaPattern = luaPattern:sub(1, -2) end

    luaPattern = luaPattern:gsub("%%", "%%%%")
    luaPattern = luaPattern:gsub("\\d", "%%d")
    luaPattern = luaPattern:gsub("\\s", "%%s")
    luaPattern = luaPattern:gsub("\\S", "%%S")
    luaPattern = luaPattern:gsub("\\w", "%%w")
    luaPattern = luaPattern:gsub("\\%(", "%%(")
    luaPattern = luaPattern:gsub("\\%)", "%%)")
    luaPattern = luaPattern:gsub("\\%?", "%%?")
    luaPattern = luaPattern:gsub("\\%.", "%%.")
    luaPattern = luaPattern:gsub("%-", "%%-")

    if hasStart then luaPattern = "^" .. luaPattern end
    if hasEnd then luaPattern = luaPattern .. "$" end

    return luaPattern
end

local nextTriggerId = 0

function createTrigger(pattern, callback, options)
    local luaPattern = regexToLuaPattern(pattern)
    nextTriggerId = nextTriggerId + 1
    local id = "trigger_" .. nextTriggerId
    table.insert(M.triggers, {
        id = id,
        pattern = luaPattern,
        originalPattern = pattern,
        callback = callback,
        options = options or {}
    })
    return id
end

function removeTrigger(id)
    for i, trigger in ipairs(M.triggers) do
        if trigger.id == id then
            table.remove(M.triggers, i)
            return true
        end
    end
    return false
end

function createAlias(pattern, callback, options)
    table.insert(M.aliases, {
        pattern = pattern,
        callback = callback,
        options = options or {}
    })
end

function createOutboundTrigger(pattern, callback, options)
    table.insert(M.outboundTriggers, {
        pattern = pattern,
        callback = callback,
        options = options or {}
    })
end

-- Timers never fire on their own here: the script arms them constantly (scan
-- pumps, paced walks, retries) and letting them run would make every test
-- reentrant. Instead we record each one so a test can fire exactly the timer it
-- cares about via M.fireTimers. The script has no timer-cancellation API — it
-- guards stale callbacks with generation counters — so firing a "cancelled"
-- timer is legitimate and is how those guards get tested.
local function recordingCreateTimer(interval, callback, options)
    table.insert(M.timers, { interval = interval, callback = callback, options = options or {} })
    return "mock_timer_id"
end
createTimer = recordingCreateTimer

-- Fire every timer armed so far, oldest first. Callbacks commonly arm follow-up
-- timers (the scan pump re-arms itself); those are queued rather than fired in
-- this pass, so a self-arming pump advances one tick per call instead of looping
-- forever. `interval` optionally restricts the pass to timers armed for exactly
-- that many milliseconds — the ones it skips stay queued for a later pass.
function M.fireTimers(interval)
    local pending = M.timers
    M.timers = {}
    for _, timer in ipairs(pending) do
        if interval == nil or timer.interval == interval then
            timer.callback()
        else
            table.insert(M.timers, timer)
        end
    end
end

-- baud's millisecond clock. Held still by default so a test that doesn't care
-- about time gets deterministic behaviour; M.advanceMs moves it for the tests
-- that reckon against it (the physical-cooldown retry).
M.currentMs = 0

function nowMs()
    return M.currentMs
end

function M.advanceMs(delta)
    M.currentMs = M.currentMs + delta
end

-- baud's window onto the host environment. Empty by default, so a test that
-- doesn't set M.env sees every variable unset -- which is what a hand-launched
-- baud looks like, and keeps auto-login dormant unless a test asks for it.
M.env = {}

function getenv(name)
    return M.env[name]
end

function setStatus(fn) end

function send(text)
    table.insert(M.sendCalls, text)
end

-- baud's runCommand: the line takes the path typed input takes, so an alias
-- runs rather than being sent as text. Unlike M.simulateAlias, which fires
-- every alias whose pattern matches, this stops at the first match and falls
-- through to send() when nothing matches -- that is what
-- AliasManager.processInput does.
local function mockRunCommand(text)
    table.insert(M.runCommandCalls, text)
    for _, alias in ipairs(M.aliases) do
        local luaPattern = regexToLuaPattern(alias.pattern)
        local matches = {string.match(text, luaPattern)}
        if #matches > 0 or string.match(text, luaPattern) then
            if #matches == 0 then matches = {} end
            table.insert(matches, 1, text)
            alias.callback(matches)
            return
        end
    end
    send(text)
end
runCommand = mockRunCommand

function echo(text)
    table.insert(M.echoCalls, text)
end

function cecho(color, text)
    table.insert(M.echoCalls, text == nil and color or text)
end

function cechoBg(color, backgroundColor, text, bold)
    table.insert(M.echoCalls, text)
    table.insert(M.cechoBgCalls, { color = color, backgroundColor = backgroundColor, text = text, bold = bold })
end

function say(text) end

function httpPost(url, body, callback)
    table.insert(M.httpPostCalls, { url = url, body = body, callback = callback })
end

function httpRequest(url, options, callback)
    table.insert(M.httpRequestCalls, { url = url, options = options, callback = callback })
end

function M.simulateLine(text)
    -- Iterate over a snapshot so a trigger callback that removes itself (or any
    -- trigger) via removeTrigger doesn't disturb this loop.
    local snapshot = {}
    for _, trigger in ipairs(M.triggers) do snapshot[#snapshot + 1] = trigger end
    for _, trigger in ipairs(snapshot) do
        local matches = {string.match(text, trigger.pattern)}
        if #matches > 0 or string.match(text, trigger.pattern) then
            if #matches == 0 then matches = {} end
            table.insert(matches, 1, text)
            trigger.callback(matches)
        end
    end
end

function M.simulateAlias(text)
    for _, alias in ipairs(M.aliases) do
        local luaPattern = regexToLuaPattern(alias.pattern)
        local matches = {string.match(text, luaPattern)}
        if #matches > 0 or string.match(text, luaPattern) then
            if #matches == 0 then matches = {} end
            table.insert(matches, 1, text)
            alias.callback(matches)
        end
    end
end

function M.simulateOutbound(text)
    for _, trigger in ipairs(M.outboundTriggers) do
        local luaPattern = regexToLuaPattern(trigger.pattern)
        local matches = {string.match(text, luaPattern)}
        if #matches > 0 or string.match(text, luaPattern) then
            if #matches == 0 then matches = {} end
            table.insert(matches, 1, text)
            trigger.callback(matches)
        end
    end
end

function M.clearDbCalls()
    for k in pairs(M.dbCalls) do M.dbCalls[k] = nil end
    M.mockDbOneRow = nil
    M.mockDbRows = {}
    M.mockExecuteReturn = nil
end

function M.findDbCall(method, sql_fragment)
    for _, call in ipairs(M.dbCalls) do
        if call.method == method and call.sql and string.find(call.sql, sql_fragment, 1, true) then
            return call
        end
    end
    return nil
end

function M.resetAll()
    for k in pairs(M.triggers) do M.triggers[k] = nil end
    for k in pairs(M.aliases) do M.aliases[k] = nil end
    for k in pairs(M.outboundTriggers) do M.outboundTriggers[k] = nil end
    for k in pairs(M.sendCalls) do M.sendCalls[k] = nil end
    for k in pairs(M.runCommandCalls) do M.runCommandCalls[k] = nil end
    for k in pairs(M.echoCalls) do M.echoCalls[k] = nil end
    for k in pairs(M.cechoBgCalls) do M.cechoBgCalls[k] = nil end
    for k in pairs(M.httpPostCalls) do M.httpPostCalls[k] = nil end
    for k in pairs(M.httpRequestCalls) do M.httpRequestCalls[k] = nil end
    for k in pairs(M.dbCalls) do M.dbCalls[k] = nil end
    M.timers = {}
    -- Several describe blocks swap in their own _G.createTimer to capture one
    -- specific timer, and most never put ours back. Left alone that leaks into
    -- every later block in the file — timers silently stop being recorded, and
    -- anything relying on M.timers sees an empty queue for reasons nothing in
    -- the test explains. Restoring it here scopes those stubs to their own block
    -- (they install after resetAll, so they still win where they are used).
    createTimer = recordingCreateTimer
    -- Same reasoning for runCommand: a test that clears it to stand in for an
    -- older baud must not leave every later test running without it.
    runCommand = mockRunCommand
    M.mockDbOneRow = nil
    M.mockDbRows = {}
    M.mockExecuteReturn = nil
    M.currentMs = 0
    M.env = {}
    taPackage = nil
end

return M
