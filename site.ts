// Build map.html: the whole mapped world as one browsable page — pick an Area,
// pick a Level, read the map.
//
// The data comes from the checked-in JSON under map/, never from tele-arena.db.
// That is the point of the exercise: everything a reader needs is already in the
// export, so this page proves the JSON is sufficient. It also means the page
// builds on a machine with no database at all, which is where the map is going.
//
// Placement is map.ts's `placeRooms`, the same pass that draws MAP.md. The hard
// part of a map is deciding where a room goes; two copies of that would drift,
// and the ASCII and the SVG disagreeing about the shape of a level would be
// worse than having only one of them. Stored coordinates are still not consulted
// (CLAUDE.md: "coordinates are soft; topology is truth").
//
// Dark only, matching report.html, because they are read side by side.

import { placeRooms, skewedEdges, SERVICES, DRAWN, type Room as GridRoom,
         type Exit as GridExit } from './map';
import type { Area, Room, Exit } from './export';

// Pixels per grid cell, and the box drawn in it. Wide enough that a diagonal
// reads as a slope and two labels never touch.
const CELL_W = 78, CELL_H = 62;
const BOX_W = 42, BOX_H = 30;
const PAD = 34;                 // room for a frontier stub at the outer edge
const STUB = 17;                // how far an unwalked exit pokes out

const COMPASS: Record<string, [number, number]> = {
  n: [0, -1], s: [0, 1], e: [1, 0], w: [-1, 0],
  ne: [1, -1], nw: [-1, -1], se: [1, 1], sw: [-1, 1],
};

const REVERSE: Record<string, string> = {
  n: 's', s: 'n', e: 'w', w: 'e', ne: 'sw', sw: 'ne', nw: 'se', se: 'nw',
  u: 'd', d: 'u', passage: 'passage',
};

export function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------
// Areas and levels

export type LevelRef = { slug: string; name: string; level: string; sort: number };
export type Group = { area: string; levels: LevelRef[] };

/**
 * Split an exported area name into the Area a reader picks and the Level within
 * it: "The Stoneworks, Level 2" is level 2 of the Stoneworks. An area with no
 * levels ("The Desert") is its own single level, labelled with a dash rather
 * than invented numbering — the select still needs one entry to point at.
 */
export function splitName(name: string): { area: string; level: string; sort: number } {
  const m = name.match(/^(.*),\s*Level\s+(\d+)$/);
  if (m) return { area: m[1], level: `Level ${m[2]}`, sort: Number(m[2]) };
  return { area: name, level: '—', sort: 0 };
}

/** Areas grouped for the two selects, levels in numeric order (not lexical). */
export function groupAreas(areas: { area: string; name: string }[]): Group[] {
  const groups = new Map<string, Group>();
  for (const a of areas) {
    const { area, level, sort } = splitName(a.name);
    if (!groups.has(area)) groups.set(area, { area, levels: [] });
    groups.get(area)!.levels.push({ slug: a.area, name: a.name, level, sort });
  }
  const out = [...groups.values()];
  for (const g of out) g.levels.sort((x, y) => x.sort - y.sort || x.slug.localeCompare(y.slug));
  out.sort((x, y) => x.area.localeCompare(y.area));
  return out;
}

// ---------------------------------------------------------------------------
// One level as SVG

export type LevelStats = {
  rooms: number; frontiers: number; devices: number; traps: number;
  doors: number; seals: number; leaving: number;
  /** Lines that do not point the way their exit goes. See `skewedEdges`. */
  skewed: number;
  /** Connections you can only cross one way. See the arrow in `renderLevel`. */
  oneWay: number;
};
export type LevelSvg = {
  svg: string; stats: LevelStats; width: number; height: number;
  /** Where the layout pass put each room, for the page to drag from and reset to. */
  home: Record<string, [number, number]>;
};

/** The short label for a link that leaves this area: "Level 3", or "The Desert". */
export function awayLabel(fromName: string, toName: string): string {
  const from = splitName(fromName), to = splitName(toName);
  return from.area === to.area && to.level !== '—' ? to.level : to.area;
}

/**
 * What goes inside the box. The shrine drawings had four characters to spend and
 * left most rooms as a bare `[ ]`; a browser can afford a word, so every box says
 * something: the service letter where the room is a shop or a temple, the slug's
 * own number where it has one (which is what `map-here` and the JSON id use), and
 * otherwise the initials of its name, so a town's plazas are told apart.
 */
export function boxLabel(room: Room): string {
  const service = SERVICES[room.name];
  if (service) return service.letter;
  const n = room.id.match(/^(.*?)-?([a-z]+)-(\d+)$/);
  // Two letters of the kind plus the number: `co50`, `ch5`. The number alone is
  // ambiguous inside one area -- stoneworks level 1 has both a chamber-1 and a
  // corridor-1, and two boxes labelled `1` are worse than no label.
  if (n) return n[2].slice(0, 2) + n[3];
  return room.name.split(/\s+/).slice(0, 2).map(w => w[0] ?? '').join('');
}

/**
 * Draw one level.
 *
 * Every exit in the JSON ends up visible as one of four things, because an exit
 * that renders as nothing is indistinguishable from an exit we failed to record:
 * a line to another box on this level, a dashed stub with a label (it leaves the
 * area), a dashed stub with an open circle (`to: null`, the frontier), or a
 * ▲/▼ badge (`u`/`d`, which have no compass offset to draw along).
 *
 * Geometry is anchored rather than absolute, so the page can move a room and keep
 * the map connected. Everything that belongs to ONE room -- its box, its label,
 * its trap and device dots, its stair badges, its stubs -- is a child of a group
 * carrying `data-a="<room id>"` and positioned by that group's `transform`, so
 * moving the room is one attribute. The only things left to recompute are the
 * pieces that span two rooms: an edge (two endpoints) and the Door or Seal mark
 * at its midpoint, both tagged `data-a` and `data-b`. `pos` goes to the page as
 * data so the drag has somewhere to keep the new positions, and a reset has the
 * old ones.
 */
