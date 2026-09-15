# Use Pi with OpenAI or Anthropic

Install the [PyPI launcher](../tutorials/getting-started.md), then run:

```bash
claude-sandbox pi
```

In your own devcontainer with the sandbox installed, run `pi` directly.
Switching agents in an existing project container does not need recreation.

## Sign in and select a model

Inside Pi, use `/login` to configure a provider, then `/model` to select
a model. Logging in does not change the selected model.

Pi's settings, credentials, extensions and sessions live in `~/.pi/agent`,
shared through the terminal-config mount. Pi sees its own credentials,
including all providers configured in Pi; Claude and Codex stores are hidden.
Use Pi's login rather than forwarding host API-key environment variables.

See [Pi's provider documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md)
for provider-specific options.

### Browser login troubleshooting

To relay Pi's Claude subscription login, enable `callback-port = 53692` in
the sandbox config; the shipped example is commented out.
If the port is occupied or your browser cannot reach the container, wait
for the redirect to fail and paste the complete callback URL at Pi's prompt.
Do not copy the earlier provider page while the redirect is still loading.

For additional callback ports, see
[Let a browser login reach the agent](network-egress-jail.md#let-a-browser-login-reach-the-agent).

## Local models

[Run Pi against a local model](pi-with-a-local-model.md) covers lllm2,
automatic model discovery and relay configuration.

## Extensions

From Pi's shell tool or a container terminal:

```bash
pi install npm:PACKAGE_NAME
```

Shared extensions persist in `~/.pi`. The image includes npm with lifecycle
scripts disabled by default; native dependencies may require explicit setup.
See [Pi's package guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md).

## Verify the sandbox

From Pi's shell tool:

```bash
bash /usr/libexec/claude-sandbox/verify-sandbox-battery.sh
```

Or, from a container terminal outside Pi:

```bash
claude-sandbox verify --agent pi
```

The latter needs a working selected model. Pi checks its launch markers before starting. No agent receives managed
prompt or session hooks; the sandbox wrapper provides isolation.
It cannot stop an operator deliberately running a separate unwrapped Pi.

Use [Upgrade](upgrade.md) to update the image. In your own devcontainer,
rebuilding installs the current Pi release; rerunning the installer keeps
an existing binary. Set `PI_VERSION` at installation to select a release,
or `WITH_PI=0` to skip its download.
