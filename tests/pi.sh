#!/usr/bin/env bash
# Pi profile, config and install contracts; no network or model credentials.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHADOW="$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
source "$REPO_ROOT/tests/lib.sh"
export CLAUDE_SHADOW_SOURCE_ONLY=1
source "$REPO_ROOT/.devcontainer/claude-sandbox/claude-shadow"
tmp="$(mktemp -d)"
register_cleanup "$tmp"
export HOME="$tmp/home"
mkdir -p "$HOME/.pi/agent" "$HOME/.claude" "$HOME/.codex" "$HOME/.cache"
touch "$HOME/.claude.json"
unset CLAUDE_SANDBOX_ALLOW_WRITE CLAUDE_SANDBOX_PASS_ENV CLAUDE_SANDBOX_NO_FORGE CLAUDE_SANDBOX_LOCAL_PORTS CLAUDE_SANDBOX_CALLBACK_PORTS

assert_eq detect-pi pi "$(detect_agent /usr/local/bin/pi '')"
agent_profile pi
argv="$(bwrap_argv_build /repo "$AGENT_REAL" --provider openai --model example)"
assert_pair pi-state "$argv" --bind "$HOME/.pi"
assert_not_contains pi-isolation "$argv" "$HOME/.claude"
assert_not_contains pi-isolation "$argv" "$HOME/.claude.json"
assert_not_contains pi-isolation "$argv" "$HOME/.codex"
assert_not_contains pi-flags "$argv" --no-chrome
assert_pair pi-sentinel "$argv" IS_SANDBOX_AGENT pi
assert_contains pi-command "$argv" /usr/libexec/claude-sandbox/pi-run
assert_pair pi-provider "$argv" --provider openai
assert_pair pi-model "$argv" --model example
for agent in claude codex; do
    agent_profile "$agent"
    argv="$(bwrap_argv_build /repo "$AGENT_REAL")"
    assert_not_contains "$agent-isolation" "$argv" "$HOME/.pi"
    if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=1920 local_model_enabled; then pass
    else fail "$agent does not enable the local relay"; fi
    argv="$(CLAUDE_SANDBOX_LOCAL_MODEL_PORT=8082 bwrap_argv_build /repo "$AGENT_REAL")"
    assert_pair "$agent-relay-port" "$argv" CLAUDE_SANDBOX_LOCAL_MODEL_PORT 8082
done
agent_profile pi
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT
if local_model_enabled; then fail 'relay enabled without configuration'; else pass; fi
parse_config "$REPO_ROOT/.devcontainer/claude-sandbox.conf"
assert_eq shipped-relay-port 1920 "$CLAUDE_SANDBOX_LOCAL_MODEL_PORT"
argv="$(bwrap_argv_build /repo "$AGENT_REAL")"
assert_pair discovery-port "$argv" CLAUDE_SANDBOX_LOCAL_MODEL_PORT 1920
printf 'local-model-port = 1920\n' > "$tmp/conf"
parse_config "$tmp/conf"
assert_parse relay-configured local_model_enabled
assert_parse valid-port validate_local_model_port
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0
parse_config "$tmp/conf"
if local_model_enabled; then fail 'explicit zero did not override config'; else pass; fi
for port in -1 65536 '1920,fork' localhost:1920 01920 99999999999999999999; do
    if CLAUDE_SANDBOX_LOCAL_MODEL_PORT="$port" validate_local_model_port 2>/dev/null; then
        fail "accepted invalid relay port: $port"
    else pass; fi
    if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0 CLAUDE_SANDBOX_LOCAL_PORTS="8082 $port" validate_local_model_port 2>/dev/null; then
        fail "accepted invalid local-port entry: $port"
    else pass; fi
done
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT

