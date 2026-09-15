#!/bin/sh
# Run as root in the OUTER container. Installs optional Playwright tooling,
# Chromium, OS libraries and Xvfb; does not modify the project's dependencies.
# Shipped path: /usr/libexec/claude-sandbox/skills/browser-testing/scripts/
set -eu

if [ "${IS_SANDBOX:-}" = 1 ]; then
    echo 'Run this installer outside the sandbox, in claude-sandbox shell.' >&2
    exit 1
fi
if [ "$(id -u)" != 0 ]; then
    echo 'Run this installer as root in the container.' >&2
    exit 1
fi
for tool in node npm apt-get; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool; install it in the outer container first." >&2
        exit 1
    fi
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 20) process.exit(1)' || {
    echo 'Playwright requires Node.js 20 or newer.' >&2
    exit 1
}

# An explicit version can match a project's Playwright without changing it.
version=${1:-1.63.0}
if [ "$#" -gt 1 ] || ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo 'Usage: install-browser-deps.sh [exact-playwright-version]' >&2
    exit 2
fi
prefix=/opt/claude-sandbox-browser
export DEBIAN_FRONTEND=noninteractive
export PLAYWRIGHT_BROWSERS_PATH=/cache/ms-playwright
# Keep browser revisions used by other projects sharing the cache.
export PLAYWRIGHT_SKIP_BROWSER_GC=1
mkdir -p "$prefix" "$PLAYWRIGHT_BROWSERS_PATH"
npm install --prefix "$prefix" --ignore-scripts --no-audit --no-fund \
    --save-exact "playwright@$version"
node "$prefix/node_modules/playwright/cli.js" install --with-deps chromium
# xvfb-run needs xauth; some minimal containers omit it.
apt-get install -y --no-install-recommends xvfb xauth
# Resolve the browser through the installed Playwright version each time so
# the launcher follows version changes without hard-coding a cache revision.
cat > /usr/local/bin/chromium <<'SHIM'
#!/bin/sh
set -eu
export PLAYWRIGHT_BROWSERS_PATH=/cache/ms-playwright
binary=$(node -e 'process.stdout.write(require("/opt/claude-sandbox-browser/node_modules/playwright").chromium.executablePath())')
exec "$binary" --no-sandbox --disable-dev-shm-usage \
    --user-data-dir=/cache/chromium-home "$@"
SHIM
chmod 755 /usr/local/bin/chromium
printf 'Installed Playwright %s at %s; browsers at %s\n' \
    "$version" "$prefix" "$PLAYWRIGHT_BROWSERS_PATH"
echo "Run 'chromium' in the outer container to open a browser; its profile lives in /cache/chromium-home."
echo 'Run the browser-testing smoke script inside the sandbox next.'
