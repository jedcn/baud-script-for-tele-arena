// xp-report.ts — what each character earned from team-fight-champions.
//
//   just xp-report                                  # everything in logs/
//   just xp-report logs/session-*-2026-11-07*.log
//
// XP is earned per point of damage, with no visible bonus for the kill, so
// damage per second is the second-by-second view of XP and the `status` readings
// calibrate it. Compare a character with itself: the rate differs by character
// and by monster.
//
// Give it every character's log. Each log holds only that character's own
// damage, and the leader's log supplies the runs. A section is one leader log, so
// one login is one section however many circuits it holds.

import { normalizeFile, type Event } from "./log";

// A run's `status` readings go out as it starts and finishes, so the replies land
// just outside the script's own lines.
const READING_SLACK_S = 5;

const RUN_START = /^Fighting the champions/;
const RUN_CHASE = /^Room clear\. Chasing/;
const RUN_END = /^(All champions dead|Back and the room|Stopped|Never reached|Could not)/;

interface Run {
  start: number;
  end: number;
  chaseStart: number | null;   // first chase of the run, if any
  finished: boolean;           // ended by the script, not by the log running out
  outcome: string;
}

interface Xp { gained: number; from: number; to: number }

interface CharRun { damage: number; xp: Xp | null }

interface RunReport extends Run {
  kills: number;
  lowestHealth: { player: string; pct: number } | null;
  chars: Record<string, CharRun>;
}

interface CharTotal {
  xp: Xp | null;
  damage: number;
  damageByMonster: Record<string, number>;
  damageInXpSpan: number;
  readyIdleS: number;
  readyCycles: number;
  lowestHealth: number | null;
  deaths: number;
}

interface Section {
  leaderFile: string;
  runs: RunReport[];
  spanS: number;
  homeS: number;
  chaseS: number;
  betweenS: number;
  chars: Record<string, CharTotal>;
}

const seconds = (e: Event): number | null =>
  e.iso ? new Date(e.iso).getTime() / 1000 : null;

const isSwing = (e: Event): boolean =>
  e.kind === "our-hit" || e.kind === "our-miss" || e.kind === "monster-dodge";

function scriptLine(e: Event): string | null {
  return e.kind === "script" && e.tag === "champions" ? String(e.message) : null;
}

// The runs a leader's log holds. One the log never finished, a dropped connection
// say, ends at the log's last clock and is marked as such.
function findRuns(events: Event[]): Run[] {
  const runs: Run[] = [];
  let open: Run | null = null;
  let lastTime = 0;
  for (const e of events) {
    const t = seconds(e);
    if (t == null) continue;
    lastTime = t;
    const line = scriptLine(e);
    if (line == null) continue;
    if (RUN_START.test(line)) {
      if (open) runs.push({ ...open, end: t });
      open = { start: t, end: t, chaseStart: null, finished: false, outcome: "log ended" };
    } else if (open && RUN_CHASE.test(line)) {
      open.chaseStart ??= t;
    } else if (open && RUN_END.test(line)) {
      runs.push({ ...open, end: t, finished: true, outcome: line });
      open = null;
    }
  }
  if (open) runs.push({ ...open, end: lastTime });
  return runs;
}

// XP between the first and last readings in a window. Rates must use these
// times, not the window's, or a window part-covered by readings understates them.
function xpBetween(events: Event[], from: number, to: number): Xp | null {
  const readings = events.flatMap(e => {
    const t = seconds(e);
    return e.kind === "status" && typeof e.xp === "number" && t != null
      && t >= from - READING_SLACK_S && t <= to + READING_SLACK_S
      ? [{ t, xp: e.xp as number }] : [];
  });
  if (readings.length < 2) return null;
  const first = readings[0];
  const last = readings[readings.length - 1];
  if (last.t === first.t) return null;
  return { gained: last.xp - first.xp, from: first.t, to: last.t };
}

function damageBetween(events: Event[], from: number, to: number): number {
  let total = 0;
  for (const e of events) {
    const t = seconds(e);
    if (e.kind === "our-hit" && t != null && t >= from && t <= to) total += e.damage as number;
  }
  return total;
}

