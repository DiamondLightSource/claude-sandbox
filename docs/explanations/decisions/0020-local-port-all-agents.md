(adr-local-port-all-agents)=

# 20. Relay a set of loopback ports to every agent

Date: 2026-09-10

## Status

Accepted

Supersedes in part {ref}`adr-pi-local-model` (ADR 19), which restricted the
relay to Pi sessions and to a single port.

## Context

ADR 19 added a `local-model-port` relay so Pi could use an lllm2 model bound
to the outer container's `127.0.0.1:1920` from inside the egress jail. It was
gated to Pi because Pi was the only agent with a local-model use case, and to
one port because one was all that case needed.

Other loopback services are legitimate agent targets too: lllm2's own panel
API on 8082 for running and comparing experiments, a local database, a dev
server under test. Nothing in the jail lets a Claude or Codex session reach
any of them. `allow-ip` punches an IP route through the gateway, which cannot
reach loopback, and pasta's port forwarding and gateway mapping are
deliberately disabled for all agents (ADR 19). The only remaining option was
the `AGENT_SANDBOX_EGRESS_JAIL=0` escape hatch, which gives the session the
whole host network to reach one local port.

## Decision

Make the relay a **set of ports for every agent**. `local-model-port` keeps
its meaning as the port Pi discovers a model on and stays in the set; the new
repeatable `local-port` key adds further ports, and `AGENT_SANDBOX_LOCAL_PORTS`
in the environment adds ports for one session. Conf and environment entries
are merged and deduplicated. The Pi-only gate on `local_model_enabled` is
gone.

The mechanism is unchanged per port: one relay, one IPv4 loopback port, a
private Unix socket between two `socat` processes, no IP route, no pasta
forwarding. Only bare port numbers are accepted; the host side is always
`127.0.0.1` on the outer container, so no configuration can turn the relay
into a route to another host. That job stays with `allow-ip`.

The shipped default stays `local-model-port = 1920`, so a Claude or Codex
session sees lllm2's model API on its loopback by default, the same as Pi.
Pi's model discovery at startup remains Pi-only.

## Consequences

- A configured relay is the way to reach loopback services from any jailed
  session; the jail escape hatch is no longer needed for that.
- Every jailed session now runs two relay processes per configured port, and
  any Claude or Codex session can reach the whole service on the shipped port
  `1920`. That service is a local model server, which the threat model does
  not treat as sensitive; operators who run something else there should set
  `local-model-port = 0` or another port.
- Each relayed port exposes the whole service behind it; the relay is not a
  path filter. `local-port` lives in `/etc`, so a compromised session cannot
  add ports for its next launch, and the environment route is only available
  to whoever launches the session.
- The conf key `local-model-port` keeps its name for compatibility even
  though it is now one member of a more general set.
- `tests/local_model.sh` runs the real relay probe with a model port and a
  `local-port` entry, for both a Pi and a Claude profile, and checks that an
  unlisted neighbouring port stays unreachable; `tests/pi.sh` covers merging,
  deduplication, validation and the model-port-zero case.
