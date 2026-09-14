#!/usr/bin/env bash
# Exercise ordinary-shell Git configuration without a container or network.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
# shellcheck source=../container/git-config.sh
source "$HERE/../container/git-config.sh"

TMP="$(mktemp -d)"
register_cleanup "$TMP"
host_config="$TMP/host.gitconfig"
container_config="$TMP/container.gitconfig"
git config --file "$host_config" user.name 'Container Test'
git config --file "$host_config" user.email 'container@example.invalid'
git config --file "$host_config" credential.helper '!false'
git config --file "$host_config" core.sshCommand 'false'
git config --file "$host_config" include.path /must-not-be-included
cp "$host_config" "$TMP/original.gitconfig"
chmod 444 "$host_config"

configure_container_git "$host_config" "$container_config"
assert_eq identity 'Container Test' "$(git config --file "$container_config" user.name)"
assert_eq email 'container@example.invalid' "$(git config --file "$container_config" user.email)"
cmp -s "$host_config" "$TMP/original.gitconfig" && pass || fail 'host config changed'
for key in credential.helper core.sshCommand include.path; do
    if git config --file "$container_config" --get "$key"; then
        fail "host setting imported: $key"
    else
        pass
    fi
done

# Configuration survives restart without duplicate rewrites or lost settings.
git config --file "$container_config" fetch.prune true
configure_container_git "$host_config" "$container_config"
assert_eq 'preserve local settings' true "$(git config --file "$container_config" fetch.prune)"
assert_eq 'no duplicate rewrites' 2 "$(git config --file "$container_config" --get-all url.https://github.com/.insteadOf | wc -l)"

git init -q "$TMP/project"
container_git() {
    GIT_CONFIG_GLOBAL="$container_config" GIT_CONFIG_NOSYSTEM=1 \
        git -C "$TMP/project" "$@"
}
for host in github.com gitlab.diamond.ac.uk; do
    for url in "git@$host:team/project.git" "ssh://git@$host/team/project.git"; do
        container_git remote remove origin 2>/dev/null || true
        container_git remote add origin "$url"
        assert_eq 'SSH remote resolves to HTTPS' "https://$host/team/project.git" \
            "$(container_git remote get-url origin)"
    done
done

# Git's atomic global-config updates (used by gh auth setup-git) must work.
container_git config --global --replace-all credential.https://github.com.helper '!gh auth git-credential'
assert_eq 'global config writable' '!gh auth git-credential' \
    "$(container_git config --global credential.https://github.com.helper)"

# Exercise gh's actual setup path where available; the fixture token is only
# used to select a configured host, with no login or network request.
if command -v gh >/dev/null; then
    GH_TOKEN=fixture-token GH_CONFIG_DIR="$TMP/gh" \
        GIT_CONFIG_GLOBAL="$container_config" GIT_CONFIG_NOSYSTEM=1 \
        gh auth setup-git --hostname github.com
    pass
    # Restore the portable helper spelling for the fake-CLI dispatch below.
    configure_container_git "$host_config" "$container_config"
fi

# A real Git credential request dispatches to the container's CLI helper.
mkdir "$TMP/bin"
for cli in gh glab; do
    printf '#!/bin/sh\n[ "$1 $2 $3" = "auth git-credential get" ] || exit 1\nprintf "username=fixture\\npassword=fixture-token\\n"\n' > "$TMP/bin/$cli"
    chmod +x "$TMP/bin/$cli"
done
for host in github.com gitlab.diamond.ac.uk; do
    credentials=$(printf 'protocol=https\nhost=%s\n\n' "$host" |
        PATH="$TMP/bin:$PATH" GIT_TERMINAL_PROMPT=0 container_git credential fill)
    assert_contains 'forge helper supplies credential' "$credentials" 'password=fixture-token'
done

# Hosts without a Git config still get HTTPS and credential-helper defaults.
configure_container_git "$TMP/absent" "$TMP/no-host.gitconfig"
assert_eq 'no-host default helper' '!gh auth git-credential' \
    "$(git config --file "$TMP/no-host.gitconfig" --get credential.https://github.com.helper)"
finish container_git
