// Show where a room sits on the shrine drawing: `just where cave-30`.
//
// In game, `map-print-room-slug` names the room you are standing in. This takes
// that name and marks it on the map, because a slug tells you nothing about
// where you are and the drawing is what a person actually reads.
//
//   [@] you are here          [?] a box the reconciliation never reached
//   [!] a disagreement        [>] where a disagreement says you could go
//
import { parseMap } from './parse';
import { reconcile, ANCHORS, type OurRoom } from './reconcile';
import { annotate } from './annotate';

/** Which shrine map covers an area, if any. */
export function mapForArea(area: string): { name: string; cfg: typeof ANCHORS[string] } | null {
  for (const [name, cfg] of Object.entries(ANCHORS)) if (cfg.area === area) return { name, cfg };
  return null;
}

if (import.meta.main) {
  const wanted = process.argv[2];
  if (!wanted) { console.error('usage: just where <room-slug>   (get the slug in game with `map-print-room-slug`)'); process.exit(1); }
  const { Database } = await import('bun:sqlite');
  const db = new Database('tele-arena.db');

  const row = db.prepare(
    `SELECT r.id, r.slug, r.name, a.slug AS area FROM rooms r
     JOIN areas a ON a.id = r.area_id WHERE r.slug = ?`).get(wanted) as any;
  if (!row) {
    // A near-miss is more useful than "not found" when slugs are hand-typed.
    const like = db.prepare('SELECT slug FROM rooms WHERE slug LIKE ? LIMIT 8').all(`%${wanted}%`) as any[];
    console.error(`no room called '${wanted}'` + (like.length ? `\n  did you mean: ${like.map(r => r.slug).join(', ')}` : ''));
    process.exit(1);
  }

  const found = mapForArea(row.area);
  console.log(`${row.slug}  ("${row.name}")  in ${row.area}`);
  const exits = db.prepare(
    `SELECT e.direction, COALESCE(r2.slug, '(unwalked)') dest FROM room_exits e
     LEFT JOIN rooms r2 ON r2.id = e.to_id WHERE e.from_id = ? ORDER BY e.direction`).all(row.id) as any[];
  console.log(`  exits: ${exits.map(e => `${e.direction} -> ${e.dest}`).join('   ')}`);

  if (!found) { console.log(`\n  no shrine map covers ${row.area} yet, so there is nothing to point at.`); process.exit(0); }

  const text = await Bun.file(`map/shrine/${found.cfg.map}.txt`).text();
  const shrine = parseMap(text);
  const rows = db.prepare(
    `SELECT r.id, r.slug FROM rooms r JOIN areas a ON a.id = r.area_id WHERE a.slug = ?`).all(row.area) as any[];
  const slugById = new Map(rows.map(r => [r.id, r.slug]));
  const ours: Record<string, OurRoom> = {};
  for (const r of rows) {
    const ex: Record<string, string | null> = {};
    for (const e of db.prepare('SELECT direction, to_id FROM room_exits WHERE from_id = ?').all(r.id) as any[])
      ex[e.direction] = e.to_id == null ? null : (slugById.get(e.to_id) ?? null);
    ours[r.slug] = { slug: r.slug, exits: ex };
  }
  const rep = reconcile(row.area, shrine, ours, found.cfg.anchor);

  const mine = rep.matched.find(([, slug]) => slug === wanted)?.[0]
            ?? rep.pits.find(([, slug]) => slug === wanted)?.[0];
  const mark = new Map<number, string>();
  for (const i of rep.unmatchedBoxes) mark.set(i, '?');
  for (const c of rep.conflicts) if (c.box >= 0) { for (const t of c.towards ?? []) mark.set(t, '>'); mark.set(c.box, '!'); }
  if (mine !== undefined) mark.set(mine, '@');

  console.log(`\n${found.name}   [@] you are here\n${'='.repeat(60)}`);
  console.log(annotate(text, mark));
  if (mine === undefined)
    console.log(`\n  This room is not placed on the drawing -- the reconciliation never reached it.`
              + `\n  Run \`just annotate ${found.name}\` to see where that walk stopped.`);
}
