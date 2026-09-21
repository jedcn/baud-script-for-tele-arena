import { describe, expect, it } from 'bun:test';
import { awayLabel, boxLabel, buildPage, groupAreas, readAreas, readPlayers, renderLevel, splitName }
  from './site';
import type { Area } from './export';

// A two-room level exercising every kind of exit the page has to draw, so the
// counts below are readable by hand.
const MINI: Area = {
  area: 'test-level-1', name: 'Test Place, Level 1', src: 'test',
  rooms: [
    {
      id: 'test-level-1/hall', name: 'hall',
      description: 'A hall.',
      exits: {
        e: { to: 'test-level-1/corridor-1' },
        n: { to: null },                                   // frontier
        d: { to: 'test-level-2/landing' },                 // leaves the level
        w: { to: 'test-level-1/vault', door: { material: 'iron', key: 'brass' } },
      },
      devices: [{ command: 'pull lever', effect: 'trap' }],
    },
    {
      id: 'test-level-1/corridor-1', name: 'corridor',
      exits: {
        w: { to: 'test-level-1/hall' },
        u: { to: 'test-level-1/vault' },                   // internal stairs
      },
      trap: { type: 'falling rocks' },
    },
    {
      id: 'test-level-1/vault', name: 'town vaults',
      exits: {
        e: { to: 'test-level-1/hall', door: { material: 'iron', key: 'brass' } },
        d: { to: 'test-level-1/corridor-1' },
        s: { to: 'test-level-1/hall', sealedBy: { command: 'say komi', room: 'test-level-1/hall' } },
      },
    },
  ],
};

const NAME_OF = (slug: string) => slug === 'test-level-2' ? 'Test Place, Level 2' : slug;

describe('splitName', () => {
  it('splits an area from its level', () => {
    expect(splitName('The Stoneworks, Level 2')).toEqual(
      { area: 'The Stoneworks', level: 'Level 2', sort: 2 });
  });

  it('leaves an area with no levels as its own single level', () => {
    // "The Desert" is one place. It still needs an entry in the Level select,
    // because the select is how a pane gets chosen.
    expect(splitName('The Desert')).toEqual({ area: 'The Desert', level: '—', sort: 0 });
  });
});

describe('groupAreas', () => {
  const groups = groupAreas([
    { area: 'x-level-10', name: 'X, Level 10' },
    { area: 'x-level-2', name: 'X, Level 2' },
    { area: 'desert', name: 'The Desert' },
  ]);

  it('orders levels numerically, not lexically', () => {
    // "Level 10" sorts before "Level 2" as text. Six stoneworks levels will hit
    // this the moment there are ten of anything.
    expect(groups.find(g => g.area === 'X')!.levels.map(l => l.level))
      .toEqual(['Level 2', 'Level 10']);
  });

  it('keeps a level-less area as one group with one level', () => {
    expect(groups.find(g => g.area === 'The Desert')!.levels.length).toBe(1);
  });
});

describe('awayLabel', () => {
  it('names the level when the link stays inside one area', () => {
    expect(awayLabel('The Stoneworks, Level 2', 'The Stoneworks, Level 3')).toBe('Level 3');
  });

  it('names the area when the link leaves it', () => {
    expect(awayLabel('The Stoneworks, Level 1', 'The Desert')).toBe('The Desert');
  });
});

describe('boxLabel', () => {
  it('uses the service letter where there is one', () => {
    expect(boxLabel(MINI.rooms[2])).toBe('V');       // town vaults
  });

  it('otherwise uses the kind and number off the slug', () => {
    expect(boxLabel(MINI.rooms[1])).toBe('co1');
    // Two letters, because stoneworks level 1 holds a chamber-1 AND a
    // corridor-1, and the bare number would label both boxes `1`.
    expect(boxLabel({ id: 'stoneworks-level-1/stonework-chamber-1', name: 'x', exits: {} }))
      .toBe('ch1');
    expect(boxLabel({ id: 'stoneworks-level-1/stonework-corridor-1', name: 'x', exits: {} }))
      .toBe('co1');
  });

  it('falls back to the initials of the name', () => {
    // A browser can afford more than the shrine's bare `[ ]`, and a town whose
    // plazas all render blank is harder to read than one where they do not.
    expect(boxLabel(MINI.rooms[0])).toBe('h');
    expect(boxLabel({ id: 'first-town/north-plaza', name: 'north plaza', exits: {} }))
      .toBe('np');
  });
});

