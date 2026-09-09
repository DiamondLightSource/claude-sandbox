#!/usr/bin/env bash
# Exercise the supervisor with a real Unix socket and a fake Codex process.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
MOCK_DIR="$(mktemp -d)"
register_cleanup "$MOCK_DIR"
export MOCK_DIR
cat >"$MOCK_DIR/codex" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$MOCK_DIR/args"
if [ "$1" = app-server ]; then
    if [ "${MOCK_FAIL:-0}" = 1 ]; then
        echo 'mock startup failure' >&2
        exit 3
    fi
    printf '%s\n' "${!#}" >"$MOCK_DIR/endpoint"
    exec node -e '
        const fs = require("fs"), net = require("net");
        const server = net.createServer().listen(process.argv[1].slice(7));
        process.on("SIGTERM", () => {
            fs.writeFileSync(process.env.MOCK_DIR + "/stopped", "yes");
            server.close(() => process.exit(0));
        });
    ' "${!#}"
fi
if [ "${!#}" = "$(cat "$MOCK_DIR/endpoint" 2>/dev/null)" ]; then
    endpoint="${!#}"
    test -S "${endpoint#unix://}" || exit 9
fi
if [ "${MOCK_WAIT:-0}" = 1 ]; then
    touch "$MOCK_DIR/client-ready"
    exec sleep 30
fi
exit 7
MOCK
chmod +x "$MOCK_DIR/codex"
run_launch() {
    bash -c 'source "$1"; shift; codex_launch "$@"' test \
        "$REPO_ROOT/.devcontainer/claude-sandbox/codex-launch" "$MOCK_DIR/codex" "$@"
}

run_launch -c 'model="test model"' agents --no-alt-screen
assert_eq client-exit 7 "$?"
expect_file "$MOCK_DIR/stopped" 'server was not stopped on client exit'
endpoint="$(cat "$MOCK_DIR/endpoint")"
assert_eq runtime-cleaned no "$(test -e "${endpoint#unix://}" && echo yes || echo no)"
assert_eq config-forwarded 2 "$(grep -cx 'model="test model"' "$MOCK_DIR/args")"
assert_eq local-connection 1 "$(grep -cx -- '--remote' "$MOCK_DIR/args")"

for args in 'agents --help' 'agents --remote=unix:///explicit' 'exec agents' '--version'; do
    : >"$MOCK_DIR/args"
    # Deliberate splitting of the fixed test cases above.
    # shellcheck disable=SC2086
    run_launch $args
    assert_eq passthrough-exit 7 "$?"
    assert_not_contains passthrough "$(cat "$MOCK_DIR/args")" app-server
done

: >"$MOCK_DIR/args"
MOCK_FAIL=1 run_launch agents >"$MOCK_DIR/failure" 2>&1
assert_eq startup-failure 1 "$?"
assert_contains startup-diagnostic "$(cat "$MOCK_DIR/failure")" 'mock startup failure'
assert_not_contains no-client-on-failure "$(cat "$MOCK_DIR/args")" agents

# Terminating the supervisor must stop both children and remove its socket.
: >"$MOCK_DIR/stopped"
MOCK_WAIT=1 bash -c 'source "$1"; shift; codex_launch "$@"' test \
    "$REPO_ROOT/.devcontainer/claude-sandbox/codex-launch" "$MOCK_DIR/codex" agents &
supervisor=$!
for attempt in {1..100}; do
    [ -f "$MOCK_DIR/client-ready" ] && break
    sleep 0.1
done
expect_file "$MOCK_DIR/client-ready"
kill -TERM "$supervisor"
wait "$supervisor"
assert_eq signal-exit 143 "$?"
assert_eq signal-server-stopped yes "$(cat "$MOCK_DIR/stopped")"
endpoint="$(cat "$MOCK_DIR/endpoint")"
assert_eq signal-runtime-cleaned no "$(test -e "${endpoint#unix://}" && echo yes || echo no)"
finish codex_launch.sh