export function renderLevel(
  area: Area, nameOf: (areaSlug: string) => string,
  /** room id -> characters last seen standing there, for the "you are here" mark. */
  playersByRoom: Map<string, string[]> = new Map(),
): LevelSvg {
  const ids = new Map(area.rooms.map((r, i) => [r.id, i + 1]));
  const gridRooms: GridRoom[] = area.rooms.map((r, i) => ({ id: i + 1, slug: r.id, name: r.name }));
  const gridExits: GridExit[] = [];
  for (const r of area.rooms) {
    for (const [dir, ex] of Object.entries(r.exits)) {
      const to = ex.to != null ? ids.get(ex.to) : undefined;
      gridExits.push({ from_id: ids.get(r.id)!, direction: dir, to_id: to ?? null });
    }
  }

  const drawn = DRAWN.find(d => d.slug === area.area);
  const origin = drawn && ids.has(`${area.area}/${drawn.origin}`)
    ? `${area.area}/${drawn.origin}` : area.rooms[0].id;
  const { pos } = placeRooms({ rooms: gridRooms, exits: gridExits, origin });

  // Which lines are about to point somewhere their exit does not go.
  //
  // An edge is drawn between the two boxes' centres, so its angle is a
  // consequence of placement and nothing else. Most of the time that agrees with
  // the direction; where it cannot, the line is marked rather than left to read
  // as a plain exit, because a reader has no way to tell the difference and this
  // page is the map people actually navigate from. `deep-forest-149 --sw-->
  // deep-forest-150` points due north and looked entirely ordinary.
  const slugOf = new Map([...ids].map(([slug, n]) => [n, slug]));
  const skewed = new Map<string, { drawn: string; inherent: boolean }>();
  for (const s of skewedEdges(gridRooms, gridExits, pos))
    skewed.set(`${slugOf.get(s.from_id)}|${s.direction}`,
               { drawn: s.drawn, inherent: s.inherent });

  const cells = [...pos.values()];
  const minC = Math.min(...cells.map(p => p.c)), maxC = Math.max(...cells.map(p => p.c));
  const minR = Math.min(...cells.map(p => p.r)), maxR = Math.max(...cells.map(p => p.r));
  const width = (maxC - minC) * CELL_W + BOX_W + PAD * 2;
  const height = (maxR - minR) * CELL_H + BOX_H + PAD * 2;
  const at = (roomId: string): [number, number] => {
    const p = pos.get(ids.get(roomId)!)!;
    return [PAD + (p.c - minC) * CELL_W + BOX_W / 2, PAD + (p.r - minR) * CELL_H + BOX_H / 2];
  };
  const home: Record<string, [number, number]> = {};
  for (const room of area.rooms) home[room.id] = at(room.id);

  const stats: LevelStats = {
    rooms: area.rooms.length, frontiers: 0, devices: 0, traps: 0,
    doors: 0, seals: 0, leaving: 0, skewed: 0, oneWay: 0,
  };
  const byId = new Map(area.rooms.map(r => [r.id, r]));
  const edges: string[] = [], gates: string[] = [], boxes: string[] = [];
  const own = new Map<string, string[]>();          // room id -> its own stubs/badges
  const part = (roomId: string, svg: string) => {
    if (!own.has(roomId)) own.set(roomId, []);
    own.get(roomId)!.push(svg);
  };
  const seen = new Set<string>();

  for (const room of area.rooms) {
    for (const [dir, ex] of Object.entries(room.exits) as [string, Exit][]) {
      const gate = ex.sealedBy ? 'seal' : ex.door ? 'door' : null;
      const title = ex.sealedBy
        ? `${dir}: sealed, opened by \`${ex.sealedBy.command}\` in ${ex.sealedBy.room}`
        : ex.door
          ? `${dir}: ${ex.door.material} door${ex.door.key ? `, ${ex.door.key} key` : ''}`
          : `${dir}`;

      // Leaves the level, or nobody has walked it: a stub either way, since
      // there is no second box to draw a line to. Drawn in the room's own
      // coordinates, which is what lets it travel with the room.
      if (ex.to == null || !ids.has(ex.to)) {
        const o = COMPASS[dir] ?? [0, dir === 'u' ? -1 : 1];
        const len = ex.to == null ? STUB : STUB + 2;
        const x1 = o[0] * (BOX_W / 2), y1 = o[1] * (BOX_H / 2);
        const x2 = x1 + o[0] * len, y2 = y1 + o[1] * len;
        if (ex.to == null) {
          stats.frontiers++;
          part(room.id, `<line class="stub" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`
            + `<circle class="frontier" cx="${x2}" cy="${y2}" r="4">`
            + `<title>${esc(dir)}: exit known, never walked</title></circle>`);
        } else {
          stats.leaving++;
          const label = awayLabel(area.name, nameOf(ex.to.split('/')[0]));
          const anchor = o[0] > 0 ? 'start' : o[0] < 0 ? 'end' : 'middle';
          part(room.id, `<line class="away" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`
            + `<text class="away-label" x="${x2 + o[0] * 4}" y="${y2 + (o[1] >= 0 ? 11 : -5)}"`
            + ` text-anchor="${anchor}">${esc(label)}</text>`
            + `<title>${esc(dir)} to ${esc(ex.to)}</title>`);
        }
        if (gate) part(room.id, gateMark(gate, (x1 + x2) / 2, (y1 + y2) / 2, title));
        continue;
      }

      // u/d carry no compass direction, so the badge on the box is what says
      // which WAY the stair goes -- a plain line would lie about where the room
      // lies. The line drawn below says which ROOM it goes to, which the badge
      // cannot: without it a staircase is invisible, and a level joined to
      // itself only by stairs reads as two drawings that have nothing to do
      // with each other. complex-caverns-level-2 is two such halves, joined at
      // caverns-116/117 and nowhere else.
      const vert = dir === 'u' || dir === 'd';
      if (vert) {
        const up = dir === 'u';
        part(room.id, `<text class="vbadge" x="${BOX_W / 2 - 5}"`
          + ` y="${up ? -BOX_H / 2 + 9 : BOX_H / 2 - 2}">${up ? '▲' : '▼'}`
          + `<title>${esc(dir)} to ${esc(ex.to)}</title></text>`);
      }

      // One line per CONNECTION, not per direction: `hall --e--> corridor` and
      // `corridor --w--> hall` are the same doorway, and drawing both doubles
      // every stroke and leaves two overlapping hover targets. Keying on the
      // direction PAIR rather than on the two rooms is what keeps a second,
      // different connection between the same two rooms (a room reachable both
      // `n` and `ne`, say) from vanishing instead -- no area has one today, and
      // if one appears the two lines will coincide, which is a cosmetic problem
      // where dropping an exit would be a lie.
      const pair = [room.id, ex.to].sort();
      const key = pair.join('|') + ':' + [dir, REVERSE[dir] ?? dir].sort().join('-');
      if (seen.has(key)) continue;
      seen.add(key);

      // Does the far side lead back? An exit whose reverse is missing, or leads
      // somewhere else entirely, is a connection you can only cross one way --
      // and nothing else on the page can say so, because one line stands for
      // both directions and a line has no direction. The Complex of Natural
      // Caverns has the only two in the world: `-87 nw` lands on `-90`, whose
      // `se` goes on to `-88` rather than back, and `-88`'s `nw` closes the
      // triangle at `-87`. Two `nw` and one `se` brings you home. It is the
      // cave, not a defect -- walked with mapping off and `ex` called in every
      // room (commit 9aeef4d).
      //
      // A reverse that EXISTS but is unwalked (`to: null`) is not evidence of
      // anything: it is a frontier, and it may well lead back here. Claiming
      // one-way there would put an arrow on every half-walked area in the world
      // and retract it later. Absent, or leading somewhere else, is the claim.
      const back = byId.get(ex.to)?.exits[REVERSE[dir] ?? dir] as Exit | undefined;
      const oneWay = !back ? true : back.to === null ? false : back.to !== room.id;
      // Anchored source-first when one-way, so the line runs the way you travel
      // and the arrow on it needs no other information to aim itself. Both
      // orders are equally correct for a line; only an arrow cares.
      const [aId, bId] = oneWay ? [room.id, ex.to] : pair;
      const [ax, ay] = home[aId], [bx, by] = home[bId];
      const anchors = ` data-a="${esc(aId)}" data-b="${esc(bId)}"`;
      // One line stands for both directions, so ask about both: whichever of the
      // two the skew was recorded against, the line is the same stroke.
      // A stair's line has no angle to be wrong about, so it is never skewed.
      const bad = vert ? undefined : (skewed.get(`${room.id}|${dir}`)
        ?? (ex.to != null ? skewed.get(`${ex.to}|${REVERSE[dir] ?? dir}`) : undefined));
      let lineTitle = vert && !gate ? `${dir} to ${ex.to}` : title;
      if (bad) {
        stats.skewed++;
        lineTitle = `${title} — but this line points ${bad.drawn}. `
          + (bad.inherent
            // Nothing to fix. Saying so is the point: otherwise a reader who
            // spots it goes looking for a bad exit that is not there.
            ? 'The loop this exit closes does not close, so no flat map can draw'
              + ' it in its own direction. The exit is right; the picture cannot be.'
            : 'The layout had to move a room out of a cell another room had'
              + ' already taken, and this line came with it.');
      }
      edges.push(`<line class="edge${vert ? ' vert' : ''}${bad ? ' skew' : ''}"${anchors}`
        + ` x1="${ax}" y1="${ay}"`
        + ` x2="${bx}" y2="${by}"><title>${esc(lineTitle)}</title></line>`);
      if (oneWay) {
        stats.oneWay++;
        // `data-rot` is what tells the page to re-aim this on a drag: the gate
        // marks are translated to the midpoint and nothing more, and an arrow
        // that kept its old angle after a room moved would point at nothing.
        gates.push(`<path class="arrow"${anchors} data-rot=""`
          + ` transform="translate(${(ax + bx) / 2},${(ay + by) / 2})`
          + ` rotate(${(Math.atan2(by - ay, bx - ax) * 180 / Math.PI).toFixed(2)})"`
          + ` d="M-5,-4.5 L6,0 L-5,4.5 Z"><title>`
          + esc(`${dir} to ${ex.to} — ONE WAY: there is no ${REVERSE[dir] ?? dir}`
            + ` back from there`) + `</title></path>`);
      }
      if (gate) {
        if (gate === 'seal') stats.seals++; else stats.doors++;
        gates.push(`<g class="gate"${anchors}`
          + ` transform="translate(${(ax + bx) / 2},${(ay + by) / 2})">`
          + gateMark(gate, 0, 0, title) + `</g>`);
      }
    }
  }

  for (const room of area.rooms) {
    const classes = ['box'];
    if (room.trap) { classes.push('trapped'); stats.traps++; }
    if (room.devices?.length) { classes.push('device'); stats.devices += room.devices.length; }
    if (SERVICES[room.name]) classes.push('service');
    if (room.id === origin) classes.push('origin');
    const here = playersByRoom.get(room.id);
    if (here?.length) classes.push('here');
    const bits = [room.id, room.name];
    if (here?.length) bits.push(`you are here: ${here.join(', ')}`);
    if (room.trap) bits.push(`trap: ${room.trap.type}`);
    for (const d of room.devices ?? []) bits.push(`\`${d.command}\` (${d.effect})`);
    const [x, y] = home[room.id];
    // <title> first: it is a tooltip only as the FIRST child of its element, and
    // the stubs and badges that follow carry titles of their own.
    boxes.push(`<g class="${classes.join(' ')}" data-id="${esc(room.id)}"`
      + ` data-a="${esc(room.id)}" transform="translate(${x},${y})" tabindex="0">`
      + `<title>${esc(bits.join('\n'))}</title>`
      + `<rect x="${-BOX_W / 2}" y="${-BOX_H / 2}" width="${BOX_W}" height="${BOX_H}" rx="5"/>`
      + `<text class="label" x="0" y="4">${esc(boxLabel(room))}</text>`
      + (room.trap
        ? `<circle class="trap-dot" cx="${-BOX_W / 2 + 5}" cy="${-BOX_H / 2 + 5}" r="3.5"/>` : '')
      + (room.devices?.length
        ? `<circle class="device-dot" cx="${BOX_W / 2 - 5}" cy="${-BOX_H / 2 + 5}" r="3.5"/>` : '')
      + (here?.length
        ? `<rect class="here-ring" x="${-BOX_W / 2 - 4}" y="${-BOX_H / 2 - 4}"`
          + ` width="${BOX_W + 8}" height="${BOX_H + 8}" rx="8"/>`
          // +14, not +16: PAD is 34, so a marked room on the bottom row has
          // exactly 34px below its centre, and a 10px label with descenders
          // needs 17 of them. Two pixels of headroom rather than none.
          + `<text class="here-who" x="0" y="${BOX_H / 2 + 14}">${esc(here.join(', '))}</text>` : '')
      + (own.get(room.id) ?? []).join('')
      + `</g>`);
  }

  const svg = `<svg class="level" viewBox="0 0 ${width} ${height}"`
    + ` style="max-width:${width}px" role="img"`
    + ` aria-label="${esc(area.name)}">\n`
    + edges.join('\n') + '\n' + gates.join('\n') + '\n'
    + boxes.join('\n') + '\n</svg>';
  return { svg, stats, width, height, home };
}

