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

## Step 1: ask the user to run the install script

Always start here. Do not probe for Xvfb, VS Code or the Electron libraries
first, and do not try to work around a missing one: a partial check is
misleading (the container is recreated without warning and keeps only
`/cache`), and any package fetched or unpacked by the agent bypasses the
review the user gets from running the script themselves. If the install is
already done, the script confirms that in a few seconds and changes nothing,
so asking costs the user almost nothing. The `claude-sandbox-user` skill
describes the outer container and how the user reaches it.

Ask the user to run
[scripts/install-vscode-driver-deps.sh](scripts/install-vscode-driver-deps.sh)
outside the sandbox, in `claude-sandbox shell` or a devcontainer terminal. The
sandbox root is read-only and nested namespaces are refused, so `apt-get
install` fails inside it. The sandbox sees the packages immediately without a
restart. They persist until the container is recreated. VS Code lands on
`/cache`, which survives recreation. The script also writes a `code` shim to
`/usr/local/bin` that adds the arguments root needs and keeps settings on
`/cache/vscode-home`, so `code` works in an outer-container terminal for the
user's own testing. The sandbox launcher does not use it.

For the shipped skill, give the user the installed path below. It exists
in the outer container and is read-only inside the sandbox. The agent's
`~/.claude/skills` (or equivalent) mount exists only inside the jail;
the installed source is available on both sides. No copy is needed:

```sh
sh /usr/libexec/claude-sandbox/skills/vscode-headless/scripts/install-vscode-driver-deps.sh
```

Say what the script does before asking. It runs unsandboxed as root, so the
user must read it first. Do not extend it beyond package installs.

The package list also covers the X11 client libraries a Qt application
needs to open a window on the Xvfb display (`libxcb-icccm4`, `libxcb-xkb1`,
`libxkbcommon-x11-0` and friends). Without them PyQt exits with
`Could not load the Qt platform plugin "xcb"`, which shows up as an
exception pause at the first Qt import instead of at your breakpoint.

Other toolkits (Tk, GTK via PyGObject, SDL, wxPython's HTML widget) need
their own packages; the traceback names the missing library. Fetch it with
the fallback below rather than growing the install script.

## Step 2: quick start

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

### Missing libraries the user cannot install right now

Only with the user's explicit go-ahead, and only for a library outside the
install script's list. Never use this route to stand in for the install
script itself: unpacking Xvfb or the Electron stack this way works, but it
is fragile (archive versions drift) and hides from the user what is running.

`apt-get download` also fails in the jail (it drops privileges with
`setgroups`), but plain HTTP works. Fetch the `.deb` files with `curl` and
unpack them under `/cache`, then point the program at them:

```sh
mkdir -p /cache/xlibs/debs && cd /cache/xlibs/debs
apt-get download --print-uris libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 \
    libxcb-util1 | awk '{gsub(/\x27/,"",$1); print $1}' | xargs -n1 curl -sfLO
for d in *.deb; do dpkg-deb -x "$d" /cache/xlibs/root; done
export LD_LIBRARY_PATH=/cache/xlibs/root/usr/lib/x86_64-linux-gnu
```

A program VS Code launches under the debugger does not inherit that export.
The Python debugger reads `${workspaceFolder}/.env` by default, so put the
`LD_LIBRARY_PATH` line there and leave the tracked `launch.json` alone; tell
the user the file is untracked and why. `DISPLAY` is already inherited from
the launcher.

## Driving VS Code

- Wait for a window before sending input: poll `windows` until one entry
  appears, then allow a few seconds for the workbench.
- `snapshot` returns visible text and controls. Use it to confirm state instead
  of a screenshot when text is enough.
- `key`, `text`, `click` and `eval` act on the focused window. Open the command
  palette with `key Ctrl+Shift+p`, type the command with `text`, then `key Enter`.
- Screenshots and other files must land in the workspace. The sandbox `/tmp`
  is a private tmpfs that nothing outside can read.
- `screenshot` captures the VS Code window only. For a window the debuggee
  opened, find it with `xdotool search --name '<title>'` on the same
  `DISPLAY`, raise it with `xdotool windowraise`, and grab it with the
  application's own toolkit (for Qt, `QApplication.primaryScreen()
  .grabWindow(<id>).save(...)` from a second process). `xwininfo -root
  -tree` lists what is on the display.
- The agent may be unable to open a PNG it just wrote (an image reader
  outside the jail does not see it). Confirm state from `snapshot` text such
  as `paused, reason breakpoint, file.py:48`, and treat the file as the
  deliverable for the user.
- After a debug run ends, `snapshot` still shows the old Call Stack text
  (`paused, reason exception`). Check for a live debuggee with `pgrep`
  before trusting it, and read the failure from the Python Debug Console
  section of the snapshot.
- A shell that is not bash (zsh) does not word-split `U="node driver.mjs";
  $U windows`. Define a function instead: `u(){ node .../vscode-ui.mjs
  "$@"; }`.
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
