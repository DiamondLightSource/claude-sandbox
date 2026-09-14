# Run Pi against a local model

Use [lllm2](https://gilesknap.github.io/lllm2/) to serve a model on your host,
then connect sandboxed Pi to it. The steps below install both tools.

## Start the model server

On a Linux host with an NVIDIA GPU and driver:

```bash
module load uv                     # DLS workstations
uv tool install --upgrade lllm2
lllm2 engines install cuda
lllm2
```

Open `http://127.0.0.1:8082`. Download a model that fits your GPU, then select
it under **Launch model** and start it. Use **Experiments → Run baseline**
with **Discover usable context** to find a working context allocation.
The model API defaults to `http://127.0.0.1:1920/v1`.
See [lllm2's tutorial](https://gilesknap.github.io/lllm2/tutorials/installation.html)
for model selection and engine setup.

:::{warning} DLS: put model downloads on scratch
Model files can fill your home quota. Before downloading, create a scratch
directory and link it at lllm2's default model location:

```bash
mkdir -p /scratch/<fedid>/models
ln -s /scratch/<fedid>/models ~/models
```

Replace `<fedid>` with your Diamond username. If `~/models` already exists,
move its contents to scratch and move the old directory aside before creating
the link; otherwise `ln` may create a link inside it instead.
:::

## Start Pi

In a host terminal, install the launcher and run it from your project:

```bash
module load uv                     # DLS workstations
uv tool install claude-sandbox
cd /path/to/my-project
claude-sandbox pi --provider lllm2
```

:::{note} DLS module setup
`module load uv` makes uv available on DLS workstations. Elsewhere, install
[uv](https://docs.astral.sh/uv/getting-started/installation/) and skip that line.
:::

The launcher uses host networking by default. The sandbox relays port 1920
into the agent's private loopback while keeping the network jail enabled.
Do not use `--bridge` when the server is on the host's loopback.

At launch, the helper discovers the loaded model and context allocation,
then refreshes Pi's `lllm2` provider. You can also start
`claude-sandbox pi` and choose it with `/model`.

After changing the model, restart Pi or run `!claude-sandbox pi-local`
inside Pi, then use `/model` again. If discovery fails, the existing
configuration is retained. Test a file edit or tool call: support depends
on the model and its chat template.

## Change the port or configure a model manually

Set `local-model-port` in your
[host config](use-the-container-image.md#configure-the-sandbox), or in
`/etc/claude-sandbox.conf` for your own devcontainer:

```ini
local-model-port = 1920
```

Restart Pi after changing it. Setting `0` disables discovery and that relay.
A custom devcontainer needs host networking to reach a host-local server.

For a server without llama.cpp's discovery endpoints, use your devcontainer
terminal (or open `claude-sandbox shell` from the host) and supply the actual
model ID, allocated context and port:

```bash
claude-sandbox pi-local 'MODEL_ID' 32768 1920
```

See [Configuration](../reference/configuration.md) for overrides and
[Pi's model guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md)
for custom provider settings.

The relay exposes every API operation on the selected port.
See [Use Pi](use-pi.md) for cloud login, extensions and verification.
