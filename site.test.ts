import { describe, expect, it } from 'bun:test';
import { awayLabel, boxLabel, buildPage, groupAreas, readAreas, renderLevel, splitName }
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
    expect(svg.match(/class="edge"/g)!.length).toBe(3);
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
  getAttribute(n: string) { return this.attrs[n] ?? null; }
  setAttribute(n: string, v: string) { this.attrs[n] = v; }
  addEventListener(t: string, fn: Function) { (this.listeners[t] ??= []).push(fn); }
  appendChild(k: El) { this.kids.push(k); return k; }
  remove() {}
  get classList() {
    return {
      add: (c: string) => this.classes.add(c),
      remove: (c: string) => this.classes.delete(c),
      toggle: () => {},
      contains: (c: string) => this.classes.has(c),
    };
  }
  closest(sel: string) {
    return sel === '.box' && this.classes.has('box') ? this : null;
  }
  querySelectorAll() { return [] as El[]; }
}

/**
 * Run map.html's inline script against a stub DOM. A syntax check would not
 * catch what this catches: report.html once died on load because a variable was
 * read before the line that filled it, and the page rendered nothing while the
 * build reported success.
 */
function runPage(html: string, hash = '') {
  const src = html.match(/<script>([\s\S]*?)<\/script>/)![1];
  const levelSlugs = [...html.matchAll(/data-level="([^"]+)"/g)].map(m => m[1]);
  const roomIds = [...html.matchAll(/data-id="([^"]+)"/g)].map(m => m[1]);

  const panes = levelSlugs.map(s => new El('div', { 'data-level': s }));
  // One box per level pane is enough to click; the page finds them by data-id.
  const boxes = roomIds.map(id => new El('g', { 'data-id': id }, ['box']));
  const area = new El('select'), level = new El('select');
  const stats = new El('div'), panel = new El('div');
  const byId: Record<string, El> = { area, level, stats, panel };

  const doc: any = {
    getElementById: (id: string) => byId[id] ?? new El('div'),
    createElement: (t: string) => new El(t),
    addEventListener(t: string, fn: Function) { (this._l ??= {})[t] = fn; },
    _l: {} as Record<string, Function>,
    querySelectorAll(sel: string) {
      if (sel === '[data-level]') return panes;
      if (sel === '.box.sel') return boxes.filter(b => b.classes.has('sel'));
      const m = sel.match(/^\[data-id="(.*)"\]$/);
      if (m) return boxes.filter(b => b.attrs['data-id'] === m[1]);
      return [];
    },
  };
  const loc: any = { hash };
  const hist: any = { replaceState(_s: unknown, _t: string, url: string) { loc.hash = url; } };
  new Function('document', 'location', 'history', src)(doc, loc, hist);
  return { doc, area, level, stats, panel, panes, boxes };
}

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
    const areas = await areasP;
    const { doc, boxes, panel } = runPage(buildPage(areas), '#stoneworks-level-2');
    const box = boxes.find(b => b.attrs['data-id'].startsWith('stoneworks-level-2/'))!;
    doc._l.click({ target: box });
    expect(panel.innerHTML).toContain(box.attrs['data-id']);
    expect(box.classes.has('sel')).toBe(true);
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
    for (const cls of ['edge', 'stub', 'frontier', 'away', 'door-mark', 'seal-mark',
                       'device-dot', 'trap-dot', 'vbadge']) {
      expect(legend).toContain(`class="${cls}`);
    }
  });
});
