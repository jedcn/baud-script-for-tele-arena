import { describe, expect, it } from 'bun:test';
import { frontiers, reciprocity, depths, levelConsistency, descriptions, report,
         routeReferences, coordinates, orphanExits, proseAgreement, proseDirections,
         drawnDirections, type Room, type Exit } from './verify';

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

describe('proseDirections', () => {
  it('reads the desert form', () => {
    expect(proseDirections('You are standing in a rocky windswept desert. Huge black'
      + ' outcroppings of rock block travel in all directions except to the south'
      + ' and northeast.')).toEqual(['ne', 's']);
  });

  it('reads both corridor verbs', () => {
    // Matching only "runs" silently skipped every "continues" room and passed
    // them all as fine.
    expect(proseDirections('The corridor runs to the north and southeast.'))
      .toEqual(['n', 'se']);
    expect(proseDirections('The corridor continues to the east and southwest.'))
      .toEqual(['e', 'sw']);
  });

  it('reads the same shape for a passage, a tunnel, a path and a room', () => {
    // One dialect per kind of place, and they are not interchangeable in the
    // prose: the desert's approach is a "sandy stone passage", the sewers are a
    // "filthy tunnel", the wilderness has paths and trails, and the storage room
    // west of the crude stone building says "The room continues to the east."
    expect(proseDirections('The passage continues to the north and south.'))
      .toEqual(['n', 's']);
    expect(proseDirections('The tunnel runs to the northwest and northeast.'))
      .toEqual(['ne', 'nw']);
    expect(proseDirections('The trail continues to the east, west, and south.'))
      .toEqual(['e', 's', 'w']);
    expect(proseDirections('The room continues to the east.')).toEqual(['e']);
  });

  it('adds a way out that something LEADS through', () => {
    // sandy-passage-7, where the strip meets the desert: "The passage continues
    // to the east and a crude stone archway leads out into the desert to the
    // south." -- and `ex` answers e,s.
    expect(proseDirections('The passage continues to the east and a crude stone'
      + ' archway leads out into the desert to the south.')).toEqual(['e', 's']);
  });

  it('declines the chamber form rather than guessing', () => {
    // "The only visible exit is east" is a claim about VISIBILITY. Stoneworks
    // level 1's mist room has a real `n` exit the prose cannot see, so reading
    // this form would report a true edge as a defect.
    expect(proseDirections('The northern portion of this chamber is obscured by a'
      + ' strange mist. The only visible exit is east.')).toBeNull();
  });

  it('adds a landmark way out, which gets a sentence of its own', () => {
    // The room south of the crude stone building answers `ex` with n,e,sw while
    // its list of directions names only two: the building entrance is a separate
    // sentence (logs/session-tojolias-2026-09-14T19-50-04.log line 670). Reading
    // only the list reports the `n` we walked in through as a defect -- which is
    // what it did, to this room and to the old desert-36, until it learned this.
    expect(proseDirections('You are standing in a rocky windswept desert. Huge black'
      + ' outcroppings of rock block travel in all directions except to the east and'
      + ' southwest. The entrance to a crude circular stone building lies to the'
      + ' north.')).toEqual(['e', 'n', 'sw']);
  });

  it('does not read a direction that is scenery rather than a way out', () => {
    // Devices and shopkeepers are described by which wall they are on. Only a
    // room whose prose already lists its exits is read at all, and only the
    // "lies to the" form adds to that list.
    expect(proseDirections('The corridor continues to the east. A stone in the north'
      + ' wall appears to protrude from the wall slightly more than the others.'))
      .toEqual(['e']);
  });

  it('returns null for prose that names no direction', () => {
    expect(proseDirections('A featureless room.')).toBeNull();
    expect(proseDirections(null)).toBeNull();
  });
});

