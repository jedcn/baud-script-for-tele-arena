-- The desert, session three: the south-west arm, and the closure the mapper very
-- nearly failed to notice.
--
-- The walk ended in a room that was `desert-7` come round the other way. Same
-- name, same exit-set `e,nw,sw`, the same description word for word, and the way
-- back still an unwalked Stub there -- a closure by every test the mapper has. It
-- minted a duplicate and said nothing, and the only reason anybody knew was that
-- the walker looked at the map afterwards and thought the last room looked
-- familiar.
--
-- The reason was a second candidate. `desert-20` matched the fingerprint just as
-- well -- these rooms are 37 of one name drawn from a handful of exit-sets -- and
-- findLoopClosure refuses to choose between candidates, because merging into the
-- wrong one is the failure that destroys a room. Refusing is right. Refusing
-- SILENTLY is what this fixture is about.
--
-- Two things changed, and this log is the evidence for both:
--
--   * with several candidates, prefer the nearest by reckoned position -- a
--     diagonal away beats four cells away -- and then defer as usual, so the next
--     move still has to confirm it. Distance chooses between candidates; it never
--     confirms one. Replaying this log now raises the closure into the right room
--     and names the moves that would settle it.
--   * when nothing separates the candidates, mint as before but SAY so, naming
--     them, so the duplicate can be merged by hand. That echo is asserted in
--     main_spec; here the distance rule wins, so it must NOT appear.
--
-- The session still ends on the held closure, because that is what the walker did:
-- `map-off` with a candidate outstanding. So the duplicate is still here at the
-- end -- announced twice over, which is the whole point -- and the live map was
-- repaired by merging it by hand.

local replay = dofile("test/log_replay.lua")
local fixture = dofile("test/desert_fixture.lua")

describe("The desert, a closure that was nearly missed", function()

    local g, at

    setup(function()
        g = replay.replayChain(fixture.upTo(3), { seed = fixture.seed() })
        at = fixture.index(g)
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    -- The room the closure is about, found by walking rather than by slug: out of
    -- the first desert room, east and down the diagonal, then back west.
    local function desertSeven()
        return at.follow(assert(at.bySlug("desert")), "e se se se s w w")
    end

    -- Matched on "settle it by walking" rather than on "possible loop closure":
    -- map-off's warning quotes the same phrase back, and counting both reads as two
    -- closures where there was one.
    it("raises the closure, into the room a diagonal away", function()
        local raised = g.echoesMatching("settle it by walking")
        assert.are.equal(1, #raised, table.concat(raised, "; "))
        assert.are.equal("#" .. desertSeven().id, raised[1]:match("#%d+"))
    end)

    it("names the moves that can settle it", function()
        -- `e` and `nw` are the candidate's walked exits. `sw` -- back the way the
        -- walk came -- is the Stub the closure would fill, so it can confirm
        -- nothing, and it is the move a walker would most naturally try.
        local raised = g.echoesMatching("settle it by walking")[1]
        assert.is_truthy(raised:find("settle it by walking e or nw", 1, true), raised)
    end)

    it("does not fall back on the ambiguity notice, because distance decided",
        function()
            -- Two candidates qualified. If the distance rule had not separated
            -- them the walk would have been told "looks like 2 rooms already
            -- mapped" and minted -- correct, but a worse outcome than a held
            -- closure, because nothing would then be waiting to be confirmed.
            assert.are.equal(0, #g.echoesMatching("looks like"))
        end)

    it("says at map-off that the closure went unsettled", function()
        -- The walk stopped on the candidate, so there was never a next arrival to
        -- confirm it against. That costs one duplicate room, and the cost is
        -- reported rather than swallowed: before this session the same walk ended
        -- in silence.
        local told = g.echoesMatching("unresolved")
        assert.are.equal(1, #told, table.concat(told, "; "))
        assert.is_truthy(told[1]:find("stays a duplicate", 1, true))
        assert.is_truthy(told[1]:find("One more move before map-off", 1, true))
    end)

    it("leaves the duplicate recognisable as one", function()
        -- Not merged -- nothing confirmed it -- but a walker or a later session
        -- can settle it, which is the trade deferring makes. It is the twin of
        -- desert-7 on every count the mapper has.
        local twin = assert(at.bySlug("desert-25"))
        local seven = desertSeven()
        assert.are_not.equal(seven.id, twin.id)
        assert.are.equal(seven.name, twin.name)
        assert.are.equal(g.exitSet(seven.id), g.exitSet(twin.id))
        assert.are.equal(seven.description, twin.description)
        -- And it is the only room of the session that should not be there.
        assert.are.equal(37, at.deserts())
    end)

    it("keeps the rest of the arm sound", function()
        assert.are.same({}, g.oneWayEdges())
        assert.are.same({}, g.proseMismatches())
        assert.is_true(g.prosesChecked() >= 35,
            "only " .. g.prosesChecked() .. " rooms were read")
    end)
end)
