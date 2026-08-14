#!/usr/bin/env bash
# Bash unit test for _git_remote_hostpath in the claude-sandbox helper CLI —
# the function that decides WHICH project `glab-auth` offers to scope a
# token to.
#
# It matters because getting it wrong is silent: a misparsed remote sends
# the user to a token page for the wrong project (or a nonsense URL), and
# they mint a credential believing it is narrower than it is. The failure
# looks like a working prompt.
#
# The CLI has a source guard, so sourcing it defines the helpers without
# dispatching a command. `git` is shadowed by a shell function here, so the
# parsing is tested directly against canned remote URLs — no fixture repos,
# no network, no root.
#
# Run via `bash tests/cli_remote_url.sh`.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO_ROOT/.devcontainer/claude-sandbox/claude-sandbox"

if [ ! -f "$CLI" ]; then
    echo "FAIL: cannot find $CLI" >&2
    exit 1
fi

# shellcheck source=lib.sh
source "$REPO_ROOT/tests/lib.sh"

# The CLI sets `set -euo pipefail` at the top, which we inherit on source.
# Restore the suite's own options afterwards: a helper returning non-zero is
# a result to assert on, not a reason to abort the run.
# shellcheck source=../.devcontainer/claude-sandbox/claude-sandbox
source "$CLI"
set +e
set -uo pipefail

# Shadow git: _git_remote_hostpath only ever calls `git remote get-url
# origin`. REMOTE_URL is the canned answer; empty means "no origin", which
# is what git exits non-zero for.
REMOTE_URL=""
git() {
    if [ "${1:-}" = "remote" ] && [ -n "$REMOTE_URL" ]; then
        printf '%s\n' "$REMOTE_URL"
        return 0
    fi
    return 1
}

# parses URL EXPECTED — assert the helper maps URL to "<host>\t<path>",
# or to the literal NONE when it declines to parse.
parses() {
    local url="$1" expected="$2" got
    REMOTE_URL="$url"
    got="$(_git_remote_hostpath)" || got="NONE"
    assert_eq "${url:-<no origin>}" "$expected" "$(printf '%s' "$got" | tr '\t' ' ')"
}

H=gitlab.diamond.ac.uk

# --- The shapes a DLS clone actually has ---------------------------------
parses "https://$H/controls/ioc/bl19i-va-ioc-01.git" "$H controls/ioc/bl19i-va-ioc-01"
parses "https://$H/controls/ioc/bl19i-va-ioc-01"     "$H controls/ioc/bl19i-va-ioc-01"
# Nested subgroups are normal at DLS and must survive intact — truncating to
# the first two segments would point at a different project's token page.
parses "https://$H/a/b/c/d/project.git"              "$H a/b/c/d/project"

# --- ssh / scp-like: the shadow forbids SSH for git, but a user's clone may
#     still carry an SSH remote, and we must still identify the project ----
parses "git@$H:controls/ioc/thing.git"               "$H controls/ioc/thing"
parses "ssh://git@$H/controls/ioc/thing.git"         "$H controls/ioc/thing"
parses "ssh://git@$H:2222/controls/ioc/thing.git"    "$H controls/ioc/thing"

# --- Credentials embedded in the URL must not be read as the host --------
parses "https://someone@$H/group/project.git"        "$H group/project"
parses "https://user:tok@$H/group/project.git"       "$H group/project"
parses "https://$H:8443/group/project.git"           "$H group/project"

# --- Other forges are parsed fine; glab-auth compares the host itself ----
parses "https://github.com/DiamondLightSource/claude-sandbox.git" \
    "github.com DiamondLightSource/claude-sandbox"

# --- Shapes with no project to scope to ----------------------------------
parses ""                          NONE   # no origin / not a git repo
parses "https://$H"                NONE   # host only, no path
parses "https://$H/"               NONE   # trailing slash, still no path
parses "/srv/git/bare-repo.git"    NONE   # local path remote
parses "file:///srv/git/repo.git"  NONE   # file:// has no host

finish cli_remote_url
