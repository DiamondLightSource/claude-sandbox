(adr-local-port-all-agents)=

# 20. Offer the single-port loopback relay to every agent

Date: 2026-09-10

## Status

Accepted

Supersedes in part {ref}`adr-pi-local-model` (ADR 19), which restricted the
relay to Pi sessions.

## Context

ADR 19 added a `local-model-port` relay so Pi could use an lllm2 model bound
to the outer container's `127.0.0.1:1920` from inside the egress jail. It was
gated to Pi because Pi was the only agent with a local-model use case.

Claude and Codex sessions now have a loopback use case too: driving lllm2's
own panel API (port 8082) to run and compare experiments. Nothing in the jail
lets them do that today. `allow-ip` punches an IP route through the gateway,
which cannot reach loopback, and pasta's port forwarding and gateway mapping
are deliberately disabled for all agents (ADR 19). The only remaining option
was the `CLAUDE_SANDBOX_EGRESS_JAIL=0` escape hatch, which gives the session
the whole host network to reach one local port.

## Decision

Drop the Pi-only gate on `local_model_enabled`. The `local-model-port` key and
the `CLAUDE_SANDBOX_LOCAL_MODEL_PORT` variable now apply to every agent. The
mechanism is unchanged: one relay, one IPv4 loopback port, a private Unix
socket between two `socat` processes, no IP route, no pasta forwarding.

The shipped default stays `1920`, so a Claude or Codex session sees lllm2's
model API on its loopback by default, the same as Pi. The environment variable
already takes precedence over the conf, so one session can relay a different
port (for example `8082` for the lllm2 panel) without editing the root-owned
file. Pi's model discovery at startup remains Pi-only.

## Consequences

- A configured relay is the way to reach one loopback service from any jailed
  session; the jail escape hatch is no longer needed for that.
- Every jailed session now runs the two relay processes when a port is
  configured, and any Claude or Codex session can reach the whole service on
  the shipped port `1920`. That service is a local model server, which the
  threat model does not treat as sensitive; operators who run something else
  there should set `local-model-port = 0` or another port.
- The relay is still single-port: a session relaying `8082` does not also see
  `1920`.
- The conf key keeps its name for compatibility even though it is no longer
  only about models.
- `tests/local_model.sh` runs the real relay probe for both a Pi and a Claude
  profile; `tests/pi.sh` asserts that every agent enables the relay and
  forwards the configured port into the sandbox.
