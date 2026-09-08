# What's installed

The files `./install` places, by scope. For the configuration these
files read, see [configuration](configuration.md).

## Container-scoped

Re-established by re-running `./install`, typically wired into
`postCreate.sh`.

The apt step also installs `passt` (which provides `pasta`, the userspace
network forwarder the {ref}`egress jail <adr-network-egress-jail>` attaches to
Claude's private netns). The jail's one container-side requirement —
`--device=/dev/net/tun` in `devcontainer.json`'s `runArgs` — is **not**
something the installer can add (a runArg is a container-launch setting); on a
host missing it the jail fails closed and `claude` refuses to launch with a
message naming the fix.

| Path | Source | Purpose |
|---|---|---|
| `/usr/libexec/claude-sandbox/claude` | Anthropic installer (`curl -fsSL https://claude.ai/install.sh \| bash`), relocated | The real Claude binary, kept off the user's PATH so the shadow always wins |
| `/usr/local/bin/claude` | `.devcontainer/claude-sandbox/claude-shadow` (verbatim) | Shadow that wraps the real binary in `bwrap`. Falls through to the real binary when `IS_SANDBOX=1` so internal `claude` invocations from a hook don't recurse |
| `/usr/libexec/claude-sandbox/codex-dist/` | OpenAI installer (`curl -fsSL https://chatgpt.com/codex/install.sh \| sh`), whole release dir relocated | The real Codex CLI package (the client for GPT-6 Astra) — `bin/codex` plus ripgrep and Codex's own bwrap/zsh helpers, which the vendor requires to sit together. Kept off the user's PATH for the same reason as Claude's, and exec'd in place so it is **read-only** inside the sandbox. Best-effort: a failed fetch warns rather than failing the install |
| `/usr/local/bin/codex` | `.devcontainer/claude-sandbox/claude-shadow` (verbatim — the **same file**) | The same shadow under the other agent's name; it picks its profile from `argv[0]` ({ref}`ADR 18 <adr-multi-agent-shadow>`). Installed even when the Codex binary is not, so the shadow owns the name on `$PATH` before the vendor's installer can claim it — it then loud-fails with instructions rather than letting an unwrapped `codex` run |
| `/usr/local/bin/claude-sandbox` | `.devcontainer/claude-sandbox/claude-sandbox` (verbatim) | Helper CLI (`gh-auth`, `glab-auth`, `update`, `verify`, `version`) — on PATH so it works after the install clone is deleted |
| `/usr/libexec/claude-sandbox/version` | Stamped by `install.sh` (`git describe` on the installing clone, or the `CLAUDE_SANDBOX_VERSION` build arg) | What `claude-sandbox version` reports. Normally a release tag: `install` checks the newest one out before installing, as does `claude-sandbox update`. A commit hash means the revision was chosen deliberately — `install --here` on a branch or working tree, or a team pin (see [Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md)) |
| `/etc/claude-gitconfig` | Generated | Curated gitconfig — regenerated from `git config --get user.{name,email}` on every shadow launch |
| `/usr/libexec/claude-sandbox/sandbox-verify.sh` | `.devcontainer/claude-sandbox/sandbox-verify.sh` | `SessionStart` guard script — full integrity battery + loud warn when unwrapped. Off-PATH, root-owned, ro inside the sandbox |
| `/usr/libexec/claude-sandbox/sandbox-gate.sh` | `.devcontainer/claude-sandbox/sandbox-gate.sh` | `UserPromptSubmit` guard script — sub-second fail-closed gate (`IS_SANDBOX=1` or block). Same protections |
| `/etc/claude-code/managed-settings.json` | jq-merged by `install.sh` | The GLOBAL guard policy. Adds the two hooks (deduped by basename), sets `env.DISABLE_AUTOUPDATER=1` + `autoUpdates:false`. Highest-precedence + user-uneditable, so removing the hooks from `~/.claude/settings.json` does **not** disable the guard. Any real admin policy already in the file is preserved; `allowManagedHooksOnly` is deliberately **not** set (your own hooks still run) |
| `/etc/codex/requirements.toml` | Written by `install.sh` | Codex's HARD managed tier — the `/etc/codex` analogue of `managed-settings.json`. Carries the same two guard hooks (`SessionStart` → verifier, `UserPromptSubmit` → gate), pointing at the same root-owned `/usr/libexec` scripts. Above Codex's project-scoped `.codex/config.toml`, which lives in the read-write workspace and is therefore attacker-writable. `allow_managed_hooks_only` deliberately **not** set. A file we did not write is left untouched with a warning |
| `/etc/codex/managed_config.toml` | Written by `install.sh` | Codex's soft managed tier — `check_for_update_on_startup = false`, the same root-cause removal as Claude's `DISABLE_AUTOUPDATER`. The in-sandbox half (`CODEX_UPDATE_DISABLED=1`) is set by the shadow |
| `/etc/claude-sandbox.conf` | `.devcontainer/claude-sandbox.conf` (skip-if-absent) | Host-global sandbox config read by the shadow at launch — `workspace-root`, `no-forge`, `allow-write`, plus the egress-jail keys `egress-jail` / `allow-ip` (ADR 0015). Applies to **both** agents. See [configuration](configuration.md) |

Disabling the auto-updater is root-cause removal: Claude Code's updater
otherwise re-creates `~/.local/bin/claude` on a version bump, which can
launch the real binary unwrapped and self-entrench. With the updater
off, updates happen only via a deliberate re-install (`claude-sandbox
update`, or re-running `install` from a fresh clone), which
re-relocates the current binary and re-asserts the shadow. See the
[shadow-on-PATH explanation](../explanations/integrity-guard.md).
The Codex CLI gets the same treatment through its own managed tier — the
bypass it closes is identical.

## Both agents, one sandbox

`claude` and `codex` are wrapped by the **same shadow file**, which resolves a
per-agent profile from `argv[0]`. The bwrap argv, the egress jail and the
`script(1)` pty wrap are shared code; only the binary to exec, the `$HOME`
paths bound for login state, and the injected flags differ
({ref}`ADR 18 <adr-multi-agent-shadow>`).

Each agent sees **only its own credentials**: a `codex` session binds
`~/.codex` and gets no `~/.claude`/`~/.claude.json`, and vice versa. Both
sessions get the same workspace bind, the same forge credentials (unless
`no-forge`), and the same egress jail.

Run `WITH_CODEX=0 ./install` to skip *fetching* the Codex binary. The codex
shadow and guard are installed either way.

## User-scope `~/.claude`

Preference only — the guard does **not** live here.

| Path | Behaviour |
|---|---|
| `~/.claude/statusline-command.sh` | Statusline — seeded **only if absent** (an owner-customised one survives) |
| `~/.claude/settings.json` | `.statusLine` set only if absent; otherwise untouched. If an earlier install put the guard here, those hook entries are pruned so the guard has a single authoritative home (`/etc`). All other keys — yours — preserved |

## User-scope `~/.codex`

`CODEX_HOME`. Created if absent so the shadow's bind succeeds on a first
launch; its contents (`config.toml`, `auth.json`, `sessions/`) are yours and
are never rewritten. Like `~/.claude`, it joins the `/user-terminal-config`
share when one is mounted, so a Codex login survives a devcontainer rebuild —
it is one vendor login, not a repo-scoped forge PAT
({ref}`ADR 6 <adr-container-scoped-credentials>`).

Not placed: `CLAUDE.md` and `README-CLAUDE.md` live in the meta-repo for
dogfooding.
