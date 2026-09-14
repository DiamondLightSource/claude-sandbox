#!/usr/bin/env bash
# Git defaults for ordinary shells in the published container. The agent
# shadow generates its own independent config inside the sandbox.

configure_container_git() {
    local host_config="$1" container_config="$2" key value hostname helper
    if [ -f "$host_config" ]; then
        for key in user.name user.email; do
            # Do not import includes, credential helpers or SSH commands.
            if value=$(git config --file "$host_config" --get "$key"); then
                git config --file "$container_config" --replace-all "$key" "$value"
            fi
        done
    fi

    for hostname in github.com gitlab.diamond.ac.uk; do
        helper=gh
        [ "$hostname" != gitlab.diamond.ac.uk ] || helper=glab
        git config --file "$container_config" --replace-all \
            "url.https://$hostname/.insteadOf" "git@$hostname:"
        git config --file "$container_config" --add \
            "url.https://$hostname/.insteadOf" "ssh://git@$hostname/"
        # Reset inherited helpers before using container-scoped credentials.
        git config --file "$container_config" --replace-all \
            "credential.https://$hostname.helper" ''
        git config --file "$container_config" --add \
            "credential.https://$hostname.helper" "!$helper auth git-credential"
    done
}
