# Claude Code at DLS

## Policy

You must use **claude-sandbox** when running Claude Code on DLS workstations.
Running Claude Code directly on the workstation outside the sandbox is not
permitted. We will soon enforce this requirement through enterprise settings.

## Install and run

On your DLS Linux workstation, outside any container:

```bash
module load uv
uv tool install claude-sandbox
cd /path/to/my-project
claude-sandbox
```

The launcher pulls the prebuilt image and starts Claude inside the sandbox.
Log in when prompted. Your project is writable, and your agent login and
memory persist. Run `claude-sandbox` in the same directory for later sessions.

:::{note} Already use a project devcontainer?
That is often the preferred route: Claude can use your project's existing
tooling. [Install the sandbox there](../how-to/sandbox-a-team-devcontainer.md)
and run `claude` directly. In the recipe below, skip `claude-sandbox shell`;
run the remaining commands in your normal devcontainer terminal,
outside an agent session.
:::

## Why use the sandbox?

An agent can run commands and edit files. Prompt injection can steer it through
malicious instructions hidden in content it reads, and even a well-intentioned
prompt can lead to unintended actions. On a workstation, either can expose SSH
keys, tokens, IDE state and facility networks.

The launcher runs on the host; the agent runs inside its container and
bubblewrap jail.

The sandbox hides your workstation credentials, restricts which files Claude
can change, and blocks access to internal networks unless you explicitly allow
a destination. The wrapper launches Claude inside the
sandbox within the configured container.

Claude can still access your project, its own login credentials, any forge
tokens you provide, and the internet. The sandbox limits the damage an agent
can do; it does not make every action safe. See the
[threat model](../explanations/threat-model.md) for the full boundaries.

## Push to GitHub or Diamond GitLab

In a container terminal, authenticate and start Claude:

```bash
claude-sandbox shell     # Skip if already in your devcontainer terminal
claude-sandbox gh-auth   # GitHub, if needed
claude-sandbox glab-auth # Diamond GitLab, if needed
claude
```

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
