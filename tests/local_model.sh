#!/usr/bin/env bash
# Real pasta/netns relay: one localhost port, streaming, routes and cleanup.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
export CLAUDE_SHADOW_SOURCE_ONLY=1
source "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
if ! unshare -rn true 2>/dev/null || [ ! -e /dev/net/tun ]; then
    echo 'SKIP: local_model.sh requires user/net namespaces and /dev/net/tun'
    [ "${EGRESS_JAIL_REQUIRE:-0}" != 1 ]
    exit $?
fi
for dep in socat pasta ss curl; do command -v "$dep" >/dev/null; done
tmp="$(mktemp -d)"
server="" other=""
trap 'stop_relay "$server"; stop_relay "$other"; rm -rf "$tmp"' EXIT
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=31920
unset CLAUDE_SANDBOX_ALLOW_IP
setsid socat TCP4-LISTEN:31920,bind=127.0.0.1,reuseaddr,fork EXEC:/bin/cat &
server=$!
setsid socat TCP4-LISTEN:31921,bind=127.0.0.1,reuseaddr,fork EXEC:/bin/cat &
other=$!
wait_for local_model_listening
printf 'echo-test\n' | socat - TCP4:127.0.0.1:31921 > "$tmp/outside"
assert_eq host-other-listener echo-test "$(cat "$tmp/outside")"

cat > "$tmp/probe" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
echo "socket=$CLAUDE_JAIL_MODEL_SOCKET"
# More than one socket buffer, in both directions: covers streaming bodies.
expected="$(head -c 262144 /dev/zero | sha256sum)"
actual="$(head -c 262144 /dev/zero | socat - TCP4:127.0.0.1:31920 | sha256sum)"
[ "$expected" = "$actual" ]
if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/31921' 2>/dev/null; then
    echo 'Unexpected reach to a different host-loopback port' >&2
    exit 1
fi
gw="$(ip route show default | awk '{print $3; exit}')"
if timeout 2 bash -c 'exec 3<>/dev/tcp/$1/31921' _ "$gw" 2>/dev/null; then
    echo 'Gateway unexpectedly maps to host loopback' >&2
    exit 1
fi
ip route show | grep -q '^blackhole 10.0.0.0/8'
ip route show | grep -q '^blackhole 192.168.0.0/16'
ip route show | grep -q '^blackhole 100.64.0.0/10'
# Loopback-only listener, no relay listening on the pasta-facing interface.
ss -H -ltn 'sport = :31920' | grep -q '127.0.0.1:31920'
echo RELAY_OK
exit 17
PROBE
# The relay is agent-independent (ADR 0020): prove it for Pi and for Claude.
for agent in pi claude; do
    agent_profile "$agent"
    rc=0
    (netns_launch bash "$tmp/probe") > "$tmp/result" 2> "$tmp/log" || rc=$?
    cat "$tmp/log"
    assert_eq "$agent-exit-status" 17 "$rc"
    assert_contains "$agent-relay" "$(< "$tmp/result")" RELAY_OK
    socket="$(sed -n 's/^socket=//p' "$tmp/result")"
    if [ -n "$socket" ] && [ ! -e "${socket%/*}" ]; then pass; else fail "$agent relay directory survived exit"; fi
    if [ -n "$socket" ] && pgrep -f "[s]ocat.*$socket" >/dev/null; then fail "$agent relay processes survived exit"; else pass; fi
done

# Missing model server must not prevent starting Pi for a cloud provider.
stop_relay "$server"
server=""
rc=0
(netns_launch bash -c 'echo CLOUD_OK; exit 19') > "$tmp/cloud" 2>> "$tmp/log" || rc=$?
assert_eq offline-local-server 19 "$rc"
assert_contains cloud "$(< "$tmp/cloud")" CLOUD_OK

# Interrupt a live launch and ensure both listeners and connections disappear.
(netns_launch bash -c 'echo "socket=$CLAUDE_JAIL_MODEL_SOCKET"; sleep 60') > "$tmp/signal" 2>> "$tmp/log" &
launch=$!
wait_for grep -q '^socket=' "$tmp/signal"
kill -TERM "$launch"
rc=0
wait "$launch" || rc=$?
assert_eq signal-status 143 "$rc"
socket="$(sed -n 's/^socket=//p' "$tmp/signal")"
if [ ! -e "${socket%/*}" ]; then pass; else fail 'relay directory survived signal'; fi
if pgrep -f "[s]ocat.*$socket" >/dev/null; then fail 'relay processes survived signal'; else pass; fi
finish local_model.sh
