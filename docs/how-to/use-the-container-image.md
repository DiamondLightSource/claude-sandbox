# Use the prebuilt container image (no devcontainer)

Run fully sandboxed Claude Code on any Linux host with rootless podman
(or docker) — no devcontainer, no VS Code, no root access on the host.
The published image ships the whole sandbox pre-installed: the `claude`
shadow, the relocated real binary, the [integrity
guard](../explanations/integrity-guard), and the [network egress
jail](network-egress-jail).

Image: `ghcr.io/diamondlightsource/claude-sandbox:latest` (amd64 + arm64), built
by CI from the same `install.sh` the devcontainer runs — plus a weekly
rebuild so the baked-in Claude tracks upstream releases. The in-image
auto-updater is deliberately disabled (that is part of the integrity
guard), so updating means pulling a newer image, not letting a running
container update itself.

## Prerequisites

- **rootless podman** (or docker). On shared or centrally managed
  machines this may need IT to provision subuid/subgid ranges once per
  user — the same requirement as any rootless container use.
- **`/dev/net/tun`** on the host (present on stock Linux). The egress
  jail is fail-closed without it.
- **Unprivileged user namespaces** enabled — the default on RHEL 8/9 and
  most distros. Ubuntu 24.04 hosts restrict them via AppArmor; the
  container entrypoint probes and refuses with instructions rather than
  running unsandboxed.

## Quick start

Fetch the launcher and put it on your `PATH`:

```bash
curl -fsSLO https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/main/container/claude-container
chmod +x claude-container
```

The launcher runs **unsandboxed on your host**, so give it the scrutiny
that deserves: it is ~200 lines of plain bash — read it before you run
it. For fixed provenance, replace `main` in the URL with a release tag
or commit SHA (any ref that contains `container/claude-container`) and
re-fetch the same pinned ref when you update:

```bash
curl -fsSLO https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/<tag-or-commit>/container/claude-container
```

You don't have to watch this repo for launcher fixes: each published
image carries a label naming the launcher version it was built and
tested with, and on every run the launcher compares itself against your
locally pulled image (`claude-container --version` prints your copy's
version). When your copy is older it prints a `curl` command pinned to
the exact revision the image was built from; it never updates itself —
the launcher runs unsandboxed, so replacing it stays a deliberate,
reviewable act.

Then, from any project directory:

```bash
cd ~/src/my-project
claude-container
```

The first run pulls the image, creates a container named after the
project directory, and starts sandboxed `claude` with the project
mounted read-write. Later runs reuse the same container. Everything
you know from the devcontainer applies inside: `claude-sandbox verify`
runs the live battery, the egress jail is on by default, and plain
`claude` can only ever resolve to the shadow.

## One named container per project

The launcher deliberately creates a **persistent named container per
project directory** rather than a throwaway `--rm` container:

- gh/glab logins made inside it (see below) live for the container's
  lifetime — the same container-scoped credential model as a
  devcontainer, without re-pasting a PAT on every launch. Credentials
  are never mounted from the host.
- `claude-container --recreate` removes and recreates it (do this after
  pulling a newer image, or to change create-time settings). Forge
  logins must then be re-done — that ceremony is the deliberate cost of
  keeping PAT blast radius small.
- The container's own process is an idle keeper; every `claude-container`
  run is a new session exec'd into it, so `--agent`, `--shell` and any
  agent arguments apply on every run. A second run in the same project
  while a session is active opens another session in the same container.
  The container stops when its last session exits.
- Only `--host-net` and `--mount` are fixed at create time. On every reuse
  the launcher prints which container it is reconnecting to and, if you
  passed either of those, that they are being ignored until `--recreate`.
- A container made by a launcher older than 0.4 has an agent baked in as
  its process; the launcher refuses to reuse it and asks for `--recreate`.

## Authenticate to forges

