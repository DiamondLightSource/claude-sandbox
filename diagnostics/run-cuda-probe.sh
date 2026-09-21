#!/usr/bin/env bash
# Disposable-container payload for probe-proc-container.sh --cuda-app.
set -euo pipefail
if [ "${1:-}" = --inside ]; then
    source <(sed -n '/^check_07() {$/,/^}$/p' \
        /probe/.devcontainer/claude-sandbox/verify-sandbox-battery.sh)
    check_07
    echo 'PASS: PID namespace differs, procfs IDs agree, kernel controls protected'
    exec /probe/build/cuda-probe/cuda-smoke
fi
export CLAUDE_SHADOW_SOURCE_ONLY=1
source /probe/.devcontainer/claude-sandbox/claude-shadow
AGENT=claude AGENT_REAL=/bin/bash AGENT_BIND_BACK=0 AGENT_FILTER_CHROME=0
AGENT_INJECT=()
CLAUDE_SANDBOX_GPU=1
declare -a launch_argv=()
bwrap_argv_build launch_argv /probe /bin/bash /probe/diagnostics/run-cuda-probe.sh --inside
[ "${#launch_argv[@]}" -gt 0 ]
exec "${launch_argv[@]}"
