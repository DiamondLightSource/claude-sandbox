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
[ "$*" = 'cdi generate' ] || exit 2
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
        SPEC=$'cdiVersion: 0.3.0\nkind: nvidia.com/gpu\ndevices: []\n' \
        "$@" bash "$helper" > "$tmp/out" 2> "$tmp/err"
}
if run OLD_PODMAN=1; then fail 'unsupported Podman accepted'; else pass; fi
assert_parse 'unsupported Podman creates no config' test ! -e "$tmp/home/.config"
assert_parse 'unsupported Podman explains limitation' grep -Fq 'lacks custom CDI directory support' "$tmp/err"
assert_parse 'initial setup' run
spec="$tmp/home/.config/cdi/nvidia.yaml"
conf="$tmp/home/.config/containers/containers.conf.d/90-claude-sandbox-nvidia-cdi.conf"
assert_parse 'spec written' test -s "$spec"
assert_parse 'user path configured' grep -Fq "$tmp/home/.config/cdi" "$conf"
echo 'unrelated configuration' > "$tmp/home/.config/containers/containers.conf"
assert_parse 'repeat setup' run
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
assert_parse 'XDG spec written' test -s "$tmp/custom config/cdi/nvidia.yaml"
assert_eq 'spec carries marker' '# Managed by claude-sandbox setup-nvidia-cdi.sh' "$(head -n 1 "$spec")"
assert_parse 'spec keeps generated content' grep -Fq 'kind: nvidia.com/gpu' "$spec"
echo '# user spec' > "$spec"
if run; then fail 'unmanaged spec overwritten'; else pass; fi
assert_eq 'unmanaged spec retained' '# user spec' "$(cat "$spec")"
assert_parse 'unmanaged spec preserves config' cmp -s "$conf" "$tmp/before-conf"
cp "$tmp/before-spec" "$spec"
echo '# user owned' > "$conf"
if run; then fail 'unmanaged config overwritten'; else pass; fi
assert_eq 'unmanaged config retained' '# user owned' "$(cat "$conf")"
if run IS_SANDBOX=1; then fail 'agent sandbox accepted'; else pass; fi
finish nvidia_cdi.sh
