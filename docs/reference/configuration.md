# Configuration

The sandbox reads `/etc/claude-sandbox.conf` inside the container and
`CLAUDE_SANDBOX_*` environment variables. With the PyPI host launcher, create
`~/.config/claude-sandbox.conf` on the host; it is mounted read-only at that
container path. See [mounting the config](../how-to/use-the-container-image.md#configure-the-sandbox).

On the host, `claude-sandbox` launches containers. Inside the container, the
same name is an administrative helper (`verify`, `gh-auth`, `version`, etc.).
Run `claude-sandbox --help` on the host for launcher options.

## `/etc/claude-sandbox.conf`

The shadow reads this file at every launch. It is seeded by
`install.sh` from the bundled
`.devcontainer/claude-sandbox.conf` (the shipped defaults). It lives at
`/etc`, **not** in the rw-bound workspace, so a compromised session
cannot rewrite it to widen the next launch's binds — or, with
`allow-ip`, its network reach.

For your own devcontainer, edit `/etc/claude-sandbox.conf` directly in the container
(you are root); the next `claude` launch picks it up. Edits are
per-devcontainer and not persisted: a rebuild, re-install, or
`claude-sandbox update` restores the shipped defaults, so re-apply
afterwards. Teams that want a persistent conf bake it in at install
time — see
[Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md).

A missing file is a no-op (`parse_config` returns). The installer
skips placing it if the clone carries no conf. File mode is `0644`.

### Format

- One directive per line.
- `key = value`, or a bare `key` for boolean flags.
- Blank lines and `#` comments are ignored.
- Environment variables take precedence for scalar settings such as
  `workspace-root`. Repeatable lists such as `allow-write` and `local-port`
  append config entries to the environment values.

### Keys

| Key | Value | Effect |
|---|---|---|
| `workspace-root` | absolute path | Sets the rw bind-mount root if `CLAUDE_SANDBOX_WORKSPACE_ROOT` is not already set. Empty value ignored |
| `no-forge` | bare flag (no value) | Equivalent to `CLAUDE_SANDBOX_NO_FORGE=1`: skips the `gh`/`glab` token binds and removes the credential helpers from the generated gitconfig |
| `allow-write` | absolute path | Adds an extra writable bind. Repeatable — each `allow-write` line appends one path. Empty values skipped; non-existent paths are skipped at bind time. Never name the session bus (`/run/user/<uid>/bus`) or an X11 socket (`/tmp/.X11-unix/X0`): either lets the session run programs on the desktop. For VS Code, use the `vscode-headless` skill, which runs it inside the sandbox |
| `pass-env` | variable name(s) | Forwards named environment variables through the `--clearenv` scrub. Comma- or space-separated, and repeatable. Names only — the value is read from the launching environment. Unset, non-identifier and denied names are skipped |
| `gpu` | bare flag / `1`; `0` disables | Exposes NVIDIA and DRM device nodes already available in the outer container to agents. The host launcher `--gpu` also requests GPUs from the engine. Environment `CLAUDE_SANDBOX_GPU` takes precedence |
| `allow-device` | absolute `/dev/…` path | Exposes one existing character or block device read-write to agents using a device bind. Repeatable; merged with the environment. Symlinks resolve to their canonical path. Missing or invalid devices fail launch. Container access must already be configured; the host launcher `--device PATH` does both steps |
| `local-model-port` | TCP port 1–65535; shipped default `1920`; `0` drops it; bare flag means `1920` | The port Pi discovers a model on at startup. Always part of the loopback relay set ({ref}`adr-local-port-all-agents`), so every agent reaches it on its own `127.0.0.1`. Environment `CLAUDE_SANDBOX_LOCAL_MODEL_PORT` takes precedence. See [Use Pi](../how-to/use-pi.md) |
| `local-port` | TCP port 1–65535 | Adds a port to the loopback relay set: the outer container's `127.0.0.1:<port>` becomes reachable at the same address inside the jail, for every agent. Repeatable — one port per line. Merged with `CLAUDE_SANDBOX_LOCAL_PORTS` from the environment and deduplicated. Each relayed service is exposed in full. Requires the network jail and `socat`. See [Reach services on the host's loopback](../how-to/network-egress-jail.md#reach-services-on-the-hosts-loopback) |
| `callback-port` | TCP port 1–65535; disabled by default (commented examples) | Reverse relay: exposes an agent's loopback listener on the outer container's loopback for browser OAuth. Repeatable; merged with `CLAUDE_SANDBOX_CALLBACK_PORTS`. Cannot overlap `local-port` or `local-model-port`. Occupied host ports are skipped with a warning. See [browser logins](../how-to/network-egress-jail.md#let-a-browser-login-reach-the-agent) |
| `egress-jail` | bare flag / `1` reaffirms on | The per-process network egress jail ({ref}`adr-network-egress-jail`) is **ON by default** and fail-closed; the key normally never needs to appear. An operator opt-out value exists but is deliberately not documented here — weakening the sandbox is discouraged. `CLAUDE_SANDBOX_EGRESS_JAIL` in the environment takes precedence over this key |
| `allow-ip` | bare IP (no CIDR) | A device IP the egress jail keeps reachable past its RFC1918 blackhole (e.g. an EPICS IOC / PMAC / internal GitLab by bare address). Repeatable — each line punches one `/32` route via the gateway. Lives in `/etc`, not the workspace, so a compromised session cannot widen its own network reach. No effect when the jail is disabled |

```ini
# .devcontainer/claude-sandbox.conf  (installed to /etc/claude-sandbox.conf)
allow-write = /cache
allow-write = /workspaces/sibling-project
pass-env = DOCKER_HOST

# Keep these device IPs reachable past the RFC1918 blackhole (bare IP):
allow-ip = 172.23.142.119  # internal GitLab
```

### `pass-env` deny-list

These names are ignored, and the sandbox's own value always wins:

| Names | Why |
|---|---|
| `PATH`, `HOME`, `USER`, `IS_SANDBOX`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM` | The sandbox sets each of these itself. Forwarding `PATH` would undo the shadow's PATH discipline; `IS_SANDBOX` would trip the recursion guard into skipping the jail |
| `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `CLAUDE_SANDBOX_AGENT`, `IS_SANDBOX_AGENT` | Agent configuration locations and profile selection remain controlled by the wrapper |
| `LD_*`, `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `IFS` | Loader and shell startup hooks — they execute code in every process the session spawns |

## Environment variables

With the host launcher, `CLAUDE_SANDBOX_*` variables are forwarded at container
creation; recreate to change them. Other host variables are not forwarded.
Inside your own devcontainer, set variables in the launching terminal or
`remoteEnv`. Config-file settings are usually simpler for durable host-launcher
configuration.

| Variable | Set by / read by | Meaning |
|---|---|---|
| `CLAUDE_SANDBOX_WORKSPACE_ROOT` | you (`remoteEnv`) → shadow | Explicit rw bind-mount root. Set to `/workspaces` to restore the old broad bind; any absolute path for a custom root. Default when unset: `$PWD` |
| `CLAUDE_SANDBOX_NO_FORGE` | you (`remoteEnv`) → shadow | `1` skips the `gh`/`glab` token binds and drops the credential helpers from the generated gitconfig, so `git push` fails inside the sandbox by design |
| `CLAUDE_SANDBOX_EGRESS_JAIL` | you (env, per session) / conf `egress-jail` → shadow | Network egress jail toggle ({ref}`adr-network-egress-jail`). Default **ON**, fail-closed: with the jail on but `/dev/net/tun` / pasta / `unshare` missing, `claude` refuses to launch. An operator opt-out value exists but is deliberately not documented — weakening the sandbox is discouraged. Env value wins over the `egress-jail` conf key |
| `CLAUDE_SANDBOX_ALLOW_IP` | populated by `parse_config` from `allow-ip` lines | Newline-separated device IPs the jail keeps reachable past the RFC1918 blackhole |
| `CLAUDE_SANDBOX_LOCAL_PORTS` | you (env, per session) and `parse_config` from `local-port` lines | Extra outer-loopback TCP ports relayed into the jail, space-, comma- or newline-separated. Conf entries are appended to whatever the environment already holds, so `CLAUDE_SANDBOX_LOCAL_PORTS=8082 claude` adds one port for one session ({ref}`adr-local-port-all-agents`) |
| `CLAUDE_SANDBOX_LOCAL_MODEL_PORT` | you (env, per session) / conf `local-model-port` → shadow, and into the sandbox for Pi | The model port Pi discovers on; always in the relay set. `0` drops it. Env wins over conf |
| `CLAUDE_SANDBOX_CALLBACK_PORTS` | you (env, per session) and `parse_config` from `callback-port` lines | Outer-loopback TCP ports relayed into the jail for browser OAuth callbacks, space-, comma- or newline-separated. Conf entries are appended to the environment's, so `CLAUDE_SANDBOX_CALLBACK_PORTS=1455 codex` adds one port for one session ({ref}`adr-callback-port-relay`) |
| `IS_SANDBOX` | set by bwrap (`--setenv IS_SANDBOX 1`) | Marker preventing recursive wrapping of nested agent calls. It is not independent proof of isolation |
| `CLAUDE_SANDBOX_ALLOW_WRITE` | populated by `parse_config` from `allow-write` lines | Newline-separated extra writable paths bound in addition to the workspace |
| `CLAUDE_SANDBOX_GPU` | launcher `--gpu` / conf `gpu` → shadow | `1` exposes available NVIDIA and DRM device nodes inside the jail. Setting this variable alone does not request GPU access from the container engine |
| `CLAUDE_SANDBOX_ALLOW_DEVICES` | launcher `--device` / conf `allow-device` → shadow | Newline-separated device paths to expose inside the jail; setting this alone does not mount devices into the outer container |
| `CLAUDE_SANDBOX_PASS_ENV` | populated by `parse_config` from `pass-env` lines | Names of environment variables to forward into the sandbox. Set it directly to forward a variable for one session without editing the conf |
| `CLAUDE_SANDBOX_GITCONFIG_PATH` | exported by the shadow | Path to the curated gitconfig (`/etc/claude-gitconfig`) consumed by the argv builder |
| `DISABLE_AUTOUPDATER` | set to `1` in managed settings by `install.sh` | Disables Claude Code's in-container auto-updater (alongside `autoUpdates:false`) so a self-update can't re-arm the unwrapped-launch bypass |

`CLAUDE_SANDBOX_NO_FORGE` is documented as a task in
[run a no-push session](../how-to/authenticate-with-forges.md#run-without-push-access); workspace scope
is covered in [widen the writable workspace](../how-to/configure-workspace-scope.md);
forwarding variables is covered in
[pass environment variables in](../how-to/pass-environment-variables.md).
