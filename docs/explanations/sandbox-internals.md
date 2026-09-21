# Sandbox internals

[Architecture](architecture.md) describes the launch sequence. This page
explains the less obvious filesystem and namespace choices.

## The XDG split: data bulk-bound, config strict-allowlist

The wrapper covers `$HOME` with an empty tmpfs, then restores selected paths.
Under `.config`, only the forge stores `gh` and `glab-cli` are restored;
`no-forge` omits those too. New credential stores under `.config` therefore
remain hidden without changes to the wrapper.

`.local/share` and `.cache` are bound as whole directories so plugins, package
registries and tool downloads work without per-tool configuration. Credentials
stored there are exposed. Two `.local/share` directories are masked again:

- `applications`: keeps Claude's desktop URL-handler registration temporary.
- `claude`: keeps its versioned binary cache separate from the outer install.

Other top-level credential directories, such as `.ssh`, `.aws`, `.kube` and
`.gnupg`, remain behind the home mask. See the
[exposure table](../reference/deliberately-exposed.md) for agent state and skills.

## uv bind discipline

Only `uv` and `uvx` are bound back from `~/.local/bin`; the directory itself
stays temporary. The real Claude binary is also bound at
`~/.local/bin/claude` for its native-install checks.

`~/.local/bin` is appended to PATH, after system directories. A binary planted
there cannot take precedence over a system command or the agent wrapper.

## gitconfig defence-in-depth

The wrapper sets `GIT_CONFIG_GLOBAL=/etc/claude-gitconfig` and
`GIT_CONFIG_SYSTEM=/dev/null`. The curated config supplies Git identity,
HTTPS rewrites and forge credential helpers.

The outer `/etc/gitconfig` remains readable. Tools such as pre-commit that
scrub `GIT_*` variables can still use it; masking it broke those tools.
The user's home gitconfig remains hidden by the home mask.

## Network-identity disclosure

With the jail enabled, `pasta` mirrors the outer address, gateway and DNS
resolvers into a private namespace. Those addresses remain visible, but the
outer container's complete interface and routing view does not.

Disabling the jail gives the agent the outer container's network view and
reach, including local services. Configured loopback relays and `allow-ip`
exceptions also grant service access while the jail is enabled.

## The procfs view

All agents use `--unshare-pid`. Non-GPU sessions retain the read-only outer
`/proc`; its process IDs differ from sandbox-local IDs. Verification check 07
uses the `NSpid` nesting information for this mode.

GPU mode mounts fresh procfs with `--proc /proc`, so process and thread IDs
match CUDA's `/proc/self/task/<tid>/comm` lookups. Bubblewrap protects kernel
controls; the wrapper restores the runtime's sensitive proc masks and drops
capabilities. Rootless Podman must permit the initial mount with
`--security-opt 'unmask=/proc/*'`, supplied by the host launcher only with
`--gpu`. Failure to mount fresh procfs stops launch.

In GPU mode, check 07 compares PID namespace identities and checks local
process/thread entries and protected kernel controls. For a live test, run
`bash tests/proc_isolation.sh` in the outer container from a checkout with
`bwrap` and `gdb` installed. It checks that a disposable outer process is
invisible and inaccessible to signals and debugger attachment. Add `--cuda`
to compile and run the GPU smoke test.

## Egress-jail mechanism: holder netns + pasta-attach

The wrapper creates an `unshare -rn` holder with a new user and network
namespace. `pasta` attaches from outside, where it has internet access. The
holder brings up loopback and locks the routing rules before starting
bubblewrap, which inherits that network namespace.

The routes block private, CGNAT, connected and link-local networks, with
exceptions for the gateway, DNS and `allow-ip` destinations. The ordering is
essential: create namespace, attach pasta, restrict routes, then launch agent.

The network namespace belongs to an ancestor user namespace, so sandboxed
processes cannot change its routes. Bubblewrap drops effective capabilities
(`CapEff=0`), although the nested namespace can retain a full capability
bounding set. Checks 19–20 inspect the routes and representative destinations;
they report a disabled jail as a pass with a note.

The private namespace has no LAN broadcast. EPICS clients need a unicast
`EPICS_CA_ADDR_LIST` and corresponding `allow-ip` entries. Ordinary container
shells retain their existing networking. See
[network configuration](../how-to/network-egress-jail.md) and
{ref}`adr-network-egress-jail`.
