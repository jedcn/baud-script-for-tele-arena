import { describe, expect, it } from 'bun:test';
import { parseDrawing, drawingExits, pairRooms, renderCoverage, teleportLinks, type Room } from './coverage';

// A miniature shrine drawing, using every connector the real ones do.
//
//   [@]-[ ]        @ east to A
//    |     \       @ south to B, A southeast to C
//   [ ]     [C]
//
const MINI = `# a comment line, skipped
[@]-[ ]
 |     \\
 |      [C]
[ ]

@ = the start
C = a landmark
`;

describe('parseDrawing', () => {
  it('finds every box, including labelled ones', () => {
    const d = parseDrawing(MINI);
    expect(d.boxes.map(b => b.label)).toEqual(['@', '', 'C', '']);
  });

  it('stops at the legend rather than reading it as map', () => {
    const d = parseDrawing(MINI);
    // Four boxes, not five: "C = a landmark" is a key line, not a room.
    expect(d.boxes.length).toBe(4);
  });

  it('reads a horizontal run as east/west', () => {
    const d = parseDrawing(MINI);
    const start = d.boxes.find(b => b.label === '@')!;
    expect(drawingExits(d, start.id).e).toBeDefined();
  });

  it('reads a vertical run as south, however many rows it spans', () => {
    // The `|` runs two rows here, and is still one move.
    const d = parseDrawing(MINI);
    const start = d.boxes.find(b => b.label === '@')!;
    const south = drawingExits(d, start.id).s;
    expect(south).toBeDefined();
    expect(drawingExits(d, south).n).toBe(start.id);
  });

  it('reads a diagonal as southeast, and gives it a reverse', () => {
    const d = parseDrawing(MINI);
    const a = d.boxes.find(b => b.r === 0 && b.label === '')!;
    const c = d.boxes.find(b => b.label === 'C')!;
    expect(drawingExits(d, a.id).se).toBe(c.id);
    expect(drawingExits(d, c.id).nw).toBe(a.id);
  });
});

describe('pairRooms', () => {
  const d = parseDrawing(MINI);
  const startBox = d.boxes.find(b => b.label === '@')!;
  const aBox = d.boxes.find(b => b.r === 0 && b.label === '')!;

  it('pairs by the path walked, not by exit-set', () => {
    const rooms: Room[] = [
      { id: 1, slug: 'start', exits: { e: 2, s: null } },
      { id: 2, slug: 'a', exits: { w: 1, se: null } },
    ];
    const { pair, problems } = pairRooms(d, rooms, 1, startBox.id);
    expect(problems).toEqual([]);
    expect(pair.get(2)).toBe(aBox.id);
  });

  it('reports an exit we have that the drawing does not', () => {
    const rooms: Room[] = [
      { id: 1, slug: 'start', exits: { e: 2, u: 2 } },
      { id: 2, slug: 'a', exits: { w: 1 } },
    ];
    const { problems } = pairRooms(d, rooms, 1, startBox.id);
    expect(problems.length).toBe(1);
    expect(problems[0]).toContain('not in the drawing');
  });

  it('refuses to pair two of our rooms with one box', () => {
    // A square, so two different paths from the start reach the same box: east
    // then south, or south then east.
    //
    //   [@]-[ ]
    //    |   |
    //   [ ]-[ ]
    //
    // Our graph claims those two paths end in DIFFERENT rooms, which cannot both
    // be true. Whichever arrives second must be reported, not quietly given a box
    // that is taken -- a duplicate room in our data looks exactly like this.
    const square = parseDrawing('[@]-[ ]\n |   |\n[ ]-[ ]\n');
    const sq = square.boxes.find(b => b.label === '@')!;
    const rooms: Room[] = [
      { id: 1, slug: 'start', exits: { e: 2, s: 3 } },
      { id: 2, slug: 'east', exits: { w: 1, s: 4 } },
      { id: 3, slug: 'south', exits: { n: 1, e: 5 } },
      { id: 4, slug: 'corner-a', exits: { n: 2 } },
      { id: 5, slug: 'corner-b', exits: { w: 3 } },
    ];
    const { problems } = pairRooms(square, rooms, 1, sq.id);
    expect(problems.some(p => p.includes('already paired'))).toBe(true);
  });

  it('leaves unwalked rooms unpaired rather than guessing', () => {
    const rooms: Room[] = [{ id: 1, slug: 'start', exits: { e: null, s: null } }];
    const { pair } = pairRooms(d, rooms, 1, startBox.id);
    expect(pair.size).toBe(1);
  });
});

