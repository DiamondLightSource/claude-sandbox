# What's installed

`uv tool install claude-sandbox` installs the host launcher. It selects a
prebuilt image containing the files below. A custom devcontainer gets the
same files through `uvx claude-sandbox install`.
For the configuration they read, see [configuration](configuration.md).

The published image also includes Vim for terminal editing. Installing the
sandbox into a custom devcontainer leaves the choice of editor to that project.

Browser testing is optional. The shipped `browser-testing` skill provides an
outer-container installer for Playwright, Chromium and system dependencies,
plus an in-sandbox smoke check. It preserves project dependencies and caches
browser downloads under `/cache/ms-playwright`; browsers are not baked into
the image. Run the setup script from an outer container terminal:

```bash
sh /usr/libexec/claude-sandbox/skills/browser-testing/scripts/install-browser-deps.sh
```

After setup, `chromium` opens the browser from an outer-container terminal
with a working display. Its profile persists under `/cache/chromium-home`.
See [browser automation](../how-to/browser-automation.md) for setup checks
and example testing prompts.

VS Code automation is also optional. The shipped `vscode-headless` skill
provides an outer-container installer, a virtual-display launcher and a UI
driver. See [VS Code automation](../how-to/vscode-automation.md) for setup
and example editor and debugging workflows.

CUDA development is also optional. The shipped `cuda-development` skill
provides an outer-container installer for the NVIDIA CUDA toolkit and an
in-sandbox GPU smoke test. The host supplies the driver, and the installer
blocks driver packages in the container. See
[CUDA development](../how-to/cuda-development.md).

## Container-scoped

Preinstalled in the published image. In a custom devcontainer, re-established
by `uvx claude-sandbox install`, typically wired into `postCreate.sh`.

