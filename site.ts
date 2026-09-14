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

import { placeRooms, SERVICES, DRAWN, type Room as GridRoom, type Exit as GridExit } from './map';
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
};
export type LevelSvg = { svg: string; stats: LevelStats; width: number; height: number };

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
 * Draw one level. Edges first so boxes sit on top of them, then the stubs that
 * mark where nobody has walked, then the boxes.
 *
 * Every exit in the JSON ends up visible as one of four things, because an exit
 * that renders as nothing is indistinguishable from an exit we failed to record:
 * a line to another box on this level, a dashed stub with a label (it leaves the
 * area), a dashed stub with an open circle (`to: null`, the frontier), or a
 * ▲/▼ badge (`u`/`d`, which have no compass offset to draw along).
 */
export function renderLevel(
  area: Area, nameOf: (areaSlug: string) => string,
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

  const cells = [...pos.values()];
  const minC = Math.min(...cells.map(p => p.c)), maxC = Math.max(...cells.map(p => p.c));
  const minR = Math.min(...cells.map(p => p.r)), maxR = Math.max(...cells.map(p => p.r));
  const width = (maxC - minC) * CELL_W + BOX_W + PAD * 2;
  const height = (maxR - minR) * CELL_H + BOX_H + PAD * 2;
  const cx = (id: number) => PAD + (pos.get(id)!.c - minC) * CELL_W + BOX_W / 2;
  const cy = (id: number) => PAD + (pos.get(id)!.r - minR) * CELL_H + BOX_H / 2;

  const stats: LevelStats = {
    rooms: area.rooms.length, frontiers: 0, devices: 0, traps: 0,
    doors: 0, seals: 0, leaving: 0,
  };
  const edges: string[] = [], stubs: string[] = [], boxes: string[] = [], marks: string[] = [];
  const seen = new Set<string>();

  for (const room of area.rooms) {
    const from = ids.get(room.id)!;
    for (const [dir, ex] of Object.entries(room.exits) as [string, Exit][]) {
      const gate = ex.sealedBy ? 'seal' : ex.door ? 'door' : null;
      const title = ex.sealedBy
        ? `${dir}: sealed, opened by \`${ex.sealedBy.command}\` in ${ex.sealedBy.room}`
        : ex.door
          ? `${dir}: ${ex.door.material} door${ex.door.key ? `, ${ex.door.key} key` : ''}`
          : `${dir}`;

      // Leaves the level, or nobody has walked it: a stub either way, since
      // there is no second box to draw a line to.
      if (ex.to == null || !ids.has(ex.to)) {
        const o = COMPASS[dir] ?? [0, dir === 'u' ? -1 : 1];
        const len = ex.to == null ? STUB : STUB + 2;
        const x1 = cx(from) + o[0] * (BOX_W / 2), y1 = cy(from) + o[1] * (BOX_H / 2);
        const x2 = x1 + o[0] * len, y2 = y1 + o[1] * len;
        if (ex.to == null) {
          stats.frontiers++;
          stubs.push(`<line class="stub" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`
            + `<circle class="frontier" cx="${x2}" cy="${y2}" r="4">`
            + `<title>${esc(dir)}: exit known, never walked</title></circle>`);
        } else {
          stats.leaving++;
          const label = awayLabel(area.name, nameOf(ex.to.split('/')[0]));
          const anchor = o[0] > 0 ? 'start' : o[0] < 0 ? 'end' : 'middle';
          stubs.push(`<line class="away" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`
            + `<text class="away-label" x="${x2 + o[0] * 4}" y="${y2 + (o[1] >= 0 ? 11 : -5)}"`
            + ` text-anchor="${anchor}">${esc(label)}</text>`
            + `<title>${esc(dir)} to ${esc(ex.to)}</title>`);
        }
        if (gate) marks.push(gateMark(gate, (x1 + x2) / 2, (y1 + y2) / 2, title));
        continue;
      }

      const to = ids.get(ex.to)!;
      // u/d carry no direction on a flat drawing, so they get a badge on the box
      // rather than a line that would lie about which way the room lies.
      if (dir === 'u' || dir === 'd') {
        const up = dir === 'u';
        marks.push(`<text class="vbadge" x="${cx(from) + BOX_W / 2 - 5}"`
          + ` y="${cy(from) + (up ? -BOX_H / 2 + 9 : BOX_H / 2 - 2)}">${up ? '▲' : '▼'}`
          + `<title>${esc(dir)} to ${esc(ex.to)}</title></text>`);
        continue;
      }

      // One line per CONNECTION, not per direction: `hall --e--> corridor` and
      // `corridor --w--> hall` are the same doorway, and drawing both doubles
      // every stroke and leaves two overlapping hover targets. Keying on the
      // direction PAIR rather than on the two rooms is what keeps a second,
      // different connection between the same two rooms (a room reachable both
      // `n` and `ne`, say) from vanishing instead -- no area has one today, and
      // if one appears the two lines will coincide, which is a cosmetic problem
      // where dropping an exit would be a lie.
      const key = [Math.min(from, to), Math.max(from, to)].join('-')
        + ':' + [dir, REVERSE[dir] ?? dir].sort().join('-');
      if (seen.has(key)) continue;
      seen.add(key);
      edges.push(`<line class="edge" x1="${cx(from)}" y1="${cy(from)}"`
        + ` x2="${cx(to)}" y2="${cy(to)}"><title>${esc(title)}</title></line>`);
      if (gate) {
        if (gate === 'seal') stats.seals++; else stats.doors++;
        marks.push(gateMark(gate, (cx(from) + cx(to)) / 2, (cy(from) + cy(to)) / 2, title));
      }
    }
  }

  for (const room of area.rooms) {
    const id = ids.get(room.id)!;
    const x = cx(id) - BOX_W / 2, y = cy(id) - BOX_H / 2;
    const classes = ['box'];
    if (room.trap) { classes.push('trapped'); stats.traps++; }
    if (room.devices?.length) { classes.push('device'); stats.devices += room.devices.length; }
    if (SERVICES[room.name]) classes.push('service');
    if (room.id === origin) classes.push('origin');
    const bits = [room.id, room.name];
    if (room.trap) bits.push(`trap: ${room.trap.type}`);
    for (const d of room.devices ?? []) bits.push(`\`${d.command}\` (${d.effect})`);
    boxes.push(`<g class="${classes.join(' ')}" data-id="${esc(room.id)}" tabindex="0">`
      + `<rect x="${x}" y="${y}" width="${BOX_W}" height="${BOX_H}" rx="5"/>`
      + `<text class="label" x="${cx(id)}" y="${cy(id) + 4}">${esc(boxLabel(room))}</text>`
      + `<title>${esc(bits.join('\n'))}</title></g>`);
    if (room.trap) {
      marks.push(`<circle class="trap-dot" cx="${x + 5}" cy="${y + 5}" r="3.5"/>`);
    }
    if (room.devices?.length) {
      marks.push(`<circle class="device-dot" cx="${x + BOX_W - 5}" cy="${y + 5}" r="3.5"/>`);
    }
  }

  const svg = `<svg class="level" viewBox="0 0 ${width} ${height}"`
    + ` style="max-width:${width}px" role="img"`
    + ` aria-label="${esc(area.name)}">\n`
    + edges.join('\n') + '\n' + stubs.join('\n') + '\n'
    + boxes.join('\n') + '\n' + marks.join('\n') + '\n</svg>';
  return { svg, stats, width, height };
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
  ['<svg viewBox="0 0 20 14"><line class="edge" x1="1" y1="7" x2="19" y2="7"/></svg>',
    'a walked exit, both ways'],
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
];

