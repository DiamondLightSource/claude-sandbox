# Make extra paths writable

By default, the agent can write only to the directory you launch from, plus
configured extra paths.

## With the PyPI launcher

On the host, add a directory to both the container and sandbox:

```bash
claude-sandbox --mount ~/src/shared-lib
```

For an existing project container, use `--recreate --mount ~/src/shared-lib`.
Recreation removes container-local packages and forge logins.

## Inside your own devcontainer

Add absolute paths to `/etc/claude-sandbox.conf` from a container terminal
outside the agent:

```ini
allow-write = /cache
allow-write = /workspaces/sibling-project
```

The paths must already be available inside the container. Missing paths are
skipped. To widen the main writable root instead, set
`workspace-root = /workspaces`; this grants access to every project there.

Changes apply on the next agent launch. Reapply them after installation or
rebuild using your [team setup](sandbox-a-team-devcontainer.md).

## Sockets grant access to services

An `allow-write` path can be a Unix socket. Exposing a socket grants the
agent access to the API behind it, not just the socket file.

**Do not expose the host's Podman or Docker socket.** It lets the agent
create containers with host mounts and escape the sandbox's restrictions.
If a container engine is essential, use a dedicated disposable engine whose
account and data hold nothing sensitive. Bind only its socket, not its whole
runtime directory, which may also contain SSH or keyring sockets.

A client may also need an environment variable such as `DOCKER_HOST`;
see [Pass environment variables](pass-environment-variables.md).

See [Configuration](../reference/configuration.md) for the complete key list.