describe('renderCoverage', () => {
  const d = parseDrawing(MINI);
  const startBox = d.boxes.find(b => b.label === '@')!;
  const cBox = d.boxes.find(b => b.label === 'C')!;

  it('preserves the drawing’s spacing exactly, so it can be compared', () => {
    // `[#]` and `[.]` are three characters, like `[ ]`; a labelled box keeps its
    // width by swapping brackets for parentheses. Column positions carry the
    // connector information, so a width change would break the drawing.
    const plain = parseDrawing(MINI).lines.map(l => l.replace(/\s+$/, ''));
    const out = renderCoverage(d, new Set([startBox.id]));
    for (let i = 0; i < out.length; i++) {
      expect(out[i].length).toBe(plain[i].length);
    }
  });

  it('marks a walked box # and an unwalked one .', () => {
    const out = renderCoverage(d, new Set([startBox.id])).join('\n');
    expect(out).toContain('[@]-[.]');
  });

  it('shows a landmark in brackets when walked, parentheses when not', () => {
    expect(renderCoverage(d, new Set([cBox.id])).join('\n')).toContain('[C]');
    expect(renderCoverage(d, new Set()).join('\n')).toContain('(C)');
  });
});

// A Teleport cannot be drawn: there is no connector for "you end up over there".
// So the drawing leaves the destination detached and says where it came from only
// in the legend -- which meant a walk of the boxes could never reach it, and the
// [S3] strip read as unwalked after being walked.
//
//   [@]-[A]      [B]-[ ]
//
// A teleports to B, and nothing connects them on the page.
const TELE = `[@]-[A]      [B]-[ ]

@ = the start
A = Push Stone to go to B
B = where you land
`;

describe('teleportLinks', () => {
  it('reads a destination out of the legend', () => {
    expect(teleportLinks(parseDrawing(TELE)).get('A')).toBe('B');
  });

  it('ignores a legend line naming no box', () => {
    const d = parseDrawing('[@]-[A]\n\n@ = start\nA = Push Stone to go to Narnia\n');
    expect(teleportLinks(d).has('A')).toBe(false);
  });

  it('ignores legend lines that are not teleports', () => {
    const d = parseDrawing(TELE);
    expect(teleportLinks(d).has('@')).toBe(false);
    expect(teleportLinks(d).has('B')).toBe(false);
  });
});

