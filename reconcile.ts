// Align a shrine map against the rooms we walked, and report every place they
// disagree.
//
// The two sources are complementary: the drawing has the room set and the
// mechanics, the database has the names and descriptions. Neither can be
// trusted over the other, so this matches them and says where they differ
// rather than merging one into the other.
//
// Matching is a walk, not a guess. From one anchored pair, a shrine edge in
// direction `d` must land on the room reached by walking `d` in our map. That
// propagates identity along the graph without ever comparing appearances --
// which is the thing that cannot be done in this world.

import { parseMap, type ParsedMap } from './parse';

export type OurRoom = { slug: string; exits: Record<string, string | null> };
export type Report = {
  area: string;
  /** Pit rooms folded into a trap box; see `absorbPits`. */
  pits: [number, string][];
  /**
   * Matches where the drawing and our map disagree about how many ways out the
   * room has. A room is not the box it is matched to if their shapes differ, so
   * any of these means the alignment has drifted and everything downstream of
   * it is unreliable. This is the check that says whether a reconciliation can
   * be believed at all -- without it, a drifted alignment still produces
   * confident-looking conflicts.
   */
  shapeMismatches: { box: number; room: string; drawn: number; ours: number }[];
  matched: [number, string][];        // shrine box index -> our room slug
  unmatchedBoxes: number[];
  unmatchedRooms: string[];
  conflicts: { box: number; room: string; message: string; towards?: number[] }[];
};

/** Where to start: a shrine box we can name in our map with certainty. */
export type Anchor = { box: (m: ParsedMap) => number; room: string };

