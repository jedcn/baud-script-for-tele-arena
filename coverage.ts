// How much of a level have we actually walked?
//
// `just coverage stoneworks-level-1` prints the SHRINE'S OWN DRAWING with our
// rooms marked on it, then says what each frontier leads to.
//
// Why not just read MAP.md. map.ts lays an area out on a grid it derives by
// walking exits from an origin -- it never reads the stored coordinates -- so it
// draws a topologically faithful picture that looks nothing like the hand-drawn
// shrine map. Two people can then stare at both and disagree about whether a
// region is mapped, which is exactly what happened on 2026-09-13 over the
// bottom-left loop (it was done; it did not look done).
//
// Laying our rooms out from their stored coordinates instead gets much closer to
// the shrine, but silently drops rooms: three pairs in the Stoneworks share a
// cell, which is benign in this non-Euclidean world and fatal to a coordinate
// layout. So neither of our own renderings can be compared with the drawing at a
// glance.
//
// Marking the drawing itself sidesteps all of it. The layout is the shrine's, so
// the comparison is free, and every box is either ours or not.

export type Box = { id: string; label: string; r: number; c0: number; c1: number; cc: number };
export type Drawing = {
  lines: string[]; boxes: Box[];
  edges: Map<string, string>;      // "boxA|boxB" -> direction A->B
};

const REVERSE: Record<string, string> = {
  n: 's', s: 'n', e: 'w', w: 'e', ne: 'sw', sw: 'ne', nw: 'se', se: 'nw',
};

// Diagonals in these drawings are placed loosely -- a `/` may sit three columns
// from the box it joins -- so an endpoint is the NEAREST box on the adjoining row
// in the right horizontal half-plane, within a tolerance.
const TOL = 6;

/** Parse a shrine drawing into boxes and the edges between them. */
export function parseDrawing(text: string): Drawing {
  const all = text.split('\n').filter(l => !l.startsWith('#'));
  // The legend begins at the first "X = ..." line; everything above it is the map.
  const end = all.findIndex(l => /^\s*\S{1,4}\s=\s/.test(l));
  const grid = end >= 0 ? all.slice(0, end) : all;
  const W = Math.max(...grid.map(l => l.length)) + 8;
  const g = grid.map(l => l.padEnd(W, ' '));
  const at = (r: number, c: number) => (r >= 0 && r < g.length && c >= 0 && c < W) ? g[r][c] : ' ';

  const boxes: Box[] = [];
  const rowBoxes = new Map<number, Box[]>();
  g.forEach((line, r) => {
    for (const m of line.matchAll(/\[([^\]]*)\]/g)) {
      const c0 = m.index!, c1 = c0 + m[0].length - 1;
      const b: Box = { id: `${r}:${c0}`, label: m[1].trim(), r, c0, c1, cc: (c0 + c1) / 2 };
      boxes.push(b);
      if (!rowBoxes.has(r)) rowBoxes.set(r, []);
      rowBoxes.get(r)!.push(b);
    }
  });

  const near = (r: number, c: number, side: 'L' | 'R'): Box | null => {
    let best: Box | null = null, bd = Infinity;
    for (const b of rowBoxes.get(r) ?? []) {
      const d = side === 'L' ? c - b.c1 : b.c0 - c;
      if (d >= -1 && d < bd) { bd = d; best = b; }
    }
    return bd <= TOL ? best : null;
  };
  const edges = new Map<string, string>();
  const add = (a: Box | null, b: Box | null, dir: string) => {
    if (!a || !b || a.id === b.id) return;
    edges.set(`${a.id}|${b.id}`, dir);
    edges.set(`${b.id}|${a.id}`, REVERSE[dir]);
  };
  const runEnd = (r: number, c: number, dr: number, dc: number, ch: string): [number, number] => {
    let rr = r, cc = c;
    while (at(rr + dr, cc + dc) === ch) { rr += dr; cc += dc; }
    return [rr, cc];
  };
  for (let r = 0; r < g.length; r++) for (let c = 0; c < W; c++) {
    const ch = at(r, c);
    if (ch === '-') {
      if (at(r, c - 1) === '-') continue;
      const [, cR] = runEnd(r, c, 0, 1, '-');
      add(near(r, c, 'L'), near(r, cR, 'R'), 'e');
    } else if (ch === '|') {
      if (at(r - 1, c) === '|') continue;
      const [rB] = runEnd(r, c, 1, 0, '|');
      // Vertical: match on centre column, since a `|` sits under a box's middle.
      const pick = (rr: number) => {
        let best: Box | null = null, bd = Infinity;
        for (const b of rowBoxes.get(rr) ?? []) {
          const d = Math.abs(b.cc - c);
          if (d < bd) { bd = d; best = b; }
        }
        return bd <= 2 ? best : null;
      };
      add(pick(r - 1), pick(rB + 1), 's');
    } else if (ch === '\\') {
      if (at(r - 1, c - 1) === '\\') continue;
      const [rB, cB] = runEnd(r, c, 1, 1, '\\');
      add(near(r - 1, c, 'L'), near(rB + 1, cB, 'R'), 'se');
    } else if (ch === '/') {
      if (at(r - 1, c + 1) === '/') continue;
      const [rB, cB] = runEnd(r, c, 1, -1, '/');
      add(near(r - 1, c, 'R'), near(rB + 1, cB, 'L'), 'sw');
    }
  }
  return { lines: g, boxes, edges };
}

