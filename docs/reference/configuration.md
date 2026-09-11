# Configuration

Reference for the two configuration surfaces: the host-global config
file `/etc/agent-sandbox.conf` and the `AGENT_SANDBOX_*` environment
variables. For task recipes see the [how-to guides](../how-to.md).

## `/etc/agent-sandbox.conf`

The shadow reads this file at every launch. It is seeded by
`install.sh` from the installing clone's
`.devcontainer/agent-sandbox.conf` (the shipped defaults). It lives at
`/etc`, **not** in the rw-bound workspace, so a compromised session
cannot rewrite it to widen the next launch's binds — or, with
`allow-ip`, its network reach.

To change it, edit `/etc/agent-sandbox.conf` directly in the container
(you are root); the next `claude` launch picks it up. Edits are
per-devcontainer and not persisted: a rebuild, re-install, or
`agent-sandbox update` restores the shipped defaults, so re-apply
afterwards. Teams that want a persistent conf bake it in at install
time — see
[Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md).

A missing file is a no-op (`parse_config` returns). The installer
skips placing it if the clone carries no conf. File mode is `0644`.

### Format

- One directive per line.
- `key = value`, or a bare `key` for boolean flags.
- Blank lines and `#` comments are ignored.
- Environment variables already set take precedence — the config
  supplies defaults.

### Keys

| Key | Value | Effect |
|---|---|---|
| `workspace-root` | absolute path | Sets the rw bind-mount root if `AGENT_SANDBOX_WORKSPACE_ROOT` is not already set. Empty value ignored |
| `no-forge` | bare flag (no value) | Equivalent to `AGENT_SANDBOX_NO_FORGE=1`: skips the `gh`/`glab` token binds and removes the credential helpers from the generated gitconfig |
| `allow-write` | absolute path | Adds an extra writable bind. Repeatable — each `allow-write` line appends one path. Empty values skipped; non-existent paths are skipped at bind time |
| `pass-env` | variable name(s) | Forwards named environment variables through the `--clearenv` scrub. Comma- or space-separated, and repeatable. Names only — the value is read from the launching environment. Unset, non-identifier and denied names are skipped |
| `local-model-port` | TCP port 1–65535; shipped default `1920`; `0` drops it; bare flag means `1920` | The port Pi discovers a model on at startup. Always part of the loopback relay set ({ref}`adr-local-port-all-agents`), so every agent reaches it on its own `127.0.0.1`. Environment `AGENT_SANDBOX_LOCAL_MODEL_PORT` takes precedence. See [Use Pi](../how-to/use-pi.md) |
| `local-port` | TCP port 1–65535 | Adds a port to the loopback relay set: the outer container's `127.0.0.1:<port>` becomes reachable at the same address inside the jail, for every agent. Repeatable — one port per line. Merged with `AGENT_SANDBOX_LOCAL_PORTS` from the environment and deduplicated. Each relayed service is exposed in full. Requires the network jail and `socat`. See [Reach services on the host's loopback](../how-to/network-egress-jail.md#reach-services-on-the-hosts-loopback) |
| `callback-port` | TCP port 1–65535; shipped default `53692` | The reverse relay ({ref}`adr-callback-port-relay`): a port the agent listens on inside its loopback becomes reachable at the outer container's `127.0.0.1:<port>`, so a browser on the host can complete an OAuth login that redirects to `localhost`. Repeatable. Merged with `AGENT_SANDBOX_CALLBACK_PORTS` and deduplicated; may not also be a `local-port` or `local-model-port`. A port already taken on the host is skipped with a warning. See [Let a browser login reach the agent](../how-to/network-egress-jail.md#let-a-browser-login-reach-the-agent) |
| `egress-jail` | bare flag / `1` reaffirms on | The per-process network egress jail ({ref}`adr-network-egress-jail`) is **ON by default** and fail-closed; the key normally never needs to appear. An operator opt-out value exists but is deliberately not documented here — weakening the sandbox is discouraged. `AGENT_SANDBOX_EGRESS_JAIL` in the environment takes precedence over this key |
| `allow-ip` | bare IP (no CIDR) | A device IP the egress jail keeps reachable past its RFC1918 blackhole (e.g. an EPICS IOC / PMAC / internal GitLab by bare address). Repeatable — each line punches one `/32` route via the gateway. Lives in `/etc`, not the workspace, so a compromised session cannot widen its own network reach. No effect when the jail is disabled |

```ini
# .devcontainer/agent-sandbox.conf  (installed to /etc/agent-sandbox.conf)
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
| `LD_*`, `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `IFS` | Loader and shell startup hooks — they execute code in every process the session spawns |

## Environment variables

Set these in your devcontainer's `remoteEnv` (restart or rebuild for the
change to take effect). Names below are verified against the shadow and
installer sources.

