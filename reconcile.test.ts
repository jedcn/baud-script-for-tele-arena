import { describe, expect, it } from 'bun:test';
import { reconcile, type OurRoom } from './reconcile';
import { parseMap } from './parse';

const ours = (spec: Record<string, Record<string, string | null>>): Record<string, OurRoom> =>
  Object.fromEntries(Object.entries(spec).map(([slug, exits]) => [slug, { slug, exits }]));

describe('reconcile', () => {
  it('walks identity outward from the anchor', () => {
    const shrine = parseMap('[*]-[a]\n |\n[b]');
    const rep = reconcile('t', shrine,
      ours({ plaza: { e: 'shop', s: 'cave' }, shop: { w: 'plaza' }, cave: { n: 'plaza' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.matched.length).toBe(3);
    expect(rep.unmatchedBoxes).toEqual([]);
    expect(rep.unmatchedRooms).toEqual([]);
  });

  // A stair is drawn like any other connector, so the drawn direction is not
  // the game direction -- town 1's vaults hang off the guild hall diagonally
  // and are really `d`.
  it('falls back to a stair when the drawn direction has no exit', () => {
    const shrine = parseMap('[*v]\n  \\\n   [V^]');
    const rep = reconcile('t', shrine, ours({ hall: { d: 'vault' }, vault: { u: 'hall' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'hall' });
    expect(rep.matched.length).toBe(2);
  });

  // Regression: an ungated stair fallback fired wherever the drawing merely
  // disagreed with us. On dungeon level 2 it took `d` from the pit trap,
  // walked into the pit, dead-ended there and stranded 35 rooms behind it.
  it('does not fall back to a stair when neither room is badged', () => {
    const shrine = parseMap('[a]-[b]');
    const rep = reconcile('t', shrine,
      ours({ trap: { d: 'pit', e: 'other' }, pit: { u: 'trap' }, other: { w: 'trap' } }),
      { box: m => m.boxes.findIndex(b => b.label === 'b'), room: 'trap' });
    // walking w from `trap` is impossible, and `d` must not be substituted
    expect(rep.matched.map(([, r]) => r)).not.toContain('pit');
    expect(rep.conflicts.some(c => /no exit that way|cannot reach/.test(c.message))).toBe(true);
  });

  it('reports a direction the drawing has and we do not', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine, ours({ plaza: {}, other: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.conflicts.map(c => c.message).join(' ')).toMatch(/no exit that way|cannot reach/);
    expect(rep.unmatchedRooms).toContain('other');
  });

  it('says so plainly when the anchor is not in our map', () => {
    const rep = reconcile('t', parseMap('[*]'), ours({ elsewhere: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'missing' });
    expect(rep.conflicts[0].message).toContain('anchor not found');
  });
});

describe('conflicts carry a location', () => {
  it('names the box so a reader can be shown where on the map it is', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine, ours({ plaza: {}, other: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.conflicts[0].box).toBe(0);
    expect(rep.conflicts[0].room).toBe('plaza');
  });
});

describe('a trap box stands for two rooms', () => {
  // The drawing gives the room you step into and the room you fall into a
  // single box, because you experience them as one event. The pit is therefore
  // not a room the drawing is missing.
  it('folds the pit into its trap box instead of calling it unmatched', () => {
    const shrine = parseMap('[*]-[t]');
    const rep = reconcile('t', shrine,
      ours({ hall: { e: 'trap' }, trap: { w: 'hall', d: 'pit' }, pit: { u: 'trap' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'hall' });
    expect(rep.pits.map(p => p[1])).toEqual(['pit']);
    expect(rep.unmatchedRooms).not.toContain('pit');
  });

  // Only traps. A staircase down gets its own box -- town 1 draws the vaults
  // as [V^] even though the guild hall drops into them.
  it('does not fold a room reached by an ordinary staircase', () => {
    const shrine = parseMap('[*]-[G]');
    const rep = reconcile('t', shrine,
      ours({ plaza: { e: 'hall' }, hall: { w: 'plaza', d: 'vault' }, vault: { u: 'hall' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.pits).toEqual([]);
    expect(rep.unmatchedRooms).toContain('vault');
  });

  it('leaves a room alone if it has exits besides the way back up', () => {
    const shrine = parseMap('[*]-[t]');
    const rep = reconcile('t', shrine,
      ours({ hall: { e: 'trap' }, trap: { w: 'hall', d: 'below' }, below: { u: 'trap', n: 'onward' }, onward: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'hall' });
    expect(rep.pits).toEqual([]);
  });
});

describe('shape check', () => {
  // The check that says whether a reconciliation can be believed at all. A room
  // is not the box it is matched to if they have different numbers of ways out,
  // and a drifted alignment still produces confident-looking conflicts.
  it('passes when every matched room has as many ways as its box', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine, ours({ plaza: { e: 'shop' }, shop: { w: 'plaza' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.shapeMismatches).toEqual([]);
  });

  it('flags a room matched to a box of a different shape', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine,
      ours({ plaza: { e: 'shop' }, shop: { w: 'plaza', n: 'attic' }, attic: { s: 'shop' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.shapeMismatches.map(m => m.room)).toContain('shop');
  });

  // An exit that leaves the area is drawn as a text label or a badge, not a
  // connector, so counting it would make every room with a stair look wrong.
  it('ignores exits that leave the area', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine,
      ours({ plaza: { e: 'shop', d: 'elsewhere/deep' }, shop: { w: 'plaza' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.shapeMismatches).toEqual([]);
  });

  it('ignores an exit that has never been walked', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine,
      ours({ plaza: { e: 'shop', n: null }, shop: { w: 'plaza' } }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.shapeMismatches).toEqual([]);
  });
});