function gateMark(kind: 'door' | 'seal', x: number, y: number, title: string): string {
  const cls = kind === 'seal' ? 'seal-mark' : 'door-mark';
  return `<rect class="${cls}" x="${x - 4}" y="${y - 4}" width="8" height="8"`
    + `${kind === 'seal' ? ` transform="rotate(45 ${x} ${y})"` : ''}>`
    + `<title>${esc(title)}</title></rect>`;
}

// ---------------------------------------------------------------------------
// The page

const LEGEND: [string, string][] = [
  ['<svg viewBox="0 0 20 14"><rect class="box" x="1" y="1" width="18" height="12" rx="3"/></svg>',
    'a room — the number is its slug'],
  ['<svg viewBox="0 0 20 14"><rect class="box service" x="1" y="1" width="18" height="12" rx="3"/>'
    + '<text class="label" x="10" y="10">T</text></svg>',
    'a service: the letter is the shop, inn, temple or guild'],
  ['<svg viewBox="0 0 20 14"><rect class="box" x="1" y="1" width="18" height="12" rx="3"/>'
    + '<circle class="device-dot" cx="4" cy="4" r="3"/></svg>',
    'a Device is worked here — a lever, a stone, a word'],
  ['<svg viewBox="0 0 20 14"><rect class="box trapped" x="1" y="1" width="18" height="12" rx="3"/>'
    + '<circle class="trap-dot" cx="4" cy="4" r="3"/></svg>',
    'a Trap has sprung here'],
  ['<svg viewBox="0 0 20 14"><rect class="box" x="3" y="3" width="14" height="8" rx="2"/>'
    + '<rect class="here-ring" x="1" y="1" width="18" height="12" rx="4"/></svg>',
    'a character stands here — where the map last saw them, not live'],
  ['<svg viewBox="0 0 20 14"><line class="edge" x1="1" y1="7" x2="19" y2="7"/></svg>',
    'a walked exit, both ways'],
  ['<svg viewBox="0 0 20 14"><line class="edge" x1="1" y1="7" x2="19" y2="7"/>'
    + '<path class="arrow" d="M-5,-4.5 L6,0 L-5,4.5 Z" transform="translate(11,7)"/></svg>',
    'a connection you can only cross the way the arrow points'],
  ['<svg viewBox="0 0 20 14"><line class="edge skew" x1="1" y1="7" x2="19" y2="7"/></svg>',
    'a walked exit whose line points the wrong way — hover it for which way it'
    + ' really goes, and why the map cannot draw it'],
  ['<svg viewBox="0 0 20 14"><line class="edge" x1="1" y1="7" x2="19" y2="7"/>'
    + '<rect class="door-mark" x="6" y="3" width="8" height="8"/></svg>',
    'a Door: hover it for the material and the key'],
  ['<svg viewBox="0 0 20 14"><line class="edge" x1="1" y1="7" x2="19" y2="7"/>'
    + '<rect class="seal-mark" x="6" y="3" width="8" height="8" transform="rotate(45 10 7)"/></svg>',
    'a Seal: hover it for the Device that opens it'],
  ['<svg viewBox="0 0 20 14"><line class="stub" x1="1" y1="7" x2="13" y2="7"/>'
    + '<circle class="frontier" cx="16" cy="7" r="3.5"/></svg>',
    'an exit nobody has walked — the frontier'],
  ['<svg viewBox="0 0 22 14"><line class="away" x1="1" y1="7" x2="12" y2="7"/>'
    + '<text class="away-label" x="14" y="10">L3</text></svg>',
    'a way out of this level, labelled with where it goes'],
  ['<svg viewBox="0 0 20 14"><rect class="box" x="1" y="1" width="18" height="12" rx="3"/>'
    + '<text class="vbadge" x="13" y="7">▲</text></svg>',
    'stairs up (▲) or down (▼) — no compass direction to draw'],
  ['<svg viewBox="0 0 20 14"><line class="edge vert" x1="1" y1="7" x2="19" y2="7"/></svg>',
    'the stairs themselves: which room the ▲/▼ leads to, on this level'],
];

