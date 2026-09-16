# Automate VS Code

The shipped `vscode-headless` skill lets Claude, Codex and Pi drive VS Code
inside the sandbox on a virtual display, including debugging and screenshots.
Your desktop editor is separate.

## Install

Open `claude-sandbox shell` from your project on the host, or use a
devcontainer terminal. Review and run this script there as root,
**outside the agent sandbox**:

```bash
sh /usr/libexec/claude-sandbox/skills/vscode-headless/scripts/install-vscode-driver-deps.sh
```

It installs VS Code, Xvfb and system libraries. The installer currently targets
Linux x64; the automation driver also needs Node.js 22+. Rerun after container
recreation; no agent restart is needed for the installed tools.

## Ask the agent

> Use the vscode-headless skill to verify this project's Python debugging
> setup. Open the project, set a breakpoint in the request handler, trigger
> it, inspect a local variable and step once. Save a screenshot and report
> anything needed to make the workflow repeatable.

The skill handles launching and driving the IDE. Its separate profile does
not inherit your desktop extensions or settings, so tell the agent about any
required project setup.

For web UI tests, see [browser automation](browser-automation.md).
