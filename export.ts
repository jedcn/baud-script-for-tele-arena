// Export the SQLite map to the checked-in JSON described in
// plans/map-schema.md: one file per area under map/areas/, plus an index.
//
// This is a translation, not a rescue. Where the database is known to be wrong
// the JSON will be too -- the point is to get the shape right on the areas that
// verify clean, so the shrine-derived areas can be authored into the same shape.

import { Database } from 'bun:sqlite';
import { existsSync, mkdirSync } from 'node:fs';

type Row = Record<string, any>;

export type Exit = { to: string | null; door?: { material: string; key: string } };
export type Room = {
  id: string; name: string; description?: string;
  exits: Record<string, Exit>;
  trap?: { type: string };
  notes?: string[];
  layout?: { x: number; y: number };
};
export type Area = {
  area: string; name: string; src: string;
  rooms: Room[];
};

/** `first-town/north-plaza` — stable, greppable, and readable in a route. */
export function roomId(areaSlug: string, roomSlug: string): string {
  return `${areaSlug}/${roomSlug}`;
}

/** Turn one area's rows into the documented shape. Pure, so it is testable. */
export function buildArea(
  areaSlug: string, areaName: string,
  rooms: Row[], exits: Row[], notes: Row[],
  // id -> "area/slug" for EVERY room in the world, not just this area. A
  // per-area lookup silently turns every cross-area exit into a dead end --
  // the arena's stair down to the dungeon vanished that way.
  idToRoomId: Map<number, string>,
): Area {
  const notesFor = new Map<number, string[]>();
  for (const n of notes) {
    if (!notesFor.has(n.room_id)) notesFor.set(n.room_id, []);
    notesFor.get(n.room_id)!.push(n.note);
  }
  const byRoom = new Map<number, Row[]>();
  for (const e of exits) {
    if (!byRoom.has(e.from_id)) byRoom.set(e.from_id, []);
    byRoom.get(e.from_id)!.push(e);
  }

  const out: Room[] = rooms.map(r => {
    const room: Room = { id: roomId(areaSlug, r.slug), name: r.name, exits: {} };
    if (r.description) room.description = r.description;
    // Sorted so the file is stable across exports and diffs cleanly.
    for (const e of (byRoom.get(r.id) ?? []).sort((a, b) => a.direction.localeCompare(b.direction))) {
      const exit: Exit = { to: null };
      if (e.to_id != null) {
        // A destination in another area is still just an id -- that is the
        // whole point of ids being area-qualified.
        const dest = idToRoomId.get(e.to_id);
        if (!dest) throw new Error(`exit ${r.slug} ${e.direction} points at unknown room ${e.to_id}`);
        exit.to = dest;
      }
      if (e.lock_door || e.lock_key)
        exit.door = { material: e.lock_door ?? 'unknown', key: e.lock_key ?? 'unknown' };
      room.exits[e.direction] = exit;
    }
    if (r.trap) room.trap = { type: r.trap };
    const n = notesFor.get(r.id);
    if (n?.length) room.notes = n;
    if (r.x != null && r.y != null) room.layout = { x: r.x, y: r.y };
    return room;
  });
  return { area: areaSlug, name: areaName, src: 'db-export', rooms: out };
}

if (import.meta.main) {
  if (!existsSync('tele-arena.db')) { console.error('export: no tele-arena.db here.'); process.exit(1); }
  const db = new Database('tele-arena.db');
  mkdirSync('map/areas', { recursive: true });

  const idToRoomId = new Map<number, string>(
    (db.prepare('SELECT r.id, r.slug, a.slug AS area FROM rooms r JOIN areas a ON a.id = r.area_id')
      .all() as Row[]).map(r => [r.id, roomId(r.area, r.slug)]));

  const wanted = process.argv.slice(2);
  const areas = (db.prepare('SELECT id, slug, name FROM areas ORDER BY slug').all() as Row[])
    .filter(a => wanted.length === 0 || wanted.includes(a.slug));

  const index: Row[] = [];
  for (const a of areas) {
    const rooms = db.prepare(
      'SELECT id, slug, name, description, trap, x, y FROM rooms WHERE area_id = ? ORDER BY id').all(a.id) as Row[];
    if (!rooms.length) continue;
    const ids = rooms.map(r => r.id).join(',');
    const exits = db.prepare(
      `SELECT from_id, direction, to_id, lock_door, lock_key FROM room_exits
       WHERE from_id IN (${ids}) ORDER BY from_id, direction`).all() as Row[];
    const notes = db.prepare(`SELECT room_id, note FROM room_notes WHERE room_id IN (${ids})`).all() as Row[];
    const area = buildArea(a.slug, a.name, rooms, exits, notes, idToRoomId);
    await Bun.write(`map/areas/${a.slug}.json`, JSON.stringify(area, null, 2) + '\n');
    index.push({ area: a.slug, name: a.name, rooms: area.rooms.length, file: `areas/${a.slug}.json` });
    console.log(`  ${a.slug.padEnd(24)} ${area.rooms.length} rooms`);
  }
  await Bun.write('map/index.json', JSON.stringify({ areas: index }, null, 2) + '\n');
}
