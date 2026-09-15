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
