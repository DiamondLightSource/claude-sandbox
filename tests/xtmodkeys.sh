#!/usr/bin/env bash
# Unit test for the XTMODKEYS output filter in claude-shadow (pty_launch).
# The modifyOtherKeys enable sequence ESC[>4;2m that every agent writes at
# startup is drawn as visible junk by the terminals on RHEL 8/9 desktops,
# so the shadow strips CSI > Ps ; Ps m from the agent's output by default.
#
# Run via `bash tests/xtmodkeys.sh`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHADOW="$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
source "$REPO_ROOT/tests/lib.sh"
export CLAUDE_SHADOW_SOURCE_ONLY=1
# shellcheck source=../.devcontainer/claude-sandbox/claude-shadow
source "$SHADOW"

# Filter helper: feed raw bytes, return printf-escaped output.
filter() { printf "$1" | xtmodkeys_filter | od -An -c | tr -s ' \n' ' '; }
# Reference: what a byte string looks like after od.
odc() { printf "$1" | od -An -c | tr -s ' \n' ' '; }

# 1. enable + reset stripped, everything else byte-identical.
out="$(filter 'A\033[>4;2mB\033[>4;0mC\033[31mred\033[0m\r\n')"
assert_eq "strips XTMODKEYS, keeps SGR and CR/LF" "$(odc 'ABC\033[31mred\033[0m\r\n')" "$out"

# 2. A sequence split across two writes is still caught (chunk boundary).
out="$( ( printf 'A\033[>4'; sleep 0.2; printf ';2mB\n' ) | xtmodkeys_filter | od -An -c | tr -s ' \n' ' ')"
assert_eq "sequence split across chunks" "$(odc 'AB\n')" "$out"

# 3. A bare ESC or unrelated CSI at end of stream is flushed, not lost.
out="$(filter 'X\033')"
assert_eq "trailing ESC flushed at EOF" "$(odc 'X\033')" "$out"
out="$(filter '\033[?u\033[>1u\033[?1004h')"
assert_eq "kitty and focus sequences pass through" "$(odc '\033[?u\033[>1u\033[?1004h')" "$out"

# 4. Opt-out: env var, conf key, or no node.
( unset CLAUDE_SANDBOX_KEEP_XTMODKEYS; xtmodkeys_kept ) && fail "filter on by default" || pass
( CLAUDE_SANDBOX_KEEP_XTMODKEYS=1 xtmodkeys_kept ) && pass || fail "CLAUDE_SANDBOX_KEEP_XTMODKEYS=1 opts out"
( unset CLAUDE_SANDBOX_KEEP_XTMODKEYS; PATH=/nonexistent xtmodkeys_kept ) && pass || fail "no node => sequences kept"
conf="$(mktemp)"; register_cleanup "$conf"
echo 'keep-xtmodkeys' > "$conf"
( unset CLAUDE_SANDBOX_KEEP_XTMODKEYS; parse_config "$conf"; [ "${CLAUDE_SANDBOX_KEEP_XTMODKEYS:-}" = 1 ] ) \
    && pass || fail "conf key keep-xtmodkeys sets CLAUDE_SANDBOX_KEEP_XTMODKEYS=1"

# 5. pty_launch end to end: the agent sees a tty, output is filtered, and the
#    agent's exit status survives the pipe.
out="$( ( unset CLAUDE_SANDBOX_KEEP_XTMODKEYS; pty_launch 'tty >/dev/null && printf "T\033[>4;2mU\n"; exit 7' ) </dev/null 2>&1 | tr -d "\r"; echo "rc=${PIPESTATUS[0]}" )"
assert_contains "pty_launch filtered output" "$out" "TU"
assert_not_contains "pty_launch no XTMODKEYS" "$out" $'T\033[>4;2mU'
assert_contains "pty_launch keeps agent exit status" "$out" "rc=7"
out="$( ( CLAUDE_SANDBOX_KEEP_XTMODKEYS=1 pty_launch 'printf "T\033[>4;2mU\n"' ) </dev/null 2>&1 | tr -d "\r" )"
assert_contains "opt-out passes XTMODKEYS through" "$out" $'T\033[>4;2mU'

finish xtmodkeys.sh
