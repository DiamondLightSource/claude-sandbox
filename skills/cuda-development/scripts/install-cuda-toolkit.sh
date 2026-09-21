#!/bin/bash
# Run as root in the OUTER container. Installs the NVIDIA CUDA toolkit from
# NVIDIA's apt repository for Ubuntu or Debian on x86_64 or arm64 servers.
# The host's container runtime supplies the GPU driver, so this script pins
# every driver package out of apt and never installs one.
# Shipped path: /usr/libexec/claude-sandbox/skills/cuda-development/scripts/
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: install-cuda-toolkit.sh [--minimal | --full] [--no-smoke] [CUDA_VERSION]

  CUDA_VERSION  major.minor toolkit to install, for example 12.8. The default
                is the newest release that the host driver supports.
  --minimal     nvcc and the CUDA runtime only (about 0.5 GiB).
  --full        the whole cuda-toolkit, with Nsight GUIs and a Java runtime
                (about 7 GiB).
  (default)     nvcc, runtime, CUDA math libraries, NVML headers and the
                command-line debug and profiling tools (about 5 GiB).
  --no-smoke    skip the GPU smoke test at the end.
EOF
    exit 2
}

profile=dev smoke=1 want=''
for arg in "$@"; do
    case $arg in
        --minimal) profile=minimal ;;
        --full) profile=full ;;
        --no-smoke) smoke=0 ;;
        [0-9]*.[0-9]*) want=$arg ;;
        *) usage ;;
    esac
done
[[ -z $want || $want =~ ^[0-9]+\.[0-9]+$ ]] || usage

die() { echo "install-cuda-toolkit: $*" >&2; exit 1; }

if [ "${IS_SANDBOX:-}" = 1 ]; then
    die 'run this installer outside the sandbox, in claude-sandbox shell.'
fi
[ "$(id -u)" = 0 ] || die 'run this installer as root in the container.'
command -v apt-get >/dev/null 2>&1 || die 'needs apt-get (Ubuntu or Debian).'

# The driver comes from the host through the container runtime (CDI or the
# NVIDIA runtime hook). Without it the toolkit is useless.
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 || die \
    'no working nvidia-smi. Start the container with GPU access, for example
    claude-sandbox --recreate --gpu, then run nvidia-smi here to check it.'
# The header line reads "... CUDA Version: 13.2 ..." and names the newest
# toolkit the driver can run without the forward-compatibility package.
driver_cuda=$(nvidia-smi | sed -n 's/.*CUDA Version: *\([0-9]*\.[0-9]*\).*/\1/p' | head -n1)
[ -n "$driver_cuda" ] || die 'cannot read the CUDA version from nvidia-smi.'

. /etc/os-release
case ${ID:-} in
    ubuntu) repo=ubuntu${VERSION_ID//./} ;;
    debian) repo=debian${VERSION_ID%%.*} ;;
    *) die "unsupported distribution '${ID:-unknown}'; NVIDIA publishes apt repositories for Ubuntu and Debian." ;;
esac
case $(dpkg --print-architecture) in
    amd64) narch=x86_64 ;;
    # sbsa is the arm64 server repository. Jetson boards use JetPack instead.
    arm64) narch=sbsa ;;
    *) die "unsupported architecture $(dpkg --print-architecture)." ;;
esac
base=https://developer.download.nvidia.com/compute/cuda/repos/$repo/$narch

# A half-installed driver package, for example from Ubuntu's own
# nvidia-cuda-toolkit, makes apt refuse every later install.
apt-get check >/dev/null 2>&1 || die 'apt reports broken packages. Fix them,
    or start a clean container with claude-sandbox --recreate --gpu.'

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
fi
curl -fsI "$base/cuda-keyring_1.1-1_all.deb" >/dev/null ||
    die "NVIDIA has no CUDA repository at $base."

