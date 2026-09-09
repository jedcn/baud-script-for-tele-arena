import { describe, expect, it } from 'bun:test';
import { parseMap, findBoxes, directionOf } from './parse';

const map = (s: string) => parseMap(s.replace(/^\n/, ''));

describe('directionOf', () => {
  it('reads a compass direction out of a grid offset', () => {
    expect(directionOf(-1, 0)).toBe('n');
    expect(directionOf(1, 1)).toBe('se');
    expect(directionOf(0, -1)).toBe('w');
  });
});

describe('findBoxes', () => {
  // `[Av]` and `[L6]` are four characters, so a box's centre cannot be assumed
  // to be one past the bracket -- getting this wrong invented an edge in town 1.
  it('measures boxes of either width', () => {
    const [three, four] = findBoxes(['[ ] [Av]']);
    expect([three.start, three.end, three.col]).toEqual([0, 2, 1]);
    expect([four.start, four.end, four.col]).toEqual([4, 7, 5]);
  });
  it('splits a label from its up/down badge', () => {
    const [b] = findBoxes(['[Gv]']);
    expect([b.label, b.badge]).toEqual(['G', 'v']);
  });
});

describe('parseMap', () => {
  it('joins boxes along a horizontal run of any length', () => {
    const p = map('[a]-[b]---[c]');
    expect(p.edges.length).toBe(2);
    expect(p.edges.every(e => e.dir === 'e' || e.dir === 'w')).toBe(true);
  });

  it('joins boxes down a vertical run', () => {
    const p = map('[a]\n |\n |\n[b]');
    expect(p.edges.length).toBe(1);
    expect(p.edges[0].dir).toBe('s');
  });

  // Regression: allowing a run to cross blank cells let a diagonal drift
  // through a gap and attach to an unrelated box.
  it('does not let a run cross a gap into an unrelated box', () => {
    const p = map('[a]\n   \\\n     \n      [b]');
    expect(p.edges.length).toBe(0);
  });

  // Regression: these are hand drawings; a fork's `/` and `\` sit under the
  // brackets, not outside them.
  it('accepts a diagonal drawn under the bracket', () => {
    const p = map('  [a]\n  / \\\n[b]   [c]');
    expect(p.edges.length).toBe(2);
  });

  it('reads several legend entries from one line', () => {
    const p = map('[a]\n\no = Onyx key          O = Onyx key door');
    expect(p.legend.o).toBe('Onyx key');
    expect(p.legend.O).toBe('Onyx key door');
  });

  // A door marker sits ON the way between two rooms, and being hand-drawn is
  // often a column off the true line.
  it('joins two rooms through a door marker and records the door', () => {
    const p = map('[a]\n #\n[b]\n\n# = locked door');
    expect(p.edges.length).toBe(1);
    expect(p.edges[0].door).toMatch(/locked door/);
  });

  it('treats a legend-defined letter as a door', () => {
    const p = map('[a]J[b]\n\nJ = Jade key door');
    expect(p.edges[0].door).toBe('Jade key door');
  });

  it('flags a link between two badged rooms as vertical, not a compass move', () => {
    const p = map('[V^]\n |\n[Gv]');
    expect(p.edges[0].vertical).toBe(true);
  });
});

describe('the real town 1 map', () => {
  it('parses to the topology we independently walked', async () => {
    const p = parseMap(await Bun.file('map/shrine/town-1.txt').text());
    expect(p.boxes.length).toBe(13);
    expect(p.edges.length).toBe(12);
    const label = (i: number) => p.boxes[i].label || '_';
    const pairs = new Set(p.edges.map(e => [label(e.from), label(e.to)].sort().join('')));
    // north plaza's six ways out, which we verified against the game
    for (const pair of ['*A', '*G', '*t', '*T', '*E', '*_']) expect(pairs.has(pair)).toBe(true);
  });

  it('leaves no box unconnected in any of the fifteen maps', async () => {
    const { MAPS } = await import('./scrape');
    for (const { slug } of MAPS) {
      const p = parseMap(await Bun.file(`map/shrine/${slug}.txt`).text());
      const linked = new Set(p.edges.flatMap(e => [e.from, e.to]));
      const orphans = p.boxes.filter(b => !linked.has(b.index));
      expect({ slug, orphans: orphans.length }).toEqual({ slug, orphans: 0 });
    }
  });
});
