// Draw a shrine map with the reconciliation marked on it, because a room slug
// says nothing about where a problem is.
//
//   [?] a box the walk never reached
//   [!] the room you would be standing in when the two sources disagree
//   [>] where the drawing says you can go from [!], and we say you cannot
//
// The [!] / [>] split matters: the room with the problem and the room in
// dispute are different rooms, and conflating them sends you to the wrong one.
//
import { parseMap } from './parse';
import { reconcile, ANCHORS, type OurRoom } from './reconcile';

/** Disagreements already settled in game, so they read as decided, not open. */
export type Checked = { area: string; room: string; direction: string; verdict: string; when: string };
export function findChecked(checked: Checked[], area: string, room: string, message: string): Checked | undefined {
  return checked.find(c => c.area === area && c.room === room && message.includes(c.direction));
}

export function annotate(text: string, mark: Map<number, string>): string {
  const p = parseMap(text);
  const lines = text.split('\n').filter(l => !l.startsWith('#')).map(l => l.split(''));
  for (const [index, ch] of mark) {
    const b = p.boxes[index];
    if (!b || !lines[b.row]) continue;
    // Overwrite the box's interior, keeping the brackets so the drawing still
    // reads as a map.
    for (let c = b.start + 1; c < b.end; c++) lines[b.row][c] = ' ';
    lines[b.row][b.start + 1] = ch;
  }
  return lines.map(l => l.join('').replace(/\s+$/, '')).join('\n');
}

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const db = new Database('tele-arena.db');
  const only = process.argv[2];
  const checked: Checked[] = JSON.parse(await Bun.file('map/checked.json').text()).checked;
  for (const [name, cfg] of Object.entries(ANCHORS)) {
    if (only && name !== only) continue;
    const shrineText = await Bun.file(`map/shrine/${cfg.map}.txt`).text();
    const shrine = parseMap(shrineText);
    const rows = db.prepare(
      `SELECT r.id, r.slug FROM rooms r JOIN areas a ON a.id=r.area_id WHERE a.slug=?`).all(cfg.area) as any[];
    const slugById = new Map(rows.map(r => [r.id, r.slug]));
    const ours: Record<string, OurRoom> = {};
    for (const r of rows) {
      const exits: Record<string, string | null> = {};
      for (const e of db.prepare('SELECT direction,to_id FROM room_exits WHERE from_id=?').all(r.id) as any[])
        exits[e.direction] = e.to_id == null ? null : (slugById.get(e.to_id) ?? null);
      ours[r.slug] = { slug: r.slug, exits };
    }
    const rep = reconcile(cfg.area, shrine, ours, cfg.anchor);
    if (!rep.unmatchedBoxes.length && !rep.conflicts.length) continue;
    const mark = new Map<number, string>();
    for (const i of rep.unmatchedBoxes) mark.set(i, '?');
    // A disputed room is almost always also unreached, so `>` must win over `?`
    // -- otherwise the one box a reader most needs to find looks like the
    // thirty around it.
    for (const c of rep.conflicts) if (c.box >= 0) {
      for (const t of c.towards ?? []) mark.set(t, '>');
      mark.set(c.box, '!');
    }
    console.log(`\n${'='.repeat(66)}\n${name}  —  ${rep.matched.length}/${shrine.boxes.length} matched`
      + `   [?] unreached ${rep.unmatchedBoxes.length}   [!] disagreement\n${'='.repeat(66)}`);
    console.log(annotate(shrineText, mark));
    const seen = new Set<string>();
    for (const c of rep.conflicts) {
      const k = `${c.box}|${c.message}`; if (seen.has(k)) continue; seen.add(k);
      const settled = findChecked(checked, rep.area, c.room, c.message);
      console.log(`  [!] ${c.room}: ${c.message}`
        + (settled ? `\n      SETTLED ${settled.when}: ${settled.verdict} — checked in game` : ''));
    }
  }
}
