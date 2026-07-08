# Baud Script for Tele-Arena

## Client

This script runs inside [baud](https://github.com/jedcn/baud), a custom MUD client. If changes are made to .lua files in this directory the user must run `/lua reloadScript()` in their session to get those changes.

What is more: we have control over baud. This means that if we are bumping into a limitation with the script for tele-arena, we can modify the source of baud.

## Scripts

- When adding a new script/mode with its own stop logic, wire its teardown into the `stop-all-scripts` alias in `main.lua`. `stop-all-scripts` is meant to halt *everything*, so factor the stop logic into a shared function (e.g. `stopTavernMode`) and call it from both the script's own `stop-*` alias and from `stop-all-scripts`. Add a case to the `stop-all-scripts` test asserting the new script is stopped too.

## Testing

- Run `just test` after every change to verify nothing is broken.

## Session logs

- Session logs (e.g. `../old-tele-arena-session-logs/`) contain raw terminal output with ANSI escape codes and binary bytes, so `grep` treats them as binary and may skip matches.
- Always search them with `grep -a` (treat as text) — e.g. `grep -a -C 3 "bronze"`. Don't pre-strip escape codes before grepping; a naive strip can eat the first letter of a word that immediately follows a color code and cause you to miss real matches.

## Database cleanup (`tele-arena.db`)

When hand-editing the room graph with `sqlite3` (deleting/merging rooms), the DB is a live directed graph, not a set of independent rows. Mutating it blindly leaves the map subtly broken in ways that only surface later during mapping.

- **Back up first, always.** `cp tele-arena.db "tele-arena.db.bak-$(date +%Y%m%dT%H%M%S)-<why>"` before any mutating statement. baud holds the DB open (WAL mode); CLI writes are safe, but the user must `/lua reloadScript()` afterward so the in-memory graph picks up the change.
- **Deleting a room orphans its neighbors' back-exits.** `DELETE FROM room_exits WHERE from_id=X OR to_id=X` also removes every `neighbor --dir--> X` edge. That silently shrinks the neighbor's exit-set, which is the fingerprint `findLoopClosure` matches on (ta_db.lua) — so a later re-walk fails to recognize the neighbor and mints a *duplicate* room. When you delete a room, **re-stub** each neighbor's edge (`UPDATE room_exits SET to_id=NULL ...`) instead of leaving it gone, so the frontier/fingerprint survives.
- **Prefer merging over delete-and-re-walk** when a duplicate already exists. To merge by hand, faithfully replicate `TaDb.mergeRoomInto` (ta_db.lua) — don't improvise: move the provisional's outgoing edges with `INSERT OR IGNORE` (only ever *fill* a NULL stub on the target, never clobber a real edge), guard against self-loops (`from_id=into AND to_id=from` → NULL), repoint inbound edges (`UPDATE room_exits SET to_id=into WHERE to_id=from`), and carry `visits`/`description`/coords via `COALESCE`. Merge in dependency order (fold the leaf that others point *at* last).
- **Follow `player_location`.** If a player stands in a room you delete/merge, repoint or NULL their `room_id` in the same transaction — nothing enforces the FK, so a dangling id just sits there.
- **Verify reciprocity, not just row counts.** After the edit, confirm every edge has its reverse (`A --se--> B` implies `B --nw--> A`) and that no `to_id` points at a deleted id. A merge that leaves one-directional exits is still broken.
- **Coordinates are soft; topology is truth.** These rooms never sat on a real grid, so dead-reckoned `x/y/z` can be internally contradictory (e.g. `50 se→61` and `60 nw→61` disagreeing by +2). Fix and trust the exit graph; treat coords as a hint that can legitimately be inconsistent.

## Committing

- Don't create new branches. Commit directly to the current branch.
- Commit after every logical change — don't batch unrelated work into one commit.
- Commit immediately after a change is working; don't wait for manual in-game testing.
- If something turns out to be wrong, commit the broken state anyway and fix it in a follow-up commit. A record of what went wrong is more valuable than a clean history.
- Independent changes get independent commits. When changes span the same files, use `git apply --cached` with targeted patch files rather than staging everything at once.
- Write commit messages that explain the *why*, not just the *what*. One-line summary + blank line + body when the change needs context.
