[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Docs](https://img.shields.io/badge/docs-online-blue.svg)](https://diamondlightsource.github.io/agent-sandbox/)

# agent-sandbox

bwrap-isolated coding agents for Debian/Ubuntu devcontainers (rootless Podman
is the supported runtime; rootless Docker likely works but is untested with
the default egress jail). One sandbox wraps **Claude Code**, **OpenAI Codex
CLI** and **Pi** (with Anthropic, OpenAI or local models): a hostile prompt,
file, or tool result cannot reach your host credentials, IDE bridges, or shell
environment. The protection is launch-time: plain `claude`, `codex` and `pi`
resolve to a shadow that wraps the real binary in `bwrap`, and a global
integrity guard fails loud and closed if an agent is ever launched unwrapped.

Claude Code is the primary agent and the one the tutorials and how-tos walk
through; the same install gives you the others.

📖 **Documentation: <https://diamondlightsource.github.io/agent-sandbox/>**

## Why use agent-sandbox

Agents are vulnerable to prompt injection embedded in the text they process (web pages, commit messages etc). This can allow a bad actor to take control of your agent. Agents can also make mistakes.

The blast radius for badly behaved agents can be very large when they are running as a user whose credentials are within their reach. All your credentials are often available to an agent running under your account on your workstation.

For this reason coding agents such as Claude Code default to asking for user approval for every tool call they are going to make. But in real use this leads to 'approval fatigue' where users stop checking what the agent is about to do. Classifier-based 'auto' modes are a partial fix, where a second model approves tool calls that don't look dangerous. Unfortunately such modes have been demonstrated to be defeated by careful prompt injection.

Hence, agent vendors recommend running the agent in an isolated environment where it does not have access to your credentials and you carefully control what network devices and filesystem folders it does have access to. agent-sandbox gives you that control inside a developer container running locally on your workstation, for every agent it wraps.

This report demonstrates key sandbox isolation properties: https://gist.github.com/gilesknap/582a289874e65b89fc99f09df37cf121.


## Install

Inside any Debian/Ubuntu devcontainer (running as `root`, the typical
rootless-podman pattern):

```
cd /tmp && rm -rf agent-sandbox && git clone https://github.com/DiamondLightSource/agent-sandbox && agent-sandbox/install
```

This installs the newest **release**, not the tip of `main` — `install`
checks the newest release tag out first and prints which one it picked
(`--here` installs the checkout as-is; `--release REF` picks a specific
one).

Then run `claude` as usual — the shadow on `$PATH` wraps every invocation.
Nothing depends on the clone after install, so a clone in `/tmp` is fine —
it evaporates with the container. The installer is idempotent; wire the
same one-liner into your devcontainer's `postCreate.sh` to re-establish it
on every rebuild (or clone at a pinned tag for a reviewable rollout — see
the [team how-to][team-howto]). Afterwards, `agent-sandbox update`
upgrades to the latest release and `agent-sandbox version` reports what
you have.

The [getting-started tutorial][tutorial] has the full walkthrough, including the
`/user-terminal-config` clone location for `python-copier-template`
devcontainers.

### Not a devcontainer user? Prebuilt image

A published image (`ghcr.io/diamondlightsource/agent-sandbox`) ships the whole sandbox
pre-installed — any Linux host with rootless podman can run a sandboxed agent
(Claude Code by default; `--agent codex` or `--agent pi` for the others) with
no devcontainer and no root access (docker is untested with the egress jail):

```bash
curl -fsSLO https://raw.githubusercontent.com/DiamondLightSource/agent-sandbox/main/container/agent-container
chmod +x agent-container
cd ~/src/my-project && ./agent-container
```

The launcher runs unsandboxed on your host — it is ~200 lines of bash; read it
before you run it. See [Use the prebuilt container image][container] for
pinning the fetch to a fixed ref, persistence, forge auth, and configuration;
each image records the launcher version it was tested with, and
`agent-container` tells you when your copy is out of date.

## What you get

- A shadow `claude` **and `codex`** — the same shadow file under both names,
  dispatching on `argv[0]` — that wraps the real binary in `bwrap` (`--ro-bind / /`,
  `--tmpfs $HOME`, `--clearenv`, `--cap-drop ALL`, PID/IPC/UTS namespaces,
  TIOCSTI defence) so host credentials and IDE bridges are unreachable.
- A per-process **egress jail** (ADR 0015, on by default) that runs Claude in
  its own network namespace and blackholes RFC1918 (internal LANs, lab devices)
  while leaving the internet, DNS, and configured `allow-ip` devices reachable —
  so a compromised session can't pivot sideways to internal hosts. Fail-closed
  (needs `--device=/dev/net/tun`).
- A global, tamper-resistant **integrity guard** (highest-precedence
  managed-settings hooks + a disabled auto-updater) that fails loud and closed
  if Claude is ever launched outside the shadow.
- **Refusal-on-failure**: if the host can't run unprivileged user namespaces the
  installer refuses, rather than install a sandbox that isn't one.
- **More than one agent**: OpenAI's Codex CLI (the client for GPT-6 Astra) gets
  the same jail, the same egress allowlist and the same fail-closed guard —
  delivered through Codex's own admin tier at `/etc/codex/requirements.toml`.
  Each agent sees only its own credentials. Skip the download with
  `WITH_CODEX=0 ./install`; the codex shadow and guard are installed regardless,
  so an unwrapped `codex` can never quietly appear on `$PATH`.
  `codex agents` automatically starts a private app-server inside its sandbox
  and stops it when you exit. This avoids daemon PID tracking, which is
  incompatible with the container's procfs view. Explicit `--remote`
  connections use the server you specify. The automatic server belongs to
  this invocation; it is not shared across terminals.
- **Pi with cloud or local models**: run `pi` (or `agent-container --agent pi`),
  authenticate OpenAI or Anthropic with `/login`, and switch using `/model`.
  A localhost relay defaults to port 1920 and discovers lllm2's model and
  context at startup, keeping the network jail enabled. The same relay serves
  Claude and Codex, and `local-port` lines in the conf add further ports. A
  reverse `callback-port` relay lets Pi's Claude Pro/Max browser login
  complete inside the jail. Pi has its own
  persistent credentials and a launch guard. See [Use Pi](docs/how-to/use-pi.md)
  for setup and guard limitations.
  `WITH_PI=0 ./install` skips downloading Pi.

How and why it works: the [architecture overview][arch], the
[threat model][threat], and the [network egress jail decision (ADR 0015)][jail].

## Documentation

| | |
|---|---|
| [Tutorial][tutorial] | Get to a working, verified sandbox. |
| [How-to guides][howto] | Verify, authenticate forges, configure workspace scope, configure the egress jail, sandbox a team devcontainer, upgrade. |
| [Reference][reference] | Locked-down defences, the egress jail, the verification checks, config keys, deliberate exposures. |
| [Explanations][explain] | Threat model, architecture, the integrity guard, sandbox internals. |

## Development

```
bash tests/bwrap_argv.sh
bash tests/smoke.sh
```

The same two commands CI runs — bash all the way down, no `uv`/pytest (see the
[contributing guide][contribute]). The repo's own `.claude/` is the canonical
source of the skills and commands the installer ships into target workspaces.
The docs live in `docs/` — the one isolated Python toolchain — and publish to
GitHub Pages on every push to `main`.

## License

See [`LICENSE`](./LICENSE).

[tutorial]: https://diamondlightsource.github.io/agent-sandbox/tutorials/getting-started.html
[team-howto]: https://diamondlightsource.github.io/agent-sandbox/how-to/sandbox-a-team-devcontainer.html
[howto]: https://diamondlightsource.github.io/agent-sandbox/how-to.html
[reference]: https://diamondlightsource.github.io/agent-sandbox/reference.html
[explain]: https://diamondlightsource.github.io/agent-sandbox/explanations.html
[arch]: https://diamondlightsource.github.io/agent-sandbox/explanations/architecture.html
[threat]: https://diamondlightsource.github.io/agent-sandbox/explanations/threat-model.html
[jail]: https://diamondlightsource.github.io/agent-sandbox/explanations/decisions/0015-network-egress-jail.html
[contribute]: https://diamondlightsource.github.io/agent-sandbox/how-to/contribute.html
[container]: https://diamondlightsource.github.io/agent-sandbox/how-to/use-the-container-image.html
