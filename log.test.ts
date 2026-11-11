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

// A long note typed in-game ran on through the next lines and swallowed
// `$ team-fight-champions` and the script's own echo, hiding a whole run.
test("does not swallow an alias or a script echo into a wrapped line", () => {
  const long = "TO FUTURE CLAUDE ANALYST, GREAT, THEY ARE BACK, RUNNING TEAM-FIGHT-CHAMPIONS";
  expect(unwrap([long, "$ team-fight-champions"]).length).toBe(2);
  expect(unwrap([long, "[champions] Fighting the champions here."]).length).toBe(2);
});

test("does not wrap a typed command onto what follows it", () => {
  const long = "> TO FUTURE CLAUDE ANALYST, GREAT, THEY ARE BACK, RUNNING TEAM-FIGHT-CHAMPIONS";
  expect(unwrap([long, "TO FUTURE"]).length).toBe(2);
});

test("rejoins a wrapped sentence across baud's clock tick", () => {
  const long = "The elven champion barely dodged Teekywiki's Twin Katanas and kept on going";
  const lines = [long, "[T] 08:12:59 tick", "going!"];
  expect(unwrap(lines).map((l) => l.text)).toEqual([`${long} going!`]);
});

test("does not treat a tick as a sentence's continuation", () => {
  const long = "The elven champion barely dodged Teekywiki's Twin Katanas and kept on going";
  expect(unwrap([long, "[T] 08:12:59 tick"]).length).toBe(2);
  expect(unwrap([long, "[T] 08:12:59 tick", "> st"]).length).toBe(3);
});

// ── classification ─────────────────────────────────────────────────────────────

test("reads damage off an incoming special-verb hit", () => {
  const e = classify("The flame giant exhaled a blast of flame at you for 395 damage!");
  expect(e.kind).toBe("incoming-hit");
  expect(e.fields).toEqual({ monster: "flame giant", damage: 395 });
});

