BAUD_HOME := "~/src/baud"

install:
    luarocks install busted

# Both suites. Grep the tail for `0 fail` as well as busted's success line --
# checking only one of them has hidden real failures before now.
#
# Both always run, and the recipe fails if either did. Previously a busted
# failure aborted the recipe and `bun test` never ran at all, so a red Lua suite
# silently stopped the TypeScript one from being checked -- which is exactly when
# you most want to know the rest still works.
test:
    #!/usr/bin/env bash
    set -uo pipefail
    rc=0
    busted test/ || rc=1
    bun test || rc=1
    exit $rc

# How much of a level have we walked? Prints the SHRINE's own drawing with our
# rooms marked on it, so it can be compared with map/shrine/*.txt at a glance --
# which MAP.md cannot, because map.ts derives its own layout by walking exits.
# Then says what each frontier leads to, separating real unexplored territory
# from unwalked links between rooms we already have.
#   just coverage stoneworks-level-1
coverage slug:
    bun coverage.ts {{slug}}

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
#
# TA_LOGIN_CMD runs much earlier -- at the username prompt, before any of the
# BBS menus -- and is the one to reach for when the character is DEAD. A dead
# character never enters the game, so it never gets a sheet and TA_INIT_CMD can
# never fire; picking 5 at the main menu lands it on the resurrect/create menu
# instead. Making a fresh farming character is the case it exists for:
#   TA_LOGIN_CMD="start-gold-farming" just run garbageman
# Use it to arm a script, not to send text: at the username prompt there is no
# game to send a command to.
#
# The log name is timestamped at launch, so an hour later you no longer know
# which file this session wrote. The EXIT trap prints the path on the way out --
# on a clean quit, a crash, or a Ctrl-C -- so it's the last thing on screen.
run label:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p ./logs
    log="./logs/session-{{label}}-$(date +%Y-%m-%dT%H-%M-%S).log"
    trap 'echo "session log: $log"' EXIT
    TA_CHARACTER={{label}} bun run {{BAUD_HOME}}/src/main.tsx --profile sat5 --script ./main.lua --log-text "$log"

# Build report.html and open it. The build runs the page's own script against a
# stub DOM first, so a report that would render a blank map fails here instead
# of in your browser.
report:
    bun report.ts
    bun test report.test.ts
    open report.html

# Build map.html: the whole mapped world as one browsable page. Pick an Area,
# pick a Level, click a room. Rooms are SVG boxes rather than `[ ]`, so a Device,
# a Trap, a Door, a Seal and an unwalked exit each get their own mark -- see the
# legend on the page.
#
# It reads the checked-in JSON under map/, NOT tele-arena.db, which is the point:
# the export is meant to be enough on its own, and this page is the thing that
# proves it. Run `bun export.ts` first if the database has moved on.
#
# Placement comes from map.ts, the same pass that draws MAP.md, so the two never
# disagree about the shape of a level.
draw-map-as-html:
    #!/usr/bin/env bash
    set -uo pipefail
    # Refresh the export first. The page itself still reads only the checked-in
    # JSON -- that is the point of it, and site.test.ts is what proves it -- but a
    # walk moves the database on and leaves that JSON behind, so on 2026-09-17 a
    # session that mapped 17 new rooms drew a map with none of them on it and
    # nothing said why. Skipped where there is no database to refresh from (the
    # VPS), because there the checked-in JSON is already the whole story.
    [ -f tele-arena.db ] && bun export.ts
    bun site.ts
    bun test site.test.ts
    open map.html

# Draw the mapped areas as ASCII maps in a single Markdown file, MAP.md.
#
# The format is the one the tele-arena shrine used for its hand-drawn town maps
# -- [X] boxes, - | \\ / connectors, ^/v badges for vertical exits, and a key --
# because our generated maps reproduce those drawings room-for-room.
#
# Which areas get drawn is the DRAWN list at the bottom of map.ts. An area only
# renders cleanly if it is tagged tightly (second-town holds exactly its 21
# rooms); a loosely-tagged area draws its wilderness too.
draw-map-as-markdown:
    bun map.ts

# Fetch the shrine's hand-drawn maps into map/shrine/ as raw text. The <pre>
# block is the data -- a character's column says which rooms a connector joins
# -- so these are saved verbatim and never reformatted. Re-run to refresh; the
# files are checked in so a parser change needs no network, and so the material
# survives the site going away.
scrape-shrine-maps:
    bun scrape.ts

# Check that a mapped area is sound. Run it between levels of a mapping session:
#   just verify-area sewers-level-1
# With no slug it checks every area. Checks for unwalked exits, one-directional
# edges, moves that change depth impossibly (which is how a teleport recorded as
# an ordinary exit gives itself away), missing descriptions, and that every room
# can actually be drawn.
#
# And two checks that read the map against the GAME rather than against itself,
# out of every session log in ./logs and the archive: a room id the game showed
# two different exit-sets (two real rooms recorded as one), and a room whose map
# exits are not the ones in its own last `ex` reply. Everything else here is
# self-consistent when the map is conflated, which is how the Complex of Natural
# Caverns passed every check while three of its rooms each stood for two.
verify-area slug="":
    bun verify.ts {{slug}}

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
    moved=0
    already=0
    conflicts=""
    nconflicts=0
    for f in "${logs[@]}"; do
        b=$(basename "$f")
        if [ ! -e "$dest/$b" ]; then
            mv "$f" "$dest/$b"
            moved=$((moved + 1))
        elif cmp -s "$f" "$dest/$b"; then
            # Already in the archive byte-for-byte: the move is a no-op, so
            # finish it by dropping the local copy.
            rm "$f"
            already=$((already + 1))
        else
            # Same name, different bytes -- usually a log that was archived
            # while the session was still writing to it. Never clobber, and
            # never claim to have moved it.
            conflicts="$conflicts  $b"$'\n'
            nconflicts=$((nconflicts + 1))
        fi
    done
    echo "archive-logs: moved $moved file(s) to $dest"
    if [ "$already" -gt 0 ]; then
        echo "archive-logs: removed $already local file(s) already archived byte-for-byte"
    fi
    if [ "$nconflicts" -gt 0 ]; then
        echo "archive-logs: left $nconflicts file(s) in ./logs -- same name in $dest, different contents:"
        printf '%s' "$conflicts"
        exit 1
    fi

# Snapshot the live DB into the sibling tele-arena-db repo (as a SQL dump) and
# commit it. Run before a risky hand-edit instead of making a .db.bak copy.
# Usage: just db-snapshot "why I'm about to change the DB"
db-snapshot why:
    sqlite3 tele-arena.db .dump > ../tele-arena-db/tele-arena.sql
    git -C ../tele-arena-db add tele-arena.sql
    git -C ../tele-arena-db diff --cached --quiet && echo "db-snapshot: no changes since last snapshot" || git -C ../tele-arena-db commit -m "{{why}}"
