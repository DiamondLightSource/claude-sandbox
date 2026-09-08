# Shared project guidance

Read and follow `CLAUDE.md` in this directory before working in this repository.
It is the single source of project instructions for Claude Code and Codex.

Codex discovers the shared skills through `.agents/skills`, a relative symlink
to `.claude/skills`. Read the relevant `SKILL.md` and resolve its supporting
files relative to that skill directory. Add and edit skills under `.claude/skills`;
preserve the symlink so new skills become available to both agents.

For a requested workspace command, read `.claude/commands/<name>.md` and
execute its instructions. The `claude-command` skill provides this adapter;
for example, `$claude-command verify-sandbox`. A request such as "run the
verify-sandbox command" works too. Do not assume Claude's slash-command menu,
hooks, settings, tool names, or private auto-memory are available in Codex.
Use equivalent available tools, and report any missing capability that prevents
completion. Preserve shell variables in code snippets; command arguments are
task inputs, not permission to substitute every `$1` in shell or awk code.
