import { describe, expect, it } from 'bun:test';
import { parseDrawing, drawingExits, pairRooms, renderCoverage, type Room } from './coverage';

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
