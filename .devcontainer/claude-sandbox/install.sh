#!/usr/bin/env bash
# claude-sandbox installer (bash-only). Idempotent: re-runs after a
# devcontainer rebuild re-establish container state without disturbing
# workspace edits.
#
# Three configurable seams for tests:
#   INSTALL_PREFIX    (default /)   — root of file placement, so
#                                    tests/smoke.sh can drop everything
#                                    into a tmpdir.
#   INSTALL_WORKSPACE (default $PWD) — workspace whose `.claude/` is the
#                                    rw bind root (still used by the
#                                    shadow); no longer carries the
#                                    integrity guard, which is global.
#   INSTALL_USER_HOME (default $HOME) — home whose user-scope
#                                    `~/.claude/settings.json` gets the
#                                    GLOBAL integrity guard merged in.
#                                    Tests point it at a tmpdir so the
#                                    real ~/.claude is never touched.
#   CLAUDE_SANDBOX_SMOKE=1            skip apt + the curl-install of every
#                                    agent binary.
#   WITH_CODEX=0                     skip fetching OpenAI's Codex CLI. The
#                                    codex SHADOW and the managed guard are
#                                    still installed either way — the shadow
#                                    has to own the name on $PATH before the
#                                    vendor's installer can claim it
#                                    (Invariant 1), so opting out here only
#                                    skips the download.
#   STATUS=1                         force-overwrite the user-scope
#                                    statusline script from the clone's
#                                    copy, instead of seed-only-if-absent.
#   DANGEROUSLY_ALLOW_CLAUDE_SANDBOX_UNWRAPPED=1
#                                    stamp the ROOT-OWNED gate escape-hatch
#                                    flag (/etc/claude-code/allow-unwrapped)
#                                    so the UserPromptSubmit gate downgrades
#                                    to warn-only. The OPERATOR's switch for
#                                    running claude unwrapped; a confined
#                                    Claude can't create it (it's under /etc,
#                                    ro in the sandbox — deep-review H4).
#                                    Unset/0 leaves the gate fail-closed and
#                                    removes a stale flag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is the clone — two levels above .devcontainer/claude-sandbox.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREFIX="${INSTALL_PREFIX:-/}"
WORKSPACE="${INSTALL_WORKSPACE:-$PWD}"
USER_HOME="${INSTALL_USER_HOME:-$HOME}"
SMOKE="${CLAUDE_SANDBOX_SMOKE:-0}"
WITH_CODEX="${WITH_CODEX:-1}"
FORCE_STATUSLINE="${STATUS:-0}"
ALLOW_UNWRAPPED="${DANGEROUSLY_ALLOW_CLAUDE_SANDBOX_UNWRAPPED:-0}"

# Resolve a target under $PREFIX. Stripping the leading slash lets us
# compose relative-to-prefix paths cleanly without a `//` between root
# and the absolute path.
prefixed() {
    local abs="$1"
    if [ "$PREFIX" = "/" ]; then
        printf '%s\n' "$abs"
    else
        printf '%s\n' "${PREFIX%/}${abs}"
    fi
}

probe_or_refuse() {
    if [ "$SMOKE" = "1" ]; then
        return 0
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "claude-sandbox: refusing — Debian/Ubuntu only (no apt-get on PATH)." >&2
        exit 1
    fi
}

apt_install() {
    if [ "$SMOKE" = "1" ]; then
        return 0
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # passt provides `pasta`, the userspace network forwarder the egress
    # jail (ADR 0015) attaches to a per-Claude netns. The jail is ON by
    # default and fail-closed, so passt is installed unconditionally: a
    # host with the jail on (the default) must not fail to launch claude
    # for want of pasta. It's tiny. The matching host-side dep,
    # --device=/dev/net/tun, is a
    # devcontainer.json runArg this installer cannot add (see claude-shadow's
    # netns_launch error message and claude-sandbox.conf).
    apt-get install -y -qq --no-install-recommends \
        bubblewrap jq curl ca-certificates git nodejs gh passt
    # glab isn't in every Ubuntu repo; install-try.
    apt-get install -y -qq --no-install-recommends glab 2>/dev/null || true
}

probe_userns_or_refuse() {
    if [ "$SMOKE" = "1" ]; then
        return 0
    fi
    if ! bwrap --ro-bind / / --unshare-user-try --unshare-pid -- /bin/true \
            >/dev/null 2>&1; then
        cat >&2 <<'EOF'
claude-sandbox: refusing — kernel unprivileged user namespaces are
forbidden. The bwrap sandbox cannot start without them.

On Ubuntu 24.04:
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
On rootful Docker with default AppArmor: rebuild the devcontainer
under rootless podman, or relax AppArmor for bwrap.
EOF
        exit 1
    fi
}

# install_claude_binary: fetch the real Claude via the official
# installer, then relocate it to a path that is NOT on the user's
# PATH. The official installer drops the binary at ~/.local/bin/claude
# AND prepends ~/.local/bin to the user's shell rc — meaning plain
# `claude` would resolve past our shadow once a new shell starts. By
# moving the binary to /usr/libexec/claude-sandbox/, ~/.local/bin/
# stays empty and the rc-mutation becomes harmless.
install_claude_binary() {
    if [ "$SMOKE" = "1" ]; then
        return 0
    fi
    local real_dest
    real_dest="$(prefixed /usr/libexec/claude-sandbox/claude)"
    if [ -x "$real_dest" ]; then
        # Idempotent: purge any stale copy a prior curl-install may have
        # left at ~/.local/bin/claude so the shadow remains the only
        # `claude` on the user's PATH.
        rm -f "$HOME/.local/bin/claude"
        return 0
    fi
    curl -fsSL https://claude.ai/install.sh | bash
    if [ ! -x "$HOME/.local/bin/claude" ]; then
        echo "claude-sandbox: official installer did not produce \$HOME/.local/bin/claude" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$real_dest")"
    mv "$HOME/.local/bin/claude" "$real_dest"
}

