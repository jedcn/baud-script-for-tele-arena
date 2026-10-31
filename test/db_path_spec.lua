-- db_path_spec.lua
-- The map database lives in data/, not the repo root. baud's dbOpen joins the
-- name onto its working directory, so the name ta_db.lua passes is the path.

require("test.test_helper")

describe("ta_db.lua", function()

    it("opens the map database under data/", function()
        local realDbOpen = _G.dbOpen
        local opened = {}
        _G.dbOpen = function(name)
            table.insert(opened, name)
            return realDbOpen(name)
        end
        local ok, err = pcall(dofile, "ta_db.lua")
        _G.dbOpen = realDbOpen
        assert.is_true(ok, err)
        assert.are.same({ "data/tele-arena.db" }, opened)
    end)

end)
