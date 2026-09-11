#!/usr/bin/env bash
# Real pasta/netns relay: two localhost ports, streaming, routes and cleanup.
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
server="" other="" second="" taken=""
trap 'stop_relay "$server" "$other" "$second" "$taken"; rm -rf "$tmp"' EXIT
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=31920
export CLAUDE_SANDBOX_LOCAL_PORTS=31922
export CLAUDE_SANDBOX_CALLBACK_PORTS=31955
unset CLAUDE_SANDBOX_ALLOW_IP
assert_eq relay-set $'31920\n31922' "$(local_ports)"
assert_eq callback-set 31955 "$(callback_ports)"
setsid socat TCP4-LISTEN:31920,bind=127.0.0.1,reuseaddr,fork EXEC:/bin/cat &
server=$!
setsid socat TCP4-LISTEN:31921,bind=127.0.0.1,reuseaddr,fork EXEC:/bin/cat &
other=$!
setsid socat TCP4-LISTEN:31922,bind=127.0.0.1,reuseaddr,fork "EXEC:/bin/echo second-port" &
second=$!
wait_for local_model_listening 31920
wait_for local_model_listening 31922
printf 'echo-test\n' | socat - TCP4:127.0.0.1:31921 > "$tmp/outside"
assert_eq host-other-listener echo-test "$(cat "$tmp/outside")"

cat > "$tmp/probe" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
echo "socket=$CLAUDE_JAIL_RELAY_DIR/31920.sock"
# More than one socket buffer, in both directions: covers streaming bodies.
expected="$(head -c 262144 /dev/zero | sha256sum)"
actual="$(head -c 262144 /dev/zero | socat - TCP4:127.0.0.1:31920 | sha256sum)"
[ "$expected" = "$actual" ]
# The local-port entry is relayed alongside the model port.
[ "$(socat - TCP4:127.0.0.1:31922 < /dev/null)" = second-port ]
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
# Loopback-only listeners, no relay listening on the pasta-facing interface.
ss -H -ltn 'sport = :31920' | grep -q '127.0.0.1:31920'
ss -H -ltn 'sport = :31922' | grep -q '127.0.0.1:31922'
[ "$(ss -H -ltn 'sport = :31922' | grep -vc '127.0.0.1:')" = 0 ]
# The callback relay's inner end waits on its private socket, holding no port.
[ -S "$CLAUDE_JAIL_RELAY_DIR/in-31955.sock" ]
[ -z "$(ss -H -ltn 'sport = :31955')" ]
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

# Callback relay (ADR 0021): a connection from the host loopback reaches a
# listener the agent opens on its own loopback. With nothing listening inside
# the browser is refused fast, a neighbouring port is not exposed, and every
# relay process and listener stops with the session.
cat > "$tmp/callback" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
echo "socket=$CLAUDE_JAIL_RELAY_DIR/in-31955.sock"
while [ ! -e "$1/go" ]; do sleep 0.05; done
socat TCP4-LISTEN:31955,bind=127.0.0.1,reuseaddr,fork "EXEC:/bin/echo callback-ok" &
listener=$!
trap 'kill "$listener" 2>/dev/null; exit 143' TERM INT
while ! ss -H -ltn 'sport = :31955' | grep -q '127.0.0.1:'; do sleep 0.05; done
echo LISTENING
sleep 60 & wait $!
PROBE
(netns_launch bash "$tmp/callback" "$tmp") > "$tmp/cb" 2>> "$tmp/log" &
launch=$!
wait_for grep -q '^socket=' "$tmp/cb"
wait_for port_in_use 31955
start=$SECONDS
out="$(timeout 5 socat - TCP4:127.0.0.1:31955 < /dev/null 2>/dev/null || true)"
assert_eq callback-no-listener-output '' "$out"
if [ $((SECONDS - start)) -lt 4 ]; then pass; else fail 'connection hung with nothing listening inside'; fi
touch "$tmp/go"
wait_for grep -q '^LISTENING' "$tmp/cb"
assert_eq callback-reaches-jail callback-ok "$(socat - TCP4:127.0.0.1:31955 < /dev/null)"
if port_in_use 31956; then fail 'neighbouring port exposed on the host loopback'; else pass; fi
kill -TERM "$launch"
rc=0
wait "$launch" || rc=$?
assert_eq callback-signal-status 143 "$rc"
if port_in_use 31955; then fail 'callback listener survived exit'; else pass; fi
socket="$(sed -n 's/^socket=//p' "$tmp/cb")"
if pgrep -f "[s]ocat.*$socket" >/dev/null; then fail 'callback relay processes survived exit'; else pass; fi

# A callback port already taken on the host fails soft: the session starts
# without that relay and says so.
setsid socat TCP4-LISTEN:31955,bind=127.0.0.1,reuseaddr,fork EXEC:/bin/cat &
taken=$!
wait_for port_in_use 31955
rc=0
(netns_launch bash -c 'echo BUSY_OK; exit 21') > "$tmp/busy" 2> "$tmp/busylog" || rc=$?
assert_eq busy-callback-port-fail-soft 21 "$rc"
assert_contains busy-callback-port-output "$(< "$tmp/busy")" BUSY_OK
assert_contains busy-callback-port-warning "$(< "$tmp/busylog")" 'callback-port 31955 is already in use'
stop_relay "$taken"
taken=""

# Interrupt a live launch and ensure both listeners and connections disappear.
(netns_launch bash -c 'echo "socket=$CLAUDE_JAIL_RELAY_DIR/31920.sock"; sleep 60') > "$tmp/signal" 2>> "$tmp/log" &
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
