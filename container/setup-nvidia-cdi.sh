#!/usr/bin/env bash
# Run on the Linux HOST as the user who runs rootless Podman. No sudo,
# package installation or container launch. Re-run after driver updates.
set -euo pipefail

die() { echo "setup-nvidia-cdi: $*" >&2; exit 1; }
case "${1:-}" in
    -h|--help)
        echo 'Usage: bash setup-nvidia-cdi.sh'
        echo 'Generate user NVIDIA CDI configuration for rootless Podman (no sudo).'
        echo 'Requires working host NVIDIA drivers, nvidia-ctk and Podman with --cdi-spec-dir support.'
        exit 0 ;;
esac
[ "$#" = 0 ] || die 'takes no arguments (use --help)'
[ "${IS_SANDBOX:-0}" != 1 ] || die 'run this on the host, outside the agent sandbox'
for tool in nvidia-smi nvidia-ctk podman; do
    command -v "$tool" >/dev/null || die "missing $tool; ask your host administrator to provide it"
done
# The config key existed before Podman actually used it when injecting CDI
# devices. Upstream PR 25717 wired it up along with --cdi-spec-dir. Probe the
# capability rather than a version number so distro backports can work too.
podman_help="$(podman --help)" || die 'cannot read Podman capabilities'
if [[ "$podman_help" != *--cdi-spec-dir* ]]; then
    die 'this Podman lacks custom CDI directory support (including upstream 4.9). Ask an administrator to generate /etc/cdi/nvidia.yaml, or use a newer Podman with --cdi-spec-dir support. No configuration was changed.'
fi
nvidia-smi -L || die 'host GPU access failed; resolve this before configuring CDI'

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
spec="$cdi_dir/nvidia.yaml"
marker='# Managed by claude-sandbox setup-nvidia-cdi.sh'
# Both files may already hold a user's own configuration, for example a spec
# generated with custom nvidia-ctk options. Replace only what carries the marker.
for managed in "$conf" "$spec"; do
    if [ -e "$managed" ] || [ -L "$managed" ]; then
        [ ! -L "$managed" ] && [ -f "$managed" ] && [ "$(head -n 1 "$managed")" = "$marker" ] \
            || die "refusing to replace an unmanaged file: $managed"
    fi
done

mkdir -p "$cdi_dir" "$conf_dir"
spec_tmp=''
conf_tmp=''
trap 'if [ -n "$spec_tmp" ]; then rm -f -- "$spec_tmp"; fi; if [ -n "$conf_tmp" ]; then rm -f -- "$conf_tmp"; fi' EXIT
spec_tmp="$(mktemp "$cdi_dir/.nvidia.XXXXXX")"
# stdout works with older toolkits, including 1.13.5 (which has no cdi list).
# Generate before replacing anything so a failure keeps working files intact.
# The marker is a YAML comment, so CDI parsers ignore it.
{ echo "$marker"; nvidia-ctk cdi generate; } > "$spec_tmp" \
    || die 'CDI generation failed; previous configuration kept'
tail -n +2 "$spec_tmp" | grep -q . || die 'CDI generation returned an empty specification; previous configuration kept'
conf_tmp="$(mktemp "$conf_dir/.nvidia.XXXXXX")"
printf "%s\n[engine]\ncdi_spec_dirs = ['/etc/cdi', '/var/run/cdi', '%s']\n" \
    "$marker" "$cdi_dir" > "$conf_tmp"
mv -f -- "$spec_tmp" "$spec"
spec_tmp=''
mv -f -- "$conf_tmp" "$conf"
conf_tmp=''
printf 'CDI specification: %s\nPodman configuration: %s\n' "$spec" "$conf"
echo 'Ready to try: claude-sandbox --gpu shell'
echo 'Re-run this helper after host NVIDIA driver or GPU configuration changes.'
