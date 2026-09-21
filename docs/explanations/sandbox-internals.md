# Sandbox internals: design rationale

This page explains *why* several of the sandbox's more subtle binds and
masks are shaped the way they are. It assumes you already know the
shape of the sandbox from the [threat model](threat-model.md) and the
list of [deliberately-exposed paths](../reference/deliberately-exposed.md);
here we cover the reasoning behind six decisions where the obvious
implementation would have been wrong or leaky.

The baseline is *strict-under-`$HOME` by inversion*: the shadow emits
`--tmpfs $HOME` to wipe the home directory, then binds back only what
Claude legitimately needs. Anything not enumerated stays masked. The
rationale below is mostly about *which* things are bound back, and how.

## The XDG split: data bulk-bound, config strict-allowlist

The bind-back list does not treat `$HOME` uniformly — it splits by XDG
category, and the two halves have opposite polarity on purpose.

`$HOME/.config/` keeps a **strict allowlist**: `gh`, `glab-cli`, and
nothing else. Credentials live here by XDG contract — `gcloud`,
`helm` repo auth, `gh` tokens, `oauth2-proxy` cookies, and anything
secret a tool persists. Keeping `.config/` masked-by-default means a
new credentialed tool that drops files under
`$HOME/.config/<newtool>/` is hidden for free, with no allowlist edit
required. The forge token dirs are the only exceptions because Claude
needs them to push code, and they are skipped entirely under
`CLAUDE_SANDBOX_NO_FORGE=1`.

`$HOME/.local/share/` and `$HOME/.cache/` go the other way and are
**bulk-bound**. These are XDG data and cache locations — plugin trees,
binary registries, download caches. Bulk-binding them means
host-installed `helm` plugins, `kubectl`/`krew` plugins, the `cargo`
registry, `npm` global state, `uv`-managed Pythons, and similar all
appear inside the sandbox without each requiring an allowlist
addition. The forward-compat bet is explicit: it rests on XDG
discipline. A tool that stores credentials under
`~/.local/share/<tool>/` instead of `~/.config/<tool>/` would leak
them into the sandbox. Audit when you add such a tool.

Two sub-directories under `.local/share/` are re-masked with a tmpfs
overlay so Claude Code's *own* runtime writes stay ephemeral rather
than escaping onto the host:

- `applications/` — Claude Code drops a `.desktop` URL handler here on
  first launch. Binding the host's directory would register the
  in-sandbox `claude` as a URL handler in the host desktop
  environment.
- `claude/` — Claude Code's own versioned binary cache, designed to be
  ephemeral. Binding the host's would collide with the host's `claude`
  install.

