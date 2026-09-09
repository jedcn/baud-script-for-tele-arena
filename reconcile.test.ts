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
    const shrine = parseMap('[*]\n \\\n  [V]');
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
    expect(rep.conflicts.some(c => /no exit that way/.test(c.message))).toBe(true);
  });

  it('reports a direction the drawing has and we do not', () => {
    const shrine = parseMap('[*]-[a]');
    const rep = reconcile('t', shrine, ours({ plaza: {}, other: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'plaza' });
    expect(rep.conflicts.join(' ')).toContain('no exit that way');
    expect(rep.unmatchedRooms).toContain('other');
  });

  it('says so plainly when the anchor is not in our map', () => {
    const rep = reconcile('t', parseMap('[*]'), ours({ elsewhere: {} }),
      { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'missing' });
    expect(rep.conflicts[0]).toContain('anchor not found');
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
