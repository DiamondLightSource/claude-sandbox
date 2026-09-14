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
    "container inspect -f {{.State.Running}} "*) case "$*" in *running*) echo true ;; *) [ -e "$MARK" ] && echo true ;; esac ;;
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
    "ps -a --filter name=^claude-sandbox- --format {{.Names}}") cat "$PS" 2>/dev/null ;;
    "images --filter reference=*/diamondlightsource/claude-sandbox --format {{.Repository}}:{{.Tag}}") cat "$IMAGES" 2>/dev/null ;;
    "rmi "*) [ "${2:-}" != "in-use:1" ] ;;
    *) : ;;
esac
FAKE
chmod +x "$TMP/bin/podman"

# run [ENV=VAL ...] -- ARGS...: fresh engine state, from the project dir.
run() {
    local -a envs=()
    while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    : > "$LOG"; rm -f "$TMP/mark"
    ( cd "${PROJECT:-$TMP/project}" && env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" \
        LOG="$LOG" MARK="$TMP/mark" PS="$TMP/ps" IMAGES="$TMP/images" CLAUDE_SANDBOX_NESTED=1 "${envs[@]}" \
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
run -- shell;      case "$(exec_line)" in *"exec bash \"\$@\" _ bash") pass ;; *) fail "shell verb default without host SHELL: $(exec_line)" ;; esac
# The ancestor walk finds this harness (bash) where /proc is readable; inside the
# sandbox host /proc is bound with foreign PIDs, so it falls back to SHELL (zsh).
run SHELL=/usr/bin/zsh -- shell;            case "$(exec_line)" in *" _ bash"|*" _ zsh") pass ;; *) fail "shell verb default: $(exec_line)" ;; esac
run SHELL=/usr/bin/zsh CLAUDE_SANDBOX_SHELL=fish -- shell -c ls; case "$(exec_line)" in *" _ fish -c ls") pass ;; *) fail "CLAUDE_SANDBOX_SHELL override: $(exec_line)" ;; esac
run CLAUDE_SANDBOX_SHELL=fish --; assert_not_contains "shell choice is not baked at create" "$(create_line)" "-e CLAUDE_SANDBOX_SHELL=fish"
run -- --resume;   case "$(exec_line)" in *" claude --resume") pass ;; *) fail "agent args without verb: $(exec_line)" ;; esac
run -- version;    case "$(exec_line)" in *" claude-sandbox version") pass ;; *) fail "version verb not forwarded: $(exec_line)" ;; esac
run -- gh-auth;    case "$(exec_line)" in *" claude-sandbox gh-auth") pass ;; *) fail "gh-auth verb not forwarded: $(exec_line)" ;; esac
run -- verify --agent pi; case "$(exec_line)" in *" claude-sandbox verify --agent pi") pass ;; *) fail "verify args not forwarded: $(exec_line)" ;; esac

# --- host networking is the default; --bridge opts out (create-time) -------
touch "$TMP/.gitconfig"
run --
case "$(create_line)" in
    *"$TMP/.gitconfig:/root/.gitconfig-host:ro"*) pass ;;
    *) fail "host git config is not mounted separately read-only" ;;
esac
assert_not_contains "container git config remains writable" "$(create_line)" ":/root/.gitconfig:ro"

run --; case "$(create_line)" in *"--network=host"*) pass ;; *) fail "host net not default: $(create_line)" ;; esac
run -- --bridge; case "$(create_line)" in *"--network=host"*) fail "--bridge still host net" ;; *) pass ;; esac

# --- filesystem view: parent ro, project rw, --mount ro, --mount-rw ---------
mkdir -p "$TMP/ws/project" "$TMP/ro" "$TMP/rw"
PROJECT="$TMP/ws/project" run --
case "$(create_line)" in *"--mount type=bind,src=$TMP/ws,dst=$TMP/ws,ro,bind-propagation=slave -v $TMP/ws/project:$TMP/ws/project -w"*) pass ;; *) fail "parent not ro before project rw: $(create_line)" ;; esac
run --   # project directly under $HOME: parent holds ~, must not be mounted
assert_not_contains "parent containing HOME is not mounted" "$(create_line)" "--mount type=bind,src=$TMP,dst=$TMP,ro,bind-propagation=slave"
case "$ERR" in *"contains your home directory"*) pass ;; *) fail "HOME guard silent: $ERR" ;; esac
run -- --mount "$TMP/ro" --mount-rw "$TMP/rw"
case "$(create_line)" in *"src=$TMP/ro,dst=$TMP/ro,ro,bind-propagation=slave"*) pass ;; *) fail "--mount not ro: $(create_line)" ;; esac
case "$(create_line)" in *"src=$TMP/rw,dst=$TMP/rw,bind-propagation=slave"*) pass ;; *) fail "--mount-rw not rw: $(create_line)" ;; esac
case "$(create_line)" in *"-e CLAUDE_SANDBOX_ALLOW_WRITE=$TMP/rw "*) pass ;; *) fail "allow-write missing rw mount: $(create_line)" ;; esac
assert_not_contains "ro mount not in allow-write" "$(create_line)" "ALLOW_WRITE=$TMP/rw:$TMP/ro"
run -- --mount; [ "$RC" = 1 ] && pass || fail "--mount without PATH accepted (rc=$RC)"