# Relay set (ADR 0020): model port plus local-port entries, merged with the
# environment, deduplicated, and still relayed when the model port is 0.
printf 'local-model-port = 1920\nlocal-port = 8082\nlocal-port = 1920\nlocal-port = 9000\n' > "$tmp/conf"
parse_config "$tmp/conf"
assert_eq relay-set $'1920\n8082\n9000' "$(local_ports)"
assert_parse relay-set-valid validate_local_model_port
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT CLAUDE_SANDBOX_LOCAL_PORTS
export CLAUDE_SANDBOX_LOCAL_PORTS='8082,9000 8082'
parse_config "$tmp/conf"
assert_eq relay-env-merge $'1920\n8082\n9000' "$(local_ports)"
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT CLAUDE_SANDBOX_LOCAL_PORTS
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0
parse_config "$tmp/conf"
assert_eq relay-without-model-port $'8082\n1920\n9000' "$(local_ports)"
assert_parse relay-without-model-port-enabled local_model_enabled
argv="$(bwrap_argv_build /repo "$AGENT_REAL")"
assert_not_contains no-discovery-without-model-port "$argv" CLAUDE_SANDBOX_LOCAL_MODEL_PORT
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT CLAUDE_SANDBOX_LOCAL_PORTS
if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0 local_model_enabled; then fail 'relay enabled with nothing configured'; else pass; fi

# Callback set (ADR 0021): the inbound relay. Shipped default is Pi's Claude
# login port; entries merge with the environment, deduplicate, validate like
# local-port, and may never overlap the outbound set.
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT CLAUDE_SANDBOX_LOCAL_PORTS CLAUDE_SANDBOX_CALLBACK_PORTS
parse_config "$REPO_ROOT/.devcontainer/claude-sandbox.conf"
assert_eq shipped-callback-port 53692 "$(callback_ports)"
assert_parse shipped-callback-valid validate_callback_ports
assert_parse shipped-callback-enabled callback_enabled
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT CLAUDE_SANDBOX_LOCAL_PORTS CLAUDE_SANDBOX_CALLBACK_PORTS
if callback_enabled; then fail 'callback relay enabled without configuration'; else pass; fi
printf 'callback-port = 53692\ncallback-port = 1455\ncallback-port = 53692\n' > "$tmp/conf"
export CLAUDE_SANDBOX_CALLBACK_PORTS='1456,1455'
parse_config "$tmp/conf"
assert_eq callback-set $'1456\n1455\n53692' "$(callback_ports)"
assert_parse callback-set-valid validate_callback_ports
unset CLAUDE_SANDBOX_CALLBACK_PORTS
for port in -1 65536 '1455,fork' localhost:1455 01455 99999999999999999999; do
    if CLAUDE_SANDBOX_CALLBACK_PORTS="$port" validate_callback_ports 2>/dev/null; then
        fail "accepted invalid callback-port entry: $port"
    else pass; fi
done
if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=1920 CLAUDE_SANDBOX_CALLBACK_PORTS=1920 validate_callback_ports 2>/dev/null; then
    fail 'accepted the model port as a callback-port'
else pass; fi
if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0 CLAUDE_SANDBOX_LOCAL_PORTS=8082 CLAUDE_SANDBOX_CALLBACK_PORTS='53692 8082' validate_callback_ports 2>/dev/null; then
    fail 'accepted a local-port as a callback-port'
else pass; fi

cli="$REPO_ROOT/.devcontainer/claude-sandbox/claude-sandbox"
printf '{"providers":{"other":{"apiKey":"preserve"}}}\n' > "$HOME/.pi/agent/models.json"
bash "$cli" pi-local 'model with "quotes"' 32768 >/dev/null
jq_check config '.providers.lllm2.baseUrl == "http://127.0.0.1:1920/v1" and .providers.lllm2.models[0].contextWindow == 32768 and .providers.lllm2.models[0].maxTokens == 8192 and .providers.other.apiKey == "preserve"' "$HOME/.pi/agent/models.json"
assert_eq config-mode 600 "$(stat -c %a "$HOME/.pi/agent/models.json")"
bash "$cli" pi-local replacement 8192 8080 >/dev/null
jq_check config-replace '.providers.lllm2.models[0].id == "replacement" and .providers.lllm2.models[0].maxTokens == 2048 and .providers.other.apiKey == "preserve"' "$HOME/.pi/agent/models.json"
bash "$cli" pi-local large-context 262144 >/dev/null
jq_check config-output-cap '.providers.lllm2.models[0].contextWindow == 262144 and .providers.lllm2.models[0].maxTokens == 32000' "$HOME/.pi/agent/models.json"
printf 'broken JSON\n' > "$HOME/.pi/agent/models.json"
if bash "$cli" pi-local test 32768 >/dev/null 2>&1; then fail 'overwrote invalid config'; else pass; fi
assert_eq invalid-config-preserved 'broken JSON' "$(cat "$HOME/.pi/agent/models.json")"
rm "$HOME/.pi/agent/models.json"
bash "$cli" pi-local first-run 32768 >/dev/null
jq_check first-run '.providers.lllm2.models[0].id == "first-run"' "$HOME/.pi/agent/models.json"

