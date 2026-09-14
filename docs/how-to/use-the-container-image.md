# Use the prebuilt container image (no devcontainer)

Run fully sandboxed Claude Code, Codex or Pi on any Linux host with rootless
podman (or docker) — no devcontainer, no VS Code, no root access on the host.
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
- **`uv`** for the `uvx` front door, or fetch the launcher script by hand
  (below).
- **Unprivileged user namespaces** enabled — the default on RHEL 8/9 and
  most distros. Ubuntu 24.04 hosts restrict them via AppArmor; the
  container entrypoint probes and refuses with instructions rather than
  running unsandboxed.

## Quick start

From any project directory:

```bash
cd ~/src/my-project
uvx claude-sandbox
```

The first run pulls the image, creates a container named after the
project directory, and starts sandboxed `claude` with the project
mounted read-write. Later runs reuse the same container. Everything
you know from the devcontainer applies inside: `claude-sandbox verify`
runs the live battery, the egress jail is on by default, and plain
`claude` can only ever resolve to the shadow.

`uvx` fetches the `claude-sandbox` wheel from PyPI. The wheel is a front
door only: it bundles the launcher script from this repository,
`container/claude-container`, unchanged, and a ten-line Python entry point
that execs it. The launcher runs **unsandboxed on your host**, so give it
the scrutiny that deserves: it is ~300 lines of plain bash — read it before
you run it. `uvx claude-sandbox --help` prints its manual.

### Versions and updates

The wheel version, the launcher's own version and the image tag are one
number, and the wheel pins the image it launches:

```bash
uvx claude-sandbox            # the wheel uv has cached; image tag = its version
uvx claude-sandbox@latest     # the newest release on PyPI, and its image
uvx claude-sandbox==4.0.0     # exactly this release, launcher and image
```

`uvx` reuses its cached wheel, so a plain `uvx claude-sandbox` never moves
you to a new release on its own. Updating is the `@latest` form, followed
by `--recreate` to move an existing project container onto the new image;
the launcher says so when it notices the container predates the pulled
image. Nothing updates itself: the launcher runs unsandboxed, so replacing
it stays a deliberate act.

### Without uv

Fetch the same script and put it on your `PATH`:

```bash
curl -fsSLO https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/main/container/claude-container
chmod +x claude-container
```

Replace `main` with a release tag or commit SHA for fixed provenance, and
re-fetch the same pinned ref when you update. Run as a copied script the
launcher defaults to the `:latest` image, and each published image carries
a label naming the launcher version it was built with: when your copy is
older the launcher prints a `curl` command pinned to the exact revision
the image was built from.

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
- The container's own process is an idle keeper; every `uvx claude-sandbox`
  run is a new session exec'd into it, so the verb (`claude`, `codex`,
  `pi`, `shell`) and any agent arguments apply on every run. A second run
  in the same project while a session is active opens another session in
  the same container. The container stops when its last session exits.
- Only `--bridge` and `--mount` are fixed at create time. On every reuse
  the launcher prints which container it is reconnecting to and, if you
  passed either of those, that they are being ignored until `--recreate`.
- Pulling a newer image does not touch an existing container. The reuse
  notice says so when the container's image differs from the one now
  pulled, and `--recreate` is the way to move a project onto it.
- A container made by a launcher older than 0.4 has an agent baked in as
  its process; the launcher refuses to reuse it and asks for `--recreate`.

## Authenticate to forges

Forge logins run outside the sandbox but inside the container, where the
`claude-sandbox` CLI is on PATH. The `shell` verb opens a plain, unsandboxed
bash there; authenticate, then start the agent from that shell or from a
fresh `uvx claude-sandbox` run:

```bash
uvx claude-sandbox shell
claude-sandbox gh-auth
claude-sandbox glab-auth gitlab.example.com
exit
uvx claude-sandbox
```

See [Authenticate with forges](authenticate-with-forges) for the
recommended PAT scopes.

Note: inside the published image, update by pulling a newer image and
recreating the container (`uvx claude-sandbox --recreate`), not with
`claude-sandbox update` — the CLI refuses there.

## Persist login and memory

The launcher mounts `~/.config/terminal-config` (override:
`CLAUDE_SANDBOX_SHARED_CONFIG`) at `/user-terminal-config`, and the
entrypoint symlinks `~/.claude` and `~/.claude.json` into it — the same
convention devcontainers use, so a host that runs both shares one Claude
login, memory, and settings. You log in to Claude once, not once per
container.

