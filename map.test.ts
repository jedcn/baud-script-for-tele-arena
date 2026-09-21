import { describe, expect, it } from 'bun:test';
import { renderArea, buildMarkdown, placeRooms, skewedEdges, type Room, type Exit } from './map';

// Fixtures are plain data, never the live DB: tele-arena.db is absent on the
// VPS, and these are also the three bugs that cost rooms silently, so they need
// to be pinned to a known graph rather than to whatever has been mapped.
const room = (id: number, slug: string, name = slug): Room => ({ id, slug, name });
const pair = (a: number, d: string, b: number, rev: string): Exit[] =>
  [{ from_id: a, direction: d, to_id: b }, { from_id: b, direction: rev, to_id: a }];

describe('renderArea', () => {
  it('draws a west-east chain with connectors between the boxes', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'mid', 'north plaza'), room(2, 'shop', 'armor shop'), room(3, 'far', 'temple')],
      exits: [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w')],
      origin: 'mid',
    });
    expect(lines.join('\n')).toBe('[ ]--[a]--[t]');
  });

  it('places a north neighbour above, joined by a vertical run', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'mid', 'north plaza'), room(2, 'up', 'temple')],
      exits: pair(1, 'n', 2, 's'),
      origin: 'mid',
    });
    expect(lines).toEqual(['[t]', ' |', ' |', '[ ]']);
  });

  // Regression: vaults and the private room are reachable ONLY by u/d. A
  // renderer that walks compass edges alone omits them with no error at all.
  it('keeps a room reachable only by a vertical exit, and connects it', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'hall', 'guild hall'), room(2, 'vault', 'town vaults')],
      exits: pair(1, 'd', 2, 'u'),
      origin: 'hall',
    });
    const text = lines.join('\n');
    expect(text).toContain('[V^]');   // the vault, with its up badge
    expect(text).toContain('[Gv]');   // the hall, with its down badge
    // And a connector joining them -- any run will do. This used to insist on a
    // vertical or diagonal one, which was a fact about where the vault got
    // PARKED: a stair had no cell of its own, so the room on the far side went
    // into a free cell next door. The layout now cuts at the stairs, so these
    // two are separate clusters tiled side by side and the run between them is
    // horizontal. What the regression is actually about -- that a room reachable
    // only by `u`/`d` is neither dropped nor left floating -- is unchanged.
    expect(text).toMatch(/[-\\|\/]/);
  });

  // Regression: placing a vertical neighbour at a fixed offset dropped the
  // arena, because the vaults landed exactly on top of it.
  it('does not let a vertical neighbour overwrite a compass room', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza'), room(2, 'arena', 'arena'), room(3, 'vault', 'town vaults')],
      exits: [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u')],
      origin: 'plaza',
    });
    const text = lines.join('\n');
    expect(text).toContain('[A]');
    expect(text).toContain('[V^]');
  });

  // Regression: a vertical room placed before pass 1 squats on a cell a real
  // compass edge needs, and the compass room then overwrites IT instead.
  it('places compass rooms before vertical ones, losing neither', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'tav', 'tavern'), room(2, 'priv', 'private room'), room(3, 'dock', 'docks')],
      // the private room is discovered first, and wants the cell docks needs
      exits: [...pair(1, 'u', 2, 'd'), ...pair(1, 'n', 3, 's')],
      origin: 'tav',
    });
    const text = lines.join('\n');
    expect(text).toContain('[D]');
    expect(text).toContain('[pv]');
  });

  // Regression: `pit` on dungeon level three is entered only by falling through
  // a trap door from level two, so it is unreachable from that level's origin.
  // Laying out from a single root placed it nowhere -- dropping it silently.
  it('keeps a room that is unreachable from the origin, tiled alongside', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'start', 'north plaza'), room(2, 'next', 'temple'), room(3, 'island', 'arena')],
      exits: [...pair(1, 'e', 2, 'w'), { from_id: 3, direction: 'u', to_id: 99 }],
      origin: 'start',
      areaOf: () => 'somewhere else',
    });
    const text = lines.join('\n');
    expect(text).toContain('[A^]');                 // the detached room is drawn
    expect(text).toContain('[ ]--[t]');             // and the main component too
    expect(text).toContain('up to somewhere else');
  });

  // Regression: the stoneworks chain flat regions together through stairs, so a
  // whole region can be reachable only THROUGH a vertical edge. Running the
  // compass and vertical passes once each placed the stair's far end but none
  // of the rooms beyond it -- 45 rooms silently missing from the drawing.
  it('places a flat region reachable only through a vertical edge', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'top', 'north plaza'), room(2, 'landing', 'arena'),
              room(3, 'beyond', 'temple'), room(4, 'further', 'inn')],
      exits: [...pair(1, 'd', 2, 'u'), ...pair(2, 'e', 3, 'w'), ...pair(3, 'e', 4, 'w')],
      origin: 'top',
    });
    const text = lines.join('\n');
    for (const glyph of ['[ v]', '[A^]', '[t]', '[I]']) expect(text).toContain(glyph);
  });

  // Regression: a plain room draws as `[ ]`, a space in the middle, so a
  // diagonal connector routed through it overwrote the blank and the room
  // rendered as `[\\]` -- a room turned into a line segment.
  it('never lets a connector overwrite a blank room glyph', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'a'), room(2, 'b'), room(3, 'c'), room(4, 'd'), room(5, 'e')],
      exits: [...pair(1, 'se', 2, 'nw'), ...pair(2, 'se', 3, 'nw'),
              ...pair(3, 'ne', 4, 'sw'), ...pair(4, 'ne', 5, 'sw')],
      origin: 'a',
    });
    const text = lines.join('\n');
    expect(text).not.toMatch(/\[[\\\/|-]\]/);
    expect((text.match(/\[ \]/g) ?? []).length).toBe(5);
  });

  // Regression: two rooms can dead-reckon to the same cell -- this world is not
  // Euclidean and loops genuinely misclose. The second one used to overwrite the
  // first and vanish; 35 stonework rooms were missing from MAP.md that way.
  it('draws every room even when two dead-reckon to the same cell', () => {
    // a square that miscloses: n, e, s, w returns to a DIFFERENT room
    const { lines } = renderArea({
      rooms: [room(1, 'a'), room(2, 'b'), room(3, 'c'), room(4, 'd'), room(5, 'e')],
      exits: [...pair(1, 'n', 2, 's'), ...pair(2, 'e', 3, 'w'),
              ...pair(3, 's', 4, 'n'), ...pair(4, 'w', 5, 'e')],
      origin: 'a',
    });
    expect((lines.join('\n').match(/\[[^\]]*\]/g) ?? []).length).toBe(5);
  });

  it('turns an exit leaving the area into a text label', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza')],
      exits: [{ from_id: 1, direction: 'd', to_id: 99 }],
      origin: 'plaza',
      areaOf: () => 'first-dungeon',
    });
    expect(lines.join('\n')).toContain('down to first-dungeon');
  });

  it('labels an unwalked exit as unexplored', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza')],
      exits: [{ from_id: 1, direction: 'n', to_id: null }],
      origin: 'plaza',
    });
    expect(lines.join('\n')).toContain('n to unexplored');
  });

  it('builds a key from only the services actually present', () => {
    const { key } = renderArea({
      rooms: [room(1, 'a', 'north plaza'), room(2, 'b', 'temple')],
      exits: pair(1, 'e', 2, 'w'),
      origin: 'a',
    });
    expect(key).toEqual(['t = Temple']);
  });

  // Placement depends on iteration order, so the query must not be free to
  // reorder rows between runs.
  it('is deterministic regardless of the order rows arrive in', () => {
    const rooms = [room(1, 'mid', 'north plaza'), room(2, 'e', 'arena'), room(3, 'n', 'temple')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'n', 3, 's')];
    const a = renderArea({ rooms, exits, origin: 'mid' });
    const b = renderArea({ rooms: [...rooms].reverse(), exits: [...exits].reverse(), origin: 'mid' });
    expect(b.lines).toEqual(a.lines);
  });

  it('rejects an origin that is not in the area', () => {
    expect(() => renderArea({ rooms: [room(1, 'a')], exits: [], origin: 'nope' }))
      .toThrow(/origin room 'nope'/);
  });
});