describe('proseAgreement', () => {
  const desertRoom = (id: number, slug: string, dirs: string) =>
    room(id, slug, 'Huge black outcroppings of rock block travel in all directions'
      + ` except to the ${dirs}.`);

  it('passes when the edges are exactly what the room says', () => {
    const f = proseAgreement([desertRoom(1, 'desert', 'south and northeast')],
      [{ from_id: 1, direction: 's', to_id: 2 }, { from_id: 1, direction: 'ne', to_id: null }]);
    expect(f.ok).toBe(true);
    expect(f.detail).toContain('1 of 1');
  });

  it('catches the conflation the desert actually had', () => {
    // Two rooms merged into one leave the survivor wearing both sets of exits,
    // and nothing else in verify.ts notices: the graph stays reciprocal, every
    // room keeps a description, and it all still draws.
    const f = proseAgreement([desertRoom(1, 'desert', 'south and northeast')],
      ['s', 'ne', 'e', 'n', 'sw'].map(d => ({ from_id: 1, direction: d, to_id: 9 })));
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('prose says ne,s, edges say e,n,ne,s,sw');
  });

  it('ignores stairs, which prose gives a sentence of their own', () => {
    // "There is a stone staircase here leading downward" is not in the list of
    // directions, so a `d` must not count against the room.
    const f = proseAgreement([room(1, 'x', 'The corridor continues to the south.')],
      [{ from_id: 1, direction: 's', to_id: 2 }, { from_id: 1, direction: 'd', to_id: 3 }]);
    expect(f.ok).toBe(true);
  });

  it('excuses a room whose prose is known to omit a real exit', () => {
    // third town's doorway: you arrive from the town square going east, and the
    // corridor does not count that as one of its exits.
    const f = proseAgreement(
      [room(1, 'stonework-corridor-175', 'The corridor continues to the east.')],
      [{ from_id: 1, direction: 'e', to_id: null }, { from_id: 1, direction: 'w', to_id: 2 }]);
    expect(f.ok).toBe(true);
  });

  it('says how many rooms it could read, so a silent no-op shows', () => {
    const f = proseAgreement([room(1, 'x', 'A featureless room.')], []);
    expect(f.ok).toBe(true);
    expect(f.detail).toContain('0 of 1');
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

describe('orphanExits', () => {
  it('passes when every exit is anchored at both ends', () => {
    expect(orphanExits(new Set([1, 2]), pair(1, 'n', 2, 's')).ok).toBe(true);
  });
  // Deleting rooms under a live session: the mapper still held currentRoomId,
  // so its next `ex` seeded exits for a room that was already gone.
  it('flags an exit left behind by a deleted room', () => {
    const f = orphanExits(new Set([1]), [{ from_id: 673, direction: 'se', to_id: null }]);
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('673 se');
  });
});

describe('drawnDirections', () => {
  it('passes a graph the grid can hold exactly', () => {
    // a --e--> b --n--> c, and nothing else to contradict it.
    const f = drawnDirections(
      [room(1, 'a'), room(2, 'b'), room(3, 'c')],
      [...pair(1, 'e', 2, 'w'), ...pair(2, 'n', 3, 's')], 'a');
    expect(f.ok).toBe(true);
    expect(f.detail).toContain('4 compass exits');
  });

  // The deep-forest-149 case in miniature: a triangle whose three edges cannot
  // all be true on a square grid. a is east of b AND b is east of c, so c must
  // be two cells west of a -- but a also says c is due north. Something has to
  // give, and whatever gives, a line ends up pointing the wrong way.
  it('reports a loop that does not close, and does not fail for it', () => {
    const f = drawnDirections(
      [room(1, 'a'), room(2, 'b'), room(3, 'c')],
      [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w'), ...pair(1, 'n', 3, 's')], 'a');
    expect(f.ok).toBe(true);                       // not a defect: the world is like this
    expect(f.detail).toContain('the loop does not close');
    expect(f.detail).toContain('b e c');
  });

  // The other cause, and the one that IS a defect: the edge was representable
  // and the layout broke it anyway. `a --d--> b` has no compass direction, so b
  // is parked in the first free cell (south-east of a) and b's whole region is
  // laid out from there -- straight into the region a already occupies. `b --n-->
  // c` wants the cell x is standing in, so c is nudged aside and the line ends up
  // pointing north-west. Nothing about b-and-c is unrepresentable; the grid just
  // gave that cell away first.
  it('fails when the layout breaks an edge it could have drawn', () => {
    const f = drawnDirections(
      [room(1, 'a'), room(2, 'x'), room(3, 'b'), room(4, 'c')],
      [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u'), ...pair(3, 'n', 4, 's')], 'a');
    expect(f.ok).toBe(false);
    expect(f.detail).toContain('broken by the layout');
    expect(f.detail).toContain('b n c (drawn nw)');
    expect(f.detail).not.toContain('the loop does not close');
  });

  it('names the direction the line actually points', () => {
    const f = drawnDirections(
      [room(1, 'a'), room(2, 'b'), room(3, 'c')],
      [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w'), ...pair(1, 'n', 3, 's')], 'a');
    // c lands north-west of b, so `b --e--> c` is drawn pointing nw.
    expect(f.detail).toContain('(drawn nw)');
  });
});
