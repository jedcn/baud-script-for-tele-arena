-- test_helper.lua
-- Mock Baud framework functions for testing triggers

SCRIPT_DIR = "./"

local M = {}

M.triggers = {}
M.aliases = {}
M.outboundTriggers = {}
M.sendCalls = {}
M.echoCalls = {}
M.cechoBgCalls = {}
M.httpPostCalls = {}
M.dbCalls = {}
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
      table.insert(M.dbCalls, { method = "query", db = name, sql = sql, params = { ... } })
      return M.mockDbRows or {}
    end,
    queryOne = function(self, sql, ...)
      table.insert(M.dbCalls, { method = "queryOne", db = name, sql = sql, params = { ... } })
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

function createTrigger(pattern, callback, options)
    local luaPattern = regexToLuaPattern(pattern)
    table.insert(M.triggers, {
        pattern = luaPattern,
        originalPattern = pattern,
        callback = callback,
        options = options or {}
    })
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

function createTimer(interval, callback, options)
    return "mock_timer_id"
end

function setStatus(fn) end

function send(text)
    table.insert(M.sendCalls, text)
end

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

function M.simulateLine(text)
    for _, trigger in ipairs(M.triggers) do
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
    for k in pairs(M.echoCalls) do M.echoCalls[k] = nil end
    for k in pairs(M.cechoBgCalls) do M.cechoBgCalls[k] = nil end
    for k in pairs(M.httpPostCalls) do M.httpPostCalls[k] = nil end
    for k in pairs(M.dbCalls) do M.dbCalls[k] = nil end
    M.mockDbOneRow = nil
    M.mockDbRows = {}
    M.mockExecuteReturn = nil
    taPackage = nil
end

return M
