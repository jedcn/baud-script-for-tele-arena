# Plan: Tele-Arena SQLite database

## Context

This repo (~/src/baud-script-for-tele-arena) contains Lua scripts for the Tele-Arena
game, loaded by the baud BBS client. baud has been extended with three Lua globals for
SQLite access:

- `dbExecute(sql, ...params)` — runs INSERT/UPDATE/CREATE/DELETE, returns rows changed
- `dbQuery(sql, ...params)` — returns all matching rows as a table of tables
- `dbQueryOne(sql, ...params)` — returns first matching row or nil
- `BAUD_DB_PATH` — absolute path to `~/Library/Application Support/baud/tele-arena.db`

The existing script is `main.lua`. It uses `createTrigger(pattern, callback, {type="regex"})`
to match lines from the game server and maintain in-memory state in `taPackage`.

The test suite is in `test/main_spec.lua` using the Busted framework. Run with `just test`.
The test helper (`test/test_helper.lua`) mocks all baud globals including `echo`.

## Goal

Build a persistent database of game knowledge that populates automatically as the player
moves through the world. Every write to the database should produce an `echo()` line in
the format `[DB→tablename] ...details...` so the player can watch the DB update in real
time and these lines are captured in session.log for post-session review.

## New file: ta_db.lua

Create `ta_db.lua` alongside `main.lua`. It is loaded by `main.lua` via:

```lua
local TaDb = dofile(scriptDir .. "ta_db.lua")
taPackage.db = TaDb
```

`ta_db.lua` is responsible for:
1. Creating all tables on first load (idempotent `CREATE TABLE IF NOT EXISTS`)
2. Exposing functions that triggers in `main.lua` call to record game events

### Schema

```sql
-- World map
CREATE TABLE IF NOT EXISTS rooms (
  name          TEXT PRIMARY KEY,
  description   TEXT,
  first_visited TEXT,
  visits        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS room_exits (
  from_room  TEXT NOT NULL REFERENCES rooms(name),
  direction  TEXT NOT NULL,
  to_room    TEXT REFERENCES rooms(name),
  PRIMARY KEY (from_room, direction)
);
-- to_room is nullable: we may know an exit exists (from a room description)
-- before the player has walked it.

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
  min_level  INTEGER,
  first_seen TEXT,
  PRIMARY KEY (name, shop)
);
-- min_level is filled in when "You are too inexperienced to use that item."
-- is seen after a purchase attempt.

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

-- Combat
CREATE TABLE IF NOT EXISTS player_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  weapon      TEXT NOT NULL,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,   -- "hit", "miss", "dodge"
  damage      INTEGER,         -- null on miss/dodge
  recorded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS monster_attacks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  outcome     TEXT NOT NULL,   -- "hit", "glanced", "miss"
  damage      INTEGER,         -- null on miss/glanced
  recorded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS monster_loot (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  monster     TEXT NOT NULL,
  gold        INTEGER NOT NULL DEFAULT 0,
  recorded_at TEXT NOT NULL
);
```

### ta_db.lua public functions

```lua
TaDb.visitRoom(name, description)
TaDb.recordExit(fromRoom, direction, toRoom)
TaDb.upsertMonster(name, description)       -- from look
TaDb.recordMonsterSeen(name)                -- from "There is a X here" or "A X enters"
TaDb.upsertDenizen(name, location, description)
TaDb.recordShopItem(name, shop, price)
TaDb.recordMinLevel(name, shop, level)
TaDb.recordService(name, location, cost)
TaDb.recordStatChange(stat, fromVal, toVal)
TaDb.recordPlayerAttack(weapon, monster, outcome, damage)
TaDb.recordMonsterAttack(monster, outcome, damage)
TaDb.recordMonsterLoot(monster, gold)
```

Each function writes to the DB and calls `echo()` with a `[DB→tablename]` prefix.

## Echo debug format

```
[DB→rooms] north plaza (visit #3)
[DB→room_exits] north plaza --east--> arena
[DB→monsters] new: lizard woman
[DB→monsters] seen: lizard woman (encounter #4)
[DB→denizens] new: crimson mage @ magic shop
[DB→shop_items] weapon shop: mace 35gp
[DB→shop_items] min_level updated: cuirass @ armor shop >= level 2
[DB→services] temple: healing 2gp (use #3)
[DB→stat_changes] Physique: 29 → 30
[DB→player_attacks] Mace HIT huge rat: 10 dmg
[DB→player_attacks] Mace MISS huge rat
[DB→monster_attacks] huge rat HIT you: 3 dmg
[DB→monster_attacks] huge rat MISS
[DB→monster_loot] huge rat: 0 gold
[DB→monster_loot] lizard woman: 4 gold
```

