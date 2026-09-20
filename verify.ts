// Check that a mapped area is sound: `just verify-area <slug>` (or no slug for
// every area). Written for the mapping sessions -- run it between levels so
// "are we on the same page" is one command rather than a conversation.
//
// The checks are the ones that have actually caught defects in this map:
// unwalked frontiers, one-directional exits, horizontal moves that change
// level, and rooms that exist but never get drawn.

import { placeRooms, skewedEdges } from './map';
import { clean } from './log';

export type Room = { id: number; slug: string; description: string | null;
                     x?: number | null; y?: number | null };
export type Exit = { from_id: number; direction: string; to_id: number | null };
export type Finding = { check: string; ok: boolean; detail: string };

const REVERSE: Record<string, string> = {
  n: 's', s: 'n', e: 'w', w: 'e', ne: 'sw', sw: 'ne', nw: 'se', se: 'nw',
  u: 'd', d: 'u', passage: 'passage',
};
const DZ: Record<string, number> = { u: 1, d: -1 };

/**
 * What the GAME said a room's exits were, read back out of the session logs.
 *
 * Every other check in this file reads the map against itself -- reciprocity,
 * frontiers, depth, whether it can be drawn -- and a map can be wrong in a way
 * that is perfectly self-consistent. A conflation is exactly that: two real rooms
 * recorded as one. Every test here passed on the Complex of Natural Caverns while
 * `-87` and `-90` were each standing in for more than one room, because the map
 * agreed with itself about a shape the cave does not have.
 *
 * The evidence that catches it has been in every log all along. Each time the
 * mapper probes a room it prints the id it believes it is in, right after the
 * game's own `Exits:` reply:
 *
 *     Exits: ne,se,nw.
 *     [mapdbg] Exits trigger: mapping=true currentRoomId=1885 (number)
 *
 * Only `mapping=true` counts. With mapping off `currentRoomId` is whatever the
 * last session left behind and means nothing.
 */
export type Observation = { roomId: number; exits: string[]; file: string; line: number };

export function observedExits(text: string, file = ''): Observation[] {
  const out: Observation[] = [];
  let pending: { exits: string[]; line: number } | null = null;
  text.split('\n').forEach((raw, i) => {
    const line = raw.trim();
    const ex = /^Exits: ([a-z,]+)\.$/.exec(line);
    if (ex) { pending = { exits: ex[1].split(','), line: i + 1 }; return; }
    const trig = /Exits trigger: mapping=true currentRoomId=(\d+)/.exec(line);
    if (trig && pending) {
      out.push({ roomId: Number(trig[1]), exits: pending.exits, file, line: pending.line });
      pending = null;
    }
  });
  return out;
}

const setOf = (xs: string[]) => [...new Set(xs)].sort().join(',');

/**
 * When a session log was written, from its name, as the ISO instant the rooms
 * table stores. `session-pelayo-2026-09-19T15-01-29.log`.
 */
export function logInstant(file: string): string | null {
  const m = /(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})/.exec(file);
  return m ? `${m[1]}T${m[2]}:${m[3]}:${m[4]}` : null;
}

/**
 * Drop sightings from before the room existed. A room id in a log means whatever
 * the rooms table meant by it THAT DAY, and this map has been rebuilt under the
 * ids it uses now -- rooms_legacy is still sitting beside it. Unfiltered, twelve
 * of first-town's thirteen rooms "changed shape", all on the strength of logs
 * from the day before those ids were minted.
 *
 * `first_visited` makes the cut exact rather than a guessed cutoff date.
 */
export function afterRoomExisted(
  obs: Observation[], firstVisited: Map<number, string>,
): Observation[] {
  return obs.filter(o => {
    const born = firstVisited.get(o.roomId);
    const when = logInstant(o.file);
    return born != null && when != null && when >= born;
  });
}

// `Exits:` lists compass and vertical moves and nothing else. A `passage` edge is
// how the map records a way through that the game does not name that way -- it can
// never appear in an `ex` reply, so comparing it against one always "finds" a
// phantom. Same for any future non-compass edge.
const COMPASS_EXITS = new Set(['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw', 'u', 'd']);

