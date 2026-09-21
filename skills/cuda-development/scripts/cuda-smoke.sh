#!/bin/bash
# Compile and run a small CUDA program to prove the toolkit and the GPU work.
# Runs inside the sandbox or in the outer container. The build goes to a
# private temporary directory unless an output directory is given.
# Usage: cuda-smoke.sh [output-dir]
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
command -v nvcc >/dev/null 2>&1 || {
    echo 'cuda-smoke: nvcc is not on PATH; run install-cuda-toolkit.sh in the outer container.' >&2
    exit 1
}
if [ $# -gt 0 ]; then
    out=$1
    mkdir -p "$out"
else
    out=$(mktemp -d)
    trap 'rm -rf "$out"' EXIT
fi
# -arch=native builds for the GPUs present. Fall back to nvcc's default
# targets when no GPU is visible at compile time.
nvcc -O2 -arch=native -o "$out/cuda-smoke" "$here/cuda-smoke.cu" 2>/dev/null ||
    nvcc -O2 -o "$out/cuda-smoke" "$here/cuda-smoke.cu"
"$out/cuda-smoke"