const CSS = `
:root {
  --bg: #0d1117; --surface: #161b22; --raised: #21262d; --border: #30363d;
  --text: #e6edf3; --muted: #8b949e; --blue: #58a6ff; --amber: #e3b341;
  --red: #f85149; --green: #3fb950; --purple: #bc8cff;
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }   /* a level pane must stay hidden inside a flex row */
body { margin: 0; background: var(--bg); color: var(--text); font-size: 14px;
  line-height: 1.55; font-family: ui-monospace, "Cascadia Code", "Fira Code", monospace; }
header { padding: 1.5rem 1.5rem 1rem; border-bottom: 1px solid var(--border); }
h1 { margin: 0 0 0.25rem; font-size: 1.35rem; letter-spacing: 0.01em; }
h1 span { color: var(--muted); font-weight: 400; }
.sub { color: var(--muted); font-size: 0.82rem; }
.sub code { color: var(--text); }
.picker { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: flex-end;
  padding: 1rem 1.5rem; border-bottom: 1px solid var(--border); background: var(--surface); }
.picker label { display: block; color: var(--muted); font-size: 0.72rem;
  text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 0.25rem; }
select { background: var(--raised); color: var(--text); border: 1px solid var(--border);
  border-radius: 5px; padding: 0.4rem 0.6rem; font: inherit; font-size: 0.85rem; min-width: 13rem; }
.stats { margin-left: auto; color: var(--muted); font-size: 0.8rem; }
.stats b { color: var(--text); font-weight: 600; }
main { display: flex; gap: 1rem; align-items: flex-start; padding: 1rem 1.5rem 2rem; }
.canvas { flex: 1 1 auto; min-width: 0; background: var(--surface);
  border: 1px solid var(--border); border-radius: 8px; padding: 0.5rem; overflow: auto; }
aside { flex: 0 0 20rem; display: flex; flex-direction: column; gap: 1rem; }
.card { background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; padding: 0.9rem 1rem; }
.card h2 { margin: 0 0 0.6rem; font-size: 0.72rem; color: var(--muted);
  text-transform: uppercase; letter-spacing: 0.06em; }
.legend { display: grid; gap: 0.45rem; }
.legend div { display: grid; grid-template-columns: 26px 1fr; gap: 0.5rem;
  align-items: center; font-size: 0.78rem; color: var(--muted); }
.legend svg { width: 24px; height: 16px; overflow: visible; }
#panel .pid { color: var(--blue); word-break: break-all; }
#panel .pname { color: var(--text); }
#panel .pdesc { color: var(--muted); font-size: 0.8rem; margin: 0.5rem 0 0; }
#panel dl { margin: 0.6rem 0 0; display: grid; grid-template-columns: 2.6rem 1fr;
  gap: 0.15rem 0.5rem; font-size: 0.8rem; }
#panel dt { color: var(--muted); }
#panel dd { margin: 0; word-break: break-all; }
#panel .gate { color: var(--amber); }
#panel .none { color: var(--muted); }
#panel ul { margin: 0.6rem 0 0; padding: 0; list-style: none; font-size: 0.8rem; }
#panel li { border-left: 3px solid var(--amber); background: rgba(227,179,65,0.08);
  padding: 0.25rem 0.5rem; margin: 0.25rem 0; border-radius: 2px; }
#panel li.trap { border-left-color: var(--red); background: rgba(248,81,73,0.08); }
svg.level { display: block; width: 100%; height: auto; touch-action: none; }
.box { cursor: grab; }
.box.dragging { cursor: grabbing; }
.box.dragging rect { stroke: var(--blue); stroke-width: 2.5px; }
button.ghost { background: var(--raised); color: var(--muted); border: 1px solid var(--border);
  border-radius: 5px; padding: 0.35rem 0.7rem; font: inherit; font-size: 0.78rem; cursor: pointer; }
button.ghost:hover { color: var(--text); border-color: var(--blue); }
button.ghost[disabled] { opacity: 0.45; cursor: default; }
.hint { color: var(--muted); font-size: 0.78rem; }
.box rect { fill: var(--raised); stroke: #4d5560; stroke-width: 1.5px; }
.box .label { fill: var(--muted); font-size: 11px; text-anchor: middle;
  font-family: inherit; pointer-events: none; }
.box:hover rect, .box:focus rect { stroke: var(--blue); stroke-width: 2px; outline: none; }
.box.sel rect { stroke: var(--blue); stroke-width: 2.5px; fill: #1c2b3d; }
.box.service rect { fill: #1b2a36; stroke: var(--blue); }
.box.service .label { fill: var(--blue); font-weight: 700; }
.box.trapped rect { stroke: var(--red); }
.box.origin rect { stroke-dasharray: none; stroke: var(--green); }
.edge { stroke: #55606d; stroke-width: 1.6px; }
.stub { stroke: #55606d; stroke-width: 1.6px; stroke-dasharray: 3 3; }
.frontier { fill: var(--bg); stroke: var(--green); stroke-width: 1.6px; }
.away { stroke: var(--blue); stroke-width: 1.6px; stroke-dasharray: 4 3; }
/* A line whose angle is not the direction of the exit it stands for. Amber and
   dashed rather than a colour of its own: it is a caveat on an ordinary exit,
   not a different kind of exit, and it has to stay legible under the door and
   seal marks that may sit on top of it. */
.edge.skew { stroke: var(--amber); stroke-dasharray: 5 3; }
/* A staircase between two rooms on this level. Dashed because its angle carries
   no meaning at all -- the rooms are above and below one another, not beside --
   and purple rather than green because green already says "frontier" here, on
   the circle and on the origin box, and a third meaning for it would be one
   too many. */
.edge.vert { stroke: var(--purple); stroke-dasharray: 6 4; }
/* The arrowhead on a connection that only goes one way. Filled in the text
   colour rather than a colour of its own: it is not a new kind of exit, it is
   the one thing a line cannot say about itself, and there are exactly two in
   the world. Outlined in the background so it stays legible over the line. */
.arrow { fill: var(--text); stroke: var(--bg); stroke-width: 1px; }
.away-label { fill: var(--blue); font-size: 9.5px; font-family: inherit; }
.door-mark { fill: var(--bg); stroke: var(--red); stroke-width: 1.5px; }
.seal-mark { fill: var(--bg); stroke: var(--amber); stroke-width: 1.5px; }
.trap-dot { fill: var(--red); }
/* A ring OUTSIDE the box, never a fill: a room you are standing in may also be a
   service, a trap or a Device, and each of those already owns the box itself. */
.here-ring { fill: none; stroke: var(--amber); stroke-width: 2px;
  stroke-dasharray: 5 3; }
.here-who { fill: var(--amber); font-size: 10px; font-weight: 700;
  text-anchor: middle; paint-order: stroke; stroke: var(--bg);
  stroke-width: 3px; }
.device-dot { fill: var(--amber); }
.vbadge { fill: var(--muted); font-size: 10px; font-family: inherit; }
@media (max-width: 860px) {
  main { flex-direction: column; }
  aside { flex: 1 1 auto; width: 100%; }
}
`;

