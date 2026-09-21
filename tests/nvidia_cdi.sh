#!/usr/bin/env bash
# Exercise host setup with fake toolkit commands; no GPU or host config writes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
helper="$HERE/../container/setup-nvidia-cdi.sh"
tmp="$(mktemp -d)"
register_cleanup "$tmp"
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/nvidia-smi" <<'SH'
#!/usr/bin/env bash
exit "${DRIVER_RC:-0}"
SH
cat > "$tmp/bin/nvidia-ctk" <<'SH'
#!/usr/bin/env bash
if [ "$*" = 'cdi generate --help' ]; then
    [ "${OLD_NVIDIA:-0}" = 1 ] || echo '  --disable-hook string'
    exit 0
fi
if [ "${OLD_NVIDIA:-0}" = 1 ]; then
    [ "$*" = 'cdi generate --class sandbox-gpu' ] || exit 2
else
    [ "$*" = 'cdi generate --class sandbox-gpu --disable-hook disable-device-node-modification' ] || exit 2
fi
printf '%s' "${SPEC:-}"
exit "${GENERATE_RC:-0}"
SH
cat > "$tmp/bin/podman" <<'SH'
#!/usr/bin/env bash
[ "$*" = --help ] || exit 2
if [ "${OLD_PODMAN:-0}" != 1 ]; then
    echo '  --cdi-spec-dir strings  Set the CDI spec directory path'
fi
exit 0
SH
chmod +x "$tmp/bin/"*
run() {
    env -u XDG_CONFIG_HOME -u IS_SANDBOX HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
        SPEC=$'cdiVersion: 0.3.0\nkind: nvidia.com/sandbox-gpu\ndevices: []\n' \
        "$@" bash "$helper" > "$tmp/out" 2> "$tmp/err"
}
if run OLD_PODMAN=1; then fail 'unsupported Podman accepted'; else pass; fi
assert_parse 'unsupported Podman creates no config' test ! -e "$tmp/home/.config"
assert_parse 'unsupported Podman explains limitation' grep -Fq 'lacks custom CDI directory support' "$tmp/err"
assert_parse 'initial setup' run
spec="$tmp/home/.config/cdi/claude-sandbox-nvidia.yaml"
conf="$tmp/home/.config/containers/containers.conf.d/90-claude-sandbox-nvidia-cdi.conf"
assert_parse 'spec written' test -s "$spec"
assert_parse 'user path configured' grep -Fq "$tmp/home/.config/cdi" "$conf"
echo 'unrelated configuration' > "$tmp/home/.config/containers/containers.conf"
assert_parse 'repeat setup' run
assert_parse 'older toolkit without params hook' run OLD_NVIDIA=1
assert_eq 'main config preserved' 'unrelated configuration' "$(cat "$tmp/home/.config/containers/containers.conf")"
cp "$spec" "$tmp/before-spec"
cp "$conf" "$tmp/before-conf"
if run OLD_PODMAN=1; then fail 'unsupported Podman accepted on rerun'; else pass; fi
assert_parse 'unsupported Podman preserves spec' cmp -s "$spec" "$tmp/before-spec"
assert_parse 'unsupported Podman preserves config' cmp -s "$conf" "$tmp/before-conf"
if run GENERATE_RC=1 SPEC=partial; then fail 'failed generation accepted'; else pass; fi
assert_parse 'failed generation preserves spec' cmp -s "$spec" "$tmp/before-spec"
assert_parse 'failed generation preserves config' cmp -s "$conf" "$tmp/before-conf"
if run SPEC=; then fail 'empty generation accepted'; else pass; fi
assert_parse 'empty generation preserves spec' cmp -s "$spec" "$tmp/before-spec"
if run DRIVER_RC=1; then fail 'broken driver accepted'; else pass; fi
assert_parse 'broken driver preserves spec' cmp -s "$spec" "$tmp/before-spec"
assert_parse 'XDG path with spaces' run XDG_CONFIG_HOME="$tmp/custom config"
assert_parse 'XDG spec written' test -s "$tmp/custom config/cdi/claude-sandbox-nvidia.yaml"
assert_eq 'spec carries marker' '# Managed by claude-sandbox setup-nvidia-cdi.sh' "$(head -n 1 "$spec")"
assert_parse 'spec keeps generated content' grep -Fq 'kind: nvidia.com/sandbox-gpu' "$spec"
if run SPEC=disable-device-node-modification; then fail 'retained params hook accepted'; else pass; fi
assert_parse 'retained hook preserves spec' cmp -s "$spec" "$tmp/before-spec"
echo '# user spec' > "$spec"
if run; then fail 'unmanaged spec overwritten'; else pass; fi
assert_eq 'unmanaged spec retained' '# user spec' "$(cat "$spec")"
assert_parse 'unmanaged spec preserves config' cmp -s "$conf" "$tmp/before-conf"
cp "$tmp/before-spec" "$spec"
echo '# user owned' > "$conf"
if run; then fail 'unmanaged config overwritten'; else pass; fi
assert_eq 'unmanaged config retained' '# user owned' "$(cat "$conf")"
if run IS_SANDBOX=1; then fail 'agent sandbox accepted'; else pass; fi
# System mode must work without custom Podman CDI paths and must not touch
# user config. Redirect the literal system destination into this fixture.
sed "s|cdi_dir=/etc/cdi|cdi_dir=$tmp/system-cdi|" "$helper" > "$tmp/system-helper"
cat > "$tmp/bin/id" <<'SH'
#!/usr/bin/env bash
echo "${TEST_UID:-0}"
SH
chmod +x "$tmp/bin/id"
system_run() {
    env -u IS_SANDBOX HOME="$tmp/system-home" PATH="$tmp/bin:$PATH" \
        OLD_PODMAN=1 SPEC=$'cdiVersion: 0.3.0\nkind: nvidia.com/sandbox-gpu\ndevices: []\n' \
        "$@" bash "$tmp/system-helper" --system > "$tmp/out" 2> "$tmp/err"
}
if system_run TEST_UID=1000; then fail 'non-root system setup accepted'; else pass; fi
assert_parse 'system setup supports old Podman' system_run
assert_parse 'system spec written' test -s "$tmp/system-cdi/claude-sandbox-nvidia.yaml"
assert_eq 'system spec readable by rootless Podman' 644 "$(stat -c %a "$tmp/system-cdi/claude-sandbox-nvidia.yaml")"
assert_parse 'system mode leaves user config alone' test ! -e "$tmp/system-home"
assert_parse 'repeat system setup' system_run
finish nvidia_cdi.sh