## Python: a ready venv, kept apart from the host's

The image bakes a uv-managed Python (`PYTHON_VERSION` build arg, 3.13) into
the read-only root and ships an empty virtual environment at `/cache/venv`,
already active: `python` is on the PATH from the first prompt, and
`uv sync` / `uv add` / `uv run` install into it because the image sets
`UV_PROJECT_ENVIRONMENT` there. uv's package cache and `uvx` tool installs
live under `/cache` too.

Two consequences worth knowing:

- **Your workspace `.venv` is never touched.** The container's environment
  lives outside the mounted directory, so a venv the host created keeps its
  host interpreter, and the container never writes container-only paths
  into it. Each side runs its own uv against its own environment.
- **It persists per project, not per session.** `/cache` is in the named
  container's writable layer: installed packages survive session restarts,
  and `--recreate` wipes them. Home inside the jail is ephemeral by design,
  so anything a tool puts under `~/.cache` (Playwright browsers, for
  instance) is gone at the next launch unless you point it at `/cache` with
  a `pass-env` line in the conf.

The devcontainer route gets none of this: there the project's own
devcontainer supplies Python, and the sandbox installer stays bash-only.

The image also carries Node.js 22 LTS with npm and npx, copied from the
official Node image (`NODE_VERSION` build arg). Inside Pi that makes
`pi install npm:<package>` work; extensions land in the shared `~/.pi`, so
they persist across containers. The devcontainer installer only provides
Ubuntu's Node 18 without npm.
npm lifecycle scripts are off by default in the image (`ignore-scripts=true`
in npm's global config, read-only inside the session), so `pi install` and
`npx` run no postinstall hooks. It is a default, not an enforcement: a
project `.npmrc` or `~/.npmrc` can re-enable them. Pure-JavaScript packages,
which pi extensions are, need nothing else; a package that must build a
native module fails at install and needs a deliberate opt-in.

## Configure the sandbox

Per-session (create-time) settings are environment variables, passed
through automatically when the container is created:

```bash
CLAUDE_SANDBOX_NO_FORGE=1 uvx claude-sandbox        # no forge creds inside
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
uvx claude-sandbox --mount ~/src/shared-lib
```

## Run Codex or Pi instead of Claude

The image ships all three agents behind the same shadow, so each is
sandboxed identically. Pick one with a verb; the default is `claude`:

```bash
uvx claude-sandbox codex
uvx claude-sandbox pi
```

Codex signs in separately from Claude (its credentials live in `~/.codex`,
persisted through the same `/user-terminal-config` share), and a Codex session
sees no Claude credentials — nor the reverse. Everything else is the same
container: the same project bind, the same forge auth, the same egress jail.

## Host networking is the default

The container is created with `--network=host`. That is what lets Pi's
relay reach a model server on the host's loopback, and what gives a `shell`
session Channel Access broadcast and X11. The agents gain nothing from it:
every agent runs inside the egress jail either way — the jail only ever
restricts, whatever the container's network mode — so device access for an
agent is still granted per-IP with `allow-ip`, and the host's loopback is
reachable only through the relay ports the conf lists.

`--bridge` creates the container on the engine's bridge network instead. It
is a create-time choice, so switching needs `--recreate`. One consequence
of host mode to know: two projects' containers share the host's loopback,
so the inbound callback relay (port 53692 by default) is taken by whichever
starts first; the second warns and launches without it.

## Update

```bash
uvx claude-sandbox@latest --recreate
```

That fetches the newest wheel, pulls the image of the same version, and
rebuilds the project container from it. With a copied script, pull
`ghcr.io/diamondlightsource/claude-sandbox:latest` yourself and run the
script with `--recreate`. If you launch with `CLAUDE_SANDBOX_ENGINE=docker`,
set the variable on the `--recreate` run too (the launcher reads it on
every invocation; it is not remembered).

## Limitations

- **Your toolchain isn't in the image.** The base is the DLS
  ubuntu-devcontainer (git, build-essential, uv, gh/glab, just…) plus one
  baked Python, an empty venv and Node 22 with npm (see above), not your
  site's module system or cross-compilers. Claude can read, edit,
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