/**
 * Sightings from after the map last agreed with the game about a room.
 *
 * A conflation stays reported forever otherwise, and a check that always fails is
 * one you stop reading -- the same way a warning that cries wolf is one you learn
 * to walk past. #1882 was seen as {ne,nw,se} and as {nw,se} across two sessions
 * on 2026-09-19 while the map had a wrong edge; the edge was repaired and a clean
 * walk read it as {ne,nw,se} twice, and the old shapes went on failing regardless.
 *
 * So: find the newest sighting of a room whose exit-set matches the map, and drop
 * everything from logs older than that one. If the map is right now, the earlier
 * disagreements were about a map that no longer exists. If it is still wrong,
 * nothing agrees, nothing is dropped, and every shape is still reported.
 *
 * The cut is by FILE, not by line, so a session that drifted MID-WALK survives
 * whole if it is also the session that last agreed -- both shapes are kept and
 * the check still fails. A later clean walk does retire an older session's drift,
 * and that is the point: the drift was caused by the map that has since been
 * repaired, and walking the corner correctly is the evidence of the repair.
 */
export function sinceTheMapLastAgreed(obs: Observation[], exits: Exit[]): Observation[] {
  const have = new Map<number, string>();
  for (const e of exits) {
    if (!COMPASS_EXITS.has(e.direction)) continue;
    have.set(e.from_id, have.has(e.from_id) ? `${have.get(e.from_id)},${e.direction}` : e.direction);
  }
  const mapShape = new Map([...have].map(([id, ds]) => [id, setOf(ds.split(','))]));
  const agreedAt = new Map<number, string>();
  for (const o of obs) {
    if (mapShape.get(o.roomId) !== setOf(o.exits)) continue;
    const prev = agreedAt.get(o.roomId);
    if (prev == null || o.file > prev) agreedAt.set(o.roomId, o.file);
  }
  return obs.filter(o => {
    const cut = agreedAt.get(o.roomId);
    return cut == null || o.file >= cut;
  });
}

/**
 * One room id, seen by the game with two different exit-sets. Exits do not change,
 * so this is the map claiming one room where the cave has two -- and it needs no
 * database at all to say so, which is why it is the first thing reported.
 */
export function oneRoomTwoShapes(obs: Observation[]): Finding {
  const byRoom = new Map<number, Map<string, Observation>>();
  for (const o of obs) {
    if (!byRoom.has(o.roomId)) byRoom.set(o.roomId, new Map());
    byRoom.get(o.roomId)!.set(setOf(o.exits), o);
  }
  const bad = [...byRoom].filter(([, shapes]) => shapes.size > 1);
  return {
    check: 'each room has one shape',
    ok: bad.length === 0,
    detail: bad.length === 0
      ? `${byRoom.size} rooms probed, none seen with two different exit-sets`
      : bad.map(([id, shapes]) => `#${id} seen as ` +
          [...shapes].map(([k, o]) => `{${k}} (${o.file}:${o.line})`).join(' and ')).join('\n')
        + '\n  (a shape seen only in an old log may describe a map since repaired;'
        + ' the file names are dated)',
  };
}

/**
 * The map against the game, room by room. An exit the map has that the game never
 * listed is a phantom -- usually the reciprocal of a move recorded into a room the
 * mapper was not actually standing in. The other direction, an exit the game lists
 * that the map lacks, means a frontier was dropped.
 */
export function exitsMatchTheGame(exits: Exit[], obs: Observation[]): Finding {
  const have = new Map<number, Set<string>>();
  for (const e of exits) {
    if (!COMPASS_EXITS.has(e.direction)) continue;
    if (!have.has(e.from_id)) have.set(e.from_id, new Set());
    have.get(e.from_id)!.add(e.direction);
  }
  // The LATEST sighting of each room, not the first. Log names are timestamps, so
  // they sort chronologically. An old disagreement may describe a map that has
  // since been repaired; the question worth asking is whether the map still
  // disagrees with the last thing the game said.
  const latest = new Map<number, Observation>();
  for (const o of [...obs].sort((a, b) => a.file.localeCompare(b.file))) latest.set(o.roomId, o);
  const problems: string[] = [];
  const seen = new Set<number>();
  for (const o of latest.values()) {
    if (!have.has(o.roomId)) continue;
    seen.add(o.roomId);
    const mine = have.get(o.roomId)!, theirs = new Set(o.exits);
    const phantom = [...mine].filter(d => !theirs.has(d)).sort();
    const missing = [...theirs].filter(d => !mine.has(d)).sort();
    if (phantom.length || missing.length) {
      problems.push(`#${o.roomId}: game said {${setOf(o.exits)}}, map has {${[...mine].sort().join(',')}}`
        + (phantom.length ? ` -- ${phantom.join(',')} is in no Exits: line` : '')
        + (missing.length ? ` -- ${missing.join(',')} never recorded` : ''));
    }
  }
  return {
    check: "the map's exits are the game's exits",
    ok: problems.length === 0,
    detail: problems.length === 0
      ? `${seen.size} rooms checked against the last \`ex\` reply each gave`
      : problems.join('\n'),
  };
}

