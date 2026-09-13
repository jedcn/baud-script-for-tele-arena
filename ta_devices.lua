--
-- Devices: recording what you operate, and what it opens.
--
-- Alias patterns are REGEX, not Lua patterns -- baud compiles them with `new
-- RegExp` -- so `\\d` and `\\S`, never `%d`. The test helper converts the same
-- dialect, and it has no conversion for a literal character class, so avoid one.
--
-- Loaded by main.lua with dofile, for the reason ta_nav.lua is: Lua allows 200
-- local variables per chunk and a file IS a chunk, so main.lua's budget (about
-- thirty slots left) is not spent on a new section of aliases. Everything
-- crossing the seam does so through taPackage.
--
--   in    taPackage.db, taPackage.mapping, taPackage.currentRoomId
--   out   nothing -- these aliases are self-contained
--
-- The vocabulary is GLOSSARY.md's, and the shapes follow it: a Device belongs to
-- the Room you OPERATE it in, a Seal lives on the thing it blocks and names the
-- Device that clears it, and nothing here records whether a Device has been
-- worked today. That last one is Device State and it belongs to this Reset, not
-- to the map.
--
-- Why a Seal is recorded from the Exit's side rather than the Device's: one
-- Device can open several Seals. `say komi` opens two doors. A single target
-- column on the device row could not say that.
--

-- The room these aliases act on by default: the one we are standing in, which is
-- only trustworthy while mapping.
local function hereRoomId()
    if taPackage.mapping and taPackage.currentRoomId then
        return taPackage.currentRoomId
    end
    return nil
end

local function roomIdBySlug(slug)
    local row = taPackage.db.roomBySlug(slug)
    return row and row.id
end

