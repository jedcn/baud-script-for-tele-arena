# Baud Script for Tele-Arena

## Client

This script runs inside [baud](https://github.com/jedcn/baud), a custom MUD client. If changes are made to .lua files in this directory the user must run `/lua reloadScript()` in their session to get those changes.

What is more: we have control over baud. This means that if we are bumping into a limitation with the script for tele-arena, we can modify the source of baud.

## Testing

- Run `just test` after every change to verify nothing is broken.

## Committing

- Don't create new branches. Commit directly to the current branch.
- Commit after every logical change — don't batch unrelated work into one commit.
- Commit immediately after a change is working; don't wait for manual in-game testing.
- If something turns out to be wrong, commit the broken state anyway and fix it in a follow-up commit. A record of what went wrong is more valuable than a clean history.
- Independent changes get independent commits. When changes span the same files, use `git apply --cached` with targeted patch files rather than staging everything at once.
- Write commit messages that explain the *why*, not just the *what*. One-line summary + blank line + body when the change needs context.
