#!/bin/sh
# Install what vscode-headless (this directory) needs to run VS Code inside the agent
# sandbox: Xvfb, the Electron libraries, the X11 client libraries a Qt (PyQt)
# debuggee needs to open a window on that display, and a VS Code tarball.
#
# Run this OUTSIDE the sandbox, as root in the container: `claude-sandbox
# shell` or a plain devcontainer terminal. The sandbox binds the container
# root read-only, so it sees the packages at once, and they last until the
# container is recreated. VS Code itself goes on the /cache volume, which
# survives recreation.
#
# The agent should have copied this file to /cache or the workspace before
# naming it: its own skills directory is a bind that exists only in the jail.
#
# Review before running: this script runs unsandboxed as root.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    xvfb x11-utils xdotool \
    libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libgtk-3-0t64 \
    libgbm1 libasound2t64 libxkbfile1 libsecret-1-0 libxss1 libxcomposite1 \
    libxdamage1 libxrandr2 libxshmfence1 libx11-xcb1 libdbus-1-3 libxkbcommon0 \
    fonts-dejavu-core \
    libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
    libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libxcb-util1 libxcb-cursor0 \
    libegl1 libopengl0

prefix=${VSCODE_PREFIX:-/cache/vscode}
if [ ! -x "$prefix/bin/code" ]; then
    mkdir -p "$prefix"
    curl -sL https://update.code.visualstudio.com/latest/linux-x64/stable \
        | tar xz -C "$prefix" --strip-components=1 --no-same-owner
fi
# `code` on the PATH runs the tarball with the arguments root needs, and keeps
# settings and extensions on /cache so they survive container recreation.
home=${VSCODE_HOME:-/cache/vscode-home}
mkdir -p "$home/data" "$home/extensions"
cat > /usr/local/bin/code <<SHIM
#!/bin/sh
# Shim written by install-vscode-driver-deps.sh; edit that script, not this.
exec "$prefix/bin/code" --no-sandbox \\
    --user-data-dir "$home/data" --extensions-dir "$home/extensions" "\$@"
SHIM
chmod 755 /usr/local/bin/code
echo "done: 'code' opens VS Code from $prefix with state in $home;"
echo "      in the sandbox use vscode-headless instead"