# Deterministic discovery responses; real HTTP and startup are covered by pi_e2e.
curl() {
    printf '%s\n' "${@: -1}" >> "$PI_TEST_HTTP/calls"
    case "${@: -1}" in
        */v1/models) cat "$PI_TEST_HTTP/models" ;;
        */props) cat "$PI_TEST_HTTP/props" ;;
        *) return 1 ;;
    esac
}
export -f curl
export PI_TEST_HTTP="$tmp"
printf '{"data":[{"id":"discovered"}]}\n' > "$tmp/models"
printf '{"default_generation_settings":{"n_ctx":65536}}\n' > "$tmp/props"
bash "$cli" pi-local >/dev/null
jq_check discovered '.providers.lllm2.models[0].id == "discovered" and .providers.lllm2.models[0].contextWindow == 65536' "$HOME/.pi/agent/models.json"
# Preserve user credentials/compatibility overrides and unrelated providers.
jq '.providers.lllm2.apiKey = "custom" | .providers.lllm2.compat.supportsDeveloperRole = true | .providers.other = {apiKey:"keep"}' "$HOME/.pi/agent/models.json" > "$tmp/custom"
cp "$tmp/custom" "$HOME/.pi/agent/models.json"
printf '{"data":[{"id":"changed"}]}\n' > "$tmp/models"
bash "$cli" pi-local --port 8080 >/dev/null
jq_check rediscovered '.providers.lllm2.models | length == 1' "$HOME/.pi/agent/models.json"
jq_check preserved '.providers.lllm2.models[0].id == "changed" and .providers.lllm2.baseUrl == "http://127.0.0.1:8080/v1" and .providers.lllm2.apiKey == "custom" and .providers.lllm2.compat.supportsDeveloperRole and .providers.other.apiKey == "keep"' "$HOME/.pi/agent/models.json"
assert_contains discovery-custom-port "$(cat "$tmp/calls")" http://127.0.0.1:8080/props
cp "$HOME/.pi/agent/models.json" "$tmp/before"
for response in '{"data":[]}' '{"data":[{"id":"a"},{"id":"b"}]}' 'broken JSON'; do
    printf '%s\n' "$response" > "$tmp/models"
    if bash "$cli" pi-local >/dev/null 2>&1; then fail 'accepted unavailable/ambiguous model'; else pass; fi
    assert_parse discovery-failure-preserves cmp -s "$tmp/before" "$HOME/.pi/agent/models.json"
done
printf '{"data":[{"id":"changed"}]}\n' > "$tmp/models"
for response in '{}' '{"default_generation_settings":{"n_ctx":12.5}}' '{"default_generation_settings":{"n_ctx":0}}'; do
    printf '%s\n' "$response" > "$tmp/props"
    if bash "$cli" pi-local >/dev/null 2>&1; then fail 'accepted invalid context'; else pass; fi
    assert_parse context-failure-preserves cmp -s "$tmp/before" "$HOME/.pi/agent/models.json"
done
unset -f curl