# install_codex_binary: same relocate-after-install dance as Claude, for
# OpenAI's Codex CLI (the client for GPT-6 Astra). Its installer also drops
# the binary into ~/.local/bin and prepends that dir to the user's shell rc,
# so leaving it there would let plain `codex` resolve past our shadow —
# Invariant 1, identically.
#
# BEST-EFFORT, unlike Claude's: a host that cannot reach chatgpt.com, or a
# vendor change to the install script, must not brick a claude-sandbox
# install. We warn and carry on; the codex shadow is still placed, and it
# loud-fails with a re-run-install message if someone types `codex`.
#
# What the vendor installer actually does (verified against
# chatgpt.com/codex/install.sh): it unpacks a versioned release under
# $CODEX_HOME/packages/standalone/releases/<version>/ and puts a SYMLINK to it
# at ~/.local/bin/codex. Two consequences we have to handle:
#
#   1. Relocating the symlink would relocate nothing. We resolve it first and
#      relocate the file it points at.
#   2. The real binary therefore lives INSIDE ~/.codex, which the shadow binds
#      READ-WRITE (it is CODEX_HOME — config and auth live there too). A copy
#      of the agent's own binary inside its writable set is a persistence
#      foothold: a compromised session could rewrite it and be re-executed by
#      the next launch. So we take a COPY to the root-owned, off-PATH,
#      ro-in-sandbox /usr/libexec, exec only that, and the shadow tmpfs-masks
#      $HOME/.codex/packages so the writable vendor tree is not visible in the
#      session at all — exactly what is already done for Claude's versioned
#      binary cache at ~/.local/share/claude.
#   3. ~/.codex is by this point usually a SYMLINK into the shared
#      cross-container store (link_terminal_config runs first), so letting the
#      vendor unpack there would push a versioned release tree — tens of MB,
#      one per release, pruned by nothing — onto the host share, where every
#      container that mounts it inherits the growth. We only ever want the
#      /usr/libexec copy, so the vendor unpacks into a TEMP CODEX_HOME that is
#      deleted once the copy is taken.

# codex_purge_vendor_tree [STAGE]: remove every writable copy of the codex
# package the vendor installer leaves behind, plus the unwrapped `codex` on the
# user's PATH (Invariant 1). Called on every exit path — including the
# idempotent one, so a tree left by an older claude-sandbox is cleaned up too.
codex_purge_vendor_tree() {
    local stage="${1:-}"
    # if, not `[ ... ] && rm`: this file runs under `set -e`, where a bare
    # AND-list that ends false takes the whole install down with it.
    if [ -n "$stage" ] && [ -d "$stage" ]; then
        rm -rf "$stage"
    fi
    # Belt and braces: if the vendor installer ignored CODEX_HOME and unpacked
    # into the real one anyway, that tree must not persist on the share either.
    # Safe to delete unconditionally — we never exec from it (the binary we run
    # is the /usr/libexec copy) and the shadow tmpfs-masks it in-session.
    rm -rf "$HOME/.codex/packages"
    rm -f "$HOME/.local/bin/codex" "$HOME/.local/bin/codex-code-mode-host"
    return 0
}

