# Use claude-sandbox inside your existing devcontainer

Use this route if you already work inside your project's devcontainer and
want the agent to use its toolchain. Otherwise, use the
[PyPI quick start](getting-started.md).

## Check the container

The devcontainer must be Debian or Ubuntu based, run as root under rootless
Podman, have uv available
and have the `/dev/net/tun` device, which the network jail requires. If
`.devcontainer/devcontainer.json` does not already pass the device, merge
this into it and rebuild once:

```json
"runArgs": ["--device=/dev/net/tun"]
```

Preserve existing run arguments. The installer warns if the device is
missing. Without uv, use the
[clone fallback](../how-to/install-without-uv.md).

## Install and run

In a devcontainer terminal:

```bash
uvx claude-sandbox install
claude
```

`codex` and `pi` are installed too; add `--minimal` after `install` if you
use only Claude
([Claude-only installation](../reference/whats-installed.md#claude-only-installation)).
Apart from the device, the installation changes nothing in the project. It lasts until the container
is rebuilt; run the install command again after a rebuild.

To push to GitHub or GitLab, see
[Authenticate with forges](../how-to/authenticate-with-forges.md).
To keep your agent login across rebuilds, add the
[terminal-config mount](set-up-a-devcontainer.md#persist-agent-logins);
DLS `python-copier-template` devcontainers already mount it.
For DLS terminal settings (devcontainer CLI, Podman, UID remapping), see
[Terminal access](set-up-a-devcontainer.md#terminal-access).

:::{note} DLS: install across your devcontainers
`python-copier-template` devcontainers source `/user-terminal-config/bashrc`.
Add `uvx claude-sandbox install` to its run-once section to install on the
first shell in each container. Each container still needs `/dev/net/tun`.
:::

## Verify and update

```bash
claude-sandbox version
claude-sandbox verify
uvx claude-sandbox@latest install   # upgrade
```

See [Upgrade](../how-to/upgrade.md) for the distinction between sandbox and agent updates.

To install a pinned release for everyone on a project, see
[Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md).
