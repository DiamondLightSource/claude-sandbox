(adr-callback-port-relay)=

# 21. Relay fixed OAuth callback ports into the jail

Date: 2026-09-11

## Status

Accepted

Extends {ref}`adr-local-port-all-agents` (ADR 20) with a relay in the
opposite direction. {ref}`adr-pi-local-model` (ADR 19) still governs pasta:
its port forwarding stays disabled for every agent.

## Context

Pi's Claude Pro/Max login opens an HTTP server on `127.0.0.1:53692` inside
the agent's private loopback and asks claude.ai to redirect the browser to
`http://localhost:53692/callback`. Inside the egress jail that loopback is the
agent's own network namespace, so the browser on the host reaches nothing,
and the tab spins until it times out. The authorization code is only in the
URL of that hung tab, and a user who copies the address bar during the spin
gets the previous page's URL instead, whose `code=true` parameter pi then
sends to the token endpoint. Pi offers no alternative: its earlier
code-display flow was dropped upstream in 0.59.0 and the pasted-URL prompt
is the only fallback.

Claude Code needs nothing here. Its login uses a random port but always
offers Anthropic's code-display page. Codex CLI and pi's Codex login share
fixed port 1455 and also offer a device-code flow. Pi's Radius login uses
fixed port 1456; its OpenRouter login picks a random port.

ADR 19 disabled pasta's automatic forwarding in both directions because it
exposed unrelated host-loopback listeners and occupied the relay's port. ADR
20's relay carries connections outward only: the outer socat connects to a
host service, the inner socat listens inside the jail. Nothing in the sandbox
gives a host process a path to a socket the agent opens.

## Decision

Add a **callback-port** relay set: TCP ports on which the outer container's
`127.0.0.1` listens and forwards into the same port on the agent's loopback.
The mechanism is ADR 20's mirrored per port: one private Unix socket under
the jail's `/tmp` relay directory, the outer socat listening on the outer
loopback and connecting to the socket, the inner socat listening on the
socket and connecting to the agent's loopback only when a connection
arrives. No IP route is added and pasta's forwarding stays off.

The set comes from repeatable `callback-port` lines in the root-owned conf
merged with `AGENT_SANDBOX_CALLBACK_PORTS` from the environment,
deduplicated and validated like `local-port`. A port may not appear in both
sets: the outbound relay would hold the port the agent needs, and the
inbound listener would hold the host service's port.

The shipped conf lists `53692` live, because pi's Claude login has no other
route, and shows `1455` and `1456` as commented examples. The relay serves
every agent: a port nothing inside listens on is refused immediately rather
than held open.

Because this end **listens** on the outer loopback, it can collide with a
port already taken there by a second agent session or an unwrapped agent.
The relay fails soft: the session starts without that port, prints a
warning naming it, and the browser fails fast so the redirect URL appears in
the address bar for the pasted-URL fallback. This differs from the outbound
relay, where a relay that cannot start is fatal.

## Consequences

- Pi's `/login` for Claude Pro/Max completes in the browser wherever the
  browser can reach the outer container's loopback: on the same machine
  with `--net=host`, and through VS Code's automatic port forwarding, which
  detects the outer listener, for a remote devcontainer.
- The published image in bridge mode gains nothing until its launcher
  publishes the port on the host loopback; the pasted-URL fallback remains
  the route there.
- This is the first path from the host into the jail. What it grants is
  narrow: a jailed agent can serve TCP on one fixed loopback port to
  processes on the host. The threat model concerns lateral movement outward;
  the realistic misuse here is a compromised agent serving a page to a host
  browser, which is the interaction the OAuth flow relies on anyway. Pi's
  callback checks the OAuth `state`, so a stray request cannot inject a
  code. Any request with a bad state aborts pi's login, a known upstream
  nuisance now reachable from the host loopback.
- Every jailed session on a host with the shipped conf runs two more relay
  processes and holds `127.0.0.1:53692` on the outer loopback. Two
  concurrent sessions cannot both hold it; the second warns and falls back.
- Logins that pick a random port (Claude Code, pi's OpenRouter) cannot use
  a static relay and keep their existing fallbacks.
- `tests/local_model.sh` proves a host-side connection reaches a listener
  inside the jail, that a missing inner listener is refused fast, that a
  neighbouring port is not exposed, that the relay dies with the session,
  and that a taken port fails soft with the warning. `tests/pi.sh` covers
  the shipped default, merging, deduplication, validation and the
  both-ways overlap rejection.
