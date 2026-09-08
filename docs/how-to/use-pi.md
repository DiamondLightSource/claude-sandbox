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
shows the providers configured by `/login`. For browser callbacks that cannot
reach the sandbox's loopback, use Pi's manual redirect/code entry when offered.

Pi's configuration, credentials, extensions and sessions live in
`~/.pi/agent`. The installer shares `~/.pi` through `/user-terminal-config`.
A Pi session sees its own store; Claude and Codex stores are hidden. All
providers configured in Pi share the Pi store. Host `OPENAI_API_KEY` and
`ANTHROPIC_API_KEY` variables remain stripped; use `/login` to save credentials
instead of changing the environment allowlist.

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

1. Outside the sandbox, add this to `/etc/claude-sandbox.conf` in the
   devcontainer. To retain it across rebuilds, also set it in the clone's
   `.devcontainer/claude-sandbox.conf` used by the installer:

   ```ini
   local-model-port = 1920
   ```

   For the published-image launcher, put the line in the host's
   `~/.config/claude-sandbox.conf`, mounted read-only by the launcher.
   Alternatively set `CLAUDE_SANDBOX_LOCAL_MODEL_PORT=1920` in the launching
   terminal. An explicit `0` disables the relay and overrides the config file.

2. Get the served model ID from a normal terminal sharing the server's
   network namespace:

   ```bash
   curl --noproxy '*' -fsS http://127.0.0.1:1920/v1/models | jq -r '.data[].id'
   ```

3. Configure Pi with that ID and the **actual context allocated in lllm2**.
   For example, if the running model has 32768 tokens of context:

   ```bash
   claude-sandbox pi-local 'MODEL_ID_FROM_ABOVE' 32768
   ```

   Run this in the devcontainer or in Pi's shell (`!claude-sandbox pi-local …`).
   It adds/replaces only the `lllm2` provider in `~/.pi/agent/models.json`,
   preserving other providers. A third argument selects a different port; it
   must match `local-model-port`. Re-run after changing the served model ID or
   context allocation. Other OpenAI-compatible servers can use this command,
   or Pi's [custom model configuration](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md).

4. Start a new Pi session, then select `lllm2` in `/model`:

   ```bash
   pi
   # Published image:
   claude-container --host-net --agent pi
   ```

   `/model` switches between configured local and cloud models and reloads
   `models.json`. Small context allocations may require adjusting Pi's
   compaction settings; allow room for tools, instructions and replies.
   Tool calling depends on the model and chat template; validate an actual
   file edit or shell tool call with your model.

The relay is opt-in, applies only to Pi, and exposes exactly one TCP port from
the outer container's IPv4 loopback to the same port on Pi's loopback. It uses
a private Unix socket between two `socat` processes; it adds no LAN route and
does not expose other localhost ports or the workbench UI. Relay listeners and
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
