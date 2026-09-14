---
name: gh-park
description: >-
  Keep several GitHub fine-grained PATs usable in one sandbox container by
  parking each pasted token under a name and wiring git checkouts to it.
  Use when work spans repositories in different GitHub organisations or
  accounts, when a second `claude-sandbox gh-auth` would replace the first
  token, when a push or `gh pr create` returns 403 or "Resource not
  accessible by personal access token", or when asked to park, save or switch
  a GitHub token.
---

# gh-park

`gh` keeps one token per account per host, and a fine-grained PAT covers one
resource owner. Pasting a second PAT with `claude-sandbox gh-auth` therefore
replaces the first. `scripts/gh-park` copies the active token to a named file
under `~/.config/gh/scoped/` and wires checkouts to it with a repo-local
`credential.helper`, so each repository pushes with the right token while the
default slot stays free for the next paste.

The files sit in the container-scoped gh directory. They have the same
lifetime and reach as the login itself, so this does not weaken the
container-scoped PAT rule. It is the manual form of the `gh-auth --scope`
proposal in issue 47.

## Workflow

1. The user pastes a PAT with `claude-sandbox gh-auth` outside the jail.
2. Park it and wire the checkouts it covers:

   ```sh
   scripts/gh-park save dls /home/giles/code/podbench
   ```

3. The user pastes the next PAT. Repeat with a new name. The last token
   pasted stays in the default slot and needs no parking unless another paste
   follows.
4. Check the result:

   ```sh
   scripts/gh-park status
   ```

   ```text
   TOKEN        EXPIRES                  ACTIVE   CHECKOUTS
   dls          2026-10-14 19:13:53      -        /home/giles/code/podbench
   gilesknap    2026-10-14 19:39:47      -        /cache/t11-services
   sandbox      2026-10-14 19:50:53      yes      /home/giles/code/claude-sandbox
   ```

## Rules for the agent

- Git operations in a wired checkout need nothing extra. The repo-local
  config first resets the helper list and then names the parked token, so the
  host-wide gh helper in `/etc/claude-gitconfig` is not asked. Without the
  reset git takes the default slot's answer first and the push fails with
  403 whenever the two tokens differ.
- `gh api`, `gh pr` and `gh issue` use the default slot only. For another
  repository run them as `scripts/gh-park with NAME gh pr create ...`.
- A new clone is not wired. Run `scripts/gh-park use NAME DIR` first, or the
  push uses the default slot and may return 403.
- Two tokens for the same organisation cannot both be default. Park one.
- Never print a token. `status` shows expiry and checkouts only.
- Tokens vanish with the container, as the login does. After `--recreate`
  the user pastes them again.

## Diagnosing a 403

`git push` 403 means the token git picked lacks Contents write on that
repository. `gh pr create` failing with "Resource not accessible by personal
access token" means the default slot's token lacks Pull requests write there,
or the repository belongs to another owner. Run `status`, confirm which token
each checkout uses, and check the token's repository list on GitHub. The
`permissions` field from `gh api repos/OWNER/REPO` describes the account, not
the token, and is not evidence.
