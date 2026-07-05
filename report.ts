import { Database } from "bun:sqlite";
import { writeFileSync } from "fs";
import { join } from "path";

const DB_PATH = join(process.cwd(), "tele-arena.db");
const OUTPUT_PATH = join(process.cwd(), "report.html");

const db = new Database(DB_PATH, { readonly: true });

// ── Raw queries ────────────────────────────────────────────────────────────────

// The room-graph schema (areas + the integer-keyed rooms) only exists after the
// ta_db migration has run, which happens when baud loads the script. If you run
// `just report` before that first launch, those tables/columns aren't there yet
// — treat the map as empty rather than crashing with a raw SQLiteError.
function hasTable(name: string): boolean {
  return db.prepare(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?"
  ).get(name) != null;
}
const roomGraphReady = hasTable("areas") && hasTable("rooms");

const rooms = roomGraphReady ? db.prepare(`
  SELECT r.id, r.slug, r.name, r.description, r.visits, r.first_visited, r.area_id,
         a.slug AS area_slug, a.name AS area_name
  FROM rooms r
  LEFT JOIN areas a ON a.id = r.area_id
  ORDER BY r.id
`).all() as any[] : [];

const areas = roomGraphReady
  ? db.prepare(`SELECT id, slug, name FROM areas ORDER BY id`).all() as any[]
  : [];

const exits = roomGraphReady ? db.prepare(`
  SELECT e.from_id, e.direction, e.to_id, t.slug AS to_slug
  FROM room_exits e
  LEFT JOIN rooms t ON t.id = e.to_id
  ORDER BY e.from_id, e.direction
`).all() as any[] : [];

// direction -> "dir → destslug" strings, grouped by source room, for the table.
const exitsByRoom = new Map<number, string[]>();
for (const e of exits) {
  if (!exitsByRoom.has(e.from_id)) exitsByRoom.set(e.from_id, []);
  exitsByRoom.get(e.from_id)!.push(`${e.direction} → ${e.to_slug ?? "?"}`);
}

// Compact node/edge payload for the interactive map (embedded as JSON below).
const graphData = {
  areas: areas.map(a => ({ id: a.id, slug: a.slug, name: a.name })),
  rooms: rooms.map(r => ({ id: r.id, slug: r.slug, area_id: r.area_id })),
  exits: exits.map(e => ({ from: e.from_id, dir: e.direction, to: e.to_id })),
};

const monsters = db.prepare(`
  SELECT name, description, first_seen, encounters
  FROM monsters ORDER BY name
`).all() as any[];

const services = db.prepare(`
  SELECT name, location, cost, uses, first_used FROM services ORDER BY location, name
`).all() as any[];

const statChanges = db.prepare(`
  SELECT stat, from_value, to_value, recorded_at FROM stat_changes ORDER BY recorded_at
`).all() as any[];

const playerAttacks = db.prepare(`
  SELECT monster, outcome, damage, recorded_at FROM player_attacks ORDER BY recorded_at
`).all() as any[];

const monsterAttacks = db.prepare(`
  SELECT monster, outcome, damage, recorded_at FROM monster_attacks ORDER BY recorded_at
`).all() as any[];

const loot = db.prepare(`
  SELECT monster, gold, recorded_at FROM monster_loot ORDER BY recorded_at
`).all() as any[];

const itemDrops = db.prepare(`
  SELECT monster, item, recorded_at FROM item_drops ORDER BY recorded_at
`).all() as any[];

const playerSpells = db.prepare(`
  SELECT
    spell,
    target,
    COUNT(*) FILTER (WHERE outcome = 'hit')    as hits,
    COUNT(*) FILTER (WHERE outcome = 'fizzle') as fizzles,
    COUNT(*) FILTER (WHERE outcome = 'resist') as resists,
    COUNT(*)                                   as total,
    ROUND(100.0 * COUNT(*) FILTER (WHERE outcome = 'hit') / COUNT(*), 1) as hit_pct,
    ROUND(AVG(amount) FILTER (WHERE outcome = 'hit'), 1) as avg_amount,
    MIN(amount) FILTER (WHERE outcome = 'hit') as min_amount,
    MAX(amount) FILTER (WHERE outcome = 'hit') as max_amount
  FROM player_spells
  GROUP BY spell, target
  ORDER BY spell, total DESC
`).all() as any[];