install_codex_binary() {
    if [ "$SMOKE" = "1" ] || [ "$WITH_CODEX" != "1" ]; then
        return 0
    fi
    local dist_dest real_dest stage
    dist_dest="$(prefixed "$CODEX_DIST_DIR")"
    real_dest="$(prefixed "$CODEX_REAL_PATH")"
    if [ -x "$real_dest" ]; then
        codex_purge_vendor_tree
        return 0
    fi
    stage="$(mktemp -d)"
    # CODEX_NON_INTERACTIVE=1: the vendor installer ends with a "Start Codex
    # now? [y/N]" prompt that it reads from /dev/tty — NOT from stdin — so
    # piping the script to sh does not make it unattended. Without this, a
    # plain `./install` blocks on that prompt in any real terminal.
    #
    # TAR_OPTIONS=--no-same-owner: the release tarball carries uid/gid 1001,
    # and tar running as root tries to restore that ownership. In a ROOTLESS
    # container — the supported runtime — in-container root maps to the
    # unprivileged host user, uid 1001 is outside the mapped range, and every
    # chown fails: "Cannot change ownership to uid 1001 ... Operation not
    # permitted", then "Exiting with failure status". GNU tar reads this
    # variable and prepends the option, which is the only seam the vendor
    # script leaves us (it invokes tar itself).
    if ! curl -fsSL https://chatgpt.com/codex/install.sh \
            | CODEX_HOME="$stage" CODEX_NON_INTERACTIVE=1 TAR_OPTIONS=--no-same-owner sh; then
        echo "claude-sandbox: WARNING — the Codex CLI installer failed; skipping codex." >&2
        echo "  The codex shadow is still installed and will refuse to launch until" >&2
        echo "  a real binary lands at $real_dest. Re-run ./install to retry." >&2
        codex_purge_vendor_tree "$stage"
        return 0
    fi

    # Find the RELEASE DIRECTORY, not just the binary. Codex ships as a
    # package: the vendor's own validity check requires codex-package.json,
    # bin/codex, bin/codex-code-mode-host, codex-path/rg (ripgrep) and
    # codex-resources/bwrap to sit together. Relocating bin/codex alone would
    # strip codex of its search tool and its own sandbox helpers.
    #
    # ~/.local/bin/codex is a symlink into that directory, so resolve it and
    # walk up from bin/.
    local link resolved release_dir=""
    link="$HOME/.local/bin/codex"
    if [ -L "$link" ] || [ -x "$link" ]; then
        resolved="$(readlink -f "$link" 2>/dev/null || true)"
        if [ -n "$resolved" ] && [ -f "$resolved" ]; then
            # Never relocate our own shadow (it is on the search path by
            # construction, so a vendor download that leaves nothing behind
            # falls through to it). Compared by CONTENT, not by grepping for a
            # marker string: a marker is a promise about a file's wording that
            # nobody remembers to keep when the header is reworded, and
            # installing the shadow as its own target HANGS (the shadow execs
            # itself forever) rather than erroring.
            #
            # Compared against the RESOLVED binary, not "$release_dir/bin/codex":
            # release_dir is derived by two branches below, and on the plain
            # */codex one it is the binary's own parent — so "$release_dir/bin/
            # codex" named a different (usually absent) file and the check
            # silently no-opped on exactly the path that needed it.
            if cmp -s "$resolved" "$SCRIPT_DIR/claude-shadow"; then
                echo "claude-sandbox: WARNING — $resolved is the claude-sandbox" >&2
                echo "  shadow itself, not a real codex binary; skipping codex relocation." >&2
                codex_purge_vendor_tree "$stage"
                return 0
            fi
            case "$resolved" in
                */bin/codex) release_dir="${resolved%/bin/codex}" ;;
                */codex)     release_dir="${resolved%/codex}" ;;
            esac
        fi
    fi
    # Fall back to the vendor's "current" symlink if the PATH entry is gone.
    # The staged CODEX_HOME first; the real one second, in case a future vendor
    # installer ignores CODEX_HOME and unpacks into ~/.codex regardless.
    local cur
    for cur in "$stage/packages/standalone/current" \
               "$HOME/.codex/packages/standalone/current"; do
        if [ -z "$release_dir" ] && [ -d "$cur" ]; then
            release_dir="$(readlink -f "$cur" 2>/dev/null || true)"
        fi
    done
    if [ -z "$release_dir" ] || [ ! -d "$release_dir" ]; then
        echo "claude-sandbox: WARNING — the Codex CLI installer ran but no release" >&2
        echo "  directory was found; skipping codex relocation." >&2
        codex_purge_vendor_tree "$stage"
        return 0
    fi
    # Same identity check again for the fallback branch, which reaches
    # release_dir without ever resolving the PATH symlink.
    if [ -f "$release_dir/bin/codex" ] \
            && cmp -s "$release_dir/bin/codex" "$SCRIPT_DIR/claude-shadow"; then
        echo "claude-sandbox: WARNING — $release_dir/bin/codex is the claude-sandbox" >&2
        echo "  shadow itself, not a real codex binary; skipping codex relocation." >&2
        codex_purge_vendor_tree "$stage"
        return 0
    fi

    # Copy the WHOLE package to a root-owned, off-PATH location. Read-only
    # inside the sandbox (--ro-bind / /), so — unlike Claude's, which is
    # bind-mounted rw at ~/.local/bin/claude — an in-session self-update
    # cannot rewrite the binary we exec.
    rm -rf "$dist_dest"
    mkdir -p "$(dirname "$dist_dest")"
    cp -a "$release_dir" "$dist_dest"
    chmod -R go-w "$dist_dest"
    if [ ! -x "$real_dest" ]; then
        echo "claude-sandbox: WARNING — copied $release_dir but $real_dest is not" >&2
        echo "  executable; codex will refuse to launch." >&2
    fi
    # Nothing unwrapped, and no writable copy of the package, may remain
    # (Invariant 1, plus the shared-store growth noted above).
    codex_purge_vendor_tree "$stage"
}

# install_file: byte-stable copy of src → dst at mode 0755. Refuses
# if src is missing (loud-fail beats a downstream errno). cmp -s
# short-circuits so a re-run is a true no-op when content matches.
install_file() {
    local src="$1" dst="$2"
    if [ ! -f "$src" ]; then
        echo "claude-sandbox: cannot find $src" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        return 0
    fi
    install -m 0755 "$src" "$dst"
}

# install_file_if_absent: place src at dst (mode 0755) only when dst is
# absent. Used for the user-scope statusline, which we seed on a fresh
# machine but never stomp if the owner already has one — the field is
# likewise set-only-if-absent in wire_user_statusline.
install_file_if_absent() {
    local src="$1" dst="$2"
    if [ ! -f "$src" ]; then
        echo "claude-sandbox: cannot find $src" >&2
        exit 1
    fi
    [ -f "$dst" ] && return 0
    mkdir -p "$(dirname "$dst")"
    install -m 0755 "$src" "$dst"
}

ensure_cred_dirs() {
    mkdir -p "$USER_HOME/.config/gh" "$USER_HOME/.config/glab-cli"
    touch "$USER_HOME/.claude.json"
    # ~/.codex is CODEX_HOME: config.toml, auth.json, sessions/. Pre-created
    # so the shadow's --bind of it succeeds on a first-ever codex launch.
    mkdir -p "$USER_HOME/.codex"
}