/** The client-side half: swap levels, and show a room when one is clicked. */
const SCRIPT = `
var groups = DATA.groups, rooms = DATA.rooms, levels = DATA.levels;
var areaSel = document.getElementById('area'),
    levelSel = document.getElementById('level'),
    stats = document.getElementById('stats'),
    resetBtn = document.getElementById('reset'),
    panel = document.getElementById('panel');

// ---------------------------------------------------------------------------
// Positions. DATA.home is where the layout pass put each room; 'pos' is where it
// is now, which the reader can change by dragging. A room id is 'area/slug', so
// the level a room belongs to is the part before the slash -- no lookup needed.
var pos = {}, shown = null;
for (var id in DATA.home) pos[id] = [DATA.home[id][0], DATA.home[id][1]];

function levelOf(id) { return id.slice(0, id.indexOf('/')); }
function storeKey(slug) { return 'ta-map-layout:' + slug; }

// Saved arrangements are a convenience, not data: a browser with storage blocked
// or cleared must still draw the map, so every read and write is guarded and a
// failure is simply ignored.
function loadSaved(slug) {
  try {
    var raw = localStorage.getItem(storeKey(slug));
    if (!raw) return;
    var saved = JSON.parse(raw);
    for (var id in saved) if (pos[id]) pos[id] = inside(id, saved[id]);
  } catch (e) { /* no storage, or nonsense in it */ }
}
// A room pushed past the edge of its level is CLIPPED by the SVG, not merely
// moved: the box stops being drawn, so there is nothing left to click, to drag
// back or to reach with the arrow keys -- all that shows is the line to it
// running off the pane with nothing on the end. The only way back used to be
// "Reset this level", which throws away the whole arrangement to rescue one
// room. So a position is held inside the level's own viewBox, on load as well
// as while moving: an arrangement saved before this existed repairs itself on
// the next visit, with every other room left where the reader put it.
var EDGE = 21;                        // half a box, so an edge room stays whole

function inside(id, p) {
  // The viewBox is asked of the room's own box, the same way a drag asks for
  // the scale -- the page has no table of level sizes, and the box is already
  // in hand here.
  var el = (ownEls[id] || [])[0], svg = el ? closestOf(el, 'svg') : null;
  var vb = svg ? (svg.getAttribute('viewBox') || '').split(/[\\s,]+/) : null;
  if (!vb || !(Number(vb[2]) > 0) || !(Number(vb[3]) > 0)) return p;
  return [Math.max(EDGE, Math.min(p[0], Number(vb[2]) - EDGE)),
          Math.max(EDGE, Math.min(p[1], Number(vb[3]) - EDGE))];
}

function save(slug) {
  var out = {};
  for (var id in pos) if (levelOf(id) === slug) out[id] = pos[id];
  try { localStorage.setItem(storeKey(slug), JSON.stringify(out)); } catch (e) {}
}

// Elements are tagged with the room(s) they belong to: one 'data-a' for a room's
// own box and stubs, 'data-a' + 'data-b' for the pieces that span two rooms. The
// index is built once so a drag is not a query per frame.
var ownEls = {}, linkEls = {};
function index() {
  ownEls = {}; linkEls = {};
  document.querySelectorAll('[data-a]').forEach(function (el) {
    var a = el.getAttribute('data-a'), b = el.getAttribute('data-b');
    if (b == null) { (ownEls[a] = ownEls[a] || []).push(el); return; }
    (linkEls[a] = linkEls[a] || []).push(el);
    (linkEls[b] = linkEls[b] || []).push(el);
  });
}

/** Move everything that depends on where room 'id' is. */
function place(id) {
  var p = pos[id];
  (ownEls[id] || []).forEach(function (el) {
    el.setAttribute('transform', 'translate(' + p[0] + ',' + p[1] + ')');
  });
  (linkEls[id] || []).forEach(function (el) {
    var a = pos[el.getAttribute('data-a')], b = pos[el.getAttribute('data-b')];
    if (!a || !b) return;
    if (el.tagName === 'line') {
      el.setAttribute('x1', a[0]); el.setAttribute('y1', a[1]);
      el.setAttribute('x2', b[0]); el.setAttribute('y2', b[1]);
    } else {
      // Translated to the midpoint, and -- for a one-way arrow -- turned to face
      // the way the line now runs. Without this a dragged room leaves the arrow
      // aimed wherever the room used to be, which is worse than no arrow.
      var t = 'translate(' + (a[0] + b[0]) / 2 + ',' + (a[1] + b[1]) / 2 + ')';
      if (el.getAttribute('data-rot') !== null) {
        t += ' rotate(' + (Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI) + ')';
      }
      el.setAttribute('transform', t);
    }
  });
}

function fillLevels(areaName, want) {
  var g = groups.filter(function (x) { return x.area === areaName; })[0];
  levelSel.innerHTML = '';
  g.levels.forEach(function (l) {
    var o = document.createElement('option');
    o.value = l.slug; o.textContent = l.level;
    levelSel.appendChild(o);
  });
  levelSel.value = want && g.levels.some(function (l) { return l.slug === want; })
    ? want : g.levels[0].slug;
  levelSel.disabled = g.levels.length < 2;
}

function show(slug) {
  var seen = null;
  document.querySelectorAll('[data-level]').forEach(function (el) {
    var on = el.getAttribute('data-level') === slug;
    el.hidden = !on;
    if (on) seen = el;
  });
  if (!seen) return;
  var s = levels[slug];
  stats.innerHTML = '<b>' + s.rooms + '</b> rooms'
    + (s.frontiers ? ' · <b>' + s.frontiers + '</b> unwalked' : '')
    + (s.leaving ? ' · <b>' + s.leaving + '</b> ways out' : '')
    + (s.devices ? ' · <b>' + s.devices + '</b> devices' : '')
    + (s.traps ? ' · <b>' + s.traps + '</b> traps' : '')
    + (s.doors ? ' · <b>' + s.doors + '</b> doors' : '')
    + (s.seals ? ' · <b>' + s.seals + '</b> seals' : '')
    + (s.skewed ? ' · <b>' + s.skewed + '</b> lines point the wrong way' : '')
    + (s.oneWay ? ' · <b>' + s.oneWay + '</b> one way' : '');
  if (location.hash.slice(1) !== slug) history.replaceState(null, '', '#' + slug);
  shown = slug;
  index();
  loadSaved(slug);
  for (var id in pos) if (levelOf(id) === slug) place(id);
  select(null);
}

function select(id) {
  document.querySelectorAll('.box.sel').forEach(function (el) { el.classList.remove('sel'); });
  if (!id) {
    panel.innerHTML = '<h2>Room</h2><p class="none">Click a room.</p>';
    return;
  }
  document.querySelectorAll('[data-id="' + id + '"]').forEach(function (el) {
    el.classList.add('sel');
  });
  var r = rooms[id];
  var html = '<h2>Room</h2><div class="pid">' + id + '</div>'
    + '<div class="pname">' + r.name + '</div>';
  if (r.description) html += '<p class="pdesc">' + r.description + '</p>';
  html += '<dl>';
  Object.keys(r.exits).forEach(function (dir) {
    var ex = r.exits[dir];
    var gate = ex.seal ? ' <span class="gate">(' + ex.seal + ')</span>'
      : ex.door ? ' <span class="gate">(' + ex.door + ')</span>' : '';
    html += '<dt>' + dir + '</dt><dd>'
      + (ex.to ? ex.to : '<span class="none">never walked</span>') + gate + '</dd>';
  });
  html += '</dl>';
  if (r.trap) html += '<ul><li class="trap">trap: ' + r.trap + '</li></ul>';
  if (r.devices && r.devices.length) {
    html += '<ul>';
    r.devices.forEach(function (d) {
      html += '<li><code>' + d.command + '</code> — ' + d.effect
        + (d.repeats ? ', ' + d.repeats : '') + (d.note ? '<br>' + d.note : '') + '</li>';
    });
    html += '</ul>';
  }
  panel.innerHTML = html;
}

areaSel.addEventListener('change', function () {
  fillLevels(areaSel.value, null);
  show(levelSel.value);
});
levelSel.addEventListener('change', function () { show(levelSel.value); });
// ---------------------------------------------------------------------------
// Dragging. The map's layout is derived from topology, so it is one valid drawing
// of the level among many -- being able to pull a room where you expect it is how
// you argue with it.
//
// Pointer movement is in CSS pixels and the SVG is scaled to its pane, so every
// delta is converted through the viewBox before it moves anything.
var drag = null;
var CLICK_SLOP = 4;                   // px of travel still counted as a click

function userScale(svg) {
  var vb = (svg.getAttribute('viewBox') || '').split(/[\s,]+/);
  var box = svg.getBoundingClientRect ? svg.getBoundingClientRect() : null;
  if (!vb[2] || !box || !box.width) return 1;
  return Number(vb[2]) / box.width;
}

function closestOf(el, sel) { return el && el.closest ? el.closest(sel) : null; }

document.addEventListener('pointerdown', function (e) {
  var box = closestOf(e.target, '.box');
  if (!box) return;
  var svg = closestOf(box, 'svg');
  drag = { id: box.getAttribute('data-id'), box: box, travelled: 0,
           k: svg ? userScale(svg) : 1, x: e.clientX, y: e.clientY };
  box.classList.add('dragging');
  // Capture, so a fast drag that outruns the box keeps sending us moves.
  if (box.setPointerCapture && e.pointerId != null) {
    try { box.setPointerCapture(e.pointerId); } catch (err) {}
  }
  if (e.preventDefault) e.preventDefault();
});

document.addEventListener('pointermove', function (e) {
  if (!drag) return;
  var dx = (e.clientX - drag.x) * drag.k, dy = (e.clientY - drag.y) * drag.k;
  drag.x = e.clientX; drag.y = e.clientY;
  drag.travelled += Math.abs(dx) + Math.abs(dy);
  var p = pos[drag.id];
  pos[drag.id] = inside(drag.id, [p[0] + dx, p[1] + dy]);
  place(drag.id);
});

document.addEventListener('pointerup', function () {
  if (!drag) return;
  drag.box.classList.remove('dragging');
  // A press that went nowhere is a click: show the room. Selecting on pointerup
  // rather than on click is what keeps a drag from also opening the panel.
  if (drag.travelled <= CLICK_SLOP) select(drag.id);
  else if (shown) save(shown);
  drag = null;
});

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape') { select(null); return; }
  var box = closestOf(e.target, '.box');
  if (!box) return;
  var id = box.getAttribute('data-id');
  if (e.key === 'Enter' || e.key === ' ') { select(id); return; }
  var step = { ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] }[e.key];
  if (!step) return;
  var far = e.shiftKey ? 10 : 2;
  pos[id] = inside(id, [pos[id][0] + step[0] * far, pos[id][1] + step[1] * far]);
  place(id);
  if (shown) save(shown);
  if (e.preventDefault) e.preventDefault();
});

resetBtn.addEventListener('click', function () {
  if (!shown) return;
  try { localStorage.removeItem(storeKey(shown)); } catch (e) {}
  for (var id in pos) {
    if (levelOf(id) !== shown) continue;
    pos[id] = [DATA.home[id][0], DATA.home[id][1]];
    place(id);
  }
});

// A hash names a level, so a link can point at one: map.html#stoneworks-level-2
var want = location.hash.slice(1);
var start = levels[want] ? want : groups[0].levels[0].slug;
var owner = groups.filter(function (g) {
  return g.levels.some(function (l) { return l.slug === start; });
})[0];
areaSel.value = owner.area;
fillLevels(owner.area, start);
show(start);
`;

