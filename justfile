BAUD_HOME := "~/src/baud"

install:
    luarocks install busted

test:
    busted test/
    bun test

# Turn raw session logs into normalized JSONL events — always the first step
# when analyzing a log (see CLAUDE.md "Session logs"). Writes to stdout, so
# pipe it to jq. Example:
#   just normalize logs/session-kerhak-2026-08-09T14-48-21.log | jq -r 'select(.kind=="incoming-hit")'
normalize +files:
    bun log.ts normalize {{files}}

# Which kinds of line a set of logs contains, and how many of each. A high
# `unknown` count means log.ts needs new patterns, not that the logs are odd.
normalize-stats +files:
    bun log.ts normalize {{files}} --stats

# Launch baud. The label names both the session log and the character to log in
# as: main.lua reads TA_CHARACTER and answers the BBS login and menus itself.
# TA_PASSWORD comes from your own environment (export it in ~/.zshrc or pass it
# inline: `TA_PASSWORD=... just run kerhak`) so it never lands in this repo.
# Without either variable baud still starts; you just log in by hand.
#
# TA_INIT_CMD, also inherited from your environment, is what to run once the
# character is in the game and its sheet has come back:
#   TA_INIT_CMD="rg 2" just run kerhak
# It goes through baud's runCommand, so aliases work, and `&&` chains the way
# typed input does: TA_INIT_CMD="drink hys && rg 2".
run label:
    mkdir -p ./logs
    TA_CHARACTER={{label}} bun run {{BAUD_HOME}}/src/main.tsx --profile sat5 --script ./main.lua --log-text ./logs/session-{{label}}-$(date +%Y-%m-%dT%H-%M-%S).log

report:
    bun report.ts && open report.html

# Move every log out of ./logs into the sibling archive repo, so the working
# logs directory only ever holds the current run's sessions.
archive-logs:
    #!/usr/bin/env bash
    set -euo pipefail
    dest=../tele-arena-archived-session-logs
    shopt -s nullglob dotglob
    logs=(./logs/*)
    if [ ${#logs[@]} -eq 0 ]; then
        echo "archive-logs: ./logs is empty, nothing to move"
        exit 0
    fi
    mkdir -p "$dest"
    mv -n "${logs[@]}" "$dest"/
    echo "archive-logs: moved ${#logs[@]} file(s) to $dest"

# Snapshot the live DB into the sibling tele-arena-db repo (as a SQL dump) and
# commit it. Run before a risky hand-edit instead of making a .db.bak copy.
# Usage: just db-snapshot "why I'm about to change the DB"
db-snapshot why:
    sqlite3 tele-arena.db .dump > ../tele-arena-db/tele-arena.sql
    git -C ../tele-arena-db add tele-arena.sql
    git -C ../tele-arena-db diff --cached --quiet && echo "db-snapshot: no changes since last snapshot" || git -C ../tele-arena-db commit -m "{{why}}"
