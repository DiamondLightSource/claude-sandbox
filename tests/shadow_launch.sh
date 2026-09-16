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

# Preserve argument boundaries through the builder and the terminal's shell.
tmp="$(mktemp -d)"
register_cleanup "$tmp"
cat > "$tmp/bwrap" <<'FAKE'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$ARGV_CAPTURE"
FAKE
chmod +x "$tmp/bwrap"
export ARGV_CAPTURE="$tmp/actual"
export PATH="$tmp:$PATH"
export MULTILINE_VALUE=$'first value\nsecond value\n'
export CLAUDE_SANDBOX_PASS_ENV=MULTILINE_VALUE
prompt=$'first line\nsecond line\n'
for agent in claude codex pi; do
    agent_profile "$agent"
    bwrap_argv_build built "$tmp" "$AGENT_REAL" "$prompt" '' 'literal $(false)'
    assert_eq "$agent multiline prompt" "$prompt" "${built[-3]}"
    assert_eq "$agent empty argument" '' "${built[-2]}"
    found=0
    for ((i=0; i < ${#built[@]} - 2; i++)); do
        if [ "${built[i]}" = --setenv ] && [ "${built[i+1]}" = MULTILINE_VALUE ]; then
            assert_eq "$agent multiline environment" "$MULTILINE_VALUE" "${built[i+2]}"
            found=1
        fi
    done
    assert_eq "$agent environment forwarded" 1 "$found"
    printf '%s\0' "${built[@]:1}" > "$tmp/expected"
    ( CLAUDE_SANDBOX_EGRESS_JAIL=0 sandbox_launch "${built[@]}" ) </dev/null >/dev/null 2>&1
    assert_parse "$agent terminal argument round trip" cmp "$tmp/expected" "$ARGV_CAPTURE"
done
# A warning before launch sets the flag, and the pause never blocks without a
# terminal. Output goes to a file, so stderr is not a tty here.
LAUNCH_WARNED=0
launch_warn "test warning" 2>"$tmp/warn"
assert_eq "launch_warn sets the flag" 1 "$LAUNCH_WARNED"
assert_eq "launch_warn prefixes the message" "claude-sandbox: test warning" "$(cat "$tmp/warn")"
rc=0
timeout 5 bash -c 'source "$1"; LAUNCH_WARNED=1; pause_after_warnings' _ "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow" </dev/null >"$tmp/pause" 2>&1 || rc=$?
assert_eq "pause does not block without a terminal" 0 "$rc"
assert_eq "pause prints nothing without a terminal" "" "$(cat "$tmp/pause")"

# On a terminal the pause waits for one key, then the launch continues.
out="$(printf x | timeout 10 script -qec "bash -c 'source \"$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow\"; launch_warn hello; pause_after_warnings; echo LAUNCHED'" /dev/null 2>&1 | tr -d '\r')" || true
assert_contains "pause prompts on a terminal" "$out" "Press any key to continue, Ctrl-C to cancel."
assert_contains "launch continues after a key" "$out" "LAUNCHED"

finish shadow_launch