# install_conf: place the clone's claude-sandbox.conf at the host-global
# /etc/claude-sandbox.conf the shadow reads at launch. Re-run on every
# rebuild (via postCreate) so the /etc copy tracks the clone's conf.
# Unlike install_file this is skip-if-absent: a clone that carries no
# conf simply gets no global config
# (parse_config then no-ops). Mode 0644 — it's data, not an executable.
# cmp -s short-circuits so a re-run with unchanged content is a no-op.
install_conf() {
    local src dst
    src="$REPO_ROOT/.devcontainer/claude-sandbox.conf"
    dst="$(prefixed /etc/claude-sandbox.conf)"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        return 0
    fi
    install -m 0644 "$src" "$dst"
}

# stamp_version: record what this clone is at install time, for
# `claude-sandbox version`. A tagged checkout stamps the tag (git
# describe on a tag == the tag, which is what `claude-sandbox update`
# installs); an unpinned main clone stamps a commit hash — honest
# "unreleased" reporting. CLAUDE_SANDBOX_VERSION overrides for builds
# with no .git (the container image). Deterministic per clone, so the
# byte-stable re-run property holds.
stamp_version() {
    local ver dst
    dst="$(prefixed "$VERSION_FILE_PATH")"
    ver="${CLAUDE_SANDBOX_VERSION:-$(git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)}"
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && [ "$(cat "$dst")" = "$ver" ]; then
        return 0
    fi
    printf '%s\n' "$ver" > "$dst"
    chmod 0644 "$dst"
}

# _is_mount PATH — true if PATH is itself a mount target. Compares the
# st_dev of PATH against its parent (the heuristic mountpoint(1) uses),
# NOT /proc/mounts: inside the sandbox /proc is the host's procfs
# (--ro-bind /proc /proc), so /proc/mounts shows the host namespace and
# would miss a path the sandbox itself bind-mounted. stat(2) queries the
# live kernel, and unlike mountpoint(1) the st_dev check works for a
# bind-mounted ~/.claude.json (a regular file) too.
_is_mount() {
    local path="$1" pdev ddev
    [ -e "$path" ] || return 1
    pdev="$(stat -c '%d' "$path" 2>/dev/null)" || return 1
    ddev="$(stat -c '%d' "$(dirname "$path")" 2>/dev/null)" || return 1
    [ "$pdev" != "$ddev" ]
}

# _is_empty PATH KIND — true when an existing dir has no entries / a file
# is zero-length. Caller guarantees PATH exists.
_is_empty() {
    local path="$1" kind="$2"
    if [ "$kind" = dir ]; then
        [ -z "$(ls -A "$path" 2>/dev/null)" ]
    else
        [ ! -s "$path" ]
    fi
}

# _ensure_shared SHARED KIND — create an empty shared dir/file when
# absent, so a symlink into it never dangles.
_ensure_shared() {
    local shared="$1" kind="$2"
    if [ -e "$shared" ]; then return 0; fi
    if [ "$kind" = dir ]; then
        mkdir -p "$shared"
    else
        mkdir -p "$(dirname "$shared")"
        : > "$shared"
    fi
}

# _share_path TARGET SHARED KIND — make TARGET ($HOME/.claude{,.json}) a
# symlink into the shared config store, picking the data-preserving
# action for whatever TARGET currently is. The old create-if-absent
# guard silently lost the share whenever TARGET already existed — and in
# a devcontainer that doesn't run install from postCreate an
# unsandboxed `claude` or the VS Code extension routinely writes a local
# ~/.claude before install ever runs, permanently shadowing the share.
# Cases:
#   symlink -> SHARED         : nothing to do (idempotent re-run).
#   symlink elsewhere         : repoint to SHARED.
#   active mountpoint         : leave alone — a devcontainer that binds
#                               ~/.claude in directly is already shared,
#                               and a busy mount can't be moved (EBUSY).
#   real, SHARED empty/absent : SEED — move TARGET into SHARED, then
#                               symlink. Preserves a first-run OAuth
#                               token / local history as the new baseline.
#   real, SHARED populated    : shared wins — back TARGET up timestamped,
#                               then symlink (the "adopt" case).
#   absent                    : ensure SHARED exists, then symlink.
_share_path() {
    local target="$1" shared="$2" kind="$3"

    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$shared" ]; then
            return 0
        fi
        _ensure_shared "$shared" "$kind"
        rm -f "$target"
        ln -s "$shared" "$target"
        return 0
    fi

    if _is_mount "$target"; then
        echo "claude-sandbox: $target is an active mountpoint; leaving as-is (assumed already shared)." >&2
        return 0
    fi

    if [ -e "$target" ]; then
        if [ ! -e "$shared" ] || _is_empty "$shared" "$kind"; then
            if [ -e "$shared" ]; then rm -rf "$shared"; fi
            mkdir -p "$(dirname "$shared")"
            mv "$target" "$shared"
            echo "claude-sandbox: seeded shared config $shared from $target." >&2
        else
            local backup="$target.pre-sandbox.$(date +%Y%m%d-%H%M%S)"
            mv "$target" "$backup"
            echo "claude-sandbox: $shared already populated; backed up $target -> $backup." >&2
        fi
        ln -s "$shared" "$target"
        return 0
    fi

    _ensure_shared "$shared" "$kind"
    ln -s "$shared" "$target"
}

