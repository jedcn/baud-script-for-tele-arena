// log.ts — turn raw baud session logs into normalized JSONL events.
//
// The logs are raw terminal capture: ANSI escapes, backspaces, BBS splash art,
// and game text all interleaved, with only occasional timestamps. Every ad-hoc
// analysis of them re-derives the same three things — strip the control codes,
// work out what time a line happened, and decide what kind of line it is — and
// gets them subtly wrong in different ways each time. This does it once.
//
//   bun log.ts normalize logs/session-pelayo-2026-08-09T13-34-09.log
//   bun log.ts normalize logs/session-*2026-08-09*.log --out /tmp/day.jsonl
//   bun log.ts normalize logs/*.log --stats        # kind histogram, no records
//
// Output is one JSON object per line, ordered as in the file, so it composes
// with jq. Merging several characters' logs is just concatenation plus a sort
// on `iso` — that is what makes a team fight readable.

import { readFileSync, writeFileSync } from "fs";
import { basename } from "path";

// ── Record shape ───────────────────────────────────────────────────────────────

type TimeSource = "debug" | "statusbar" | "bbs" | "carried" | "start";

interface Event {
  file: string;
  char: string;          // "pelayo", from the filename
  session: string;       // "2026-08-09T13-34-09", from the filename
  line: number;          // 1-based, into the cleaned text
  time: string | null;   // local wall clock, "13:34:28"
  iso: string | null;    // local absolute, "2026-08-09T13:34:28" — sort key
  timeSource: TimeSource;
  kind: string;
  text: string;
  [field: string]: unknown;
}

// ── Cleaning ───────────────────────────────────────────────────────────────────

// ANSI sequences in these files are NOT reliably confined to one line: the
// capture can split one mid-parameter, so the raw bytes hold "\x1b[1" + "\n" +
// ";37;46m". Stripping line-by-line (the obvious `sed` reflex) leaves ";37;46m"
// behind as text and — worse — leaves a phantom line break in the middle of a
// game line. So the strip has to run over the whole buffer, and the character
// class has to admit the newline.
function clean(raw: string): string {
  const text = raw
    .replace(/\0/g, "")
    // CSI: params (digits, ; ? < > =, and stray newlines) then a final byte.
    .replace(/\x1b\[[0-9;?<>=\n]*[ -/]*[@-~]/g, "")
    // Other escapes: charset selection, single-char escapes, OSC strings.
    .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b[()][A-Za-z0-9]/g, "")
    .replace(/\x1b./g, "")
    .replace(/\r/g, "");
  return text.includes("\x08") ? applyBackspaces(text) : text;
}

// The BBS prompt spinner writes backspaces; apply them rather than leaving the
// overwritten characters in place. A linear scan, not a regex — consecutive
// backspaces each cancel one more character, which a pairwise pattern gets
// wrong. Spelled \x08, never \b: outside a character class \b is a word
// boundary, and /[^\n\b]\b/ silently deletes the last letter of every word
// instead ("Sorry, you'll" -> "Sorr,yolhav").
function applyBackspaces(text: string): string {
  const out: string[] = [];
  for (const ch of text) {
    if (ch !== "\x08") { out.push(ch); continue; }
    // Never erase across a line boundary.
    if (out.length > 0 && out[out.length - 1] !== "\n") out.pop();
  }
  return out.join("");
}

// Box-drawing and block glyphs. The BBS banner, the menu, and the game's own
// splash are made of these; three or more on a line means it is furniture.
const ART = /[│├└┌┐┘┴┬┤─┼█▄▀░▒▓▌▐]/g;

function isArt(text: string): boolean {
  const hits = text.match(ART);
  return hits != null && hits.length >= 3;
}

// The BBS hard-wraps at 78 columns mid-sentence, so a single game line can
// arrive as two. Left alone this is not just cosmetic — "The gargoyle attacked
// Tojolias, but its wicked claws glanced off Tojolias's" / "armor!" matches no
// pattern at all, and the event is silently lost. Rejoin a long line that stops
// without terminal punctuation, keeping the first line's number.
const WRAP_MIN = 70;

