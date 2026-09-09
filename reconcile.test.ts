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
