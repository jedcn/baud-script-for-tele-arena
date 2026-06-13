# Task: Expose native file read/write to baud's Lua scripting environment

## Background

baud is a BBS client (~/src/baud) that embeds Lua 5.4 via wasmoon (WebAssembly). Lua scripts
can call baud-provided globals like `send()`, `echo()`, `createTrigger()`, etc.

The Lua environment uses wasmoon's in-memory virtual filesystem, so Lua's standard `io.open`
writes to an in-memory FS that disappears when baud closes — not to the real macOS filesystem.
`io.popen` and `os.execute` are also unavailable/broken in this sandbox.

## What needs to be added

Expose two new globals to the Lua environment that use Node.js `fs` to read/write real files:

- `writeFile(path, content)` — writes `content` (string) to the absolute path, returns `true`
  on success or `false` on error
- `readFile(path)` — reads and returns the file content as a string, or `nil` if the file
  doesn't exist or can't be read

These should follow the same pattern as existing baud Lua globals (look at how `send`, `echo`,
`createTrigger`, etc. are registered with the Lua VM).

## Why

A Lua script at ~/src/baud-script-for-tele-arena/main.lua maintains an in-memory monster
database and wants to persist it to disk across sessions. It calls a `db.lua` module that
currently uses `io.open` (broken in sandbox). Once `writeFile`/`readFile` are available, db.lua
will be updated to use them instead.

The target file path will be something like:
  /Users/jednorthridge/src/baud-script-for-tele-arena/monsters.lua

## Acceptance check

After the change, this should work from baud's `/lua` console without error:

  /lua writeFile("/tmp/baud-test.txt", "hello")
  /lua echo(readFile("/tmp/baud-test.txt"))   -- should print: hello