The apt step also installs `passt` (which provides `pasta`, the userspace
network forwarder the {ref}`egress jail <adr-network-egress-jail>` attaches to
Claude's private netns). The jail's one container-side requirement —
`--device=/dev/net/tun` in `devcontainer.json`'s `runArgs` — is **not**
something the installer can add (a runArg is a container-launch setting); on a
host missing it the jail fails closed and `claude` refuses to launch with a
message naming the fix. The PyPI host launcher adds the tun device automatically.

| Path | Source | Purpose |
|---|---|---|
| `/usr/libexec/claude-sandbox/claude` | Anthropic installer (`curl -fsSL https://claude.ai/install.sh \| bash`), relocated | The real Claude binary, kept off the user's PATH so the shadow always wins |
| `/usr/local/bin/claude` | `.devcontainer/claude-sandbox/claude-shadow` (verbatim) | Shadow that wraps the real binary in `bwrap`. Falls through to the real binary when `IS_SANDBOX=1` so internal `claude` invocations from a hook don't recurse |
| `/usr/libexec/claude-sandbox/codex-dist/` | OpenAI installer (`curl -fsSL https://chatgpt.com/codex/install.sh \| sh`), whole release dir relocated | The real Codex CLI package (the client for GPT-6 Astra) — `bin/codex` plus ripgrep and Codex's own bwrap/zsh helpers, which the vendor requires to sit together. Kept off the user's PATH for the same reason as Claude's, and exec'd in place so it is **read-only** inside the sandbox. Best-effort: a failed fetch warns rather than failing the install |
| `/usr/local/bin/codex` | `.devcontainer/claude-sandbox/claude-shadow` (verbatim — the **same file**) | The same shadow under the other agent's name; it picks its profile from `argv[0]` ({ref}`ADR 18 <adr-multi-agent-shadow>`). Installed even when the Codex binary is not, so the shadow owns the name on `$PATH` before the vendor's installer can claim it — it then loud-fails with instructions rather than letting an unwrapped `codex` run |
| `/usr/local/bin/pi` | `.devcontainer/claude-sandbox/claude-shadow` (same file) | Pi profile of the shared wrapper; always installed, even with `WITH_PI=0` |
| `/usr/libexec/claude-sandbox/pi-run` | `.devcontainer/claude-sandbox/pi-run` | Fixed launch guard that checks sandbox markers before starting Pi; see [Pi guard limitations](../how-to/use-pi.md#verify-the-sandbox) |
| `/usr/libexec/claude-sandbox/pi-dist/` | Latest Pi standalone release on fresh install, verified against release checksums; optional `PI_VERSION` pin | Pi executable and assets, read-only inside the sandbox; Linux x64 and arm64. Existing installs are kept on re-run. No separate Node.js runtime needed |
| `/usr/local/bin/claude-sandbox` | `.devcontainer/claude-sandbox/claude-sandbox` (verbatim) | Helper CLI (`gh-auth`, `glab-auth`, `update`, `verify`, `pi-local`, `doctor`, `version`) — on PATH so it works after the install clone is deleted |
| `/usr/libexec/claude-sandbox/statusline-command.sh` | `.claude/statusline-command.sh` (verbatim) | The recommended Claude status line, which `claude-sandbox doctor --fix` copies to `~/.claude` |
| `/usr/libexec/claude-sandbox/pi-sandbox-tag.ts` | `.devcontainer/claude-sandbox/pi-sandbox-tag.ts` (verbatim) | Pi footer extension showing the host and container tag, which `claude-sandbox doctor --fix` copies to `~/.pi/agent/extensions` |
| `/usr/libexec/claude-sandbox/installer` | Stamped by `install.sh` only when the PyPI wheel ran it (`uvx`) | Lets `claude-sandbox update` point at `uvx claude-sandbox@latest install` instead of a git clone that would step past the wheel's pin. Absent after a clone install |
| `/usr/libexec/claude-sandbox/version` | Stamped by `install.sh` (`git describe` on the installing clone, the wheel's version under `uvx`, or the `CLAUDE_SANDBOX_VERSION` build arg) | What `claude-sandbox version` reports. Normally a release tag: `install` checks the newest one out before installing, as does `claude-sandbox update`. A commit hash means the revision was chosen deliberately — `install --here` on a branch or working tree, or a team pin (see [Sandbox a team devcontainer](../how-to/sandbox-a-team-devcontainer.md)) |
| `/etc/claude-gitconfig` | Generated | Curated gitconfig — regenerated from `git config --get user.{name,email}` on every shadow launch |
| `/etc/claude-code/managed-settings.json` | jq-merged by `install.sh` | Disables the vendor updater with `env.DISABLE_AUTOUPDATER=1` and `autoUpdates:false`; preserves existing administrator settings and hooks |
| `/etc/codex/managed_config.toml` | Written by `install.sh` | Codex's soft managed tier — `check_for_update_on_startup = false`, the same root-cause removal as Claude's `DISABLE_AUTOUPDATER`. The in-sandbox half (`CODEX_UPDATE_DISABLED=1`) is set by the shadow |
| `/etc/claude-sandbox.conf` | Bundled `.devcontainer/claude-sandbox.conf`, or the host launcher's read-only config mount | Sandbox config for all three agents. See [configuration](configuration.md) |

Disabling the auto-updater is root-cause removal: Claude Code's updater
otherwise re-creates `~/.local/bin/claude` on a version bump, which can
launch the real binary unwrapped and self-entrench. With the updater
off, newer agents come from a deliberately updated image or fresh installation.
Reinstalling the sandbox keeps existing agent binaries and reasserts their
wrappers. See [Upgrade](../how-to/upgrade.md) and the
[shadow-on-PATH explanation](../explanations/launch-isolation.md).
The Codex CLI gets the same treatment through its own managed tier — the
bypass it closes is identical.

## Three agents, one sandbox

`claude`, `codex`, and `pi` are wrapped by the **same shadow file**, which resolves a
per-agent profile from `argv[0]`. The bwrap argv, the egress jail and the
`script(1)` pty wrap are shared code; only the binary to exec, the `$HOME`
paths bound for login state, and the injected flags differ
({ref}`ADR 18 <adr-multi-agent-shadow>`).

Each agent sees **only its own credentials**: a `codex` session binds
`~/.codex` and gets no `~/.claude`/`~/.claude.json`, and vice versa. Both
sessions get the same workspace bind, the same forge credentials (unless
`no-forge`), and the same egress jail.

Run `WITH_CODEX=0 uvx claude-sandbox install` in a custom devcontainer to skip
*fetching* the Codex binary. The codex
shadow is installed either way.

## User-scope `~/.claude`

The installer seeds a statusline preference.

| Path | Behaviour |
|---|---|
| `~/.claude/statusline-command.sh` | Statusline — seeded **only if absent** (an owner-customised one survives) |
| `~/.claude/settings.json` | `.statusLine` set only if absent. Existing settings and hooks are preserved |

`claude-sandbox doctor --fix` replaces both with the recommended status line and
saves a `.bak-` copy of each file first.

## User-scope `~/.codex`

`CODEX_HOME`. Created if absent so the shadow's bind succeeds on a first
launch; its contents (`config.toml`, `auth.json`, `sessions/`) are yours and
are never rewritten. Like `~/.claude`, it joins the `/user-terminal-config`
share when one is mounted, so a Codex login survives a devcontainer rebuild —
it is one vendor login, not a repo-scoped forge PAT
({ref}`ADR 6 <adr-container-scoped-credentials>`).

## User-scope `~/.agents/skills`

Skills shared by every agent. Created if absent (by the shadow at launch) and
bound read-write into Claude, Codex and Pi sessions alike. Codex and Pi load
skills from it natively; Claude loads one only when you symlink it into
`~/.claude/skills`. Its contents are yours and are never rewritten. When
`/user-terminal-config` is mounted, it joins the share, so the skills survive
a rebuild. Only the `skills` directory is bound or shared; the rest of
`~/.agents` stays outside the sandbox
({ref}`ADR 25 <adr-shared-agent-skills>`,
[share skills between agents](../how-to/share-skills-between-agents.md)).

Not placed: `CLAUDE.md` and `README-CLAUDE.md` live in the meta-repo for
dogfooding.
