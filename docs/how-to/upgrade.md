# Upgrade claude-sandbox

## Installed from PyPI on your host

```bash
uv tool upgrade claude-sandbox
cd ~/src/my-project
claude-sandbox --recreate
```

The package selects the matching image version. Existing project containers
keep their old image until recreated, so repeat the second step in each
project you want to update.

Recreation removes the container's local packages, caches and forge logins.
Project files and agent settings in `~/.config/terminal-config` survive.
Exit active sessions before recreating, then
[authenticate to forges](authenticate-with-forges.md) again if needed.

Check the installed launcher with `claude-sandbox --version`.
For a fixed version, install with `uv tool install claude-sandbox==4.0.0`;
change that constraint explicitly to move to another release.

If you use the one-off launcher instead of a tool install:

```bash
uvx claude-sandbox@latest --recreate
```

See [uv's tool guide](https://docs.astral.sh/uv/guides/tools/#upgrading-tools)
for package upgrade behaviour.

## Installed into your own devcontainer

Inside the container, as root:

```bash
uvx claude-sandbox@latest install
claude-sandbox version
```

For a team, update the version in
[postCreate](sandbox-a-team-devcontainer.md) and rebuild.
Reapply custom `/etc/claude-sandbox.conf` settings after installation.

The installer keeps existing agent binaries. Updating the sandbox does not
itself guarantee a newer agent; a fresh devcontainer installs the current
agents. The published image supplies the agents baked into that image.

For a legacy clone installation, `claude-sandbox update` fetches and installs
the newest release. For a wheel installation it prints the PyPI update
instructions. In the published image it refuses: upgrade from the host.

## Migrating from the copied launcher

Replace `claude-container` with the PyPI tool install above. The old
`--agent NAME` and `--shell` flags are now verbs (`codex`, `pi`, `shell`);
host networking is the default, with `--bridge` as the alternative.

Agent auto-updaters are disabled to preserve the sandbox wrapper.
See [The integrity guard](../explanations/integrity-guard.md) for the rationale.