// ── Combat summary (player attacks per monster) ────────────────────────────────

type CombatRow = { hits: number; misses: number; dodges: number; totalDmg: number; maxDmg: number };
const combatByMonster = new Map<string, CombatRow>();

for (const a of playerAttacks) {
  if (!combatByMonster.has(a.monster)) {
    combatByMonster.set(a.monster, { hits: 0, misses: 0, dodges: 0, totalDmg: 0, maxDmg: 0 });
  }
  const row = combatByMonster.get(a.monster)!;
  if (a.outcome === "hit") { row.hits++; row.totalDmg += a.damage ?? 0; row.maxDmg = Math.max(row.maxDmg, a.damage ?? 0); }
  else if (a.outcome === "miss") row.misses++;
  else if (a.outcome === "dodge") row.dodges++;
}

// ── Damage taken per monster ───────────────────────────────────────────────────

type TakenRow = { hits: number; misses: number; glanced: number; totalDmg: number; maxDmg: number };
const takenByMonster = new Map<string, TakenRow>();

for (const a of monsterAttacks) {
  if (!takenByMonster.has(a.monster)) {
    takenByMonster.set(a.monster, { hits: 0, misses: 0, glanced: 0, totalDmg: 0, maxDmg: 0 });
  }
  const row = takenByMonster.get(a.monster)!;
  if (a.outcome === "hit") { row.hits++; row.totalDmg += a.damage ?? 0; row.maxDmg = Math.max(row.maxDmg, a.damage ?? 0); }
  else if (a.outcome === "miss") row.misses++;
  else if (a.outcome === "glanced") row.glanced++;
}

// ── Loot summary ──────────────────────────────────────────────────────────────

type LootRow = { kills: number; drops: number; totalGold: number };
const lootByMonster = new Map<string, LootRow>();

for (const l of loot) {
  if (!lootByMonster.has(l.monster)) {
    lootByMonster.set(l.monster, { kills: 0, drops: 0, totalGold: 0 });
  }
  const row = lootByMonster.get(l.monster)!;
  row.kills++;
  if (l.gold > 0) { row.drops++; row.totalGold += l.gold; }
}

// ── HP estimates ──────────────────────────────────────────────────────────────
// For each kill event, sum player hit damage between previous kill and this kill
// for the same monster.

type HpRow = { fights: number[]; };
const hpByMonster = new Map<string, HpRow>();
const lastKillTime = new Map<string, string>();