# --- env: locale always, X11 only when the host has a DISPLAY --------------
run --; case "$(create_line)" in *"-e LANG=en_US.UTF-8"*) pass ;; *) fail "LANG default: $(create_line)" ;; esac
assert_not_contains "no DISPLAY without one on the host" "$(create_line)" "DISPLAY"
touch "$TMP/.Xauthority"
run DISPLAY=:1 --
case "$(create_line)" in *"-e DISPLAY=:1"*) pass ;; *) fail "DISPLAY not passed: $(create_line)" ;; esac
case "$(create_line)" in *"-v $TMP/.Xauthority:/root/.Xauthority:ro"*) pass ;; *) fail "Xauthority not mounted ro: $(create_line)" ;; esac
rm -f "$TMP/.Xauthority"

# --- uv download cache on a named volume; venv stays per container ---------
run --
case "$(create_line)" in *"-v claude-sandbox-uv-cache:/cache/uv -e UV_LINK_MODE=copy"*) pass ;; *) fail "uv cache volume: $(create_line)" ;; esac
assert_not_contains "venv is not on the shared volume" "$(create_line)" "/cache "
run CLAUDE_SANDBOX_UV_CACHE=mine --
case "$(create_line)" in *"-v mine:/cache/uv"*) pass ;; *) fail "uv cache volume name override: $(create_line)" ;; esac
assert_not_contains "volume name not baked as env" "$(create_line)" "-e CLAUDE_SANDBOX_UV_CACHE=mine"
run CLAUDE_SANDBOX_UV_CACHE= --
case "$(create_line)" in *":/cache/uv"*) fail "empty name should disable the volume: $(create_line)" ;; *) pass ;; esac

# --- pre-4.0 spellings refuse rather than leak into agent argv -------------
for old in --agent --host-net --shell; do
    run -- $old codex
    [ "$RC" = 2 ] && [ -z "$(exec_line)" ] && pass || fail "$old accepted (rc=$RC)"
done
run -- install; [ "$RC" = 2 ] && pass || fail "install verb accepted by the script (rc=$RC)"

# --- in-container refusal (seam off) ---------------------------------------
if [ -e /run/.containerenv ] || [ -e /.dockerenv ]; then
    : > "$LOG"
    ( cd "${PROJECT:-$TMP/project}" && env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" LOG="$LOG" MARK="$TMP/mark" \
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


# --- clean removes stopped keeper containers; running ones only with --force -
printf '%s\n' claude-sandbox-a-1 claude-sandbox-b-2 claude-sandbox-running-3 > "$TMP/ps"
run -- clean
[ "$RC" = 0 ] && pass || fail "clean rc=$RC: $ERR"
grep -qx 'rm -f claude-sandbox-a-1' "$LOG" && grep -qx 'rm -f claude-sandbox-b-2' "$LOG" && pass || fail "clean did not remove both stopped: $(cat "$LOG")"
grep -q 'rm -f claude-sandbox-running-3' "$LOG" && fail "clean removed a running container without --force" || pass
case "$ERR" in *"kept claude-sandbox-running-3 (running; --force"*) pass ;; *) fail "running container not reported: $ERR" ;; esac
[ -z "$(exec_line)" ] && [ -z "$(create_line)" ] && pass || fail "clean started a session"
case "$ERR" in *"2 container(s) removed, 1 running kept"*) pass ;; *) fail "clean summary: $ERR" ;; esac
run -- clean --force
grep -qx 'rm -f claude-sandbox-running-3' "$LOG" && pass || fail "--force did not remove the running container: $(cat "$LOG")"
case "$ERR" in *"3 container(s) removed, 0 running kept"*) pass ;; *) fail "--force summary: $ERR" ;; esac
grep -q '^rmi ' "$LOG" && fail "clean touched images without --images" || pass
printf '%s\n' ghcr.io/diamondlightsource/claude-sandbox:4.0.0 in-use:1 > "$TMP/images"
run -- clean --force --images
grep -qx 'rmi ghcr.io/diamondlightsource/claude-sandbox:4.0.0' "$LOG" && pass || fail "--images did not rmi: $(cat "$LOG")"
case "$ERR" in *"removed image ghcr.io/diamondlightsource/claude-sandbox:4.0.0"*) pass ;; *) fail "image summary: $ERR" ;; esac
case "$ERR" in *"removed image in-use"*) fail "in-use image reported removed" ;; *) pass ;; esac
run -- clean --bogus; [ "$RC" = 2 ] && [ -z "$(grep '^rm ' "$LOG")" ] && pass || fail "clean --bogus accepted (rc=$RC)"
rm -f "$TMP/ps" "$TMP/images"
echo "launcher: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