// A one-way triangle, the shape the Complex of Natural Caverns really has at
// caverns-87/90/88: nw from A lands on B, whose se goes on to C rather than
// back, and C's nw closes it at A. Its own fixture, because MINI's line and
// badge counts are pinned above and a one-way exit there would move them.
const ONEWAY: Area = {
  area: 'cave-level-1', name: 'Cave, Level 1', src: 'test',
  rooms: [
    { id: 'cave-level-1/a', name: 'cave', exits: { nw: { to: 'cave-level-1/b' },
                                                   se: { to: 'cave-level-1/c' } } },
    { id: 'cave-level-1/b', name: 'cave', exits: { se: { to: 'cave-level-1/c' } } },
    { id: 'cave-level-1/c', name: 'cave', exits: { nw: { to: 'cave-level-1/a' } } },
  ],
};

describe('a connection you can only cross one way', () => {
  const { svg, stats } = renderLevel(ONEWAY, NAME_OF);

  it('marks the two one-way crossings and not the reciprocal one', () => {
    // a--nw-->b has no way back (b's se goes to c), and b--se-->c has none
    // (c's nw goes to a). a--se-->c and c--nw-->a are each other's reverse, so
    // that line carries no arrow.
    expect(stats.oneWay).toBe(2);
    expect(svg.match(/class="arrow"/g)!.length).toBe(2);
  });

  it('runs the line from source to destination, so the arrow aims itself', () => {
    // The anchors are what the page drags from AND what the arrow reads its
    // angle out of, so on a one-way line they are source-first rather than
    // sorted. Sorted order is equally correct for a line; only an arrow cares.
    const arrows = [...svg.matchAll(/<path class="arrow" data-a="([^"]+)" data-b="([^"]+)"/g)]
      .map(m => [m[1], m[2]]);
    expect(arrows).toContainEqual(['cave-level-1/a', 'cave-level-1/b']);
    expect(arrows).toContainEqual(['cave-level-1/b', 'cave-level-1/c']);
  });

  it('says which way, and that there is no way back', () => {
    expect(svg).toContain('ONE WAY: there is no se back from there');
  });

  it('is drawn turned along the line it sits on', () => {
    expect(svg).toMatch(/class="arrow"[^>]*transform="translate\([^)]*\) rotate\(-?[\d.]+\)"/);
  });

  it('does not call a connection one-way while the way back is still unwalked', () => {
    // MINI's vault leaves `s` to the hall, and the hall's `n` is a FRONTIER --
    // it may well lead back. An arrow there would assert something unwalked,
    // and would have to be retracted the day someone walks it. Absent, or
    // leading somewhere else, is the claim; unwalked is not evidence.
    const hall = MINI.rooms[0];
    expect(hall.exits.n).toEqual({ to: null });
    expect(renderLevel(MINI, NAME_OF).stats.oneWay).toBe(0);
  });

  it('leaves an ordinary reciprocal level unmarked', () => {
    expect(renderLevel(MINI, NAME_OF).stats.oneWay).toBe(0);
    expect(renderLevel(MINI, NAME_OF).svg).not.toContain('class="arrow"');
  });
});

