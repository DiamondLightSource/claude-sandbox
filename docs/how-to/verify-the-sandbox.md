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

The shipped `verify-sandbox` skill adds an expanded adversarial audit in
Claude, Codex and Pi. Ask the agent to use that skill (or invoke
`/verify-sandbox` in Claude). It runs the installed battery first, then tries
ten adversarial probes only if all checks pass. No source checkout is needed.
The workflow lives in `skills/verify-sandbox/SKILL.md`.

After updating an existing installation, start a fresh agent session to get
the new skill mount. Remove obsolete personal `verify-sandbox` commands or
skills so there is only one maintained audit workflow.

Ordinary verification uses the installed battery and needs no source checkout.
There are no automatic session or prompt hooks.
