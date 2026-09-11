(adr-rename-agent-sandbox)=

# 22. Rename the project from claude-sandbox to agent-sandbox

Date: 2026-09-11

## Status

Accepted

## Context

The project started as a bwrap jail for one agent, Claude Code, and was
named for it. {ref}`ADR 18 <adr-multi-agent-shadow>` made the shadow
dispatch on `argv[0]` and added OpenAI's Codex CLI; {ref}`ADR 19
<adr-pi-local-model>` added Pi, which talks to Anthropic, OpenAI or a local
model. The sandbox, the egress jail, the integrity guard and the helper CLI
are all agent-agnostic. The name was the last thing that said otherwise, and
it misled in two directions: users of Codex or Pi assumed the tool was not
for them, and readers assumed the Claude-specific parts (managed settings
under `/etc/claude-code`, `~/.claude` persistence) were the whole design.

Claude Code remains the primary agent for Diamond and the one the tutorials
and how-to guides walk through. The rename is about what the sandbox *is*,
not about demoting the agent most people run in it.

## Decision

Rename the project, and every artefact named after it, to `agent-sandbox`:

| was | is |
|---|---|
| repo `DiamondLightSource/claude-sandbox` | `DiamondLightSource/agent-sandbox` |
| `.devcontainer/claude-sandbox/` | `.devcontainer/agent-sandbox/` |
| `claude-shadow` (source file) | `agent-shadow` |
| helper CLI `claude-sandbox` | `agent-sandbox` |
| `/etc/claude-sandbox.conf` | `/etc/agent-sandbox.conf` |
| `/usr/libexec/claude-sandbox/` | `/usr/libexec/agent-sandbox/` |
| `CLAUDE_SANDBOX_*` env vars | `AGENT_SANDBOX_*` |
| `DANGEROUSLY_ALLOW_CLAUDE_SANDBOX_UNWRAPPED` | `DANGEROUSLY_ALLOW_AGENT_SANDBOX_UNWRAPPED` |
| image `ghcr.io/diamondlightsource/claude-sandbox` | `ghcr.io/diamondlightsource/agent-sandbox` |
| launcher `container/claude-container` | `container/agent-container` |
| skills `claude-sandbox*` | `agent-sandbox*` |

What does **not** change: the installed shadow names (`claude`, `codex`,
`pi`) are the agents' own command names and must stay so
({ref}`Invariant 1 <adr-multi-agent-shadow>`); `/etc/claude-code/` and
`/etc/codex/` are the *agents'* managed-policy directories, not ours;
`~/.claude`, `~/.codex` and `~/.pi` are the agents' homes.

No compatibility aliases. A second name for the CLI, the conf or the env
vars would be one more path through security-critical code to audit, for a
project with one organisation's worth of installs that all re-run
`./install` on every rebuild. Instead `install.sh` gains
`migrate_legacy_names`: it moves the relocated agent binaries from the old
libexec dir to the new one (no re-download), removes the old CLI and conf,
and `wire_managed_settings` prunes hook entries that point into the old
libexec dir before its basename-keyed dedup runs (otherwise an upgraded
container would keep a guard entry pointing at a script that no longer
exists).

## Consequences

- This is a breaking change and ships as a major release. Anything that set
  `CLAUDE_SANDBOX_*` (CI, shell rc, a team's `postCreate`) must switch to
  `AGENT_SANDBOX_*`; a local edit to `/etc/claude-sandbox.conf` is dropped on
  upgrade (as every re-install already did) and must be redone in
  `/etc/agent-sandbox.conf`.
- Hosts that copied `claude-container` need to fetch `agent-container`; the
  image label the launcher compares against is renamed too, so an old
  launcher reports the new image as unlabelled rather than silently
  matching. The launcher version is bumped to 0.5.0.
- The GitHub repository rename is a separate, manual act. GitHub redirects
  the old repo URL, but the Pages site does not redirect, so docs links to
  `agent-sandbox` are dead until the rename is done and the old ones go
  stale once it is.
- Prose that names Claude Code where the mechanism is agent-agnostic has
  been made generic; the tutorials and how-tos deliberately keep Claude Code
  as their worked example.
