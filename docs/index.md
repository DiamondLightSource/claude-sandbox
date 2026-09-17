---
html_theme.sidebar_secondary.remove: true
---

# claude-sandbox

Run Claude Code, Codex or Pi in a container with isolated credentials,
limited writable paths and a network jail.

On a Linux host with [uv](https://docs.astral.sh/uv/getting-started/installation/)
and rootless Podman:

```bash
uv tool install claude-sandbox
cd ~/src/my-project
claude-sandbox
```

The launcher creates the container and starts sandboxed Claude. No clone or
devcontainer setup is needed. [Getting started](tutorials/getting-started.md)
covers prerequisites, login and verification. Already have a project
devcontainer? [Install into it](how-to/sandbox-a-team-devcontainer.md).

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
:maxdepth: 3

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

## Using Claude Code at Diamond Light Source

DLS developers: start at [Claude Code at DLS](dls/claude-at-dls.md) — the
one-page policy summary and getting-started instructions.

```{toctree}
:maxdepth: 1
:hidden:

dls
```
