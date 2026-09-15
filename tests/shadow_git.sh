#!/usr/bin/env bash
# Render real Git identity values through the shadow without a live sandbox.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
export CLAUDE_SHADOW_SOURCE_ONLY=1
source "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
tmp="$(mktemp -d)"
register_cleanup "$tmp"
git init -q "$tmp/repo"
cd "$tmp/repo"
export CLAUDE_SANDBOX_GITCONFIG_PATH="$tmp/curated.gitconfig"
for name in 'Sam "SJ" Jones' 'Sam #1; Jones' 'Sam\Jones' $'Sam\n[core]\n    hooksPath = /unexpected'; do
    email='sam@example.invalid'
    git config --local user.name "$name"
    git config --local user.email "$email"
    render_gitconfig
    assert_eq 'identity name round trip' "$name" "$(git config --file "$CLAUDE_SANDBOX_GITCONFIG_PATH" user.name)"
    assert_eq 'identity email round trip' "$email" "$(git config --file "$CLAUDE_SANDBOX_GITCONFIG_PATH" user.email)"
    if git config --file "$CLAUDE_SANDBOX_GITCONFIG_PATH" --get core.hooksPath; then
        fail 'identity became a Git directive'
    else
        pass
    fi
done
assert_eq 'curated config readable by agents' 644 "$(stat -c %a "$CLAUDE_SANDBOX_GITCONFIG_PATH")"
finish shadow_git
