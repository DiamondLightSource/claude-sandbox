(adr-no-native-host-mode)=

# 30. No native host mode: the sandbox always runs in a container

Date: 2026-11-24

## Status

Accepted. Extends {ref}`ADR 23 <adr-pypi-front-door>`.

## Context

The sandbox has two deployment models, and both put the jail inside a
container. One is the published image, started by the host launcher
({ref}`ADR 23 <adr-pypi-front-door>`). The other is an install into a
project's own devcontainer. They differ very little: the same installer
writes the same root-owned trust anchor, which is the pinned interpreter
under `/usr/libexec/claude-sandbox`, the shadow on `PATH` and the managed
settings under `/etc` ({ref}`ADR 13 <adr-managed-settings-guard>`,
{ref}`ADR 26 <adr-python-implementation>`). The jail inside is the same in
both.

The sandbox is now required for all developers, and some of them do not use
devcontainers. Projects that build container images themselves feel the
constraints most. That raised the question of a third model: running the
jail natively on the host with no container at all.

The jail itself does not need a container:

- bwrap needs only unprivileged user namespaces
  ({ref}`ADR 4 <adr-bwrap-isolation>`).
- The network egress jail was designed around unprivileged building blocks
  (`unshare -rn` plus pasta), because rootless podman gives no
  `CAP_NET_ADMIN` ({ref}`ADR 15 <adr-network-egress-jail>`).

In principle bwrap could also take over what the container provides, as
Flatpak does:

- an explicit list of the host paths the agent can see, in place of the
  read-only `/`;
- per-project credential directories bound over `~/.config/gh`;
- the conf and managed settings bound read-only over `/etc`, which removes
  the need for root ownership;
- a seccomp filter passed with `--seccomp`.

Doing that means rebuilding the container's role inside the jail:

- **Visibility policy.** On a host, `/` holds every project under `/scratch`,
  `/home` and `/dls` that the user can read. Today the jail binds back
  `~/.config/gh`, `~/.config/glab-cli`, `~/.cache` and `~/.local/share`
  read-write. Inside a container those hold throwaway, per-container tokens
  ({ref}`ADR 6 <adr-container-scoped-credentials>`). On a host they are the
  user's real tokens and keyrings. A native mode needs its own policy for
  which paths are visible and where per-project state lives, and that policy
  is security-critical.
- **seccomp.** Podman applies a default filter. bwrap applies only one we
  supply, so we would ship and maintain our own.
- **Supply chain.** The installer supports apt only. RHEL 8 hosts need a
  dnf path and builds of passt and a current bwrap that we would ship
  ourselves.
- **Persistence.** A session's leftovers would sit in the user's real home
  rather than a container that can be recreated. That widens the problem in
  {ref}`ADR 28 <adr-review-what-a-session-leaves>`.
- **Audit core.** The visibility policy, per-project state and seccomp would
  all land in `bwrap.py`, which must stay small and readable top to bottom.
  Today rootless podman carries that complexity, outside the code we audit.

## Decision

The sandbox runs only in a container: the published image, or a
devcontainer install. We do not add a native host mode.

A native mode would be a third deployment model and the one least like the
other two. It would have its own trust anchor, visibility policy, seccomp
policy and binary supply chain. Every security change would need checking
against it separately. The two container models share one code path, and
keeping that is worth more than removing the container for some users.

The existing refusal of `install` outside a container
({ref}`ADR 23 <adr-pypi-front-door>`) is the enforcement.
`CLAUDE_SANDBOX_HOST_INSTALL=1` stays as an override for hermetic CI and
tests. It is not a supported deployment, and the docs do not advertise it.

Developers who find the container model limiting are served by fixing those
limits in the container, one at a time:

- building and running containers from inside the project container (issue #125);
- host tooling such as `/dls_sw` and environment modules, through mounts and
  image contents;
- documentation for developers who do not normally work in containers.

## Consequences

- One trust anchor and one jail, in two packaging variants. Security review
  stays focused on `bwrap.py`, `jail.py` and `shadow.py`.
- Developers without devcontainers must use the published image and accept
  its constraints. They lose packages installed in the container on
  `--recreate` and must log in to forges per project.
- Projects that build container images are blocked until nested builds work
  in the project container. That work is tracked separately and has its own
  threat-model questions.
- Host-specific checks need not handle a bare host. For example, the
  automount refusal does not exempt systemd's `binfmt_misc` autofs, which
  exists only on hosts.
- Revisit this decision if container limits that cannot be fixed keep a
  significant group of developers off the sandbox.