# link_terminal_config: when /user-terminal-config is mounted (the
# convention used by terminal-config-style devcontainers), share
# ~/.claude and ~/.claude.json into it so Claude's settings and OAuth
# state follow the user across every devcontainer on the host. Runs
# before install_claude_binary. Delegates per-path policy to
# _share_path, which adopts (or seeds from) a pre-existing local config
# instead of silently leaving it un-shared.
link_terminal_config() {
    local shared="${CLAUDE_SHARED_CONFIG:-/user-terminal-config}"
    [ -d "$shared" ] || return 0
    _share_path "$HOME/.claude"      "$shared/.claude"      dir
    _share_path "$HOME/.claude.json" "$shared/.claude.json" file
    # ~/.codex carries ONE OpenAI login (auth.json), the same class of
    # credential as ~/.claude — not a repo-scoped forge PAT, which stays
    # container-scoped by design (Invariant 2). Sharing it means signing in to
    # Codex once per host rather than once per devcontainer rebuild.
    #
    # Guarded on writability, unlike the two above: those predate this and
    # their behaviour is deliberately unchanged, but a shared store that is
    # mounted read-only (or owned by another uid) must not abort the whole
    # install under `set -e` just because codex could not be shared. Losing
    # the share costs a re-login after a rebuild; losing the install costs
    # the sandbox.
    if [ -w "$shared" ]; then
        _share_path "$HOME/.codex" "$shared/.codex" dir
    else
        echo "claude-sandbox: $shared is not writable; ~/.codex stays container-scoped (expect to sign in to codex again after a rebuild)." >&2
    fi
}

# The GLOBAL integrity guard is delivered through Claude Code's MANAGED
# settings layer (`/etc/claude-code/managed-settings.json`) — highest
# precedence, and crucially NOT overridable by editing the user's own
# `~/.claude/settings.json`. Two properties make this tamper-resistant
# in the same spirit as Invariant 4 (config at /etc, never the rw
# workspace):
#   - The hook ENTRIES live in /etc — a user editing their shared
#     ~/.claude can't remove them; only root editing /etc (or a
#     deliberate ./install) changes the guard.
#   - The hook SCRIPTS live in /usr/libexec/claude-sandbox (off-PATH,
#     root-owned) — like the relocated real binary, they are ro-bound
#     inside the sandbox (`--ro-bind / /`), so a compromised in-session
#     Claude cannot rewrite them to `exit 0`. (Under ~/.claude they
#     would have been rw-bound and editable.)
# Commands are absolute /usr/libexec paths — no $HOME, resolves in any
# cwd and in both wrapped and unwrapped launches.
GUARD_LIBEXEC="/usr/libexec/claude-sandbox"
VERIFY_PATH="$GUARD_LIBEXEC/sandbox-verify.sh"
GATE_PATH="$GUARD_LIBEXEC/sandbox-gate.sh"
# The /verify-sandbox phase-1 battery lives next to the guard scripts —
# off-PATH, root-owned, ro inside the sandbox — so a compromised in-session
# Claude (the workspace is rw) cannot rewrite the verifier to print PASS for
# a broken sandbox. It is NOT a hook (not wired into managed-settings); the
# /verify-sandbox command runs it by absolute path for the live battery.
BATTERY_PATH="$GUARD_LIBEXEC/verify-sandbox-battery.sh"
# Version record for `claude-sandbox version` — data, not a script, but
# it lives with the guard scripts (root-owned, ro in the sandbox) so a
# compromised session can't spoof what "version" reports.
VERSION_FILE_PATH="$GUARD_LIBEXEC/version"
VERIFY_CMD="bash $VERIFY_PATH"
GATE_CMD="bash $GATE_PATH"
MANAGED_SETTINGS="/etc/claude-code/managed-settings.json"
# Root-owned escape-hatch flag the gate checks (keep in sync with
# sandbox-gate.sh's hard-coded ALLOW_UNWRAPPED_FLAG). Under /etc — ro inside
# the sandbox, not host-shared — so only root (or a deliberate ./install) can
# create it; a confined Claude cannot (H4).
GATE_FLAG_PATH="/etc/claude-code/allow-unwrapped"
# Codex's equivalent of Claude's managed-settings layer. requirements.toml is
# the HARD constraint tier — admin-controlled, highest precedence, and able to
# carry hooks inline; managed_config.toml is the SOFT default tier. Same
# /etc-not-the-rw-workspace discipline as Invariants 4 and 5: both are
# read-only inside the sandbox, and Codex's project-scoped `.codex/config.toml`
# (which IS inside the rw workspace, and so is attacker-writable from inside
# the jail) cannot override either.
# Codex ships as a PACKAGE, not a lone binary: bin/codex plus ripgrep
# (codex-path/rg) and its own bwrap/zsh helpers (codex-resources/) that the
# vendor's own validity check requires to sit together. So the whole release
# directory is relocated, and the binary is exec'd from inside it.
CODEX_DIST_DIR="/usr/libexec/claude-sandbox/codex-dist"
CODEX_REAL_PATH="$CODEX_DIST_DIR/bin/codex"
CODEX_ETC="/etc/codex"
CODEX_REQUIREMENTS="$CODEX_ETC/requirements.toml"
CODEX_MANAGED_CONFIG="$CODEX_ETC/managed_config.toml"
# First line of any file this installer owns. Its absence means the file is
# somebody else's (a real enterprise policy), and we refuse to rewrite it.
CODEX_MARKER="# Managed by claude-sandbox — do not edit by hand."
USER_SL_CMD='bash $HOME/.claude/statusline-command.sh'

