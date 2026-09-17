# How-to Guides

Focused recipes for specific tasks you already know you need to do.

Start with the [PyPI quick start](tutorials/getting-started.md).
For day-to-day use, see [container options](how-to/use-the-container-image.md),
[forge authentication](how-to/authenticate-with-forges.md),
[upgrades](how-to/upgrade.md), or [Pi with a local model](how-to/pi-with-a-local-model.md).
The devcontainer and organisation guides cover custom toolchains and rollout.

For agent-driven UI testing, see [browser automation](how-to/browser-automation.md)
and [VS Code automation](how-to/vscode-automation.md). Both use optional tools
you install in the outer container and shipped skills the agent runs inside
its sandbox.

## Installation and upgrades

```{toctree}
:maxdepth: 1

how-to/use-the-container-image
how-to/install-without-uv
how-to/sandbox-a-team-devcontainer
how-to/enforce-org-wide
how-to/upgrade
```

## Access and isolation

```{toctree}
:maxdepth: 1

how-to/authenticate-with-forges
how-to/configure-workspace-scope
how-to/pass-environment-variables
how-to/network-egress-jail
how-to/verify-the-sandbox
```

## Agents and skills

```{toctree}
:maxdepth: 1

how-to/use-pi
how-to/pi-with-a-local-model
how-to/share-skills-between-agents
```

## Testing and development

```{toctree}
:maxdepth: 1

how-to/browser-automation
how-to/vscode-automation
how-to/contribute
```
