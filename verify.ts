// Check that a mapped area is sound: `just verify-area <slug>` (or no slug for
// every area). Written for the mapping sessions -- run it between levels so
// "are we on the same page" is one command rather than a conversation.
//
// The checks are the ones that have actually caught defects in this map:
// unwalked frontiers, one-directional exits, horizontal moves that change
// level, and rooms that exist but never get drawn.

export type Room = { id: number; slug: string; description: string | null;
                     x?: number | null; y?: number | null };
export type Exit = { from_id: number; direction: string; to_id: number | null };
export type Finding = { check: string; ok: boolean; detail: string };

const REVERSE: Record<string, string> = {
  n: 's', s: 'n', e: 'w', w: 'e', ne: 'sw', sw: 'ne', nw: 'se', se: 'nw',
  u: 'd', d: 'u', passage: 'passage',
};
const DZ: Record<string, number> = { u: 1, d: -1 };

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
  const { existsSync } = await import('node:fs');
  const { renderArea } = await import('./map');

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
