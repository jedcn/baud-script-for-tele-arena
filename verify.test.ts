import { describe, expect, it } from 'bun:test';
import { frontiers, reciprocity, depths, levelConsistency, descriptions, report,
         routeReferences, coordinates, type Room, type Exit } from './verify';

// Fixtures, never the live DB: tele-arena.db is absent on the VPS, and a check
// has to be pinned to a graph whose defects are known.
const room = (id: number, slug: string, description: string | null = 'a room'): Room =>
  ({ id, slug, description });
const pair = (a: number, d: string, b: number, rev: string): Exit[] =>
  [{ from_id: a, direction: d, to_id: b }, { from_id: b, direction: rev, to_id: a }];

describe('frontiers', () => {
  it('passes when every listed exit has been walked', () => {
    const f = frontiers([room(1, 'a'), room(2, 'b')], pair(1, 'n', 2, 's'));
    expect(f.ok).toBe(true);
  });
  it('names the room and direction of an unwalked exit', () => {
    const f = frontiers([room(1, 'a')], [{ from_id: 1, direction: 'ne', to_id: null }]);
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('a ne');
  });
});

describe('reciprocity', () => {
  it('passes when both directions are recorded', () => {
    const e = pair(1, 'e', 2, 'w');
    expect(reciprocity([room(1, 'a'), room(2, 'b')], e, e).ok).toBe(true);
  });
  it('flags a one-directional edge', () => {
    const e: Exit[] = [{ from_id: 1, direction: 'e', to_id: 2 }];
    const f = reciprocity([room(1, 'a'), room(2, 'b')], e, e);
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('a e');
  });
  it('accepts `passage`, whose reverse is itself', () => {
    const e = pair(1, 'passage', 2, 'passage');
    expect(reciprocity([room(1, 'a'), room(2, 'b')], e, e).ok).toBe(true);
  });
});

describe('depths', () => {
  it('counts only u and d, treating compass moves as level', () => {
    const e = [...pair(1, 'd', 2, 'u'), ...pair(2, 'e', 3, 'w'), ...pair(3, 'd', 4, 'u')];
    const z = depths(e, 1);
    expect([z.get(1), z.get(2), z.get(3), z.get(4)]).toEqual([0, -1, -1, -2]);
  });
  it('treats `passage` as level, so the two towns share a depth', () => {
    const z = depths(pair(1, 'passage', 2, 'passage'), 1);
    expect(z.get(2)).toBe(0);
  });
});

describe('levelConsistency', () => {
  it('passes on a graph whose depths agree', () => {
    const e = [...pair(1, 'd', 2, 'u'), ...pair(2, 'e', 3, 'w')];
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c')];
    expect(levelConsistency(rooms, e, depths(e, 1)).ok).toBe(true);
  });
  // This is how a `push stone` teleport recorded as an ordinary compass exit
  // gives itself away: you cannot walk east and change depth.
  it('flags a compass move that changes depth', () => {
    const e = [...pair(1, 'd', 2, 'u'), ...pair(1, 'e', 3, 'w'), ...pair(2, 'n', 3, 's')];
    const rooms = [room(1, 'a'), room(2, 'b'), room(3, 'c')];
    const f = levelConsistency(rooms, e, depths(e, 1));
    expect(f.ok).toBe(false);
    expect(f.detail).toMatch(/z -?\d+ -> -?\d+/);
  });
});

describe('descriptions', () => {
  it('flags a room with none', () => {
    const f = descriptions([room(1, 'a'), room(2, 'b', null)]);
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('b');
  });
});

describe('report', () => {
  it('marks each check PASS or FAIL', () => {
    const out = report([
      { check: 'one', ok: true, detail: 'fine' },
      { check: 'two', ok: false, detail: 'broken' },
    ]);
    expect(out).toContain('PASS  one');
    expect(out).toContain('FAIL  two');
  });
});

describe('routeReferences', () => {
  const ok = () => ({ areaExists: true, matches: 1 });
  it('passes when every reference resolves', () => {
    const src = 'from = "sewers-level-2/town-sewers-63",\n to = "third-town/town-square",';
    expect(routeReferences(src, ok).ok).toBe(true);
  });
  // The exact regression: splitting `sewers` into three levels left every route
  // that said "sewers/..." unwalkable, and nothing noticed until someone tried.
  it('flags a reference to an area that no longer exists', () => {
    const src = 'from = "sewers/town-sewers-63",';
    const f = routeReferences(src, () => ({ areaExists: false, matches: 0 }));
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('sewers/town-sewers-63 (no such area)');
  });
  it('flags an ambiguous reference', () => {
    const f = routeReferences('to = "first-town/cave",', () => ({ areaExists: true, matches: 3 }));
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('(3 matches)');
  });
  it('ignores route keys, which are labels rather than room references', () => {
    const f = routeReferences('["town-3/part-1"] = {', () => ({ areaExists: false, matches: 0 }));
    expect(f.ok).toBe(true);
  });
});

describe('coordinates', () => {
  const at = (m: Record<number, [number, number]>) =>
    new Map(Object.entries(m).map(([k, v]) => [Number(k), { x: v[0], y: v[1] }]));
  it('passes when every edge lands where its direction says', () => {
    const e = [...pair(1, 'n', 2, 's'), ...pair(2, 'e', 3, 'w')];
    const f = coordinates([room(1, 'a'), room(2, 'b'), room(3, 'c')], e,
                          at({ 1: [0, 0], 2: [0, 1], 3: [1, 1] }));
    expect(f.ok).toBe(true);
  });
  // The desert's exact defect: two rooms joined by an edge but dead-reckoned
  // from different anchors, so findRoomByFingerprint stops matching.
  it('flags an edge whose endpoints were reckoned from different anchors', () => {
    const e = pair(1, 'sw', 2, 'ne');
    const f = coordinates([room(1, 'a'), room(2, 'b')], e, at({ 1: [4, -2], 2: [12, -3] }));
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('a sw b');
    expect(f.detail).toContain('mint duplicates');
  });
});
