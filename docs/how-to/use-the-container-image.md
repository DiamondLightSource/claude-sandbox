# Use the prebuilt container image

The PyPI launcher runs Claude Code, Codex or Pi in
`ghcr.io/diamondlightsource/claude-sandbox`. Use this route when you want
an agent in your project without configuring a devcontainer.

## Install and run

On a Linux host with [uv](https://docs.astral.sh/uv/getting-started/installation/),
rootless Podman, `/dev/net/tun`, and unprivileged user namespaces:

```bash
uv tool install claude-sandbox
cd ~/src/my-project
claude-sandbox
```

The first run pulls the matching image and creates a named container for the
project. Later runs reuse it. Each invocation starts a fresh agent session;
the container stops when its last session exits.
[Getting started](../tutorials/getting-started.md) covers login and verification.

Choose an agent or open a container shell:

```bash
claude-sandbox codex
claude-sandbox pi
claude-sandbox shell        # Skip if already in your devcontainer terminal
```

`shell` is an **unsandboxed shell inside the container**, for administration
such as forge login and installing system packages. It runs the shell
you launched from (zsh in a zsh terminal, even where the login `$SHELL` is
bash; override with `CLAUDE_SANDBOX_SHELL=zsh`; bash if the image lacks it) and sources your `~/.config/terminal-config` rc file, as a
devcontainer terminal does. X11 applications reach your display when
`DISPLAY` was set at creation.
From there, `claude`, `codex` and `pi` still start sandboxed agents.

This is equivalent to your normal terminal in a devcontainer with the sandbox
installed. There, skip `claude-sandbox shell` and the matching `exit` in these
guides; the commands inside are the same.

The helper commands of the in-container `claude-sandbox` CLI (`gh-auth`,
`glab-auth`, `verify`, `pi-local`, `version`, `update`) can be given to the
host launcher directly: `claude-sandbox verify` on the host runs them inside
the project's container, so a shell is only needed for other administration.

## Versions and updates

The installed package version selects the image tag. To update:

```bash
uv tool upgrade claude-sandbox
claude-sandbox --recreate
```

Run recreation in each project you want to update, after exiting active
sessions. It removes container-local packages, caches and forge logins.
Project files and shared agent settings survive.

Reconnecting to an existing project container keeps the image it was
created from, whatever has been pulled since. When testing a new image, or
to reclaim space from projects you no longer use, remove the containers the
launcher created on this host in one go:

```bash
claude-sandbox clean                    # stopped project containers; running ones are listed and kept
claude-sandbox clean --force            # running ones too, ending their sessions
claude-sandbox clean --force --images   # also drop claude-sandbox image tags no container uses
```

The next launch in any project then creates a fresh container from the
current image, with a fresh venv; venvs left on the cache volume by removed
containers are pruned by the same command. As with recreation, forge logins inside those containers are
lost; project files and shared agent settings on the host survive.

For a fixed release, use `uv tool install claude-sandbox==4.0.0`.
For an occasional run without a persistent tool install, use
`uvx claude-sandbox`. See [Upgrade](upgrade.md) for the other install routes.

## Authentication and persistence

Agent logins, memory and settings persist in the host's
`~/.config/terminal-config`, mounted at `/user-terminal-config`.
Override the host directory with `CLAUDE_SANDBOX_SHARED_CONFIG` when creating
a container. Each agent sees its own credential store.

Forge logins are separate and stay in the project container:

The container has a writable Git config with HTTPS rewrites for GitHub and
Diamond GitLab, so ordinary shell commands such as `git pull` use the same
forge logins. Only your name and email are imported from the read-only host
Git config; host credential helpers and SSH settings are not copied.

```bash
claude-sandbox gh-auth      # Same command on the host or in a devcontainer terminal
# Or: claude-sandbox glab-auth
```

Use [project-scoped tokens](authenticate-with-forges.md), and authenticate again
after recreation.

## Configure the sandbox

Create `~/.config/claude-sandbox.conf` on the host for durable settings
(or set `CLAUDE_SANDBOX_CONF` to another file). The launcher mounts this file
read-only at `/etc/claude-sandbox.conf`. It replaces the image's config,
so retain defaults you need, such as `allow-write = /cache` for Python tooling.

For example:

```ini
allow-write = /cache
allow-ip = 172.23.142.119   # Diamond GitLab
allow-ip = 172.23.1.3      # a device this agent needs
local-model-port = 1920
# Optional browser login relay; disabled in the shipped config:
# callback-port = 53692
```

If you add the file after a project container already exists, recreate that
container to establish the mount. Subsequent in-place edits are read at the
next agent launch; recreate if your editor replaces the mounted file.

See [Configuration](../reference/configuration.md) for all keys and
[Configure the network egress jail](network-egress-jail.md) for network access.

The project directory is the only writable path. Its parent is mounted
read-only, so sibling checkouts are readable as in a devcontainer (skipped
when the parent is your home directory). Automounted trees such as `/dls_sw`
work: the binds use slave propagation, so mounts the host automounter makes
appear inside without the container triggering them. To add more:

```bash
claude-sandbox --mount ~/src/shared-lib       # read-only
claude-sandbox --mount-rw ~/src/other-repo    # writable in the container and the sandbox
```

Use `--mount-rw` for a sibling checkout the agent must edit. The
`workspace-root` config key only widens the sandbox bind within what the
container mounted, so on its own it cannot make a read-only sibling writable.

Mounts, network mode and forwarded `CLAUDE_SANDBOX_*` variables are fixed
when a container is created. For an existing container, include
`--recreate` when changing them. For example:

```bash
CLAUDE_SANDBOX_NO_FORGE=1 claude-sandbox --recreate
```

## Toolchains

The image includes Python with an active environment at `/cache/venv`,
uv, Node.js and npm. `/cache` is a named volume, `claude-sandbox-cache`,
shared by every project container and laid out as the DLS python-copier
devcontainer lays out its own: the uv download cache, the pre-commit home
and one venv per project at `/cache/venv-for<project path>`, all on one
filesystem so uv hardlinks packages into the venv instead of copying them.
A new container gets a fresh venv, as a devcontainer rebuild does; the
downloads it installs from survive `--recreate` and `clean`. `claude-sandbox clean` also removes the venvs of projects whose container
is gone. Set `CLAUDE_SANDBOX_CACHE` to another volume name, or empty for
none. The mounted project's `.venv` is not
used by the image's default uv configuration.

npm lifecycle scripts are disabled by default, but project configuration can
override that setting. Extensions needing native libraries may need an
explicit setup step in a container shell.

For site-specific compilers, modules or a different build environment, use
[your own devcontainer](sandbox-a-team-devcontainer.md).

## Networking and platform limits

Host networking is the default so configured loopback relays can reach local
services. The agent still has its own network jail. `--bridge` selects bridge
networking at container creation, but the container's loopback then no longer
reaches host services.

Callback ports can be occupied by another session; the launcher warns when a
relay cannot start. See [browser logins](network-egress-jail.md#let-a-browser-login-reach-the-agent).

Rootless Podman on Linux is supported. Rootless Docker
(`CLAUDE_SANDBOX_ENGINE=docker`) and macOS with a Linux VM are untested;
rootful Docker cannot host the default jail.

## Without uv

The [clone fallback](install-without-uv.md#host-launcher) runs the same Bash
launcher without the PyPI entry point. It requires manual version management.