for (const kill of loot) {
  const monster = kill.monster;
  const killTime = kill.recorded_at;
  const prevTime = lastKillTime.get(monster) ?? "1970-01-01T00:00:00";

  const damageInFight = (playerAttacks as any[])
    .filter(a => a.monster === monster && a.outcome === "hit" && a.recorded_at > prevTime && a.recorded_at <= killTime)
    .reduce((sum: number, a: any) => sum + (a.damage ?? 0), 0);

  if (damageInFight > 0) {
    if (!hpByMonster.has(monster)) hpByMonster.set(monster, { fights: [] });
    hpByMonster.get(monster)!.fights.push(damageInFight);
  }

  lastKillTime.set(monster, killTime);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function pct(n: number, d: number) { return d === 0 ? "—" : Math.round((n / d) * 100) + "%"; }
function avg(n: number, d: number) { return d === 0 ? "—" : (n / d).toFixed(1); }
function esc(s: string) { return (s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }

function table(headers: string[], rows: (string | number)[][], opts: { alignRight?: number[] } = {}) {
  const ths = headers.map((h, i) => `<th${opts.alignRight?.includes(i) ? ' class="r"' : ""}>${h}</th>`).join("");
  const trs = rows.map(row =>
    "<tr>" + row.map((cell, i) =>
      `<td${opts.alignRight?.includes(i) ? ' class="r"' : ""}>${cell ?? "—"}</td>`
    ).join("") + "</tr>"
  ).join("\n");
  return `<table><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table>`;
}

// ── All monsters that appear in any table ─────────────────────────────────────

const allMonsters = [...new Set([
  ...combatByMonster.keys(),
  ...takenByMonster.keys(),
  ...lootByMonster.keys(),
  ...hpByMonster.keys(),
])].filter(m => m !== "unknown").sort();

// ── Build HTML sections ───────────────────────────────────────────────────────

const generatedAt = new Date().toLocaleString();

const combatRows = allMonsters.map(m => {
  const c = combatByMonster.get(m);
  const total = (c?.hits ?? 0) + (c?.misses ?? 0) + (c?.dodges ?? 0);
  return [
    esc(m),
    total || "—",
    c?.hits ?? "—",
    c?.misses ?? "—",
    c?.dodges ?? "—",
    pct(c?.hits ?? 0, total),
    c?.totalDmg ?? "—",
    avg(c?.totalDmg ?? 0, c?.hits ?? 0),
    c?.maxDmg ?? "—",
  ];
});

const hpRows = allMonsters
  .filter(m => hpByMonster.has(m))
  .map(m => {
    const f = hpByMonster.get(m)!.fights;
    const min = Math.min(...f);
    const max = Math.max(...f);
    const mean = (f.reduce((a, b) => a + b, 0) / f.length).toFixed(0);
    return [esc(m), min, max, mean, f.length, f.join(", ")];
  });

const takenRows = allMonsters
  .filter(m => takenByMonster.has(m))
  .map(m => {
    const t = takenByMonster.get(m)!;
    const total = t.hits + t.misses + t.glanced;
    return [esc(m), total || "—", t.hits, t.misses, t.glanced, pct(t.hits, total), avg(t.totalDmg, t.hits), t.maxDmg || "—"];
  });

const lootRows = allMonsters
  .filter(m => lootByMonster.has(m))
  .map(m => {
    const l = lootByMonster.get(m)!;
    return [esc(m), l.kills, l.drops, pct(l.drops, l.kills), l.totalGold, avg(l.totalGold, l.drops)];
  });

const roomRows = rooms.map(r => [
  esc(r.slug),
  esc(r.name),
  esc(r.area_slug ?? "—"),
  r.visits,
  r.first_visited?.slice(0,10) ?? "—",
  esc((exitsByRoom.get(r.id) ?? []).join(", ") || "none"),
]);

const serviceRows = services.map(s => [esc(s.name), esc(s.location), s.cost != null ? s.cost + " gp" : "—", s.uses]);

const statRows = statChanges.map(s => [esc(s.stat), s.from_value, s.to_value, s.recorded_at?.slice(0,10) ?? "—"]);

const monsterCards = monsters.map(m => `
  <div class="card">
    <h3>${esc(m.name)}</h3>
    <p class="desc">${esc(m.description ?? "(no description yet)")}</p>
    <p class="meta">First seen: ${m.first_seen?.slice(0,10) ?? "—"} · Encounters: ${m.encounters}</p>
  </div>`).join("\n");

const roomCards = rooms.map(r => {
  const rx = exitsByRoom.get(r.id);
  return `
  <div class="card">
    <h3>${esc(r.slug)}</h3>
    <p class="desc">${esc(r.description || "(no description yet)")}</p>
    <p class="meta">Area: ${esc(r.area_slug ?? "—")} · Visits: ${r.visits}${rx ? ` · Exits: ${esc(rx.join(", "))}` : ""}</p>
  </div>`;
}).join("\n");

// ── Full HTML ─────────────────────────────────────────────────────────────────

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tele-Arena Report</title>
<style>
  :root { --bg: #0d1117; --surface: #161b22; --border: #30363d; --text: #e6edf3; --muted: #8b949e; --green: #3fb950; --red: #f85149; --yellow: #d29922; --blue: #58a6ff; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: ui-monospace, "Cascadia Code", "Fira Code", monospace; font-size: 14px; line-height: 1.6; padding: 2rem; }
  h1 { font-size: 1.6rem; color: var(--blue); margin-bottom: 0.25rem; }
  h2 { font-size: 1.1rem; color: var(--yellow); margin: 2.5rem 0 0.75rem; border-bottom: 1px solid var(--border); padding-bottom: 0.4rem; }
  h3 { font-size: 0.95rem; color: var(--blue); margin-bottom: 0.25rem; }
  .meta-line { color: var(--muted); font-size: 0.85rem; margin-bottom: 2rem; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; }
  th { background: var(--surface); color: var(--muted); font-weight: 600; text-align: left; padding: 0.4rem 0.75rem; border-bottom: 1px solid var(--border); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.04em; }
  td { padding: 0.35rem 0.75rem; border-bottom: 1px solid var(--border); color: var(--text); }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: var(--surface); }
  th.r, td.r { text-align: right; }
  .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 1rem; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; padding: 1rem; }
  .desc { color: var(--muted); font-size: 0.85rem; margin: 0.4rem 0; line-height: 1.5; }
  .meta { color: var(--muted); font-size: 0.75rem; margin-top: 0.5rem; }
  .note { color: var(--muted); font-size: 0.8rem; margin-bottom: 0.75rem; font-style: italic; }
  .map-wrap { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; margin-bottom: 0.5rem; overflow: hidden; }
  #map { width: 100%; height: 620px; display: block; cursor: grab; touch-action: none; }
  #map text { fill: var(--text); font-size: 11px; pointer-events: none; user-select: none; }
  #map .edge-dir { fill: var(--muted); font-size: 9px; }
  .map-legend { display: flex; flex-wrap: wrap; gap: 0.75rem 1.25rem; margin-bottom: 0.75rem; font-size: 0.8rem; color: var(--muted); }
  .map-legend .swatch { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 0.4rem; vertical-align: middle; }
</style>
</head>
<body>
<h1>Tele-Arena — Pelayo's Field Notes</h1>
<p class="meta-line">Generated ${generatedAt}</p>

<h2>Player Combat</h2>
<p class="note">Attacks made by Pelayo against each monster.</p>
${table(
  ["Monster", "Attacks", "Hits", "Misses", "Dodged", "Hit Rate", "Total Dmg", "Avg/Hit", "Max Hit"],
  combatRows,
  { alignRight: [1,2,3,4,5,6,7,8] }
)}

<h2>HP Estimates</h2>
<p class="note">Total damage dealt per kill. Min/max/avg across observed fights. Higher fight counts = more reliable estimate.</p>
${hpRows.length > 0 ? table(
  ["Monster", "Min HP", "Max HP", "Avg HP", "Fights", "Per-fight damage"],
  hpRows,
  { alignRight: [1,2,3,4] }
) : "<p class='note'>Not enough kill data yet.</p>"}

<h2>Damage Taken</h2>
<p class="note">Attacks made by monsters against Pelayo.</p>
${table(
  ["Monster", "Attacks", "Hits", "Misses", "Glanced", "Hit Rate", "Avg Dmg", "Max Hit"],
  takenRows,
  { alignRight: [1,2,3,4,5,6,7] }
)}

<h2>Loot</h2>
${table(
  ["Monster", "Kills", "Gold Drops", "Drop Rate", "Total Gold", "Avg Gold (when drops)"],
  lootRows,
  { alignRight: [1,2,3,4,5] }
)}

<h2>Item Drops</h2>
${itemDrops.length > 0 ? table(
  ["Monster", "Item", "Date"],
  itemDrops.map(d => [esc(d.monster), esc(d.item), d.recorded_at?.slice(0,10) ?? "—"]),
  {}
) : "<p class='note'>No item drops recorded yet.</p>"}

<h2>World Map</h2>
${!roomGraphReady ? `<p class="note">Room-graph schema not initialized yet — launch baud once to run the migration, then map some rooms.</p>` : ""}
${rooms.length > 0 ? `
<div id="map-legend" class="map-legend"></div>
<div class="map-wrap"><svg id="map"></svg></div>
<p class="note">Position encodes direction — north is up, east is right, diagonals at the corners · scroll to zoom, drag to pan · dashed octagons are known exits not yet walked. (Up/down exits are omitted for now.)</p>
` : ""}
${table(
  ["Room", "Name", "Area", "Visits", "First Visited", "Exits"],
  roomRows,
  { alignRight: [3] }
)}

<h2>Services</h2>
${table(
  ["Service", "Location", "Cost", "Times Used"],
  serviceRows,
  { alignRight: [2,3] }
)}

<h2>Spells</h2>
${playerSpells.length > 0 ? table(
  ["Spell", "Target", "Hits", "Fizzles", "Resists", "Hit%", "Avg", "Min", "Max"],
  playerSpells.map(s => [esc(s.spell), esc(s.target), s.hits, s.fizzles, s.resists, s.hit_pct + "%", s.avg_amount ?? "—", s.min_amount ?? "—", s.max_amount ?? "—"]),
  { alignRight: [2,3,4,5,6,7,8] }
) : "<p class='note'>No spells recorded yet.</p>"}

<h2>Stat Changes</h2>
${statRows.length > 0 ? table(
  ["Stat", "From", "To", "Date"],
  statRows,
  { alignRight: [1,2] }
) : "<p class='note'>No stat changes recorded yet.</p>"}

<h2>Room Encyclopedia</h2>
<div class="cards">
${roomCards || "<p class='note'>No rooms visited yet.</p>"}
</div>

<h2>Monster Encyclopedia</h2>
<div class="cards">
${monsterCards || "<p class='note'>No monster descriptions captured yet.</p>"}
</div>

<script>
(function(){
  var GRAPH = ${JSON.stringify(graphData)};
  var svg = document.getElementById('map');
  if(!svg) return;
  var NS = 'http://www.w3.org/2000/svg';
  var PALETTE = ['#58a6ff','#3fb950','#d29922','#bc8cff','#39c5cf','#ff7b72','#7ee787','#f85149'];
  var areaColor = {};
  GRAPH.areas.forEach(function(a,i){ areaColor[a.id] = PALETTE[i % PALETTE.length]; });

  var legend = document.getElementById('map-legend');
  if(legend){
    GRAPH.areas.forEach(function(a){
      var span = document.createElement('span');
      span.innerHTML = '<span class="swatch" style="background:'+areaColor[a.id]+'"></span>'+a.slug;
      legend.appendChild(span);
    });
    var un = document.createElement('span');
    un.innerHTML = '<span class="swatch" style="background:transparent;border:1px solid var(--muted)"></span>unexplored exit';
    legend.appendChild(un);
  }

  // --- Direction → grid offset (col, row); row increases downward, so n = up. ---
  // Only the 8 compass exits participate in layout; u/d are ignored for now.
  var OFF = { n:[0,-1], s:[0,1], e:[1,0], w:[-1,0], ne:[1,-1], nw:[-1,-1], se:[1,1], sw:[-1,1] };

  var roomById = {};
  GRAPH.rooms.forEach(function(r){ roomById[r.id] = r; });

  // Adjacency from walked (to != null) compass edges; collect stubs (to == null) too.
  var adj = {}, stubs = [];
  GRAPH.rooms.forEach(function(r){ adj[r.id] = []; });
  GRAPH.exits.forEach(function(e){
    if(!OFF[e.dir]) return;                         // skip u/d and anything unexpected
    if(e.to == null){ stubs.push(e); return; }
    if(!roomById[e.from] || !roomById[e.to]) return;
    adj[e.from].push({ dir:e.dir, to:e.to });
  });

  // --- Lay out each connected component on its own integer grid, then tile them. ---
  var seen = {}, components = [];
  GRAPH.rooms.forEach(function(rootRoom){
    if(seen[rootRoom.id]) return;
    var lpos = {}, locc = {};
    function lkey(c,r){ return c+','+r; }
    function lfindFree(c,r){                          // spiral out to nearest empty cell
      if(!(lkey(c,r) in locc)) return [c,r];
      for(var rad=1; rad<400; rad++){
        for(var dc=-rad; dc<=rad; dc++) for(var dr=-rad; dr<=rad; dr++){
          if(Math.max(Math.abs(dc),Math.abs(dr)) !== rad) continue;
          if(!(lkey(c+dc,r+dr) in locc)) return [c+dc,r+dr];
        }
      }
      return [c,r];
    }
    function lplace(id,c,r){ lpos[id]={c:c,r:r}; locc[lkey(c,r)]=id; seen[id]=true; }
    lplace(rootRoom.id, 0, 0);
    var q = [rootRoom.id];
    while(q.length){
      var cur = q.shift(), base = lpos[cur];
      adj[cur].forEach(function(ed){
        if(seen[ed.to]) return;                       // already placed; edge drawn as connector
        var o = OFF[ed.dir], cell = lfindFree(base.c + o[0], base.r + o[1]);
        lplace(ed.to, cell[0], cell[1]);
        q.push(ed.to);
      });
    }
    var ids = Object.keys(lpos), minc=Infinity, maxc=-Infinity, minr=Infinity, maxr=-Infinity;
    ids.forEach(function(id){ var p=lpos[id];
      minc=Math.min(minc,p.c); maxc=Math.max(maxc,p.c);
      minr=Math.min(minr,p.r); maxr=Math.max(maxr,p.r); });
    components.push({ lpos:lpos, ids:ids, minc:minc, maxc:maxc, minr:minr, maxr:maxr });
  });

  // Tile components left-to-right with a gap; produce final global cells.
  var cell = {}, GAP = 2, cursor = 0;
  components.forEach(function(cp){
    cp.ids.forEach(function(id){ var p = cp.lpos[id];
      cell[id] = { c: cursor + (p.c - cp.minc), r: (p.r - cp.minr) }; });
    cursor += (cp.maxc - cp.minc) + 1 + GAP;
  });

  // --- Geometry: stop-sign octagons on a square grid (truncated-square tiling). ---
  var R = 36;                                         // octagon circumradius
  var APO = R * Math.cos(Math.PI/8);                  // center → flat-edge distance
  var PITCH = 2 * APO;                                // cell spacing so cardinal edges touch
  var PAD = R + 24;
  function centerOf(id){ var p = cell[id]; return { x: PAD + p.c*PITCH, y: PAD + p.r*PITCH }; }
  function octPoints(x,y,rad){
    var pts = [];
    for(var k=0;k<8;k++){ var a = Math.PI/8 + k*Math.PI/4;
      pts.push((x+rad*Math.cos(a)).toFixed(1)+','+(y+rad*Math.sin(a)).toFixed(1)); }
    return pts.join(' ');
  }

  var root = document.createElementNS(NS,'g');
  svg.appendChild(root);

  // Connector lines under the octagons (hidden for touching neighbors, visible for
  // long/relocated links so non-grid connections stay legible).
  GRAPH.exits.forEach(function(e){
    if(!OFF[e.dir] || e.to == null) return;
    if(!cell[e.from] || !cell[e.to]) return;
    var a = centerOf(e.from), b = centerOf(e.to);
    var line = document.createElementNS(NS,'line');
    line.setAttribute('x1',a.x); line.setAttribute('y1',a.y);
    line.setAttribute('x2',b.x); line.setAttribute('y2',b.y);
    line.setAttribute('stroke','#484f58'); line.setAttribute('stroke-width','2');
    root.appendChild(line);
  });

  // Stubs: dashed ghost octagon one cell away in the missing exit's direction.
  stubs.forEach(function(e){
    if(!cell[e.from]) return;
    var a = centerOf(e.from), o = OFF[e.dir];
    var len = Math.sqrt(o[0]*o[0] + o[1]*o[1]);
    var gx = a.x + o[0]/len * PITCH * 0.82, gy = a.y + o[1]/len * PITCH * 0.82;
    var spur = document.createElementNS(NS,'line');
    spur.setAttribute('x1',a.x); spur.setAttribute('y1',a.y);
    spur.setAttribute('x2',gx); spur.setAttribute('y2',gy);
    spur.setAttribute('stroke','#6e7681'); spur.setAttribute('stroke-width','1');
    spur.setAttribute('stroke-dasharray','3,3');
    root.appendChild(spur);
    var ghost = document.createElementNS(NS,'polygon');
    ghost.setAttribute('points', octPoints(gx,gy,R*0.42));
    ghost.setAttribute('fill','transparent');
    ghost.setAttribute('stroke','#6e7681'); ghost.setAttribute('stroke-width','1');
    ghost.setAttribute('stroke-dasharray','2,2');
    root.appendChild(ghost);
    var dl = document.createElementNS(NS,'text');
    dl.setAttribute('class','edge-dir'); dl.setAttribute('text-anchor','middle');
    dl.setAttribute('x',gx); dl.setAttribute('y',gy+3);
    dl.textContent = e.dir;
    root.appendChild(dl);
  });

  // Room octagons + labels.
  GRAPH.rooms.forEach(function(r){
    if(!cell[r.id]) return;
    var c = centerOf(r.id);
    var oct = document.createElementNS(NS,'polygon');
    oct.setAttribute('points', octPoints(c.x, c.y, R));
    oct.setAttribute('fill', areaColor[r.area_id] || '#8b949e');
    oct.setAttribute('stroke','#0d1117'); oct.setAttribute('stroke-width','1.5');
    root.appendChild(oct);
    var t = document.createElementNS(NS,'text');
    t.setAttribute('text-anchor','middle'); t.setAttribute('dy','4');
    t.textContent = r.slug;
    root.appendChild(t);
  });

  // --- Pan / zoom. ---
  var W = svg.clientWidth || 900, H = 620;
  var tx = 0, ty = 0, scale = 1;
  function applyTransform(){ root.setAttribute('transform','translate('+tx+','+ty+') scale('+scale+')'); }

  // Fit the whole map into view on first render.
  (function fit(){
    var minX=Infinity, maxX=-Infinity, minY=Infinity, maxY=-Infinity, any=false;
    GRAPH.rooms.forEach(function(r){ if(!cell[r.id]) return; any=true;
      var c=centerOf(r.id); minX=Math.min(minX,c.x); maxX=Math.max(maxX,c.x);
      minY=Math.min(minY,c.y); maxY=Math.max(maxY,c.y); });
    if(!any){ applyTransform(); return; }
    var gw = (maxX-minX) + 2*PAD, gh = (maxY-minY) + 2*PAD;
    scale = Math.max(0.2, Math.min(1.4, Math.min(W/gw, H/gh)));
    tx = (W - gw*scale)/2 - (minX - PAD)*scale;
    ty = (H - gh*scale)/2 - (minY - PAD)*scale;
    applyTransform();
  })();

  var panning = false, panStart = null;
  svg.addEventListener('pointerdown', function(ev){ panning = true; panStart = { x:ev.clientX - tx, y:ev.clientY - ty }; });
  svg.addEventListener('pointermove', function(ev){
    if(!panning) return; tx = ev.clientX - panStart.x; ty = ev.clientY - panStart.y; applyTransform();
  });
  function endPointer(){ panning = false; }
  svg.addEventListener('pointerup', endPointer);
  svg.addEventListener('pointercancel', endPointer);
  svg.addEventListener('wheel', function(ev){
    ev.preventDefault();
    var rect = svg.getBoundingClientRect();
    var mx = ev.clientX - rect.left, my = ev.clientY - rect.top;
    var factor = ev.deltaY < 0 ? 1.1 : 1/1.1;
    var ns = Math.max(0.2, Math.min(4, scale*factor));
    tx = mx - (mx - tx) * (ns/scale);
    ty = my - (my - ty) * (ns/scale);
    scale = ns; applyTransform();
  }, { passive:false });
})();
</script>

</body>
</html>`;

writeFileSync(OUTPUT_PATH, html);
console.log(`Report written to ${OUTPUT_PATH}`);
