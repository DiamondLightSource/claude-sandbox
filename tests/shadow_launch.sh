#!/usr/bin/env bash
# Exercise the real terminal wrapper without requiring nested namespaces.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
export CLAUDE_SHADOW_SOURCE_ONLY=1
source "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"

# Only namespace setup is substituted; both paths run the real script(1).
netns_launch() { "$@"; }
for jail in 0 1; do
    for expected in 0 42; do
        rc=0
        ( CLAUDE_SANDBOX_EGRESS_JAIL="$jail" sandbox_launch bash -c "exit $expected" ) </dev/null >/dev/null 2>&1 || rc=$?
        assert_eq "terminal exit status (jail=$jail)" "$expected" "$rc"
    done
done
finish shadow_launch
