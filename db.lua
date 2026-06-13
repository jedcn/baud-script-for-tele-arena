local Db = {}

function Db.load(filepath)
  local f = io.open(filepath, "r")
  if not f then return {} end
  f:close()
  local ok, result = pcall(dofile, filepath)
  if ok and type(result) == "table" then
    return result
  end
  return {}
end

function Db.save(filepath, monsters)
  local f = io.open(filepath, "w")
  if not f then return false end
  f:write("return {\n")
  for name, entry in pairs(monsters) do
    f:write(string.format("  [%q] = {\n", name))
    f:write(string.format("    description = %q,\n", entry.description))
    f:write(string.format("    firstSeen = %q,\n", entry.firstSeen))
    f:write(string.format("    encounters = %d,\n", entry.encounters))
    f:write("  },\n")
  end
  f:write("}\n")
  f:close()
  return true
end

return Db