/**
 * JSON safe to drop inside a `<script>`. A literal `</script>` anywhere in the
 * data ends the element early and the rest of the page becomes visible text, and
 * U+2028/9 are line terminators to a JS parser but not to JSON. Room prose has
 * none of these today; a page that breaks the moment a description does is still
 * a page that breaks.
 */
function jsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

export function buildPage(
  areas: Area[],
  /** Characters last seen per room id; empty when map/players.json is absent. */
  playersByRoom: Map<string, string[]> = new Map(),
): string {
  const bySlug = new Map(areas.map(a => [a.area, a]));
  const nameOf = (slug: string) => bySlug.get(slug)?.name ?? slug;
  const groups = groupAreas(areas.map(a => ({ area: a.area, name: a.name })));

  // Every room in the world, so the panel can name a room in another area and a
  // link out of a level can say where it lands.
  const rooms: Record<string, unknown> = {};
  for (const a of areas) {
    for (const r of a.rooms) {
      const exits: Record<string, unknown> = {};
      for (const [dir, ex] of Object.entries(r.exits) as [string, Exit][]) {
        exits[dir] = {
          to: ex.to,
          ...(ex.door ? { door: ex.door.material + ' door'
            + (ex.door.key ? `, ${ex.door.key} key` : '') } : {}),
          ...(ex.sealedBy ? { seal: `\`${ex.sealedBy.command}\` in ${ex.sealedBy.room}` } : {}),
        };
      }
      rooms[r.id] = {
        name: r.name, area: a.name, exits,
        ...(r.description ? { description: r.description } : {}),
        ...(r.trap ? { trap: r.trap.type } : {}),
        ...(r.devices?.length ? { devices: r.devices } : {}),
      };
    }
  }

  const levels: Record<string, LevelStats> = {};
  const home: Record<string, [number, number]> = {};
  const panes: string[] = [];
  for (const g of groups) {
    for (const ref of g.levels) {
      const level = renderLevel(bySlug.get(ref.slug)!, nameOf, playersByRoom);
      levels[ref.slug] = level.stats;
      Object.assign(home, level.home);
      panes.push(`<div class="canvas" data-level="${esc(ref.slug)}" hidden>${level.svg}</div>`);
    }
  }

  const totals = areas.reduce((n, a) => n + a.rooms.length, 0);
  const option = (g: Group) => `<option value="${esc(g.area)}">${esc(g.area)}</option>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tele-Arena — the mapped world</title>
<style>${CSS}</style>
</head>
<body>
<header>
  <h1>Tele-Arena <span>— the mapped world</span></h1>
  <div class="sub">${areas.length} areas, ${totals} rooms, built from
    <code>map/areas/*.json</code> by <code>just draw-map-as-html</code>.
    Topology is the truth here: boxes are placed by walking exits, never from
    stored coordinates, so distances mean nothing and a line means you can walk
    it.</div>
</header>
<div class="picker">
  <div><label for="area">Area</label>
    <select id="area">${groups.map(option).join('')}</select></div>
  <div><label for="level">Level</label><select id="level"></select></div>
  <div><label for="reset">Layout</label>
    <button class="ghost" id="reset" type="button">Reset this level</button></div>
  <div class="stats" id="stats"></div>
</div>
<div class="hint" style="padding: 0 1.5rem 0.75rem">Drag a room to move it — its exits
  follow. Arrow keys nudge the room you have selected. Your arrangement is kept in this
  browser, per level, until you reset it.</div>
<main>
${panes.join('\n')}
<aside>
  <div class="card" id="panel"><h2>Room</h2><p class="none">Click a room.</p></div>
  <div class="card"><h2>Legend</h2><div class="legend">
${LEGEND.map(([sw, text]) => `    <div>${sw}<span>${esc(text)}</span></div>`).join('\n')}
  </div></div>
</aside>
</main>
<script>
var DATA = ${jsonForScript({ groups, rooms, levels, home })};
${SCRIPT}
</script>
</body>
</html>
`;
}

