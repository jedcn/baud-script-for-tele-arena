// Tests for xp-report.ts, on the events log.ts produces.

import { test, expect } from "bun:test";
import type { Event } from "./log";
import { buildReport, findRuns, formatSection } from "./xp-report";

const LEADER = "session-pelayo-2026-11-07T08-51-43.log";
const FOLLOWER = "session-pollux-2026-11-07T08-51-57.log";

function at(second: number): string {
  const m = Math.floor(second / 60);
  return `2026-11-07T09:${String(m).padStart(2, "0")}:${String(second % 60).padStart(2, "0")}`;
}

function event(file: string, second: number, kind: string, fields: Record<string, unknown> = {}): Event {
  return {
    file, char: file.split("-")[1], session: "s", line: 1, time: null, iso: at(second),
    timeSource: "debug", kind, text: "", ...fields,
  };
}

const say = (second: number, message: string) =>
  event(LEADER, second, "script", { tag: "champions", message });
const hit = (file: string, second: number, damage: number, monster = "elven champion") =>
  event(file, second, "our-hit", { monster, damage });
const status = (file: string, second: number, xp: number) => event(file, second, "status", { xp });

function poll(second: number, states: Record<string, string>, health = 100): Event[] {
  return [
    event(LEADER, second, "group-header"),
    ...Object.entries(states).map(([player, stamina]) =>
      event(LEADER, second, "group-member", { player, stamina, healthPct: health })),
  ];
}

const chars = (events: Event[]) => buildReport(events)[0].chars;

test("finds a run, its first chase and how it ended", () => {
  const runs = findRuns([
    say(10, "Fighting the champions here."),
    say(100, "Room clear. Chasing the one that went n."),
    say(140, "Room clear. Chasing the one that went e."),
    say(200, "All champions dead: 3 killed."),
  ]);
  expect(runs).toHaveLength(1);
  expect(runs[0]).toMatchObject({ chaseStart: new Date(at(100)).getTime() / 1000, finished: true });
  expect(runs[0].end - runs[0].start).toBe(190);
});

test("a progress line is not the end of a run", () => {
  expect(findRuns([
    say(10, "Fighting the champions here."),
    say(20, "2 champions here is too many at once. Going back."),
    say(30, "Stopped."),
  ])[0].end - new Date(at(10)).getTime() / 1000).toBe(20);
});

test("a run the log never finished is marked and ends at the last clock", () => {
  const [run] = findRuns([say(10, "Fighting the champions here."), event(LEADER, 50, "sent")]);
  expect(run.finished).toBe(false);
  expect(run.end - run.start).toBe(40);
});

test("a log with no runs makes no section", () => {
  expect(buildReport([hit(FOLLOWER, 10, 40), status(FOLLOWER, 12, 100)])).toEqual([]);
});

test("takes XP from the readings around a run and damage from everyone's log", () => {
  const report = buildReport([
    say(10, "Fighting the champions here."),
    status(LEADER, 10, 1000),
    hit(LEADER, 20, 10),
    say(70, "All champions dead: 3 killed."),
    status(LEADER, 71, 2080),
    status(FOLLOWER, 11, 5000),
    hit(FOLLOWER, 20, 100),
    status(FOLLOWER, 72, 18500),
  ]);
  const [section] = report;
  expect(section.leaderFile).toBe(LEADER);
  expect(section.chars.pelayo.xp?.gained).toBe(1080);
  expect(section.chars.pollux.damage).toBe(100);
  expect(section.chars.pollux.xp?.gained).toBe(13500);
  expect(section.runs[0].chars.pollux.damage).toBe(100);
});

test("leaves out a reading that belongs to the next run", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    status(FOLLOWER, 10, 100),
    say(70, "All champions dead: 3 killed."),
    status(FOLLOWER, 70, 200),
    status(FOLLOWER, 500, 900),
  ]);
  expect(pollux.xp?.gained).toBe(100);
});

test("no XP from a single reading", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    status(FOLLOWER, 20, 100),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(pollux.xp).toBeNull();
});

