-- strict_globals_spec.lua
-- The test helper turns a read of an undefined global into an error, so a name a
-- file split left behind fails a spec instead of reading as a silent nil.

require("test.test_helper")

describe("strict globals", function()

    it("raises on a read of a global nobody defined", function()
        assert.has_error(function() return _G.noSuchGlobal end)
    end)

    it("names the global in the error", function()
        local ok, err = pcall(function() return _G.noSuchGlobal end)
        assert.is_false(ok)
        assert.matches("noSuchGlobal", err)
    end)

    it("lets the scripts test for the globals they treat as optional", function()
        for _, name in ipairs({ "taPackage", "runCommand" }) do
            local saved = rawget(_G, name)
            rawset(_G, name, nil)
            assert.is_nil(_G[name])
            rawset(_G, name, saved)
        end
    end)

end)
