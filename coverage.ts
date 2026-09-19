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
  legend: Map<string, string>;     // label -> the key line that explains it
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
  // Keep the legend: it is the only place a Teleport's destination is written
  // down, since no connector can draw one.
  const legend = new Map<string, string>();
  for (const line of end >= 0 ? all.slice(end) : []) {
    const m = line.match(/^\s*(\S{1,4})\s*[=-]\s*(.+?)\s*$/);
    if (m) legend.set(m[1], m[2]);
  }
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
  return { lines: g, boxes, edges, legend };
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

/**
 * Teleport destinations, read from the legend: "S2 = Push Stone to go to S3".
 *
 * A Teleport cannot be drawn -- there is no connector for "you end up over
 * there" -- so the drawing shows the destination as a detached box and says where
 * it came from only in words. Which means a walk of the boxes can never reach it,
 * and the [S3] strip read as unwalked after being walked.
 */
export function teleportLinks(d: Drawing): Map<string, string> {
  const out = new Map<string, string>();
  for (const [label, text] of d.legend) {
    const m = text.match(/to go to (\S+?)\.?$/);
    if (m && d.boxes.some(b => b.label === m[1])) out.set(label, m[1]);
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
export function pairRooms(
  d: Drawing, rooms: Room[], startRoomId: number, startBoxId: string,
  // room id -> room id, from devices with effect='teleport'. Without these the
  // walk stops at every Teleport, because the drawing has no edge to follow.
  teleports: Map<number, number> = new Map(),
) {
  const links = teleportLinks(d);
  const boxByLabel = new Map(d.boxes.filter(b => b.label).map(b => [b.label, b.id]));
  const byId = new Map(rooms.map(r => [r.id, r]));
  const pair = new Map<number, string>([[startRoomId, startBoxId]]);
  const taken = new Set<string>([startBoxId]);
  const problems: string[] = [];
  // Ways out of the area. The shrine draws the room across a Seam as a caption
  // rather than a box ("Down to Sewers", "[S] Stoneworks"), so an exit leading out
  // has no connector to match and is not a disagreement -- it is the area ending.
  const leaves: string[] = [];
  // The other direction, which nothing used to check: a connector the DRAWING
  // gives a paired box where the game gives that room no such exit. `problems`
  // only ever reads our exits against the drawing, so a line the shrine draws and
  // we do not have was rendered on the page and reported nowhere -- which is how
  // an east exit out of complex-of-natural-caverns-5 sat on the coverage picture,
  // contradicting map.html, until someone put the two side by side.
  //
  // Only PAIRED boxes are judged, because only there do we know the room's whole
  // exit-set from `ex`. Where the far end is a box we have not walked the
  // disagreement still holds: the room has the exits it has, whoever is on the
  // other side of them.
  const drawn: string[] = [];
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
        if (!byId.has(to)) leaves.push(`${byId.get(id)!.slug} ${dir} (out of this area)`);
        else problems.push(`${byId.get(id)!.slug} --${dir}--> exists for us, not in the drawing`);
        continue;
      }
      if (pair.has(to)) continue;
      if (taken.has(beyond)) {
        problems.push(`${byId.get(to)?.slug ?? `#${to}`} wants a drawing box already paired`);
        continue;
      }
      // A destination in ANOTHER area still occupies its box -- the drawing draws
      // the room across a Seam, and we do have it, just filed elsewhere. So mark
      // the box walked and stop: following its exits would read a neighbouring
      // area's graph through this area's drawing. The desert's `[S]` is the case:
      // its box is stoneworks-level-1's riddle chamber, and before this the walk
      // queued a room it had no record of and died on it.
      pair.set(to, beyond); taken.add(beyond);
      if (byId.has(to)) queue.push(to);
    }
    // Then the Teleport, if this room has one and the legend says where its box
    // lands. The destination is a detached box, so nothing else can reach it.
    const dest = teleports.get(id);
    const label = d.boxes.find(b => b.id === boxId)!.label;
    const targetLabel = label ? links.get(label) : undefined;
    const target = targetLabel ? boxByLabel.get(targetLabel) : undefined;
    if (dest != null && target && !pair.has(dest)) {
      if (taken.has(target)) {
        problems.push(`${byId.get(dest)!.slug} wants drawing box [${targetLabel}], already paired`);
      } else {
        pair.set(dest, target); taken.add(target); queue.push(dest);
      }
    }
  }
  for (const [k, dir] of d.edges) {
    const [from, to] = k.split('|');
    let ours: number | undefined;
    for (const [roomId, boxId] of pair) if (boxId === from) { ours = roomId; break; }
    if (ours == null) continue;
    const room = byId.get(ours);
    if (!room || dir in room.exits) continue;
    let far: number | undefined;
    for (const [roomId, boxId] of pair) if (boxId === to) { far = roomId; break; }
    const where = far != null ? byId.get(far)?.slug ?? `#${far}` : 'a box we have not walked';
    drawn.push(`${room.slug} is drawn with ${dir} to ${where}`
      + `, but the game gives it ${Object.keys(room.exits).sort().join(',')}`);
  }
  return { pair, problems, leaves, drawn };
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

/**
 * Which shrine drawing goes with which area, and the room that sits on which box.
 * Add a line per area as each is mapped; the shrine's six stoneworks drawings are
 * stoneworks-1..6.
 *
 * Registering an area is what makes `just coverage <slug>` work, and that command
 * is for a walk in PROGRESS -- it exists to say how much is left. So an entry here
 * is not a claim that the area is finished or that it agrees with its drawing.
 * COMPLETE, in coverage.test.ts, is where that claim lives.
 */
export const SHRINE_MAPS: Record<string,
  { file: string; originBox: string; originRoom: string }> = {

  'stoneworks-level-1': {
    file: 'map/shrine/stoneworks-1.txt',
    originBox: '@',                      // "say komi" to enter
    originRoom: 'stonework-chamber',
  },
  // The desert's one certain landmark: [v] is the room whose `d` drops into the
  // sewers, and crude-stone-building is the only room of ours with that exit.
  // Every other box on that drawing is an anonymous stretch of sand.
  desert: {
    file: 'map/shrine/desert.txt',
    originBox: 'v',
    originRoom: 'crude-stone-building',
  },
  'stoneworks-level-2': {
    file: 'map/shrine/stoneworks-2.txt',
    originBox: '^',                      // the stairs back up to Level 1
    originRoom: 'stonework-chamber-5',
  },
  // The fourth town, whose drawing carries one correction -- see the header of
  // town-4.txt. Five of its boxes are labelled shops, so the origin has a choice
  // of landmarks; [W] is the one the walk started from.
  'fourth-town': {
    file: 'map/shrine/town-4.txt',
    originBox: 'W',                      // Weapon Shop ("advanced weapons!")
    originRoom: 'weapon-shop-3',
  },
  // The valley west of the deep forest, still being walked. Its page has exactly
  // one labelled box, [v]: a single north connector over a down exit, which is
  // valley-14 and nothing else -- `d` to the caverns, `n` to valley-13. Anchoring
  // there puts both of the area's ways out on the captions the shrine drew for
  // them, which is the confirmation that the box is the right one.
  valley: {
    file: 'map/shrine/valley.txt',
    originBox: 'v',                      // down to the Complex of Natural Caverns
    originRoom: 'valley-14',
  },
  // Down from valley-14. The shrine draws this cave system as FOUR pages, joined
  // by numbered up/down boxes -- complexcaverns1..4 -- and the walk so far is all
  // on page 1: the three `d` exits off it are still frontiers, so nothing has yet
  // been walked onto 2, 3 or 4. Only page 1 is registered here because only page 1
  // has an area to pair with; when a `d` is walked, the room it lands in belongs to
  // a NEW area (`map-area complex-caverns-level-2`), which gets its own entry.
  //
  // Caverns 1 carries exactly one [^], captioned "Up to Valley", and exactly one
  // room of ours has a `u` leading out of the area -- so the two identify each
  // other, which is the confirmation the box is the right one.
  'complex-caverns': {
    file: 'map/shrine/complex-caverns-1.txt',
    originBox: '^',                      // up to the Valley
    originRoom: 'complex-of-natural-caverns',
  },
};

/**
 * Turn an exported area (map/areas/*.json) into what pairRooms wants: integer ids
 * with the bare slug, and the Teleports read off the devices. The CLI reads the
 * live database instead, because during a walk that is the thing you want to look
 * at -- but the JSON has to be sufficient on its own, and this is what proves it.
 */
export function roomsFromExport(area: {
  rooms: { id: string; exits: Record<string, { to: string | null }>;
           devices?: { effect: string; dest?: string }[] }[];
}): { rooms: Room[]; teleports: Map<number, number>; idOf: Map<string, number> } {
  const idOf = new Map(area.rooms.map((r, i) => [r.id, i + 1]));
  // A destination outside this area still needs a number, or its exit reads as
  // unwalked. Numbers past the area's own count are never in `rooms`, which is
  // exactly how pairRooms tells "another area's room" from one of ours.
  let outside = area.rooms.length;
  const num = (roomId: string) => {
    if (!idOf.has(roomId)) idOf.set(roomId, ++outside);
    return idOf.get(roomId)!;
  };
  const rooms: Room[] = area.rooms.map(r => ({
    id: idOf.get(r.id)!,
    slug: r.id.slice(r.id.indexOf('/') + 1),
    exits: Object.fromEntries(Object.entries(r.exits)
      .map(([dir, ex]) => [dir, ex.to == null ? null : num(ex.to)])),
  }));
  const teleports = new Map<number, number>();
  for (const r of area.rooms) {
    for (const d of r.devices ?? []) {
      if (d.effect === 'teleport' && d.dest) teleports.set(idOf.get(r.id)!, num(d.dest));
    }
  }
  return { rooms, teleports, idOf };
}

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const { existsSync } = await import('node:fs');

  const SHRINE = SHRINE_MAPS;

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

  // Teleports come from the devices table, which is where a Teleport's
  // destination lives -- it is deliberately not a compass edge.
  const teleports = new Map<number, number>();
  for (const t of db.prepare(
    `SELECT room_id, dest_room_id FROM devices
     WHERE effect = 'teleport' AND dest_room_id IS NOT NULL`).all() as any[]) {
    teleports.set(t.room_id, t.dest_room_id);
  }

  const { pair, problems, leaves, drawn } = pairRooms(
    drawing, rooms, start.id, startBox.id, teleports);
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
  say('walked exits that leave the area — the drawing captions these', leaves);
  say('lines the drawing has that we do not — the drawing is wrong, or we are', drawn);

  const unpaired = drawing.boxes.filter(b => !mapped.has(b.id));
  console.log(`\nboxes not yet ours (${unpaired.length})`);
  console.log('  ' + (unpaired.map(b => b.label ? `[${b.label}]` : `r${b.r}c${b.c0}`).join('  ') || 'none'));

  // "Not yet ours" reads as "rooms you have not walked", and that is only true
  // while there is somewhere left to walk. pairRooms is a BFS through OUR exits,
  // so a single direction it cannot follow -- a disagreement -- strands every box
  // behind it, walked or not. An area with no frontiers and unpaired boxes is
  // therefore describing a pairing failure, not missing rooms, and on the valley
  // it left six boxes listed that map.html was drawing all along. Say so, rather
  // than leave the reader to reconcile two lines that contradict each other.
  if (unpaired.length && !opens.length && !closes.length) {
    console.log(`\n  ^ but there is nothing left to walk here: no frontiers, and no`);
    console.log(`    unwalked link between rooms we have. The pairing stopped early`);
    console.log(problems.length
      ? `    at the ${problems.length === 1 ? 'disagreement' : 'disagreements'} below, so those boxes were never reached --`
      : `    without reaching those boxes --`);
    console.log(`    they may well be rooms you already have. map.html draws every`);
    console.log(`    room either way; this pairing is what cannot see them.`);
  }

  if (problems.length) {
    console.log(`\nDISAGREEMENTS WITH THE DRAWING (${problems.length})`);
    for (const p of problems) console.log('  ' + p);
  } else {
    console.log('\nno disagreements: every paired room has the exits the drawing gives its box');
  }
  console.log();
}