`.local/state/` and `.local/bin/` are left as tmpfs. State is
transient by XDG contract, and `.local/bin/` is handled specially —
see [uv bind discipline](#uv-bind-discipline) below.

Pre-XDG dotdir credential stores (`.ssh`, `.aws`, `.gnupg`,
`.docker`, `.kube`, `.azure`, and so on) sit directly under `$HOME`
and are masked by the `--tmpfs $HOME` baseline. The inversion is still
fully in effect at the top level; only `.config/`, `.local/share/`,
and `.cache/` change polarity within it.

## uv bind discipline

The whole `~/.local/bin/` directory is deliberately **not** bound.
Claude Code writes into that directory via tmpfs at runtime, and those
writes are meant to be ephemeral. Only two individual files are bound
back — `uv` and `uvx` — so Python tooling installed via `uv` works
inside the sandbox. (The real `claude` binary is also bound into this
directory, at the conventional `~/.local/bin/claude` path, so Claude
Code's self-inspection sees the location it expects.)

For `uv` to resolve without a full path, `$HOME/.local/bin` is added
to `PATH`. The critical detail is that it is **appended, not
prepended**. PATH resolution scans left to right, so the system
directories (`/usr/local/bin`, `/usr/bin`, …) are searched first. A
malicious binary planted at `~/.local/bin/<sysname>` — for example a
fake `git` or `ls` — therefore cannot hijack a standard command,
because the genuine one in a system directory is found first. The same
appended-not-prepended discipline keeps the `/usr/local/bin/claude`
shadow winning resolution over anything in `~/.local/bin`.

## gitconfig defence-in-depth

The host's system gitconfig at `/etc/gitconfig` is reachable
read-only from inside the sandbox (it comes in via `--ro-bind / /`),
but it is **neutralised for `git`** by setting
`GIT_CONFIG_SYSTEM=/dev/null` in the sandbox environment, alongside
`GIT_CONFIG_GLOBAL=/etc/claude-gitconfig` which points git at the
curated config instead.

An earlier version layered an additional bind-mask over
`/etc/gitconfig` for defence-in-depth. That mask was **removed**. The
reason is that some tools scrub `GIT_*` environment variables before
spawning git — pre-commit's `no_git_env` is the canonical example.
Those tools will see the real host `/etc/gitconfig`, and that is the
*intended* behaviour. The bind-mask broke them without adding
meaningful protection beyond the environment redirect: the redirect
already covers every git invocation that inherits the sandbox
environment, and the tools that bypass the redirect are precisely the
ones that need the real system config. There is no comparable concern
for the per-user config: the host's `/root/.gitconfig` is invisible
under strict-under-`$HOME`, so nothing reaches it in the first place.

## Network-identity disclosure

By default — the egress jail, {ref}`adr-network-egress-jail` — Claude runs
in a *private* network namespace bridged to the internet by `pasta`, with a
routing allowlist that blackholes RFC1918 and the connected subnet. In that
namespace Claude sees only the pasta-mirrored address, gateway, and DNS
resolver, not the host's full interface and routing view.

Host network-identity disclosure applies to the **escape-hatch path**
(`CLAUDE_SANDBOX_EGRESS_JAIL=0`). On that path bwrap omits `--unshare-net`
and inherits the container's host network namespace — the netns is *not*
unshared — so Claude can enumerate the host's interface addresses, routing
table, and DNS resolver via `AF_NETLINK` or ordinary tooling such as
`ip addr`, `ip route`, and reading `/etc/resolv.conf`. (Even on the default
jailed path, `pasta` mirrors the host address, gateway, and DNS resolvers
into the netns, so those resolver and gateway addresses remain visible —
but the host's *full* network identity does not.)

This is **network-identity disclosure, not credential exfiltration**, and
it applies only when the egress jail is disabled
(`CLAUDE_SANDBOX_EGRESS_JAIL=0`). Nothing secret is leaked by it directly.
On the `=0` path it does mean the sandbox is visible to internal services on
the same host network, and can reach them. The practical caveat (for `=0`
only): do not run a local metadata-style credential service on the loopback
or RFC1918 address of a host that also runs an unjailed `claude`, unless you
are comfortable with Claude being able to reach it. With the jail on (the
default), RFC1918 and the connected subnet are blackholed, so Claude cannot
reach a loopback or RFC1918 metadata-style credential service in the first
place — closing exactly this reach is its whole point. `/verify-sandbox`
surfaces the reachability question as an `[INCONCLUSIVE]` adversarial probe
so it stays on the radar rather than being silently forgotten.

## The procfs view

All agents use `--unshare-pid`. Non-GPU sessions retain the read-only outer
`/proc` view and the original `NSpid` nesting check. This needs no extra
devcontainer options, but process IDs in procfs differ from sandbox-local IDs.

GPU mode additionally uses `--proc /proc`. The fresh procfs
shows the sandbox's process tree, with IDs matching the running processes
and threads. This also supports CUDA's `/proc/self/task/<tid>/comm` lookup.
Bubblewrap protects `/proc/sys`, `/proc/sysrq-trigger`, `/proc/irq` and
`/proc/bus` against writes; capability dropping remains enabled. The launcher
also restores the runtime's sensitive proc file and directory masks after
mounting fresh procfs. Rootless Podman must allow that initial mount with
`--security-opt 'unmask=/proc/*'`, which the host launcher supplies only with
`--gpu`.

In GPU mode, check 07 compares the sandbox's PID namespace with the launcher's, checks
local process and thread entries, and checks those kernel controls. The live
test `bash tests/proc_isolation.sh` selects the GPU procfs path even without
GPU hardware. Run it in the outer container from the
checkout with `bwrap` and `gdb` installed, additionally checks that a
disposable outer process is invisible and inaccessible to signalling and
debugger attachment. Add `--cuda` to compile and run the GPU smoke test.

GPU mode fails if it cannot mount fresh procfs; it does not fall back to the
outer view, which cannot support CUDA's thread lookups.

## Egress-jail mechanism: holder netns + pasta-attach

The egress jail ({ref}`adr-network-egress-jail`) is on by default and is
driven by three functions that live inline in the shadow. `egress_jail_enabled`
is the one-line gate (anything but `CLAUDE_SANDBOX_EGRESS_JAIL=0`, including
the `egress-jail` key in `/etc/claude-sandbox.conf`, means on; the env var
wins). `netns_launch` orchestrates the launch: it runs inside `unshare -rn`
(a short-lived **holder** that owns a fresh user+net namespace), waits for the
holder's `/proc/<pid>/ns/net` to appear, then runs `pasta --config-net` against
the holder PID from *outside* the namespace — pasta needs host connectivity to
proxy — and backgrounds it. `netns_holder` runs *inside* the namespace: it
brings up `lo`, waits for the readiness signal, then locks the surgical routing
allowlist before exec'ing the bwrap'd Claude.

The allowlist blackholes `10/8`, `172.16/12`, `192.168/16`, the connected
subnet, and `169.254/16`, then punches back only the gateway, the DNS
resolvers, and the `allow-ip` devices (configured via the repeatable `allow-ip`
key or `CLAUDE_SANDBOX_ALLOW_IP`). Internet, DNS, and the allow-ip devices stay
reachable; everything sideways into RFC1918 and link-local does not. The
ordering is load-bearing: netns -> pasta attach -> routes locked -> Claude.

Why the holder creates the namespace and not bwrap: the container has no
`CAP_NET_ADMIN` to make a netns without a userns, and bwrap keeps *omitting*
`--unshare-net` so it inherits the holder's namespace. The security boundary is
**ancestor-userns ownership, not caplessness**. Inside the jail Claude is *not*
capless — bwrap nests its userns inside the holder's, so Claude has a full
`CapBnd` ceiling (a nested-userns artifact) — but `CapEff` is still 0 because
bwrap runs `--cap-drop ALL`. What contains it is that the netns and its routes
are owned by the holder's *ancestor* userns: route del/punch and device-add all
return `EPERM` from inside. Check 06 asserts `CapEff=0`; checks 19–20 inspect
blackhole routes and representative destinations. Those network checks report
a disabled jail as a pass with a note, so read the result details.

The jail is **fail-closed**: if `/dev/net/tun` (the `--device=/dev/net/tun`
runArg in `devcontainer.json`), `pasta` (apt package `passt`), or `unshare` is
missing, the shadow refuses to launch — naming the fix and the
`CLAUDE_SANDBOX_EGRESS_JAIL=0` escape hatch — rather than falling back to open
egress. Setting `=0` restores the shared-host-netns world of
{ref}`adr-network-egress-open`.

A consequence is that EPICS Channel Access *broadcast* for Claude is gone — a
private netns has no LAN broadcast — so Claude must use a unicast
`EPICS_CA_ADDR_LIST` to the device's `allow-ip`. Normal (non-Claude) shells in
the container keep host networking and broadcast, since the container itself
stays `--network=host`. The wider rationale — lateral-movement containment, and
how this layer meshes with Claude Code's native domain isolation — lives in
[the egress jail and the native
sandbox](threat-model.md#the-egress-jail-and-the-native-sandbox).
