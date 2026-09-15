---
name: browser-testing
description: Set up and use Playwright with Chromium to test web interfaces inside claude-sandbox, including screenshots, traces and optional headed tests on Xvfb. Use for browser-based UI verification or missing browser dependencies; native desktop apps use vscode-headless instead.
---

# Browser testing

Run the app server and browser inside the same agent sandbox. Use Playwright
directly, with headless Chromium by default. Do not connect to the user's
desktop browser, reuse host profiles or expose a browser debugging port outside
the sandbox. Browser processes retain the agent sandbox's filesystem and
network restrictions; Chromium's nested sandbox is disabled for this setup.

## Setup

First inspect the project's test commands and installed Playwright version.
Use existing tests and dependencies when present. Do not replace a project's
Playwright with the standalone installation or change its lockfile for setup.

The optional installer installs a pinned standalone Playwright package under
`/opt/claude-sandbox-browser`, matching Chromium builds under
`/cache/ms-playwright`, OS libraries, Xvfb and xauth. It leaves project files
alone. The package and OS dependencies last until container recreation;
browser downloads persist in `/cache`. It can be rerun after recreation.

The installer also writes `/usr/local/bin/chromium` for the user's manual
testing in the outer container. It launches the matching Playwright Chromium
with the flags needed as root and a persistent profile at `/cache/chromium-home`.
The user can run `chromium` or `chromium https://example.com` in a terminal
with a working display. Agent tests use Playwright's fresh contexts instead
of this manual-testing profile.

If setup is missing, ask the user to run the installed script as root in the
outer container (`claude-sandbox shell` or a devcontainer terminal):

```sh
sh /usr/libexec/claude-sandbox/skills/browser-testing/scripts/install-browser-deps.sh
```

Explain those changes before asking. Do not run the installer in the jail or
copy the shipped script into a writable location. For development before the
skill is installed, give its absolute path in the shared checkout instead.
No agent restart is needed to see the installed package and system libraries.

The default is Playwright 1.63.0. To match a project's version, pass that exact
version as the script's sole argument. For example, if the project uses
1.63.0, append `1.63.0`. Each Playwright release requires matching browser
builds; do not override `executablePath` to borrow an incompatible Chromium.
See [Playwright browser installation](https://playwright.dev/docs/browsers).

## Verify the installation

Inside the sandbox, run the bundled smoke script, giving an output directory
under the workspace:

```sh
node /usr/libexec/claude-sandbox/skills/browser-testing/scripts/smoke.cjs ./browser-smoke
```

It loads a loopback page, clicks a button, checks the result and browser errors,
then saves `page.png` and `trace.zip`. Inspect the screenshot before claiming
visual verification. These artifacts are test output; do not commit them.

For a headed browser on a private virtual display:

```sh
BROWSER_HEADED=1 xvfb-run -a node /usr/libexec/claude-sandbox/skills/browser-testing/scripts/smoke.cjs ./browser-smoke-headed
```

## Test the actual app

For project tests, set the browser cache explicitly in the agent shell (the
outer shell's environment is scrubbed), then run the project's normal command:

```sh
export PLAYWRIGHT_BROWSERS_PATH=/cache/ms-playwright
```

Use `chromiumSandbox: false` in launch options for this jail if the project
enables Chromium's nested sandbox. Keep other project options intact.
Headed tests can run under `xvfb-run -a`.

For ad hoc Node scripts when the project has no Playwright, import
`/opt/claude-sandbox-browser/node_modules/playwright` explicitly and set the
same browser-cache variable. Use fresh browser contexts and close browsers
and app servers when finished. Prefer role/label locators and Playwright's
waiting facilities to fixed sleeps.

Exercise the requested user flow, check console errors and failed requests,
and save screenshots and traces under the workspace. Distinguish assertions
that passed from appearance you actually inspected. A passing installer or
smoke test is not evidence that the app itself works.

If a browser revision or library is missing, report the error and the exact
setup command needed. Keep the existing filesystem/network isolation; do not
work around missing dependencies by unpacking OS packages inside the jail.