/** Exits the game listed that nobody has stepped through yet. */
export function frontiers(rooms: Room[], exits: Exit[]): Finding {
  const mine = new Set(rooms.map(r => r.id));
  const open = exits.filter(e => mine.has(e.from_id) && e.to_id == null);
  const by = new Map(rooms.map(r => [r.id, r.slug]));
  return {
    check: 'no unwalked exits',
    ok: open.length === 0,
    detail: open.length === 0 ? 'every listed exit has been walked'
      : `${open.length} unwalked: ` + open.map(e => `${by.get(e.from_id)} ${e.direction}`).join(', '),
  };
}

/** A --dir--> B must imply B --reverse--> A. A one-way edge is a mis-link. */
export function reciprocity(rooms: Room[], exits: Exit[], allExits: Exit[]): Finding {
  const mine = new Set(rooms.map(r => r.id));
  const have = new Set(allExits.filter(e => e.to_id != null)
    .map(e => `${e.from_id}|${e.direction}|${e.to_id}`));
  const by = new Map(rooms.map(r => [r.id, r.slug]));
  const bad = exits.filter(e => {
    if (e.to_id == null || !mine.has(e.from_id)) return false;
    const rev = REVERSE[e.direction];
    return rev != null && !have.has(`${e.to_id}|${rev}|${e.from_id}`);
  });
  return {
    check: 'every exit is reciprocal',
    ok: bad.length === 0,
    detail: bad.length === 0 ? 'all edges have their reverse'
      : `${bad.length} one-directional: ` + bad.map(e => `${by.get(e.from_id)} ${e.direction}`).join(', '),
  };
}

/** Depth from an anchor room, counting only u/d. Every other move is level. */
export function depths(exits: Exit[], anchor: number): Map<number, number> {
  const adj = new Map<number, [string, number][]>();
  for (const e of exits) {
    if (e.to_id == null) continue;
    if (!adj.has(e.from_id)) adj.set(e.from_id, []);
    adj.get(e.from_id)!.push([e.direction, e.to_id]);
  }
  const z = new Map([[anchor, 0]]);
  const queue = [anchor];
  while (queue.length) {
    const cur = queue.shift()!;
    for (const [dir, next] of adj.get(cur) ?? []) {
      if (z.has(next)) continue;
      z.set(next, z.get(cur)! + (DZ[dir] ?? 0));
      queue.push(next);
    }
  }
  return z;
}

/**
 * A compass move cannot change your depth. An edge that says otherwise is
 * impossible, and is how teleports recorded as ordinary exits give themselves
 * away -- three such edges in the stoneworks glued several levels into one.
 */
export function levelConsistency(rooms: Room[], allExits: Exit[], z: Map<number, number>): Finding {
  const mine = new Set(rooms.map(r => r.id));
  const by = new Map(rooms.map(r => [r.id, r.slug]));
  const bad: string[] = [];
  for (const e of allExits) {
    if (e.to_id == null || !mine.has(e.from_id)) continue;
    const a = z.get(e.from_id), b = z.get(e.to_id);
    if (a == null || b == null) continue;
    if (b - a !== (DZ[e.direction] ?? 0))
      bad.push(`${by.get(e.from_id)} ${e.direction} (z ${a} -> ${b})`);
  }
  return {
    check: 'no move crosses a level impossibly',
    ok: bad.length === 0,
    detail: bad.length === 0 ? 'depth is consistent along every edge'
      : `${bad.length} impossible: ` + bad.join(', '),
  };
}

