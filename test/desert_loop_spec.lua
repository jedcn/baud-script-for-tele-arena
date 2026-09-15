-- The desert, session two: east out of the strip and round the first loop.
--
-- This is the one that matters. The desert is the area that broke the mapper, and
-- it broke on loops: 103 rooms joined by 120 edges, so eighteen of them, walked
-- by a character whose every room is called "desert" and whose exit-sets repeat.
-- The old data had three rooms wearing two rooms' exits because a closure was
-- taken on trust.
--
-- Here one is taken on evidence, and this is the whole sequence:
--
--   1. Arriving in the twelfth room, `findLoopClosure` finds #1203 -- the room the
--      walk set out from, same name, same exit-set, and the way back is a Stub
--      there, which is exactly what a closure looks like. Nothing is merged.
--   2. The echo names the moves that can settle it: "settle it by walking e or n".
--      Those are the candidate's WALKED exits, the only ones that predict
--      anything; the obvious move, back the way you came, would refute a true
--      closure because that direction is the Stub the closure would fill.
--   3. The walk goes `n`, which mints a provisional sandy passage, because as far
--      as the graph knows it is standing in a room with no `n` neighbour.
--   4. The arrival IS what #1203 predicted through `n`, so the closure is
--      confirmed -- and BOTH provisionals fold away: the room the closure was held
--      on into #1203, and the sandy passage minted behind it into
--      sandy-passage-7. `sandy-passage-8` does not exist in the end.
--
-- The cost of getting this wrong is what the old desert looked like. The cost of
-- deferring is one duplicate room if a session stops on a held closure, and
-- map-off says so.

local replay = dofile("test/log_replay.lua")
local fixture = dofile("test/desert_fixture.lua")

describe("The desert, the first loop", function()

    local g, at

    setup(function()
        g = replay.replayChain(fixture.upTo(2), { seed = fixture.seed() })
        at = fixture.index(g)
    end)

    teardown(function()
        if g then g.db.remove() end
    end)

    describe("the closure", function()

        it("raises one candidate and confirms it", function()
            -- Echoes are the LAST log's only, so these are session two's.
            assert.are.equal(1, #g.echoesMatching("possible loop closure"))
            assert.are.equal(1, #g.echoesMatching("loop closure confirmed"))
            assert.are.equal(0, #g.echoesMatching("refused"))
        end)

        it("names the moves that can settle it, not just 'one more move'", function()
            -- A direction the candidate has never walked predicts nothing, so the
            -- echo has to say which ones do. On 2026-09-13 a closure went unsettled
            -- because the only obvious move -- back the way we came -- was the one
            -- the candidate knew least about.
            local raised = g.echoesMatching("possible loop closure")[1]
            assert.is_truthy(raised:find("settle it by walking e or n", 1, true), raised)
        end)

        it("leaves no duplicate behind, not even the room minted mid-closure",
            function()
                -- The walk's `n` minted a sandy passage while the closure was still
                -- held. Confirming has to fold that away too, or the level carries
                -- a second copy of sandy-passage-7 forever.
                assert.is_nil(at.bySlug("sandy-passage-8"))
                assert.are.equal(23, at.deserts())
            end)

        it("closes the loop: the way out and the way back meet", function()
            -- What a closure IS. Out of the first desert room the long way round --
            -- east, four moves down the diagonal, then back west and north -- and
            -- in from its own `sw`, and the two must be the same room.
            local first = assert(at.bySlug("desert"))
            local theLongWay = at.follow(first, "e se se se s w w nw nw nw ne ne")
            assert.are.equal(first.id, theLongWay.id)
            -- And the room one step short of it is what `sw` reaches directly.
            local viaSw = at.follow(first, "sw")
            local lastLeg = at.follow(first, "e se se se s w w nw nw nw ne")
            assert.are.equal(viaSw.id, lastLeg.id)
        end)

        it("fills the Stub that made it a candidate", function()
            -- #1203's `sw` was unwalked, which is half of why the closure was
            -- plausible; the merge is what walks it.
            local first = assert(at.bySlug("desert"))
            assert.is_truthy(first.exits.sw)
            assert.are.equal("e,n,sw", g.exitSet(first.id))
        end)
    end)

    describe("the graph after two sessions", function()

        it("holds 23 rooms", function()
            assert.are.equal(23, at.deserts())
        end)

        it("keeps every edge reciprocal", function()
            assert.are.same({}, g.oneWayEdges())
        end)

        it("records no exit a room's own description denies", function()
            -- 22 of the 23 name their exits in prose -- every room but the crude
            -- stone building, which describes its doors instead ("To the east and
            -- west lie sturdy oak doors"). This is the check the old desert failed.
            assert.are.same({}, g.proseMismatches())
            assert.is_true(g.prosesChecked() >= 22,
                "only " .. g.prosesChecked() .. " rooms were read")
        end)

        it("leaves exactly the frontiers the walk stopped at, and the Seam",
            function()
                -- Four in the desert, plus both ends of the unlinked stairs. Stated
                -- as one list because g.stubs() is the whole database: a stub
                -- appearing anywhere else would be a room we walked away from
                -- without recording, which is the thing worth failing over.
                local want = {}
                for _, spec in ipairs({
                    { "desert-5", "e" }, { "desert-5", "s" },      -- the four-way room
                    { "desert-7", "sw" }, { "desert-10", "sw" },
                    { "crude-stone-building", "d" }, { "town-sewer-1", "u" },
                }) do
                    local room = assert(at.bySlug(spec[1]), spec[1] .. " is missing")
                    want[#want + 1] = room.id .. " " .. spec[2]
                end
                table.sort(want)
                local got = g.stubs()
                table.sort(got)
                assert.are.same(want, got)
            end)

        it("keeps two rooms that dead-reckon into the same cell", function()
            -- desert-11 was minted at (-1,-4,0), the coordinate the walk's starting
            -- room already occupied. That is legal here -- this world is not
            -- Euclidean and CLAUDE.md says to treat a collision as a hint, not a
            -- defect -- and the fingerprint was right to refuse it: same name, same
            -- cell, different exit-set, different room.
            local first = assert(at.bySlug("desert"))
            local eleven = assert(at.bySlug("desert-11"))
            assert.are_not.equal(first.id, eleven.id)
            assert.are.equal(first.x, eleven.x)
            assert.are.equal(first.y, eleven.y)
            assert.are_not.equal(g.exitSet(first.id), g.exitSet(eleven.id))
        end)

        it("still leaves the sewers Seam unlinked", function()
            -- Session one's cost, unchanged by session two: nothing the walk can do
            -- relinks it, which is why it was repaired by hand in the live map.
            assert.are.equal(false, assert(at.bySlug("crude-stone-building")).exits.d)
            assert.are.equal(false, assert(at.bySlug("town-sewer-1")).exits.u)
        end)
    end)
end)