// One poll per `group`: who was Resting or Ready when the leader asked.
function groupPolls(leader: Event[]): { t: number; states: Record<string, string> }[] {
  const polls: { t: number; states: Record<string, string> }[] = [];
  for (const e of leader) {
    const t = seconds(e);
    if (t == null) continue;
    if (e.kind === "group-header") polls.push({ t, states: {} });
    else if (e.kind === "group-member" && polls.length) {
      polls[polls.length - 1].states[String(e.player).toLowerCase()] = String(e.stamina);
    }
  }
  return polls;
}

// Seconds between a poll first showing the character Ready and their next swing,
// while the group is fighting at home. A chase's Ready wait is not idleness: the
// script is standing them down on purpose. The poll sees a flip up to 3s late, so
// this understates the idle time a little.
function readyIdle(polls: ReturnType<typeof groupPolls>, swings: number[], run: Run, char: string) {
  const fightEnd = run.chaseStart ?? run.end;
  let idle = 0;
  let cycles = 0;
  const inFight = polls.filter(p => p.t >= run.start && p.t <= fightEnd);
  for (let i = 1; i < inFight.length; i++) {
    if (inFight[i - 1].states[char] !== "Resting" || inFight[i].states[char] !== "Ready") continue;
    const next = swings.find(s => s >= inFight[i].t);
    if (next == null || next > fightEnd) continue;
    idle += next - inFight[i].t;
    cycles++;
  }
  return { idle, cycles };
}

function buildSection(leaderFile: string, leader: Event[], all: Event[], runs: Run[]): Section {
  const first = runs[0].start;
  const last = runs[runs.length - 1].end;
  const within = (e: Event) => {
    const t = seconds(e);
    return t != null && t >= first - READING_SLACK_S && t <= last + READING_SLACK_S;
  };
  const byChar = new Map<string, Event[]>();
  for (const e of all.filter(within)) {
    if (!byChar.has(e.char)) byChar.set(e.char, []);
    byChar.get(e.char)!.push(e);
  }
  const polls = groupPolls(leader);

  const reports: RunReport[] = runs.map(run => {
    const leaderInRun = leader.filter(e => {
      const t = seconds(e);
      return t != null && t >= run.start && t <= run.end;
    });
    let lowestHealth: RunReport["lowestHealth"] = null;
    for (const e of leaderInRun) {
      if (e.kind === "group-member" && (!lowestHealth || (e.healthPct as number) < lowestHealth.pct)) {
        lowestHealth = { player: String(e.player), pct: e.healthPct as number };
      }
    }
    const chars: Record<string, CharRun> = {};
    for (const [char, events] of byChar) {
      chars[char] = {
        damage: damageBetween(events, run.start, run.end),
        xp: xpBetween(events, run.start, run.end),
      };
    }
    return {
      ...run,
      kills: leaderInRun.filter(e => e.kind === "monster-death" && e.monster === "elven champion").length,
      lowestHealth,
      chars,
    };
  });

  const chars: Record<string, CharTotal> = {};
  for (const [char, events] of byChar) {
    const damageByMonster: Record<string, number> = {};
    for (const e of events) {
      if (e.kind === "our-hit") {
        const monster = String(e.monster);
        damageByMonster[monster] = (damageByMonster[monster] ?? 0) + (e.damage as number);
      }
    }
    const swings = events.filter(isSwing).flatMap(e => seconds(e) ?? []);
    let readyIdleS = 0;
    let readyCycles = 0;
    for (const run of runs) {
      const { idle, cycles } = readyIdle(polls, swings, run, char);
      readyIdleS += idle;
      readyCycles += cycles;
    }
    const health = leader.filter(within).filter(e =>
      e.kind === "group-member" && String(e.player).toLowerCase() === char)
      .map(e => e.healthPct as number);
    const xp = xpBetween(events, first, last);
    chars[char] = {
      xp,
      damage: Object.values(damageByMonster).reduce((a, b) => a + b, 0),
      damageByMonster,
      damageInXpSpan: xp ? damageBetween(events, xp.from, xp.to) : 0,
      readyIdleS,
      readyCycles,
      lowestHealth: health.length ? Math.min(...health) : null,
      deaths: events.filter(e => e.kind === "our-death").length,
    };
  }

  const homeS = runs.reduce((sum, r) => sum + (r.chaseStart ?? r.end) - r.start, 0);
  const chaseS = runs.reduce((sum, r) => sum + (r.chaseStart ? r.end - r.chaseStart : 0), 0);
  return {
    leaderFile, runs: reports, spanS: last - first, homeS, chaseS,
    betweenS: last - first - homeS - chaseS, chars,
  };
}

