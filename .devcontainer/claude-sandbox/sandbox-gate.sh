#!/usr/bin/env bash
# Managed UserPromptSubmit hook for Claude and Codex. Exit 2 blocks an
# unwrapped prompt; sandbox-verify.sh supplies the deeper session checks.
# Installed under /usr/libexec, read-only inside the sandbox.
#
# The operator can allow unwrapped sessions with the root-owned /etc flag.
# Keep this opt-out outside user settings: the agent can persist environment
# values there. Claude Code Web skips the gate.
set -uo pipefail

# Fixed operator flag; tests pass a fixture path to gate_allows directly.
ALLOW_UNWRAPPED_FLAG="/etc/claude-code/allow-unwrapped"

# gate_allows FLAG: succeed (return 0) when the prompt should be let through —
# running on Claude Code Web, inside the bwrap shadow, or the operator's
# root-owned escape-hatch flag is present. FLAG is a parameter so the test seam
# is an argument, not an environment variable a confined Claude could forge.
gate_allows() {
    local flag="$1"
    [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && return 0
    [ "${IS_SANDBOX:-}" = "1" ]            && return 0
    [ -f "$flag" ]                         && return 0
    return 1
}

# agent_label ARGS...: read an optional `--agent NAME` out of the hook's argv
# and render the name for the block message. Parsed HERE, inside the function,
# not at file scope: tests source this file to unit-test gate_allows(), and a
# top-level read of "$@" would see the sourcing script's arguments.
# Presentation only — the gate's DECISION never depends on it.
agent_label() {
    local a
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --agent) shift; case "${1:-}" in codex) a=Codex ;; *) a=Claude ;; esac ;;
        esac
        shift || break
    done
    printf '%s\n' "${a:-Claude}"
}

gate_main() {
    local label; label="$(agent_label "$@")"
    local binary; if [ "$label" = "Codex" ]; then binary="codex"; else binary="claude"; fi

    # UserPromptSubmit delivers JSON on stdin; drain it when piped so the
    # writer never blocks. We don't need its contents.
    [ -t 0 ] || cat >/dev/null 2>&1 || true

    gate_allows "$ALLOW_UNWRAPPED_FLAG" && exit 0

    # Exit 2 blocks the prompt and surfaces stderr to the user. Both agents
    # honour that contract.
    echo "BLOCKED: $label is running OUTSIDE the claude-sandbox bwrap shadow (IS_SANDBOX unset) — host credentials are NOT isolated. An agent self-update can re-create ~/.local/bin/$binary and bypass the shadow; re-run claude-sandbox/install, then relaunch $binary. (To work unwrapped anyway, the host operator can: sudo touch /etc/claude-code/allow-unwrapped.)" >&2
    exit 2
}

# Run the gate only when EXECUTED directly, not when a test SOURCES this file to
# unit-test gate_allows(). The guard is BASH_SOURCE-vs-$0 — intrinsic to how the
# script is invoked, NOT an environment variable — so a confined Claude cannot
# set anything to skip the gate.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    gate_main "$@"
fi
