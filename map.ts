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

  // The shape the data ASKS for, which is not always a shape that exists. It is
  // consulted only when a nudge has to choose which neighbour to disappoint:
  // an edge this already violates lies on a loop that does not close, so no cell
  // anywhere will draw it right and there is nothing to be gained by moving a
  // room to chase it. Letting those edges pull is what made the nudge sacrifice
  // a perfectly drawable exit to satisfy an undrawable one.
  const ideal = idealCoords(rooms, exits);
  const hopeless = new Set<string>();
  for (const e of exits) {
    const o = OFF[e.direction];
    if (!o || !internal(e)) continue;
    const a = ideal.get(e.from_id)!, b = ideal.get(e.to_id!)!;
    if (b.c - a.c !== o[0] || b.r - a.r !== o[1])
      hopeless.add(`${e.from_id}|${e.direction}|${e.to_id}`);
  }

  // Split into connected components first. A room can be unreachable from the
  // origin without the map being wrong -- `pit` on dungeon level three is
  // entered only by falling through a trap door from level two -- and laying
  // out from a single root would place every such room nowhere, i.e. drop it
  // from the drawing with no error. Each component is laid out on its own and
  // the components are then tiled side by side, the way report.ts does it.
  //
  // The cut is made at the STAIRS: `u`/`d` join two rooms that are above and
  // below one another, and a flat grid has no cell for that, so the room on the
  // far side gets parked in whatever cell happens to be free next door. Every
  // room laid out from there inherits the lie, and a whole region ends up
  // rotated or folded through the region it hangs off -- which is where the
  // wrongly-drawn lines come from. Cutting there instead lays each flat region
  // out on its own, in its own coordinates, and the ^/v badges plus the stair
  // line carry the join. That is also how the shrine draws these caves: page 3
  // is five separate clusters joined by numbered up/down boxes, and cutting at
  // its four internal stairs reproduces exactly those five.
  //
  // A stair between two rooms the compass ALSO joins changes nothing: the
  // region stays one component, because the cut only removes an edge the flat
  // exits already duplicate.
  const neighbours = new Map<number, Set<number>>();
  for (const e of exits) {
    if (!internal(e) || !OFF[e.direction]) continue;
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
  const GAP = 2;
  // Each component is laid out in its own coordinates first and packed
  // afterwards, because where a cluster goes depends on how big the others are.
  const laid: { members: Map<number, Pos>; w: number; h: number }[] = [];
  roots.forEach((root, index) => {
    const members = rooms.filter(r => componentOf.get(r.id) === index).map(r => r.id);
    const inComponent = new Set(members);
    const local = new Map<number, Pos>([[root, { c: 0, r: 0 }]]);
    // Both ends, not just the source: a stair out of this region now leads to a
    // room in ANOTHER component, and the vertical pass below would otherwise
    // place it here as well as in its own layout -- the same room in two cells.
    const relevant = exits.filter(e => inComponent.has(e.from_id)
      && (!internal(e) || inComponent.has(e.to_id!)));

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
    // The wanted cell if it is free, else the best free one near it.
    //
    // "Best" is not "nearest". What a reader takes from this drawing is which
    // way a room lies from its neighbour, and both renderers draw that line
    // from the two cells alone -- so a nudge that keeps the room roughly close
    // but puts it on the wrong side of a neighbour produces a line that points
    // somewhere the exit does not go, silently. This used to scan rings in
    // raster order from (-1,-1), which has no notion of direction at all: 18 of
    // the 21 nudges across the map displaced WEST and 8 of them exactly
    // north-west, and that alone accounted for 34 of the 76 wrongly-drawn lines
    // (`skewedEdges`, and verify.ts's `lines point where the exits go`).
    //
    // So candidates are ranked rather than enumerated, and ranked against EVERY
    // neighbour already on the grid, not just the edge that happened to arrive
    // first. Honouring only that one edge is what left desert-27 and
    // town-sewers-167 wrong after the bearing was introduced: both were nudged
    // to a cell that read correctly from the room that placed them and wrongly
    // from another neighbour they already had. A room has one cell and several
    // bearings to satisfy, so the cell has to answer to all of them.
    //
    // The search gives up after LOOK rings. A room dragged far away to save one
    // bearing wrecks the others and sprawls the level besides.
    const LOOK = 3;
    // "From `at`, this room must lie in direction `o`." Both ends of the edge
    // are recorded the same way, so an exit pointing either way constrains.
    type Pull = { at: Pos; o: [number, number]; winnable: boolean };
    const pulls = (id: number): Pull[] => {
      const out: Pull[] = [];
      for (const e of relevant) {
        if (!internal(e)) continue;
        const o = OFF[e.direction];
        if (!o) continue;
        const winnable = !hopeless.has(`${e.from_id}|${e.direction}|${e.to_id}`);
        if (e.to_id === id) {
          const at = local.get(e.from_id);
          if (at) out.push({ at, o, winnable });
        } else if (e.from_id === id) {
          const at = local.get(e.to_id!);
          if (at) out.push({ at, o: [-o[0], -o[1]], winnable });
        }
      }
      return out;
    };
    const keepsSign = (p: Pos, q: Pull) =>
      Math.sign(p.c - q.at.c) === q.o[0] && Math.sign(p.r - q.at.r) === q.o[1];
    // Cosine of the angle between the bearing a cell actually has from `at` and
    // the bearing the exit claims. 1 is dead on, -1 is the opposite way.
    const bearing = (p: Pos, q: Pull) => {
      const vc = p.c - q.at.c, vr = p.r - q.at.r;
      const len = Math.hypot(vc, vr) * Math.hypot(q.o[0], q.o[1]);
      return len === 0 ? -1 : (vc * q.o[0] + vr * q.o[1]) / len;
    };
    const free = (id: number, want: Pos): Pos => {
      if (!taken(want.c, want.r)) return want;
      const must = pulls(id);
      // Ranked in three tiers, then by the cell's own coordinates so the choice
      // is a pure function of the graph and a re-run is byte-identical.
      //
      // Winnable exits come first and are never traded for an unwinnable one:
      // an exit already doomed by a loop that does not close will be drawn wrong
      // from every cell on the grid, so letting it pull is how a perfectly
      // drawable neighbour ends up sacrificed to it. They still rank SECOND
      // rather than not at all -- where two cells serve the winnable exits
      // equally, the one that also happens to suit a doomed exit is free, and
      // taking it draws eight fewer wrong lines across the map.
      const rank = (p: Pos): [number, number, number] => [
        must.filter(q => q.winnable && keepsSign(p, q)).length,
        must.filter(q => !q.winnable && keepsSign(p, q)).length,
        must.reduce((n, q) => n + bearing(p, q), 0),
      ];
      const better = (a: Pos, b: Pos) => {
        const x = rank(a), y = rank(b);
        for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return x[i] > y[i];
        return a.c !== b.c ? a.c < b.c : a.r < b.r;
      };
      let best: Pos | null = null;
      for (let ring = 1; ring < 40; ring++) {
        const open: Pos[] = [];
        for (let dc = -ring; dc <= ring; dc++)
          for (let dr = -ring; dr <= ring; dr++) {
            if (Math.max(Math.abs(dc), Math.abs(dr)) !== ring) continue;
            if (!taken(want.c + dc, want.r + dr))
              open.push({ c: want.c + dc, r: want.r + dr });
          }
        let here: Pos | null = null;
        for (const p of open) if (!here || better(p, here)) here = p;
        if (here && (!best || better(here, best))) best = here;
        // A cell that answers every neighbour is as good as it gets, and the
        // nearest ring to offer one wins -- no reason to keep walking outward.
        if (best && rank(best)[0] + rank(best)[1] === must.length) break;
        if (ring >= LOOK) break;
      }
      return best ?? want;
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
          local.set(e.to_id!, free(e.to_id!, { c: from.c + o[0], r: from.r + o[1] }));
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
    const rws = [...local.values()].map(p => p.r);
    const loC = Math.min(...cols), loR = Math.min(...rws);
    const normalised = new Map<number, Pos>();
    for (const [id, p] of local) normalised.set(id, { c: p.c - loC, r: p.r - loR });
    laid.push({ members: normalised,
                w: Math.max(...cols) - loC + 1, h: Math.max(...rws) - loR + 1 });
  });

  // Pack the clusters into ROWS rather than one long strip. Cutting at the
  // stairs turns a level into several clusters -- the caverns' level 3 into
  // five -- and tiling those side by side gave a drawing 54 cells wide and 17
  // tall, which reads as a strip of unrelated fragments and, in MAP.md, wraps
  // in a terminal. Shelf-packed to roughly square, they read as one map with
  // parts, which is how the shrine draws them and how they were laid out by
  // hand.
  //
  // Next-fit in component order, not by size: the origin's cluster stays first
  // and the rest keep the order the walk discovered them in, so the packing is
  // a pure function of the graph and a re-run is byte-identical.
  // The width to wrap at is SEARCHED rather than guessed. Clusters are few and
  // wide, so a greedy shelf takes whatever the first guess allows: every budget
  // between 20 and 28 packs the caverns' five the same way, into a column 20
  // wide and 32 tall, when 40 by 23 was available the whole time. Trying each
  // possible width and keeping the squarest-but-landscape result costs nothing
  // at this size and answers for every level instead of for the one that was
  // measured.
  const widest = Math.max(...laid.map(l => l.w));
  const fullWidth = laid.reduce((n, l) => n + l.w + GAP, -GAP);
  const shelve = (budget: number) => {
    const at: Pos[] = [];
    let c = 0, r = 0, shelf = 0, w = 0;
    for (const l of laid) {
      if (c > 0 && c + l.w > budget) { r += shelf + GAP; c = 0; shelf = 0; }
      at.push({ c, r });
      c += l.w + GAP;
      shelf = Math.max(shelf, l.h);
      w = Math.max(w, c - GAP);
    }
    return { at, w, h: r + shelf };
  };
  // Landscape, because that is the shape of a browser window and of a page of
  // MAP.md. Scored on the LOG of the ratio so that twice too wide and twice too
  // tall count the same, and ties go to the narrower drawing.
  const WANT = 1.6;
  let best = shelve(widest);
  for (let b = widest + 1; b <= fullWidth; b++) {
    const box = shelve(b);
    const score = (x: { w: number; h: number }) => Math.abs(Math.log(x.w / x.h / WANT));
    if (score(box) < score(best)) best = box;
  }
  laid.forEach((l, i) => {
    for (const [id, p] of l.members)
      pos.set(id, { c: p.c + best.at[i].c, r: p.r + best.at[i].r });
  });

  const unplaced = rooms.filter(r => !pos.has(r.id));
  if (unplaced.length) throw new Error(
    `${unplaced.length} room(s) could not be placed: ${unplaced.map(r => r.slug).join(', ')}`);

  return { pos, rooms, exits };
}

// Grid displacement back to a direction name, for saying what a line ACTUALLY
// points at.
const DIR_OF = new Map(Object.entries(OFF).map(([d, [c, r]]) => [`${c},${r}`, d]));

/**
 * Dead-reckon every room with NO collision handling, one compass-connected
 * slab at a time.
 *
 * A slab is a set of rooms joined by compass edges, and it is the unit the grid
 * can place rigidly: within one slab every edge has a true offset, so the whole
 * thing has exactly one shape (up to translation). `u`/`d` carry no offset, so
 * they are what separates one slab from the next -- the deep forest is seven
 * slabs, its floor and its platforms alternating.
 *
 * The result is the shape the data ASKS for, which is not always a shape that
 * exists: where a loop misses, two rooms land on one cell and an edge points the
 * wrong way. That is the point of computing it. `placeRooms` cannot tell you
 * this, because it resolves every such conflict silently.
 */
function idealCoords(rooms: Room[], exits: Exit[]): Map<number, Pos> {
  const ids = new Set(rooms.map(r => r.id));
  const internal = (e: Exit) => e.to_id != null && ids.has(e.to_id);
  const sorted = [...rooms].sort((a, b) => a.id - b.id);
  const edges = [...exits].sort(
    (a, b) => a.from_id - b.from_id || a.direction.localeCompare(b.direction));

  const slabOf = new Map<number, number>();
  const neighbours = new Map<number, Set<number>>();
  for (const e of edges) {
    if (!internal(e) || !OFF[e.direction]) continue;
    if (!neighbours.has(e.from_id)) neighbours.set(e.from_id, new Set());
    if (!neighbours.has(e.to_id!)) neighbours.set(e.to_id!, new Set());
    neighbours.get(e.from_id)!.add(e.to_id!);
    neighbours.get(e.to_id!)!.add(e.from_id);
  }
  let slabs = 0;
  for (const r of sorted) {
    if (slabOf.has(r.id)) continue;
    const index = slabs++;
    const stack = [r.id];
    slabOf.set(r.id, index);
    while (stack.length) {
      const cur = stack.pop()!;
      for (const n of neighbours.get(cur) ?? []) {
        if (slabOf.has(n)) continue;
        slabOf.set(n, index);
        stack.push(n);
      }
    }
  }

  const at = new Map<number, Pos>();
  for (let slab = 0; slab < slabs; slab++) {
    const seed = sorted.find(r => slabOf.get(r.id) === slab)!;
    at.set(seed.id, { c: 0, r: 0 });
    let moved = true;
    while (moved) {
      moved = false;
      for (const e of edges) {
        if (slabOf.get(e.from_id) !== slab) continue;
        const from = at.get(e.from_id);
        if (!from || !internal(e) || at.has(e.to_id!)) continue;
        const o = OFF[e.direction];
        if (!o) continue;
        at.set(e.to_id!, { c: from.c + o[0], r: from.r + o[1] });
        moved = true;
      }
    }
  }
  return at;
}

/** An edge the drawing points somewhere other than where the game says. */
export type Skew = {
  from_id: number;
  to_id: number;
  /** The direction the game reports for this exit. */
  direction: string;
  /** The direction the line actually points, read off the placed cells. */
  drawn: string;
  /**
   * True when no grid could have drawn it right: the loop this edge closes
   * misses, so the data is asking for a shape that does not exist in two
   * dimensions. False means the layout broke a representable edge on its own --
   * a collision nudge moved one end -- which is a bug rather than a fact about
   * the world.
   */
  inherent: boolean;
};

/**
 * Every edge whose drawn direction is not the one the game reports.
 *
 * Both renderers draw a connector from the GEOMETRY of where the two rooms
 * landed, not from the exit's direction -- deliberately, because `u`/`d` have no
 * direction to draw along. The cost is that a compass edge silently lies
 * whenever placement could not honour it, and nothing said so: `deep-forest-149
 * --sw--> deep-forest-150` was drawn pointing due north for months.
 *
 * Placement is first-come-wins (see `placeRooms`), so the first path to reach a
 * room fixes its cell and every later edge into it is merely drawn. This is what
 * tells the two causes apart, which matters because only one of them is fixable.
 */
export function skewedEdges(
  rooms: Room[], exits: Exit[], pos: Map<number, Pos>,
): Skew[] {
  const ids = new Set(rooms.map(r => r.id));
  const internal = (e: Exit) => e.to_id != null && ids.has(e.to_id);
  const ideal = idealCoords(rooms, exits);
  const out: Skew[] = [];
  for (const e of [...exits].sort(
    (a, b) => a.from_id - b.from_id || a.direction.localeCompare(b.direction))) {
    const want = OFF[e.direction];
    if (!want || !internal(e)) continue;
    const a = pos.get(e.from_id), b = pos.get(e.to_id!);
    if (!a || !b) continue;
    const dc = Math.sign(b.c - a.c), dr = Math.sign(b.r - a.r);
    if (dc === want[0] && dr === want[1]) continue;
    const ia = ideal.get(e.from_id)!, ib = ideal.get(e.to_id!)!;
    out.push({
      from_id: e.from_id, to_id: e.to_id!, direction: e.direction,
      drawn: DIR_OF.get(`${dc},${dr}`) ?? 'the same cell',
      inherent: ib.c - ia.c !== want[0] || ib.r - ia.r !== want[1],
    });
  }
  return out;
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
  // The deep forest below the fourth town's catwalks. Two levels in one area for
  // now: four wooden platforms and a rope bridge hang at the catwalks' height,
  // and three ways down from them reach the forest floor. The origin is the
  // platform you land on coming down from catwalk-18.
  { slug: 'deep-forest', title: 'The Deep Forest', origin: 'wooden-platform' },
  // West out of the forest. The origin is the room you arrive in, which is the
  // only landmark it has while the walk is young.
  { slug: 'valley', title: 'The Valley', origin: 'valley' },
  // Two areas opened off the valley: down to the caverns from valley-14, and
  // north-east to the corridors from valley-54 (still one room).
  // The title carries the level, because site.ts groups the Area select on the
  // NAME -- "<Area>, Level <N>" -- and an area whose name omits it lands in the
  // Level select as a dash. Level 1 read "-" beside level 2's "Level 2" until
  // this said so.
  { slug: 'complex-caverns-level-1', title: 'The Complex of Natural Caverns, Level 1',
    origin: 'complex-of-natural-caverns' },
  { slug: 'complex-caverns-level-2', title: 'The Complex of Natural Caverns, Level 2',
    origin: 'complex-of-natural-caverns-98' },
  // Level 4 before level 3, because the shrine's pages are what the levels are
  // named after and caverns-94's `d` lands on page 4. Nothing has been walked
  // onto page 3 yet -- that is caverns-97's `d`, the last unwalked staircase on
  // level 1 -- so there is no level-3 area to sit between these two. The Level
  // select sorts on the number, so the gap shows as 1, 2, 4 and reads correctly.
  { slug: 'complex-caverns-level-3', title: 'The Complex of Natural Caverns, Level 3',
    origin: 'complex-of-natural-caverns-191' },
  { slug: 'complex-caverns-level-4', title: 'The Complex of Natural Caverns, Level 4',
    origin: 'complex-of-natural-caverns-151' },
  { slug: 'hewn-granite-corridors', title: 'The Hewn Granite Corridors',
    origin: 'hewn-granite-corridor' },
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
