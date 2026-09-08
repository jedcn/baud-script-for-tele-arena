// Check that a mapped area is sound: `just verify-area <slug>` (or no slug for
// every area). Written for the mapping sessions -- run it between levels so
// "are we on the same page" is one command rather than a conversation.
//
// The checks are the ones that have actually caught defects in this map:
// unwalked frontiers, one-directional exits, horizontal moves that change
// level, and rooms that exist but never get drawn.

export type Room = { id: number; slug: string; description: string | null };
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
      `SELECT r.id, r.slug, r.description FROM rooms r JOIN areas a ON a.id = r.area_id
       WHERE a.slug = ? ORDER BY r.id`).all(slug) as Room[];
    if (!rooms.length) { console.log(`\n${slug}: no rooms\n`); continue; }
    const mine = new Set(rooms.map(r => r.id));
    const exits = allExits.filter(e => mine.has(e.from_id));

    const findings = [
      frontiers(rooms, exits),
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
  console.log(failed === 0 ? '\nAll checks passed.\n' : `\n${failed} check(s) failed.\n`);
  process.exit(failed === 0 ? 0 : 1);
}
