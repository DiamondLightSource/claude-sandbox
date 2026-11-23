# Claude Code at DLS

## Policy

You must use **claude-sandbox** when running Claude Code on DLS workstations.
It prevents unauthorised access to your files and Diamond's, and the
accidental leaking of credentials.

## What the sandbox does

Claude Code runs commands and edits files for you. Without a sandbox it can do
anything you can: read any file in your home directory, use your SSH keys and
passwords, and reach any machine on Diamond's network. It could misuse that
access by mistake, or because of instructions hidden in a web page or file it
reads.

claude-sandbox runs Claude in a separate, locked-down environment on your
workstation:

- It can only see your project folder. The rest of your home directory, your
  SSH keys and other credentials are hidden from it.
- It can only change files inside your project folder.
- It cannot reach machines on Diamond's internal network, apart from Diamond
  GitLab, unless you allow them.

Claude can still read and change everything in your project, use the
internet, and use its own login and any GitHub or GitLab token you give it.
So keep secrets out of the project folder, and still review what Claude does:
the sandbox limits the damage it can do, but it doesn't make every action
safe.

The [threat model](../explanations/threat-model.md) explains what the sandbox
protects against, and why, in more detail.

## Install and run

In a normal terminal on your DLS Linux workstation:

```bash
module load uv
uv tool install claude-sandbox
cd /path/to/my-project
claude-sandbox
```

Change `/path/to/my-project` to the folder you want Claude to work on, for
example a git repository. Claude can see everything in the folder you start
in, so don't run it in your home directory.

The first run downloads the sandbox, which can take a few minutes, then
starts Claude. Log in when prompted. Next time, run `claude-sandbox` in the same
folder; you stay logged in.

:::{note}
If you use devcontainers, follow
[Use claude-sandbox inside your existing devcontainer](../tutorials/use-claude-sandbox-in-your-devcontainer.md).
:::

## Push to GitHub or Diamond GitLab

Run `claude-sandbox shell` to get a terminal inside the sandbox, then log in
and start Claude:

```bash
claude-sandbox shell
claude-sandbox gh-auth   # GitHub, if needed
claude-sandbox glab-auth # Diamond GitLab, if needed
claude
```

Use a short-lived token restricted to the project. See
[which permissions to give a GitHub or GitLab token](../how-to/authenticate-with-forges.md#choose-permissions).
The sandbox can reach Diamond GitLab by default.

## Stay current

Run in your project folder:

```bash
uv tool upgrade claude-sandbox
claude-sandbox --recreate
```

This rebuilds the sandbox: anything you installed inside it and your GitHub
or GitLab logins are lost; your project files and Claude settings are kept.
Run `claude-sandbox --recreate` in each of your other projects too when you
want them to use the new version.

