# Test a web app with browser automation

The shipped `browser-testing` skill lets Claude, Codex and Pi test your UI
with Playwright and Chromium, including screenshots and performance checks.

## Install

Open `claude-sandbox shell` from your project on the host, or use a
devcontainer terminal. Review and run this script there as root,
**outside the agent sandbox**:

```bash
sh /usr/libexec/claude-sandbox/skills/browser-testing/scripts/install-browser-deps.sh
```

It installs Playwright, Chromium and system dependencies without changing
project dependencies. Requires Node.js 20+ and npm. Rerun after container
recreation; no agent restart is needed for the installed tools.

## Ask the agent

This prompt worked well:

> This project is designed to run in Kubernetes as a web app that talks to
> Argo CD. Can you stub out backends and use browser automation to test the
> performance of its UI?

That example also used a service-account kubeconfig accessible to the agent
and an `allow-ip` entry for the Kubernetes API IP in the
[sandbox network configuration](network-egress-jail.md). Start a fresh agent
session after changing the allowlist, then give it the kubeconfig path,
context and namespace. Keep the kubeconfig out of commits. Local tests using
only stubs need no cluster access.

The agent's skill handles browser setup checks and running the app and tests.
Ask for screenshots, timings and a repeatable test command; stubbed timings
measure the local UI, not production backend performance.
