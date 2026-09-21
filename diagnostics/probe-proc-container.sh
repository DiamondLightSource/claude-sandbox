#!/usr/bin/env bash
# Run on the HOST: bash diagnostics/probe-proc-container.sh CONTAINER_NAME [--params-hook | --cuda-app]
# Compare fresh-proc mounts in disposable rootless Podman containers using
# the existing container's image. No project/config volumes, no image pulls,
# no changes to the existing container. --cuda-app mounts this checkout read-only
# and runs its precompiled vector-add app under the modified launcher.
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] ||
    { [ "$#" = 2 ] && [ "$2" != --params-hook ] && [ "$2" != --cuda-app ]; }; then
    echo "Usage: $0 CONTAINER_NAME [--params-hook | --cuda-app]" >&2
    exit 2
fi
command -v podman >/dev/null
[ "$(podman info --format '{{.Host.Security.Rootless}}')" = true ] || {
    echo 'This probe is for rootless Podman only.' >&2
    exit 2
}
image=$(podman container inspect --format '{{.Image}}' "$1")
cdi_options=()
probe() {
    local name=$1 rc=0
    shift
    printf '\n%s\n' "$name"
    podman "${cdi_options[@]}" run --rm --pull=never --network=none --security-opt label=disable \
        "$@" --entrypoint /bin/bash "$image" -c '
            bwrap --ro-bind / / --unshare-user-try --unshare-pid \
                --proc /proc --cap-drop ALL -- /bin/bash -c '\''
                    printf "Fresh proc mounted; shell PID=%s\n" "$$"
                    while read -r key value; do
                        if [ "$key" = Pid: ]; then
                            printf "procfs PID=%s\n" "$value"
                            [ "$value" = "$$" ] || exit 1
                            break
                        fi
                    done < /proc/self/status
                '\''
        ' || rc=$?
    printf 'Exit status: %s\n' "$rc"
}
if [ "${2:-}" = --params-hook ] || [ "${2:-}" = --cuda-app ]; then
    command -v nvidia-ctk >/dev/null
    cdi_tmp=$(mktemp -d)
    trap 'rm -f -- "$cdi_tmp/probe.yaml"; rmdir -- "$cdi_tmp"' EXIT
    # Unique device class avoids conflicts with installed CDI specifications.
    # The same generated spec is tested with and without just the params hook.
    cdi_options=( --cdi-spec-dir "$cdi_tmp" )
    if [ "$2" = --params-hook ]; then
    nvidia-ctk cdi generate --class proc-probe --output "$cdi_tmp/probe.yaml"
    if ! grep -q disable-device-node-modification "$cdi_tmp/probe.yaml"; then
        echo 'Generated spec has no params hook; cannot perform this A/B test.' >&2
        exit 1
    fi
    probe '4a. Generated CDI, params hook enabled' --security-opt 'unmask=/proc/*' \
        --device nvidia.com/proc-probe=all
    fi
    nvidia-ctk cdi generate --class proc-probe \
        --disable-hook disable-device-node-modification --output "$cdi_tmp/probe.yaml"
    if grep -q disable-device-node-modification "$cdi_tmp/probe.yaml"; then
        echo 'Params hook was not removed; refusing a misleading comparison.' >&2
        exit 1
    fi
    if [ "$2" = --cuda-app ]; then
        repo=$(cd "$(dirname "$0")/.." && pwd)
        [ -x "$repo/build/cuda-probe/cuda-smoke" ] || {
            echo 'Missing precompiled build/cuda-probe/cuda-smoke.' >&2
            exit 1
        }
        podman "${cdi_options[@]}" run --rm --pull=never --network=none \
            --security-opt label=disable --security-opt 'unmask=/proc/*' \
            --device nvidia.com/proc-probe=all \
            -v "$repo:/probe:ro" -w /probe --entrypoint /bin/bash "$image" \
            /probe/diagnostics/run-cuda-probe.sh
        exit 0
    fi
    probe '4b. Generated CDI, params hook disabled' --security-opt 'unmask=/proc/*' \
        --device nvidia.com/proc-probe=all
    exit 0
fi
probe '1. Default proc masks, no GPU'
probe '2. Unmasked proc, no GPU' --security-opt 'unmask=/proc/*'
probe '3. Unmasked proc, NVIDIA CDI' --security-opt 'unmask=/proc/*' \
    --device nvidia.com/gpu=all
