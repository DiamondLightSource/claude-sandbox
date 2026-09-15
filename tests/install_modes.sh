#!/usr/bin/env bash
# Both installation modes ship the same files; runtime setup waits for startup
# during image builds. All file writes stay within the fixture directories.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
tmp="$(mktemp -d)"
register_cleanup "$tmp"
run_mode() (
    local mode="$1"; shift
    export CLAUDE_SANDBOX_SMOKE=1 INSTALL_PREFIX="$tmp/$mode"
    export INSTALL_USER_HOME="$tmp/$mode-home"
    mkdir -p "$INSTALL_USER_HOME/.claude"
    source "$REPO_ROOT/.devcontainer/claude-sandbox/install.sh"
    probe_userns_or_refuse() { echo probe >> "$tmp/$mode.calls"; }
    link_terminal_config() { echo share >> "$tmp/$mode.calls"; }
    main "$@" > "$tmp/$mode.log" 2>&1
)
run_mode container
run_mode image --image-build
assert_eq 'normal installation performs runtime setup' $'probe\nshare' "$(cat "$tmp/container.calls")"
if [ -e "$tmp/image.calls" ]; then
    fail 'image build performed runtime setup'
else
    pass
fi
assert_parse 'both modes install the same files' diff -r "$tmp/container" "$tmp/image"
assert_parse 'both modes seed the same user settings' diff -r "$tmp/container-home" "$tmp/image-home"
finish install_modes
