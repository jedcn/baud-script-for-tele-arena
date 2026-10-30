-- ta_utils.lua -- small helpers every other file uses
--
-- Nothing here knows about the game: formatting numbers, the ntfy push, the
-- clock and trimming a line. All of it is on taPackage.utils.
--
-- Loaded by main.lua first, so every other file can count on it. Nothing here
-- reads anything from the other files.
--
-- main.lua's absoluteScriptDir is the one helper that stays behind, on purpose:
-- it reads its answer off the source of the chunk it is defined in. baud runs
-- main.lua as a string, so there it always takes the fallback directory, which
-- is where monsters.lua lives; defined in a file loaded by dofile it would
-- return the script directory instead, and quietly start a new, empty monster
-- database.

taPackage.utils = {}

-- Milliseconds since the epoch. baud supplies nowMs precisely because Lua
-- can't: os.time only resolves to the second, which can't tell 1.0s from 1.9s,
-- and os.clock measures CPU rather than elapsed time. Fall back to whole
-- seconds if the script is reloaded into a baud too old to have it -- the
-- timings go coarse, but nothing breaks.
function taPackage.utils.nowMillis()
    if nowMs then return nowMs() end
    return os.time() * 1000
end

function taPackage.utils.trimLine(line)
    return (line or ""):match("^%s*(.-)%s*$")
end

-- Group an integer into comma-separated thousands, e.g. 620046 -> "620,046".
-- Display-only (the status bar and notifications). Takes a number or a numeric
-- string, floors a fraction, and returns anything else as tostring() of it.
function taPackage.utils.formatWithCommas(n)
    local num = tonumber(n)
    if not num then return tostring(n) end
    local s = tostring(math.floor(num))
    while true do
        local replaced
        s, replaced = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

-- Fire-and-forget push to our ntfy topic. `title` becomes the notification
-- title (ntfy's X-Title header), `body` the message. Pass markdown=true to have
-- ntfy render the body as Markdown (X-Markdown header). No callback — a failed
-- ping must never disturb whatever loop triggered it.
function taPackage.utils.sendNtfy(title, body, markdown)
    local headers = { ["X-Title"] = title }
    if markdown then
        headers["X-Markdown"] = "true"
    end
    httpRequest("https://ntfy.sh/s5bbs-tele-arena-j5", {
        method = "POST",
        headers = headers,
        body = body,
    })
end