# install_guard_scripts: place the guard scripts off the user's PATH and
# off the sandbox rw set (same neighbourhood as the relocated real
# binary). Root-owned, ro inside the sandbox. The /verify-sandbox phase-1
# battery rides along for the same tamper-resistance (it's not a hook,
# just an off-PATH script the command invokes by absolute path).
install_guard_scripts() {
    install_file "$SCRIPT_DIR/sandbox-verify.sh"          "$(prefixed "$VERIFY_PATH")"
    install_file "$SCRIPT_DIR/sandbox-gate.sh"            "$(prefixed "$GATE_PATH")"
    install_file "$SCRIPT_DIR/verify-sandbox-battery.sh"  "$(prefixed "$BATTERY_PATH")"
}

# wire_gate_flag: stamp (DANGEROUSLY_ALLOW_CLAUDE_SANDBOX_UNWRAPPED=1) or remove the ROOT-OWNED gate
# escape-hatch flag the UserPromptSubmit gate checks. The flag REPLACES the
# old CLAUDE_SANDBOX_ALLOW_UNWRAPPED env hatch, which a confined Claude could
# forge by writing ~/.claude/settings.json's "env" block (deep-review H4).
# Living under /etc — root-owned, ro inside the sandbox, NOT host-shared —
# the flag can only be created by the operator (or a deliberate ./install),
# never from inside the jail. State is fully driven by the env seam so a
# re-install with it unset removes a previously-stamped flag (fail-closed
# default restored). Mode 0644 — it's a presence marker; only existence
# matters.
wire_gate_flag() {
    local flag; flag="$(prefixed "$GATE_FLAG_PATH")"
    if [ "$ALLOW_UNWRAPPED" = "1" ]; then
        mkdir -p "$(dirname "$flag")"
        : > "$flag"
        chmod 0644 "$flag"
        echo "claude-sandbox: WARNING — gate escape hatch ENABLED ($flag); the UserPromptSubmit gate is warn-only, unwrapped claude is permitted. Re-run install with DANGEROUSLY_ALLOW_CLAUDE_SANDBOX_UNWRAPPED unset to restore fail-closed." >&2
    else
        rm -f "$flag"
    fi
}

