---
name: vscode-headless
description: >-
  Run VS Code on a virtual display inside the agent sandbox and drive it
  through the DevTools port with the bundled vscode-ui.mjs driver. Use when a
  task needs VS Code started, inspected, screenshotted or driven from inside
  the sandbox, when a tool wants a `code` binary path, or when the sandbox
  lacks Xvfb or VS Code. Also surface when anyone proposes binding the host
  display, X11 socket or session D-Bus into the sandbox to reach VS Code.
---

# vscode-headless

VS Code runs inside the sandbox on an Xvfb display. Never start VS Code on the
host desktop from the sandbox, never connect the driver to a host VS Code, and
never ask for the display or session bus to be bound in. The DevTools port
hands over everything that VS Code process can do, and a host process runs
with the user's full session. Inside the sandbox the process is already
confined, so the port grants nothing the agent does not already have. The
shadow masks `/tmp/.X11-unix`, `/run/user` and `~/.Xauthority` on purpose.

Scripts live in this skill's `scripts/` directory. Call them by absolute path
from there, or copy them into a project.

## Quick start

```sh
scripts/vscode-headless /path/to/workspace &
node scripts/vscode-ui.mjs windows
node scripts/vscode-ui.mjs screenshot ./ide.png
```

`vscode-headless` starts Xvfb on `:99` when no display answers, then starts VS
Code from `/cache/vscode` with a private data directory under
`/tmp/vscode-headless` and DevTools on `127.0.0.1:9222`. A second call reuses
both the display and the running VS Code, so it also serves as the `code`
binary for any tool that takes one.

Environment overrides: `VSCODE_HEADLESS_BINARY`, `VSCODE_HEADLESS_DISPLAY`,
`VSCODE_HEADLESS_PORT`, `VSCODE_HEADLESS_DATA`, and for the driver
`VSCODE_HEADLESS_WINDOW`.

## When the sandbox lacks Xvfb or VS Code

The sandbox root is read-only and nested namespaces are refused, so `apt-get
install` fails inside it. Ask the user to run
[scripts/install-vscode-driver-deps.sh](scripts/install-vscode-driver-deps.sh)
outside the sandbox, in `claude-sandbox shell` or a devcontainer terminal. The
sandbox sees the packages immediately without a restart. They persist until the
container is recreated. VS Code lands on `/cache`, which survives recreation.
The script also writes a `code` shim to `/usr/local/bin` that adds the
arguments root needs and keeps settings on `/cache/vscode-home`, so `code`
works in an outer-container terminal. The sandbox launcher does not use it.

Say what the script does before asking. It runs unsandboxed as root, so the
user must read it first. Do not extend it beyond package installs.

## Driving VS Code

- Wait for a window before sending input: poll `windows` until one entry
  appears, then allow a few seconds for the workbench.
- `snapshot` returns visible text and controls. Use it to confirm state instead
  of a screenshot when text is enough.
- `key`, `text`, `click` and `eval` act on the focused window. Open the command
  palette with `key Ctrl+Shift+p`, type the command with `text`, then `key Enter`.
- Screenshots and other files must land in the workspace. The sandbox `/tmp`
  is a private tmpfs that nothing outside can read.
- Stop VS Code with the DevTools call `Browser.close` through `eval` or a short
  Node script when `kill` does not reach the process.
- On a fresh profile the chat box may hold focus, so focus or create a terminal
  through the command palette before typing, and use output-only markers,
  because the typed command is also visible in `snapshot`.

## Driving a Remote-SSH connection

A tool that opens a remote workspace, such as `podbench ide vscode`, adds two
wrinkles the driver must handle:

- Two windows appear: a short-lived bootstrap window and the workspace window.
  Select the workspace window by title, not the first `windows` entry.
- The workspace title gains its `[SSH: ...]` suffix a few seconds after the
  tool reports the connection is ready. Wait for the suffix before sending
  input, or a command runs against a local, disconnected window.
- Give each connection its own `--user-data-dir` and port, so a stale window
  from an earlier target cannot capture the new workspace.

## Checks that prove the setup is sound

- A terminal opened inside VS Code prints `IS_SANDBOX=1`, and
  `touch /usr/bin/probe` fails with a read-only error.
- `ss -ltn` shows port 9222 only on `127.0.0.1` in the sandbox network.