const OFFSET: Record<string, [number, number]> = {
  n: [0, 1], s: [0, -1], e: [1, 0], w: [-1, 0],
  ne: [1, 1], nw: [-1, 1], se: [1, -1], sw: [-1, -1],
};

/**
 * Walking one step must move you one cell in that direction. An edge whose
 * stored x/y disagree means the two rooms were dead-reckoned from different
 * anchors -- typically two mapping sessions -- and that breaks loop closure:
 * findRoomByFingerprint matches on an exact coordinate, so it silently stops
 * recognising rooms and mints duplicates instead.
 *
 * This is the check that was missing when the desert passed clean while
 * carrying eight such edges, and then duplicated six rooms on the first loop.
 */
export function coordinates(rooms: Room[], allExits: Exit[],
                            at: Map<number, { x: number; y: number } | null>): Finding {
  const mine = new Set(rooms.map(r => r.id));
  const by = new Map(rooms.map(r => [r.id, r.slug]));
  const bad: string[] = [];
  for (const e of allExits) {
    if (e.to_id == null || !mine.has(e.from_id) || !mine.has(e.to_id)) continue;
    const off = OFFSET[e.direction];
    const a = at.get(e.from_id), b = at.get(e.to_id);
    if (!off || !a || !b) continue;
    if (a.x + off[0] !== b.x || a.y + off[1] !== b.y)
      bad.push(`${by.get(e.from_id)} ${e.direction} ${by.get(e.to_id)}`);
  }
  return {
    check: 'coordinates agree with the moves',
    ok: bad.length === 0,
    detail: bad.length === 0 ? 'every edge lands where its direction says'
      : `${bad.length} disagree (loop closure will mint duplicates here): ` + bad.join(', '),
  };
}

/**
 * Whether the drawings point their lines the way the game says.
 *
 * Both renderers place rooms by dead reckoning and then draw each connector
 * from the GEOMETRY of where the two ends landed, never from the exit's own
 * direction. So a line can point somewhere the exit does not go, and until this
 * check existed nothing anywhere said so -- `deep-forest-149 --sw-->
 * deep-forest-150` was drawn pointing due north, and only a reader who knew the
 * area noticed.
 *
 * Two causes, and only one of them is a defect:
 *
 *   - INHERENT. The loop that edge closes does not close: walk it the long way
 *     round and you arrive somewhere else. No grid can honour every edge then,
 *     because the shape being asked for does not exist in two dimensions. This
 *     is the world being non-Euclidean, which CLAUDE.md notes is by design, so
 *     it is reported and not failed. `site.ts` marks these lines on the page.
 *   - LAYOUT. The edge was perfectly representable and the layout broke it
 *     anyway, by nudging one end aside when a collision put two rooms on one
 *     cell. That is a bug in `placeRooms`, so it fails.
 */
export function drawnDirections(
  rooms: Room[], exits: Exit[], origin: string,
): Finding {
  const mine = new Set(rooms.map(r => r.id));
  const by = new Map(rooms.map(r => [r.id, r.slug]));
  const grid = rooms.map(r => ({ id: r.id, slug: r.slug, name: '' }));
  const drawable = exits.filter(
    e => e.to_id != null && mine.has(e.to_id) && OFFSET[e.direction]);
  let skewed;
  try {
    const { pos } = placeRooms({ rooms: grid, exits, origin });
    skewed = skewedEdges(grid, exits, pos);
  } catch (e) {
    // Unplaceable rooms are the `every room can be drawn` check's business.
    return { check: 'lines point where the exits go', ok: true,
             detail: `not checked: ${(e as Error).message}` };
  }
  const say = (s: typeof skewed[number]) =>
    `${by.get(s.from_id)} ${s.direction} ${by.get(s.to_id)} (drawn ${s.drawn})`;
  const inherent = skewed.filter(s => s.inherent);
  const layout = skewed.filter(s => !s.inherent);
  const notes: string[] = [];
  if (layout.length) notes.push(
    `${layout.length} the layout moved off a cell the data agrees on: ` + layout.map(say).join(', '));
  if (inherent.length) notes.push(
    `${inherent.length} cannot be drawn right at all — the loop does not close: `
    + inherent.map(say).join(', '));
  return {
    check: 'lines point where the exits go',
    ok: layout.length === 0,
    detail: notes.length === 0
      ? `all ${drawable.length} compass exits within the area are drawn in`
        + ' their own direction'
      : notes.join('; '),
  };
}

