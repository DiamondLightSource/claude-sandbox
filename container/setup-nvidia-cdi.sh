#!/usr/bin/env bash
# Run on the Linux HOST. Default: user config; --system: root-owned /etc/cdi
# for older Podman. No package installation or container launch.
set -euo pipefail

die() { echo "setup-nvidia-cdi: $*" >&2; exit 1; }
system=0
case "${1:-}" in
    --system) system=1; shift ;;
    -h|--help)
        echo 'Usage: bash setup-nvidia-cdi.sh [--system]'
        echo 'Default: user CDI config, requiring Podman --cdi-spec-dir support.'
        echo '--system: run as root to write /etc/cdi (also works with Podman 4.7).'
        echo 'Requires working host drivers and nvidia-ctk CDI generation.'
        exit 0 ;;
esac
[ "$#" = 0 ] || die 'takes no arguments (use --help)'
[ "${IS_SANDBOX:-0}" != 1 ] || die 'run this on the host, outside the agent sandbox'
for tool in nvidia-smi nvidia-ctk; do
    command -v "$tool" >/dev/null || die "missing $tool; ask your host administrator to provide it"
done
# The config key existed before Podman actually used it when injecting CDI
# devices. Upstream PR 25717 wired it up along with --cdi-spec-dir. Probe the
# capability rather than a version number so distro backports can work too.
if [ "$system" = 1 ]; then
    [ "$(id -u)" = 0 ] || die '--system must run as root on the host'
else
    podman_help="$(podman --help)" || die 'cannot read Podman capabilities'
    if [[ "$podman_help" != *--cdi-spec-dir* ]]; then
        die 'this Podman lacks custom CDI directory support. Ask an administrator to run this helper with --system. No configuration was changed.'
    fi
fi
nvidia-smi -L || die 'host GPU access failed; resolve this before configuring CDI'
cdi_help=$(nvidia-ctk cdi generate --help) || die 'cannot read NVIDIA CDI generation capabilities'
generate_args=(cdi generate --class sandbox-gpu)
if [[ "$cdi_help" == *--disable-hook* ]]; then
    generate_args+=( --disable-hook disable-device-node-modification )
fi

conf=''
conf_dir=''
if [ "$system" = 1 ]; then
    cdi_dir=/etc/cdi
else
    config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
    # TOML literal strings preserve spaces and backslashes without interpolation.
    case "$config_root" in
        /*) ;;
        *) die 'HOME/XDG_CONFIG_HOME must select an absolute configuration path' ;;
    esac
    case "$config_root" in
        *"'"*|*$'\n'*|*$'\r'*) die 'configuration path cannot contain apostrophes or newlines' ;;
    esac
    cdi_dir="$config_root/cdi"
    conf_dir="$config_root/containers/containers.conf.d"
    conf="$conf_dir/90-claude-sandbox-nvidia-cdi.conf"
fi
spec="$cdi_dir/claude-sandbox-nvidia.yaml"
marker='# Managed by claude-sandbox setup-nvidia-cdi.sh'
# Both files may already hold a user's own configuration, for example a spec
# generated with custom nvidia-ctk options. Replace only what carries the marker.
for managed in "$conf" "$spec"; do
    [ -n "$managed" ] || continue
    if [ -e "$managed" ] || [ -L "$managed" ]; then
        [ ! -L "$managed" ] && [ -f "$managed" ] && [ "$(head -n 1 "$managed")" = "$marker" ] \
            || die "refusing to replace an unmanaged file: $managed"
    fi
done

mkdir -p "$cdi_dir"
[ -z "$conf_dir" ] || mkdir -p "$conf_dir"
spec_tmp=''
conf_tmp=''
trap 'if [ -n "$spec_tmp" ]; then rm -f -- "$spec_tmp"; fi; if [ -n "$conf_tmp" ]; then rm -f -- "$conf_tmp"; fi' EXIT
spec_tmp="$(mktemp "$cdi_dir/.nvidia.XXXXXX")"
# Keep the standard GPU class intact for other containers. This class omits
# the hook that overlays /proc/driver/nvidia/params: that covered procfs file
# prevents the agent's fresh procfs mount in its nested user namespace.
# Older toolkits predate this hook and have no --disable-hook option. Inspect
# the generated spec in either case and refuse one that retains the hook.
# Generate before replacing anything so a failure keeps working files intact.
# The marker is a YAML comment, so CDI parsers ignore it.
{ echo "$marker"; nvidia-ctk "${generate_args[@]}"; } > "$spec_tmp" \
    || die 'CDI generation failed; previous configuration kept'
tail -n +2 "$spec_tmp" | grep -q . || die 'CDI generation returned an empty specification; previous configuration kept'
if grep -q disable-device-node-modification "$spec_tmp"; then
    die 'CDI generation retained the params hook; previous configuration kept'
fi
# Rootless Podman must be able to read a root-installed system spec.
chmod 0644 "$spec_tmp"
if [ -n "$conf" ]; then
    conf_tmp="$(mktemp "$conf_dir/.nvidia.XXXXXX")"
    printf "%s\n[engine]\ncdi_spec_dirs = ['/etc/cdi', '/var/run/cdi', '%s']\n" \
        "$marker" "$cdi_dir" > "$conf_tmp"
fi
mv -f -- "$spec_tmp" "$spec"
spec_tmp=''
if [ -n "$conf" ]; then
    mv -f -- "$conf_tmp" "$conf"
    conf_tmp=''
    printf 'Podman configuration: %s\n' "$conf"
fi
printf 'CDI specification: %s\n' "$spec"
echo 'Ready to try: claude-sandbox --gpu shell'
echo 'Re-run this helper after host NVIDIA driver or GPU configuration changes.'
