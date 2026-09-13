import { describe, expect, it } from 'bun:test';
import { buildArea, roomId } from './export';

const ids = new Map([[1, 'first-town/north-plaza'], [2, 'first-town/arena'],
                     [3, 'first-dungeon-level-1/dungeon-entrance']]);
const rooms = [{ id: 1, slug: 'north-plaza', name: 'north plaza', description: 'a plaza' },
               { id: 2, slug: 'arena', name: 'arena', description: null, trap: null }];

describe('roomId', () => {
  it('qualifies a room by its area', () => {
    expect(roomId('first-town', 'north-plaza')).toBe('first-town/north-plaza');
  });
});

describe('buildArea', () => {
  // Regression: a per-area slug lookup turned every cross-area exit into a dead
  // end, silently -- the arena's stair down to the dungeon just vanished.
  it('keeps an exit that leaves the area', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 2, direction: 'd', to_id: 3 }], [], [], ids);
    expect(a.rooms.find(r => r.id === 'first-town/arena')!.exits.d.to)
      .toBe('first-dungeon-level-1/dungeon-entrance');
  });

  it('records an unwalked exit as null rather than omitting it', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'ne', to_id: null }], [], [], ids);
    expect(a.rooms[0].exits.ne).toEqual({ to: null });
  });

  it('carries a door as material plus key, which are different metals', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'w', to_id: 2, lock_door: 'stone', lock_key: 'iron' }], [], [], ids);
    expect(a.rooms[0].exits.w.door).toEqual({ material: 'stone', key: 'iron' });
  });

  it('sorts exits so the file diffs cleanly across exports', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'w', to_id: 2 }, { from_id: 1, direction: 'e', to_id: 2 },
       { from_id: 1, direction: 'n', to_id: 2 }], [], [], ids);
    expect(Object.keys(a.rooms[0].exits)).toEqual(['e', 'n', 'w']);
  });

  // A Seal is the Device-cleared counterpart of a Door, and saying `key:
  // "unknown"` on one would be a lie rather than a gap: no key opens it.
  it('carries a device-sealed exit as sealedBy, with no key claimed', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'e', to_id: 2, lock_door: 'iron', sealed_by: 7 }],
      [], [{ id: 7, room_id: 1, command: 'say komi' }], ids);
    expect(a.rooms[0].exits.e.door).toEqual({ material: 'iron' });
    expect(a.rooms[0].exits.e.sealedBy)
      .toEqual({ command: 'say komi', room: 'first-town/north-plaza' });
  });

  it('still says the key is unknown when nothing else explains the block', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'e', to_id: 2, lock_door: 'iron' }], [], [], ids);
    expect(a.rooms[0].exits.e.door).toEqual({ material: 'iron', key: 'unknown' });
  });

  it('names the device by the room it is worked in, which is often elsewhere', () => {
    const a = buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'e', to_id: 2, sealed_by: 7 }],
      [], [{ id: 7, room_id: 3, command: 'pull lever' }], ids);
    expect(a.rooms[0].exits.e.sealedBy!.room)
      .toBe('first-dungeon-level-1/dungeon-entrance');
  });

  it('refuses an exit pointing at a room it cannot name', () => {
    expect(() => buildArea('first-town', 'First Town', rooms,
      [{ from_id: 1, direction: 'n', to_id: 999 }], [], [], ids)).toThrow(/unknown room 999/);
  });
});