/** Descriptions carry doors, levers and stones, so a missing one is a real gap. */
export function descriptions(rooms: Room[]): Finding {
  const missing = rooms.filter(r => !r.description);
  return {
    check: 'every room has a description',
    ok: missing.length === 0,
    detail: missing.length === 0 ? `all ${rooms.length} rooms described`
      : `${missing.length} missing: ` + missing.map(r => r.slug).join(', '),
  };
}

// A room's own description names its exits, in one of a few rigid forms, which
// makes the prose an independent check on the edges we recorded -- and the only
// check that catches CONFLATION, where two rooms were merged into one and the
// survivor ends up wearing both sets of exits. That is what the desert's 2026-09
// damage looks like: `desert` says "except to the south and northeast" and
// carries five edges.
//
// Only forms that have proved reliable are read. The chamber form ("The only
// visible exit is east") is deliberately absent: `stonework-chamber-1` has a real
// `n` exit hidden by mist, so "visible" is not the same claim.
const PROSE_WORD: Record<string, string> = {
  north: 'n', south: 's', east: 'e', west: 'w',
  northeast: 'ne', northwest: 'nw', southeast: 'se', southwest: 'sw',
};
const PROSE_FORMS = [
  /block travel in all directions except to (?:the )?([^.]+)\./,   // the desert
  // "The corridor runs to the north and southeast." Both verbs matter, and so
  // does each noun: the stoneworks say corridor, the desert's approach says
  // passage, the caves say tunnel, the wilderness says path or trail, and a
  // storage room says room.
  /(?:corridor|passage|tunnel|path|trail|room) (?:runs|continues) to the ([^.]+)\./,
];

// A way out that is a LANDMARK gets a sentence of its own, outside the list of
// directions: "Huge black outcroppings of rock block travel in all directions
// except to the east and southwest. The entrance to a crude circular stone
// building lies to the north." -- and `ex` answers n,e,sw. Read only when one of
// the forms above already matched, because plenty of rooms mention a direction
// without meaning an exit ("A small lever is partially concealed in a niche in
// the north wall", "The shop keeper sits behind a counter along the south wall").
const PROSE_ALSO = /\b(?:lies to the|leads? [^.]*?\bto the) ([a-z]+)/g;

/** The directions a description names, or null where it uses no form we trust. */
export function proseDirections(description: string | null): string[] | null {
  if (!description) return null;
  for (const re of PROSE_FORMS) {
    const m = description.match(re);
    if (!m) continue;
    const dirs = new Set((m[1].match(/[a-z]+/g) ?? [])
      .map(w => PROSE_WORD[w]).filter(Boolean) as string[]);
    for (const also of description.matchAll(PROSE_ALSO)) {
      const dir = PROSE_WORD[also[1]];
      if (dir) dirs.add(dir);
    }
    if (dirs.size) return [...dirs].sort();
  }
  return null;
}

/**
 * Rooms whose prose really does omit a real exit, with the reason. Each one is a
 * doorway you arrive through rather than a way the room describes leaving, so the
 * game's wording is right and so are our edges.
 */
export const PROSE_EXCEPTIONS: Record<string, string> = {
  'stonework-corridor-175': 'third town\'s doorway: entered from the town square'
    + ' to the west, which the corridor does not count among its exits',
};

/**
 * Every exit a room has, against every exit its description names. Stairs are
 * excluded: `u`/`d` get a sentence of their own ("There is a stone staircase here
 * leading downward") and never appear in the list of directions.
 */
export function proseAgreement(rooms: Room[], exits: Exit[]): Finding {
  const byRoom = new Map<number, string[]>();
  for (const e of exits) {
    if (e.direction === 'u' || e.direction === 'd') continue;
    if (!byRoom.has(e.from_id)) byRoom.set(e.from_id, []);
    byRoom.get(e.from_id)!.push(e.direction);
  }
  let checked = 0;
  const bad: string[] = [];
  for (const r of rooms) {
    const said = proseDirections(r.description);
    if (!said) continue;
    checked++;
    if (PROSE_EXCEPTIONS[r.slug]) continue;
    const got = (byRoom.get(r.id) ?? []).sort();
    if (said.join(',') !== got.join(',')) {
      bad.push(`${r.slug} (prose says ${said.join(',') || 'none'}, edges say ${got.join(',') || 'none'})`);
    }
  }
  return {
    check: 'no room contradicts its own description',
    ok: bad.length === 0,
    detail: bad.length === 0
      ? `${checked} of ${rooms.length} rooms name their exits in prose, and all agree`
      : `${bad.length} of ${checked} disagree: ` + bad.join(', '),
  };
}

