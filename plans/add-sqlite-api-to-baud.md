# Plan: SQLite API for baud + Tele-Arena database schema

## Overview

Two-part plan:
1. Modify baud (TypeScript) to expose a SQLite API to Lua scripts
2. Build a Tele-Arena Lua module that uses that API to maintain a game database

---

## Part 1: baud changes (~/src/baud)

### Dependency

Add `better-sqlite3` (not `node:sqlite`). It is **synchronous**, which maps cleanly onto
Lua's synchronous execution model — no Promises, no callbacks, no async complications in
the wasmoon sandbox.

```
npm install better-sqlite3
npm install --save-dev @types/better-sqlite3
```

### Database location

A fixed absolute path the Lua side can rely on:

```
~/Library/Application Support/baud/tele-arena.db
```

Expose it as a Lua global so scripts can reference it without hardcoding:

```typescript
lua.set("BAUD_DB_PATH", path.join(os.homedir(), "Library", "Application Support", "baud", "tele-arena.db"))
```

### Three new Lua globals

Follow the same registration pattern used for `send`, `echo`, `createTrigger`, etc.

```typescript
import Database from "better-sqlite3"
import * as os from "os"
import * as path from "path"

const dbPath = path.join(os.homedir(), "Library", "Application Support", "baud", "tele-arena.db")
const db = new Database(dbPath)
db.pragma("journal_mode = WAL")  // safe for concurrent reads

// Execute a statement (INSERT, UPDATE, CREATE TABLE, DELETE).
// Returns number of rows changed.
lua.set("dbExecute", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).run(...params).changes
})

// Query returning all matching rows as an array of objects.
// Lua receives this as a table of tables.
lua.set("dbQuery", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).all(...params)
})

// Query returning the first matching row, or nil.
lua.set("dbQueryOne", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).get(...params) ?? null
})
```

### Acceptance check

After the change, this should work from baud's `/lua` console:

```
/lua dbExecute("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, val TEXT)")
/lua dbExecute("INSERT INTO test (val) VALUES (?)", "hello")
/lua local row = dbQueryOne("SELECT * FROM test WHERE val = ?", "hello"); echo(row.val)
-- should print: hello
```

### Note on session.log

The plan below relies on `echo()` calls for debug output. For these to appear in
session.log, baud's logger must include echo output alongside server text. Verify
(or add) this behavior before implementing Part 2.

---

## Part 2: Tele-Arena Lua module (this repo)

### New file: `ta_db.lua`

A module loaded by `main.lua` via `dofile(scriptDir .. "ta_db.lua")`. Responsible for:
- Creating all tables on first load (idempotent `CREATE TABLE IF NOT EXISTS`)
- Exposing functions called by triggers in `main.lua`

`main.lua` stores the module reference in `taPackage.db` and calls its functions
from trigger callbacks.

### Schema

```sql
-- World map
CREATE TABLE IF NOT EXISTS rooms (
  name         TEXT PRIMARY KEY,
  description  TEXT,
  first_visited TEXT,
  visits       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS room_exits (
  from_room  TEXT NOT NULL REFERENCES rooms(name),
  direction  TEXT NOT NULL,
  to_room    TEXT REFERENCES rooms(name),  -- nullable: exit known but not yet walked
  PRIMARY KEY (from_room, direction)
);

-- Inhabitants
CREATE TABLE IF NOT EXISTS monsters (
  name        TEXT PRIMARY KEY,
  description TEXT,
  first_seen  TEXT,
  encounters  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS denizens (
  name        TEXT NOT NULL,
  location    TEXT NOT NULL,
  description TEXT,
  first_seen  TEXT,
  PRIMARY KEY (name, location)
);

-- Economy
CREATE TABLE IF NOT EXISTS shop_items (
  name       TEXT NOT NULL,
  shop       TEXT NOT NULL,
  price      INTEGER,
  min_level  INTEGER,  -- filled in when "too inexperienced" purchase is attempted
  first_seen TEXT,
  PRIMARY KEY (name, shop)
);

CREATE TABLE IF NOT EXISTS services (
  name       TEXT NOT NULL,
  location   TEXT NOT NULL,
  cost       INTEGER,
  first_used TEXT,
  uses       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (name, location)
);

-- Character progression
CREATE TABLE IF NOT EXISTS stat_changes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  stat        TEXT NOT NULL,
  from_value  INTEGER NOT NULL,
  to_value    INTEGER NOT NULL,
  recorded_at TEXT NOT NULL
);

-- Combat log
CREATE TABLE IF NOT EXISTS player_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  weapon      TEXT NOT NULL,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,  -- "hit", "miss", "dodge"
  damage      INTEGER,        -- null on miss/dodge
  recorded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS monster_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,  -- "hit", "glanced", "miss"
  damage      INTEGER,        -- null on miss/glanced
  recorded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS monster_loot (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  gold        INTEGER NOT NULL DEFAULT 0,
  recorded_at TEXT NOT NULL
);
```

