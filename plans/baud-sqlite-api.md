# Plan: Add SQLite API to baud

## Context

baud (~/src/baud) is a TypeScript BBS client that embeds Lua 5.4 via wasmoon (WebAssembly).
Lua scripts call baud-provided globals like `send()`, `echo()`, `createTrigger()`, etc.

The Lua scripting environment uses wasmoon's in-memory virtual filesystem — `io.open`,
`os.execute`, and `io.popen` do not reach the real macOS filesystem. To persist game data
to disk, baud must expose file/database access from the TypeScript side.

The goal of this task is to expose a SQLite API to Lua scripts, following the same pattern
used for existing baud Lua globals.

## Dependency

Add `better-sqlite3` (NOT `node:sqlite`). It is **synchronous**, which is critical — Lua
executes synchronously inside wasmoon, so any database API must return results immediately
without Promises or callbacks.

```
npm install better-sqlite3
npm install --save-dev @types/better-sqlite3
```

## Database location

```
~/Library/Application Support/baud/tele-arena.db
```

This directory already exists (baud uses it for profiles and command history).

## Three new Lua globals

Find where existing Lua globals like `send`, `echo`, and `createTrigger` are registered
with the Lua VM and add these three in the same place.

```typescript
import Database from "better-sqlite3"
import * as os from "os"
import * as path from "path"

const dbPath = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "baud",
  "tele-arena.db"
)
const db = new Database(dbPath)
db.pragma("journal_mode = WAL")

// Execute a statement (INSERT, UPDATE, CREATE TABLE, DELETE).
// Returns number of rows changed.
lua.set("dbExecute", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).run(...params).changes
})

// Query returning all matching rows as a Lua-compatible array of objects.
lua.set("dbQuery", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).all(...params)
})

// Query returning the first matching row as a Lua table, or nil.
lua.set("dbQueryOne", (sql: string, ...params: unknown[]) => {
  return db.prepare(sql).get(...params) ?? null
})
```

Also expose the DB path as a global so Lua scripts don't need to hardcode it:

```typescript
lua.set("BAUD_DB_PATH", dbPath)
```

## Acceptance check

After the change, these should all work from baud's `/lua` console without error:

```
/lua dbExecute("CREATE TABLE IF NOT EXISTS _test (id INTEGER PRIMARY KEY, val TEXT)")
/lua dbExecute("INSERT INTO _test (val) VALUES (?)", "hello")
/lua local row = dbQueryOne("SELECT * FROM _test WHERE val = ?", "hello"); echo(row.val)
```

Expected output from the last line: `hello`

Then clean up: `/lua dbExecute("DROP TABLE _test")`

## Note on session.log

A Lua script will use `echo()` to log every database write as a `[DB→table]` prefixed line.
For post-session debugging these lines need to appear in session.log alongside server output.
Verify that baud's logger includes `echo()` output in the log file. If not, add that behavior
as part of this task.