describe('buildMarkdown', () => {
  it('writes a heading, a linked table of contents, and a fenced section each', () => {
    const md = buildMarkdown([
      { title: 'First Town', lines: ['[ ]'], key: ['t = Temple'] },
      { title: 'Second Town', lines: ['[a]'], key: [] },
    ]);
    expect(md).toContain('# Tele Arena Map');
    expect(md).toContain('1. [First Town](#first-town)');
    expect(md).toContain('2. [Second Town](#second-town)');
    expect(md).toContain('### First Town');
    expect(md).toContain('- `t` — Temple');
    expect(md.match(/```/g)).toHaveLength(4);   // one fence pair per area
    expect(md.endsWith('\n')).toBe(true);
  });
});

describe('skewedEdges', () => {
  const skew = (rooms: Room[], exits: Exit[], origin: string) =>
    skewedEdges(rooms, exits, placeRooms({ rooms, exits, origin }).pos);

  it('finds nothing in a graph the grid holds exactly', () => {
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c')];
    expect(skew(rooms, [...pair(1, 'e', 2, 'w'), ...pair(2, 'n', 3, 's')], 'a')).toEqual([]);
  });

  // A triangle that asks for a shape two dimensions do not have: c is two cells
  // west of a by way of b, and also due north of a. The grid picks one; whichever
  // it picks, some line points somewhere the exit does not go.
  it('marks an edge inherent when the loop it closes misses', () => {
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c')];
    const got = skew(rooms,
      [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w'), ...pair(1, 'n', 3, 's')], 'a');
    expect(got.map(s => [s.from_id, s.direction, s.to_id, s.drawn, s.inherent]))
      .toEqual([[2, 'e', 3, 'nw', true], [3, 'w', 2, 'se', true]]);
  });

  // The other cause, pinned on `pos` directly rather than through `placeRooms`:
  // whether the classifier can tell the two apart must not depend on whether the
  // layout happens to make that mistake today. a --n--> b is perfectly
  // representable, so a drawing that puts b north-EAST of a is nobody's fault
  // but the drawing's.
  it('marks an edge NOT inherent when the data could have been drawn right', () => {
    const rooms = [room(1, 'a'), room(2, 'b')];
    const exits = pair(1, 'n', 2, 's');
    const pos = new Map([[1, { c: 0, r: 0 }], [2, { c: 1, r: -1 }]]);
    expect(skewedEdges(rooms, exits, pos).map(s => [s.direction, s.drawn, s.inherent]))
      .toEqual([['n', 'ne', false], ['s', 'sw', false]]);
  });

  // u/d are drawn as a badge rather than a line precisely because they have no
  // direction to point, so they can never be skewed and must not be reported.
  it('ignores vertical exits', () => {
    const rooms = [room(1, 'a'), room(2, 'b')];
    expect(skew(rooms, pair(1, 'd', 2, 'u'), 'a')).toEqual([]);
  });

  it('ignores an exit that leaves the area or was never walked', () => {
    const rooms = [room(1, 'a')];
    expect(skew(rooms, [{ from_id: 1, direction: 'n', to_id: null },
                        { from_id: 1, direction: 's', to_id: 99 }], 'a')).toEqual([]);
  });
});

// A nudge happens when two rooms dead-reckon to one cell. Where it puts the
// loser decides which way its lines then point, and for a long time it put it
// wherever a raster scan reached first -- (-1,-1), north-west, with no notion of
// the direction at all.
describe('placeRooms cuts a level at its stairs', () => {
  // A stair joins two rooms that are above and below one another, which a flat
  // grid has no cell for. Laying the far side out in the same coordinates as
  // the near side folds one region through the other; cutting there gives each
  // flat region its own coordinates, and the ^/v badges carry the join. This is
  // how the shrine draws these caves -- caverns page 3 is five clusters joined
  // by numbered up/down boxes.
  it('lays a region reached only by a stair out in its own coordinates', () => {
    // Two corridors running east, joined ONLY by a stair from a to b. Laid out
    // together, b's region starts wherever b was parked -- diagonally next to a
    // -- and `b --e--> c` then collides with `a --e--> x`.
    const rooms = [room(1, 'a'), room(2, 'x'), room(3, 'b'), room(4, 'c')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'), ...pair(3, 'e', 4, 'w')];
    const { pos } = placeRooms({ rooms, exits, origin: 'a' });
    const a = pos.get(1)!, x = pos.get(2)!, b = pos.get(3)!, c = pos.get(4)!;
    // Each cluster is internally true: x due east of a, c due east of b.
    expect([x.c - a.c, x.r - a.r]).toEqual([1, 0]);
    expect([c.c - b.c, c.r - b.r]).toEqual([1, 0]);
    // And the stair is not drawn as a direction at all, so it cannot be skewed.
    expect(skewedEdges(rooms, exits, pos)).toEqual([]);
  });

  it('leaves a level whose regions the compass already joins exactly as it was', () => {
    // A stair BETWEEN two rooms a compass path also connects removes nothing:
    // the region is still one component, so the drawing is unchanged. This is
    // what keeps the change to the levels that actually needed it.
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c')];
    const flat = [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w')];
    const withStair = [...flat, ...pair(1, 'd', 3, 'u')];
    const before = placeRooms({ rooms, exits: flat, origin: 'a' }).pos;
    const after = placeRooms({ rooms, exits: withStair, origin: 'a' }).pos;
    expect([...after.entries()]).toEqual([...before.entries()]);
  });

  it('packs the clusters into rows rather than one long strip', () => {
    // Five clusters of four rooms each, joined in a chain of stairs. Tiled side
    // by side that is 20-odd cells wide and 2 tall; the packing wraps it.
    const rooms = [], exits = [];
    for (let k = 0; k < 5; k++) {
      const base = k * 4;
      for (let i = 0; i < 4; i++) rooms.push(room(base + i + 1, `r${base + i + 1}`));
      for (let i = 0; i < 3; i++) exits.push(...pair(base + i + 1, 'e', base + i + 2, 'w'));
      if (k) exits.push(...pair(base - 3, 'd', base + 1, 'u'));
    }
    const { pos } = placeRooms({ rooms, exits, origin: 'r1' });
    const cs = [...pos.values()];
    const w = Math.max(...cs.map(p => p.c)) - Math.min(...cs.map(p => p.c)) + 1;
    const h = Math.max(...cs.map(p => p.r)) - Math.min(...cs.map(p => p.r)) + 1;
    expect(h).toBeGreaterThan(1);               // wrapped onto more than one row
    expect(w).toBeLessThan(4 * 5 + 2 * 4);      // narrower than a single strip
    expect(pos.size).toBe(20);                  // and nothing was dropped
  });

  it('is a pure function of the graph, packing included', () => {
    // Re-running must produce a byte-identical file, so the wrap width is
    // searched deterministically rather than by trying to be clever.
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c'), room(4, 'd')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'), ...pair(3, 'e', 4, 'w')];
    const once = placeRooms({ rooms, exits, origin: 'a' }).pos;
    const twice = placeRooms({ rooms: [...rooms].reverse(), exits: [...exits].reverse(),
                               origin: 'a' }).pos;
    expect([...twice.entries()].sort()).toEqual([...once.entries()].sort());
  });
});

describe('placeRooms nudges by bearing', () => {
  it('keeps a bumped room on the right side of the room that placed it', () => {
    // x is east of a. b hangs below on a stair, so it is parked rather than
    // placed by a compass edge -- and its region is then laid out from there,
    // straight into a's. `b --n--> c` wants the cell x is standing in.
    const rooms = [room(1, 'a'), room(2, 'x'), room(3, 'b'), room(4, 'c')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'), ...pair(3, 'n', 4, 's')];
    const { pos } = placeRooms({ rooms, exits, origin: 'a' });
    const b = pos.get(3)!, c = pos.get(4)!;
    expect(c.c).toBe(b.c);                        // still due north, not north-west
    expect(c.r).toBeLessThan(b.r);
    expect(skewedEdges(rooms, exits, pos)).toEqual([]);
  });

  // The cell a room is nudged into has to answer to every neighbour it already
  // has, not just the exit that placed it. Honouring only that one is what left
  // desert-27 and town-sewers-167 pointing the wrong way from a second
  // neighbour that was already on the grid.
  it('weighs every neighbour already placed, not just the exit that placed it', () => {
    // a--e-->x; a--d-->b parks b; b--n-->c is blocked by x, and c also has to sit
    // west of d, which b--e-->d has already put down.
    const rooms = [room(1, 'a'), room(2, 'x'), room(3, 'b'), room(4, 'c'), room(5, 'd')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'),
                   ...pair(3, 'e', 5, 'w'), ...pair(3, 'n', 4, 's'), ...pair(4, 'e', 5, 'w')];
    const { pos } = placeRooms({ rooms, exits, origin: 'a' });
    const skew = skewedEdges(rooms, exits, pos);
    // Whatever it picks, it must not break an exit that the grid can hold.
    expect(skew.filter(s => !s.inherent)).toEqual([]);
  });
});
