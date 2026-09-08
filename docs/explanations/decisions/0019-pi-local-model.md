(adr-pi-local-model)=
# 19. Add Pi and an explicit single-port localhost relay

## Status

Proposed.

## Context

Pi supports cloud providers and local OpenAI-compatible servers. lllm2 starts
a single-model llama.cpp server bound to `127.0.0.1:1920`. The agent's network
namespace has its own loopback, so allowing an RFC1918 address does not make
that server reachable. Mapping the entire host loopback would grant access to
unrelated services.

Pi has a standalone Linux release and its own `~/.pi/agent` store, but no
equivalent to the managed prompt-hook policies used by Claude and Codex.

## Decision

Extend ADR 0018's shared shadow with a Pi profile. Install a pinned,
checksum-verified standalone release under the read-only `/usr/libexec` tree;
keep the wrapper on PATH even when its optional download is skipped or fails.
Bind and persist only Pi's store for Pi sessions. Use Pi's own authentication
and model picker, and provide a helper to configure lllm2 without guessing its
allocated context window. A fixed Bash launcher checks the sandbox markers
before starting Pi; it is a launch guard, not a managed per-prompt hook.

Add `local-model-port` in the operator-controlled sandbox configuration,
disabled by default and used only for Pi. A host-side `socat` forwards a private
Unix socket to the configured port on `127.0.0.1`. A second `socat` in the
holder's network namespace forwards a loopback listener to that socket. bwrap
masks the host socket under `/tmp`; both relays remain outside the agent's PID
namespace. Each relay owns a process
group so cleanup also terminates forked streaming connections. No additional
IP route, firewall capability, GPU mount or model installation is needed.

Make pasta's port forwarding explicit for **all agents**: `-t none -u none
-T none -U none --no-map-gw`. In the tested Ubuntu 24.04 pasta package, default
automatic forwarding exposed other host-loopback listeners and occupied the
intended relay port. Gateway mapping also bypasses the intent of the pinned
gateway route. Disabling those shortcuts preserves ordinary outbound traffic
and the existing dedicated DNS forwarder. This supplements ADR 0015's routing
policy; routes alone do not restrict socket forwarding performed by pasta.

## Consequences

- The outer container must share the server's network namespace for an
  external localhost server; the existing devcontainer uses host networking,
  and the published-image launcher supports `--host-net`.
- The selected TCP port exposes the entire service, including any management
  endpoints it serves. It is not an HTTP path filter.
- The port stays available throughout a Pi session to support `/model`
  switching. It does not depend on which provider is currently selected.
- Automatic forwarding of agent listeners back onto the outer host is also
  disabled. Workflows that depended on pasta discovering listening ports need
  an explicit exposure mechanism outside this feature.
- All providers authenticated in Pi share Pi's credential store. Stores from
  other coding agents remain hidden.
- A separate, deliberately unwrapped Pi installation is not protected by a
  vendor-managed guard. Document this difference instead of claiming parity.
- Namespace tests cover streaming, other localhost ports, gateway mapping,
  routing, normal exit and signal cleanup. The image tests exercise a real Pi
  release making a streamed tool call against a deterministic local server.
