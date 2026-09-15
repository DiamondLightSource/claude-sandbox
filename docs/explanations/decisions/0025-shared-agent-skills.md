(adr-shared-agent-skills)=

# 25. Share `~/.agents/skills` read-write with every agent

Date: 2026-09-15

## Status

Accepted

Amends {ref}`ADR 18 <adr-multi-agent-shadow>`'s rule that each agent sees only
its own home paths, for this one directory. Leaves
{ref}`ADR 24 <adr-shipped-skills>` (shipped skills) unchanged.

## Context

Issue #52. Codex and Pi discover user skills in `~/.agents/skills`. Inside the
sandbox `$HOME` is a private tmpfs and only each agent's own config directory
is bound back, so skills installed there in the outer container were
invisible, and a skill saved there during a session was a private copy that
vanished on exit.

Users also want one set of skills to serve all three agents, while keeping
the option of skills that only one agent sees.

Options considered:

- Bind the whole `~/.agents`. Its contents are defined by whichever tools
  adopt the convention (Codex already reads `~/.agents/plugins`), so the
  sandbox would expose whatever lands there next without review, and the
  integrity battery could no longer say what the directory should hold.
- Bind `~/.agents/skills` read-only. Blocks a session from saving a skill the
  user asked for, and pushes that edit outside the sandbox. The agents'
  own config directories, which also hold skills, are already read-write.
- Bind it for Codex only. Serves the issue as written but not a skill set
  shared across agents through symlinks, because a link into
  `~/.agents/skills` would dangle in Claude and Pi sessions.

## Decision

Bind `~/.agents/skills`, and nothing else under `~/.agents`, read-write into
every agent's session. The shadow creates it at launch when missing, and
`install.sh` adds it to the `/user-terminal-config` share when that is
mounted and writable.

- Each agent keeps its own skills directory (`~/.claude/skills`,
  `~/.codex/skills`, `~/.pi/agent/skills`), unshared.
- Codex and Pi load everything in `~/.agents/skills`. Claude loads a shared
  skill only when the user symlinks it into `~/.claude/skills`. `$HOME` is the
  same path inside and outside the sandbox, so those links resolve in-session.
- Links in the other direction (from `~/.agents/skills` into one agent's
  config) dangle in the other agents' sessions. That is intended: credential
  separation is unchanged.
- Shipped skills stay read-only binds into each agent's own directory, never
  into `~/.agents/skills`, which is user-owned and writable.
- Battery check 03 allows `.agents` under `$HOME` for every agent, provided
  it contains only `skills`.

## Consequences

- `~/.agents/skills` is a write channel between agents. A compromised session
  of one agent can plant a skill that another agent later loads, with that
  agent's access, in any project and container sharing the terminal config.
  No credentials cross, the shared workspace already lets agents write each
  other's project instructions, and each agent could already persist
  instructions through its own config; the new part is the cross-agent,
  cross-project reach. Pi, which may run a small local model, can now
  influence Claude and Codex this way.
- A skill with the same name in `~/.agents/skills` and in an agent's own
  directory is seen twice by that agent; the sandbox does not arbitrate.
- Without `/user-terminal-config`, the directory lives and dies with the
  container, like `~/.codex`.
- Sharing another `~/.agents` subdirectory is a deliberate, separate change.