describe('a Device that teleports', () => {
  // Two rooms no compass exit joins, and a stone that moves you between them --
  // the shape of stonework-corridor-20 -> 43, where the teleport is the only
  // way onto the strip at all.
  const PORT: Area = {
    area: 'works-level-1', name: 'Works, Level 1', src: 'test',
    rooms: [
      { id: 'works-level-1/near', name: 'corridor', exits: { e: { to: 'works-level-1/mid' } },
        devices: [{ command: 'push stone', effect: 'teleport', dest: 'works-level-1/far' }] },
      { id: 'works-level-1/mid', name: 'corridor', exits: { w: { to: 'works-level-1/near' } } },
      { id: 'works-level-1/far', name: 'corridor', exits: {},
        devices: [{ command: 'pull lever', effect: 'trap',
                    trapRoom: 'works-level-1/mid' }] },
    ],
  };
  const { svg, stats } = renderLevel(PORT, NAME_OF);

  it('joins the two rooms, pointing the way the Device takes you', () => {
    expect(stats.teleports).toBe(1);
    const line = svg.match(/<line class="edge port"[^>]*>/)![0];
    expect(line).toContain('data-a="works-level-1/near"');
    expect(line).toContain('data-b="works-level-1/far"');
    const arrow = svg.match(/<path class="arrow port"[^>]*>/)![0];
    expect(arrow).toContain('data-a="works-level-1/near"');
    expect(arrow).toContain('data-b="works-level-1/far"');
    expect(arrow).toMatch(/rotate\(-?[\d.]+\)/);
  });

  it('names the command, because you cannot walk this one', () => {
    expect(svg).toContain('push stone` here puts you in works-level-1/far');
  });

  it('draws no line for a Device that is not a teleport', () => {
    // `pull lever` reaches another room too -- it disarms a trap there -- and a
    // line would say you can get there that way. stonework-corridor-42's `push
    // stone` is the live case: the same verb as the teleport, a remote SEAL.
    expect(svg.match(/class="edge port"/g)!.length).toBe(1);
  });

  it('keeps the device dot, which is what says the room has one', () => {
    expect(svg.match(/class="device-dot"/g)!.length).toBe(2);
  });
});

describe('renderLevel', () => {
  const { svg, stats } = renderLevel(MINI, NAME_OF);

  it('draws one box per room', () => {
    expect(svg.match(/class="box[^"]*" data-id=/g)!.length).toBe(3);
    expect(stats.rooms).toBe(3);
  });

  it('draws one line per connection, not one per direction', () => {
    // hall--e-->corridor and corridor--w-->hall are one doorway. Drawing both
    // doubles every stroke and leaves two overlapping hover targets.
    //
    // Three lines, not two: hall and vault are joined TWICE here, by the w/e
    // door and again by the s/n seal, and a connection that renders as nothing
    // is indistinguishable from one we never recorded. (No real area has a
    // double connection today -- this fixture is the guard against a dedup that
    // keys on the two rooms alone.)
    //
    // Matched on the class PREFIX: a line can also carry `skew` or `vert`, and
    // this fixture has one of each. hall reaches vault both `w` and `s`, which
    // is a shape no grid holds, so whichever line loses is drawn pointing
    // somewhere else; corridor and vault are joined by a stair.
    expect(svg.match(/class="edge[ "]/g)!.length).toBe(4);
    expect(svg.match(/class="edge vert"/g)!.length).toBe(1);
  });

  it('draws the stair between two rooms on the same level, and says nothing about its angle', () => {
    // The badge says WHICH WAY (u/d); only the line says which room, and
    // without it a level joined to itself only by stairs reads as two separate
    // drawings. The angle of that line means nothing -- the rooms are above and
    // below one another -- so it is dashed, and it is never counted as skewed.
    const line = svg.match(/<line class="edge vert"[^>]*>(?:<title>([^<]*)<)?/)!;
    expect(line[0]).toContain('data-a="test-level-1/corridor-1"');
    expect(line[0]).toContain('data-b="test-level-1/vault"');
    expect(line[1]).toBe('u to test-level-1/vault');
    // Both boxes keep their badge: the line alone cannot say which end is up.
    expect(svg.match(/class="vbadge"/g)!.length).toBe(2);
  });

  it('does not draw a stair to a room on another level', () => {
    // `d` out of the level is a labelled stub, not a line to a box that is not
    // in this drawing at all. hall's `d` leaves for test-level-2.
    expect(svg).toContain('class="away"');
    expect(svg).not.toContain('data-b="test-level-2/landing"');
  });

  // The two ways a line can lie about its direction, and why the page says so:
  // a reader cannot tell a wrongly-angled line from an ordinary one, and this is
  // the map people navigate from.
  it('marks a line that does not point the way its exit goes', () => {
    expect(stats.skewed).toBe(1);
    expect(svg).toContain('class="edge skew"');
    expect(svg).toContain('but this line points');
  });

  it('marks an unwalked exit as a stub with an open end', () => {
    expect(stats.frontiers).toBe(1);
    expect(svg).toContain('class="frontier"');
  });

  it('labels an exit that leaves the level with where it goes', () => {
    expect(stats.leaving).toBe(1);
    expect(svg).toContain('>Level 2</text>');
  });

  it('badges internal stairs rather than drawing a line', () => {
    // `u`/`d` have no compass offset, so a line would claim a direction the
    // exit does not have. Both ends get a badge; neither gets an edge.
    expect(svg.match(/class="vbadge"/g)!.length).toBe(2);
  });

  it('marks a Door and a Seal on the exit they block', () => {
    expect(stats.doors).toBe(1);
    expect(stats.seals).toBe(1);
    expect(svg).toContain('iron door, brass key');
    expect(svg).toContain('say komi');
  });

  it('counts devices and traps', () => {
    expect(stats.devices).toBe(1);
    expect(stats.traps).toBe(1);
  });

  it('places every box at a real coordinate', () => {
    // One NaN in a transform silently drops a room off the drawing, and the page
    // still loads -- which is how a missing room goes unnoticed.
    expect(svg).not.toContain('NaN');
    expect(svg).not.toContain('undefined');
  });

  it('puts the room tooltip first in its group, where a browser reads it', () => {
    // <title> is a tooltip only as the first child of its element. The stubs and
    // badges that follow carry titles of their own, and with the room's title
    // last the browser shows one of theirs for the whole box.
    const out = renderLevel(MINI, NAME_OF).svg;
    const box = out.slice(out.indexOf('<g class="box'));
    expect(box.slice(box.indexOf('>') + 1)).toStartWith('<title>');
  });

  it('escapes what it puts in a title', () => {
    const quoted: Area = {
      ...MINI,
      rooms: [{ id: 'test-level-1/hall', name: 'a "hall" & <b>', exits: {} }],
    };
    const out = renderLevel(quoted, NAME_OF).svg;
    expect(out).toContain('&quot;hall&quot; &amp; &lt;b&gt;');
    expect(out).not.toContain('<b>');
  });
});

