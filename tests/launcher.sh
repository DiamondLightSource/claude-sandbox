#!/usr/bin/env bash
# Launcher argv tests for container/claude-container — the verbs, the
# host-network default, the pre-4.0 flag refusals, the in-container refusal
# and the uvx-aware update hint. Drives the REAL launcher against a fake
# container engine on PATH that logs every call and answers the inspect
# queries the launcher makes; no image, no container, no network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
LAUNCHER="$HERE/../container/claude-container"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/project"
LOG="$TMP/engine.log"

# The fake engine. Existence of the container is a marker file created by
# `create`; the image label is FAKE_IMG_VER (empty = unlabelled).
cat > "$TMP/bin/podman" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
case "$*" in
    "container inspect -f {{.State.Running}} "*) [ -e "$MARK" ] && echo true ;;
    "container inspect -f {{join .Config.Cmd \" \"}} "*) echo 'bash -c trap "exit 0" TERM INT; while :; do sleep 60 & wait $!; done' ;;
    "container inspect -f {{.Created}} "*) echo 2026-09-13T00:00:00 ;;
    "container inspect -f {{.Image}} "*) echo img1 ;;
    "container inspect -f {{len .ExecIDs}} "*) echo 0 ;;
    "container inspect "*) [ -e "$MARK" ] ;;
    "image inspect -f {{index .Config.Labels \"io.diamondlightsource.claude-sandbox.launcher-version\"}} "*)
        [ -n "${FAKE_IMG_VER:-}" ] && echo "$FAKE_IMG_VER" ;;
    "image inspect -f {{index .Config.Labels \"org.opencontainers.image.revision\"}} "*) echo abc123 ;;
    "image inspect -f {{.Id}} "*) echo img1 ;;
    "create "*) touch "$MARK" ;;
    *) : ;;
esac
FAKE
chmod +x "$TMP/bin/podman"

# run [ENV=VAL ...] -- ARGS...: fresh engine state, from the project dir.
run() {
    local -a envs=()
    while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    : > "$LOG"; rm -f "$TMP/mark"
    ( cd "$TMP/project" && env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" \
        LOG="$LOG" MARK="$TMP/mark" CLAUDE_SANDBOX_NESTED=1 "${envs[@]}" \
        bash "$LAUNCHER" "$@" 2>"$TMP/err" ); RC=$?
    ERR="$(cat "$TMP/err")"
}
exec_line() { grep '^exec -it ' "$LOG" | head -1; }
create_line() { grep '^create ' "$LOG" | head -1; }

# --- version prints the project version -----------------------------------
out="$(bash "$LAUNCHER" --version)"
ver="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$LAUNCHER")"
[ "$out" = "claude-sandbox $ver" ] && pass || fail "--version printed '$out'"

# --- verbs -----------------------------------------------------------------
run --; assert_contains "default verb is claude" "$(exec_line)" "exec -it claude-sandbox-project-$(printf '%s' "$TMP/project" | cksum | awk '{print $1}') claude"
run -- pi -p hi;   case "$(exec_line)" in *" pi -p hi") pass ;; *) fail "pi verb: $(exec_line)" ;; esac
run -- codex;      case "$(exec_line)" in *" codex") pass ;; *) fail "codex verb: $(exec_line)" ;; esac
run -- shell;      case "$(exec_line)" in *" bash") pass ;; *) fail "shell verb: $(exec_line)" ;; esac
run -- --resume;   case "$(exec_line)" in *" claude --resume") pass ;; *) fail "agent args without verb: $(exec_line)" ;; esac

# --- host networking is the default; --bridge opts out (create-time) -------
run --; case "$(create_line)" in *"--network=host"*) pass ;; *) fail "host net not default: $(create_line)" ;; esac
run -- --bridge; case "$(create_line)" in *"--network=host"*) fail "--bridge still host net" ;; *) pass ;; esac

# --- pre-4.0 spellings refuse rather than leak into agent argv -------------
for old in --agent --host-net --shell; do
    run -- $old codex
    [ "$RC" = 2 ] && [ -z "$(exec_line)" ] && pass || fail "$old accepted (rc=$RC)"
done
run -- install; [ "$RC" = 2 ] && pass || fail "install verb accepted by the script (rc=$RC)"

# --- in-container refusal (seam off) ---------------------------------------
if [ -e /run/.containerenv ] || [ -e /.dockerenv ]; then
    : > "$LOG"
    ( cd "$TMP/project" && env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" LOG="$LOG" MARK="$TMP/mark" \
        bash "$LAUNCHER" 2>"$TMP/err" ); rc=$?
    [ "$rc" = 1 ] && grep -q 'inside' "$TMP/err" && [ -z "$(exec_line)" ] && pass \
        || fail "in-container launch not refused (rc=$rc): $(cat "$TMP/err")"
else
    echo "note: not in a container — in-container refusal not exercised" >&2
fi

# --- update hint names the front door that ran us ---------------------------
run FAKE_IMG_VER=99.0.0 --; case "$ERR" in *"curl -fsSLO"*) pass ;; *) fail "copied-script hint: $ERR" ;; esac
run FAKE_IMG_VER=99.0.0 CLAUDE_SANDBOX_LAUNCHER=uvx --
case "$ERR" in *"uvx claude-sandbox@latest"*) pass ;; *) fail "uvx hint: $ERR" ;; esac
case "$ERR" in *"curl"*) fail "uvx hint still mentions curl" ;; *) pass ;; esac
run FAKE_IMG_VER=0.1.0 CLAUDE_SANDBOX_LAUNCHER=uvx --
case "$ERR" in *"uvx claude-sandbox --recreate"*) pass ;; *) fail "newer-launcher hint under uvx: $ERR" ;; esac

echo "launcher: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
