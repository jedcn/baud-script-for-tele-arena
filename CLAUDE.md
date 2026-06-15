# Baud Script for Tele-Arena

## Committing

- Commit after every logical change — don't batch unrelated work into one commit.
- Commit immediately after a change is working; don't wait for manual in-game testing.
- If something turns out to be wrong, commit the broken state anyway and fix it in a follow-up commit. A record of what went wrong is more valuable than a clean history.
- Independent changes get independent commits. When changes span the same files, use `git apply --cached` with targeted patch files rather than staging everything at once.
- Write commit messages that explain the *why*, not just the *what*. One-line summary + blank line + body when the change needs context.