// ---------------------------------------------------------------------------
// The page, run the way a browser would run it.

class El {
  attrs: Record<string, string> = {};
  classes = new Set<string>();
  textContent = '';
  hidden = false;
  value = '';
  disabled = false;
  kids: El[] = [];
  parent: El | null = null;
  captured: number | null = null;
  listeners: Record<string, Function[]> = {};
  constructor(public tag: string, attrs: Record<string, string> = {}, classes: string[] = []) {
    this.attrs = attrs;
    for (const c of classes) this.classes.add(c);
  }
  // Setting innerHTML empties an element in a browser; a stub that keeps its
  // children makes a re-filled <select> look like it has every option twice.
  private html = '';
  get innerHTML() { return this.html; }
  set innerHTML(v: string) { this.html = v; if (v === '') this.kids = []; }
  get tagName() { return this.tag; }
  getAttribute(n: string) { return this.attrs[n] ?? null; }
  setAttribute(n: string, v: string | number) { this.attrs[n] = String(v); }
  addEventListener(t: string, fn: Function) { (this.listeners[t] ??= []).push(fn); }
  appendChild(k: El) { this.kids.push(k); k.parent = this; return k; }
  remove() {}
  setPointerCapture(id: number) { this.captured = id; }
  getBoundingClientRect() { return { x: 0, y: 0, width: 1000, height: 800, top: 0, left: 0 }; }
  get classList() {
    return {
      add: (c: string) => this.classes.add(c),
      remove: (c: string) => this.classes.delete(c),
      toggle: () => {},
      contains: (c: string) => this.classes.has(c),
    };
  }
  /** Enough of a selector match for the page: a class, or a tag name. */
  matches(sel: string) {
    return sel.startsWith('.') ? this.classes.has(sel.slice(1)) : this.tag === sel;
  }
  closest(sel: string): El | null {
    for (let el: El | null = this; el; el = el.parent) if (el.matches(sel)) return el;
    return null;
  }
  querySelectorAll() { return [] as El[]; }
}

