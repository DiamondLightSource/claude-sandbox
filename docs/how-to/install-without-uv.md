# Install without uv

Prefer the [PyPI quick start](../tutorials/getting-started.md). Use these
fallbacks when uv is unavailable.

## Host launcher

Clone the repository at a chosen release and run its launcher:

```bash
git clone --branch 4.0.0 --depth 1 https://github.com/DiamondLightSource/claude-sandbox /path/to/claude-sandbox
cd ~/src/my-project
CLAUDE_SANDBOX_IMAGE=ghcr.io/diamondlightsource/claude-sandbox:4.0.0 \
  /path/to/claude-sandbox/container/claude-container
```

Choose an unused clone path. Rootless Podman and the other
[host prerequisites](../tutorials/getting-started.md#1-install-on-your-host)
still apply. Keep the script release and image tag aligned when updating;
the copied script otherwise defaults to the `:latest` image.

## Install into a devcontainer

Inside a Debian/Ubuntu devcontainer, as root:

```bash
CSBX_DIR="$(mktemp -d)"
git clone --depth 1 --branch 4.0.0 https://github.com/DiamondLightSource/claude-sandbox "$CSBX_DIR"
bash "$CSBX_DIR/install" --here
claude
```

`--here` installs the chosen checkout. Without it, the installer attempts
to select the newest release and refuses a pinned or modified checkout.
The installed sandbox does not depend on the temporary clone afterwards.

Use the same block in `postCreate.sh` for a pinned team install.
The [team guide](sandbox-a-team-devcontainer.md) covers the tun device,
configuration and verification.
