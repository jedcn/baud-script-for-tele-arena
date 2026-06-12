BAUD_HOME := "~/src/baud"

install:
    luarocks install busted

test:
    busted test/

run:
    bun run {{BAUD_HOME}}/src/main.tsx --profile sat5 --script ./main.lua

