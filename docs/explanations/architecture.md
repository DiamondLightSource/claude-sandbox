# Architecture

The host launcher starts a project container. Inside it, the same wrapper
launches Claude, Codex or Pi in a bubblewrap jail. A custom devcontainer uses
that wrapper too.

## Launch sequence

1. The shell resolves `claude`, `codex` or `pi` to a wrapper in
   `/usr/local/bin`. The vendor binaries live off PATH under
   `/usr/libexec/claude-sandbox`.
2. The wrapper reads `/etc/claude-sandbox.conf`, refreshes the curated Git
   config from your name and email, and selects the agent's profile.
3. It creates a private network namespace, attaches `pasta` for internet
   access, and installs the routing restrictions.
4. It starts bubblewrap with the filesystem mounts, scrubbed environment,
   dropped capabilities and separate PID, IPC and UTS namespaces.
5. The agent runs inside the jail. A `script(1)` pseudo-terminal separates
   its terminal input from the outer shell.

Missing isolation prerequisites cause launch to fail. Nested agent calls use
`IS_SANDBOX=1` to avoid wrapping again; that marker alone is not proof of
isolation. See [verification](../how-to/verify-the-sandbox.md).

## Filesystem and credentials

The container filesystem starts read-only. Empty temporary filesystems cover
`$HOME`, `/tmp` and available runtime/secret directories. The wrapper then
binds back the workspace, the selected agent's state, shared skills, tool data
and configured extra paths.

Each agent sees its own login store. Forge tokens are deliberately available
unless `no-forge` is set. Other home-directory credentials, including SSH keys,
remain hidden. The exact paths are in
[Deliberately exposed](../reference/deliberately-exposed.md); the bind rationale
is in [Sandbox internals](sandbox-internals.md).

## Network and configuration

The default network jail blocks private networks, connected subnets and
link-local destinations, with exceptions for the gateway, DNS and configured
`allow-ip` addresses. Internet access remains available. See the
[threat model](threat-model.md#the-egress-jail-and-the-native-sandbox) for its limits.

Configuration lives under `/etc`, outside the writable workspace. An agent
cannot edit it to widen the next session's filesystem or network access.
Change it from a container terminal, or through the host launcher's mounted
[configuration file](../reference/configuration.md).

## Installation and updates

The PyPI package, published image and custom devcontainers use the same Bash
installer. Projects reference it rather than copying security code into their
own repositories. [Architecture decisions](decisions.md) record the history.

Vendor auto-updaters are disabled to preserve the wrapper on PATH. Update
through the image or devcontainer installation; see
[Launch isolation and updates](launch-isolation.md).

## Where the code lives

| File | Purpose |
|---|---|
| `container/claude-container` | Host container launcher |
| `.devcontainer/claude-sandbox/claude-shadow` | Agent profiles, mounts, environment and network jail |
| `.devcontainer/claude-sandbox/install.sh` | Agent installation, wrappers and configuration |
| `.devcontainer/claude-sandbox/verify-sandbox-battery.sh` | Deterministic isolation checks |
| `skills/verify-sandbox/` | Adversarial audit instructions and check rationale |
