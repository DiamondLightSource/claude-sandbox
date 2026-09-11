# Use Pi with OpenAI, Anthropic, or lllm2

[Pi](https://pi.dev/) uses the same bwrap wrapper and network jail as Claude
Code and Codex. On a fresh devcontainer, `postCreate` installs the latest Pi
standalone release for Linux x64 and arm64, alongside Claude and Codex. The
developer image contains no agent installation step, so new agent releases do
not require a new developer image. Re-running the installer keeps an existing
Pi installation; rebuilding the devcontainer installs the then-current release.
`PI_VERSION=0.85.1 ./install` optionally selects a specific release instead.
`WITH_PI=0 ./install` skips the download; the `pi` wrapper
remains installed and reports that the binary is missing.

The separate published `claude-sandbox` image runs the same installer at image
build time and includes the agents. Its Pi version can also be selected with
the `PI_VERSION` build argument.

The installer also provides `ripgrep` and `fd-find` (`fdfind` on Debian/Ubuntu),
which Pi uses for searching. This avoids downloading and extracting those tools
inside the sandbox on first launch. For an existing container showing search-tool
download errors, run `apt-get update && apt-get install -y ripgrep fd-find` from
a normal container terminal outside Pi, then restart Pi.

## Start Pi and choose a cloud provider

From a normal devcontainer terminal, run `pi`. With the published image:

```bash
claude-container --agent pi
```

An existing stopped container retains its original agent and image. Use
`--recreate --agent pi` to replace it; container-scoped forge authentication
must then be repeated.

Inside Pi, use `/login` to configure OpenAI or Anthropic with an API key or an
available subscription login, then `/model` to select a model. Pi also accepts
`--provider openai --model MODEL_ID` or `--provider anthropic --model MODEL_ID`
at launch. Subscription logins may use a separate provider name; the picker
shows the providers configured by `/login`.

The Claude Pro/Max login redirects your browser to `http://localhost:53692`,
a server Pi opens on its own loopback. The shipped conf relays that port
into the jail ({ref}`adr-callback-port-relay`), so the login completes in the
browser as it would outside the sandbox, including through VS Code's port
forwarding from a laptop. A login saves credentials but does not change the
selected model: if Pi was last using lllm2, the next prompt still goes there,
and a "Loading model" or connection error means exactly that. Run `/model`
and pick a Claude model. If the sandbox warned at launch that 53692 was
already in use, or your browser cannot reach the container's loopback, let
the tab fail, copy the `http://localhost:53692/callback?code=...` URL from
its address bar, and paste it at Pi's prompt. Do not copy the address bar
while the tab is still loading: it still shows the previous claude.ai page,
whose URL carries a `code=true` parameter that Pi would send as the code.
OpenAI's Codex login uses port 1455 and also offers a device-code flow; see
[Let a browser login reach the agent](network-egress-jail.md#let-a-browser-login-reach-the-agent)
to relay it too.

Pi's configuration, credentials, extensions and sessions live in
`~/.pi/agent`. The installer shares `~/.pi` through `/user-terminal-config`.
A Pi session sees its own store; Claude and Codex stores are hidden. All
providers configured in Pi share the Pi store. Host `OPENAI_API_KEY` and
`ANTHROPIC_API_KEY` variables remain stripped; use `/login` to save credentials
instead of changing the environment allowlist.

The launcher appends a short environment note to Pi's system prompt from
`/usr/libexec/claude-sandbox/pi-system.md`: the root filesystem is read-only,
there is no `apt-get` or `sudo`, Python tooling goes through `uv` and `uvx`,
and outbound network access is allowlisted. Without it Pi cannot tell it is
sandboxed and wastes turns on system-wide installs. The file is root-owned and
read-only inside the session. Your own additions still work through Pi's
usual `~/.pi/agent/APPEND_SYSTEM.md` or a project `AGENTS.md`.

See Pi's [provider documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md)
for authentication details.

## Connect to lllm2 on localhost

Start a model in lllm2 on the host. Its model API defaults to
`http://127.0.0.1:1920/v1`; port 8082 is the workbench UI.

The **outer container must share the model server's network namespace** for
that loopback address to refer to the same server. This repository's
devcontainer already uses `--net=host`. With the published-image launcher use
`--host-net`; an ordinary bridge container's `127.0.0.1` refers to itself.
The inner bwrap network jail remains enabled.

With lllm2 running, start Pi:

```bash
pi --provider lllm2
# Or run pi and select lllm2 in /model.
# Published image:
claude-container --host-net --agent pi
```

The shipped `.devcontainer/claude-sandbox.conf` sets `local-model-port = 1920`.
At each Pi launch, the helper queries `/v1/models` for the single loaded model
and `/props` for its actual per-slot context allocation. It refreshes the
`lllm2` entry in `~/.pi/agent/models.json`, preserving other providers and
local credentials/compatibility overrides. Changing the model in lllm2 needs
no manual model ID edit: restart Pi to discover it. Discovery does not change
your selected cloud provider. If the server is unavailable, startup continues
quietly and the existing model configuration is kept.

If you change the model while Pi is open, run `!claude-sandbox pi-local`, then
use `/model` to reload the configuration and select the new model. From an
ordinary devcontainer terminal, the refresh command is `claude-sandbox pi-local`.

For an existing container, set `local-model-port = 1920` in
`/etc/claude-sandbox.conf` outside the sandbox. Set a different port there if
needed, or `0` to disable both discovery and the relay. Retain changes across
rebuilds in the clone's `.devcontainer/claude-sandbox.conf`. For the
published-image launcher, use the host's `~/.config/claude-sandbox.conf`,
mounted read-only by the launcher. The launching terminal's
`CLAUDE_SANDBOX_LOCAL_MODEL_PORT` overrides the file. Restart Pi after changing
the port. An explicit refresh outside Pi can use `claude-sandbox pi-local --port PORT`.

For servers without llama.cpp's `/props` endpoint, configure manually:

```bash
claude-sandbox pi-local 'MODEL_ID' 32768 1920
```

Supply the actual allocated context and matching relay port. See also Pi's
[custom model configuration](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md).
Small contexts may require adjusting Pi's compaction settings; allow room for
tools, instructions and replies. Tool calling depends on the model and chat
template; validate an actual file edit or shell tool call with your model.

The relay exposes the model port from the outer container's IPv4 loopback to
the same port on Pi's loopback, together with any `local-port` entries (every
agent gets the same relay set; see [Reach services on the host's loopback](network-egress-jail.md#reach-services-on-the-hosts-loopback)). It uses
a private Unix socket between two `socat` processes; it adds no LAN route and
does not expose other localhost ports. Relay listeners and
connections stop when the session exits. The model server may be off while
using a cloud provider. Access covers **all HTTP paths on the selected port**;
this is not a filter for individual API operations.

With the operator's existing egress-jail opt-out, Pi shares the outer
container's network directly and no relay is created. The relay is intended
for the default jailed configuration.

## Verify the sandbox

From inside Pi's shell, run:

```bash
bash /usr/libexec/claude-sandbox/verify-sandbox-battery.sh
```

From an ordinary terminal, `claude-sandbox verify --agent pi` asks Pi to run
the same battery and report the result; it needs a working selected model.

Pi's standalone release and fixed launcher live under
`/usr/libexec/claude-sandbox`, read-only inside the sandbox. The launcher checks
the sandbox markers before running Pi, and startup version checks are disabled.
Rebuild the devcontainer to install the latest Pi, or select an explicit
`PI_VERSION` through the installer. In the published-image workflow, pull a new
image and recreate the container.

Pi does not have the managed prompt-hook tier used by the Claude and Codex
integrations. Its guard is at launch; this integration does not claim to stop
an operator deliberately running a separate, unwrapped installation of Pi.