describe('pairRooms across a teleport', () => {
  const d = parseDrawing(TELE);
  const at = (l: string) => d.boxes.find(b => b.label === l)!.id;
  // Our graph has no edge from 2 to 3: the link lives on the device.
  const rooms: Room[] = [
    { id: 1, slug: 'start', exits: { e: 2 } },
    { id: 2, slug: 'stone-room', exits: { w: 1 } },
    { id: 3, slug: 'landed', exits: { e: 4 } },
    { id: 4, slug: 'beyond', exits: { w: 3 } },
  ];

  it('cannot reach the detached boxes without the device', () => {
    const { pair } = pairRooms(d, rooms, 1, at('@'));
    expect(pair.size).toBe(2);
  });

  it('reaches them when the device says where the stone lands', () => {
    const { pair, problems } = pairRooms(d, rooms, 1, at('@'), new Map([[2, 3]]));
    expect(problems).toEqual([]);
    expect(pair.size).toBe(4);
    expect(pair.get(3)).toBe(at('B'));
  });

  it('marks a box that belongs to another area, and stops there', () => {
    // The desert's `[S]` box IS stoneworks-level-1's riddle chamber: the drawing
    // draws the room across the Seam, and we do have it, filed under the other
    // area. So the box counts as walked -- and the walk must not follow it, or it
    // reads the neighbouring area's graph through this area's drawing. It used to
    // queue a room it had no record of and die on the next lookup.
    const d = parseDrawing(MINI);
    const at = (l: string) => d.boxes.find(b => b.label === l)!.id;
    const rooms: Room[] = [
      { id: 1, slug: 'start', exits: { e: 2 } },
      { id: 2, slug: 'a', exits: { w: 1, se: 99 } },   // 99 lives in another area
    ];
    const { pair, problems } = pairRooms(d, rooms, 1, at('@'));
    expect(problems).toEqual([]);
    expect(pair.get(99)).toBe(at('C'));
  });

  it('separates a way OUT of the area from a wrong edge', () => {
    // Both are exits with no connector in the drawing. One is the area ending --
    // the shrine captions the room across a Seam ("[S] Stoneworks") instead of
    // drawing it -- and the other is an edge we should not have. Lumping them
    // together means every finished area reports a disagreement it cannot fix.
    const d = parseDrawing(MINI);
    const at = (l: string) => d.boxes.find(b => b.label === l)!.id;
    const rooms: Room[] = [
      { id: 1, slug: 'start', exits: { e: 2, u: 77 } },   // 77 is another area's
      { id: 2, slug: 'a', exits: { w: 1, n: 1 } },        // and this `n` is wrong
    ];
    const { problems, leaves } = pairRooms(d, rooms, 1, at('@'));
    expect(leaves).toEqual(['start u (out of this area)']);
    expect(problems).toEqual(['a --n--> exists for us, not in the drawing']);
  });

  it('reports a destination whose box is already paired', () => {
    // Two stones whose legend lines both land on [B], and two different rooms of
    // ours claiming to be where each lands. Both cannot be [B].
    const two = parseDrawing(
      '[@]-[A]      [B]-[ ]\n\n@ = Push Stone to go to B\nA = Push Stone to go to B\nB = where you land\n');
    const atTwo = (l: string) => two.boxes.find(b => b.label === l)!.id;
    const { problems } = pairRooms(two, rooms, 1, atTwo('@'), new Map([[1, 3], [2, 4]]));
    expect(problems.some(p => p.includes('already paired'))).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// The committed map against the committed drawings.
//
// Everything above tests the parser on fixtures. This tests the DATA: that
// map/areas/*.json still agrees with map/shrine/*.txt, box for box, for every
// area registered in SHRINE_MAPS. It needs no database -- which is the point
// twice over, since it is the same claim the static page makes.
//
// Until now that agreement existed only because somebody ran `just coverage` and
// read the output. A walk, an export or a hand-repair that breaks it now fails
// here instead.

import { SHRINE_MAPS, roomsFromExport } from './coverage';

// The areas walked to completion, which are the ones whose agreement with the
// shrine is a claim rather than a progress report. SHRINE_MAPS is a wider set:
// registering an area there is what makes `just coverage <slug>` work, and that
// command is for a walk still in progress. Keeping the two apart is what lets an
// unfinished area be checked by eye without its drawing being asserted as met.
const COMPLETE = ['desert', 'fourth-town', 'stoneworks-level-1', 'stoneworks-level-2'];

async function pairArea(slug: string) {
  const spec = SHRINE_MAPS[slug];
  const area = JSON.parse(await Bun.file(`map/areas/${slug}.json`).text());
  const drawing = parseDrawing(await Bun.file(spec.file).text());
  const { rooms, teleports } = roomsFromExport(area);
  const start = rooms.find(r => r.slug === spec.originRoom);
  const startBox = drawing.boxes.find(b => b.label === spec.originBox);
  return { spec, drawing, rooms, teleports, start, startBox };
}

// The valley is walked out and the pairing still leaves six boxes unclaimed,
// because pairRooms is a BFS through our exits and one direction it cannot follow
// strands everything behind it. That shape, "nothing left to walk and boxes still
// unpaired", is what the CLI now explains rather than reporting as missing rooms.
//
// "Walked out" means no frontier into unwalked VALLEY. valley-14's `d` is the one
// exception and swings either way: it is a stub whenever the Complex of Natural
// Caverns below is unwalked, and walked again once someone goes down. Asserting
// an empty list therefore breaks every time the caverns are wiped, and asserting
// the stub breaks when they are re-walked. Neither is the claim being made here,
// which is about exits into unwalked VALLEY -- so that one seam exit is excluded
// by name and everything else still has to lead somewhere.
describe('a stalled pairing is not the same as an unwalked area', () => {
  it('leaves boxes unpaired behind a disagreement, with no frontier to blame', async () => {
    const area = JSON.parse(await Bun.file('map/areas/valley.json').text());
    const drawing = parseDrawing(await Bun.file(SHRINE_MAPS.valley.file).text());
    const { rooms, teleports } = roomsFromExport(area);
    const start = rooms.find(r => r.slug === SHRINE_MAPS.valley.originRoom)!;
    const box = drawing.boxes.find(b => b.label === SHRINE_MAPS.valley.originBox)!;
    const { pair, problems } = pairRooms(drawing, rooms, start.id, box.id, teleports);

    // Every exit of ours leads somewhere, bar the one way down out of the area.
    const stubs = rooms.flatMap(r =>
      Object.entries(r.exits).filter(([, to]) => to == null).map(([d]) => `${r.slug} ${d}`));
    expect(stubs.filter(s => s !== 'valley-14 d')).toEqual([]);

    // And yet the pairing does not reach every box, which is the pairing's limit
    // and not a gap in the map.
    expect(problems.length).toBeGreaterThan(0);
    expect(pair.size).toBeLessThan(drawing.boxes.length);
  });
});

describe('the exported map agrees with the shrine drawings', () => {
  for (const slug of COMPLETE) {
    it(`${slug} pairs with its drawing, box for box`, async () => {
      const { spec, drawing, rooms, teleports, start, startBox } = await pairArea(slug);
      expect(start, `${spec.originRoom} is in ${slug}`).toBeDefined();
      expect(startBox, `box [${spec.originBox}] is in the drawing`).toBeDefined();

      const { pair, problems, drawn } = pairRooms(
        drawing, rooms, start!.id, startBox!.id, teleports);

      // A room of ours whose exits the drawing does not have is either a wrong
      // edge or a room paired to the wrong box -- both worth failing over. An exit
      // that LEAVES the area is neither, and pairRooms separates those out: the
      // shrine captions the room across a Seam instead of drawing it.
      expect(problems).toEqual([]);

      // And the other direction, which went unchecked until an east exit the
      // shrine draws out of complex-of-natural-caverns-5 turned up on the coverage
      // picture and nowhere in its report. A finished area has to agree both ways
      // or "agrees with the drawing" means only half of what it sounds like.
      expect(drawn).toEqual([]);

      // Every room we have is somewhere on the page, and every box on the page is
      // ours. Both directions, because the area is finished.
      expect(pair.size).toBeGreaterThanOrEqual(rooms.length);
      expect(pair.size, `${slug} has unwalked boxes`).toBe(drawing.boxes.length);
    });
  }

  it('checks every area that has been walked to completion', () => {
    // Named explicitly, so finishing an area and forgetting to assert it here is
    // a failure rather than a silence.
    expect(COMPLETE.every(slug => slug in SHRINE_MAPS)).toBe(true);
    expect([...COMPLETE].sort()).toEqual(COMPLETE);
  });

  // An area still being walked gets no agreement check -- `just coverage` is how
  // its disagreements are read, by eye, while they are still being resolved. What
  // it does get is this: the wiring has to be real, or the command that is
  // supposed to report those disagreements dies on a typo instead.
  for (const slug of Object.keys(SHRINE_MAPS).filter(s => !COMPLETE.includes(s))) {
    it(`${slug} is registered with a drawing and an origin that resolve`, async () => {
      const spec = SHRINE_MAPS[slug];
      expect(await Bun.file(spec.file).exists(), `${spec.file} exists`).toBe(true);
      const drawing = parseDrawing(await Bun.file(spec.file).text());
      expect(drawing.boxes.length).toBeGreaterThan(0);
      expect(drawing.boxes.find(b => b.label === spec.originBox),
        `box [${spec.originBox}] is on ${spec.file}`).toBeDefined();

      // An area can be registered before it has any rooms -- that is the state
      // complex-caverns is in after being wiped to be re-walked, and registering
      // it is what makes `just coverage` usable DURING that walk (the CLI reads
      // the live database, not this export). So the origin room is checked only
      // once there is an export to check it against; the drawing half above is
      // what catches a typo in the wiring either way.
      const file = Bun.file(`map/areas/${slug}.json`);
      if (!(await file.exists())) return;
      const { rooms } = roomsFromExport(JSON.parse(await file.text()));
      expect(rooms.find(r => r.slug === spec.originRoom),
        `${spec.originRoom} is a room of ${slug}`).toBeDefined();
    });
  }
});
