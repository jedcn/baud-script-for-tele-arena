// Tests for log.ts. Every case here is a shape that actually appears in the
// session logs and that a naive strip-and-grep gets wrong — these are the
// reasons the normalizer exists rather than being a one-line sed.

import { test, expect } from "bun:test";
import { mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { clean, unwrap, classify, normalizeFile } from "./log";

// ── cleaning ───────────────────────────────────────────────────────────────────

test("applies backspaces instead of deleting word endings", () => {
  // The bug this guards: /[^\n\b]\b/ reads \b as a word boundary outside a
  // character class, turning every line into "Sorr,yolhavtreswhilbeforyocamov."
  expect(clean("Sorry, you'll have to rest a while.")).toBe(
    "Sorry, you'll have to rest a while.");
  expect(clean("abcX\b")).toBe("abc");
  expect(clean("abcXY\b\b")).toBe("abc");
});

test("strips an ANSI sequence split across a newline", () => {
  // Real bytes from session-pelayo-2026-08-09T13-34-09.log: the capture broke
  // ESC[1;37;46m in half. Stripping per-line leaves ";37;46m" as visible text
  // and a phantom line break in the middle of a game line.
  expect(clean("before\x1b[1\n;37;46mafter")).toBe("beforeafter");
  expect(clean("\x1b[2Jhello\x1b[0m")).toBe("hello");
});

test("drops NUL bytes", () => {
  expect(clean("a\0b")).toBe("ab");
});

// ── wrapping ───────────────────────────────────────────────────────────────────

test("rejoins a line the BBS hard-wrapped at 78 columns", () => {
  const lines = [
    "The gargoyle attacked Tojolias, but its wicked claws glanced off Tojolias's",
    "armor!",
  ];
  const [first] = unwrap(lines);
  expect(first.text).toBe(
    "The gargoyle attacked Tojolias, but its wicked claws glanced off Tojolias's armor!");
  expect(first.n).toBe(1); // keeps the first physical line's number
});

test("does not swallow the next line when one ends in punctuation", () => {
  const lines = [
    "You found 17 gold crowns while searching the flame giant's corpse. Nice.",
    "You're in the arena.",
  ];
  expect(unwrap(lines).length).toBe(2);
});

test("does not swallow a prompt echo or a debug echo into a wrapped line", () => {
  const long = "Kerhak just attacked the flame giant with a rimeax and kept going";
  expect(unwrap([long, "> st"]).length).toBe(2);
  expect(unwrap([long, "[T] 13:34:28 flee-triggered"]).length).toBe(2);
});

// ── classification ─────────────────────────────────────────────────────────────

test("reads damage off an incoming special-verb hit", () => {
  const e = classify("The flame giant exhaled a blast of flame at you for 395 damage!");
  expect(e.kind).toBe("incoming-hit");
  expect(e.fields).toEqual({ monster: "flame giant", damage: 395 });
});

test("counts a rogue's skillful attack as one of our hits", () => {
  const e = classify("Your skillful attack hit the apollyon dragon for 58 damage!");
  expect(e.kind).toBe("our-hit");
  expect(e.fields).toEqual({ monster: "apollyon dragon", damage: 58 });
});

test("separates a special aimed at someone else, which carries no number", () => {
  const e = classify("The flame giant exhaled a blast of flame at Pelayo!");
  expect(e.kind).toBe("monster-vs-other");
  expect(e.fields).toEqual({ monster: "flame giant", target: "Pelayo" });
});

test("tells a player death from a monster death", () => {
  expect(classify("Pelayo just fell to the ground lifeless!").kind).toBe("player-death");
  expect(classify("The flame giant falls to the ground lifeless!").kind).toBe("monster-death");
});

test("recognizes our own death and the blocked moves around it", () => {
  expect(classify("As the final blow strikes your body you fall unconscious.").kind)
    .toBe("our-death");
  expect(classify("Sorry, you'll have to rest a while before you can move.").kind)
    .toBe("blocked-move-rest");
  expect(classify("You cannot leave in the heat of battle!").kind)
    .toBe("blocked-move-battle");
  expect(classify("You are still physically exhausted from your previous activities!").kind)
    .toBe("blocked-action-exhausted");
});

test("distinguishes a walked room from a looked-at one", () => {
  expect(classify("You're in the arena.").fields).toEqual({ room: "arena", via: "move" });
  expect(classify("You are in the arena.").fields).toEqual({ room: "arena", via: "look" });
});

// ── whole-file normalize ───────────────────────────────────────────────────────

function fixture(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), "logtest-"));
  const path = join(dir, "session-pelayo-2026-08-09T13-34-09.log");
  writeFileSync(path, body);
  return path;
}

const HEADER = "# baud text log - started 2026-08-09T17:34:09.286Z\n";

test("attributes a hand-typed command to the user and a scripted one to the script", () => {
  // This is the distinction that explained Pelayo's death: the script targets a
  // monster by its FIRST word ("a flame"), so "a giant" was typed by hand. baud
  // echoes typed input locally with a "> " prompt; script sends have none.
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "[T] 13:34:18 attack-sent",
    "a flame",
    "> a giant",
    "a giant",
  ].join("\n")));
  const sent = events.filter(e => e.kind === "sent");
  expect(sent.map(e => [e.command, e.origin])).toEqual([
    ["a flame", "script"],
    ["a giant", "user"],
  ]);
});

test("collapses an st block into one status record", () => {
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "[T] 13:34:28 flee-triggered",
    "Race:         Dwarven",
    "Class:        Acolyte",
    "Level:        18",
    "Vitality:     350 / 434",
    "Encumberance: 920 / 1000",
  ].join("\n")));
  const status = events.filter(e => e.kind === "status");
  expect(status.length).toBe(1);
  expect(status[0].vitality).toBe(350);
  expect(status[0].vitalityMax).toBe(434);
  expect(status[0].encumbrance).toBe(920);
  expect(status[0].encumbranceMax).toBe(1000);
  expect(status[0].class).toBe("Acolyte");
});

test("carries the clock forward and dates lines from the UTC header", () => {
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "[T] 13:34:28 flee-triggered",
    "Sorry, you'll have to rest a while before you can move.",
  ].join("\n")));
  const blocked = events.find(e => e.kind === "blocked-move-rest")!;
  expect(blocked.time).toBe("13:34:28");
  expect(blocked.iso).toBe("2026-08-09T13:34:28");
  expect(blocked.timeSource).toBe("carried"); // no clock of its own — say so
});

test("a late logon broadcast never rewinds the clock", () => {
  // The BBS states when the logon happened, not when it was delivered. Adopting
  // it dated Pelayo's hand-typed attacks three minutes before they occurred.
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "[T] 13:34:28 flee-triggered",
    "Tojolias logs ON line 5.  [09-AUG-26/13:31:42] Users Online: 3: ",
    "Sorry, you'll have to rest a while before you can move.",
  ].join("\n")));
  expect(events.find(e => e.kind === "blocked-move-rest")!.time).toBe("13:34:28");
});

test("classifies dialup furniture outside the game as bbs, not unknown", () => {
  // `unknown` has to keep meaning "a game line we don't understand yet",
  // otherwise --stats is useless for finding gaps in the patterns.
  const events = normalizeFile(fixture(HEADER + [
    "Main System Menu (TOP)",
    "Entering Tele-Arena...",
    "You're in the arena.",
    "Exiting Tele-Arena...",
    "(N)onstop, (Q)uit, or (C)ontinue?",
  ].join("\n")));
  expect(events.filter(e => e.kind === "unknown").length).toBe(0);
  expect(events.filter(e => e.kind === "bbs").length).toBe(2);
});
