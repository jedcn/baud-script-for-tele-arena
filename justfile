BAUD_HOME := "~/src/baud"

install:
    luarocks install busted

test:
    busted test/

run:
    bun run {{BAUD_HOME}}/src/main.tsx --profile sat5 --script ./main.lua

run-and-save-session-log label:
    mkdir -p ./logs
    bun run {{BAUD_HOME}}/src/main.tsx --profile sat5 --script ./main.lua --log-text ./logs/session-{{label}}-$(date +%Y-%m-%dT%H-%M-%S).log

report:
    bun report.ts && open report.html

# Snapshot the live DB into the sibling tele-arena-db repo (as a SQL dump) and
# commit it. Run before a risky hand-edit instead of making a .db.bak copy.
# Usage: just db-snapshot "why I'm about to change the DB"
db-snapshot why:
    sqlite3 tele-arena.db .dump > ../tele-arena-db/tele-arena.sql
    git -C ../tele-arena-db add tele-arena.sql
    git -C ../tele-arena-db diff --cached --quiet && echo "db-snapshot: no changes since last snapshot" || git -C ../tele-arena-db commit -m "{{why}}"

