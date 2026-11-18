# Claude Code at DLS

## Policy

You must use **claude-sandbox** when running Claude Code on DLS workstations,
to prevent unauthorised access to your and Diamond's files, or accidental
leaking of credentials. Running Claude Code directly on the workstation outside the sandbox is not
permitted. We will soon enforce this requirement through enterprise settings.

## Install and run

In a normal terminal on your DLS Linux workstation:

```bash
module load uv
uv tool install claude-sandbox
cd /path/to/my-project
claude-sandbox
```

The launcher pulls the prebuilt image and starts Claude inside the sandbox.
Log in when prompted. Your project is writable, and your agent login and
memory persist. Run `claude-sandbox` in the same directory for later sessions.

:::{note}
If you already work inside your project's devcontainer (for example with
VS Code's **Reopen in Container**), follow
[Use the sandbox in a devcontainer](../how-to/use-the-sandbox-in-a-devcontainer.md)
instead of the steps above.
:::

## Why use the sandbox?

An agent can run commands and edit files. Prompt injection can steer it through
malicious instructions hidden in content it reads, and even a well-intentioned
prompt can lead to unintended actions. On a workstation, either can expose SSH
keys, tokens, IDE state and facility networks.

The [threat model](../explanations/threat-model.md) describes these risks in
more detail.

The launcher runs on the host; the agent runs inside its container and
bubblewrap jail.

The sandbox hides your workstation credentials, restricts which files Claude
can change, and blocks access to internal networks unless you explicitly allow
a destination. The wrapper launches Claude inside the
sandbox within the configured container.

Claude can still access your project, its own login credentials, any forge
tokens you provide, and the internet. The sandbox limits the damage an agent
can do; it does not make every action safe.

## Push to GitHub or Diamond GitLab

Open a terminal in the sandbox container, then authenticate and start Claude:

```bash
claude-sandbox shell
claude-sandbox gh-auth   # GitHub, if needed
claude-sandbox glab-auth # Diamond GitLab, if needed
claude
```

Use a short-lived token restricted to the project.
[Authenticate with forges](../how-to/authenticate-with-forges.md) explains
token permissions. The default network configuration allows Diamond GitLab.

## Stay current

Run in your project directory:

```bash
uv tool upgrade claude-sandbox
claude-sandbox --recreate
```

Recreation removes container-local packages and forge logins; project files
and shared agent settings remain. Repeat recreation for other projects when
you want them to use the new version.