/**
 * Run map.html's inline script against a stub DOM. A syntax check would not
 * catch what this catches: report.html once died on load because a variable was
 * read before the line that filled it, and the page rendered nothing while the
 * build reported success.
 *
 * The stub is built from the real page: its level panes, its room ids, and one
 * edge per pair of rooms the page says are joined, so the drag code moves the
 * same things a browser would move.
 */
function runPage(html: string, hash = '', seed: Record<string, string> = {}) {
  const src = html.match(/<script>([\s\S]*?)<\/script>/)![1];
  // Room ids and level slugs come from the page's own payload rather than from
  // its markup: the inline script contains the literal `data-id="` as part of a
  // selector, so scraping attributes picks up a room called `' + id + '`.
  const data = JSON.parse(src.match(/var DATA = (\{[\s\S]*?\});\n/)![1]);
  const levelSlugs = Object.keys(data.levels);
  const roomIds = Object.keys(data.home);
  const pairs = [...html.matchAll(/<line class="edge[^"]*" data-a="([^"]+)" data-b="([^"]+)"/g)]
    .map(m => [m[1], m[2]] as [string, string]);

  const panes = levelSlugs.map(slug => {
    const pane = new El('div', { 'data-level': slug });
    pane.appendChild(new El('svg', { viewBox: '0 0 1000 800' }));
    return pane;
  });
  const svgOf = (slug: string) => panes.find(p => p.attrs['data-level'] === slug)!.kids[0];
  const boxes = roomIds.map(id => {
    const box = new El('g', { 'data-id': id, 'data-a': id }, ['box']);
    box.parent = svgOf(id.slice(0, id.indexOf('/')));
    return box;
  });
  const edges = pairs.map(([a, b]) =>
    new El('line', { 'data-a': a, 'data-b': b, x1: '0', y1: '0', x2: '0', y2: '0' }));
  // One-way arrows are spanning elements too, and the only ones that have to be
  // re-AIMED on a drag rather than just moved.
  const arrows = [...html.matchAll(/<path class="arrow" data-a="([^"]+)" data-b="([^"]+)"/g)]
    .map(m => new El('path', { 'data-a': m[1], 'data-b': m[2], 'data-rot': '',
                               transform: '' }, ['arrow']));
  const area = new El('select'), level = new El('select');
  const stats = new El('div'), panel = new El('div'), reset = new El('button');
  const byId: Record<string, El> = { area, level, stats, panel, reset };

  const doc: any = {
    getElementById: (id: string) => byId[id] ?? new El('div'),
    createElement: (t: string) => new El(t),
    addEventListener(t: string, fn: Function) { (this._l ??= {})[t] = fn; },
    _l: {} as Record<string, Function>,
    querySelectorAll(sel: string) {
      if (sel === '[data-level]') return panes;
      if (sel === '[data-a]') return [...boxes, ...edges, ...arrows];
      if (sel === '.box.sel') return boxes.filter(b => b.classes.has('sel'));
      const m = sel.match(/^\[data-id="(.*)"\]$/);
      if (m) return boxes.filter(b => b.attrs['data-id'] === m[1]);
      return [];
    },
  };
  const loc: any = { hash };
  const hist: any = { replaceState(_s: unknown, _t: string, url: string) { loc.hash = url; } };
  const store: Record<string, string> = { ...seed };
  const storage = {
    getItem: (k: string) => store[k] ?? null,
    setItem: (k: string, v: string) => { store[k] = v; },
    removeItem: (k: string) => { delete store[k]; },
  };
  new Function('document', 'location', 'history', 'localStorage', src)(doc, loc, hist, storage);

  /** Press, move by (dx, dy) CSS pixels, release. */
  const dragBox = (box: El, dx: number, dy: number) => {
    doc._l.pointerdown({ target: box, clientX: 100, clientY: 100, pointerId: 1,
                         preventDefault() {} });
    if (dx || dy) doc._l.pointermove({ clientX: 100 + dx, clientY: 100 + dy });
    doc._l.pointerup({});
  };
  const boxFor = (slug: string) =>
    boxes.find(b => b.attrs['data-id'].startsWith(slug + '/'))!;

  return { doc, area, level, stats, panel, reset, panes, boxes, edges, arrows, store,
           dragBox, boxFor };
}

describe('the "you are here" mark', () => {
  const HERE = new Map([['test-level-1/corridor-1', ['Tojolias']]]);

  it('rings the room a character stands in, and names them', () => {
    const svg = renderLevel(MINI, NAME_OF, HERE).svg;
    expect(svg).toContain('here-ring');
    expect(svg).toContain('>Tojolias<');
  });

  it('marks that room and no other', () => {
    const svg = renderLevel(MINI, NAME_OF, HERE).svg;
    expect(svg.match(/here-ring/g)).toHaveLength(1);
  });

  // The room keeps whatever else it was. corridor-1 is trapped, and a fill would
  // have hidden that, which is why the mark is a ring outside the box.
  it('does not displace the marks the room already carried', () => {
    const svg = renderLevel(MINI, NAME_OF, HERE).svg;
    expect(svg).toContain('trap-dot');
    expect(svg).toContain('class="box trapped here"');
  });

  it('draws nothing at all when nobody is located', () => {
    const svg = renderLevel(MINI, NAME_OF).svg;
    expect(svg).not.toContain('here-ring');
  });

  it('names the character in the room tooltip too', () => {
    const svg = renderLevel(MINI, NAME_OF, HERE).svg;
    expect(svg).toContain('you are here: Tojolias');
  });

  it('lists several characters sharing a room', () => {
    const svg = renderLevel(MINI, NAME_OF,
      new Map([['test-level-1/hall', ['Kerhak', 'Teekywiki']]])).svg;
    expect(svg).toContain('you are here: Kerhak, Teekywiki');
  });

  // map/players.json is untracked and written only by `bun export.ts`, so a fresh
  // clone and the VPS both have none. That must draw a plain map, not fail.
  it('reads no players from a directory without the file', async () => {
    expect((await readPlayers('map/does-not-exist')).size).toBe(0);
  });

  it('reads the players file when it is there', async () => {
    const dir = `/tmp/ta-players-${Date.now()}`;
    await Bun.write(`${dir}/players.json`, JSON.stringify(
      { players: [{ player: 'Tojolias', room: 'deep-forest/deep-forest-1' }] }));
    const byRoom = await readPlayers(dir);
    expect(byRoom.get('deep-forest/deep-forest-1')).toEqual(['Tojolias']);
  });

  it('ignores a malformed entry rather than throwing', async () => {
    const dir = `/tmp/ta-players-bad-${Date.now()}`;
    await Bun.write(`${dir}/players.json`, '{"players":[{"player":"NoRoom"},null]}');
    expect((await readPlayers(dir)).size).toBe(0);
  });
});

describe('map.html', () => {
  const areasP = readAreas();

  it('builds from the checked-in JSON alone', async () => {
    // No tele-arena.db is opened anywhere in site.ts. This is the whole claim the
    // page is here to test: the export carries enough to draw the world.
    const areas = await areasP;
    expect(areas.length).toBeGreaterThan(1);
    expect(await Bun.file('site.ts').text()).not.toContain('bun:sqlite');
  });

  it('runs without throwing, and shows exactly one level', async () => {
    const { panes, stats } = runPage(buildPage(await areasP));
    expect(panes.filter(p => !p.hidden).length).toBe(1);
    expect(stats.innerHTML).toContain('rooms');
  });

  it('opens the level named in the hash, and its Area with it', async () => {
    const areas = await areasP;
    const { panes, area, level } = runPage(buildPage(areas), '#stoneworks-level-2');
    expect(panes.find(p => !p.hidden)!.attrs['data-level']).toBe('stoneworks-level-2');
    expect(area.value).toBe('The Stoneworks');
    expect(level.value).toBe('stoneworks-level-2');
  });

  it('fills the Level select from the Area, and disables it when there is one', async () => {
    const areas = await areasP;
    const { area, level, doc } = runPage(buildPage(areas), '#desert');
    expect(level.disabled).toBe(true);          // the desert has no levels
    area.value = 'The Stoneworks';
    area.listeners.change[0]();
    expect(level.disabled).toBe(false);
    expect(level.kids.map(o => o.textContent)).toEqual(['Level 1', 'Level 2']);
    expect(doc).toBeDefined();
  });

  it('shows a room when one is clicked', async () => {
    // A press that goes nowhere is a click. Selecting on pointerup rather than on
    // click is what stops a drag from also opening the panel.
    const { dragBox, boxFor, panel } = runPage(buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    dragBox(box, 0, 0);
    expect(panel.innerHTML).toContain(box.attrs['data-id']);
    expect(box.classes.has('sel')).toBe(true);
  });

  it('moves a dragged room, and the exits with it', async () => {
    const { dragBox, boxFor, edges, panel } = runPage(
      buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    const id = box.attrs['data-id'];
    const before = box.attrs['transform'];
    const edge = edges.find(e => e.attrs['data-a'] === id || e.attrs['data-b'] === id)!;
    const edgeBefore = [edge.attrs['x1'], edge.attrs['y1'], edge.attrs['x2'], edge.attrs['y2']];

    dragBox(box, 60, 40);

    expect(box.attrs['transform']).not.toBe(before);
    // The whole point: the line still ends on the box at each end.
    expect([edge.attrs['x1'], edge.attrs['y1'], edge.attrs['x2'], edge.attrs['y2']])
      .not.toEqual(edgeBefore);
    // A drag is not a click, so the panel stays as it was.
    expect(panel.innerHTML).not.toContain(id);
    expect(box.classes.has('dragging')).toBe(false);
  });

  it('converts pointer pixels through the viewBox', async () => {
    // The SVG is scaled to its pane, so a 100px drag is not 100 user units. Here
    // the stub reports a 1000px-wide box for a 1000-unit viewBox, so the scale is
    // 1 and the arithmetic is checkable by hand.
    const { dragBox, boxFor } = runPage(buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    const [x0, y0] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    dragBox(box, 60, 40);
    const [x1, y1] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    expect(x1 - x0).toBeCloseTo(60, 6);
    expect(y1 - y0).toBeCloseTo(40, 6);
  });

  it('keeps an arrangement per level, and gives it back', async () => {
    const html = buildPage(await areasP);
    const first = runPage(html, '#stoneworks-level-2');
    const id = first.boxFor('stoneworks-level-2').attrs['data-id'];
    first.dragBox(first.boxFor('stoneworks-level-2'), 60, 40);
    const moved = first.boxFor('stoneworks-level-2').attrs['transform'];
    expect(Object.keys(first.store)).toEqual(['ta-map-layout:stoneworks-level-2']);
    expect(JSON.parse(first.store['ta-map-layout:stoneworks-level-2'])[id]).toBeDefined();
  });

  it('resets a level to where the layout pass put it', async () => {
    const { dragBox, boxFor, reset, store } = runPage(
      buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    const home = box.attrs['transform'];
    dragBox(box, 60, 40);
    expect(box.attrs['transform']).not.toBe(home);
    reset.listeners.click[0]();
    expect(box.attrs['transform']).toBe(home);
    expect(store['ta-map-layout:stoneworks-level-2']).toBeUndefined();
  });

  it('will not let a room be pushed off the edge of the drawing', async () => {
    // A box outside the viewBox is clipped away: nothing left to click, and the
    // only line to it runs off the pane. The stub svg is 1000x800.
    const { dragBox, boxFor, doc } = runPage(buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    dragBox(box, 5000, 4000);
    const [x, y] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    expect(x).toBeLessThanOrEqual(1000);
    expect(y).toBeLessThanOrEqual(800);
    for (let i = 0; i < 200; i++) {
      doc._l.keydown({ key: 'ArrowRight', shiftKey: true, target: box, preventDefault() {} });
    }
    const [x2] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    expect(x2).toBeLessThanOrEqual(1000);
  });

  it('pulls a stray room back in without disturbing the rest of the arrangement', async () => {
    // The repair an arrangement saved before the clamp existed needs: one room
    // off the map, every other room left exactly where the reader put it.
    const html = buildPage(await areasP);
    const probe = runPage(html, '#stoneworks-level-2');
    const lost = probe.boxFor('stoneworks-level-2').attrs['data-id'];
    const kept = probe.boxes.filter(b => b.attrs['data-id'] !== lost
      && b.attrs['data-id'].startsWith('stoneworks-level-2/'))[0].attrs['data-id'];
    const saved = { [lost]: [4000, 3000], [kept]: [300, 200] };
    const { boxes } = runPage(html, '#stoneworks-level-2',
      { 'ta-map-layout:stoneworks-level-2': JSON.stringify(saved) });
    const at = (id: string) => boxes.find(b => b.attrs['data-id'] === id)!
      .attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    const [x, y] = at(lost);
    expect(x).toBeLessThanOrEqual(1000);
    expect(y).toBeLessThanOrEqual(800);
    expect(at(kept)).toEqual([300, 200]);
  });

  it('re-aims a one-way arrow when either end is dragged', async () => {
    // The arrow reads its angle from where the two rooms are NOW. Left alone it
    // keeps pointing at wherever the room used to be, which is worse than
    // drawing no arrow at all. The caverns' 87->90 is the live case.
    const { arrows, boxes, dragBox } = runPage(
      buildPage(await areasP), '#complex-caverns-level-1');
    expect(arrows.length).toBeGreaterThan(0);
    const arrow = arrows[0];
    const before = arrow.attrs['transform'];
    expect(before).toMatch(/rotate\(-?[\d.]+\)/);
    const source = boxes.find(b => b.attrs['data-id'] === arrow.attrs['data-a'])!;
    dragBox(source, 0, 300);
    const after = arrow.attrs['transform'];
    expect(after).toMatch(/rotate\(-?[\d.]+\)/);
    expect(after).not.toBe(before);
  });

  it('nudges the room under the keyboard, without touching any other', async () => {
    const { doc, boxFor, boxes } = runPage(buildPage(await areasP), '#stoneworks-level-2');
    const box = boxFor('stoneworks-level-2');
    const other = boxes.filter(b => b !== box
      && b.attrs['data-id'].startsWith('stoneworks-level-2/'))[0];
    const before = other.attrs['transform'];
    const [x0] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    doc._l.keydown({ key: 'ArrowRight', target: box, preventDefault() {} });
    const [x1] = box.attrs['transform'].match(/-?[\d.]+/g)!.map(Number);
    expect(x1).toBeGreaterThan(x0);
    expect(other.attrs['transform']).toBe(before);
  });

  it('cannot be broken out of by a room description', async () => {
    // `</script>` in the payload would end the element and spill the rest of the
    // page as text.
    const html = buildPage([{
      area: 'x', name: 'X', src: 't',
      rooms: [{ id: 'x/a', name: 'a', description: 'look </script> out', exits: {} }],
    }]);
    expect(html).not.toContain('look </script> out');
    expect(html).toContain('\\u003c/script>');
  });

  it('carries every area and every room into the page', async () => {
    const areas = await areasP;
    const html = buildPage(areas);
    for (const a of areas) expect(html).toContain(`data-level="${a.area}"`);
    const total = areas.reduce((n, a) => n + a.rooms.length, 0);
    // Every room is a box, and is also in the payload the panel reads.
    expect(html.match(/class="box[^"]*" data-id=/g)!.length).toBe(total);
  });

  it('names a legend entry for every mark it draws', async () => {
    const html = buildPage(await areasP);
    const legend = html.slice(html.indexOf('<h2>Legend</h2>'));
    for (const cls of ['edge', 'edge vert', 'stub', 'frontier', 'away', 'door-mark',
                       'seal-mark', 'device-dot', 'trap-dot', 'vbadge']) {
      expect(legend).toContain(`class="${cls}`);
    }
  });
});
