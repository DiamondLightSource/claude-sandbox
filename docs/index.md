---
html_theme.sidebar_secondary.remove: true
---

# agent-sandbox

bwrap-isolated coding agents for Debian/Ubuntu devcontainers (rootless Podman
is the supported runtime; rootless Docker likely works but is untested with
the default egress jail). One sandbox wraps **Claude Code**, **OpenAI Codex
CLI** and **Pi** (Anthropic, OpenAI or local models). A hostile prompt, file,
or tool result cannot reach your host credentials, IDE bridges, or shell
environment. The protection is launch-time: plain `claude`, `codex` and `pi`
resolve to a shadow that wraps the real binary in `bwrap`, and a global
integrity guard fails loud and closed if an agent is ever launched unwrapped.
By default every agent also runs in a
per-process egress jail (ADR 0015) that blackholes RFC1918 internal networks, so
a compromised session can't pivot sideways to internal hosts or lab devices while
the internet, DNS, and configured `allow-ip` devices stay reachable.

## How the documentation is structured

::::{grid} 2
:gutter: 3

:::{grid-item-card} {material-regular}`directions_walk;2em` Tutorials
Guided lessons that take you from nothing to a working sandbox.

```{toctree}
:maxdepth: 2

tutorials
```
:::

:::{grid-item-card} {material-regular}`directions;2em` How-to Guides
Focused recipes for specific tasks you already have in mind.

```{toctree}
:maxdepth: 2

how-to
```
:::

:::{grid-item-card} {material-regular}`info;2em` Reference
Dry, factual lookup: config keys, paths, checks, and flags.

```{toctree}
:maxdepth: 2

reference
```
:::

:::{grid-item-card} {material-regular}`menu_book;2em` Explanations
The why behind the design: threat model, sandbox rationale, and the network
egress jail.

```{toctree}
:maxdepth: 2

explanations
```
:::

::::

Claude Code is the primary agent at Diamond and the one the tutorials and
how-to guides walk through; Codex and Pi share the same install and the same
jail (see [Use Pi](how-to/use-pi.md) and {ref}`ADR 18 <adr-multi-agent-shadow>`).

## Using Claude Code at Diamond Light Source

DLS developers: start at [Claude Code at DLS](dls/claude-at-dls.md) — the
one-page policy summary and getting-started instructions.

```{toctree}
:maxdepth: 1
:hidden:

dls
```
