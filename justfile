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

