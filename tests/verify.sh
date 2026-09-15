#!/usr/bin/env bash
# Run the helper and full shadow launch with fixture paths. Only bwrap and
# vendor binaries are substitutes; script(1), config and dispatch are real.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/tests/lib.sh"
tmp="$(mktemp -d)"
register_cleanup "$tmp"
mkdir -p "$tmp/bin" "$tmp/libexec/codex-dist/bin" "$tmp/home"
printf 'egress-jail = 0\n' > "$tmp/sandbox.conf"
for file in claude-sandbox claude-shadow; do
    sed -e "s|/usr/local/bin/|$tmp/bin/|g" \
        -e "s|/usr/libexec/claude-sandbox|$tmp/libexec|g" \
        -e "s|/etc/claude-gitconfig|$tmp/gitconfig|g" \
        -e "s|/etc/claude-sandbox.conf|$tmp/sandbox.conf|g" \
        "$REPO_ROOT/.devcontainer/claude-sandbox/$file" > "$tmp/bin/$file"
    chmod +x "$tmp/bin/$file"
done
for agent in claude codex pi; do ln -s claude-shadow "$tmp/bin/$agent"; done
for real in claude codex-dist/bin/codex pi-run; do
    printf '#!/bin/sh\necho VENDOR_WAS_STARTED\nexit 99\n' > "$tmp/libexec/$real"
    chmod +x "$tmp/libexec/$real"
done
cat > "$tmp/bin/bwrap" <<'FAKE'
#!/usr/bin/env bash
while [ "$1" != -- ]; do shift; done
shift
exec "$@"
FAKE
chmod +x "$tmp/bin/bwrap"
cat > "$tmp/libexec/verify-sandbox-battery.sh" <<'BATTERY'
[ "$#" = 0 ] || exit 98
echo DIRECT_BATTERY
exit "${BATTERY_STATUS:-0}"
BATTERY
for agent in claude codex pi; do
    for expected in 0 7; do
        rc=0
        output="$(env -u IS_SANDBOX -u CLAUDE_SHADOW_SOURCE_ONLY -u CLAUDE_SANDBOX_AGENT \
            HOME="$tmp/home" PATH="$tmp/bin:$PATH" BATTERY_STATUS="$expected" \
            bash "$tmp/bin/claude-sandbox" verify --agent "$agent" </dev/null 2>&1)" || rc=$?
        assert_eq "$agent battery exit status" "$expected" "$rc"
        assert_contains "$agent runs battery directly" "${output//$'\r'/}" DIRECT_BATTERY
        assert_not_contains "$agent does not start vendor" "$output" VENDOR_WAS_STARTED
    done
done
rc=0
IS_SANDBOX=1 BATTERY_STATUS=7 bash "$tmp/bin/claude-sandbox" verify > "$tmp/inside" || rc=$?
assert_eq 'verify an existing sandbox returns battery status' 7 "$rc"
assert_contains 'verify an existing sandbox runs battery' "$(cat "$tmp/inside")" DIRECT_BATTERY
rc=0
bash "$tmp/bin/claude-sandbox" verify --agent invalid >/dev/null 2>&1 || rc=$?
assert_eq 'reject invalid verification profile' 2 "$rc"
finish verify