/** Read the checked-in export. No database anywhere in this file. */
export async function readAreas(dir = 'map'): Promise<Area[]> {
  const index = JSON.parse(await Bun.file(`${dir}/index.json`).text()) as
    { areas: { area: string; file: string }[] };
  const out: Area[] = [];
  for (const entry of index.areas) {
    out.push(JSON.parse(await Bun.file(`${dir}/${entry.file}`).text()) as Area);
  }
  return out;
}

/**
 * Characters last seen per room, from map/players.json. That file is written by
 * `bun export.ts` and is untracked, so it is routinely absent -- a fresh clone,
 * the VPS, anyone who has not exported. Absent or malformed, the map simply
 * draws no mark, which is why this swallows rather than throws.
 */
export async function readPlayers(dir = 'map'): Promise<Map<string, string[]>> {
  const byRoom = new Map<string, string[]>();
  try {
    const raw = JSON.parse(await Bun.file(`${dir}/players.json`).text()) as
      { players?: { player: string; room: string }[] };
    for (const p of raw.players ?? []) {
      if (!p?.room || !p?.player) continue;
      if (!byRoom.has(p.room)) byRoom.set(p.room, []);
      byRoom.get(p.room)!.push(p.player);
    }
  } catch { /* no file, or not JSON: no marks */ }
  return byRoom;
}

if (import.meta.main) {
  const areas = await readAreas();
  const players = await readPlayers();
  const html = buildPage(areas, players);
  await Bun.write('map.html', html);
  const rooms = areas.reduce((n, a) => n + a.rooms.length, 0);
  const marked = [...players.values()].reduce((n, v) => n + v.length, 0);
  console.log(`site: wrote map.html — ${areas.length} areas, ${rooms} rooms,`
    + ` ${marked} character${marked === 1 ? '' : 's'} marked,`
    + ` ${(html.length / 1024).toFixed(0)}KB`);
}