-- One device rendered for a listing, with whatever its effect points at resolved
-- to something readable.
local function describeDevice(d)
    local bits = { "#" .. tostring(d.id), d.command, "(" .. d.effect }
    if d.repeats then bits[#bits] = bits[#bits] .. ", " .. d.repeats end
    bits[#bits] = bits[#bits] .. ")"
    if d.effect == "teleport" then
        bits[#bits + 1] = "-> " .. (d.dest_room_id
            and tostring(taPackage.db.roomRef(d.dest_room_id)) or "destination unknown")
    elseif d.effect == "trap" then
        bits[#bits + 1] = "disarms " .. (d.trap_room_id
            and tostring(taPackage.db.roomRef(d.trap_room_id)) or "trap room unknown")
    elseif d.effect == "light" then
        bits[#bits + 1] = "lights area " .. tostring(d.light_area_id or "unknown")
    elseif d.effect == "seal" then
        local sealed = taPackage.db.exitsSealedBy(d.id)
        if #sealed == 0 then
            bits[#bits + 1] = "seals nothing yet"
        else
            local parts = {}
            for _, e in ipairs(sealed) do
                parts[#parts + 1] = tostring(taPackage.db.roomRef(e.from_id)) .. " " .. e.direction
            end
            bits[#bits + 1] = "opens " .. table.concat(parts, ", ")
        end
    end
    if d.sealed_by then
        bits[#bits + 1] = "[behind device #" .. tostring(d.sealed_by) .. "]"
    end
    if d.note then bits[#bits + 1] = "-- " .. d.note end
    return table.concat(bits, " ")
end

local EFFECTS = { seal = true, teleport = true, light = true, trap = true }

-- `map-add-device <effect> <command>` — record a device in the room you are
-- standing in. The effect comes first so the command can be free text with
-- spaces: `map-add-device seal pull lever`, `map-add-device teleport push stone`,
-- `map-add-device seal say komi`, `map-add-device seal move tapestry`.
--
-- Deliberately records only what is true from standing here. What it opens, where
-- it sends you and whether it toggles are each their own command, because you
-- usually learn them later -- you cannot know a teleport's destination until you
-- have taken it.
createAlias("^map-add-device (\\S+) (.+)$", function(matches)
    local effect, command = matches[2], matches[3]:match("^%s*(.-)%s*$")
    if not EFFECTS[effect] then
        echo("[device] effect must be one of seal, teleport, light, trap"
            .. " -- got '" .. tostring(effect) .. "'")
        return
    end
    local roomId = hereRoomId()
    if not roomId then
        echo("[device] not anchored on a room -- turn mapping on first"
            .. " (map-here <slug>), since a device belongs to the room you work it in")
        return
    end
    local id = taPackage.db.addDevice(roomId, command, effect)
    if not id then
        echo("[device] this room already has a '" .. command .. "'"
            .. " -- `pull lever` could not tell two of them apart anyway")
        return
    end
    echo("[device] #" .. tostring(id) .. " " .. command .. " (" .. effect .. ") in "
        .. tostring(taPackage.db.roomRef(roomId)))
end, { type = "regex" })

-- `map-device-repeats <id> once|toggle` — whether working it again this Reset does
-- anything. `once` and the Seal stays open however many times you pull; `toggle`
-- and the second pull shuts it again. Meaningless for a teleport, which fires
-- every time and leaves no state, so that is refused rather than stored.
createAlias("^map-device-repeats (\\d+) (\\S+)$", function(matches)
    local id, how = tonumber(matches[2]), matches[3]
    if how ~= "once" and how ~= "toggle" then
        echo("[device] usage: map-device-repeats <id> once|toggle")
        return
    end
    local d = taPackage.db.deviceById(id)
    if not d then echo("[device] no device #" .. tostring(id)); return end
    if d.effect == "teleport" then
        echo("[device] a teleport is neither: it fires every time and leaves no"
            .. " state for a Reset to undo")
        return
    end
    taPackage.db.setDeviceField(id, "repeats", how)
    echo("[device] #" .. tostring(id) .. " " .. how .. " per reset")
end, { type = "regex" })

-- `map-device-dest <id> <room-slug>` — where a teleport lands you. Always the
-- same room, so this is a fact about the device and not about the trip.
createAlias("^map-device-dest (\\d+) (\\S+)$", function(matches)
    local id, slug = tonumber(matches[2]), matches[3]
    local d = taPackage.db.deviceById(id)
    if not d then echo("[device] no device #" .. tostring(id)); return end
    local destId = roomIdBySlug(slug)
    if not destId then echo("[device] no room with slug: " .. slug); return end
    taPackage.db.setDeviceField(id, "dest_room_id", destId)
    echo("[device] #" .. tostring(id) .. " lands in " .. slug)
end, { type = "regex" })

-- `map-device-trap <id> <room-slug>` — the room whose trap this device disarms.
createAlias("^map-device-trap (\\d+) (\\S+)$", function(matches)
    local id, slug = tonumber(matches[2]), matches[3]
    local d = taPackage.db.deviceById(id)
    if not d then echo("[device] no device #" .. tostring(id)); return end
    local trapId = roomIdBySlug(slug)
    if not trapId then echo("[device] no room with slug: " .. slug); return end
    taPackage.db.setDeviceField(id, "trap_room_id", trapId)
    echo("[device] #" .. tostring(id) .. " disarms the trap in " .. slug)
end, { type = "regex" })

-- `map-device-light <id> <area-slug>` — the area this device lights. Always a
-- whole area, never one room, which is why it takes an area slug: the Level is
-- carried in that slug (`labyrinth-level-2`), so one argument names both.
createAlias("^map-device-light (\\d+) (\\S+)$", function(matches)
    local id, slug = tonumber(matches[2]), matches[3]
    local d = taPackage.db.deviceById(id)
    if not d then echo("[device] no device #" .. tostring(id)); return end
    local areaId = taPackage.db.areaIdBySlug(slug)
    if not areaId then echo("[device] no area with slug: " .. slug); return end
    taPackage.db.setDeviceField(id, "light_area_id", areaId)
    echo("[device] #" .. tostring(id) .. " lights " .. slug)
end, { type = "regex" })

-- `map-device-behind <id> <other-id>` — this device cannot be worked until that
-- one has been. The Hewn Granite case: the lever is behind the tapestry, so
-- `move tapestry` must come first. A Seal over a Device rather than over an Exit,
-- which is why it is the same word.
createAlias("^map-device-behind (\\d+) (\\d+)$", function(matches)
    local id, blockerId = tonumber(matches[2]), tonumber(matches[3])
    if id == blockerId then
        echo("[device] a device cannot be behind itself")
        return
    end
    for _, v in ipairs({ id, blockerId }) do
        if not taPackage.db.deviceById(v) then
            echo("[device] no device #" .. tostring(v)); return
        end
    end
    taPackage.db.setDeviceField(id, "sealed_by", blockerId)
    echo("[device] #" .. tostring(id) .. " is behind #" .. tostring(blockerId))
end, { type = "regex" })

-- `map-seal <dir> <device-id>` — the exit `dir` out of the room you are standing
-- in is Sealed, and that device opens it. `map-seal <room-slug> <dir> <device-id>`
-- for an exit somewhere else, which is the common case: the Device and the Seal
-- are usually rooms apart.
--
-- The exit has to exist already. It will: `ex` seeds every direction the game
-- lists, and a Seal does not remove the exit it sits on -- `[D1]` answered
-- "Exits: n,e." and refused `n` in the same breath.
local function sealExit(fromId, dir, deviceId, label)
    if not taPackage.db.deviceById(deviceId) then
        echo("[device] no device #" .. tostring(deviceId)); return
    end
    local changed = taPackage.db.setExitSeal(fromId, dir, deviceId)
    if not changed or changed == 0 then
        echo("[device] " .. label .. " has no " .. dir .. " exit recorded --"
            .. " walk it or `ex` there first; a seal goes ON an exit, it does not"
            .. " create one")
        return
    end
    echo("[device] " .. label .. " " .. dir .. " is sealed, opened by #" .. tostring(deviceId))
end

createAlias("^map-seal (\\w+) (\\d+)$", function(matches)
    local roomId = hereRoomId()
    if not roomId then
        echo("[device] not anchored on a room -- name one:"
            .. " map-seal <room-slug> <dir> <device-id>")
        return
    end
    sealExit(roomId, matches[2], tonumber(matches[3]), tostring(taPackage.db.roomRef(roomId)))
end, { type = "regex" })

createAlias("^map-seal (\\S+) (\\w+) (\\d+)$", function(matches)
    local slug, dir, deviceId = matches[2], matches[3], tonumber(matches[4])
    local roomId = roomIdBySlug(slug)
    if not roomId then echo("[device] no room with slug: " .. slug); return end
    sealExit(roomId, dir, deviceId, slug)
end, { type = "regex" })

-- `map-unseal <room-slug> <dir>` — it turned out not to be sealed after all.
createAlias("^map-unseal (\\S+) (\\w+)$", function(matches)
    local slug, dir = matches[2], matches[3]
    local roomId = roomIdBySlug(slug)
    if not roomId then echo("[device] no room with slug: " .. slug); return end
    local changed = taPackage.db.setExitSeal(roomId, dir, nil)
    if not changed or changed == 0 then
        echo("[device] " .. slug .. " has no " .. dir .. " exit recorded")
        return
    end
    echo("[device] " .. slug .. " " .. dir .. " is no longer sealed")
end, { type = "regex" })

-- `map-devices` — every device here. `map-devices <room-slug>` for one room,
-- `map-devices all` for the lot.
createAlias("^map-devices$", function()
    local roomId = hereRoomId()
    if not roomId then
        echo("[device] not anchored on a room -- try map-devices all,"
            .. " or map-devices <room-slug>")
        return
    end
    local list = taPackage.db.devicesInRoom(roomId)
    if #list == 0 then
        echo("[device] nothing to operate in " .. tostring(taPackage.db.roomRef(roomId)))
        return
    end
    for _, d in ipairs(list) do echo("[device] " .. describeDevice(d)) end
end, { type = "regex" })

createAlias("^map-devices (\\S+)$", function(matches)
    local arg = matches[2]
    local list
    if arg == "all" then
        list = taPackage.db.allDevices()
    else
        local roomId = roomIdBySlug(arg)
        if not roomId then echo("[device] no room with slug: " .. arg); return end
        list = taPackage.db.devicesInRoom(roomId)
    end
    if #list == 0 then echo("[device] no devices recorded"); return end
    for _, d in ipairs(list) do
        local where = arg == "all"
            and (tostring(taPackage.db.roomRef(d.room_id)) .. ": ") or ""
        echo("[device] " .. where .. describeDevice(d))
    end
end, { type = "regex" })

-- `map-device-note <id> <text>` — the catch-all that room_notes used to be, kept
-- where it is actually useful: attached to the device it is about.
createAlias("^map-device-note (\\d+) (.+)$", function(matches)
    local id, text = tonumber(matches[2]), matches[3]
    if not taPackage.db.deviceById(id) then
        echo("[device] no device #" .. tostring(id)); return
    end
    taPackage.db.setDeviceField(id, "note", text)
    echo("[device] #" .. tostring(id) .. " noted")
end, { type = "regex" })

-- `map-del-device <id>` — and anything pointing at it is un-pointed, since
-- nothing enforces those references.
createAlias("^map-del-device (\\d+)$", function(matches)
    local id = tonumber(matches[2])
    local removed = taPackage.db.deleteDevice(id)
    if removed and removed > 0 then
        echo("[device] deleted #" .. tostring(id))
    else
        echo("[device] no device #" .. tostring(id))
    end
end, { type = "regex" })
