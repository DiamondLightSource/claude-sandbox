# Configure the network egress jail

The egress jail runs Claude in its own **IPv4-only** network namespace and
blackholes RFC1918 (`10/8`, `172.16/12`, `192.168/16`), CGNAT (`100.64/10`,
Tailscale et al.), every connected subnet, and link-local (`169.254/16`) so a
compromised or prompt-injected session **cannot pivot to internal hosts or lab
devices** (EPICS IOCs, PMAC) — over IPv4 or IPv6. The internet, DNS, and any IPs
you allow stay reachable. It is **on by default** ({ref}`adr-network-egress-jail`)
and **fail-closed**. Normal, non-Claude shells keep host networking untouched.

For the design rationale and how it meshes with Claude Code's native sandbox,
see [the egress jail and the native sandbox](../explanations/threat-model.md#the-egress-jail-and-the-native-sandbox).

```{include} ../_snippets/clone-note.md
```

## Add the one required container device

The jail needs `/dev/net/tun` in the container. An installer cannot add a
container runArg, so you must add it to your devcontainer yourself:

```json
// .devcontainer/devcontainer.json → runArgs
"runArgs": ["--device=/dev/net/tun"]
```

Rebuild the devcontainer for it to take effect. `install.sh` already installs
`passt` (which provides `pasta`), so that dependency is never the blocker.

**Fail-closed:** if `/dev/net/tun`, `pasta`, or `unshare` is missing while the
jail is on, `claude` **refuses to launch** rather than silently falling back to
open egress. The error names both the fix and the escape hatch.

**Rootful docker cannot host the jail.** If the refusal is `pasta failed to
attach to the netns` and the pasta log shows `Couldn't open user namespace
/proc/<pid>/ns/user: Permission denied`, the container is running under
*rootful* docker, whose namespace-access semantics deny pasta the attach —
lifting seccomp/AppArmor confinement does not help. Run the container under
rootless podman (the supported runtime), or accept the weaker posture of
disabling the jail for that host (see below).

## Keep a lab device or internal forge reachable

Device IPs you still need (an EPICS IOC, a PMAC, your internal GitLab) must be
punched through the blackhole with `allow-ip` in the sandbox config. Edit
`/etc/agent-sandbox.conf` in the container (you are root):

```ini
# /etc/agent-sandbox.conf
allow-ip = 172.23.142.119   # internal GitLab forge
allow-ip = 172.23.1.3       # an EPICS IOC / PMAC
```

One bare IP per line; repeat for multiple devices. The shipped default allows
Diamond's internal GitLab (`172.23.142.119`) so `git push` to the forge keeps
working. `allow-ip` lives in `/etc`, **not** the workspace, so a compromised
session cannot widen its own reach.

The next `claude` launch picks the change up. Edits are per-devcontainer
and not persisted — a rebuild, re-install, or `agent-sandbox update`
restores the shipped defaults, so re-apply afterwards (teams bake a
persistent conf in at install time — see
[Sandbox a team devcontainer](sandbox-a-team-devcontainer.md)).

## Reach services on the host's loopback

`allow-ip` cannot reach `127.0.0.1`: loopback is not routable through the
gateway, and the jail disables pasta's port forwarding. What the jail offers
instead is a relay for chosen TCP ports from the outer container's loopback to
the same ports on the agent's loopback ({ref}`adr-local-port-all-agents`).
The shipped conf relays `1920`, lllm2's model API, through `local-model-port`.
Add ports with `local-port`, one per line, in `/etc/agent-sandbox.conf`:

```ini
local-port = 8082    # lllm2 panel and its experiments API
local-port = 5432    # a local database the agent may query
```

For one session, add ports through the environment instead of editing the
root-owned conf; the two are merged:

```bash
AGENT_SANDBOX_LOCAL_PORTS=8082 claude
```

The outer container must share the services' network namespace: this
repository's devcontainer uses `--net=host`, and the published-image launcher
has `--host-net`. Each relayed port exposes the whole service behind it, so
list only what you would hand the agent outright. Every other localhost port
stays unreachable, and the relays stop with the session.

## Let a browser login reach the agent

Some logins run the other way: the agent opens a small HTTP server on its
own loopback and the provider redirects your browser to
`http://localhost:<port>/...`. Pi's Claude Pro/Max login does this on port
53692 and has no other route. Inside the jail that port is not on the host's
loopback, so the browser tab would spin. The `callback-port` relay
({ref}`adr-callback-port-relay`) listens on the outer container's
`127.0.0.1:<port>` and hands each connection to the same port inside the
agent's loopback. The shipped conf relays 53692; add others with one line
per port:

```ini
callback-port = 1455    # Codex CLI and Pi's Codex login
callback-port = 1456    # Pi's Radius login
```

Or for one session:

```bash
AGENT_SANDBOX_CALLBACK_PORTS=1455 codex
```

Only fixed ports can be relayed. Claude Code's login picks a random port and
offers a code to paste instead, so it needs nothing here. A port may not also
appear as `local-port` or `local-model-port`. If the port is already taken on
the host, by another session or an agent run outside the sandbox, the session
still starts, prints a warning naming the port, and that browser login falls
back to pasting the redirect URL from the browser's address bar. When
nothing inside is listening the browser is refused at once, never held.

The browser must be able to reach the outer container's loopback: on the
same machine that is `--net=host`; from a laptop, VS Code forwards the
detected port automatically. A bridge-mode container needs the port
published on the host loopback first.

## A note on Channel Access for Claude

Claude's private netns has no LAN broadcast domain, so EPICS Channel Access
**auto-discovery does not work for Claude** while jailed — use a unicast
`EPICS_CA_ADDR_LIST`. Normal (non-Claude) shells keep host networking and
broadcast.

## See also

- [Threat model](../explanations/threat-model.md) — why lateral movement is the
  risk this jail addresses, and how it meshes with the native sandbox.
- [Configuration](../reference/configuration.md) — the `egress-jail` / `allow-ip`
  conf keys and the `AGENT_SANDBOX_EGRESS_JAIL` environment variable.
- {ref}`adr-network-egress-jail` — the full design (Design D).
