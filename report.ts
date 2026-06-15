import { Database } from "bun:sqlite";
import { writeFileSync } from "fs";
import { join } from "path";

const DB_PATH = join(process.cwd(), "tele-arena.db");
const OUTPUT_PATH = join(process.cwd(), "report.html");

const db = new Database(DB_PATH, { readonly: true });

// ── Raw queries ────────────────────────────────────────────────────────────────

const rooms = db.prepare(`
  SELECT r.name, r.description, r.visits, r.first_visited,
         GROUP_CONCAT(re.direction || ' → ' || COALESCE(re.to_room,'?'), ', ') AS exits
  FROM rooms r
  LEFT JOIN room_exits re ON re.from_room = r.name
  GROUP BY r.name
  ORDER BY r.first_visited
`).all() as any[];

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

const roomRows = rooms.map(r => [esc(r.name), r.visits, r.first_visited?.slice(0,10) ?? "—", esc(r.exits ?? "none")]);

const serviceRows = services.map(s => [esc(s.name), esc(s.location), s.cost != null ? s.cost + " gp" : "—", s.uses]);

const statRows = statChanges.map(s => [esc(s.stat), s.from_value, s.to_value, s.recorded_at?.slice(0,10) ?? "—"]);

const monsterCards = monsters.map(m => `
  <div class="card">
    <h3>${esc(m.name)}</h3>
    <p class="desc">${esc(m.description ?? "(no description yet)")}</p>
    <p class="meta">First seen: ${m.first_seen?.slice(0,10) ?? "—"} · Encounters: ${m.encounters}</p>
  </div>`).join("\n");

const roomCards = rooms.map(r => `
  <div class="card">
    <h3>${esc(r.name)}</h3>
    <p class="desc">${esc(r.description || "(no description yet)")}</p>
    <p class="meta">First visited: ${r.first_visited?.slice(0,10) ?? "—"} · Visits: ${r.visits}${r.exits ? ` · Exits: ${esc(r.exits)}` : ""}</p>
  </div>`).join("\n");

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

<h2>World Map</h2>
${table(
  ["Room", "Visits", "First Visited", "Exits"],
  roomRows,
  { alignRight: [1] }
)}

<h2>Services</h2>
${table(
  ["Service", "Location", "Cost", "Times Used"],
  serviceRows,
  { alignRight: [2,3] }
)}

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

</body>
</html>`;

writeFileSync(OUTPUT_PATH, html);
console.log(`Report written to ${OUTPUT_PATH}`);