function unwrap(lines: string[]): { n: number; text: string }[] {
  const out: { n: number; text: string }[] = [];
  for (let i = 0; i < lines.length; i++) {
    let text = lines[i].replace(/\s+$/, "");
    const n = i + 1;
    while (
      text.length >= WRAP_MIN &&
      !/[.!?:]$/.test(text) &&
      !isArt(text) &&
      i + 1 < lines.length
    ) {
      const next = lines[i + 1].replace(/\s+$/, "");
      // Never swallow a blank line, a prompt echo, or an injected debug echo —
      // those are their own records, not a continuation of this sentence.
      if (next.trim() === "" || next.startsWith(">") ||
          next.trim().startsWith("[T]") || isArt(next)) break;
      text = text + " " + next.trim();
      i++;
    }
    out.push({ n, text });
  }
  return out;
}

// ── Time ───────────────────────────────────────────────────────────────────────

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

// Lines that carry a real clock. The arena debug echoes are the dense source
// (one every few seconds during a fight); the BBS status bar and the logon/logoff
// broadcasts are sparse but carry the date too.
const RE_DEBUG_TIME = /^\[T\] (\d{2}:\d{2}:\d{2}) (.*)$/;
const RE_STATUS_BAR = /■\s*(\d{2}:\d{2}:\d{2})\s*■\s*(\d{2})-([A-Z]{3})-(\d{2})\s*■/;
const RE_BBS_PRESENCE = /logs (ON|OFF)[^[]*\[(\d{2})-([A-Z]{3})-(\d{2})\/(\d{2}:\d{2}:\d{2})\]/;

function secondsOfDay(hhmmss: string): number {
  const [h, m, s] = hhmmss.split(":").map(Number);
  return h * 3600 + m * 60 + s;
}

function pad(n: number, width = 2): string {
  return String(n).padStart(width, "0");
}

// The header records the session start in UTC ("# baud text log - started
// 2026-08-09T17:34:09.286Z") while every in-band clock is local. Rather than
// hardcode a zone — these logs travel between a laptop and a VPS — recover the
// offset from the first in-band time, rounded to a quarter hour. Anything within
// a few minutes of the header is the same instant, so the rounding is safe.
function inferOffsetMinutes(headerUtcMs: number, firstLocal: string): number {
  const utc = new Date(headerUtcMs);
  const utcSecs = utc.getUTCHours() * 3600 + utc.getUTCMinutes() * 60 + utc.getUTCSeconds();
  let delta = secondsOfDay(firstLocal) - utcSecs;
  if (delta > 14 * 3600) delta -= 24 * 3600;
  if (delta < -12 * 3600) delta += 24 * 3600;
  return Math.round(delta / 900) * 15;
}

// Walks the local wall clock forward, rolling the date over when the clock wraps
// past midnight. A session can straddle midnight; without this, sorting a merged
// multi-character stream would shuffle the small hours to the front.
class Clock {
  private y: number;
  private mo: number;
  private d: number;
  private lastSecs = -1;

  constructor(startLocalMs: number) {
    const t = new Date(startLocalMs);
    this.y = t.getUTCFullYear();
    this.mo = t.getUTCMonth();
    this.d = t.getUTCDate();
  }

  // Anchor the date explicitly (from a status bar or logon broadcast, which
  // carry DD-MMM-YY) so a long gap in the in-band clock can't drift the day.
  setDate(day: number, mon: string, yy: number): void {
    const mi = MONTHS.indexOf(mon);
    if (mi < 0) return;
    this.y = 2000 + yy;
    this.mo = mi;
    this.d = day;
  }

  iso(hhmmss: string): string {
    const secs = secondsOfDay(hhmmss);
    // A jump backwards of more than an hour is midnight, not clock jitter — the
    // in-band times are seconds apart in practice.
    if (this.lastSecs >= 0 && secs + 3600 < this.lastSecs) {
      const next = new Date(Date.UTC(this.y, this.mo, this.d + 1));
      this.y = next.getUTCFullYear();
      this.mo = next.getUTCMonth();
      this.d = next.getUTCDate();
    }
    this.lastSecs = secs;
    return `${this.y}-${pad(this.mo + 1)}-${pad(this.d)}T${hhmmss}`;
  }
}

// ── Line classification ────────────────────────────────────────────────────────
//
// The patterns mirror main.lua's triggers, which are the authoritative
// vocabulary for this game's text — when the script learns a new line, this list
// should learn it too. Order matters: the first match wins, so specific forms
// come before the general ones they would otherwise be swallowed by.

interface Rule {
  kind: string;
  re: RegExp;
  fields?: (m: RegExpMatchArray) => Record<string, unknown>;
}

// The verbs a monster deals damage through. Anything that hits US carries a
// number; the same verb aimed at a party member does not, which is why the two
// are separate kinds rather than one with an optional field.
const HIT_VERBS = [
  /^The (.+) attacked you .+ for (\d+) damage!$/,
  /^The (.+) hurled a boulder at you for (\d+) damage!$/,
  /^The (.+) picks up and hurls you for (\d+) damage!$/,
  /^The (.+) breathed flames at you for (\d+) damage!$/,
  /^The (.+) discharged .+ at you for (\d+) damage!$/,
  /^The (.+) viciously bit you for (\d+) damage!$/,
  /^The (.+) lashed out with its tail for (\d+) damage!$/,
  /^The (.+) charged you for (\d+) damage!$/,
  /^The (.+) expelled a ball of fire at you for (\d+) damage!$/,
  /^The (.+) exhaled a blast of flame at you for (\d+) damage!$/,
];

const RULES: Rule[] = [
  // — our combat —
  { kind: "our-hit", re: /^Your attack hit the (.+) for (\d+) damage!$/,
    fields: m => ({ monster: m[1], damage: +m[2] }) },
  { kind: "our-miss", re: /^Your attack missed!$/ },
  { kind: "monster-dodge", re: /^The (.+) dodged your attack!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "our-spell-hit", re: /^You discharged the spell at the (.+) for (\d+) damage!$/,
    fields: m => ({ monster: m[1], damage: +m[2] }) },
  { kind: "our-spell-heal", re: /^You discharged the spell at friendly people in the area, healing (\d+) damage!$/,
    fields: m => ({ healed: +m[1], target: "party" }) },
  { kind: "our-spell-heal", re: /^You intoned the spell for (.+) which healed (\d+) damage!$/,
    fields: m => ({ healed: +m[2], target: m[1] }) },
  { kind: "spell-failed", re: /^You confuse the key syllables and the spell fails!$/ },
  { kind: "spell-negated", re: /^Your spell was negated by the (.+)'s magickal defenses!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "mana-low", re: /^Your mana is too low to cast that spell\.$/ },

  // — incoming —
  { kind: "monster-glance", re: /^The (.+) attacked you, but .+ glanced off your armor!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "monster-miss", re: /^The (.+?)'?s? .+ misses? you!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "our-dodge", re: /^You barely dodge the (.+)'s attack!$/,
    fields: m => ({ monster: m[1] }) },

  // — other players —
  { kind: "other-attack", re: /^(.+) just attacked the (.+) with (?:an?|the) (.+)!$/,
    fields: m => ({ player: m[1], monster: m[2], weapon: m[3] }) },
  { kind: "other-miss", re: /^(.+)'s poorly executed attack misses the (.+)!$/,
    fields: m => ({ player: m[1], monster: m[2] }) },
  { kind: "other-dodged", re: /^The (.+) barely dodged (.+)'s .+!$/,
    fields: m => ({ monster: m[1], player: m[2] }) },

  // — lifecycle —
  { kind: "our-death", re: /^As the final blow strikes your body you fall unconscious\.$/ },
  { kind: "revive", re: /^You awaken after an unknown amount of time\.\.\.$/ },
  { kind: "player-death", re: /^(.+) just fell to the ground lifeless!$/,
    fields: m => ({ player: m[1] }) },
  { kind: "monster-death", re: /^The (.+) falls to the ground lifeless!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "monster-spawn", re: /^An? (.+) appears in a puff of .+ smoke!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "monster-arrive", re: /^An? (.+) enters the arena through the dungeon gate!$/,
    fields: m => ({ monster: m[1] }) },
  { kind: "our-gong", re: /^You just rang the great gong!$/ },
  { kind: "other-gong", re: /^(.+) just rang the great gong!$/,
    fields: m => ({ player: m[1] }) },

  // — blocked actions. The reason a flee fails is the whole point of most of
  //   these investigations, so each refusal gets its own kind.
  { kind: "blocked-move-rest", re: /^Sorry, you'll have to rest a while before you can move\.$/ },
  { kind: "blocked-move-battle", re: /^You cannot leave in the heat of battle!$/ },
  { kind: "blocked-action-exhausted", re: /^You are still physically exhausted from your previous activities!$/ },
  { kind: "blocked-action-mental", re: /^You are still too mentally exhausted from your last incantation!$/ },
  { kind: "blocked-move-noexit", re: /^Sorry, there's no exit in that direction\.$/ },
  { kind: "blocked-move-door", re: /^The locked (.+) door prevents your exit in that direction\.$/,
    fields: m => ({ door: m[1] }) },
  { kind: "trip", re: /^In your haste, you trip and fall!$/ },

  // — movement / room —
  { kind: "room", re: /^You're (?:in|on|at|inside|outside) (?:an? |the )?(.+)\.$/,
    fields: m => ({ room: m[1], via: "move" }) },
  { kind: "room", re: /^You are (?:in|on|at|inside|outside) (?:an? |the )?(.+)\.$/,
    fields: m => ({ room: m[1], via: "look" }) },
  { kind: "exits", re: /^Exits: (.+)\.$/, fields: m => ({ exits: m[1] }) },
  { kind: "occupants", re: /^There is nobody here\.$/, fields: () => ({ occupants: [] }) },
  { kind: "occupants", re: /^There (?:is|are) (.+) here\.$/,
    fields: m => ({ occupants: m[1] }) },
  { kind: "occupants", re: /^(.+) (?:is|are) here\.$/, fields: m => ({ occupants: m[1] }) },
  { kind: "floor", re: /^There is nothing on the floor\.$/, fields: () => ({ items: [] }) },
  { kind: "floor", re: /^There is (.+) lying on the floor\.$/, fields: m => ({ items: m[1] }) },
  { kind: "other-move", re: /^(.+) has just gone (?:to the )?(.+)\.$/,
    fields: m => ({ player: m[1], direction: m[2] }) },
  { kind: "other-arrive", re: /^(.+) has just arrived from (?:the )?(.+)\.$/,
    fields: m => ({ player: m[1], direction: m[2] }) },
  { kind: "other-trip", re: /^(.+) tripped and fell to the floor!$/,
    fields: m => ({ player: m[1] }) },
  { kind: "other-ambient", re: /^(.+) is taking (?:inventory of|a look around)/,
    fields: m => ({ player: m[1] }) },
  { kind: "other-ambient", re: /^You hear (.+)'s stomach growling\.$/,
    fields: m => ({ player: m[1] }) },
  { kind: "other-ambient", re: /^You notice (.+) doing something out of the corner of your eye\.$/,
    fields: m => ({ player: m[1] }) },
  { kind: "bad-command", re: /^Sorry, that is not an appropriate command\.$/ },
  { kind: "group-header", re: /^Your group currently consists of:$/ },
  { kind: "group-member", re: /^\s*(\S+)\s*(\(L\))?\s*\[HE:\s*(\d+)% ST:(\S+)\]$/,
    fields: m => ({ player: m[1], leader: m[2] != null, healthPct: +m[3], stamina: m[4] }) },

  // — economy —
  { kind: "heal-bought", re: /^The priests heal all your wounds for (\d+) crowns\.$/,
    fields: m => ({ cost: +m[1] }) },
  { kind: "cant-afford", re: /^You can't afford (.+)\.$/, fields: m => ({ item: m[1] }) },
  { kind: "bought", re: /^Ok, you bought (?:an? )?(.+) for (\d+) crowns\.$/,
    fields: m => ({ item: m[1], cost: +m[2] }) },
  { kind: "drink", re: /^You feel somehow different after drinking the potion\.$/ },
  { kind: "potion-expired", re: /^An odd tingling sensation washes over you briefly!$/ },
  { kind: "gold", re: /^You are carrying (\d+) gold crowns/,
    fields: m => ({ gold: +m[1] }) },
  { kind: "loot", re: /^You found (\d+) gold crowns while searching the (.+)'s corpse\.$/,
    fields: m => ({ gold: +m[1], monster: m[2] }) },
  { kind: "loot", re: /^You found (\d+) gold crowns while searching the area\.$/,
    fields: m => ({ gold: +m[1], monster: null }) },
  { kind: "bought", re: /^The barmaid brings you an? (\S+) for (\d+) crowns\.$/,
    fields: m => ({ item: m[1], cost: +m[2] }) },

  // — needs / condition —
  { kind: "hungry", re: /^You're hungry\.$/ },
  { kind: "thirsty", re: /^You're thirsty\.$/ },
  { kind: "poisoned", re: /^You're poisoned!$/ },

  // — team speech —
  { kind: "team-msg-in", re: /^From (.+?)(?: \(to group\))?: (.+)$/,
    fields: m => ({ player: m[1], message: m[2] }) },
  { kind: "team-msg-sent", re: /^-- Message sent --$/ },

  // — session —
  { kind: "game-enter", re: /^Entering Tele-Arena\.\.\.$/ },
  { kind: "game-exit", re: /^Exiting Tele-Arena\.\.\.$/ },
  { kind: "other-enter", re: /^(.+) has just entered Tele-Arena\.$/,
    fields: m => ({ player: m[1] }) },
  { kind: "other-exit", re: /^(.+) has just exited Tele-Arena\.$/,
    fields: m => ({ player: m[1] }) },
];

// Commands we send or type. Recognized so a command echo is never mistaken for
// game text — and so `origin` can tell a scripted swing from a hand-typed one,
// which is exactly the distinction that explains a death after the fact.
const RE_COMMAND = new RegExp(
  "^(?:" + [
    "[nsew]|[ns][ew]|u|d|up|down",           // movement
    "a .+|k .+|attack .+",                    // melee
    "cast .+|c .+",                           // spells
    "buy .+|b .+|sell .+|drink .+|get .+|drop .+",
    "ring gong|rest|search|ex|exits|look.*|l .*|l|st|status|i|inv|spells|gr|group",
    "x|y|n",                                  // exit handshake
    "push .+|pull .+|open .+|unlock .+",
    "[a-z-]+-[a-z-]+",                        // baud aliases, e.g. map-print-slug
    // A bare lowercase token: "reroll", or a spell name typed at a prompt
    // ("kusamotumaru"). Game text is capitalized and punctuated, and this is
    // only reached after every game pattern has already declined the line.
    "[a-z][a-z0-9]{1,19}",
  ].join("|") + ")$"
);

// Speech the arena script says out loud. Short, capitalized, no game punctuation
// — indistinguishable from prose by shape alone, so list them.
const SPOKEN = new Set(["I need healing", "I am healed"]);

function classify(text: string): { kind: string; fields: Record<string, unknown> } {
  for (const verb of HIT_VERBS) {
    const m = text.match(verb);
    if (m) return { kind: "incoming-hit", fields: { monster: m[1], damage: +m[2] } };
  }
  // Same verbs aimed at someone else: no damage number is printed.
  const other = text.match(/^The (.+?) (?:attacked|exhaled a blast of flame at|breathed flames at|hurled a boulder at|charged|viciously bit) (.+?)(?: with .+)?!$/);
  if (other && other[2] !== "you") {
    return { kind: "monster-vs-other", fields: { monster: other[1], target: other[2] } };
  }
  for (const rule of RULES) {
    const m = text.match(rule.re);
    if (m) return { kind: rule.kind, fields: rule.fields ? rule.fields(m) : {} };
  }
  return { kind: "unknown", fields: {} };
}

// ── Status blocks ──────────────────────────────────────────────────────────────
//
// `st` prints eighteen lines that are only meaningful together. Emitting them
// individually is how you end up scrolling back through a log hunting for the
// max-HP that made a flee threshold make sense; emit one record instead.

const STATUS_FIELDS: Record<string, [string, "int" | "str" | "pair"]> = {
  "Race": ["race", "str"],
  "Class": ["class", "str"],
  "Level": ["level", "int"],
  "Experience": ["xp", "int"],
  "Rune": ["rune", "str"],
  "Intellect": ["intellect", "int"],
  "Knowledge": ["knowledge", "int"],
  "Physique": ["physique", "int"],
  "Stamina": ["stamina", "int"],
  "Agility": ["agility", "int"],
  "Charisma": ["charisma", "int"],
  "Mana": ["mana", "pair"],
  "Vitality": ["vitality", "pair"],
  "Status": ["condition", "str"],
  "Armor Rating": ["armorRating", "int"],
  "Weapon": ["weapon", "str"],
  "Armor": ["armor", "str"],
  "Encumberance": ["encumbrance", "pair"],
};

const RE_STATUS_LINE = /^([A-Za-z ]+):\s+(.+)$/;

// ── Normalize ──────────────────────────────────────────────────────────────────

function normalizeFile(path: string): Event[] {
  const raw = readFileSync(path, "latin1");
  const utf8 = readFileSync(path, "utf8");
  // Prefer the utf8 read (the art is box-drawing), but fall back if it mangles.
  const text = clean(utf8.includes("�") ? raw : utf8);
  const lines = text.split("\n");
  const logical = unwrap(lines);

  const name = basename(path);
  const parsed = name.match(/^session-(.+?)-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})/);
  const char = parsed ? parsed[1] : "unknown";
  const session = parsed ? parsed[2] : name;

  const header = text.match(/^# baud text log - started (\S+)/);
  const headerMs = header ? Date.parse(header[1]) : NaN;

  // First pass: find an in-band clock so the UTC header can be localized.
  let firstLocal: string | null = null;
  for (const line of lines) {
    const d = line.match(RE_DEBUG_TIME);
    if (d) { firstLocal = d[1]; break; }
    const s = line.match(RE_STATUS_BAR);
    if (s) { firstLocal = s[1]; break; }
    const b = line.match(RE_BBS_PRESENCE);
    if (b) { firstLocal = b[5]; break; }
  }
  const offset = Number.isNaN(headerMs) || !firstLocal
    ? 0
    : inferOffsetMinutes(headerMs, firstLocal);
  const clock = new Clock(Number.isNaN(headerMs) ? Date.now() : headerMs + offset * 60_000);

  const events: Event[] = [];
  let time: string | null = null;
  let timeSource: TimeSource = "start";

  // The carried clock only ever moves forward. A stray out-of-order stamp would
  // otherwise rewind every subsequent line; a real midnight rollover is a jump
  // back of nearly a full day, which this still lets through.
  const advance = (t: string, src: TimeSource) => {
    if (time != null) {
      const delta = secondsOfDay(t) - secondsOfDay(time);
      if (delta < 0 && delta > -20 * 3600) return;
    }
    time = t;
    timeSource = src;
  };
  // Commands typed by hand, awaiting their echo from the BBS.
  const typed: string[] = [];
  let status: Record<string, unknown> | null = null;
  let statusLine = 0;

  const flushStatus = (upto: number) => {
    if (!status) return;
    events.push({
      file: name, char, session, line: statusLine,
      time, iso: time ? clock.iso(time) : null, timeSource,
      kind: "status", text: `status block (lines ${statusLine}-${upto})`,
      endLine: upto, ...status,
    });
    status = null;
  };

  // Everything before "Entering Tele-Arena..." and after "Exiting Tele-Arena..."
  // is dialup furniture: the logon banner, the door menu, the account screen. A
  // structural rule beats pattern-matching each menu row, and it keeps `unknown`
  // meaning "a game line we do not understand yet" — which is the only reading
  // that makes the stats output useful for improving this file.
  let inGame = false;

  logical.forEach(({ n, text }) => {
    const trimmed = text.trim();

    // — clocks, before anything else, so the line they sit on is dated by itself
    const debug = trimmed.match(RE_DEBUG_TIME);
    if (debug) {
      flushStatus(n - 1);
      advance(debug[1], "debug");
      events.push({
        file: name, char, session, line: n, time, iso: clock.iso(time!),
        timeSource, kind: "debug", text: trimmed, message: debug[2],
      });
      return;
    }
    // Echoes the lua script printed to its own console ("[arena] Heading to
    // bar.", "[nav|t] 13:22:04 +1502ms  send step 4/9 se"). Not game text, but
    // the only record of what the script believed it was doing — which is half
    // of every post-mortem. Some carry their own clock; use it.
    // Tags are not all lowercase words: "[re-roll]", "[nav|t]", "[DB→rooms]".
    const script = trimmed.match(/^\[([^\]\s]{1,16})\] (.*)$/);
    if (script) {
      flushStatus(n - 1);
      const stamped = script[2].match(/^(\d{2}:\d{2}:\d{2})\s+(.*)$/);
      if (stamped) advance(stamped[1], "debug");
      events.push({
        file: name, char, session, line: n,
        time, iso: time ? clock.iso(time) : null,
        timeSource: stamped ? "debug" : (timeSource === "start" ? "start" : "carried"),
        kind: "script", text: trimmed, tag: script[1],
        message: stamped ? stamped[2] : script[2],
      });
      return;
    }

    const bar = text.match(RE_STATUS_BAR);
    if (bar) {
      flushStatus(n - 1);
      clock.setDate(+bar[2], bar[3], +bar[4]);
      advance(bar[1], "statusbar");
      events.push({
        file: name, char, session, line: n, time, iso: time ? clock.iso(time) : null,
        timeSource, kind: "bbs-clock", text: trimmed,
      });
      return;
    }
    const presence = text.match(RE_BBS_PRESENCE);
    if (presence) {
      flushStatus(n - 1);
      // Date only. Unlike the debug echoes and the status bar — both written at
      // the moment they are displayed — a logon broadcast states when the event
      // happened, and the BBS can deliver it minutes late. Adopting it as the
      // clock drags every following line backwards: Pelayo's hand-typed attacks
      // dated 13:31:42 when they really happened just after 13:34:28.
      clock.setDate(+presence[2], presence[3], +presence[4]);
      events.push({
        file: name, char, session, line: n,
        time: presence[5], iso: null, timeSource: "bbs",
        kind: "bbs-presence", text: trimmed,
        who: text.match(/^(\S+) logs/)?.[1] ?? null,
        action: presence[1],
      });
      return;
    }

    if (trimmed === "") { flushStatus(n - 1); return; }

    const at = () => ({
      file: name, char, session, line: n,
      time, iso: time ? clock.iso(time) : null,
      timeSource: (timeSource === "start" ? "start" : "carried") as TimeSource,
    });

    // baud's own first line, holding the session start in UTC.
    if (trimmed.startsWith("# baud text log")) {
      events.push({ ...at(), kind: "header", text: trimmed, startedUtc: header?.[1] ?? null });
      return;
    }

    // — status block accumulation
    const field = trimmed.match(RE_STATUS_LINE);
    if (field && STATUS_FIELDS[field[1]]) {
      const [key, type] = STATUS_FIELDS[field[1]];
      if (field[1] === "Race" || !status) { flushStatus(n - 1); status = {}; statusLine = n; }
      if (type === "int") status![key] = parseInt(field[2], 10);
      else if (type === "pair") {
        const p = field[2].match(/(\d+)\s*\/\s*(\d+)/);
        if (p) { status![key] = +p[1]; status![key + "Max"] = +p[2]; }
      } else status![key] = field[2].trim();
      if (field[1] === "Encumberance") flushStatus(n);
      return;
    }
    flushStatus(n - 1);

    // — BBS furniture
    if (isArt(trimmed)) {
      events.push({ ...at(), kind: "noise", text: trimmed });
      return;
    }

    // — a command typed by hand: baud echoes it locally with a prompt, which is
    //   the only thing that distinguishes it from a command the script sent.
    const prompt = text.match(/^>\s?(.*)$/);
    if (prompt) {
      const cmd = prompt[1].trim();
      if (cmd !== "") typed.push(cmd);
      events.push({ ...at(), kind: "input", text: trimmed, command: cmd, origin: "user" });
      return;
    }

    const { kind, fields } = classify(trimmed);
    if (kind === "game-enter") inGame = true;
    if (kind !== "unknown") {
      events.push({ ...at(), kind, text: trimmed, ...fields });
      if (kind === "game-exit") inGame = false;
      return;
    }

    // — a command echoed back by the BBS. Attribute it: if it matches the oldest
    //   unconsumed hand-typed command, it is that one arriving; otherwise the
    //   script sent it. This is a heuristic, but it is the one that separates a
    //   scripted `a flame` from a hand-typed `a giant`.
    if (RE_COMMAND.test(trimmed) || SPOKEN.has(trimmed)) {
      const idx = typed.indexOf(trimmed);
      if (idx >= 0) typed.splice(idx, 1);
      events.push({
        ...at(), kind: "sent", text: trimmed, command: trimmed,
        origin: idx >= 0 ? "user" : "script",
      });
      return;
    }

    events.push({ ...at(), kind: inGame ? "unknown" : "bbs", text: trimmed });
  });
  flushStatus(lines.length);

  return events;
}

// ── CLI ────────────────────────────────────────────────────────────────────────

function main(): void {
  const argv = process.argv.slice(2);
  const command = argv[0];
  if (command !== "normalize") {
    console.error("usage: bun log.ts normalize <logfile...> [--out FILE] [--stats]");
    process.exit(2);
  }

  const args = argv.slice(1);
  const stats = args.includes("--stats");
  const outIdx = args.indexOf("--out");
  const out = outIdx >= 0 ? args[outIdx + 1] : null;
  const files = args.filter((a, i) =>
    !a.startsWith("--") && !(outIdx >= 0 && i === outIdx + 1));

  if (files.length === 0) {
    console.error("no log files given");
    process.exit(2);
  }

  const all: Event[] = [];
  for (const f of files) all.push(...normalizeFile(f));

  if (stats) {
    const counts = new Map<string, number>();
    for (const e of all) counts.set(e.kind, (counts.get(e.kind) ?? 0) + 1);
    for (const [kind, n] of [...counts].sort((a, b) => b[1] - a[1])) {
      console.log(String(n).padStart(7), kind);
    }
    console.log(String(all.length).padStart(7), "TOTAL");
    return;
  }

  const jsonl = all.map(e => JSON.stringify(e)).join("\n") + "\n";
  if (out) writeFileSync(out, jsonl);
  else process.stdout.write(jsonl);
}

// Only when run as a program — importing this from a test must not parse argv.
if (import.meta.main) main();

export { clean, unwrap, classify, normalizeFile, inferOffsetMinutes };
export type { Event };
