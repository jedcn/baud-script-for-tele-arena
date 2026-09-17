// Render mapped areas as ASCII maps in a single Markdown file (MAP.md).
//
// The output format is the one the tele-arena shrine used for its hand-drawn
// town maps: a `[X]` box per room, `-` `|` `\` `/` connectors between them,
// `^`/`v` badges for vertical exits, and a key naming the lettered rooms. Our
// generated maps reproduce those drawings room-for-room, so the format is worth
// keeping rather than inventing a new one.
//
// `renderArea` is a pure function over plain rooms/exits so it can be tested
// without a database -- the map DB is absent on the VPS, and `dbOpen` would
// silently create an empty one.

export type Room = { id: number; slug: string; name: string };
export type Exit = { from_id: number; direction: string; to_id: number | null };

// Grid displacement per compass direction, in (col, row). North is up, so it
// decreases the row.
const OFF: Record<string, [number, number]> = {
  n: [0, -1], s: [0, 1], e: [1, 0], w: [-1, 0],
  ne: [1, -1], nw: [-1, -1], se: [1, 1], sw: [-1, 1],
};

// Characters per room. Five columns and three rows give a diagonal two
// characters of run, so it reads as a slope rather than an ambiguous corner.
// (The two hand-drawn shrine maps disagree with each other on pitch -- one uses
// two connector rows, the other one -- so there is no convention to preserve.
// Pick one and hold it.)
const PITCH_X = 5, PITCH_Y = 3;

// Rooms that get a letter, and what the key calls them. Everything else is a
// bare `[ ]`: plazas and corridors alike, which is how the shrine maps read --
// you navigate by the lettered boxes.
export const SERVICES: Record<string, { letter: string; label: string }> = {
  'arena': { letter: 'A', label: 'Arena' },
  'armor shop': { letter: 'a', label: 'Armor Shop' },
  'docks': { letter: 'D', label: 'Docks' },
  'equipment shop': { letter: 'E', label: 'Equipment Shop' },
  'guild hall': { letter: 'G', label: 'Guild Hall' },
  'inn': { letter: 'I', label: 'Inn' },
  'magic shop': { letter: 'M', label: 'Magic Shop' },
  'private room': { letter: 'p', label: 'Private Room' },
  'tavern': { letter: 'T', label: 'Tavern' },
  'temple': { letter: 't', label: 'Temple' },
  'town vaults': { letter: 'V', label: 'Town Vaults' },
  'weapon shop': { letter: 'W', label: 'Weapon Shop' },
};

export type RenderOpts = {
  rooms: Room[];
  exits: Exit[];
  origin: string;                      // slug to place at the grid origin
  areaOf?: (roomId: number) => string; // area name for an off-map destination
};

type Pos = { c: number; r: number };

export type Pos = { c: number; r: number };

export type Placement = {
  /** Room id -> integer grid cell. */
  pos: Map<number, Pos>;
  /** The same rooms and exits, sorted, so a renderer paints deterministically. */
  rooms: Room[];
  exits: Exit[];
};

/**
 * Place every room of an area on an integer grid by walking its exits from an
 * origin. Shared by the two renderers -- the ASCII maps in MAP.md and the SVG
 * in map.html -- because the hard part is the placement, not the paint, and two
 * copies of it would drift. Coordinates in the database are deliberately NOT
 * consulted (CLAUDE.md: "coordinates are soft; topology is truth").
 */