function buildReport(events: Event[]): Section[] {
  const byFile = new Map<string, Event[]>();
  for (const e of events) {
    if (!byFile.has(e.file)) byFile.set(e.file, []);
    byFile.get(e.file)!.push(e);
  }
  const sections: Section[] = [];
  for (const [file, fileEvents] of byFile) {
    const runs = findRuns(fileEvents);
    if (runs.length) sections.push(buildSection(file, fileEvents, events, runs));
  }
  return sections.sort((a, b) => a.runs[0].start - b.runs[0].start);
}

// ── Formatting ─────────────────────────────────────────────────────────────────

const clock = (t: number) => new Date(t * 1000).toTimeString().slice(0, 8);
const duration = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;
const whole = (n: number) => Math.round(n).toLocaleString("en-US");

function table(rows: string[][]): string {
  const widths = rows[0].map((_, col) => Math.max(...rows.map(r => r[col].length)));
  return rows.map(r => r.map((cell, col) =>
    col === 0 ? cell.padEnd(widths[col]) : cell.padStart(widths[col])).join("  ").trimEnd())
    .join("\n");
}

function formatSection(s: Section): string {
  const names = Object.keys(s.chars).sort();
  const runRows = [["run", "start", "time", "home", "chase", "kills", "damage", "dmg/s", "group XP", "lowest HE"]];
  s.runs.forEach((r, i) => {
    const seconds = r.end - r.start;
    const damage = names.reduce((sum, n) => sum + r.chars[n].damage, 0);
    const xps = names.map(n => r.chars[n].xp);
    const xp = xps.every(x => x) ? whole(xps.reduce((sum, x) => sum + x!.gained, 0)) : "-";
    const home = (r.chaseStart ?? r.end) - r.start;
    runRows.push([
      String(i + 1) + (r.finished ? "" : "*"), clock(r.start), duration(seconds), duration(home),
      r.chaseStart ? duration(r.end - r.chaseStart) : "-", String(r.kills), whole(damage),
      seconds ? (damage / seconds).toFixed(1) : "-", xp,
      r.lowestHealth ? `${r.lowestHealth.player} ${r.lowestHealth.pct}%` : "-",
    ]);
  });

  const charRows = [["character", "XP", "XP/min", "XP/dmg", "damage", "dmg/s", "champion", "other", "idle/cycle", "lowest HE", "deaths"]];
  for (const name of names) {
    const c = s.chars[name];
    const minutes = c.xp ? (c.xp.to - c.xp.from) / 60 : 0;
    const champion = c.damageByMonster["elven champion"] ?? 0;
    charRows.push([
      name, c.xp ? whole(c.xp.gained) : "-", c.xp ? whole(c.xp.gained / minutes) : "-",
      c.xp && c.damageInXpSpan ? (c.xp.gained / c.damageInXpSpan).toFixed(0) : "-",
      whole(c.damage), s.spanS ? (c.damage / s.spanS).toFixed(1) : "-",
      whole(champion), whole(c.damage - champion),
      c.readyCycles ? `${(c.readyIdleS / c.readyCycles).toFixed(1)}s` : "-",
      c.lowestHealth == null ? "-" : `${c.lowestHealth}%`, String(c.deaths),
    ]);
  }

  const lines = [
    s.leaderFile,
    `${s.runs.length} run(s) over ${duration(s.spanS)}: ${duration(s.homeS)} fighting at home, `
      + `${duration(s.chaseS)} chasing, ${duration(s.betweenS)} between runs`,
    "",
    table(runRows),
    "",
    table(charRows),
  ];
  if (s.runs.some(r => !r.finished)) lines.push("", "* the log ended before this run did");
  return lines.join("\n");
}

function main(): void {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error("usage: bun xp-report.ts <logfile...>");
    process.exit(2);
  }
  const sections = buildReport(files.flatMap(normalizeFile));
  if (sections.length === 0) {
    console.log("No team-fight-champions runs in these logs.");
    return;
  }
  console.log(sections.map(formatSection).join("\n\n"));
}

if (import.meta.main) main();

export { buildReport, formatSection, findRuns };
