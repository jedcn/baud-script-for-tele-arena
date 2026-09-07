import { describe, expect, it } from 'bun:test';
import { renderArea, buildMarkdown, type Room, type Exit } from './map';

// Fixtures are plain data, never the live DB: tele-arena.db is absent on the
// VPS, and these are also the three bugs that cost rooms silently, so they need
// to be pinned to a known graph rather than to whatever has been mapped.
const room = (id: number, slug: string, name = slug): Room => ({ id, slug, name });
const pair = (a: number, d: string, b: number, rev: string): Exit[] =>
  [{ from_id: a, direction: d, to_id: b }, { from_id: b, direction: rev, to_id: a }];

describe('renderArea', () => {
  it('draws a west-east chain with connectors between the boxes', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'mid', 'north plaza'), room(2, 'shop', 'armor shop'), room(3, 'far', 'temple')],
      exits: [...pair(1, 'e', 2, 'w'), ...pair(2, 'e', 3, 'w')],
      origin: 'mid',
    });
    expect(lines.join('\n')).toBe('[ ]--[a]--[t]');
  });

  it('places a north neighbour above, joined by a vertical run', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'mid', 'north plaza'), room(2, 'up', 'temple')],
      exits: pair(1, 'n', 2, 's'),
      origin: 'mid',
    });
    expect(lines).toEqual(['[t]', ' |', ' |', '[ ]']);
  });

  // Regression: vaults and the private room are reachable ONLY by u/d. A
  // renderer that walks compass edges alone omits them with no error at all.
  it('keeps a room reachable only by a vertical exit, and connects it', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'hall', 'guild hall'), room(2, 'vault', 'town vaults')],
      exits: pair(1, 'd', 2, 'u'),
      origin: 'hall',
    });
    const text = lines.join('\n');
    expect(text).toContain('[V^]');   // the vault, with its up badge
    expect(text).toContain('[Gv]');   // the hall, with its down badge
    expect(text).toMatch(/[\\|\/]/);  // and a connector joining them
  });

  // Regression: placing a vertical neighbour at a fixed offset dropped the
  // arena, because the vaults landed exactly on top of it.
  it('does not let a vertical neighbour overwrite a compass room', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza'), room(2, 'arena', 'arena'), room(3, 'vault', 'town vaults')],
      exits: [...pair(1, 'e', 2, 'w'), ...pair(1, 'd', 3, 'u')],
      origin: 'plaza',
    });
    const text = lines.join('\n');
    expect(text).toContain('[A]');
    expect(text).toContain('[V^]');
  });

  // Regression: a vertical room placed before pass 1 squats on a cell a real
  // compass edge needs, and the compass room then overwrites IT instead.
  it('places compass rooms before vertical ones, losing neither', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'tav', 'tavern'), room(2, 'priv', 'private room'), room(3, 'dock', 'docks')],
      // the private room is discovered first, and wants the cell docks needs
      exits: [...pair(1, 'u', 2, 'd'), ...pair(1, 'n', 3, 's')],
      origin: 'tav',
    });
    const text = lines.join('\n');
    expect(text).toContain('[D]');
    expect(text).toContain('[pv]');
  });

  it('turns an exit leaving the area into a text label', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza')],
      exits: [{ from_id: 1, direction: 'd', to_id: 99 }],
      origin: 'plaza',
      areaOf: () => 'first-dungeon',
    });
    expect(lines.join('\n')).toContain('down to first-dungeon');
  });

  it('labels an unwalked exit as unexplored', () => {
    const { lines } = renderArea({
      rooms: [room(1, 'plaza', 'north plaza')],
      exits: [{ from_id: 1, direction: 'n', to_id: null }],
      origin: 'plaza',
    });
    expect(lines.join('\n')).toContain('n to unexplored');
  });

  it('builds a key from only the services actually present', () => {
    const { key } = renderArea({
      rooms: [room(1, 'a', 'north plaza'), room(2, 'b', 'temple')],
      exits: pair(1, 'e', 2, 'w'),
      origin: 'a',
    });
    expect(key).toEqual(['t = Temple']);
  });

  // Placement depends on iteration order, so the query must not be free to
  // reorder rows between runs.
  it('is deterministic regardless of the order rows arrive in', () => {
    const rooms = [room(1, 'mid', 'north plaza'), room(2, 'e', 'arena'), room(3, 'n', 'temple')];
    const exits = [...pair(1, 'e', 2, 'w'), ...pair(1, 'n', 3, 's')];
    const a = renderArea({ rooms, exits, origin: 'mid' });
    const b = renderArea({ rooms: [...rooms].reverse(), exits: [...exits].reverse(), origin: 'mid' });
    expect(b.lines).toEqual(a.lines);
  });

  it('rejects an origin that is not in the area', () => {
    expect(() => renderArea({ rooms: [room(1, 'a')], exits: [], origin: 'nope' }))
      .toThrow(/origin room 'nope'/);
  });
});

describe('buildMarkdown', () => {
  it('writes a heading, a linked table of contents, and a fenced section each', () => {
    const md = buildMarkdown([
      { title: 'First Town', lines: ['[ ]'], key: ['t = Temple'] },
      { title: 'Second Town', lines: ['[a]'], key: [] },
    ]);
    expect(md).toContain('# Tele Arena Map');
    expect(md).toContain('1. [First Town](#first-town)');
    expect(md).toContain('2. [Second Town](#second-town)');
    expect(md).toContain('### First Town');
    expect(md).toContain('- `t` — Temple');
    expect(md.match(/```/g)).toHaveLength(4);   // one fence pair per area
    expect(md.endsWith('\n')).toBe(true);
  });
});
