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

/**
 * The part of a page an area owns, when one page draws two areas. Rows and
 * columns are inclusive and count the drawing's grid -- the lines left once the
 * `#` header is dropped. `keep` says which side of the rectangle is this area's.
 */
export type Region = { rows: [number, number]; cols: [number, number]; keep: 'inside' | 'outside' };

/** Parse a shrine drawing into boxes and the edges between them. */
export function parseDrawing(text: string, region?: Region): Drawing {
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
  // Blank whatever lies outside this area's region before reading anything, so
  // the other area's boxes and connectors simply are not on the page.
  const owned = (r: number, c: number) => {
    if (!region) return true;
    const within = r >= region.rows[0] && r <= region.rows[1]
      && c >= region.cols[0] && c <= region.cols[1];
    return within === (region.keep === 'inside');
  };
  const g = grid.map((l, r) => [...l.padEnd(W, ' ')]
    .map((ch, c) => owned(r, c) ? ch : ' ').join(''));
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

  const inBox = (r: number, c: number) =>
    (rowBoxes.get(r) ?? []).some(b => c >= b.c0 && c <= b.c1);
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
  // A diagonal may slide two columns a row where the box it reaches sits too far
  // over for 45 degrees -- the swamp's Swordswoman climbs to her north-east
  // neighbour that way. Follow one column if it is there, else two.
  const diagStep = (r: number, c: number, dc: number, ch: string): number | null =>
    at(r + 1, c + dc) === ch ? c + dc : at(r + 1, c + 2 * dc) === ch ? c + 2 * dc : null;
  const diagEnd = (r: number, c: number, dc: number, ch: string): [number, number] => {
    let rr = r, cc = c, next: number | null;
    while ((next = diagStep(rr, cc, dc, ch)) != null) { rr += 1; cc = next; }
    return [rr, cc];
  };
  // Is (r, c) the continuation of a diagonal begun on the row above?
  const diagContinues = (r: number, c: number, dc: number, ch: string) =>
    [c - dc, c - 2 * dc].some(p => at(r - 1, p) === ch && diagStep(r - 1, p, dc, ch) === c);
  for (let r = 0; r < g.length; r++) for (let c = 0; c < W; c++) {
    const ch = at(r, c);
    if (ch === '-') {
      if (at(r, c - 1) === '-') continue;
      const [, cR] = runEnd(r, c, 0, 1, '-');
      add(near(r, c, 'L'), near(r, cR, 'R'), 'e');
    } else if (ch === '|' || ch === '#') {
      // A `#` standing in for a `|` is a locked door -- the labyrinth's "Lever at
      // 1 unlocks door (#)". Only outside a box ([#1] is a label), and a line of
      // nothing but `#` must sit exactly under one box's centre and over
      // another's: the hewn granite's slanted doors and "Scroll #3" are not
      // vertical lines, and a loose match read them as due south.
      const door = (rr: number) => at(rr, c) === '#' && !inBox(rr, c)
        && !/[A-Za-z0-9]/.test(at(rr, c - 1)) && !/[A-Za-z0-9]/.test(at(rr, c + 1));
      const vert = (rr: number) => at(rr, c) === '|' || door(rr);
      if (!vert(r) || vert(r - 1)) continue;
      let rB = r, bar = ch === '|';
      while (vert(rB + 1)) { rB++; if (at(rB, c) === '|') bar = true; }
      // Vertical: match on centre column, since a `|` sits under a box's middle.
      const pick = (rr: number) => {
        let best: Box | null = null, bd = Infinity;
        for (const b of rowBoxes.get(rr) ?? []) {
          const d = Math.abs(b.cc - c);
          if (d < bd) { bd = d; best = b; }
        }
        return bd <= (bar ? 2 : 0) ? best : null;
      };
      add(pick(r - 1), pick(rB + 1), 's');
    } else if (ch === '\\') {
      if (diagContinues(r, c, 1, '\\')) continue;
      const [rB, cB] = diagEnd(r, c, 1, '\\');
      add(near(r - 1, c, 'L'), near(rB + 1, cB, 'R'), 'se');
    } else if (ch === '.' && at(r, c + 1) === '[') {
      // A dot just left of a box: a step south-west onto the box on the next row
      // that ends where the dot is. The gnoll caves draw a staircase of boxes on
      // consecutive rows this way, having no row between them for a `/`.
      const below = (rowBoxes.get(r + 1) ?? []).find(b => Math.abs(b.c1 - (c - 1)) <= 1) ?? null;
      add((rowBoxes.get(r) ?? []).find(b => b.c0 === c + 1) ?? null, below, 'sw');
    } else if (ch === '/') {
      if (diagContinues(r, c, -1, '/')) continue;
      const [rB, cB] = diagEnd(r, c, -1, '/');
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
// The eight compass points in order, and the two either side of one. The shrine's
// drawings are hand-made: a corridor that runs west gets drawn on the diagonal
// when the page is tight, and a diagonal gets straightened when it is not. What
// they are reliable about is WHICH ROOM IS NEXT TO WHICH -- adjacency survives the
// draughtsman, exact bearing does not.
//
// So when our exit has no connector in the drawing, the box 45 degrees either side
// is tried before giving up. Only when exactly one such box is free, and every one
// is reported, because a skew is still a disagreement -- it is just one that should
// not strand the rest of the level behind it. Before this, one bad connector one
// step out of the entrance left 22 walked rooms reading as unwalked
// (the Complex of Natural Caverns, 2026-09-19).
const COMPASS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'];
function eitherSide(dir: string): string[] {
  const i = COMPASS.indexOf(dir);
  return i < 0 ? [] : [COMPASS[(i + 7) % 8], COMPASS[(i + 1) % 8]];
}

export function pairRooms(
  d: Drawing, rooms: Room[], startRoomId: number, startBoxId: string,
  // room id -> room id, from devices with effect='teleport'. Without these the
  // walk stops at every Teleport, because the drawing has no edge to follow.
  teleports: Map<number, number> = new Map(),
  // Further [room, box] anchors, for an area with more than one way in. The walk
  // below only reaches what our exits connect, so a branch entered by a second
  // door stays unplaced until something joins it to the first -- which is the
  // whole time you are walking it (the swamp, 2026-09-22).
  moreStarts: [number, string][] = [],
) {
  const links = teleportLinks(d);
  const boxByLabel = new Map(d.boxes.filter(b => b.label).map(b => [b.label, b.id]));
  const byId = new Map(rooms.map(r => [r.id, r]));
  const starts: [number, string][] = [[startRoomId, startBoxId], ...moreStarts];
  const pair = new Map<number, string>(starts);
  const taken = new Set<string>(starts.map(([, b]) => b));
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
  // Exits we followed 45 degrees off what the drawing shows (see eitherSide).
  const skewed: string[] = [];
  // Every drawing connector the walk actually used, both orientations. `drawn`
  // reports connectors we did NOT use, and a skewed edge is used -- so without
  // this each skew is reported a second time from its far end, wearing the
  // reverse bearing and looking like a separate disagreement.
  const used = new Set<string>();
  const queue = starts.map(([r]) => r);
  while (queue.length) {
    const id = queue.shift()!;
    const boxId = pair.get(id)!;
    const mine = byId.get(id)!.exits, theirs = drawingExits(d, boxId);
    for (const dir of Object.keys(mine)) {
      const to = mine[dir];
      if (to == null) continue;
      let beyond = theirs[dir];
      if (!beyond && byId.has(to)) {
        // Not drawn in that exact direction. Try 45 degrees either side, and take
        // it only if exactly one of those is a box nothing else has claimed.
        const sides = eitherSide(dir).filter(x => theirs[x] && !taken.has(theirs[x]));
        if (sides.length === 1) {
          beyond = theirs[sides[0]];
          skewed.push(`${byId.get(id)!.slug} ${dir} is drawn ${sides[0]}`);
        }
      }
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
      used.add(`${boxId}|${beyond}`); used.add(`${beyond}|${boxId}`);
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
    if (used.has(k)) continue;   // we walked this connector, exact or skewed
    const room = byId.get(ours);
    if (!room || dir in room.exits) continue;
    let far: number | undefined;
    for (const [roomId, boxId] of pair) if (boxId === to) { far = roomId; break; }
    const where = far != null ? byId.get(far)?.slug ?? `#${far}` : 'a box we have not walked';
    drawn.push(`${room.slug} is drawn with ${dir} to ${where}`
      + `, but the game gives it ${Object.keys(room.exits).sort().join(',')}`);
  }
  return { pair, problems, leaves, drawn, skewed };
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
// The swamp's page draws the ruined town in its bottom-left corner. The town
// has all 20 boxes in here; the Warlock's column, the temple's key text beside
// it and the swamp's [a] with its "Ruined Town" caption (row 48) are outside.
const RUINED_TOWN_ON_SWAMP_PAGE = { rows: [49, 61] as [number, number], cols: [0, 41] as [number, number] };

export const SHRINE_MAPS: Record<string,
  { file: string; originBox: string; originRoom: string;
    // More ways in, each anchored the same way. See pairRooms' moreStarts.
    moreOrigins?: { box: string; room: string }[];
    // Only part of the page is this area's. See Region.
    region?: Region }> = {

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
  'stoneworks-level-3': {
    file: 'map/shrine/stoneworks-3.txt',
    originBox: '^',                      // the stairs back up to Level 2
    originRoom: 'stonework-chamber-11',
  },
  'stoneworks-level-4': {
    file: 'map/shrine/stoneworks-4.txt',
    originBox: '^',                      // the stairs back up to Level 3
    originRoom: 'stonework-chamber-15',
  },
  'stoneworks-level-5': {
    file: 'map/shrine/stoneworks-5.txt',
    originBox: '^',                      // the stairs back up to Level 4
    originRoom: 'stonework-chamber-19',
  },
  // The last level. Its bottom row runs west through two Seals (the chasms) to
  // the [*] beside "Town 3", stonework-corridor-237, whose w is third town's
  // town-square -- the one exit that leaves the level besides the stairs.
  'stoneworks-level-6': {
    file: 'map/shrine/stoneworks-6.txt',
    originBox: '^',                      // the stairs back up to Level 5
    originRoom: 'stonework-chamber-22',
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
  // Named level-1 to match sewers-level-1 and stoneworks-level-2, and to keep the
  // AREA slug clearly apart from the DRAWING slugs in scrape.ts, which are
  // complex-caverns-1..4 and are pages of the shrine rather than areas of ours.
  'complex-caverns-level-1': {
    file: 'map/shrine/complex-caverns-1.txt',
    originBox: '^',                      // up to the Valley
    originRoom: 'complex-of-natural-caverns',
  },
  // South-west of the first town. The shrine labels no box on the walked side of
  // this page, so the drawing carries a [g] we added (see its header): the box
  // beside "Town 1", which is town-gates -- the room the July walk could not read
  // the name of, and so skipped, until it was walked on 2026-09-22.
  mountains: {
    file: 'map/shrine/mountains.txt',
    originBox: 'g',
    originRoom: 'town-gates',
  },
  // North off the mountains. Both pages draw the room between them: the mountains
  // as "[*] to Orc Caves", this page as its bottom box over "to Mountains". It is
  // filed here, the way the desert's [S] is filed under the stoneworks, so each
  // page reads the other side as the area ending. The bottom box carries a [*] we
  // added (see the drawing's header).
  // West off the mountains' caves. The page labels only encounters, so the
  // drawing carries an [m] we added (see its header) on the box whose east arrow
  // is "Mountains -->": the room we call `forest`.
  forest: {
    file: 'map/shrine/forest.txt',
    originBox: 'm',
    originRoom: 'forest',
  },
  // East off the forest, by two ways in, both labelled on the drawing (see its
  // header). [a] is the room we call `swamp`, off forest-27, walked in July;
  // [b] is swamp-30, off forest-39, walked 2026-09-22 -- anchored separately
  // because until a walk joins the two branches, nothing leads from one to the
  // other. The ruined town is drawn on this page too, but is its own area.
  swamp: {
    file: 'map/shrine/swamp.txt',
    originBox: 'a',
    originRoom: 'swamp',
    moreOrigins: [{ box: 'b', room: 'swamp-30' }],
    region: { ...RUINED_TOWN_ON_SWAMP_PAGE, keep: 'outside' },
  },
  // Up the swamp's north-east trail, drawn at the bottom of the swamp's page and
  // filed as its own area. The shrine labels the temple [Tv] -- T for the Ancient
  // Temple, v for its way down to the cellars -- so it anchors without an edit.
  'ruined-town': {
    file: 'map/shrine/swamp.txt',
    originBox: 'Tv',
    originRoom: 'ancient-temple',
    region: { ...RUINED_TOWN_ON_SWAMP_PAGE, keep: 'inside' },
  },
  // South off the forest, from forest-63. The way in is the page's [H] under "to
  // Forest" (H for the Hyenas), which is forest-64: n to the forest, w into the
  // caves. The page has a second [H] further down, but boxes are found top to
  // bottom, so 'H' is this one without editing the drawing.
  'gnoll-caves': {
    file: 'map/shrine/gnoll-caves.txt',
    originBox: 'H',
    originRoom: 'forest-64',
  },
  // South off the forest (forest-87). The shrine draws the tower's four levels on
  // one page, joined only by labelled stairs, and this is Level 1 -- the
  // top-left quarter, which holds exactly its 18 boxes. The entrance under "To
  // Forest" carries an [e] we added (see the drawing's header). The other levels,
  // walked as their own areas, would each take their own quarter the same way.
  'tower-level-1': {
    file: 'map/shrine/tower.txt',
    originBox: 'e',
    originRoom: 'entrance-hall',
    region: { rows: [0, 19], cols: [0, 29], keep: 'inside' },
  },
  // Up Level 1's east stairs (marble-hallway-11). The page's top-right quarter,
  // anchored on its [v]. The area also holds the landing the west stairs pass
  // through on the way to Level 3, which no page draws -- the shrine shows a
  // stack of stair rooms as one [^] -- so one room here is never placed.
  'tower-level-2': {
    file: 'map/shrine/tower.txt',
    originBox: 'v',
    originRoom: 'marble-hallway-42',
    region: { rows: [0, 19], cols: [30, 99], keep: 'inside' },
  },
  // Up two flights from Level 1's west stairs, and up one more from here. The
  // page's bottom-left quarter is Level 3 and its bottom-right is Level 4; each
  // anchors on its own [v], the stairs it is reached by.
  'tower-level-3': {
    file: 'map/shrine/tower.txt',
    originBox: 'v',
    originRoom: 'marble-hallway-14',
    region: { rows: [20, 99], cols: [0, 29], keep: 'inside' },
  },
  'tower-level-4': {
    file: 'map/shrine/tower.txt',
    originBox: 'v',
    originRoom: 'marble-hallway-28',
    region: { rows: [20, 99], cols: [30, 99], keep: 'inside' },
  },
  // Reached from the tower's Level 4: west from marble-hallway-41 into the [L]
  // box, where "a cloud of thick black smoke" carries you here -- a teleport, so
  // no exit joins the two. The page labels where you land [E], "Entrance Point".
  'labyrinth-level-1': {
    file: 'map/shrine/labyrinth-1.txt',
    originBox: 'E',
    originRoom: 'labyrinth',
  },
  // Two levels down from Level 1. Level 2 is dark until a Device is worked, so
  // it is walked blind for now and Level 3 is mapped on its own, joined up later.
  // The walk comes down the stairs into the page's [^], "Stairs Up to Level 2".
  // Dark until the stone on Level 5 is pushed; walked lit on 2026-09-26. Anchored
  // on the page's [v], "Stairs Down to Level 3": labyrinth-318, exits s,d, whose
  // d is Level 3's labyrinth-100.
  'labyrinth-level-2': {
    file: 'map/shrine/labyrinth-2.txt',
    originBox: 'v',
    originRoom: 'labyrinth-318',
  },
  'labyrinth-level-3': {
    file: 'map/shrine/labyrinth-3.txt',
    originBox: '^',
    originRoom: 'labyrinth-100',
  },
  // Lit by the stone on Level 2. Two anchors, because the two stairs rooms were
  // walked before anything joined them: [^] (labyrinth-198, up to Level 3) and
  // [v] (labyrinth-236, down to Level 5). The rooms minted here in the dark were
  // junk and are gone (2026-09-26).
  'labyrinth-level-4': {
    file: 'map/shrine/labyrinth-4.txt',
    originBox: '^',
    originRoom: 'labyrinth-198',
    moreOrigins: [{ box: 'v', room: 'labyrinth-236' }],
  },
  // The bottom of the labyrinth, reached down the stairs from Level 4 -- which is
  // dark, so it is not mapped and the two are not joined. Anchored on the page's
  // [^], "Stairs Up to Level 4": labyrinth-204, exits s,u,w.
  'labyrinth-level-5': {
    file: 'map/shrine/labyrinth-5.txt',
    originBox: '^',
    originRoom: 'labyrinth-204',
  },
  'orc-caves': {
    file: 'map/shrine/orc-caves.txt',
    originBox: '*',
    originRoom: 'cave-201',
  },
};

/**
 * Shrine pages that draw several of our areas, by the name you ask for the page
 * by: `just coverage tower` shows the whole tower page with every level's walked
 * boxes marked, then each level's own report. Every area listed must be
 * registered above on that page, with a region of its own.
 */
export const PAGES: Record<string, string[]> = {
  tower: ['tower-level-1', 'tower-level-2', 'tower-level-3', 'tower-level-4'],
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
  if (!spec && !(slug && PAGES[slug])) {
    console.error(`coverage: no shrine drawing registered for '${slug ?? ''}'.`);
    console.error(`  known: ${[...Object.keys(SHRINE), ...Object.keys(PAGES)].join(', ') || '(none)'}`);
    process.exit(1);
  }
  if (!existsSync('tele-arena.db')) {
    console.error('coverage: no tele-arena.db here.');
    process.exit(1);
  }
  // A plain read-write handle, never mode=ro: baud keeps the DB in WAL mode and a
  // read-only connection cannot attach the -wal file, so it returns stale data.
  const db = new Database('tele-arena.db');
  const areaId = (s: string) => (db.prepare('SELECT id FROM areas WHERE slug = ?').get(s) as any)?.id;

  // One area's report: its picture (unless the caller draws the page itself),
  // then what is left to walk and where it disagrees with the drawing. Returns
  // the lines and the boxes it walked, so a page can mark several areas at once.
  const report = async (slug: string, picture: boolean) => {
  const spec = SHRINE[slug];
  const out: string[] = [];
  const drawing = parseDrawing(await Bun.file(spec.file).text(), spec.region);
  const area = { id: areaId(slug) };
  if (!area.id) { console.error(`coverage: no area '${slug}'`); process.exit(1); }

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

  // The other ways in. One not walked yet is simply left out -- it will be
  // reached from the first, or anchored once it exists.
  const moreStarts: [number, string][] = [];
  for (const o of spec.moreOrigins ?? []) {
    const room = rooms.find(r => r.slug === o.room);
    const box = drawing.boxes.find(b => b.label === o.box);
    if (!box) { console.error(`coverage: no box '${o.box}' on ${spec.file}`); process.exit(1); }
    if (room) moreStarts.push([room.id, box.id]);
  }

  const { pair, problems, leaves, drawn, skewed } = pairRooms(
    drawing, rooms, start.id, startBox.id, teleports, moreStarts);
  const mapped = new Set(pair.values());

  // Both numbers, always. "6 of 97" on its own reads as "you have walked six
  // rooms", and on 2026-09-19 it said that about a level with 22 rooms walked --
  // the pairing had stalled, and every figure below it was scoped to the six it
  // had placed. How much is walked and how much the drawing can be matched to are
  // different questions and the header now asks both.
  const placed = [...pair.keys()].filter(id => roomById.has(id)).length;
  out.push(`\n${slug} — ${rooms.length} rooms walked; `
    + `${placed} of them placed on the drawing, which has ${drawing.boxes.length} boxes\n`);
  if (picture) {
    for (const line of renderCoverage(drawing, mapped)) out.push(line);
    out.push('\n  [#] walked    [.] not yet    [X1] landmark walked    (X1) landmark not yet\n');
  }

  // Frontiers, and what the drawing says is on the other side. The distinction
  // that matters: a stub whose far side is ALREADY a room of ours adds nothing by
  // being walked -- it closes a loop. Mistaking one for unexplored territory is
  // how a region looks unfinished when it is done.
  const boxToRoom = new Map<string, number>();
  for (const [rid, bid] of pair) boxToRoom.set(bid, rid);
  const closes: string[] = [], opens: string[] = [], offMap: string[] = [];
  // Frontiers in rooms the pairing could not place. These used to be dropped
  // entirely -- the loop skipped an unplaced room -- so a level with frontiers all
  // over it reported "no frontiers, nothing left to walk here". That is the
  // opposite of the truth and it is the line a walker acts on.
  const unplaced: string[] = [];
  for (const r of rooms) {
    const bid = pair.get(r.id);
    if (!bid) {
      for (const dir of Object.keys(r.exits)) {
        if (r.exits[dir] == null) unplaced.push(`${r.slug} ${dir}`);
      }
      continue;
    }
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
    out.push(`${title} (${items.length})`);
    for (const i of items) out.push(`  ${i}`);
    if (!items.length) out.push('  none');
  };
  say('frontiers into NEW rooms', opens);
  say('unwalked links between rooms we already have — walking one closes a loop', closes);
  say('unwalked exits the drawing does not show (a label, or off this map)', offMap);
  say('walked exits that leave the area — the drawing captions these', leaves);
  say('frontiers in rooms the drawing could not be matched to — still yours to walk', unplaced);
  say('exits followed 45° off what the drawing shows — its bearing, not its adjacency', skewed);
  say('lines the drawing has that we do not — the drawing is wrong, or we are', drawn);

  const unpaired = drawing.boxes.filter(b => !mapped.has(b.id));
  out.push(`\nboxes not yet ours (${unpaired.length})`);
  out.push('  ' + (unpaired.map(b => b.label ? `[${b.label}]` : `r${b.r}c${b.c0}`).join('  ') || 'none'));

  // "Not yet ours" reads as "rooms you have not walked", and that is only true
  // while there is somewhere left to walk. pairRooms is a BFS through OUR exits,
  // so a single direction it cannot follow -- a disagreement -- strands every box
  // behind it, walked or not. An area with no frontiers and unpaired boxes is
  // therefore describing a pairing failure, not missing rooms, and on the valley
  // it left six boxes listed that map.html was drawing all along. Say so, rather
  // than leave the reader to reconcile two lines that contradict each other.
  if (unpaired.length && !opens.length && !closes.length && !unplaced.length) {
    out.push(`\n  ^ but there is nothing left to walk here: no frontiers, and no`);
    out.push(`    unwalked link between rooms we have. The pairing stopped early`);
    out.push(problems.length
      ? `    at the ${problems.length === 1 ? 'disagreement' : 'disagreements'} below, so those boxes were never reached --`
      : `    without reaching those boxes --`);
    out.push(`    they may well be rooms you already have. map.html draws every`);
    out.push(`    room either way; this pairing is what cannot see them.`);
  }

  if (problems.length) {
    out.push(`\nDISAGREEMENTS WITH THE DRAWING (${problems.length})`);
    for (const p of problems) out.push('  ' + p);
  } else {
    out.push('\nno disagreements: every paired room has the exits the drawing gives its box');
  }
  out.push('');
  return { out, mapped };
  };

  if (PAGES[slug!]) {
    // The whole page, every level's walked boxes marked on it. Box ids are grid
    // positions, the same whichever region a level was parsed with, so marking
    // is a union. A level not walked yet has no area and is left out.
    const levels = PAGES[slug!].filter(l => areaId(l));
    const page = parseDrawing(await Bun.file(SHRINE[PAGES[slug!][0]].file).text());
    const reports = [];
    for (const l of levels) reports.push(await report(l, false));
    const marked = new Set(reports.flatMap(r => [...r.mapped]));
    console.log(`\n${slug} — ${levels.length} of ${PAGES[slug!].length} registered levels walked; `
      + `${[...marked].filter(b => page.boxes.some(x => x.id === b)).length} of the page's ${page.boxes.length} boxes marked\n`);
    for (const line of renderCoverage(page, marked)) console.log(line);
    console.log('\n  [#] walked    [.] not yet    [X1] landmark walked    (X1) landmark not yet');
    for (const r of reports) for (const line of r.out) console.log(line);
  } else {
    for (const line of (await report(slug!, true)).out) console.log(line);
  }
}