Forge logins run outside the sandbox but inside the container, where the
`claude-sandbox` CLI is on PATH. `--shell` opens a plain, unsandboxed bash
there; authenticate, then start the agent from that shell or from a fresh
`claude-container` run:

```bash
claude-container --shell
claude-sandbox gh-auth
claude-sandbox glab-auth gitlab.example.com
exit
claude-container
```

See [Authenticate with forges](authenticate-with-forges) for the
recommended PAT scopes.

Note: inside the published image, update by pulling a newer image and
recreating the container (`claude-container --recreate`), not with
`claude-sandbox update` — the CLI refuses there.

## Persist login and memory

The launcher mounts `~/.config/terminal-config` (override:
`CLAUDE_SANDBOX_SHARED_CONFIG`) at `/user-terminal-config`, and the
entrypoint symlinks `~/.claude` and `~/.claude.json` into it — the same
convention devcontainers use, so a host that runs both shares one Claude
login, memory, and settings. You log in to Claude once, not once per
container.

## Configure the sandbox

Per-session (create-time) settings are environment variables, passed
through automatically when the container is created:

```bash
CLAUDE_SANDBOX_NO_FORGE=1 claude-container          # no forge creds inside
```

They are frozen into the container at create time — `--recreate` to
change them.

Durable settings go in `~/.config/claude-sandbox.conf` (override:
`CLAUDE_SANDBOX_CONF`), written in the normal
[claude-sandbox.conf format](../reference/configuration). When the file
exists the launcher mounts it **read-only** over
`/etc/claude-sandbox.conf` — the canonical path the shadow reads. The
usual rule that the conf must live outside the sandbox's writable set
still holds: inside the container it is at `/etc` and read-only, so a
compromised session cannot widen its own binds for the next launch.

```ini
# ~/.config/claude-sandbox.conf
allow-ip = 172.23.1.3        # keep this IOC reachable past the blackhole
```

To make extra folders writable, `--mount` binds them into the container
*and* adds a matching `allow-write` entry for the sandbox:

```bash
claude-container --mount ~/src/shared-lib
```

## Run Codex instead of Claude

The image ships both agents behind the same shadow, so either is sandboxed
identically. Pick one with `--agent`:

```bash
claude-container --agent codex
```

Codex signs in separately from Claude (its credentials live in `~/.codex`,
persisted through the same `/user-terminal-config` share), and a Codex session
sees no Claude credentials — nor the reverse. Everything else is the same
container: the same project bind, the same forge auth, the same egress jail.

## EPICS / lab-device hosts

`--host-net` creates the container with `--network=host` (Channel Access
broadcast for non-Claude shells). Claude itself stays inside the egress
jail either way — the jail is container-network-mode-agnostic — so
device access for Claude is still granted per-IP with `allow-ip`.

## Update

```bash
podman pull ghcr.io/diamondlightsource/claude-sandbox:latest
claude-container --recreate
```

If you launch with `CLAUDE_SANDBOX_ENGINE=docker`, pull with `docker`
instead — and set the variable on the `--recreate` run too (the launcher
reads it on every invocation; it is not remembered).

## Limitations

- **Your toolchain isn't in the image.** The base is the DLS
  ubuntu-devcontainer (git, build-essential, uv, gh/glab, just…), not
  your site's module system or cross-compilers. Claude can read, edit,
  build what the image supports, and commit; site-specific builds may
  still happen outside the container.
- **Claude's version is the image's.** By design (disabled updater);
  pull + `--recreate` to update.
- **Rootless podman is the supported engine.** `CLAUDE_SANDBOX_ENGINE=docker`
  exists, but under *rootful* docker the egress jail's pasta attach is
  denied (`Couldn't open user namespace ... Permission denied` — differing
  namespace/ptrace semantics), so `claude` fail-closes at launch. Rootless
  docker is untested. Prefer rootless podman.
- **Linux only** — the sandbox is built on Linux namespaces. macOS with
  `podman machine` runs the Linux image in a VM and should work, but is
  untested.
