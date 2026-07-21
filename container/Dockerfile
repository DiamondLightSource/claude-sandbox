# Published claude-sandbox image — sandboxed Claude Code for hosts WITHOUT
# a devcontainer workflow (rootless podman/docker + the container/
# claude-container launcher is all a host needs). Built and pushed to
# ghcr.io/gilesknap/claude-sandbox by .github/workflows/container.yml.
#
# Built FROM the same DLS base as the repo's devcontainer Dockerfile and
# installed by the same install.sh the devcontainer runs via postCreate —
# the image is a third consumer of the one installer (dogfood ≈ guest ≈
# image), not a new install path to audit.
#
# Build context is the REPO ROOT (workflow passes `file:
# container/Dockerfile`), so the whole clone is available to COPY.
FROM ghcr.io/diamondlightsource/ubuntu-devcontainer:noble

COPY . /opt/claude-sandbox
WORKDIR /opt/claude-sandbox

# Run install.sh's main() sequence MINUS probe_userns_or_refuse, via the
# same source-guard seam promote.sh uses. The userns probe is skipped
# HERE only because a build-time probe proves the BUILDER can nest
# namespaces, not the host that will run the image (and BuildKit
# confinement varies by builder); container/entrypoint.sh re-runs the
# probe at container start, where refusal-on-failure actually protects
# someone. KEEP THIS LIST IN STEP WITH main() IN install.sh.
RUN bash -c ' \
    set -euo pipefail; \
    source .devcontainer/claude-sandbox/install.sh; \
    probe_or_refuse; \
    install_file "$SCRIPT_DIR/claude-shadow" "$(prefixed /usr/local/bin/claude)"; \
    apt_install; \
    link_terminal_config; \
    install_claude_binary; \
    ensure_cred_dirs; \
    install_conf; \
    install_guard_scripts; \
    wire_managed_settings; \
    wire_gate_flag; \
    wire_user_statusline; \
    rm -rf /var/lib/apt/lists/*'

# The entrypoint re-runs the launch-time installer steps that depend on
# runtime mounts (shared ~/.claude, /etc conf), probes userns, then execs
# the command — default: claude, i.e. the shadow on $PATH.
ENTRYPOINT ["/opt/claude-sandbox/container/entrypoint.sh"]
CMD ["claude"]
