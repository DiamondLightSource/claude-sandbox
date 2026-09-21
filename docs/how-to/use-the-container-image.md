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
`glab-auth`, `verify`, `pi-local`, `version`, `update`, `doctor`) can be given to the
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

## Tell containers apart

Each project directory gets its own container, so a shell opened from a
different directory runs in a different container. A `gh-auth` login made
there does not reach the agent session you meant.

Each container has a short tag: the project directory name and four hex
digits, such as `myproj-3f2a`. The tag is in `/etc/claude-sandbox-tag`.
Show it with the host name, as `ws1:myproj-3f2a`, in the Claude status line
and the Pi footer. The zsh and bash prompts show the tag alone, in white,
because most prompts already show the host name:

```bash
claude-sandbox doctor        # Report what is not set up; changes nothing
claude-sandbox doctor --fix  # Apply the recommended setup
```

`--fix` installs the recommended Claude status line and a Pi footer extension,
and adds a marked block to `zshrc` and `bashrc` in the shared terminal config.
It saves a timestamped `.bak-` copy of every file before a change. The prompt
block does nothing outside a tagged container, so shells on the host and in
devcontainers that share the files are unchanged. A later `--fix` replaces an
older block. To remove the prompt tag, delete the block between the
`claude-sandbox prompt tag` markers.

Codex has no custom status line text, so it does not show the tag.
Containers created before the tag existed have none: recreate them.

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

The launcher mounts the project directory read-write. Each agent can write
only to the directory it was started in. Automounted trees such as `/dls_sw`
work: the binds use slave propagation, so mounts the host automounter makes
appear inside without the container triggering them.

To also mount the project's parent read-write, as a devcontainer mounts
`/workspaces`, use `--peers` when you create the container. From
`claude-sandbox shell` you can then `cd` into a sibling checkout and start
an agent session there. The launcher skips the parent when it contains your
home directory.

```bash
claude-sandbox --peers
# For an existing project container:
claude-sandbox --recreate --peers
```

Peers are off by default because sibling projects are then **readable by
agents**, including any credentials they contain. Read-only access prevents
changes, not disclosure. Version 4.4.0 mounted the parent by default. A
container created by that version keeps the parent mount, and the launcher
warns until you run `claude-sandbox --recreate`. `--no-peers` still works
and selects the default.

This affects containers created by the host launcher. It does not change
workspace mounts supplied by an existing devcontainer. Explicit `--mount`
and `--mount-rw` paths apply with or without `--peers`. To add specific paths:

```bash
claude-sandbox --mount ~/src/shared-lib       # read-only
claude-sandbox --mount-rw ~/src/other-repo    # writable in the container and the sandbox
```

Use `--mount-rw` for a path outside the parent that an agent must edit. The
`workspace-root` config key only widens the sandbox bind within what the
container mounted, so on its own it cannot make a read-only mount writable.

### GPUs and other devices

Expose all NVIDIA GPUs to both the container shell and sandboxed agents:

```bash
claude-sandbox --gpu
claude-sandbox --recreate --gpu   # if the project container already exists
claude-sandbox --gpu shell       # then run nvidia-smi to check the container
```

The host needs its NVIDIA driver and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
Docker uses `--gpus all`; Podman uses `--device nvidia.com/gpu=all` and needs
the toolkit's [CDI configuration](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html).
The runtime supplies driver libraries; install your workload's CUDA or other
user-space dependencies in the container as needed.

If Podman reports `unresolvable CDI devices nvidia.com/gpu=all`, it cannot
find the NVIDIA CDI specification. When the host driver works (`nvidia-smi`)
and `nvidia-ctk` is installed, the repository provides a helper that generates
a specification in your user configuration directory without sudo. This
requires Podman with `--cdi-spec-dir` support (check `podman --help`). Older
versions, including upstream 4.9, ignore the custom CDI directory setting
when loading devices; merely writing a user configuration file is not enough.
The helper checks for this capability before changing any files. On the
**host**, download it, inspect it, then run it:

```bash
curl -fL -o setup-nvidia-cdi.sh \
  https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/main/container/setup-nvidia-cdi.sh
less setup-nvidia-cdi.sh
bash setup-nvidia-cdi.sh
claude-sandbox --gpu shell
```

From a checkout, run `bash container/setup-nvidia-cdi.sh` instead. For an
unmerged change, replace `main` in the download URL with its commit SHA.

The helper writes `~/.config/cdi/nvidia.yaml` and a dedicated
`~/.config/containers/containers.conf.d/90-claude-sandbox-nvidia-cdi.conf`
file; it uses `$XDG_CONFIG_HOME` instead of `~/.config` when set. It retains
the standard CDI search directories and adds the user directory, leaving
your main `containers.conf` untouched. Any custom `cdi_spec_dirs` setting
should be reconciled with this drop-in. It installs no packages and grants
no new device permissions. Missing host tools or GPU permissions need your
host administrator. Toolkit 1.13.5 is supported; `nvidia-ctk cdi list` is
not required. Re-run after driver updates or GPU configuration changes.

If Podman lacks custom CDI directory support, an administrator can generate
the specification in a system directory that the older engine searches:

```bash
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Run these on the host, then retry `claude-sandbox --gpu shell` as your normal
user. The administrator must regenerate that file after driver or GPU
configuration changes. Alternatively, use a Podman build with the custom
directory support added by [upstream PR 25717](https://github.com/containers/podman/pull/25717).
Recreating the container does not fix an undiscoverable CDI specification.

If generation fails, the previous specification and Podman configuration
are preserved. After setup, run `nvidia-smi` inside the container shell and
ask an agent to run it too, to check both layers of device access.

For other hardware, repeat `--device` with individual device nodes:

```bash
claude-sandbox --device /dev/ttyUSB0
claude-sandbox --device /dev/dri/renderD128                 # Intel/AMD rendering
claude-sandbox --device /dev/kfd --device /dev/dri/renderD128 # AMD compute
```

Paths must name existing character or block devices under `/dev`. Symlinks
are resolved and the canonical path is used inside the container and sandbox.
Directories and Docker-style `host:container:permissions` mappings are not
accepted. The host user must have access to the devices. With Podman,
`--device` adds `--group-add keep-groups`, so a node that only a group can
open, such as `dialout` or `render`, works for a member of that group. This
needs the crun runtime. Docker does not get this flag. `--device` is create-time, so an existing container
needs `--recreate`. Devices are exposed read-write to agents, including
their ioctl interface and, for disks, raw contents. Choose only the devices
the workload needs.

Device access widens the sandbox's trust boundary: every process in the agent
session can use the device, including downloaded tools and project scripts.
A vulnerability in the host GPU/device driver could allow a sandbox escape;
GPU workloads can also exhaust shared GPU memory or compute. Raw disk access
can bypass filesystem protections. These options are off by default and do
not enable privileged-container mode, but the remaining sandbox protections
cannot contain a compromised host driver.

The sandbox keeps its private `/dev` and adds the selected nodes. `--gpu`
adds NVIDIA and DRM device nodes available inside the container. For an
existing devcontainer, configure device access in its container runtime and
add `gpu` or repeatable `allow-device = /dev/…` entries to
`/etc/claude-sandbox.conf` to expose those devices to agents too.

Mounts, devices, GPU access, network mode and forwarded `CLAUDE_SANDBOX_*` variables are fixed
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