test("measures XP per damage over the span the readings cover", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    hit(FOLLOWER, 20, 999),
    status(FOLLOWER, 30, 100),
    hit(FOLLOWER, 40, 50),
    status(FOLLOWER, 50, 6100),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(pollux.damageInXpSpan).toBe(50);
  expect(pollux.damage).toBe(1049);
});

test("splits damage by monster, for a circuit that also kills warriors", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    hit(FOLLOWER, 20, 100),
    say(70, "All champions dead: 3 killed."),
    hit(FOLLOWER, 75, 30, "elven warrior"),
    say(100, "Fighting the champions here."),
    hit(FOLLOWER, 110, 100),
    say(150, "All champions dead: 3 killed."),
    hit(FOLLOWER, 90, 40, "elven warrior"),
  ]);
  expect(pollux.damageByMonster).toEqual({ "elven champion": 200, "elven warrior": 70 });
});

test("counts Ready time before the next swing as idle", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    ...poll(20, { Pollux: "Resting" }),
    ...poll(23, { Pollux: "Ready" }),
    hit(FOLLOWER, 30, 40),
    ...poll(40, { Pollux: "Resting" }),
    ...poll(43, { Pollux: "Ready" }),
    event(FOLLOWER, 45, "our-miss"),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(pollux.readyIdleS).toBe(9);
  expect(pollux.readyCycles).toBe(2);
});

test("does not count the Ready wait before a chase as idle", () => {
  const { pollux } = chars([
    say(10, "Fighting the champions here."),
    say(20, "Room clear. Chasing the one that went n."),
    ...poll(30, { Pollux: "Resting" }),
    ...poll(33, { Pollux: "Ready" }),
    hit(FOLLOWER, 40, 40),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(pollux.readyCycles).toBe(0);
});

test("reports the lowest health and any death", () => {
  const [section] = buildReport([
    say(10, "Fighting the champions here."),
    ...poll(20, { Pollux: "Ready" }, 70),
    ...poll(23, { Pollux: "Ready" }, 90),
    event(FOLLOWER, 30, "our-death"),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(section.chars.pollux.lowestHealth).toBe(70);
  expect(section.chars.pollux.deaths).toBe(1);
  expect(section.runs[0].lowestHealth).toEqual({ player: "Pollux", pct: 70 });
});

test("adds up time at home, chasing and between runs", () => {
  const [section] = buildReport([
    say(0, "Fighting the champions here."),
    say(60, "Room clear. Chasing the one that went n."),
    say(90, "All champions dead: 3 killed."),
    say(130, "Fighting the champions here."),
    say(200, "All champions dead: 3 killed."),
  ]);
  expect([section.homeS, section.chaseS, section.betweenS, section.spanS]).toEqual([130, 30, 40, 200]);
});

test("counts only champion deaths as the run's kills", () => {
  const [section] = buildReport([
    say(10, "Fighting the champions here."),
    event(LEADER, 20, "monster-death", { monster: "elven champion" }),
    event(LEADER, 21, "monster-death", { monster: "elven warrior" }),
    say(70, "All champions dead: 1 killed."),
  ]);
  expect(section.runs[0].kills).toBe(1);
});

test("each leader log is its own section, in time order", () => {
  const second = LEADER.replace("08-51-43", "10-00-00");
  const report = buildReport([
    { ...say(600, "Fighting the champions here."), file: second },
    { ...say(650, "All champions dead: 3 killed."), file: second },
    say(10, "Fighting the champions here."),
    say(70, "All champions dead: 3 killed."),
  ]);
  expect(report.map(s => s.leaderFile)).toEqual([LEADER, second]);
});

test("formats a section, marking an unfinished run", () => {
  const [section] = buildReport([
    say(10, "Fighting the champions here."),
    status(FOLLOWER, 10, 100),
    hit(FOLLOWER, 20, 50),
    status(FOLLOWER, 40, 6100),
  ]);
  const text = formatSection(section);
  expect(text).toContain("1 run(s) over");
  expect(text).toContain("1*");
  expect(text).toContain("the log ended before this run did");
  expect(text).toContain("pollux");
});
