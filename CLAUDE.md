# Baud Script for Tele-Arena

## Client

This script runs inside [baud](https://github.com/jedcn/baud), a custom MUD client. Do not assume Mudlet or any other client. The `createTrigger`, `createAlias`, `createTimer`, `send`, `echo` etc. APIs are baud's Lua scripting interface. To reload the script after changes, refer to baud's loading docs at https://github.com/jedcn/baud?tab=readme-ov-file#loading-scripts.

## Testing

- Run `just test` after every change to verify nothing is broken.

## Committing

- Commit after every logical change — don't batch unrelated work into one commit.
- Commit immediately after a change is working; don't wait for manual in-game testing.
- If something turns out to be wrong, commit the broken state anyway and fix it in a follow-up commit. A record of what went wrong is more valuable than a clean history.
- Independent changes get independent commits. When changes span the same files, use `git apply --cached` with targeted patch files rather than staging everything at once.
- Write commit messages that explain the *why*, not just the *what*. One-line summary + blank line + body when the change needs context.