| Variable | Set by / read by | Meaning |
|---|---|---|
| `AGENT_SANDBOX_WORKSPACE_ROOT` | you (`remoteEnv`) → shadow | Explicit rw bind-mount root. Set to `/workspaces` to restore the old broad bind; any absolute path for a custom root. Default when unset: `$PWD` |
| `AGENT_SANDBOX_NO_FORGE` | you (`remoteEnv`) → shadow | `1` skips the `gh`/`glab` token binds and drops the credential helpers from the generated gitconfig, so `git push` fails inside the sandbox by design |
| `DANGEROUSLY_ALLOW_AGENT_SANDBOX_UNWRAPPED` | you → `install.sh` (install-time) | `1` stamps the root-owned gate escape-hatch flag `/etc/claude-code/allow-unwrapped` (downgrades the unwrapped-launch gate to warn-only; weakening the sandbox is discouraged); unset/`0` leaves the gate fail-closed and removes a stale flag. Replaces the retired `AGENT_SANDBOX_ALLOW_UNWRAPPED` env hatch, which a confined Claude could forge via `~/.claude/settings.json` (deep-review H4) |
| `AGENT_SANDBOX_EGRESS_JAIL` | you (env, per session) / conf `egress-jail` → shadow | Network egress jail toggle ({ref}`adr-network-egress-jail`). Default **ON**, fail-closed: with the jail on but `/dev/net/tun` / pasta / `unshare` missing, `claude` refuses to launch. An operator opt-out value exists but is deliberately not documented — weakening the sandbox is discouraged. Env value wins over the `egress-jail` conf key |
| `AGENT_SANDBOX_ALLOW_IP` | populated by `parse_config` from `allow-ip` lines | Newline-separated device IPs the jail keeps reachable past the RFC1918 blackhole |
| `AGENT_SANDBOX_LOCAL_PORTS` | you (env, per session) and `parse_config` from `local-port` lines | Extra outer-loopback TCP ports relayed into the jail, space-, comma- or newline-separated. Conf entries are appended to whatever the environment already holds, so `AGENT_SANDBOX_LOCAL_PORTS=8082 claude` adds one port for one session ({ref}`adr-local-port-all-agents`) |
| `AGENT_SANDBOX_LOCAL_MODEL_PORT` | you (env, per session) / conf `local-model-port` → shadow, and into the sandbox for Pi | The model port Pi discovers on; always in the relay set. `0` drops it. Env wins over conf |
| `AGENT_SANDBOX_CALLBACK_PORTS` | you (env, per session) and `parse_config` from `callback-port` lines | Outer-loopback TCP ports relayed into the jail for browser OAuth callbacks, space-, comma- or newline-separated. Conf entries are appended to the environment's, so `AGENT_SANDBOX_CALLBACK_PORTS=1455 codex` adds one port for one session ({ref}`adr-callback-port-relay`) |
| `IS_SANDBOX` | set by bwrap (`--setenv IS_SANDBOX 1`) | Sentinel proving the sandbox was entered. The shadow's recursion guard falls through to the real binary when it is `1`; the gate blocks every prompt unless it is `1` |
| `AGENT_SANDBOX_ALLOW_WRITE` | populated by `parse_config` from `allow-write` lines | Newline-separated extra writable paths bound in addition to the workspace |
| `AGENT_SANDBOX_PASS_ENV` | populated by `parse_config` from `pass-env` lines | Names of environment variables to forward into the sandbox. Set it directly to forward a variable for one session without editing the conf |
| `AGENT_SANDBOX_GITCONFIG_PATH` | exported by the shadow | Path to the curated gitconfig (`/etc/claude-gitconfig`) consumed by the argv builder |
| `CLAUDE_CODE_REMOTE` | Claude Code Web | When `true`, both guard scripts skip (the guard does not run on Claude Code Web) |
| `DISABLE_AUTOUPDATER` | set to `1` in managed settings by `install.sh` | Disables Claude Code's in-container auto-updater (alongside `autoUpdates:false`) so a self-update can't re-arm the unwrapped-launch bypass |

`AGENT_SANDBOX_NO_FORGE` is documented as a task in
[run a no-push session](../how-to/run-without-push-access.md); workspace scope
is covered in [widen the writable workspace](../how-to/configure-workspace-scope.md);
forwarding variables is covered in
[pass environment variables in](../how-to/pass-environment-variables.md).

## Gate escape-hatch flag: `/etc/claude-code/allow-unwrapped`

The `UserPromptSubmit` gate ([integrity guard](../explanations/integrity-guard.md))
is fail-closed: it blocks every prompt unless Claude is inside the bwrap
shadow (`IS_SANDBOX=1`). A root-owned flag file at this path downgrades
the gate to warn-only. It exists for operators who need a deliberate,
root-gated exception; how to manage it is documented for IT/platform
teams in
[Enforce sandbox use across an organisation](../how-to/enforce-org-wide.md),
not here. When the flag is present the `SessionStart` warning still
fires: unwrapped is allowed, never silent.

It is deliberately a flag under `/etc`, **not** an environment variable:
`/etc` is root-owned, read-only inside the sandbox (`--ro-bind / /`), and
not part of the host-shared `~/.claude`. A confined Claude can write
`~/.claude/settings.json` (host-shared, persistent) and Claude Code
exports that file's `env` block into later sessions, so an env-var hatch
was forgeable from inside the jail and would persistently neutralise the
gate on a later unwrapped launch (deep-review **H4**). Only `root` on the
host can create this flag.
