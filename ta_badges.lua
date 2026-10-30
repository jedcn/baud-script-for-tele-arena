-- ta_badges.lua -- the coloured result badges echoed after combat lines
--
-- A normalized, color-coded badge echoed right after a combat line so the
-- result doesn't get lost in the fast scroll of party/monster chatter. The
-- badges share the same bold, padded, near-white block so they read as a set;
-- only the foreground color differs: blue for damage we deal, pink/red for
-- damage we take, green for healing.
--
-- Loaded by main.lua with dofile, before the triggers that badge. Reads nothing
-- from the other files; the badges are on taPackage.badges.

taPackage.badges = {}

local BADGE_BG = "#e0e0e0"
local OUTGOING_FG = "#2563eb" -- blue: damage we deal
local INCOMING_FG = "#ff5fd7" -- pink/red: damage we take
local HEAL_FG = "#16a34a" -- green: healing we cast (blue is reserved for damage dealt)

local function badge(fg, text)
    cechoBg(fg, BADGE_BG, " " .. text .. " ", true)
end

function taPackage.badges.outgoing(text) badge(OUTGOING_FG, text) end
function taPackage.badges.incoming(text) badge(INCOMING_FG, text) end
function taPackage.badges.healing(text) badge(HEAL_FG, text) end