export function placeRooms(opts: {
  rooms: Room[]; exits: Exit[]; origin: string;
}): Placement {
  // Sort everything up front: placement depends on iteration order, and SQLite
  // makes no ordering promise without ORDER BY. Sorting here makes the output a
  // pure function of the data, so re-running produces a byte-identical file.
  const rooms = [...opts.rooms].sort((a, b) => a.id - b.id);
  const exits = [...opts.exits].sort(
    (a, b) => a.from_id - b.from_id || a.direction.localeCompare(b.direction));

  const ids = new Set(rooms.map(r => r.id));
  const byId = new Map(rooms.map(r => [r.id, r]));
  const origin = rooms.find(r => r.slug === opts.origin);
  if (!origin) throw new Error(`origin room '${opts.origin}' is not in this area`);

  const internal = (e: Exit) => e.to_id != null && ids.has(e.to_id);

  // Split into connected components first. A room can be unreachable from the
  // origin without the map being wrong -- `pit` on dungeon level three is
  // entered only by falling through a trap door from level two -- and laying
  // out from a single root would place every such room nowhere, i.e. drop it
  // from the drawing with no error. Each component is laid out on its own and
  // the components are then tiled side by side, the way report.ts does it.
  const neighbours = new Map<number, Set<number>>();
  for (const e of exits) {
    if (!internal(e)) continue;
    if (!neighbours.has(e.from_id)) neighbours.set(e.from_id, new Set());
    if (!neighbours.has(e.to_id!)) neighbours.set(e.to_id!, new Set());
    neighbours.get(e.from_id)!.add(e.to_id!);
    neighbours.get(e.to_id!)!.add(e.from_id);
  }
  const componentOf = new Map<number, number>();
  const roots: number[] = [];
  // The origin's component is laid out first so it stays leftmost.
  for (const seed of [origin.id, ...rooms.map(r => r.id)]) {
    if (componentOf.has(seed)) continue;
    const index = roots.length;
    roots.push(seed);
    const stack = [seed];
    componentOf.set(seed, index);
    while (stack.length) {
      const cur = stack.pop()!;
      for (const n of neighbours.get(cur) ?? []) {
        if (componentOf.has(n)) continue;
        componentOf.set(n, index);
        stack.push(n);
      }
    }
  }

  const pos = new Map<number, Pos>();
  let cursor = 0;                       // left edge of the next component
  const GAP = 2;
  roots.forEach((root, index) => {
    const members = rooms.filter(r => componentOf.get(r.id) === index).map(r => r.id);
    const inComponent = new Set(members);
    const local = new Map<number, Pos>([[root, { c: 0, r: 0 }]]);
    const relevant = exits.filter(e => inComponent.has(e.from_id));

    // Placement alternates two passes until nothing more can be placed.
    //
    // Compass edges carry a true direction, so they are always preferred and
    // are run to a fixpoint first. `u`/`d` have no compass offset, so a
    // vertical neighbour is parked in the first FREE adjacent cell and the ^/v
    // badges carry the vertical -- the way the shrine maps show the vaults and
    // the private room.
    //
    // The alternation matters as much as the order. A region can be reachable
    // only THROUGH a stair: the stoneworks chains flat regions together that
    // way. Running each pass once places the vertical neighbour but never the
    // rooms beyond it, which is 45 stonework rooms silently missing before the
    // unplaced guard below caught it. So: compass to fixpoint, then one
    // vertical, then compass again, until neither can move.
    const taken = (c: number, r: number) =>
      [...local.values()].some(p => p.c === c && p.r === r);
    // The wanted cell if it is free, else the nearest free one, searched in
    // rings so the room stays as close to its true direction as possible.
    const free = (_m: Map<number, Pos>, c: number, r: number): Pos => {
      if (!taken(c, r)) return { c, r };
      for (let ring = 1; ring < 40; ring++)
        for (let dc = -ring; dc <= ring; dc++)
          for (let dr = -ring; dr <= ring; dr++) {
            if (Math.max(Math.abs(dc), Math.abs(dr)) !== ring) continue;
            if (!taken(c + dc, r + dr)) return { c: c + dc, r: r + dr };
          }
      return { c, r };
    };
    for (;;) {
      let moved = true;
      while (moved) {
        moved = false;
        for (const e of relevant) {
          const from = local.get(e.from_id);
          if (!from || !internal(e) || local.has(e.to_id!)) continue;
          const o = OFF[e.direction];
          if (!o) continue;
          // Two distinct rooms can dead-reckon to the same cell -- this world is
          // not Euclidean and loops genuinely misclose, which CLAUDE.md notes is
          // by design in the data. Whoever gets there second must be nudged to
          // the nearest free cell or it silently overwrites the first and the
          // room vanishes from the drawing (35 stoneworks rooms did).
          local.set(e.to_id!, free(local, from.c + o[0], from.r + o[1]));
          moved = true;
        }
      }
      let placedVertical = false;
      for (const e of relevant) {
        const from = local.get(e.from_id);
        if (!from || !internal(e) || local.has(e.to_id!)) continue;
        if (e.direction !== 'u' && e.direction !== 'd') continue;
        const order: [number, number][] = e.direction === 'u'
          ? [[-1, -1], [1, -1], [0, -1], [-1, 0], [1, 0], [-1, 1], [1, 1], [0, 1]]
          : [[1, 1], [-1, 1], [0, 1], [1, 0], [-1, 0], [1, -1], [-1, -1], [0, -1]];
        for (const [dc, dr] of order)
          if (!taken(from.c + dc, from.r + dr)) {
            local.set(e.to_id!, { c: from.c + dc, r: from.r + dr });
            placedVertical = true;
            break;
          }
        if (placedVertical) break;
      }
      if (!placedVertical) break;
    }

    const cols = [...local.values()].map(p => p.c);
    const lo = Math.min(...cols), hi = Math.max(...cols);
    for (const [id, p] of local) pos.set(id, { c: p.c - lo + cursor, r: p.r });
    cursor += (hi - lo) + 1 + GAP;
  });

  const unplaced = rooms.filter(r => !pos.has(r.id));
  if (unplaced.length) throw new Error(
    `${unplaced.length} room(s) could not be placed: ${unplaced.map(r => r.slug).join(', ')}`);

  return { pos, rooms, exits };
}