test("reads damage off a frost breath as well as a flame one", () => {
  const e = classify("The ice giantess exhaled a blast of frost at you for 60 damage!");
  expect(e.kind).toBe("incoming-hit");
  expect(e.fields).toEqual({ monster: "ice giantess", damage: 60 });
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

test("reads the 'down in' brief of the shaft below the crooked path as a move", () => {
  expect(classify("You're down in a hole.").fields).toEqual({ room: "hole", via: "move" });
});

test("reads the Elven Valley brief, which has no full stop, as a move", () => {
  expect(classify("You're on a path in the Elven Valley").fields)
    .toEqual({ room: "path in the Elven Valley", via: "move" });
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

test("leaves origin unknown once baud logs script sends with the same prompt", () => {
  // From baud e46e03d (2026-08-13) a script's send() is logged as "> cmd"
  // exactly like typed input, so the prompt no longer says who sent it. Both
  // of these were the script's in session-pollux-2026-10-10T23-28-55.log.
  const path = fixture([
    "# baud text log - started 2026-10-10T23:28:56.000Z",
    "Entering Tele-Arena...",
    "> ring gong",
    "ring gong",
    "> a flame",
    "a flame",
  ].join("\n"));
  const events = normalizeFile(path);
  const withOrigin = events.filter(e => e.kind === "sent" || e.kind === "input");
  expect(withOrigin.length).toBe(4);
  expect(withOrigin.every(e => e.origin === "unknown")).toBe(true);
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

test("classifies a sprung trap, with the type the mapper stores", () => {
  // These were `unknown` until Stoneworks level 2 was walked into [T2]
  // (logs/session-tojolias-2026-09-13T19-34-24.log line 290). A trap prints no
  // damage number, so the line itself is the only record that one fired -- and
  // the `trap` field is the same string main.lua writes to rooms.trap, so a log
  // can be checked against the map.
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "Several large stones fall on you from above!",
    "You just fell through a trap door in the floor!",
  ].join("\n")));
  expect(events.filter(e => e.kind === "unknown").length).toBe(0);
  expect(events.find(e => e.kind === "trap")!.trap).toBe("falling rocks");
  expect(events.find(e => e.kind === "trap-door")!.trap).toBe("trap door");
});

test("reads the version of baud and of the scripts", () => {
  const events = normalizeFile(fixture([
    "# baud text log - started 2026-11-07T23:10:00.000Z - baud 2d3407b",
    "Starting to read main.lua (10399d4)",
    "Finishing reading main.lua (10399d4)",
    "[T] 18:20:01 tick",
    "Starting to read main.lua (10399d4-dirty)",
    "Finishing reading main.lua (10399d4-dirty)",
  ].join("\n")));
  const header = events.find(e => e.kind === "header");
  expect(header?.baudVersion).toBe("2d3407b");
  expect(header?.startedUtc).toBe("2026-11-07T23:10:00.000Z");
  const loads = events.filter(e => e.kind === "script-load");
  expect(loads.map(e => [e.phase, e.scriptVersion])).toEqual([
    ["start", "10399d4"], ["finish", "10399d4"],
    ["start", "10399d4-dirty"], ["finish", "10399d4-dirty"],
  ]);
});

test("reads logs from before either version was recorded", () => {
  const events = normalizeFile(fixture(HEADER + [
    "Starting to read main.lua",
    "Finishing reading main.lua",
  ].join("\n")));
  expect(events.find(e => e.kind === "header")?.baudVersion).toBeNull();
  const loads = events.filter(e => e.kind === "script-load");
  expect(loads.map(e => [e.phase, e.scriptVersion])).toEqual([["start", null], ["finish", null]]);
});

// logs/session-johnsonite-2026-11-11T16-28-22.log, line 108: a character with no
// Rune at the docks. Wrapped at 78 columns like any long line.
test("names the ferry's refusal of a character with no Rune", () => {
  const [line] = unwrap([
    "Sorry, by decree of the guild masters, no one shall venture across the great",
    "lake who does not bear a rune upon their brow.",
  ]);
  expect(classify(line.text).kind).toBe("blocked-ferry-rune");
});

test("names the ferry's refusal of a character short of the fare", () => {
  expect(classify("Sorry, you cannot afford passage across the great lake!").kind)
    .toBe("blocked-ferry-gold");
});

// logs/session-tojolias-2026-11-11T17-19-17.log, line 3201.
test("names a ferry crossing", () => {
  expect(classify("You buy passage across the great lake and board a ship...").kind)
    .toBe("ferry-crossed");
});

// Lines that were `unknown` across the logs of 2026-11-07..11, most of them from
// team-fight-elves. Each is a real line from those logs.
test.each([
  ["Teekywiki just attacked the elven champion with Twin Katanas!", "other-attack",
    { player: "Teekywiki", monster: "elven champion", weapon: "Twin Katanas" }],
  ["Pelayo just attacked the elven warrior with a Charred Mace!", "other-attack",
    { player: "Pelayo", monster: "elven warrior", weapon: "Charred Mace" }],
  ["Pelayo barely dodged the elven champion's attack!", "other-dodge",
    { player: "Pelayo", monster: "elven champion" }],
  ["The elven warrior's poorly executed attack misses Castor!", "monster-miss-other",
    { monster: "elven warrior", player: "Castor" }],
  ["Pelayo just discharged a very dark bluish mist at friendly people in the area!", "other-spell-heal",
    { player: "Pelayo", target: "party" }],
  ["Pelayo just intoned a very powerful healing spell for Pelayo!", "other-spell-heal",
    { player: "Pelayo", target: "Pelayo" }],
  ["-- Message sent only to group --", "team-msg-sent", {}],
  ["Castor just shared 37 gold with the group, your share was 9 gold.", "gold-share-in",
    { player: "Castor", total: 37, amount: 9 }],
  ["You shared 40 gold with the group, each share was 10 gold.", "gold-share-out",
    { total: 40, share: 10 }],
  ["Pelayo just gave you 50 gold coins.", "gold-given-in", { player: "Pelayo", amount: 50 }],
  ["You gave 50 gold coins to Castor.", "gold-given-out", { amount: 50, player: "Castor" }],
  ["Pelayo just handed some gold coins to Castor.", "other-gold-given", { player: "Pelayo", to: "Castor" }],
  ["Pelayo just gave you an Ecliptic Glaive.", "item-given-in", { player: "Pelayo", item: "Ecliptic Glaive" }],
  ["You deposited 300 gold in your account.", "bank-deposit", { amount: 300 }],
  ["You withdrew 100 gold from your account.", "bank-withdraw", { amount: 100 }],
  ["You currently have 812 gold in your account.", "bank-balance", { amount: 812 }],
  ["Ok, you sold a waterskin for 2 gold crowns.", "sold", { item: "waterskin", amount: 2 }],
  ["Ok, you've asked to join Pelayo's group.", "group-join-asked", { leader: "Pelayo" }],
  ["You are now a member of Pelayo's group.", "group-joined", { leader: "Pelayo" }],
  ["You are no longer a member of Pelayo's group.", "group-left", { leader: "Pelayo" }],
  ["Pollux is asking to join your group.", "group-asking", { player: "Pollux", leader: "us" }],
  ["Castor is asking to join Pelayo's group.", "group-asking", { player: "Castor", leader: "Pelayo" }],
  ["Pollux is now a member of your group.", "group-added", { player: "Pollux", leader: "us" }],
  ["Teekywiki has been accepted into Pelayo's group.", "group-added", { player: "Teekywiki", leader: "Pelayo" }],
  ["Sorry, you are not the leader of a group.", "not-leader", {}],
  ["Sorry, you don't see \"warrior\" nearby.", "not-here", { target: "warrior" }],
  ["Pelayo just took a drink of something.", "other-drink", { player: "Pelayo" }],
  ["Castor is looking rather parched.", "other-thirsty", { player: "Castor" }],
  ["Pelayo just bought a rowan potion from the shopkeeper.", "other-bought", { player: "Pelayo", item: "rowan potion" }],
  ["Castor just sold a waterskin to the shopkeeper.", "other-sold", { player: "Castor", item: "waterskin" }],
  ["Pelayo just picked up a soulstone.", "other-pickup", { player: "Pelayo", item: "soulstone" }],
  ["Pelayo is looking to the east.", "other-look", { player: "Pelayo", at: "east" }],
  ["Pelayo is looking the elven champion over.", "other-look", { player: "Pelayo", at: "the elven champion" }],
] as [string, string, Record<string, unknown>][])("names %p", (text, kind, fields) => {
  const got = classify(text);
  expect(got.kind).toBe(kind);
  expect(got.fields).toMatchObject(fields);
});

test("reads group, gold and talk commands as sent, not unknown", () => {
  const events = normalizeFile(fixture(HEADER + [
    "Entering Tele-Arena...",
    "confer kill warrior",
    "share 40",
    "join pelayo",
    "add castor",
    "give castor 50 gold",
    "deposit 300",
    "wi 100",
    "say ether",
  ].join("\n")));
  expect(events.filter(e => e.kind === "unknown")).toEqual([]);
  expect(events.filter(e => e.kind === "sent")).toHaveLength(8);
});