# wire_managed_settings: idempotent jq merge of the guard into the
# managed-settings policy file. Adds (deduped by command basename):
#   - SessionStart    → sandbox-verify.sh (full battery + loud warn)
#   - UserPromptSubmit → sandbox-gate.sh  (lean fail-closed gate)
# and sets env.DISABLE_AUTOUPDATER=1 + autoUpdates=false (root-cause
# removal: the in-container updater is what re-arms the bypass). Foreign
# keys — e.g. a real enterprise admin's org policy — are preserved, so
# we merge rather than own the file. A non-JSON file is warned-and-
# skipped (never brick install over a file we don't exclusively own).
# We deliberately do NOT set allowManagedHooksOnly — that would also
# block the owner's own user/project hooks. Re-running is byte-stable.
wire_managed_settings() {
    local settings; settings="$(prefixed "$MANAGED_SETTINGS")"
    mkdir -p "$(dirname "$settings")"

    if [ -f "$settings" ] && ! jq -e . "$settings" >/dev/null 2>&1; then
        cat >&2 <<EOF
claude-sandbox: WARNING — $settings is not valid JSON.
Skipping the managed integrity-guard merge. Hand-add to "hooks":
  "SessionStart":    [{"hooks":[{"type":"command","command":"$VERIFY_CMD"}]}]
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$GATE_CMD"}]}]
and set "env":{"DISABLE_AUTOUPDATER":"1"}, "autoUpdates": false.
EOF
        return 0
    fi

    local input merged tmp
    if [ -f "$settings" ]; then input="$(cat "$settings")"; else input='{}'; fi

    # jq program: idempotent merge of the integrity guard + updater-disable into
    # the managed-settings policy. Dedup by command basename; foreign keys (a
    # real admin's org policy) are preserved. $verify/$gate are jq --arg vars.
    local merge_program='
        .hooks //= {}
        | .hooks.SessionStart //= []
        | .hooks.UserPromptSubmit //= []
        | .env //= {}
        | .env.DISABLE_AUTOUPDATER = "1"
        | .autoUpdates = false
        | (if (.hooks.SessionStart | any(.[].hooks[]?; (.command // "") | endswith("sandbox-verify.sh")))
             then . else .hooks.SessionStart += [{hooks:[{type:"command",command:$verify}]}] end)
        | (if (.hooks.UserPromptSubmit | any(.[].hooks[]?; (.command // "") | endswith("sandbox-gate.sh")))
             then . else .hooks.UserPromptSubmit += [{hooks:[{type:"command",command:$gate}]}] end)
    '
    merged="$(printf '%s' "$input" | jq --arg verify "$VERIFY_CMD" --arg gate "$GATE_CMD" "$merge_program")"

    tmp="$(mktemp "$settings.XXXXXX")"
    printf '%s\n' "$merged" > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$settings"
}

# wire_codex_managed: deliver the SAME integrity guard to Codex through its
# managed-configuration layer, so `codex` is guarded exactly like `claude`.
#
#   /etc/codex/requirements.toml   → SessionStart + UserPromptSubmit hooks
#                                    pointing at the same two /usr/libexec
#                                    scripts (root-owned, off-PATH, ro inside
#                                    the sandbox — so they cannot be rewritten
#                                    to `exit 0` from inside the jail).
#   /etc/codex/managed_config.toml → check_for_update_on_startup = false: the
#                                    same root-cause removal as Claude's
#                                    DISABLE_AUTOUPDATER, because a self-update
#                                    is what re-creates ~/.local/bin/codex and
#                                    re-arms the bypass. Updates become a
#                                    deliberate ./install. (The in-sandbox half
#                                    is CODEX_UPDATE_DISABLED=1, set by the
#                                    shadow.)
#
# UserPromptSubmit is the one Codex event that can stop a turn before the model
# runs, and it blocks on exit 2 — the same contract sandbox-gate.sh already
# implements for Claude, which is why one script serves both.
#
# We deliberately do NOT set allow_managed_hooks_only: it would suppress the
# owner's own user/project hooks, exactly as allowManagedHooksOnly would on the
# Claude side (Invariant 5).
#
# TOML, not JSON, and this repo is bash-only: there is no jq to merge with, so
# rather than half-parse TOML we either own the file or we do not touch it. A
# file we wrote (first line == CODEX_MARKER) is rewritten byte-stably; a file
# somebody else wrote is left alone with a loud warning and the exact snippet
# to paste. Bricking a site's real Codex policy would be worse than not wiring
# the guard — the same call the non-JSON managed-settings path makes.
codex_requirements_body() {
    cat <<TOML
$CODEX_MARKER
#
# claude-sandbox integrity guard for the Codex CLI. These hooks assert that
# codex is running inside the bwrap shadow, and fail closed when it is not.
# Removing them re-opens the silent-bypass hole; re-run claude-sandbox/install
# to restore. See: https://diamondlightsource.github.io/claude-sandbox/

[[hooks.SessionStart]]

[[hooks.SessionStart.hooks]]
type = "command"
command = "bash $VERIFY_PATH --agent codex"

[[hooks.UserPromptSubmit]]

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "bash $GATE_PATH --agent codex"
TOML
}

codex_managed_config_body() {
    cat <<TOML
$CODEX_MARKER
#
# Root-cause removal of the update-driven sandbox bypass: a Codex self-update
# re-creates ~/.local/bin/codex, which would then resolve ahead of the shadow.
# Updating is a deliberate \`claude-sandbox update\` / ./install instead.
check_for_update_on_startup = false
TOML
}

# install_owned_toml BODY_FN DEST LABEL: write a file this installer owns,
# byte-stably (so a re-run is a true no-op), refusing to clobber one it did
# not write.
install_owned_toml() {
    local body_fn="$1" dest="$2" label="$3" tmp
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && [ "$(head -n 1 "$dest")" != "$CODEX_MARKER" ]; then
        {
            echo "claude-sandbox: WARNING — $dest exists and was not written by us."
            echo "Leaving it untouched, so the $label is NOT active on this host."
            echo "To apply it, merge this in by hand:"
            echo
            "$body_fn" | tail -n +2
        } >&2
        return 0
    fi
    tmp="$(mktemp "$dest.XXXXXX")"
    "$body_fn" > "$tmp"
    chmod 0644 "$tmp"
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$dest"
}

wire_codex_managed() {
    install_owned_toml codex_requirements_body \
        "$(prefixed "$CODEX_REQUIREMENTS")" "codex integrity guard"
    install_owned_toml codex_managed_config_body \
        "$(prefixed "$CODEX_MANAGED_CONFIG")" "codex updater-disable"
}

# codex_owned_or_skipped DEST: does the file at DEST actually carry OUR policy?
# install_owned_toml deliberately refuses to overwrite a site's own Codex policy
# file, so on such a host the guard is NOT in force — and the install summary
# must say so rather than assert a guard that was skipped. Read back from disk
# rather than threaded through a return code: disk is the ground truth, and
# install_owned_toml returning non-zero would abort main() under `set -e`.
codex_owned_or_skipped() {
    local dest="$1"
    if [ -f "$dest" ] && [ "$(head -n 1 "$dest")" = "$CODEX_MARKER" ]; then
        printf 'active'
    else
        printf 'NOT ACTIVE — a foreign policy file is in place; merge by hand'
    fi
}

# wire_user_statusline: the user-scope ~/.claude/settings.json now holds
# only the statusline PREFERENCE (set-only-if-absent + script seeded
# only-if-absent — never stomp an owner's own). The integrity guard does
# NOT live here anymore. To migrate an earlier install that DID put the
# guard in user-scope, prune any of our guard-hook entries so the guard
# has a single authoritative home (managed settings) and never double-
# fires. Foreign hooks are preserved. Non-JSON → warn-and-skip.
wire_user_statusline() {
    local settings="$USER_HOME/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"

    local sl_src="$REPO_ROOT/.claude/statusline-command.sh"
    if [ -f "$sl_src" ]; then
        # Seed-only-if-absent by default (never stomp an owner's own);
        # STATUS=1 forces the clone's copy to win (content-compared).
        if [ "$FORCE_STATUSLINE" = "1" ]; then
            install_file "$sl_src" "$USER_HOME/.claude/statusline-command.sh"
        else
            install_file_if_absent "$sl_src" "$USER_HOME/.claude/statusline-command.sh"
        fi
    fi

    if [ -f "$settings" ] && ! jq -e . "$settings" >/dev/null 2>&1; then
        echo "claude-sandbox: WARNING — $settings is not valid JSON; skipping statusline wiring + interim-guard prune." >&2
        return 0
    fi

    local had_file=false input merged tmp sl_present=false
    [ -f "$settings" ] && had_file=true
    if [ "$had_file" = true ]; then input="$(cat "$settings")"; else input='{}'; fi
    if [ -f "$USER_HOME/.claude/statusline-command.sh" ]; then sl_present=true; fi

    # jq program: prune any legacy user-scope guard hooks (the guard now lives
    # only in managed settings, so it never double-fires) and set the statusline
    # preference if absent. Foreign hooks survive. $sl/$slp are jq vars.
    local prune_program='
        (if .hooks.SessionStart    then .hooks.SessionStart    |= map(select((any(.hooks[]?; (.command // "") | endswith("sandbox-verify.sh"))) | not)) else . end)
        | (if .hooks.UserPromptSubmit then .hooks.UserPromptSubmit |= map(select((any(.hooks[]?; (.command // "") | endswith("sandbox-gate.sh"))) | not)) else . end)
        | (if ($slp and .statusLine == null) then .statusLine = {type:"command",command:$sl} else . end)
    '
    merged="$(printf '%s' "$input" | jq --arg sl "$USER_SL_CMD" --argjson slp "$sl_present" "$prune_program")"

    # Don't create an empty {} settings on a fresh home that has no
    # statusline source to wire.
    if [ "$had_file" = false ] && printf '%s' "$merged" | jq -e '. == {}' >/dev/null 2>&1; then
        return 0
    fi

    tmp="$(mktemp "$settings.XXXXXX")"
    printf '%s\n' "$merged" > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$settings"
}

main() {
    probe_or_refuse
    # Shadow first: with /usr/local/bin/claude in place before the
    # official installer runs, any `claude` lookup during the rest of
    # install resolves (and bash-hashes) to the shadow path, even if
    # the shadow itself transiently fails because bwrap or the real
    # binary haven't landed yet.
    install_file "$SCRIPT_DIR/claude-shadow" "$(prefixed /usr/local/bin/claude)"
    # The SAME shadow under the other agent's name — it dispatches on argv[0].
    # Placed unconditionally, even when WITH_CODEX=0 or the download failed:
    # the shadow must own `codex` on $PATH before the vendor's installer can
    # claim it (Invariant 1). An unbacked shadow loud-fails with instructions;
    # an unshadowed vendor binary would silently run outside the jail.
    install_file "$SCRIPT_DIR/claude-shadow" "$(prefixed /usr/local/bin/codex)"
    # The helper CLI (gh-auth, glab-auth, update, verify, version) —
    # on PATH so it works after the install clone is deleted.
    install_file "$SCRIPT_DIR/claude-sandbox" "$(prefixed /usr/local/bin/claude-sandbox)"
    apt_install
    probe_userns_or_refuse
    link_terminal_config
    install_claude_binary
    install_codex_binary
    ensure_cred_dirs
    install_conf
    stamp_version
    # GLOBAL integrity guard via the MANAGED settings layer: scripts off
    # the rw set in /usr/libexec, hook entries + updater-disable in
    # /etc/claude-code/managed-settings.json (highest precedence, not
    # removable by editing ~/.claude). Fires in every cwd. The user-scope
    # settings.json keeps only the statusline preference (and is migrated
    # off any earlier user-scope guard).
    install_guard_scripts
    wire_managed_settings
    wire_codex_managed
    wire_gate_flag
    wire_user_statusline

    echo "claude-sandbox: install complete."
    echo "  shadow:      $(prefixed /usr/local/bin/claude), $(prefixed /usr/local/bin/codex)"
    echo "  cli:         $(prefixed /usr/local/bin/claude-sandbox) ($(cat "$(prefixed "$VERSION_FILE_PATH")"))"
    echo "  real claude: $(prefixed /usr/libexec/claude-sandbox/claude)"
    echo "  real codex:  $(prefixed "$CODEX_REAL_PATH") $([ -x "$(prefixed "$CODEX_REAL_PATH")" ] && echo 'installed (whole package, ro in sandbox)' || echo 'NOT installed — `codex` will refuse to launch')"
    echo "  config:      $(prefixed /etc/claude-sandbox.conf)"
    echo "  guard:       $(prefixed "$VERIFY_PATH"), $(prefixed "$GATE_PATH") (off-PATH, ro in sandbox)"
    echo "  battery:     $(prefixed "$BATTERY_PATH") (off-PATH, ro in sandbox; /verify-sandbox phase 1)"
    echo "  managed:     $(prefixed "$MANAGED_SETTINGS") (SessionStart + UserPromptSubmit + DISABLE_AUTOUPDATER)"
    echo "  codex guard: $(prefixed "$CODEX_REQUIREMENTS") (SessionStart + UserPromptSubmit) — $(codex_owned_or_skipped "$(prefixed "$CODEX_REQUIREMENTS")")"
    echo "  codex conf:  $(prefixed "$CODEX_MANAGED_CONFIG") (updater off) — $(codex_owned_or_skipped "$(prefixed "$CODEX_MANAGED_CONFIG")")"
    echo "  gate hatch:  $(prefixed "$GATE_FLAG_PATH") $([ "$ALLOW_UNWRAPPED" = "1" ] && echo 'PRESENT — gate warn-only (unwrapped permitted)' || echo 'absent — gate fail-closed')"
    echo "  statusline:  $USER_HOME/.claude/settings.json (preference only)"
    echo "  workspace:   $WORKSPACE"
    echo "  run \`claude-sandbox verify\` for the live battery (or \`/verify-sandbox\` inside Claude in a claude-sandbox clone for the full audit)."
}

# Source guard: the container image build (see Dockerfile) re-uses the
# install functions by sourcing this file. The guard keeps main() from
# auto-running in that case.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