export function reconcile(area: string, shrine: ParsedMap,
                          ours: Record<string, OurRoom>, anchor: Anchor): Report {
  const boxToRoom = new Map<number, string>();
  const roomToBox = new Map<string, number>();
  const conflicts: { box: number; room: string; message: string; towards?: number[] }[] = [];

  const start = anchor.box(shrine);
  if (start < 0 || !ours[anchor.room])
    return { area, matched: [], unmatchedBoxes: shrine.boxes.map(b => b.index),
             unmatchedRooms: Object.keys(ours), pits: [], shapeMismatches: [],
             conflicts: [{ box: -1, room: anchor.room, message: `anchor not found` }] };

  const pair = (box: number, room: string) => { boxToRoom.set(box, room); roomToBox.set(room, box); };
  pair(start, anchor.room);

  // Shrine edges, indexed by the box they leave and the direction they leave in.
  const out = new Map<number, { dir: string; to: number; vertical: boolean }[]>();
  for (const e of shrine.edges) {
    const rev = (d: string) => d.split('').map(c => ({ n: 's', s: 'n', e: 'w', w: 'e' } as any)[c]).join('');
    (out.get(e.from) ?? out.set(e.from, []).get(e.from)!).push({ dir: e.dir, to: e.to, vertical: e.vertical });
    (out.get(e.to) ?? out.set(e.to, []).get(e.to)!).push({ dir: rev(e.dir), to: e.from, vertical: e.vertical });
  }

  const queue = [start];
  while (queue.length) {
    const box = queue.shift()!;
    const room = ours[boxToRoom.get(box)!];
    if (!room) continue;
    for (const edge of out.get(box) ?? []) {
      if (boxToRoom.has(edge.to)) continue;
      // Prefer the direction the drawing shows, and fall back to a stair only
      // where a stair is possible.
      //
      // A stair is drawn as an ordinary connector, so its drawn direction can
      // be meaningless -- town 1's vaults hang off the guild hall diagonally
      // and are really `d`. But the fallback must be GATED on a ^/v badge at
      // one end, or it fires wherever the drawing simply disagrees with us:
      // dungeon level 2's pit trap has a west exit in the drawing that our map
      // lacks, and an ungated fallback took `d` instead, walked into the pit,
      // dead-ended there and stranded 35 rooms behind it.
      //
      // The badges alone are not enough either -- they describe each room's own
      // stairs, not the link -- so they permit the fallback rather than decide
      // it, and the drawn direction is still tried first.
      const badged = /[\^v]/.test(shrine.boxes[box].badge) || /[\^v]/.test(shrine.boxes[edge.to].badge);
      const dirs = badged ? [edge.dir, 'u', 'd'] : [edge.dir];
      let landed: string | null = null, via = '';
      for (const d of dirs) { const t = room.exits[d]; if (t) { landed = t; via = d; break; } }
      if (!landed) {
        conflicts.push({ box, room: room.slug, towards: [edge.to],
                         message: `the drawing goes ${edge.dir} from here to a room we cannot reach` });
        continue;
      }
      if (roomToBox.has(landed)) {
        if (roomToBox.get(landed) !== edge.to)
          conflicts.push({ box: edge.to, room: landed,
                           message: `walking ${edge.dir} from here reaches ${landed}, which the drawing puts elsewhere` });
        continue;
      }
      pair(edge.to, landed);
      queue.push(edge.to);
    }
  }

  // A trap box stands for TWO rooms: the one you step into, and the one you
  // fall into. The drawing gives them one box, so the pit is not a missing
  // room -- it is drawn inside its trap. Fold it in rather than reporting it.
  //
  // Only traps do this. A staircase down gets its own box: town 1 draws the
  // vaults as [V^] even though the guild hall drops into them.
  const pits: [number, string][] = [];
  for (const [boxIndex, slug] of boxToRoom) {
    if (!/^[tpf]$/.test(shrine.boxes[boxIndex].label)) continue;
    const below = ours[slug]?.exits['d'];
    if (!below || roomToBox.has(below)) continue;
    const only = Object.entries(ours[below]?.exits ?? {});
    if (only.length === 1 && only[0][0] === 'u') { pits.push([boxIndex, below]); roomToBox.set(below, boxIndex); }
  }

  const degree = new Map<number, number>();
  for (const e of shrine.edges) {
    degree.set(e.from, (degree.get(e.from) ?? 0) + 1);
    degree.set(e.to, (degree.get(e.to) ?? 0) + 1);
  }
  const shapeMismatches = [];
  for (const [boxIndex, slug] of boxToRoom) {
    if (pits.some(([, p]) => p === slug)) continue;          // a pit is drawn inside its trap
    const drawn = degree.get(boxIndex) ?? 0;
    // Count only what the drawing actually draws as a connector: exits that go
    // to another room of this same area and have been walked. An exit leaving
    // the area is drawn as a text label ("down to Dungeon") or a ^/v badge, and
    // an unwalked stub is not drawn at all -- counting either makes every room
    // with a stair look mismatched.
    //
    // A pit hangs off its trap room in our map but not in the drawing, so a
    // room with a pit folded into it legitimately has one exit more than its
    // box. Only when a pit was actually folded, though: cave-6 is a SPIKED
    // trap with nothing below it, and subtracting for every trap box reported
    // a correct pairing as broken.
    const foldedPit = pits.some(([bi]) => bi === boxIndex);
    const oursCount = Object.values(ours[slug]?.exits ?? {})
      .filter(dest => dest != null && ours[dest as string] !== undefined).length
      - (foldedPit ? 1 : 0);
    if (drawn !== oursCount) shapeMismatches.push({ box: boxIndex, room: slug, drawn, ours: oursCount });
  }

  return {
    area,
    pits,
    shapeMismatches,
    matched: [...boxToRoom.entries()],
    unmatchedBoxes: shrine.boxes.filter(b => !boxToRoom.has(b.index)).map(b => b.index),
    unmatchedRooms: Object.keys(ours).filter(s => !roomToBox.has(s)),
    conflicts,
  };
}

