# Verify the sandbox

From your project on the host, open a container shell and run the verifier:

Already in a devcontainer with the sandbox installed? Skip `claude-sandbox shell`
and `exit`; the verification command is identical.

```bash
claude-sandbox shell        # Skip if already in your devcontainer terminal
claude-sandbox verify
exit                       # Only if you opened the shell above
```

Run the helper outside the agent. It launches a sandboxed Claude session to
run the battery; agent authentication is required.

For another agent, use `claude-sandbox verify --agent codex` or
`claude-sandbox verify --agent pi` inside the container.

## Read the result

Every check should report `PASS`. A failure names the affected defence.
[Verification checks](../reference/verification-checks.md) explains the checks
and their limits. Checks 19–20 inspect network routes, but treat a disabled
jail as a pass with a note; read those notes as well as the PASS count.

The helper opens an interactive agent session. For a direct result inside an
already sandboxed agent's shell tool, run:

```bash
bash /usr/libexec/claude-sandbox/verify-sandbox-battery.sh
```

The battery itself exits non-zero on failure. Do not treat the interactive
helper's exit status as an automatic CI assertion of the battery's result.

## Full adversarial audit

In a claude-sandbox source checkout, `claude-sandbox verify` also selects
the repository's `/verify-sandbox` command for an expanded audit.
You can invoke that slash command from Claude in the checkout.

Ordinary project installations get the installed battery without needing
a clone. The full specification lives in `.claude/commands/verify-sandbox.md`.

Run verification after installation or configuration changes. There are no
automatic session or prompt hooks.
