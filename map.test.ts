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
    expect(text).toMatch(/[\\|\/]/);  // and a connector joining them
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

  // The same drawing fault from the other cause. `a --d--> b` carries no compass
  // offset, so b is parked in a free cell and everything beyond it is laid out
  // from there -- over the top of a's own region. `b --n--> c` then finds x in the
  // cell it wants and c is shoved aside. b and c alone fit the grid perfectly, so
  // this one is the layout's doing and could be fixed.
  it('marks an edge NOT inherent when only the layout broke it', () => {
    const rooms = [room(1, 'a'), room(2, 'x'), room(3, 'b'), room(4, 'c')];
    const got = skew(rooms,
      [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'), ...pair(3, 'n', 4, 's')], 'a');
    expect(got.map(s => [s.from_id, s.direction, s.to_id, s.drawn, s.inherent]))
      .toEqual([[3, 'n', 4, 'nw', false], [4, 's', 3, 'se', false]]);
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