const CSS = `
:root {
  --bg: #0d1117; --surface: #161b22; --raised: #21262d; --border: #30363d;
  --text: #e6edf3; --muted: #8b949e; --blue: #58a6ff; --amber: #e3b341;
  --red: #f85149; --green: #3fb950;
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
svg.level { display: block; width: 100%; height: auto; }
.box rect { fill: var(--raised); stroke: #4d5560; stroke-width: 1.5px; }
.box .label { fill: var(--muted); font-size: 11px; text-anchor: middle;
  font-family: inherit; pointer-events: none; }
.box { cursor: pointer; }
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
.away-label { fill: var(--blue); font-size: 9.5px; font-family: inherit; }
.door-mark { fill: var(--bg); stroke: var(--red); stroke-width: 1.5px; }
.seal-mark { fill: var(--bg); stroke: var(--amber); stroke-width: 1.5px; }
.trap-dot { fill: var(--red); }
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
    panel = document.getElementById('panel');

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
    + (s.seals ? ' · <b>' + s.seals + '</b> seals' : '');
  if (location.hash.slice(1) !== slug) history.replaceState(null, '', '#' + slug);
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
document.addEventListener('click', function (e) {
  var box = e.target && e.target.closest ? e.target.closest('.box') : null;
  if (box) select(box.getAttribute('data-id'));
});
document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape') select(null);
  var box = e.target && e.target.closest ? e.target.closest('.box') : null;
  if (box && (e.key === 'Enter' || e.key === ' ')) select(box.getAttribute('data-id'));
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

export function buildPage(areas: Area[]): string {
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
  const panes: string[] = [];
  for (const g of groups) {
    for (const ref of g.levels) {
      const { svg, stats } = renderLevel(bySlug.get(ref.slug)!, nameOf);
      levels[ref.slug] = stats;
      panes.push(`<div class="canvas" data-level="${esc(ref.slug)}" hidden>${svg}</div>`);
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
  <div class="stats" id="stats"></div>
</div>
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
var DATA = ${jsonForScript({ groups, rooms, levels })};
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

if (import.meta.main) {
  const areas = await readAreas();
  const html = buildPage(areas);
  await Bun.write('map.html', html);
  const rooms = areas.reduce((n, a) => n + a.rooms.length, 0);
  console.log(`site: wrote map.html — ${areas.length} areas, ${rooms} rooms,`
    + ` ${(html.length / 1024).toFixed(0)}KB`);
}
