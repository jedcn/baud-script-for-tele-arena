install:
    luarocks install busted

test:
    busted test/

test-verbose:
    busted test/ --verbose