/** Directions out of a drawing box, to the box each reaches. */
export function drawingExits(d: Drawing, boxId: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, dir] of d.edges) {
    const [a, b] = k.split('|');
    if (a === boxId) out[dir] = b;
  }
  return out;
}

export type Room = { id: number; slug: string; exits: Record<string, number | null> };

/**
 * Pair our rooms to drawing boxes by walking both from a shared starting point.
 *
 * Pairing by exit-set alone would be worthless -- exit-sets repeat constantly --
 * so identity comes from the PATH, the same principle the mapper itself uses. A
 * box already taken is reported rather than reused, since that means the two
 * graphs disagree about shape.
 */
export function pairRooms(d: Drawing, rooms: Room[], startRoomId: number, startBoxId: string) {
  const byId = new Map(rooms.map(r => [r.id, r]));
  const pair = new Map<number, string>([[startRoomId, startBoxId]]);
  const taken = new Set<string>([startBoxId]);
  const problems: string[] = [];
  const queue = [startRoomId];
  while (queue.length) {
    const id = queue.shift()!;
    const boxId = pair.get(id)!;
    const mine = byId.get(id)!.exits, theirs = drawingExits(d, boxId);
    for (const dir of Object.keys(mine)) {
      const to = mine[dir];
      if (to == null) continue;
      const beyond = theirs[dir];
      if (!beyond) {
        problems.push(`${byId.get(id)!.slug} --${dir}--> exists for us, not in the drawing`);
        continue;
      }
      if (pair.has(to)) continue;
      if (taken.has(beyond)) {
        problems.push(`${byId.get(to)!.slug} wants a drawing box already paired`);
        continue;
      }
      pair.set(to, beyond); taken.add(beyond); queue.push(to);
    }
  }
  return { pair, problems };
}

/**
 * The drawing, with every box marked. Spacing is preserved exactly, so the output
 * can be diffed against the shrine file: `[#]`/`[.]` are the same width as `[ ]`,
 * and a labelled box keeps its width by swapping brackets for parentheses when it
 * is not ours.
 */