## Triggers to add to main.lua

### Room entry — `^You're in the (.+)\.$`
Calls `TaDb.visitRoom(name)`.
Also: store current room in `taPackage.currentRoom` so exit tracking works.

### Movement commands — outbound or echo triggers on n/s/e/w/ne/nw/se/sw
Track `taPackage.pendingDirection` when the player issues a move command.
When the next room-entry trigger fires, call `TaDb.recordExit(prevRoom, direction, newRoom)`.

### Monster in room — `^There is a (.+) here\.$`
Calls `TaDb.recordMonsterSeen(name)`.

### Monster enters — `^An? (.+) enters `
Calls `TaDb.recordMonsterSeen(name)`.

### Look at monster — multi-line accumulator (already exists)
On finalization calls `TaDb.upsertMonster(name, description)`.

### Look at denizen — similar multi-line accumulator (new)
Non-hostile NPCs also have descriptions. Detect by absence of health line:
if accumulation ends without a health line (e.g., player looks at another room or
issues a new command), check if the description looks like an NPC (no combat health
phrases). Call `TaDb.upsertDenizen(name, currentRoom, description)`.
Alternatively: separate trigger path for known denizen names.

### Shop item list — multi-line accumulator
Triggered by detecting `list items` echo. Each `| item   | price |` line is parsed.
Terminated by the closing `+=====+` line.
Calls `TaDb.recordShopItem(name, currentRoom, price)` for each item.

### Too inexperienced — `^You are too inexperienced to use that item\.$`
Track `taPackage.lastAttemptedPurchase`. On this line, call
`TaDb.recordMinLevel(lastAttemptedPurchase, currentRoom, currentLevel + 1)`.

### Services purchased
- `^The priests heal all your wounds for (\d+) crowns\.$`
  → `TaDb.recordService("healing", "temple", cost)`
- `^The barmaid brings you a drink for (\d+) crowns\.$`
  → `TaDb.recordService("drink", "tavern", cost)`

### Stat changes
After each full `status` block is received, compare all stat values to last-known.
Log any changes via `TaDb.recordStatChange(stat, old, new)`.
Store last-known stats in `taPackage.character` (already partially populated).

### Player attack outcomes
- `^Your attack hit the (.+) for (\d+) damage!$` → hit, parse monster + damage
- `^Your attack missed!$` → miss (use `taPackage.lastAttackTarget`)
- `^The (.+) dodged your attack!$` → dodge
All call `TaDb.recordPlayerAttack(currentWeapon, monster, outcome, damage)`.

### Monster attack outcomes
- `^The (.+) attacked you .+ for (\d+) damage!$` → hit
- `^The (.+)'s .+ glanced off your armor!$` → glanced
- `^The (.+)'s? .+ misses? you!$` → miss
All call `TaDb.recordMonsterAttack(monster, outcome, damage)`.

### Monster loot
- `^You found (\d+) gold crowns while searching` → `TaDb.recordMonsterLoot(monster, gold)`
- `^The (.+) falls to the ground lifeless!$` → set `taPackage.lastKilledMonster`;
  if no gold line follows before the next non-combat line, call
  `TaDb.recordMonsterLoot(monster, 0)`.

## Testing approach

The test helper mocks `dbExecute`, `dbQuery`, `dbQueryOne` as no-ops that record calls,
following the same pattern used to mock `createTrigger` and `echo`. Tests verify that
the right DB function is called with the right arguments when a trigger fires.

Add a new `describe("ta_db", ...)` block in `test/main_spec.lua`.

## Implementation order

Work one table at a time. After each, play a short session and review the session.log
`[DB→...]` lines to verify correct behavior before moving on.

1. `rooms` — room entry trigger
2. `room_exits` — movement tracking
3. `monsters` — look accumulator + seen triggers (already partially built)
4. `player_attacks` + `monster_attacks` — combat triggers
5. `monster_loot` — kill + gold triggers
6. `shop_items` — list parsing
7. `services` — healing + drink triggers
8. `denizens` — NPC look accumulator
9. `stat_changes` — status block comparison

## Verification

After a play session:
- Check session.log for `[DB→...]` lines covering all expected events
- Open `~/Library/Application Support/baud/tele-arena.db` in a SQLite browser
  to inspect table contents directly
- Run `/lua local r = dbQueryOne("SELECT * FROM rooms WHERE name = ?", "north plaza"); echo(r.name .. " visits: " .. r.visits)`