### Echo debug format

Every DB write produces a short `echo()` line prefixed with the table name.
These appear in-game and in session.log for post-session review.

```
[DB→rooms] north plaza (visit #3)
[DB→room_exits] north plaza --east--> arena
[DB→monsters] new: lizard woman
[DB→monsters] seen: lizard woman (encounter #4)
[DB→denizens] new: crimson mage @ magic shop
[DB→shop_items] weapon shop: mace 35gp
[DB→services] temple: healing 2gp (use #3)
[DB→stat_changes] Physique: 29 → 30
[DB→player_attacks] Mace HIT huge rat: 10 dmg
[DB→player_attacks] Mace MISS huge rat
[DB→monster_attacks] huge rat HIT you: 3 dmg
[DB→monster_attacks] huge rat MISS
[DB→monster_loot] huge rat: 0 gold
[DB→monster_loot] lizard woman: 4 gold
```

### Triggers to add to main.lua

**Room entry** — `^You're in the (.+)\.$`
- Upsert room (INSERT OR IGNORE, then increment visits)
- If previously-known room: update visits only
- Echo: `[DB→rooms]`

**Room exit detection** — outbound trigger on movement commands (n, s, e, w, ne, nw, se, sw)
paired with the next room-entry trigger
- Record `room_exits (from_room, direction, to_room)`
- Echo: `[DB→room_exits]`

**Monster in room** — existing `^There is a (.+) here\.$` trigger
- Increment `monsters.encounters` if known
- Echo: `[DB→monsters] seen: X (encounter #N)`

**Monster enters** — existing `^An? (.+) enters` trigger
- Same as above

**Look at monster** — existing multi-line accumulator
- Upsert `monsters (name, description, first_seen)`
- Echo: `[DB→monsters] new/updated: X`

**Look at denizen** — similar multi-line accumulator (for non-hostile NPCs)
- Upsert `denizens (name, location, description, first_seen)`
- Echo: `[DB→denizens]`

**Shop item list** — multi-line accumulator triggered by `list items` echo,
terminated by `+=====+` closing line
- Upsert `shop_items (name, shop, price, first_seen)`
- Echo: `[DB→shop_items]`

**Too inexperienced** — `^You are too inexperienced to use that item\.$`
- Update `shop_items.min_level` for the last attempted purchase
- Echo: `[DB→shop_items] min_level updated`

**Services purchased**
- Temple healing: existing trigger `^The priests heal all your wounds for (\d+) crowns\.$`
  → upsert `services (healing, temple, cost)`, increment uses
- Tavern drink: `^The barmaid brings you a drink for (\d+) crowns\.$`
  → upsert `services (drink, tavern, cost)`, increment uses
- Echo: `[DB→services]`

**Stat changes** — after each `status` block, compare new values to stored values
- Log any change to `stat_changes`
- Echo: `[DB→stat_changes]`

**Player attack outcomes**
- `^Your attack hit the (.+) for (\d+) damage!$` → outcome=hit
- `^Your attack missed!$` → outcome=miss
- `^The (.+) dodged your attack!$` → outcome=dodge
- Echo: `[DB→player_attacks]`

**Monster attack outcomes**
- `^The (.+) attacked you .+ for (\d+) damage!$` → outcome=hit
- `^The (.+)'s .+ glanced off your armor!$` → outcome=glanced
- `^The (.+)'s .+ misses you!$` → outcome=miss
- Echo: `[DB→monster_attacks]`

**Monster loot** — existing trigger `^You found (\d+) gold crowns while searching`
- Insert `monster_loot (monster, gold)`
- Also insert `monster_loot (monster, 0)` on kill with no loot
  (detect via `^The (.+) falls to the ground lifeless!$` with no following gold line)
- Echo: `[DB→monster_loot]`

### Implementation order

1. Part 1: Add SQLite API to baud, verify acceptance check passes
2. Verify `echo()` output appears in session.log
3. Create `ta_db.lua` with schema initialization
4. Wire `ta_db.lua` into `main.lua` initialization block
5. Add triggers one table at a time, testing each with session.log review
6. Suggested order: rooms → room_exits → monsters → player_attacks → monster_attacks
   → monster_loot → shop_items → services → denizens → stat_changes

### Verification

After a short play session:
- Run `/lua taPackage.db.rooms()` (or similar query helper) to see visited rooms
- Run `/lua taPackage.db.path()` to confirm DB path
- Open `tele-arena.db` in any SQLite browser to inspect tables directly
- Review session.log `[DB→...]` lines to trace every write that occurred