/** Anchors, chosen because each is identifiable in both sources with certainty. */
export const ANCHORS: Record<string, { map: string; area: string; anchor: Anchor }> = {
  'town-1':   { map: 'town-1',   area: 'first-town',
                anchor: { box: m => m.boxes.findIndex(b => b.label === '*'), room: 'north-plaza' } },
  'town-2':   { map: 'town-2',   area: 'second-town',
                anchor: { box: m => m.boxes.findIndex(b => b.label === 'M'), room: 'magic-shop-1' } },
  'dungeon-1': { map: 'dungeon-1', area: 'first-dungeon-level-1',
                anchor: { box: m => m.boxes.findIndex(b => b.badge === '^'), room: 'dungeon-entrance' } },
  'dungeon-2': { map: 'dungeon-2', area: 'first-dungeon-level-2',
                anchor: { box: m => m.boxes.findIndex(b => b.badge === '^'), room: 'bottom-of-a-circular-stairwell' } },
  'dungeon-3': { map: 'dungeon-3', area: 'first-dungeon-level-3',
                anchor: { box: m => m.boxes.findIndex(b => b.badge === '^'), room: 'bottom-of-a-stairwell' } },
  'sewers-1': { map: 'sewers-1', area: 'sewers-level-1',
                anchor: { box: m => m.boxes.findIndex(b => b.badge === '^'), room: 'town-sewers' } },
  'sewers-2': { map: 'sewers-2', area: 'sewers-level-2',
                anchor: { box: m => m.boxes.findIndex(b => b.badge === '^'), room: 'town-sewers-63' } },
  'sewers-3': { map: 'sewers-3', area: 'sewers-level-3',
                anchor: { box: m => m.boxes.findIndex(b => b.label === 'c'), room: 'town-sewers-165' } },
};

if (import.meta.main) {
  const { Database } = await import('bun:sqlite');
  const db = new Database('tele-arena.db');
  const reports: any[] = [];
  for (const [name, cfg] of Object.entries(ANCHORS)) {
    const shrine = parseMap(await Bun.file(`map/shrine/${cfg.map}.txt`).text());
    const rows = db.prepare(
      `SELECT r.id, r.slug FROM rooms r JOIN areas a ON a.id = r.area_id WHERE a.slug = ?`).all(cfg.area) as any[];
    const slugById = new Map(rows.map(r => [r.id, r.slug]));
    const ours: Record<string, OurRoom> = {};
    for (const r of rows) {
      const exits: Record<string, string | null> = {};
      for (const e of db.prepare('SELECT direction, to_id FROM room_exits WHERE from_id = ?').all(r.id) as any[])
        exits[e.direction] = e.to_id == null ? null : (slugById.get(e.to_id) ?? null);
      ours[r.slug] = { slug: r.slug, exits };
    }
    const rep = reconcile(cfg.area, shrine, ours, cfg.anchor);
    const ok = rep.unmatchedBoxes.length === 0 && rep.unmatchedRooms.length === 0
            && rep.conflicts.length === 0 && rep.shapeMismatches.length === 0;
    console.log(`\n${name.padEnd(11)} ${ok ? 'ALIGNED' : 'PARTIAL'}  ${rep.matched.length}/${shrine.boxes.length} boxes matched to ${Object.keys(ours).length} rooms`);
    if (rep.shapeMismatches.length)
      console.log(`    ${rep.shapeMismatches.length} match(es) whose shape disagrees — THE ALIGNMENT HAS DRIFTED,`
                + ` conflicts below are not trustworthy`);
    for (const m of rep.shapeMismatches.slice(0, 3))
      console.log(`        ${m.room} has ${m.ours} exit(s); its box is drawn with ${m.drawn}`);
    if (rep.pits.length) console.log(`    ${rep.pits.length} pit(s) drawn inside a trap box: ${rep.pits.map(p => p[1]).join(', ')}`);
    if (rep.unmatchedBoxes.length) console.log(`    ${rep.unmatchedBoxes.length} box(es) unmatched`);
    if (rep.unmatchedRooms.length) console.log(`    rooms with no box: ${rep.unmatchedRooms.slice(0, 6).join(', ')}${rep.unmatchedRooms.length > 6 ? ` +${rep.unmatchedRooms.length - 6}` : ''}`);
    const uniq = [...new Map(rep.conflicts.map(c => [`${c.box}|${c.message}`, c])).values()];
    for (const c of uniq.slice(0, 5)) console.log(`    conflict at ${c.room}: ${c.message}`);
    if (uniq.length > 5) console.log(`    ... +${uniq.length - 5} more`);
    reports.push({ ...rep, conflicts: uniq,
                   boxes: shrine.boxes.length, rooms: Object.keys(ours).length });
  }
  await Bun.write('map/reconcile.json', JSON.stringify({ generated: new Date().toISOString().slice(0, 10), reports }, null, 2) + '\n');
  console.log(`\nwrote map/reconcile.json`);
}
