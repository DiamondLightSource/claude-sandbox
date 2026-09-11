# Upgrade agent-sandbox

```bash
agent-sandbox update
```

This clones the latest **release** into a fresh temporary directory,
checks out its tag, runs the installer, and records the version — check
what you have with:

```bash
agent-sandbox version
```

The installer is idempotent; the shadow is re-established without
re-downloading Claude. No persistent clone is needed — the temporary one
is removed after the install.

(Inside the published container image, update by pulling a newer image
and recreating the container instead — see
[Use the container image](use-the-container-image.md).)

## Upgrading from claude-sandbox

The project was renamed from `claude-sandbox` to `agent-sandbox`
({ref}`ADR 22 <adr-rename-agent-sandbox>`). A container installed under the
old name still has the old CLI, so run `claude-sandbox update` once (GitHub
redirects the old repository URL); the installer then migrates the old paths
itself: the relocated agent binaries move to `/usr/libexec/agent-sandbox/`
without a re-download, the old `claude-sandbox` CLI and
`/etc/claude-sandbox.conf` are removed, and the integrity-guard hooks are
re-pointed. Afterwards:

- use `agent-sandbox` where you used `claude-sandbox`;
- rename any `CLAUDE_SANDBOX_*` variables in shell rc files, CI or a team's
  `postCreate` to `AGENT_SANDBOX_*`;
- redo any local edits to the conf in `/etc/agent-sandbox.conf`;
- on hosts using the container image, fetch `agent-container` in place of
  `claude-container` and pull `ghcr.io/diamondlightsource/agent-sandbox`.

## Why upgrades are deliberate

Claude Code's in-container auto-updater is **disabled**
(`env.DISABLE_AUTOUPDATER=1` + `autoUpdates:false`). The updater otherwise
re-creates `~/.local/bin/claude` on a version bump, which — depending on
your `PATH` order — can launch the real binary *unwrapped*, with no bwrap
and no git steering. This is self-entrenching and silent.

With the updater off, updates happen only when *you* run
`agent-sandbox update` (or re-run the installer from a clone). Updating:

- re-relocates the current Claude binary to
  `/usr/libexec/agent-sandbox/claude` (off the user's PATH), and
- re-asserts the shadow at `/usr/local/bin/claude`.

For why this root-cause removal matters and how the global guard fails loud
if an unwrapped binary ever appears anyway, see the
[integrity guard explanation](../explanations/integrity-guard.md).
