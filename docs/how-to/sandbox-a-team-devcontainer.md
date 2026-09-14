# Sandbox a team devcontainer

Make your project's devcontainer bring up the sandbox automatically for
every teammate — without copying any sandbox code into your repo. The
project carries a few lines of `postCreate` wiring; the security-critical
machinery stays in this one auditable repo, at a revision you pin and bump
deliberately.

This is the recommended rollout path for a team. For interactive use
beside your own projects, `uvx claude-sandbox install` in
[Getting started](../tutorials/getting-started.md) is simpler.

## 1. Add the postCreate wiring

In your project's `.devcontainer/postCreate.sh` (create it if absent):

```bash
#!/usr/bin/env bash
# Bring up claude-sandbox at a pinned release. Bumping the pin is a
# deliberate, reviewable act — like any dependency upgrade.
set -euo pipefail
uvx claude-sandbox==4.0.0 install
```

`uvx` fetches the `claude-sandbox` wheel from PyPI. The wheel ships this
repository's installer unchanged and execs it; the pinned version is the
release tag. `install` refuses to run outside a container, so the line
cannot reshape a host if pasted in the wrong terminal.

No `uv` in the image? [Install without uv](install-without-uv.md) has the
same pin as a clone-and-`install --here` block.

Either way, every teammate gets the `claude-sandbox` helper CLI on PATH
(`gh-auth`, `glab-auth`, `verify`, `version`). After a wheel install,
`claude-sandbox update` points back at `uvx` rather than cloning past the
pin.

## 2. Wire it into devcontainer.json

```json
// .devcontainer/devcontainer.json
"postCreateCommand": "bash .devcontainer/postCreate.sh",
"runArgs": ["--device=/dev/net/tun"]
```

(If you already have a `postCreateCommand`, chain the line into it — this
file is JSONC and yours; nothing here edits it for you.)

The `--device=/dev/net/tun` runArg is required by the fail-closed
[network egress jail](network-egress-jail.md); without it `claude`
refuses to launch.

## 3. (Optional) team configuration

`install.sh` stamps its bundled `.devcontainer/claude-sandbox.conf` to the
host-global `/etc/claude-sandbox.conf` (never read from the workspace —
see {ref}`the config invariant <adr-untrusted-workspace>`). To ship team
settings, write the conf yourself after the install (the wheel's copy is
read-only inside the uv cache); with a clone, write them into the clone
before running the installer:

```bash
cat > "$CSBX_DIR/.devcontainer/claude-sandbox.conf" <<'EOF'
# Team defaults — see reference/configuration for all keys.
allow-ip = 192.168.1.50    # lab device reachable through the jail
EOF
bash "$CSBX_DIR/install" --here
```

:::{admonition} postCreate runs unjailed
:class: warning

Everything in `postCreate.sh` runs as root at container-create time,
outside the sandbox. Review changes to it — and to the pin — with the
same care as a `Dockerfile` change.
:::

## See also

- [Use the container image](use-the-container-image.md) — the zero-wiring
  alternative when your project has no devcontainer.
- [Run without push access](run-without-push-access.md) — disable forge
  token binds for read/edit-only sessions.
- {ref}`adr-remove-promote` — why the sandbox is referenced at a pin
  instead of copied into your repo (the retired `just promote`).
