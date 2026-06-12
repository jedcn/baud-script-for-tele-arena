--
-- This script will be read by [baud](https://github.com/jedcn/baud).
--
-- Details [here](https://github.com/jedcn/baud?tab=readme-ov-file#loading-scripts)
--
echo("Starting to read main.lua")

-- SCRIPT_DIR is set by Baud to the directory containing this script
local scriptDir = SCRIPT_DIR
if not scriptDir then
  error("SCRIPT_DIR not set - are you running this through Baud?")
end

-- =========================================================================
-- State
-- =========================================================================

if not taPackage then
  taPackage = {}
  taPackage.character = {}
end

function setCharacterStatus(value)
  taPackage.character.status = value
end

function getCharacterStatus()
  return taPackage.character.status
end

function setVitality(current, max)
  taPackage.character.vitalityCurrent = tonumber(current)
  taPackage.character.vitalityMax = tonumber(max)
end

function getVitality()
  return taPackage.character.vitalityCurrent, taPackage.character.vitalityMax
end

function setExperience(value)
  taPackage.character.experience = tonumber(value)
end

function getExperience()
  return taPackage.character.experience
end

-- =========================================================================
-- Triggers
-- =========================================================================

createTrigger("^Status:\\s+(\\S+)$", function(matches)
  setCharacterStatus(matches[2])
end, { type = "regex" })

createTrigger("^Vitality:\\s+(\\d+) / (\\d+)$", function(matches)
  setVitality(matches[2], matches[3])
end, { type = "regex" })

createTrigger("^Experience:\\s+(\\d+)$", function(matches)
  setExperience(matches[2])
end, { type = "regex" })

-- =========================================================================
-- Status bar
-- =========================================================================

local function status()
  local charStatus = getCharacterStatus() or "?"
  local vitalityCurrent, vitalityMax = getVitality()
  local vitalityText = (vitalityCurrent and vitalityMax)
    and (vitalityCurrent .. "/" .. vitalityMax)
    or "?"
  local experience = getExperience() and tostring(getExperience()) or "?"

  local segments = {
    { text = "Status" },
    { text = charStatus, fg = "white" },
    { text = "Vitality" },
    { text = vitalityText, fg = "white" },
    { text = "XP" },
    { text = experience, fg = "white" },
  }
  return segments
end

setStatus(status)

echo("Finishing reading main.lua")