rc=0
env -u IS_SANDBOX -u IS_SANDBOX_AGENT bash "$REPO_ROOT/.devcontainer/claude-sandbox/pi-run" >/dev/null 2>&1 || rc=$?
assert_eq unwrapped-pi-blocked 2 "$rc"
rc=0
IS_SANDBOX=1 IS_SANDBOX_AGENT=claude bash "$REPO_ROOT/.devcontainer/claude-sandbox/pi-run" >/dev/null 2>&1 || rc=$?
assert_eq sibling-session-blocked 2 "$rc"

# The opt-out still installs the shadow and launch guard, and shared state is
# wired independently of whether the real binary was downloaded.
(
    export CLAUDE_SANDBOX_SMOKE=1 WITH_PI=0 INSTALL_PREFIX="$tmp/install" INSTALL_USER_HOME="$HOME"
    source "$REPO_ROOT/.devcontainer/claude-sandbox/install.sh"
    main >/dev/null 2>&1
    mkdir -p "$tmp/shared"
    CLAUDE_SHARED_CONFIG="$tmp/shared" link_terminal_config
)
assert_parse pi-shadow cmp -s "$SHADOW" "$tmp/install/usr/local/bin/pi"
expect_file "$tmp/install/usr/libexec/claude-sandbox/pi-run"
assert_eq pi-shared "$tmp/shared/.pi" "$(readlink "$HOME/.pi")"

# Exercise the real release installer with a tiny local tarball and transport
# stub: valid checksums install assets; corrupt downloads preserve the old tree.
(
    export CLAUDE_SANDBOX_SMOKE=0 WITH_PI=1 INSTALL_PREFIX="$tmp/release-install"
    unset PI_VERSION
    source "$REPO_ROOT/.devcontainer/claude-sandbox/install.sh"
    mkdir -p "$tmp/archive/pi"
    printf '#!/bin/sh\necho fake-pi\n' > "$tmp/archive/pi/pi"
    chmod +x "$tmp/archive/pi/pi"
    printf asset > "$tmp/archive/pi/asset"
    tar -czf "$tmp/pi.tar.gz" -C "$tmp/archive" pi
    digest="$(sha256sum "$tmp/pi.tar.gz" | cut -d ' ' -f1)"
    printf '%s  pi-linux-x64.tar.gz\n%s  pi-linux-arm64.tar.gz\n' "$digest" "$digest" > "$tmp/checksums"
    curl() {
        printf '%s\n' "$*" >> "$tmp/curl-calls"
        if [ "$1" = -fsSLI ]; then
            printf 'https://github.com/earendil-works/pi/releases/tag/v0.85.1'
            return 0
        fi
        local url="${4}" output="${6}"
        case "$url" in
            */SHA256SUMS) cp "$tmp/checksums" "$output" ;;
            *) cp "$tmp/pi.tar.gz" "$output" ;;
        esac
    }
    install_pi_binary
    test -x "$PREFIX/usr/libexec/claude-sandbox/pi-dist/pi"
    test -f "$PREFIX/usr/libexec/claude-sandbox/pi-dist/asset"
    test ! -e "$HOME/.local/bin/pi"
    test "$(cat "$PREFIX/usr/libexec/claude-sandbox/pi-dist/.sandbox-version")" = 0.85.1
    test "$(wc -l < "$tmp/curl-calls")" -eq 3
    # Re-running in an existing container must not fetch/check for upgrades.
    install_pi_binary
    test "$(wc -l < "$tmp/curl-calls")" -eq 3
    # An explicit pin bypasses latest lookup and can deliberately change version.
    PI_VERSION=0.85.2
    install_pi_binary
    test "$(wc -l < "$tmp/curl-calls")" -eq 5
    test "$(cat "$PREFIX/usr/libexec/claude-sandbox/pi-dist/.sandbox-version")" = 0.85.2
    printf corrupt > "$tmp/pi.tar.gz"
    PI_VERSION=0.85.3
    install_pi_binary 2>/dev/null
    test "$(cat "$PREFIX/usr/libexec/claude-sandbox/pi-dist/.sandbox-version")" = 0.85.2
) && pass || fail 'Pi release install or corrupt-download preservation failed'
finish pi.sh
