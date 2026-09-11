# Run Pi against a local model

Serve a model on your own GPU with [lllm2](https://gilesknap.github.io/lllm2/),
then run [Pi](https://pi.dev/) against it inside the sandbox, using the
published container image. No cloud account, no devcontainer, and nothing the
agent does can leave the jail. One page, start to finish; the lllm2 tutorial
[From a model to Pi](https://gilesknap.github.io/lllm2/tutorials/installation.html)
covers the model half in more depth.

```{note}
The project is being renamed from **claude-sandbox** to **agent-sandbox**
([PR #30](https://github.com/DiamondLightSource/claude-sandbox/pull/30)). When that lands, `claude-container`
becomes `agent-container`, the image becomes
`ghcr.io/diamondlightsource/agent-sandbox`, and `CLAUDE_SANDBOX_*` variables
become `AGENT_SANDBOX_*`. Everything else on this page is unchanged.
```

## What you need

- A Linux machine with an NVIDIA GPU and driver.
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (DLS: `module load uv`).
- Rootless Podman, and `/dev/net/tun` on the host. Check with:

  ```bash
  podman info --format '{{.Host.Security.Rootless}}'   # must print true
  ```

Run the shell commands below in a terminal on that machine, outside any
container.

## 1. Serve a model with lllm2

```bash
uv tool install --upgrade lllm2
lllm2 engines install cuda
lllm2
```

Open <http://127.0.0.1:8082> and keep the panel running. Under **Find models**,
queue a download from **My catalogue** or search Hugging Face for a GGUF build
that fits your card; a 27B to 35B parameter model at 4-bit quantisation is a
good match for a 24 GB GPU. Then **Launch model**, choose it, and **Start
Model**.

Before the first agent session it is worth one **Experiments → Run baseline**
with **Discover usable context** checked. Pi's tool calls and a project's files
eat context quickly; the baseline finds the largest window that actually loads,
and **Try in Launch** carries it back to the launch settings. Save them.

The model API is now at `http://127.0.0.1:1920/v1`. Nothing on the Pi side
needs that address: the sandbox discovers it.

```{admonition} DLS users
Keep model files off your home directory. Before downloading, symlink
`~/models` to scratch: `mkdir -p /scratch/<fedid>/models && ln -s
/scratch/<fedid>/models ~/models`.
```

## 2. Install the launcher

The published image ships the whole sandbox with Claude Code, Codex and Pi
already installed. The host needs only the launcher script:

```bash
curl -fsSLO https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/main/container/claude-container
chmod +x claude-container && mv claude-container ~/.local/bin/   # anywhere on PATH
```

It runs unsandboxed on your host, so read it first; it is a short bash script.
Pin a release tag in the URL instead of `main` if you want fixed provenance.
See [Use the prebuilt container image](use-the-container-image.md) for the
launcher's options and its container-per-project model.

## 3. Run Pi

From the project directory you want Pi to work in:

```bash
cd ~/src/my-project
claude-container --host-net --agent pi
```

- `--host-net` shares the model server's network namespace, so Pi's relay can
  reach `127.0.0.1:1920`. Without it the container's loopback is its own.
  The agent's egress jail stays on regardless.
- `--agent pi` picks Pi over the default Claude Code.

The first run pulls the image and creates a container named after the
directory. At every Pi launch the sandbox queries lllm2 for the loaded model
and its real context allocation and writes them into Pi's `lllm2` provider,
so inside Pi you run `/model` and pick it, or start with
`claude-container --host-net --agent pi --provider lllm2`. Your project is
mounted read-write at the same path as on the host; Pi's settings, sessions
and extensions live in `~/.pi`, shared with every container on this host.

Changed the model in lllm2? Restart Pi, or run `!claude-sandbox pi-local`
from Pi's prompt and then `/model` again. Later runs in the same directory
reuse the container, and the launcher says so; `--recreate` rebuilds it after
pulling a newer image. The venv at `/cache/venv` and any `uv` or `npm`
installs persist with the container.

## 4. Install Pi extensions

Pi packages bundle extensions, skills, prompt templates and themes, and are
installed from npm or git. Inside a Pi session:

```
pi install npm:pi-web-access
```

The package lands in `~/.pi/agent/npm/`, on the shared store, so it stays
installed across sessions and containers. The image carries Node 22 with npm,
and npm lifecycle scripts are switched off by default: `pi install` runs no
postinstall hooks inside the jail. Pure-JavaScript packages, which Pi
extensions are, need nothing more. A package that must build a native module
fails at install; opt in deliberately with a project `.npmrc` containing
`ignore-scripts=false`.

For work that has to happen outside the jail, open a plain shell in the same
container:

```bash
claude-container --shell
```

You are root there, apt works, and the `claude-sandbox` CLI is on PATH. Use
it to authenticate to a forge before the first agent session, or to install
system libraries an extension needs. `pi install ...` from that shell still
runs through the sandbox: `pi` is the shadow, and a management subcommand
goes straight to Pi. Exit, then start the agent again.

```bash
claude-container --shell
claude-sandbox gh-auth              # forge push access for this container
pi install npm:pi-web-access        # same as from inside a session
exit
claude-container --host-net --agent pi
```

Project-local packages (`pi install -l`) write to `.pi/settings.json` in the
project and install on startup once the project is trusted; they suit a team
that shares one extension set through git.

## Where to read more

- [pi.dev](https://pi.dev/) and the
  [pi repository](https://github.com/earendil-works/pi), including its
  [documentation folder](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/docs)
  and [packages guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md).
  The installed command is the npm package
  [`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent).
- [lllm2 documentation](https://gilesknap.github.io/lllm2/): model choice,
  context discovery and tuning.
- [Use Pi with OpenAI, Anthropic, or lllm2](use-pi.md): cloud logins, the
  devcontainer route, and the loopback relay in detail.
- [Use the prebuilt container image](use-the-container-image.md): launcher
  options, forge authentication, persistence and limits.