/**
 * Place every room on an integer grid, then paint boxes, connectors and
 * off-map labels into a character buffer. Returns the map lines and the key.
 */
export function renderArea(opts: RenderOpts): { lines: string[]; key: string[] } {
  const { pos, rooms, exits } = placeRooms(opts);
  const byId = new Map(rooms.map(r => [r.id, r]));
  const ids = new Set(rooms.map(r => r.id));
  const internal = (e: Exit) => e.to_id != null && ids.has(e.to_id);

  const placed = [...pos.values()];
  const minC = Math.min(...placed.map(p => p.c)), maxC = Math.max(...placed.map(p => p.c));
  const minR = Math.min(...placed.map(p => p.r)), maxR = Math.max(...placed.map(p => p.r));
  const width = (maxC - minC) * PITCH_X + 5;
  const height = (maxR - minR) * PITCH_Y + 1;
  const grid: string[][] = Array.from({ length: height },
    () => Array.from({ length: width }, () => ' '));

  const centre = (p: Pos) => [(p.c - minC) * PITCH_X + 1, (p.r - minR) * PITCH_Y] as const;
  // Cells a box occupies, reserved even where the glyph char is a space. A
  // plain room draws as `[ ]`, so without this a diagonal connector passing
  // through overwrites the blank middle and the room renders as `[\]`.
  const reserved = new Set<string>();
  const put = (x: number, y: number, ch: string) => {
    if (!grid[y] || grid[y][x] === undefined) return;
    if (reserved.has(`${x},${y}`)) return;
    const cur = grid[y][x];
    // Two diagonals through one cell is a genuine crossing, not a clobber.
    if (cur === ' ') grid[y][x] = ch;
    else if (cur !== ch && (cur === '/' || cur === '\\')) grid[y][x] = 'X';
  };

  // Boxes first, then connectors. A room with a vertical exit gets a badge --
  // `[A^]` -- which is four characters wide and so overruns into the column a
  // horizontal connector wants. Drawing boxes first lets the connector give way
  // (`[A^]-[t]`); the other order silently ate the closing bracket.
  // Boxes. `[X]`, with `^`/`v` appended for vertical exits in either direction.
  const used = new Map<string, string>();
  for (const [id, p] of pos) {
    const room = byId.get(id)!;
    const dirs = new Set(exits.filter(e => e.from_id === id).map(e => e.direction));
    const service = SERVICES[room.name];
    if (service) used.set(service.letter, service.label);
    const badge = (dirs.has('u') ? '^' : '') + (dirs.has('d') ? 'v' : '');
    const glyph = `[${service?.letter ?? ' '}${badge}]`;
    const [x, y] = centre(p);
    for (let i = 0; i < glyph.length; i++) {
      grid[y][x - 1 + i] = glyph[i];
      reserved.add(`${x - 1 + i},${y}`);
    }
  }

  // Connectors. A vertical edge joins two rooms that pass 2 placed adjacently,
  // so draw it from the geometry of where they landed rather than from the
  // logical direction -- otherwise those rooms float unattached.
  for (const e of exits) {
    const a = pos.get(e.from_id), b = internal(e) ? pos.get(e.to_id!) : undefined;
    if (!a || !b) continue;
    const [ax, ay] = centre(a), [bx, by] = centre(b);
    const dc = Math.sign(b.c - a.c), dr = Math.sign(b.r - a.r);
    if (dr === 0) {
      for (let x = Math.min(ax, bx) + 2; x <= Math.max(ax, bx) - 2; x++) put(x, ay, '-');
      continue;
    }
    const ch = dc === 0 ? '|' : (dc === dr ? '\\' : '/');
    const steps = Math.abs(by - ay);
    for (let s = 1; s < steps; s++)
      put(Math.round(ax + (bx - ax) * (s / steps)), ay + Math.sign(by - ay) * s, ch);
  }

  // Off-map exits become text labels. They are appended AFTER rasterizing, not
  // written into the grid: an edge leaving the area has nowhere to go on this
  // grid, and writing past the buffer would leave holes that `join` swallows.
  // All labels land in one column so they read as a margin.
  const labels = new Map<number, string[]>();
  for (const e of exits) {
    if (internal(e)) continue;
    const p = pos.get(e.from_id);
    if (!p) continue;
    const where = e.to_id == null ? 'unexplored' : (opts.areaOf?.(e.to_id) ?? '?');
    const label = e.direction === 'passage' ? `passage to ${where}`
      : e.direction === 'u' ? `up to ${where}`
      : e.direction === 'd' ? `down to ${where}`
      : `${e.direction} to ${where}`;
    const [, y] = centre(p);
    labels.set(y, [...(labels.get(y) ?? []), label]);
  }

  const drawn = grid.map(row => row.join('').replace(/\s+$/, ''));
  const margin = Math.max(...drawn.map(l => l.length)) + 3;
  // Every room must appear. Placement can no longer collide, but a glyph could
  // still be overwritten by a later one, so count what actually got drawn.
  const boxes = (drawn.join('\n').match(/\[[^\]]*\]/g) ?? []).length;
  if (boxes !== rooms.length)
    throw new Error(`drew ${boxes} boxes for ${rooms.length} rooms — ${rooms.length - boxes} lost`);

  const lines = drawn.map((line, y) => {
    const ls = labels.get(y);
    return ls ? (line.padEnd(margin) + ls.join('   ')).replace(/\s+$/, '') : line;
  });
  const key = [...used.entries()]
    .sort((a, b) => a[1].localeCompare(b[1]))
    .map(([letter, label]) => `${letter} = ${label}`);
  return { lines, key };
}