# Driver packages in the container would replace or clash with the files the
# runtime mounts from the host, and dpkg then leaves apt broken. Ubuntu's
# nvidia-cuda-toolkit depends on one, so it is blocked too.
cat > /etc/apt/preferences.d/claude-sandbox-no-nvidia-driver <<'EOF'
Explanation: claude-sandbox: the host supplies the NVIDIA driver; never install it here.
Package: libnvidia-* nvidia-driver* nvidia-dkms-* nvidia-kernel-* nvidia-utils-* nvidia-compute-utils-* nvidia-firmware-* xserver-xorg-video-nvidia-* cuda-drivers* libcuda1 libnvcuvid1 nvidia-cuda-toolkit
Pin: version *
Pin-Priority: -1
EOF

if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/cuda-keyring.deb" "$base/cuda-keyring_1.1-1_all.deb"
    dpkg -i "$tmp/cuda-keyring.deb"
fi
apt-get update

# version_le A B: true when major.minor A is not newer than B.
version_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }

mapfile -t available < <(apt-cache pkgnames cuda-nvcc- |
    sed -n 's/^cuda-nvcc-\([0-9]*\)-\([0-9]*\)$/\1.\2/p' | sort -V)
[ "${#available[@]}" -gt 0 ] || die "no cuda-nvcc packages found in $base."
if [ -n "$want" ]; then
    printf '%s\n' "${available[@]}" | grep -qx "${want//./\\.}" ||
        die "CUDA $want is not in the repository. Available: ${available[*]}"
    version_le "$want" "$driver_cuda" || die "CUDA $want needs a newer driver;
    the host driver supports CUDA $driver_cuda or older."
else
    for v in "${available[@]}"; do
        if version_le "$v" "$driver_cuda"; then want=$v; fi
    done
    [ -n "$want" ] || die "the host driver supports CUDA $driver_cuda, older
    than every toolkit in the repository (${available[*]})."
fi

v=${want//./-}
case $profile in
    minimal) pkgs=(cuda-compiler-"$v" cuda-cudart-dev-"$v") ;;
    dev) pkgs=(cuda-compiler-"$v" cuda-cudart-dev-"$v" cuda-libraries-dev-"$v"
               cuda-command-line-tools-"$v" cuda-nvml-dev-"$v") ;;
    full) pkgs=(cuda-toolkit-"$v") ;;
esac
echo "Installing CUDA $want ($profile) for a driver that supports CUDA $driver_cuda"
apt-get install -y --no-install-recommends "${pkgs[@]}"
apt-get clean

prefix=/usr/local/cuda-$want
[ -x "$prefix/bin/nvcc" ] || die "nvcc is missing from $prefix/bin after the install."
# The packages register /usr/local/cuda as an alternative. Select this
# version explicitly when several are installed.
update-alternatives --set cuda "$prefix" >/dev/null 2>&1 || true
[ -e /usr/local/cuda ] || ln -s "$prefix" /usr/local/cuda

# The agent's shell does not read /etc/profile.d, so link the tools onto the
# default PATH. The links go through /usr/local/cuda to follow the selected
# version. Remove links that an older toolkit left dangling.
for link in /usr/local/bin/*; do
    if [ -L "$link" ] && [[ $(readlink "$link") == /usr/local/cuda/bin/* ]] &&
        [ ! -e "$link" ]; then
        rm -f "$link"
    fi
done
for tool in /usr/local/cuda/bin/*; do
    link=/usr/local/bin/${tool##*/}
    if [ ! -e "$link" ] && [ ! -L "$link" ]; then
        ln -s "/usr/local/cuda/bin/${tool##*/}" "$link"
    elif [ "$(readlink "$link")" != "/usr/local/cuda/bin/${tool##*/}" ]; then
        echo "Left $link alone: it is not a CUDA toolkit link." >&2
    fi
done
cat > /etc/profile.d/claude-sandbox-cuda.sh <<'EOF'
export CUDA_HOME=/usr/local/cuda
EOF
echo /usr/local/cuda/lib64 > /etc/ld.so.conf.d/claude-sandbox-cuda.conf
ldconfig

echo "Installed CUDA $want at $prefix; nvcc is $(command -v nvcc)."
if [ "$smoke" = 1 ]; then
    bash "$(dirname "$(readlink -f "$0")")/cuda-smoke.sh"
fi
echo 'Run the cuda-development smoke script inside the sandbox next.'
