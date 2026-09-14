# Claude Code at DLS

## Policy

You must use **claude-sandbox** when running Claude Code on DLS workstations.
Running Claude Code directly on the workstation outside the sandbox is not
permitted. We will enforce this requirement through enterprise settings.

## Install and run

On your DLS Linux workstation, outside any container:

```bash
uv tool install claude-sandbox
cd /path/to/my-project
claude-sandbox
```

If uv is unavailable, run `module load uv` first. You also need rootless
Podman, `/dev/net/tun`, and unprivileged user namespaces; see
[Getting started](../tutorials/getting-started.md) for checks.

The launcher pulls the prebuilt image and starts Claude inside the sandbox.
Log in when prompted. Your project is writable, and your agent login and
memory persist. Run `claude-sandbox` in the same directory for later sessions.
VS Code and a project devcontainer are optional.

:::{note} Already use a project devcontainer?
That is often the preferred route: Claude can use your project's existing
tooling. [Install the sandbox there](../how-to/sandbox-a-team-devcontainer.md)
and run `claude` directly. In the recipes below, skip `claude-sandbox shell`
and `exit`; run the commands between them in your normal devcontainer terminal,
outside an agent session.
:::

## Why use the sandbox?

An agent can run commands, edit files and follow instructions hidden in content
it reads. On a workstation, that can expose SSH keys, tokens, IDE state and
facility networks.

The launcher runs on the host; the agent runs inside its container and
bubblewrap jail.

The sandbox masks host credentials, limits writable paths, and blocks internal
networks except explicitly allowed IPs. Its integrity guard blocks unwrapped
Claude launches inside the configured container. Project files, agent credentials,
forge tokens you provide and allowed services remain accessible to the agent;
internet access is open. See the [threat model](../explanations/threat-model.md).

## Push to GitHub or Diamond GitLab

Open a container shell, authenticate, then return to the host:

```bash
claude-sandbox shell        # Skip if already in your devcontainer terminal
claude-sandbox gh-auth       # GitHub, if needed
claude-sandbox glab-auth     # Diamond GitLab, if needed
exit                       # Only if you opened the shell above
```

Resume with `claude-sandbox` on the host, or `claude` in your devcontainer.

Use a short-lived token restricted to the project.
[Authenticate with forges](../how-to/authenticate-with-forges.md) explains
token permissions. The default network configuration allows Diamond GitLab.

## Stay current

For the host launcher, run in your project directory:

```bash
uv tool upgrade claude-sandbox
claude-sandbox --recreate
```

Recreation removes container-local packages and forge logins; project files
and shared agent settings remain. Repeat recreation for other projects when
you want them to use the new version.

For your own devcontainer, follow [devcontainer upgrades](../how-to/upgrade.md#installed-into-your-own-devcontainer).

## Existing devcontainers and further help

For a project's own toolchain, you can
[install into its devcontainer](../how-to/sandbox-a-team-devcontainer.md)
and run `claude` there. The published image may not contain site-specific
build tools or module environments.

[Devcontainer setup](../tutorials/set-up-a-devcontainer.md) covers persistence
and DLS terminal settings.
[Verify the sandbox](../how-to/verify-the-sandbox.md) explains how to check
a running installation.
