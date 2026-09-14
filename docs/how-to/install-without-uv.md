# Install without uv

The normal way to install the sandbox into a devcontainer is the PyPI
wheel:

```bash
uvx claude-sandbox install
```

If the container image has no `uv`, clone this repository and run the
same installer from the clone. The wheel ships that installer unchanged,
so the two routes install exactly the same thing.

## One-off install

In a terminal inside the container (as `root`):

```bash
cd /tmp && rm -rf claude-sandbox && git clone https://github.com/DiamondLightSource/claude-sandbox && claude-sandbox/install
```

This installs the **newest release**, not the tip of `main`: the clone
lands on the default branch, and `install` then checks out the newest
release tag before installing it — the same revision `claude-sandbox
update` would give you. It prints which one it picked. To install a
specific release instead:

```bash
claude-sandbox/install --release 4.0.0
```

The clone is **disposable** — nothing depends on it after install (the
`claude-sandbox` helper CLI lands on your PATH, and `claude-sandbox update`
fetches its own fresh clone when you upgrade), so `/tmp` is exactly the
right place: it evaporates with the container.

The installer is idempotent. After a devcontainer rebuild, run the
one-liner again, or wire it into `postCreate` as below.

## Re-seeding the statusline

Your statusline script is seeded once and then left alone, so edits you
make to it survive re-runs. To have a re-run pull the clone's current
statusline instead, run `STATUS=1 <clone>/install --here` (`--here`
because the clone is now checked out at the release it installed, and
re-running without it would ask to move to a newer one).

## Pinned install in a team devcontainer

The `uvx claude-sandbox==4.0.0 install` line in
[Sandbox a team devcontainer](sandbox-a-team-devcontainer.md) becomes a
clone at the pin:

```bash
#!/usr/bin/env bash
# Bring up claude-sandbox at a pinned revision. Bumping the pin is a
# deliberate, reviewable act — like any dependency upgrade.
set -euo pipefail

CSBX_REPO="https://github.com/DiamondLightSource/claude-sandbox.git"
CSBX_PIN="4.0.0"           # a release tag, or a full commit SHA
CSBX_DIR="$HOME/claude-sandbox"

if [ ! -d "$CSBX_DIR" ]; then
    git clone --filter=blob:none "$CSBX_REPO" "$CSBX_DIR"
fi
git -C "$CSBX_DIR" fetch --quiet origin "$CSBX_PIN" || true
git -C "$CSBX_DIR" checkout --quiet "$CSBX_PIN"

bash "$CSBX_DIR/install" --here
```

`--here` is what makes the pin authoritative. Run with no flag, `install`
resolves and installs the **newest release tag** instead — right for a
one-off clone, wrong here, where you have just checked out the revision
you intend to run. It will not do that silently: on a clone that is
pinned, on a non-default branch, or locally modified, the flagless form
refuses and tells you to pass `--here`. Passing it makes the intent
explicit and keeps the pin the only thing that decides your version.

The clone lives in the container filesystem, so a rebuild re-creates it at
the pinned revision; the installer is idempotent, so re-runs are cheap and
never re-download Claude.

The rest of that how-to (the `devcontainer.json` wiring, the tun device,
verification) applies unchanged.
