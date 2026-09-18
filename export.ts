// Export the SQLite map to the checked-in JSON described in
// plans/map-schema.md: one file per area under map/areas/, plus an index.
//
// This is a translation, not a rescue. Where the database is known to be wrong
// the JSON will be too -- the point is to get the shape right on the areas that
// verify clean, so the shrine-derived areas can be authored into the same shape.

import { Database } from 'bun:sqlite';
import { existsSync, mkdirSync } from 'node:fs';

type Row = Record<string, any>;

export type Exit = {
  to: string | null;
  // A Door is the Seal a carried key clears, so `key` is only present when a key
  // is what opens it. An exit opened by a Device carries `sealedBy` instead --
  // saying `key: "unknown"` there would be a lie, not a gap.
  door?: { material: string; key?: string };
  sealedBy?: { command: string; room: string };
};
export type Room = {
  id: string; name: string; description?: string;
  exits: Record<string, Exit>;
  trap?: { type: string };
  devices?: {
    command: string; effect: string; repeats?: string; note?: string;
    // Where the effect LANDS, when it lands on one room: the room a Teleport puts
    // you in, or the room whose Trap a lever disarms. Without these the JSON
    // cannot say what a device does, which is not a small gap -- `just coverage`
    // needs a Teleport's destination to reach the rooms no compass exit does, and
    // a reader of the map needs to know which trap the lever is for. A Seal has
    // neither, on purpose: one device can open several, so the Seal is recorded on
    // the exits it blocks (`sealedBy`) and pointed back here.
    dest?: string; trapRoom?: string;
  }[];
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
  rooms: Row[], exits: Row[], devices: Row[], allDevices: Row[],
  // id -> "area/slug" for EVERY room in the world, not just this area. A
  // per-area lookup silently turns every cross-area exit into a dead end --
  // the arena's stair down to the dungeon vanished that way.
  idToRoomId: Map<number, string>,
): Area {
  // Devices grouped by the room you OPERATE them in, which is not the room they
  // affect -- see GLOSSARY.md. What a device opens is carried on the exit
  // (sealed_by) rather than here, because one device can open several.
  const devicesFor = new Map<number, Room['devices']>();
  for (const d of devices) {
    if (!devicesFor.has(d.room_id)) devicesFor.set(d.room_id, []);
    devicesFor.get(d.room_id)!.push({
      command: d.command, effect: d.effect,
      ...(d.repeats ? { repeats: d.repeats } : {}),
      ...(d.dest_room_id && idToRoomId.get(d.dest_room_id)
        ? { dest: idToRoomId.get(d.dest_room_id)! } : {}),
      ...(d.trap_room_id && idToRoomId.get(d.trap_room_id)
        ? { trapRoom: idToRoomId.get(d.trap_room_id)! } : {}),
      ...(d.note ? { note: d.note } : {}),
    });
  }
  const sealers = new Map<number, { command: string; room: string }>();
  for (const d of allDevices) {
    const room = idToRoomId.get(d.room_id);
    if (room) sealers.set(d.id, { command: d.command, room });
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
      if (e.lock_door || e.lock_key) {
        exit.door = { material: e.lock_door ?? 'unknown' };
        // Only claim a key when one is known, or when nothing else explains the
        // block. A Device-sealed exit has no key at all.
        if (e.lock_key) exit.door.key = e.lock_key;
        else if (!e.sealed_by) exit.door.key = 'unknown';
      }
      const sealer = sealers.get(e.sealed_by);
      if (sealer) exit.sealedBy = sealer;
      room.exits[e.direction] = exit;
    }
    if (r.trap) room.trap = { type: r.trap };
    const dv = devicesFor.get(r.id);
    if (dv?.length) room.devices = dv;
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

  // Every device in the world, not just this area's: the device that opens an
  // exit is usually somewhere else entirely, which is the whole reason a Seal is
  // recorded on the exit and points at it.
  const allDevices = db.prepare(
    'SELECT id, room_id, command FROM devices ORDER BY id').all() as Row[];

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
      `SELECT from_id, direction, to_id, lock_door, lock_key, sealed_by FROM room_exits
       WHERE from_id IN (${ids}) ORDER BY from_id, direction`).all() as Row[];
    const devices = db.prepare(
      `SELECT room_id, command, effect, repeats, dest_room_id, trap_room_id, note
         FROM devices WHERE room_id IN (${ids}) ORDER BY room_id, id`).all() as Row[];
    const area = buildArea(a.slug, a.name, rooms, exits, devices, allDevices, idToRoomId);
    await Bun.write(`map/areas/${a.slug}.json`, JSON.stringify(area, null, 2) + '\n');
    index.push({ area: a.slug, name: a.name, rooms: area.rooms.length, file: `areas/${a.slug}.json` });
    console.log(`  ${a.slug.padEnd(24)} ${area.rooms.length} rooms`);
  }
  await Bun.write('map/index.json', JSON.stringify({ areas: index }, null, 2) + '\n');

  // Where each character was last seen, for the "you are here" mark on the map.
  // Its own file, and an untracked one, because this is not a map fact: it
  // changes with every step, so folding it into index.json would put a diff of
  // somebody's whereabouts in front of every commit. A machine without it (a
  // fresh clone, the VPS) simply draws no mark.
  const players = db.prepare(
    `SELECT p.player, p.room_id, p.updated_at FROM player_location p
      WHERE p.room_id IS NOT NULL ORDER BY p.player`).all() as Row[];
  const located = players
    .filter(p => idToRoomId.has(p.room_id))
    .map(p => ({ player: p.player, room: idToRoomId.get(p.room_id), seen: p.updated_at }));
  await Bun.write('map/players.json', JSON.stringify({ players: located }, null, 2) + '\n');
  console.log(`  ${'players'.padEnd(24)} ${located.length} located`);
}
