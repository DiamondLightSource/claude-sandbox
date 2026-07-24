# Further reading for DLS

Detail deliberately kept off [Claude Code at DLS](claude-at-dls.md) to
keep that page tight.

## Claude in every devcontainer, automatically

Devcontainers that mount `/user-terminal-config` and source its `bashrc`
(all `python-copier-template` devcontainers do) have a run-once section
in `/user-terminal-config/bashrc` that executes on a container's first
shell. Add the install one-liner there:

```bash
cd /tmp && rm -rf claude-sandbox && git clone https://github.com/DiamondLightSource/claude-sandbox && claude-sandbox/install
```

Every devcontainer you open then installs the sandbox on first use —
no per-project setup beyond the three `devcontainer.json` items.

## What the three devcontainer.json items are for

- **`"runArgs": ["--device=/dev/net/tun"]`** — the one hard container
  requirement of the
  [network egress jail](../how-to/network-egress-jail.md). The jail is
  fail-closed: without the device, `claude` refuses to launch rather
  than run with lateral movement open.
- **The `/user-terminal-config` mount** — the installer symlinks
  `~/.claude` and `~/.claude.json` into it, so your Claude login,
  memory, and settings live on the host, survive rebuilds, and are
  shared by every devcontainer that mounts the same directory. See
  [Persist your login and memory](../how-to/persist-login-and-memory.md).
- **The `initializeCommand`** — creates the host directory as *you*
  before the container starts; otherwise the container engine creates
  it root-owned and the mount fights your host UID.

## Forge access and the Diamond network

- `claude-sandbox glab-auth` defaults to `gitlab.diamond.ac.uk`; the
  shipped configuration already punches Diamond's GitLab through the
  egress jail's internal-network blackhole. Any other internal host a
  session must reach needs an `allow-ip` entry — see
  [Configure the network egress jail](../how-to/network-egress-jail.md).
- Tokens are container-scoped on purpose: re-pasting a short-lived PAT
  after a rebuild is the cost of keeping a leaked token's blast radius
  small. See [Authenticate with forges](../how-to/authenticate-with-forges.md).

## Other supported routes

The main page prescribes one route to keep the instructions simple.
Also supported:

- **The prebuilt container image** — sandboxed Claude with no
  devcontainer at all, via rootless Podman and a small launcher:
  [Use the container image](../how-to/use-the-container-image.md).
- **Team rollout at a pinned tag** — a project's `postCreate` clones
  claude-sandbox at a pinned release and installs it, so every teammate
  gets an identical, reviewable sandbox with no manual step:
  [Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md).

## Blocking Claude on the host

The managed-settings gate that denies unsandboxed Claude on DLS
workstations — how it works, what it can and cannot enforce, and the
operator escape hatch — is documented in
[Enforce sandbox use across an organisation](../how-to/enforce-org-wide.md).