/** Assemble the whole MAP.md document from already-rendered areas. */
export function buildMarkdown(
  areas: { title: string; lines: string[]; key: string[] }[],
): string {
  const anchor = (t: string) => t.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const out: string[] = ['# Tele Arena Map', '', '## Table of Contents', ''];
  areas.forEach((a, i) => out.push(`${i + 1}. [${a.title}](#${anchor(a.title)})`));
  for (const a of areas) {
    out.push('', `### ${a.title}`, '', '```');
    out.push(...a.lines);
    out.push('```', '');
    if (a.key.length) {
      out.push('Key:', '');
      for (const k of a.key) out.push(`- \`${k.split(' = ')[0]}\` — ${k.split(' = ')[1]}`);
      out.push('', '`[ ]` — a room with no shop or service (plaza, path, corridor).');
      out.push('`^` / `v` — an exit up / down.');
    }
  }
  return out.join('\n').replace(/\n{3,}/g, '\n\n') + '\n';
}

// --------------------------------------------------------------------------
// CLI: `bun map.ts` (see `just draw-map-as-markdown`)
// --------------------------------------------------------------------------

// Which areas get drawn, in what order, and which room anchors the grid. The
// origin only fixes where (0,0) sits -- it does not affect topology -- so pick
// a central, memorable room.
export const DRAWN = [
  { slug: 'first-town', title: 'First Town', origin: 'north-plaza' },
  { slug: 'second-town', title: 'Second Town', origin: 'north-plaza-1' },
  // The dungeon under the first town. Each level is its own area (they are
  // joined by exactly three passages), so each renders as an ordinary section
  // and the stairs between them fall out as cross-area labels. Origins are the
  // room you arrive in coming down from the level above.
  { slug: 'first-dungeon-level-1', title: 'First Dungeon, Level 1', origin: 'dungeon-entrance' },
  { slug: 'first-dungeon-level-2', title: 'First Dungeon, Level 2', origin: 'bottom-of-a-circular-stairwell' },
  { slug: 'first-dungeon-level-3', title: 'First Dungeon, Level 3', origin: 'bottom-of-a-stairwell' },
  // The desert, which is not split into levels and renders as a sprawl.
  { slug: 'desert', title: 'The Desert', origin: 'crude-stone-building' },
  // The stoneworks, one area per level now, which is what the shrine draws. The
  // old flat `stoneworks` area held all six at once and is empty; levels 1 and 2
  // are mapped. Level 1's origin is the riddle chamber, where the shrine's
  // drawing starts -- `say komi` there opens the way in; level 2's is the room
  // you arrive in coming down from level 1.
  { slug: 'stoneworks-level-1', title: 'The Stoneworks, Level 1', origin: 'stonework-chamber' },
  { slug: 'stoneworks-level-2', title: 'The Stoneworks, Level 2', origin: 'stonework-chamber-5' },
  // The sewers under the second town, three levels. Origins are the room you
  // arrive in coming down from above.
  { slug: 'sewers-level-1', title: 'Sewers, Level 1', origin: 'town-sewers' },
  { slug: 'sewers-level-2', title: 'Sewers, Level 2', origin: 'town-sewers-63' },
  { slug: 'sewers-level-3', title: 'Sewers, Level 3', origin: 'town-sewers-118' },
  // The wilderness south-west of the first town, and what lies under it.
  { slug: 'mountains', title: 'The Mountains', origin: 'mountains' },
  { slug: 'cellars', title: 'The Cellars', origin: 'cellar' },
  { slug: 'third-town', title: 'Third Town', origin: 'town-square' },
  // The fourth town, which no mapped area reaches yet -- the only way on from it
  // is catwalk-18's `d`, down to the deep forest. Its four plazas sit in a 2x2
  // square at the centre; the north-west one anchors the grid.
  { slug: 'fourth-town', title: 'Fourth Town', origin: 'northwest-plaza' },
];

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const { existsSync } = await import('node:fs');

  const DB_PATH = 'tele-arena.db';
  if (!existsSync(DB_PATH)) {
    console.error(`map: no ${DB_PATH} here — nothing to draw.`);
    process.exit(1);
  }
  // A plain read-write handle, never mode=ro: baud keeps the DB in WAL mode and
  // a read-only connection cannot attach the -wal file, so it silently returns
  // stale data.
  const db = new Database(DB_PATH);

  const areaName = db.prepare(
    'SELECT a.name FROM rooms r JOIN areas a ON a.id = r.area_id WHERE r.id = ?');

  const rendered = DRAWN.map(({ slug, title, origin }) => {
    const rooms = db.prepare(
      `SELECT r.id, r.slug, r.name FROM rooms r
       JOIN areas a ON a.id = r.area_id WHERE a.slug = ? ORDER BY r.id`)
      .all(slug) as Room[];
    // An area can legitimately be empty: one that has been cleared for
    // re-mapping still wants its row, so `map-area <slug>` can refile into it.
    if (!rooms.length) { console.log(`map: skipping '${slug}' — no rooms yet`); return null; }
    const exits = db.prepare(
      `SELECT from_id, direction, to_id FROM room_exits
       WHERE from_id IN (SELECT r.id FROM rooms r JOIN areas a ON a.id = r.area_id
                         WHERE a.slug = ?) ORDER BY from_id, direction`)
      .all(slug) as Exit[];
    const { lines, key } = renderArea({
      rooms, exits, origin,
      areaOf: (id) => (areaName.get(id) as { name: string } | null)?.name ?? '?',
    });
    return { title, lines, key };
  }).filter((a): a is { title: string; lines: string[]; key: string[] } => a !== null);

  await Bun.write('MAP.md', buildMarkdown(rendered));
  const total = rendered.reduce((n, a) => n + a.lines.length, 0);
  console.log(`map: wrote MAP.md — ${rendered.length} areas, ${total} lines`);
}
