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
  SELECT r.id, r.slug, r.name, r.description, r.visits, r.first_visited, r.area_id, r.trap,
         a.slug AS area_slug, a.name AS area_name
  FROM rooms r
  LEFT JOIN areas a ON a.id = r.area_id
  ORDER BY r.id
`).all() as any[] : [];

const areas = roomGraphReady
  ? db.prepare(`SELECT id, slug, name FROM areas ORDER BY id`).all() as any[]
  : [];

const exits = roomGraphReady ? db.prepare(`
  SELECT e.from_id, e.direction, e.to_id, e.lock_key, e.lock_door, t.slug AS to_slug
  FROM room_exits e
  LEFT JOIN rooms t ON t.id = e.to_id
  ORDER BY e.from_id, e.direction
`).all() as any[] : [];

// Last known room per character, for the "you are here" marker on the map.
const playerLocations = (roomGraphReady && hasTable("player_location")) ? db.prepare(`
  SELECT player, room_id, updated_at FROM player_location WHERE room_id IS NOT NULL
`).all() as any[] : [];

// room id -> [character names] standing there.
const playersByRoom = new Map<number, string[]>();
for (const p of playerLocations) {
  if (!playersByRoom.has(p.room_id)) playersByRoom.set(p.room_id, []);
  playersByRoom.get(p.room_id)!.push(p.player);
}

// direction -> "dir → destslug" strings, grouped by source room, for the table.
const exitsByRoom = new Map<number, string[]>();
for (const e of exits) {
  if (!exitsByRoom.has(e.from_id)) exitsByRoom.set(e.from_id, []);
  exitsByRoom.get(e.from_id)!.push(`${e.direction} → ${e.to_slug ?? "?"}`);
}

// Compact node/edge payload for the interactive map (embedded as JSON below).
const graphData = {
  areas: areas.map(a => ({ id: a.id, slug: a.slug, name: a.name })),
  rooms: rooms.map(r => ({ id: r.id, slug: r.slug, name: r.name, description: r.description,
                           area_id: r.area_id, area_slug: r.area_slug, visits: r.visits,
                           first_visited: r.first_visited, trap: r.trap,
                           players: playersByRoom.get(r.id) ?? [] })),
  exits: exits.map(e => ({ from: e.from_id, dir: e.direction, to: e.to_id, to_slug: e.to_slug,
                           lock_key: e.lock_key, lock_door: e.lock_door })),
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

function table(headers: string[], rows: (string | number)[][], opts: { alignRight?: number[]; rowAttrs?: (string | undefined)[] } = {}) {
  const ths = headers.map((h, i) => `<th${opts.alignRight?.includes(i) ? ' class="r"' : ""}>${h}</th>`).join("");
  const trs = rows.map((row, ri) =>
    `<tr${opts.rowAttrs?.[ri] ? " " + opts.rowAttrs![ri] : ""}>` + row.map((cell, i) =>
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
  .map-wrap { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; margin-bottom: 0.5rem; overflow: hidden; display: flex; }
  #map { flex: 1 1 auto; min-width: 0; height: 620px; display: block; cursor: grab; touch-action: none; }
  #map text { fill: var(--text); font-size: 11px; pointer-events: none; user-select: none; }
  #map .edge-dir { fill: var(--muted); font-size: 9px; }
  #map .map-label { fill: var(--text); font-size: 12px; paint-order: stroke; stroke: var(--bg); stroke-width: 3px; stroke-linejoin: round; pointer-events: none; user-select: none; }
  #map .map-label-sel { fill: #fff; font-weight: 600; }
  #map .vbadge { fill: var(--text); font-size: 11px; pointer-events: none; user-select: none; }
  .floor-tabs { display: flex; gap: 0.4rem; margin-bottom: 0.6rem; }
  .floor-tab { background: var(--surface); color: var(--muted); border: 1px solid var(--border); border-radius: 4px; padding: 0.25rem 0.7rem; font: inherit; font-size: 0.8rem; cursor: pointer; }
  .floor-tab:hover { color: var(--text); }
  .floor-tab.active { background: var(--blue); color: var(--bg); border-color: var(--blue); font-weight: 600; }
  tr[data-room-id] { cursor: pointer; }
  tr[data-room-id]:hover td { background: var(--surface); }
  tr[data-room-id].sel td { background: rgba(88,166,255,0.16); }
  #room-panel { flex: 0 0 300px; border-left: 1px solid var(--border); height: 620px; padding: 1.1rem 1.2rem; box-sizing: border-box; overflow-y: auto; font-size: 0.85rem; }
  #room-panel h3 { margin: 0 0 0.15rem; font-size: 1rem; color: var(--text); word-break: break-word; }
  #room-panel .rp-sub { color: var(--muted); font-size: 0.75rem; margin-bottom: 0.6rem; }
  #room-panel .rp-desc { color: var(--text); line-height: 1.5; margin: 0.6rem 0 0.2rem; }
  #room-panel .rp-trap { color: #f85149; font-weight: 600; }
  #room-panel .rp-here { color: #e3b341; font-weight: 600; margin-bottom: 0.3rem; }
  #room-panel .rp-door { color: #db6d28; font-weight: 600; }
  #room-panel .rp-label { color: var(--muted); text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.05em; margin: 1rem 0 0.35rem; }
  #room-panel ul.rp-exits { list-style: none; margin: 0; padding: 0; }
  #room-panel ul.rp-exits li { padding: 0.15rem 0; border-bottom: 1px solid var(--border); }
  #room-panel ul.rp-exits li:last-child { border-bottom: none; }
  #room-panel .rp-dir { display: inline-block; min-width: 2.4em; color: var(--blue); font-weight: 600; }
  #room-panel .rp-empty { color: var(--muted); font-style: italic; }
  .map-legend { display: flex; flex-wrap: wrap; gap: 0.75rem 1.25rem; margin-bottom: 0.75rem; font-size: 0.8rem; color: var(--muted); }
  .map-legend .swatch { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 0.4rem; vertical-align: middle; }
</style>
</head>
<body>
<h1>Tele-Arena — Pelayo's Field Notes</h1>
<p class="meta-line">Generated ${generatedAt}</p>

<h2>World Map</h2>
${!roomGraphReady ? `<p class="note">Room-graph schema not initialized yet — launch baud once to run the migration, then map some rooms.</p>` : ""}
${rooms.length > 0 ? `
<div id="map-legend" class="map-legend"></div>
<div id="floor-tabs" class="floor-tabs"></div>
<div class="map-wrap"><svg id="map"></svg><aside id="room-panel"><p class="rp-empty">Click a room to see its name, description, and exits.</p></aside></div>
<p class="note">Position encodes direction — north is up, east is right, diagonals at the corners · scroll to zoom, drag to pan · dashed octagons are known exits not yet walked · ▲/▼ badges and the floor tabs move between levels (a room reached by up/down sits on the cell directly above/below its neighbor).</p>
` : ""}
${table(
  ["Room", "Name", "Area", "Visits", "First Visited", "Exits"],
  roomRows,
  { alignRight: [3], rowAttrs: rooms.map(r => `data-room-id="${r.id}"`) }
)}

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
  var TRAP_COLOR = '#f85149';                          // trapped rooms are painted red
  var PLAYER_COLOR = '#e3b341';                         // "you are here" — a character's room
  var DOOR_COLOR = '#db6d28';                            // locked-door edges (orange)
  var FERRY_COLOR = '#39c5cf';                           // great-lake ferry ("passage") edges (cyan)
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
    var tr = document.createElement('span');
    tr.innerHTML = '<span class="swatch" style="background:'+TRAP_COLOR+'"></span>trap';
    legend.appendChild(tr);
    var pl = document.createElement('span');
    pl.innerHTML = '<span class="swatch" style="background:'+PLAYER_COLOR+'"></span>you are here';
    legend.appendChild(pl);
    var dr = document.createElement('span');
    dr.innerHTML = '<span class="swatch" style="background:'+DOOR_COLOR+'"></span>locked door';
    legend.appendChild(dr);
    var fy = document.createElement('span');
    fy.innerHTML = '<span class="swatch" style="background:'+FERRY_COLOR+'"></span>ferry (buy passage)';
    legend.appendChild(fy);
  }

  // --- Direction → grid offset (col, row); row increases downward, so n = up.
  //     u/d don't move you on the plane -- they change floor (see VERT). ---
  var OFF = { n:[0,-1], s:[0,1], e:[1,0], w:[-1,0], ne:[1,-1], nw:[-1,-1], se:[1,1], sw:[-1,1] };
  var VERT = { u:1, d:-1 };

  var roomById = {};
  GRAPH.rooms.forEach(function(r){ roomById[r.id] = r; });

  // Adjacency now includes u/d so vertically-linked rooms join the same component.
  // Compass edges move you on the plane; u/d edges carry a floor delta instead.
  var adj = {}, stubs = [];
  GRAPH.rooms.forEach(function(r){ adj[r.id] = []; });
  GRAPH.exits.forEach(function(e){
    if(OFF[e.dir]){
      if(e.to == null){ stubs.push(e); return; }          // unexplored compass exit
      if(roomById[e.from] && roomById[e.to]) adj[e.from].push({ dir:e.dir, to:e.to, vert:0 });
    } else if(VERT[e.dir] && e.to != null && roomById[e.from] && roomById[e.to]){
      adj[e.from].push({ dir:e.dir, to:e.to, vert:VERT[e.dir] });
    }
  });

  // --- Lay out each component on a 3D integer grid (col, row, floor), then tile. ---
  var seen = {}, components = [];
  GRAPH.rooms.forEach(function(rootRoom){
    if(seen[rootRoom.id]) return;
    var lpos = {}, locc = {};
    function lkey(c,r,f){ return f+':'+c+','+r; }
    function lfindFree(c,r,f){                          // spiral out within the same floor
      if(!(lkey(c,r,f) in locc)) return [c,r];
      for(var rad=1; rad<400; rad++){
        for(var dc=-rad; dc<=rad; dc++) for(var dr=-rad; dr<=rad; dr++){
          if(Math.max(Math.abs(dc),Math.abs(dr)) !== rad) continue;
          if(!(lkey(c+dc,r+dr,f) in locc)) return [c+dc,r+dr];
        }
      }
      return [c,r];
    }
    function lplace(id,c,r,f){ lpos[id]={c:c,r:r,f:f}; locc[lkey(c,r,f)]=id; seen[id]=true; }
    lplace(rootRoom.id, 0, 0, 0);
    var q = [rootRoom.id];
    while(q.length){
      var cur = q.shift(), base = lpos[cur];
      adj[cur].forEach(function(ed){
        if(seen[ed.to]) return;                       // already placed; drawn as connector/badge
        if(ed.vert){
          lplace(ed.to, base.c, base.r, base.f + ed.vert);       // same cell, one floor up/down
        } else {
          var o = OFF[ed.dir], cl = lfindFree(base.c + o[0], base.r + o[1], base.f);
          lplace(ed.to, cl[0], cl[1], base.f);
        }
        q.push(ed.to);
      });
    }
    var ids = Object.keys(lpos), minc=Infinity, maxc=-Infinity, minr=Infinity, maxr=-Infinity;
    ids.forEach(function(id){ var p=lpos[id];
      minc=Math.min(minc,p.c); maxc=Math.max(maxc,p.c);
      minr=Math.min(minr,p.r); maxr=Math.max(maxr,p.r); });
    components.push({ lpos:lpos, ids:ids, minc:minc, maxc:maxc, minr:minr, maxr:maxr });
  });

  // Tile components left-to-right with a gap; floor is preserved.
  var cell = {}, GAP = 2, cursor = 0;
  components.forEach(function(cp){
    cp.ids.forEach(function(id){ var p = cp.lpos[id];
      cell[id] = { c: cursor + (p.c - cp.minc), r: (p.r - cp.minr), f: p.f }; });
    cursor += (cp.maxc - cp.minc) + 1 + GAP;
  });

  // Distinct floors present, sorted high → low (upper floors first).
  var floorSet = {};
  GRAPH.rooms.forEach(function(r){ if(cell[r.id]) floorSet[cell[r.id].f] = true; });
  var floors = Object.keys(floorSet).map(Number).sort(function(a,b){ return b - a; });
  function floorLabel(f){ return f === 0 ? 'Ground' : (f > 0 ? 'Up ' + f : 'Down ' + (-f)); }

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

  // --- Detail panel + lookups. ---
  var roomInfo = {};
  GRAPH.rooms.forEach(function(r){ roomInfo[r.id] = r; });
  var exitsFrom = {}, vertExits = {};
  GRAPH.rooms.forEach(function(r){ exitsFrom[r.id] = []; vertExits[r.id] = []; });
  GRAPH.exits.forEach(function(e){
    if(exitsFrom[e.from]) exitsFrom[e.from].push(e);
    if(VERT[e.dir] && e.to != null && vertExits[e.from]) vertExits[e.from].push(e);
  });

  var panel = document.getElementById('room-panel');
  var octByRoom = {}, rowByRoom = {}, tabByFloor = {};
  var selectedOct = null, selectedRow = null, selectedId = null;
  var hoverLabel = null, selectLabel = null, currentFloor = 0;
  function onFloor(id){ return cell[id] && cell[id].f === currentFloor; }
  function labelAt(el, id){
    if(!el || !cell[id]) return;
    var c = centerOf(id);
    el.setAttribute('x', c.x); el.setAttribute('y', c.y - R - 7);
    el.textContent = roomInfo[id].name || roomInfo[id].slug;
    el.style.display = '';
  }
  function escapeHtml(s){
    return String(s).replace(/[&<>"]/g, function(ch){
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[ch];
    });
  }
  var DIR_ORDER = { n:0, ne:1, e:2, se:3, s:4, sw:5, w:6, nw:7, u:8, d:9 };
  function destLabel(e){
    if(e.to == null) return '<span class="rp-empty">unexplored</span>';
    var r = roomInfo[e.to];
    return escapeHtml((r && (r.name || r.slug)) || e.to_slug || '?');
  }
  function showRoom(id){
    if(!panel) return;
    var r = roomInfo[id];
    if(!r){ return; }
    var exs = exitsFrom[id].slice().sort(function(a,b){
      return (DIR_ORDER[a.dir] ?? 99) - (DIR_ORDER[b.dir] ?? 99);
    });
    var html = '<h3>' + escapeHtml(r.name || r.slug) + '</h3>';
    var sub = [escapeHtml(r.slug)];
    if(r.area_slug) sub.push(escapeHtml(r.area_slug));
    if(cell[id]) sub.push(floorLabel(cell[id].f));
    sub.push((r.visits || 0) + (r.visits === 1 ? ' visit' : ' visits'));
    html += '<div class="rp-sub">' + sub.join(' · ') + '</div>';
    if(r.players && r.players.length){
      html += '<div class="rp-here">▸ ' + r.players.map(escapeHtml).join(', ') + '</div>';
    }
    html += r.description
      ? '<div class="rp-desc">' + escapeHtml(r.description) + '</div>'
      : '<div class="rp-desc rp-empty">No description captured yet.</div>';
    if(r.trap){
      html += '<div class="rp-label">Trap</div>';
      html += '<div class="rp-trap">' + escapeHtml(r.trap) + '</div>';
    }
    html += '<div class="rp-label">Exits</div>';
    if(exs.length){
      html += '<ul class="rp-exits">';
      exs.forEach(function(e){
        // Annotate a locked exit inline so the door + key show right in the room's
        // exit list (not only on the map's door line).
        var lock = e.lock_door
          ? ' <span class="rp-door">🔒 ' + escapeHtml(e.lock_door)
            + (e.lock_key ? ' (' + escapeHtml(e.lock_key) + ' key)' : '') + '</span>'
          : '';
        html += '<li><span class="rp-dir">' + escapeHtml(e.dir) + '</span> ' + destLabel(e) + lock + '</li>';
      });
      html += '</ul>';
    } else {
      html += '<div class="rp-empty">none recorded</div>';
    }
    panel.innerHTML = html;
  }
  // Door detail: clicking a locked-door edge shows the door, which rooms it
  // sits between, and the key that opens it.
  function showDoor(e){
    if(!panel) return;
    var A = roomInfo[e.from], B = roomInfo[e.to];
    var an = A ? (A.name || A.slug) : ('#' + e.from);
    var bn = B ? (B.name || B.slug) : ('#' + e.to);
    var html = '<h3>' + escapeHtml((e.lock_door || 'locked') + ' door') + '</h3>';
    html += '<div class="rp-sub">locked door</div>';
    html += '<div class="rp-desc">Between <span class="rp-door">' + escapeHtml(an)
      + '</span> and <span class="rp-door">' + escapeHtml(bn) + '</span>.</div>';
    if(e.lock_key){
      html += '<div class="rp-label">Key</div><div class="rp-door">' + escapeHtml(e.lock_key) + ' key</div>';
    }
    panel.innerHTML = html;
  }
  function applySelectionHighlight(){
    if(selectedOct){ selectedOct.setAttribute('stroke','#0d1117'); selectedOct.setAttribute('stroke-width','1.5'); selectedOct = null; }
    if(selectedId == null || !onFloor(selectedId)){ if(selectLabel) selectLabel.style.display = 'none'; return; }
    var el = octByRoom[selectedId];
    if(el){ el.setAttribute('stroke','#e6edf3'); el.setAttribute('stroke-width','3'); selectedOct = el; }
    labelAt(selectLabel, selectedId);
  }
  function selectRoom(id){
    selectedId = id;
    if(selectedRow) selectedRow.classList.remove('sel');
    var row = rowByRoom[id];
    if(row){ row.classList.add('sel'); selectedRow = row; }
    var f = cell[id] ? cell[id].f : currentFloor;
    if(f !== currentFloor) drawFloor(f);            // redraw re-applies the highlight
    else applySelectionHighlight();
    if(hoverLabel) hoverLabel.style.display = 'none';
    showRoom(id);
  }

  // --- Render a single floor into the (cleared) root group. ---
  function drawFloor(f){
    currentFloor = f;
    while(root.firstChild) root.removeChild(root.firstChild);
    octByRoom = {};

    // compass connectors between rooms on this floor. A locked-door edge is
    // drawn in the door color; its 🔒 badge is drawn in a later pass (after the
    // octagons) so it isn't hidden — cardinal neighbours touch edge-to-edge, so
    // a badge at the shared edge would otherwise be painted over by the rooms.
    GRAPH.exits.forEach(function(e){
      if(!OFF[e.dir] || e.to == null || !onFloor(e.from) || !onFloor(e.to)) return;
      var a = centerOf(e.from), b = centerOf(e.to);
      var locked = !!e.lock_door;
      var line = document.createElementNS(NS,'line');
      line.setAttribute('x1',a.x); line.setAttribute('y1',a.y);
      line.setAttribute('x2',b.x); line.setAttribute('y2',b.y);
      line.setAttribute('stroke', locked ? DOOR_COLOR : '#484f58');
      line.setAttribute('stroke-width', locked ? '3' : '2');
      root.appendChild(line);
    });

    // Great-lake ferry ("passage"): a non-compass edge between the two towns'
    // docks. It doesn't move you on the grid (the towns have independent
    // coordinates), so it's absent from the layout adjacency and never distorts
    // either town's shape; draw it as a distinct dashed cyan connector labelled
    // "ferry" so it reads as a boat crossing, not a walkable corridor. Each
    // undirected crossing is stored both ways, so draw it once (from < to).
    GRAPH.exits.forEach(function(e){
      if(e.dir !== 'passage' || e.to == null || e.from >= e.to) return;
      if(!onFloor(e.from) || !onFloor(e.to)) return;
      var a = centerOf(e.from), b = centerOf(e.to);
      var line = document.createElementNS(NS,'line');
      line.setAttribute('x1',a.x); line.setAttribute('y1',a.y);
      line.setAttribute('x2',b.x); line.setAttribute('y2',b.y);
      line.setAttribute('stroke', FERRY_COLOR); line.setAttribute('stroke-width','2');
      line.setAttribute('stroke-dasharray','6,4');
      root.appendChild(line);
      var lbl = document.createElementNS(NS,'text');
      lbl.setAttribute('class','edge-dir'); lbl.setAttribute('text-anchor','middle');
      lbl.setAttribute('x',(a.x+b.x)/2); lbl.setAttribute('y',(a.y+b.y)/2 - 4);
      lbl.textContent = 'ferry';
      root.appendChild(lbl);
    });

    // stubs: dashed ghost octagon one cell away in the missing exit's direction
    stubs.forEach(function(e){
      if(!onFloor(e.from)) return;
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

    // room octagons + up/down badges
    GRAPH.rooms.forEach(function(r){
      if(!onFloor(r.id)) return;
      var c = centerOf(r.id);
      var oct = document.createElementNS(NS,'polygon');
      oct.setAttribute('points', octPoints(c.x, c.y, R));
      // A character's current room wins (yellow, "you are here"), then a trapped
      // room (red), else the area color. The panel names the specific trap and
      // any players present.
      var occupied = r.players && r.players.length;
      oct.setAttribute('fill', occupied ? PLAYER_COLOR
        : (r.trap ? TRAP_COLOR : (areaColor[r.area_id] || '#8b949e')));
      oct.setAttribute('stroke','#0d1117'); oct.setAttribute('stroke-width','1.5');
      oct.style.cursor = 'pointer';
      oct.addEventListener('click', function(){ selectRoom(r.id); });
      oct.addEventListener('mouseenter', function(){ if(r.id !== selectedId) labelAt(hoverLabel, r.id); });
      oct.addEventListener('mouseleave', function(){ if(hoverLabel) hoverLabel.style.display = 'none'; });
      root.appendChild(oct);
      octByRoom[r.id] = oct;

      vertExits[r.id].forEach(function(ed){
        var up = ed.dir === 'u';
        var bx = c.x + R*0.52, by = c.y + (up ? -R*0.42 : R*0.42);
        var g = document.createElementNS(NS,'g');
        g.style.cursor = 'pointer';
        var circ = document.createElementNS(NS,'circle');
        circ.setAttribute('cx',bx); circ.setAttribute('cy',by); circ.setAttribute('r','9');
        circ.setAttribute('fill','#0d1117'); circ.setAttribute('stroke','#e6edf3'); circ.setAttribute('stroke-width','1');
        g.appendChild(circ);
        var tri = document.createElementNS(NS,'text');
        tri.setAttribute('class','vbadge'); tri.setAttribute('text-anchor','middle');
        tri.setAttribute('x',bx); tri.setAttribute('y',by + 3.5);
        tri.textContent = up ? '\\u25B2' : '\\u25BC';
        g.appendChild(tri);
        g.addEventListener('click', function(ev){ ev.stopPropagation(); selectRoom(ed.to); centerOn(ed.to); });
        root.appendChild(g);
      });
    });

    // locked-door 🔒 badges, drawn ON TOP of the octagons so they show even when
    // the two rooms touch edge-to-edge (cardinal neighbours have no gap). One per
    // doorway (deduped across its two directions), clickable for the door detail.
    var doorBadgeDrawn = {};
    GRAPH.exits.forEach(function(e){
      if(!OFF[e.dir] || !e.lock_door || e.to == null || !onFloor(e.from) || !onFloor(e.to)) return;
      var pairKey = Math.min(e.from, e.to) + '-' + Math.max(e.from, e.to);
      if(doorBadgeDrawn[pairKey]) return;
      doorBadgeDrawn[pairKey] = true;
      var a = centerOf(e.from), b = centerOf(e.to);
      var mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      var g = document.createElementNS(NS,'g');
      g.style.cursor = 'pointer';
      var circ = document.createElementNS(NS,'circle');
      circ.setAttribute('cx',mx); circ.setAttribute('cy',my); circ.setAttribute('r','9');
      circ.setAttribute('fill','#0d1117'); circ.setAttribute('stroke',DOOR_COLOR); circ.setAttribute('stroke-width','2');
      g.appendChild(circ);
      var t = document.createElementNS(NS,'text');
      t.setAttribute('class','vbadge'); t.setAttribute('text-anchor','middle');
      t.setAttribute('x',mx); t.setAttribute('y',my + 3.5);
      t.textContent = '\\uD83D\\uDD12';                    // 🔒 padlock
      g.appendChild(t);
      g.addEventListener('click', function(){ showDoor(e); });
      root.appendChild(g);
    });

    // floating labels on top (recreated each redraw)
    hoverLabel = document.createElementNS(NS,'text');
    hoverLabel.setAttribute('class','map-label'); hoverLabel.setAttribute('text-anchor','middle');
    hoverLabel.style.display = 'none'; root.appendChild(hoverLabel);
    selectLabel = document.createElementNS(NS,'text');
    selectLabel.setAttribute('class','map-label map-label-sel'); selectLabel.setAttribute('text-anchor','middle');
    selectLabel.style.display = 'none'; root.appendChild(selectLabel);

    floors.forEach(function(ff){ if(tabByFloor[ff]) tabByFloor[ff].classList.toggle('active', ff === f); });
    applySelectionHighlight();
  }

  // --- Pan / zoom. ---
  var W = svg.clientWidth || 900, H = 620;
  var tx = 0, ty = 0, scale = 1;
  function applyTransform(){ root.setAttribute('transform','translate('+tx+','+ty+') scale('+scale+')'); }
  function fit(){                                     // fit all rooms (floors share x/y) into view
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
  }

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

  // Pan the map so a given room sits in the middle of the viewport.
  function centerOn(id){
    if(!cell[id]) return;
    var c = centerOf(id);
    tx = W/2 - c.x*scale; ty = H/2 - c.y*scale;
    applyTransform();
  }

  // --- Floor selector tabs (only shown when there's more than one floor). ---
  var tabsEl = document.getElementById('floor-tabs');
  if(tabsEl && floors.length > 1){
    floors.forEach(function(f){
      var b = document.createElement('button');
      b.className = 'floor-tab'; b.textContent = floorLabel(f);
      b.addEventListener('click', function(){ drawFloor(f); });
      tabsEl.appendChild(b);
      tabByFloor[f] = b;
    });
  }

  // Deep-link: clicking a Room table row selects it here and brings it into view.
  var wrap = document.querySelector('.map-wrap');
  Array.prototype.forEach.call(document.querySelectorAll('tr[data-room-id]'), function(tr){
    var id = +tr.getAttribute('data-room-id');
    rowByRoom[id] = tr;
    tr.addEventListener('click', function(){
      selectRoom(id);
      centerOn(id);
      if(wrap) wrap.scrollIntoView({ behavior:'smooth', block:'center' });
    });
  });

  // Initial render: Ground if present, else the topmost floor.
  drawFloor(floorSet[0] ? 0 : (floors.length ? floors[0] : 0));
  fit();
})();
</script>

</body>
</html>`;

writeFileSync(OUTPUT_PATH, html);
console.log(`Report written to ${OUTPUT_PATH}`);
