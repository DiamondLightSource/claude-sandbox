#!/usr/bin/env bash
# Live test of the checkout's launcher. Run from the OUTER container in this
# checkout: bash tests/proc_isolation.sh [--cuda]. Requires bwrap and gdb.
# Uses a disposable outer process; never signals or attaches to user processes.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = --inside ]; then
    outer_pid=$2
    cuda=$3
    # Exercise the actual battery implementation, not a copy of check 07.
    source <(sed -n '/^check_07() {$/,/^}$/p' \
        "$REPO_ROOT/.devcontainer/claude-sandbox/verify-sandbox-battery.sh")
    check_07
    echo 'PASS: different PID namespace, matching procfs IDs, protected controls'

    # Naming our own thread is safe and exercises CUDA's failing procfs path.
    printf 'proc-test\n' > "/proc/$$/task/$$/comm"
    [ "$(cat /proc/$$/comm)" = proc-test ]
    echo 'PASS: local thread comm is writable'

    # Do not confuse a reused sandbox PID with the outer fixture. Reserve a
    # margin for the few subprocesses below; fail rather than probe a collision.
    max_pid=0
    for entry in /proc/[0-9]*; do
        pid=${entry##*/}
        (( pid <= max_pid )) || max_pid=$pid
    done
    if (( outer_pid <= max_pid + 32 )); then
        echo 'FAIL: outer fixture PID overlaps the test PID range; rerun from the outer container' >&2
        exit 1
    fi
    [ ! -e "/proc/$outer_pid" ]
    if kill -0 "$outer_pid" 2>/dev/null; then
        echo 'FAIL: outer fixture is addressable by kill' >&2
        exit 1
    fi
    trace=$(gdb -nx -nh -q -batch -ex "attach $outer_pid" -ex detach 2>&1) || true
    if ! grep -q 'ptrace: No such process' <<< "$trace"; then
        printf 'FAIL: unexpected ptrace result:\n%s\n' "$trace" >&2
        exit 1
    fi
    echo 'PASS: outer fixture is invisible and inaccessible to kill and ptrace'
    if [ "$cuda" = 1 ]; then
        PATH=/usr/local/cuda/bin:$PATH bash "$REPO_ROOT/skills/cuda-development/scripts/cuda-smoke.sh"
    fi
    echo 'PASS: inner proc isolation checks complete'
    exit 0
fi

if [ "${IS_SANDBOX:-0}" = 1 ]; then
    echo 'Run this test in the outer container; it must create a new sandbox.' >&2
    exit 2
fi
cuda=0
case "${1:-}" in
    '') ;;
    --cuda) cuda=1 ;;
    *) echo 'Usage: bash tests/proc_isolation.sh [--cuda]' >&2; exit 2 ;;
esac
command -v bwrap >/dev/null
command -v gdb >/dev/null
# A newly started disposable container has low PIDs. Allocate our fixture
# above the inner test's PID range so numeric collisions cannot fake success.
while :; do
    sleep 300 &
    outer_pid=$!
    (( outer_pid < 128 )) || break
    kill "$outer_pid"
    wait "$outer_pid" 2>/dev/null || true
done
trap 'kill "$outer_pid" 2>/dev/null || true; wait "$outer_pid" 2>/dev/null || true' EXIT

export CLAUDE_SHADOW_SOURCE_ONLY=1
source "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
# Use the actual argv builder with bash as the test payload; retain all its
# mounts, environment scrubbing, capability drops and namespace flags.
AGENT=claude AGENT_REAL=/bin/bash AGENT_BIND_BACK=0 AGENT_FILTER_CHROME=0
AGENT_INJECT=()
CLAUDE_SANDBOX_GPU=$cuda
declare -a launch_argv=()
bwrap_argv_build launch_argv "$REPO_ROOT" /bin/bash \
    "$REPO_ROOT/tests/proc_isolation.sh" --inside "$outer_pid" "$cuda"
[ "${#launch_argv[@]}" -gt 0 ]
inner_rc=0
inner_output=$("${launch_argv[@]}") || inner_rc=$?
printf '%s\n' "$inner_output"
[ "$inner_rc" -eq 0 ] || exit "$inner_rc"
grep -qx 'PASS: inner proc isolation checks complete' <<< "$inner_output"
kill -0 "$outer_pid"
echo 'PASS: outer fixture survived the test'