export function renderCoverage(d: Drawing, mapped: Set<string>): string[] {
  const out: string[] = [];
  for (let r = 0; r < d.lines.length; r++) {
    const row = d.lines[r].split('');
    for (const b of d.boxes.filter(x => x.r === r)) {
      const ours = mapped.has(b.id);
      if (b.label) {
        row[b.c0] = ours ? '[' : '(';
        row[b.c1] = ours ? ']' : ')';
      } else {
        row[b.c0 + 1] = ours ? '#' : '.';
      }
    }
    out.push(row.join('').replace(/\s+$/, ''));
  }
  while (out.length && out[out.length - 1] === '') out.pop();
  return out;
}

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const { existsSync } = await import('node:fs');

  // Which drawing goes with which area, and the room that sits on which box. Add
  // a line per level as each is mapped; the shrine's six stoneworks drawings are
  // stoneworks-1..6.
  const SHRINE: Record<string, { file: string; originBox: string; originRoom: string }> = {
    'stoneworks-level-1': {
      file: 'map/shrine/stoneworks-1.txt',
      originBox: '@',                      // "say komi" to enter
      originRoom: 'stonework-chamber',
    },
  };

  const slug = process.argv[2];
  const spec = slug ? SHRINE[slug] : undefined;
  if (!spec) {
    console.error(`coverage: no shrine drawing registered for '${slug ?? ''}'.`);
    console.error(`  known: ${Object.keys(SHRINE).join(', ') || '(none)'}`);
    process.exit(1);
  }
  if (!existsSync('tele-arena.db')) {
    console.error('coverage: no tele-arena.db here.');
    process.exit(1);
  }

  const drawing = parseDrawing(await Bun.file(spec.file).text());
  // A plain read-write handle, never mode=ro: baud keeps the DB in WAL mode and a
  // read-only connection cannot attach the -wal file, so it returns stale data.
  const db = new Database('tele-arena.db');
  const area = db.prepare('SELECT id FROM areas WHERE slug = ?').get(slug) as any;
  if (!area) { console.error(`coverage: no area '${slug}'`); process.exit(1); }

  const rows = db.prepare(
    'SELECT id, slug FROM rooms WHERE area_id = ? ORDER BY id').all(area.id) as any[];
  const exitRows = db.prepare(
    `SELECT from_id, direction, to_id FROM room_exits
     WHERE from_id IN (SELECT id FROM rooms WHERE area_id = ?)`).all(area.id) as any[];
  const rooms: Room[] = rows.map(r => ({ id: r.id, slug: r.slug, exits: {} }));
  const roomById = new Map(rooms.map(r => [r.id, r]));
  for (const e of exitRows) roomById.get(e.from_id)!.exits[e.direction] = e.to_id;

  const start = rooms.find(r => r.slug === spec.originRoom);
  const startBox = drawing.boxes.find(b => b.label === spec.originBox);
  if (!start || !startBox) {
    console.error(`coverage: cannot anchor '${spec.originRoom}' onto box '${spec.originBox}'`);
    process.exit(1);
  }

  const { pair, problems } = pairRooms(drawing, rooms, start.id, startBox.id);
  const mapped = new Set(pair.values());

  console.log(`\n${slug} — ${pair.size} of ${drawing.boxes.length} rooms in the drawing\n`);
  for (const line of renderCoverage(drawing, mapped)) console.log(line);
  console.log('\n  [#] walked    [.] not yet    [X1] landmark walked    (X1) landmark not yet\n');

  // Frontiers, and what the drawing says is on the other side. The distinction
  // that matters: a stub whose far side is ALREADY a room of ours adds nothing by
  // being walked -- it closes a loop. Mistaking one for unexplored territory is
  // how a region looks unfinished when it is done.
  const boxToRoom = new Map<string, number>();
  for (const [rid, bid] of pair) boxToRoom.set(bid, rid);
  const closes: string[] = [], opens: string[] = [], offMap: string[] = [];
  for (const r of rooms) {
    const bid = pair.get(r.id);
    if (!bid) continue;
    const theirs = drawingExits(drawing, bid);
    for (const dir of Object.keys(r.exits)) {
      if (r.exits[dir] != null) continue;
      const beyond = theirs[dir];
      if (!beyond) { offMap.push(`${r.slug} ${dir}`); continue; }
      const known = boxToRoom.get(beyond);
      if (known) closes.push(`${r.slug} ${dir} -> ${roomById.get(known)!.slug}`);
      else opens.push(`${r.slug} ${dir}`);
    }
  }
  const say = (title: string, items: string[]) => {
    console.log(`${title} (${items.length})`);
    for (const i of items) console.log(`  ${i}`);
    if (!items.length) console.log('  none');
  };
  say('frontiers into NEW rooms', opens);
  say('unwalked links between rooms we already have — walking one closes a loop', closes);
  say('unwalked exits the drawing does not show (a label, or off this map)', offMap);

  const unpaired = drawing.boxes.filter(b => !mapped.has(b.id));
  console.log(`\nboxes not yet ours (${unpaired.length})`);
  console.log('  ' + (unpaired.map(b => b.label ? `[${b.label}]` : `r${b.r}c${b.c0}`).join('  ') || 'none'));

  if (problems.length) {
    console.log(`\nDISAGREEMENTS WITH THE DRAWING (${problems.length})`);
    for (const p of problems) console.log('  ' + p);
  } else {
    console.log('\nno disagreements: every paired room has the exits the drawing gives its box');
  }
  console.log();
}