/**
 * `navigate-to` addresses rooms as "<area>/<room>" strings inside ta_nav.lua,
 * which nothing type-checks. Renaming an area silently breaks every route that
 * named it, and the break only shows up when someone tries to walk it -- which
 * is how splitting `sewers` into three levels stranded the whole town-3 chain.
 *
 * `resolve` mirrors the real resolver in ta_db.roomsInAreaMatching: an exact
 * slug match wins, else rooms whose NAME slugifies to the reference.
 */
export function routeReferences(
  src: string,
  resolve: (area: string, ref: string) => { areaExists: boolean; matches: number },
): Finding {
  const bad: string[] = [];
  const re = /\b(?:from|to)\s*=\s*"([a-z0-9-]+)\/([a-z0-9-]+)"/g;
  let m: RegExpExecArray | null;
  let seen = 0;
  while ((m = re.exec(src)) !== null) {
    seen++;
    const [, area, ref] = m;
    const { areaExists, matches } = resolve(area, ref);
    if (!areaExists) bad.push(`${area}/${ref} (no such area)`);
    else if (matches !== 1) bad.push(`${area}/${ref} (${matches} matches)`);
  }
  return {
    check: 'every navigate-to route reference resolves',
    ok: bad.length === 0,
    detail: bad.length === 0 ? `all ${seen} area/room references resolve`
      : `${bad.length} broken: ` + [...new Set(bad)].join(', '),
  };
}

/**
 * An exit whose from_id names a room that no longer exists. The mapper holds
 * currentRoomId in memory, so deleting rooms underneath a live session lets it
 * write exits back for a room that is already gone -- which is how two rows
 * survived the desert delete, seeded by an `ex` run seconds afterwards.
 *
 * Checked globally rather than per area, since an orphan has no area to be in.
 */
export function orphanExits(roomIds: Set<number>, allExits: Exit[]): Finding {
  const bad = allExits.filter(e => !roomIds.has(e.from_id));
  const dangling = allExits.filter(e => e.to_id != null && !roomIds.has(e.to_id));
  const total = bad.length + dangling.length;
  return {
    check: 'no exit references a room that is gone',
    ok: total === 0,
    detail: total === 0 ? 'every exit is anchored at both ends'
      : `${bad.length} from a deleted room (${bad.map(e => `${e.from_id} ${e.direction}`).join(', ')})`
        + `, ${dangling.length} pointing at one`,
  };
}

export function report(findings: Finding[]): string {
  return findings.map(f => `  ${f.ok ? 'PASS' : 'FAIL'}  ${f.check}\n        ${f.detail}`).join('\n');
}

