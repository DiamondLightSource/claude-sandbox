#!/usr/bin/env bash
# Entrypoint for the published claude-sandbox image (podman/docker run —
# no devcontainer). The image bakes a full install at build time
# (container/Dockerfile); this re-runs only the launch-time steps that
# depend on runtime mounts, then execs the requested command (default:
# claude, i.e. the shadow on $PATH).
#
# Sourcing install.sh (its source guard keeps main() from running) reuses
# the exact functions the devcontainer path runs via postCreate — one
# installer, one audit surface.
set -euo pipefail

# shellcheck disable=SC1091
source /opt/claude-sandbox/.devcontainer/claude-sandbox/install.sh

# Persist Claude login/memory/settings across containers when the
# launcher mounts a shared host dir at /user-terminal-config. No-op when
# absent — but then ~/.claude dies with the container, and the shadow's
# persistence check warns loudly about exactly that.
link_terminal_config
ensure_cred_dirs

# Re-stamp /etc/claude-sandbox.conf from the baked clone — unless the
# operator mounted their own conf over it (a read-only bind, which must
# win and would EROFS the copy anyway). A mounted conf still satisfies
# Invariant 4: it sits at /etc, read-only, outside the sandbox rw set.
if ! _is_mount /etc/claude-sandbox.conf; then
    install_conf
fi

# The image build skipped this probe deliberately (a builder that can
# nest namespaces proves nothing about this host — see the Dockerfile).
# Refuse HERE, at container start, if the runtime host cannot run
# unprivileged user namespaces: refusal-on-failure, never a sandbox that
# isn't one.
probe_userns_or_refuse

exec "$@"
