# claude-sandbox

Sandboxed Claude Code, Codex and Pi. A bubblewrap jail hides host
credentials, an egress allowlist stops lateral movement, and a managed
integrity guard refuses to run an agent outside the jail.

This wheel is a front door only. It ships the project's bash launcher and
installer unchanged and execs them. The security-critical code is bash and
lives at <https://github.com/DiamondLightSource/claude-sandbox>.

```bash
cd ~/src/my-project
uvx claude-sandbox            # sandboxed claude in a per-project container
uvx claude-sandbox pi         # or codex; shell for an unsandboxed bash
uvx claude-sandbox install    # inside a devcontainer, as root: install the sandbox
```

The wheel version pins the container image it launches. Documentation:
<https://diamondlightsource.github.io/claude-sandbox/>.