// --------------------------------------------------------------------------

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const { existsSync, readdirSync, readFileSync } = await import('node:fs');
  const { renderArea, DRAWN } = await import('./map');
  const drawnOrigin = (slug: string, rooms: Room[]) => {
    const want = DRAWN.find(d => d.slug === slug)?.origin;
    return want && rooms.some(r => r.slug === want) ? want : rooms[0].slug;
  };

  if (!existsSync('tele-arena.db')) {
    console.error('verify: no tele-arena.db here — nothing to check.');
    process.exit(1);
  }
  const db = new Database('tele-arena.db');
  const wanted = process.argv[2];
  const slugs = wanted
    ? [wanted]
    : (db.prepare('SELECT slug FROM areas ORDER BY slug').all() as any[]).map(r => r.slug);

  const allExits = db.prepare('SELECT from_id, direction, to_id FROM room_exits').all() as Exit[];
  const born = new Map<number, string>(
    (db.prepare('SELECT id, first_visited FROM rooms').all() as any[])
      .map(r => [r.id, r.first_visited]));

  // Every session log we still have, current and archived. These are the game's
  // own words about the rooms, and the only evidence in the project that does not
  // come from the map itself.
  const observations: Observation[] = [];
  for (const dir of ['logs', '../tele-arena-archived-session-logs']) {
    if (!existsSync(dir)) continue;
    for (const name of readdirSync(dir)) {
      if (!name.endsWith('.log')) continue;
      const path = `${dir}/${name}`;
      observations.push(...observedExits(clean(readFileSync(path, 'latin1')), name));
    }
  }
  const anchor = (db.prepare("SELECT id FROM rooms WHERE slug='north-plaza'").get() as any)?.id;
  const z = anchor == null ? new Map<number, number>() : depths(allExits, anchor);

  let failed = 0;
  for (const slug of slugs) {
    const rooms = db.prepare(
      `SELECT r.id, r.slug, r.description, r.x, r.y FROM rooms r JOIN areas a ON a.id = r.area_id
       WHERE a.slug = ? ORDER BY r.id`).all(slug) as Room[];
    if (!rooms.length) { console.log(`\n${slug}: no rooms\n`); continue; }
    const mine = new Set(rooms.map(r => r.id));
    const exits = allExits.filter(e => mine.has(e.from_id));

    const findings = [
      frontiers(rooms, exits),
      coordinates(rooms, allExits, new Map(rooms.map(r =>
        [r.id, r.x == null || r.y == null ? null : { x: r.x, y: r.y }]))),
      reciprocity(rooms, exits, allExits),
      levelConsistency(rooms, allExits, z),
      descriptions(rooms),
      proseAgreement(rooms, exits),
      // The same origin `site.ts` draws from, not just the lowest id: the origin
      // decides which path reaches a room FIRST, and first-come-wins is exactly
      // what produces the skew, so a different origin would report a different
      // set of bad lines than the page actually draws.
      drawnDirections(rooms, exits, drawnOrigin(slug, rooms)),
      // Against the game rather than against ourselves. Last, because when it
      // fails the checks above are all still passing and that is the point.
      oneRoomTwoShapes(sinceTheMapLastAgreed(
        afterRoomExisted(observations.filter(o => mine.has(o.roomId)), born), exits)),
      exitsMatchTheGame(exits, afterRoomExisted(observations.filter(o => mine.has(o.roomId)), born)),
    ];
    // The drawing is a check too: renderArea throws if a room cannot be placed
    // or if fewer boxes come out than rooms went in.
    try {
      renderArea({ rooms: rooms.map(r => ({ ...r, name: '' })) as any, exits, origin: rooms[0].slug });
      findings.push({ check: 'every room can be drawn', ok: true, detail: `${rooms.length} rooms placed and drawn` });
    } catch (e) {
      findings.push({ check: 'every room can be drawn', ok: false, detail: String((e as Error).message) });
    }
    const bad = findings.filter(f => !f.ok).length;
    failed += bad;
    console.log(`\n${slug}  (${rooms.length} rooms)  ${bad === 0 ? 'OK' : `${bad} PROBLEM(S)`}`);
    console.log(report(findings));
  }
  // Two global checks, run once rather than per area.
  {
    const ids = new Set((db.prepare('SELECT id FROM rooms').all() as any[]).map(r => r.id));
    const f = orphanExits(ids, allExits);
    if (!f.ok) failed++;
    console.log(`\nwhole map  ${f.ok ? 'OK' : 'PROBLEM'}`);
    console.log(report([f]));
  }

  // Route references are global rather than per-area, so they are checked once.
  if (existsSync('ta_nav.lua')) {
    const slugify = (n: string) => n.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const f = routeReferences(await Bun.file('ta_nav.lua').text(), (area, ref) => {
      const rows = db.prepare(
        `SELECT r.slug, r.name FROM rooms r JOIN areas a ON a.id = r.area_id WHERE a.slug = ?`)
        .all(area) as { slug: string; name: string }[];
      if (!rows.length) return { areaExists: false, matches: 0 };
      const bySlug = rows.filter(r => r.slug === ref);
      return { areaExists: true, matches: bySlug.length || rows.filter(r => slugify(r.name) === ref).length };
    });
    if (!f.ok) failed++;
    console.log(`\nnavigate-to routes  ${f.ok ? 'OK' : 'PROBLEM'}`);
    console.log(report([f]));
  }

  console.log(failed === 0 ? '\nAll checks passed.\n' : `\n${failed} check(s) failed.\n`);
  process.exit(failed === 0 ? 0 : 1);
}
