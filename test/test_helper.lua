-- test_helper.lua
-- Mock Baud framework functions for testing triggers

SCRIPT_DIR = "./"

local M = {}

M.triggers = {}
M.aliases = {}
M.outboundTriggers = {}
M.sendCalls = {}
M.echoCalls = {}

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

function say(text) end

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

function M.resetAll()
    for k in pairs(M.triggers) do M.triggers[k] = nil end
    for k in pairs(M.aliases) do M.aliases[k] = nil end
    for k in pairs(M.outboundTriggers) do M.outboundTriggers[k] = nil end
    for k in pairs(M.sendCalls) do M.sendCalls[k] = nil end
    for k in pairs(M.echoCalls) do M.echoCalls[k] = nil end
    taPackage = nil
end

return M
