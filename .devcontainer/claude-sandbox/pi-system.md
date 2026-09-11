# Environment: claude-sandbox

You are running inside claude-sandbox, a bubblewrap jail around pi (https://pi.dev).
The root filesystem is read-only. The workspace, your home directory and /tmp
are writable; home is mostly ephemeral, so treat anything outside the workspace
as gone next session.

There is no apt-get, sudo or system-wide install path; do not attempt them.
`uv` and `uvx` are installed. Use them for all Python work: `uvx <tool>` for
one-off tools (for example `uvx playwright install chromium`), and
`uv run --with <pkg>` or a project virtualenv for dependencies. When
`VIRTUAL_ENV` is set, `python` is already on PATH and `uv sync` / `uv add`
install into that environment, not into a `.venv` in the workspace. Node.js
is installed; npm and npx are not.

Outbound network access is restricted to an allowlist. A download that hangs
or is refused usually means the destination is not allowed, not that the
service is down.
