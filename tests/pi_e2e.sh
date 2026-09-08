#!/usr/bin/env bash
# Run ONLY in a disposable container with the sandbox and Pi already installed.
# The Container workflow runs this against the actual built image on both archs.
set -euo pipefail
test -x /usr/libexec/claude-sandbox/pi-dist/pi
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
server=""
cleanup() {
    if [ -n "$server" ]; then kill -TERM -- "-$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
    rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p /work "$HOME/.pi/agent"
git config --global user.name 'Pi integration test'
git config --global user.email 'pi-test@example.invalid'
touch /tmp/outer-only
cp "$REPO_ROOT/tests/fixtures/pi-model-server.sh" "$tmp/http"
setsid socat TCP4-LISTEN:1920,bind=127.0.0.1,reuseaddr,fork "EXEC:bash $tmp/http" &
server=$!
for _ in {1..100}; do
    if ss -H -ltn 'sport = :1920' | grep -q '127.0.0.1:'; then break; fi
    sleep 0.05
done
claude-sandbox pi-local local-test 32768 >/dev/null
cd /work
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=1920
# Avoid catalog/version traffic in this test. The production profile leaves
# catalog refresh enabled so cloud logins can discover their available models.
export PI_OFFLINE=1 CLAUDE_SANDBOX_PASS_ENV=PI_OFFLINE
timeout 60 pi --provider lllm2 --model local-test --no-session \
    --no-extensions --no-skills --no-prompt-templates --no-themes \
    -p 'Run the sandbox checks using your bash tool.' > "$tmp/output" 2>&1
cat "$tmp/output"
cat /work/battery
test "$(cat /work/tool-proof)" = PI_TOOL_OK
grep -q LOCAL_MODEL_OK "$tmp/output"
echo 'pi_e2e.sh: real Pi streamed a tool call through the jailed localhost relay; all sandbox checks passed'
