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
unset CLAUDE_SANDBOX_ALLOW_WRITE CLAUDE_SANDBOX_PASS_ENV CLAUDE_SANDBOX_NO_FORGE

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
    if CLAUDE_SANDBOX_LOCAL_MODEL_PORT=1920 local_model_enabled; then
        fail "$agent unexpectedly enables the local relay"
    else pass; fi
done
agent_profile pi
unset CLAUDE_SANDBOX_LOCAL_MODEL_PORT
if local_model_enabled; then fail 'relay enabled by default'; else pass; fi
printf 'local-model-port = 1920\n' > "$tmp/conf"
parse_config "$tmp/conf"
assert_parse relay-opt-in local_model_enabled
assert_parse valid-port validate_local_model_port
export CLAUDE_SANDBOX_LOCAL_MODEL_PORT=0
parse_config "$tmp/conf"
if local_model_enabled; then fail 'explicit zero did not override config'; else pass; fi
for port in -1 65536 '1920,fork' localhost:1920 01920 99999999999999999999; do
    if CLAUDE_SANDBOX_LOCAL_MODEL_PORT="$port" validate_local_model_port 2>/dev/null; then
        fail "accepted invalid relay port: $port"
    else pass; fi
done

cli="$REPO_ROOT/.devcontainer/claude-sandbox/claude-sandbox"
printf '{"providers":{"other":{"apiKey":"preserve"}}}\n' > "$HOME/.pi/agent/models.json"
bash "$cli" pi-local 'model with "quotes"' 32768 >/dev/null
jq_check config '.providers.lllm2.baseUrl == "http://127.0.0.1:1920/v1" and .providers.lllm2.models[0].contextWindow == 32768 and .providers.lllm2.models[0].maxTokens == 4096 and .providers.other.apiKey == "preserve"' "$HOME/.pi/agent/models.json"
assert_eq config-mode 600 "$(stat -c %a "$HOME/.pi/agent/models.json")"
bash "$cli" pi-local replacement 8192 8080 >/dev/null
jq_check config-replace '.providers.lllm2.models[0].id == "replacement" and .providers.lllm2.models[0].maxTokens == 2048 and .providers.other.apiKey == "preserve"' "$HOME/.pi/agent/models.json"
printf 'broken JSON\n' > "$HOME/.pi/agent/models.json"
if bash "$cli" pi-local test 32768 >/dev/null 2>&1; then fail 'overwrote invalid config'; else pass; fi
assert_eq invalid-config-preserved 'broken JSON' "$(cat "$HOME/.pi/agent/models.json")"
rm "$HOME/.pi/agent/models.json"
bash "$cli" pi-local first-run 32768 >/dev/null
jq_check first-run '.providers.lllm2.models[0].id == "first-run"' "$HOME/.pi/agent/models.json"

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
    source "$REPO_ROOT/.devcontainer/claude-sandbox/install.sh"
    mkdir -p "$tmp/archive/pi"
    printf '#!/bin/sh\necho fake-pi\n' > "$tmp/archive/pi/pi"
    chmod +x "$tmp/archive/pi/pi"
    printf asset > "$tmp/archive/pi/asset"
    tar -czf "$tmp/pi.tar.gz" -C "$tmp/archive" pi
    digest="$(sha256sum "$tmp/pi.tar.gz" | cut -d ' ' -f1)"
    printf '%s  pi-linux-x64.tar.gz\n%s  pi-linux-arm64.tar.gz\n' "$digest" "$digest" > "$tmp/checksums"
    curl() {
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
    printf corrupt > "$tmp/pi.tar.gz"
    PI_VERSION=invalid-download
    install_pi_binary 2>/dev/null
    test "$(cat "$PREFIX/usr/libexec/claude-sandbox/pi-dist/.sandbox-version")" = 0.85.1
) && pass || fail 'Pi release install or corrupt-download preservation failed'
finish pi.sh
