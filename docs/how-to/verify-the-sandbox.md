# Verify the sandbox

From your project on the host:

```bash
claude-sandbox verify
```

The same command works in a container terminal. It runs the installed battery
directly through the sandbox wrapper: no model, agent login or prompt is needed.
To check another agent's filesystem profile:

```bash
claude-sandbox verify --agent codex
claude-sandbox verify --agent pi
```

The selected profile uses the normal workspace, configuration, mounts and
network jail. Its agent must be installed, but is not started. Inside an
existing sandbox, `claude-sandbox verify` checks that current sandbox instead.

## Read the result

Every check should report `PASS`. A failure names the affected defence.
The command exits with the battery's failure count; zero means all checks
passed. Namespace setup failures also return nonzero.

[Verification checks](../reference/verification-checks.md) explains the checks
and their limits. Checks 19–20 inspect network routes, but treat a disabled
jail as a pass with a note; read those notes as well as the PASS count.

## Full adversarial audit

The repository's `/verify-sandbox` Claude command adds an expanded adversarial
audit. Invoke that slash command from Claude in a source checkout when you
want the agent-driven audit. Its specification is in
`.claude/commands/verify-sandbox.md`.

Ordinary verification uses the installed battery and needs no source checkout.
There are no automatic session or prompt hooks.
