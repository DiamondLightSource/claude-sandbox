# Two consumers, one file, one base:
#
#   developer      — the repo's own devcontainer (devcontainer.json builds
#                    `target: developer`). Intentionally a bare FROM: the
#                    DLS ubuntu-devcontainer image already ships the
#                    dev-tooling baseline (git, curl, ca-certificates, jq,
#                    sudo) the bash installer needs; everything else
#                    (bubblewrap, nodejs, gh) is apt-installed by
#                    `.devcontainer/claude-sandbox/install.sh` at
#                    postCreate.
#   claude-sandbox — the PUBLISHED image (ghcr.io/diamondlightsource/claude-sandbox,
#                    built by .github/workflows/container.yml): sandboxed
#                    Claude Code for hosts WITHOUT a devcontainer workflow;
#                    rootless podman/docker + the container/claude-container
#                    launcher is all a host needs. It builds FROM the
#                    developer stage and is installed by the same install.sh
#                    the devcontainer runs — dogfood ≈ guest ≈ image, one
#                    installer, one audit surface.
FROM ghcr.io/diamondlightsource/ubuntu-devcontainer:noble AS developer

FROM developer AS claude-sandbox

# The version of container/claude-container this image was built and
# tested with. CI derives it from the script's VERSION line (single
# source of truth) and passes it in; the launcher reads the label from
# the pulled image to warn when the user's copy is out of date.
ARG LAUNCHER_VERSION=""
LABEL io.diamondlightsource.claude-sandbox.launcher-version="${LAUNCHER_VERSION}"

# What `claude-sandbox version` reports inside the image. .dockerignore
# excludes .git, so stamp_version can't run `git describe` at build —
# CI passes the ref name (tag on releases, `main` otherwise) instead.
ARG CLAUDE_SANDBOX_VERSION=""

# Whether to fetch OpenAI's Codex CLI at build time (install.sh's own
# WITH_CODEX knob, exposed here). The codex SHADOW and its managed guard
# are installed either way — Invariant 1 says the shadow must own the name
# on $PATH regardless — this only controls the best-effort curl fetch of
# the real binary. Default on, matching install.sh; set to 0 to build an
# image that never reaches chatgpt.com (e.g. an offline/air-gapped build,
# or to keep the published image's Codex support pinned to a build done
# with known network access rather than whichever runner happened to build
# a given tag).
ARG WITH_CODEX=1

COPY . /opt/claude-sandbox
WORKDIR /opt/claude-sandbox

# Run install.sh's main() sequence MINUS two build-time-inappropriate
# steps, via install.sh's source-guard seam:
#   - probe_userns_or_refuse: a build-time probe proves the BUILDER can
#     nest namespaces, not the host that will run the image (and BuildKit
#     confinement varies by builder).
#   - link_terminal_config: the base image ships an EMPTY stub
#     /user-terminal-config dir, so wiring at build symlinks
#     ~/.claude.json to a zero-length file — which the official Claude
#     installer's setup step then rejects as corrupted JSON (build
#     failure). The share only exists for real as a runtime mount.
# container/entrypoint.sh runs both at container start, where they act
# on the actual host / actual mounts. KEEP THIS LIST IN STEP WITH main()
# IN install.sh.
RUN bash -c ' \
    set -euo pipefail; \
    export WITH_CODEX="'"$WITH_CODEX"'"; \
    source .devcontainer/claude-sandbox/install.sh; \
    probe_or_refuse; \
    install_file "$SCRIPT_DIR/claude-shadow" "$(prefixed /usr/local/bin/claude)"; \
    install_file "$SCRIPT_DIR/claude-shadow" "$(prefixed /usr/local/bin/codex)"; \
    install_file "$SCRIPT_DIR/claude-sandbox" "$(prefixed /usr/local/bin/claude-sandbox)"; \
    apt_install; \
    install_claude_binary; \
    install_codex_binary; \
    ensure_cred_dirs; \
    install_conf; \
    stamp_version; \
    install_guard_scripts; \
    wire_managed_settings; \
    wire_codex_managed; \
    wire_gate_flag; \
    wire_user_statusline; \
    rm -rf /var/lib/apt/lists/*'

# No USER directive, deliberately (the DLS base-image pattern): the
# supported runtime is a ROOTLESS engine, where in-container root maps
# to the unprivileged invoking host user via user namespaces — root in
# here is not root on the host. Under a ROOTFUL engine Claude really
# would run as host UID 0; that path is unsupported (and the egress
# jail's pasta attach is denied there anyway — see the how-to's
# troubleshooting note).
#
# The entrypoint re-runs the launch-time installer steps that depend on
# runtime mounts (shared ~/.claude and ~/.codex, /etc conf), probes userns,
# then execs the command — default: claude, i.e. the shadow on $PATH. Run the
# image with `codex` as the command to get a sandboxed Codex session from the
# same image (the same shadow, dispatching on argv[0]).
ENTRYPOINT ["/opt/claude-sandbox/container/entrypoint.sh"]
CMD ["claude"]
