# Roll out the sandbox across an organisation

Provide a pinned container image or a team devcontainer configuration so
users start agents through the sandbox wrapper. See
[Sandbox a team devcontainer](sandbox-a-team-devcontainer.md).

## Keep the deployment predictable

- Pin the package or image version and review upgrades before rolling them out.
- Supply the required `/dev/net/tun` device and unprivileged user namespaces.
- Place site configuration in `/etc/claude-sandbox.conf`, outside the writable
  workspace. Review each extra writable path and network exception.
- Use project-scoped forge credentials and keep host credentials outside the
  project directory.
- Run [verification](verify-the-sandbox.md) on each supported host setup.

## Enforcement limits

The wrapper isolates processes that it launches. It does not prevent a
machine's owner from running an agent directly outside the wrapper. This
project installs no managed prompt or session hooks; any separate workstation
policy belongs to the organisation.

Read the [threat model](../explanations/threat-model.md) for the supported
boundary and [launch isolation](../explanations/launch-isolation.md) for the
wrapper and updater controls.
